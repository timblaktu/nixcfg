import sys
import argparse
import pathlib
import re
from multiprocessing import Pool, Manager, cpu_count
from functools import partial
import pymupdf
import pymupdf4llm


def sanitize_filename(text):
    """Convert text to safe filename component"""
    # Remove/replace unsafe characters
    text = re.sub(r'[^\w\s-]', '', text.lower())
    text = re.sub(r'[-\s]+', '-', text)
    return text.strip('-')[:50]  # Limit length


def estimate_bytes_per_page(doc, sample_pages=3):
    """Estimate average bytes per page by sampling a few pages"""
    total_pages = len(doc)
    # Sample up to 3 pages evenly distributed through the document
    sample_indices = [
        0,  # First page
        total_pages // 2,  # Middle page
        total_pages - 1  # Last page
    ]
    # Only use valid indices
    sample_indices = [i for i in sample_indices
                      if 0 <= i < total_pages][:sample_pages]

    total_bytes = 0
    for idx in sample_indices:
        sample_text = pymupdf4llm.to_markdown(doc, pages=[idx])
        total_bytes += len(sample_text.encode('utf-8'))

    return total_bytes // len(sample_indices)


def split_large_chunk(toc_entry, max_size, bytes_per_page):
    """Split a TOC entry into smaller chunks if it exceeds max_size"""
    level, title, start_page, end_page = toc_entry
    pages = list(range(start_page, end_page))

    total_estimated = bytes_per_page * len(pages)

    if total_estimated <= max_size:
        return [toc_entry]

    # Split into smaller chunks
    chunks = []
    pages_per_chunk = max(1, int(max_size / bytes_per_page))

    for i in range(0, len(pages), pages_per_chunk):
        chunk_pages = pages[i:i + pages_per_chunk]
        chunk_title = f"{title} (Part {i//pages_per_chunk + 1})"
        chunks.append((level, chunk_title, chunk_pages[0],
                       chunk_pages[-1] + 1))

    return chunks


def build_toc_chunks(doc, max_chunk_size):
    """Build chunks from TOC with size limits"""
    toc = doc.get_toc()
    total_pages = len(doc)

    if not toc:
        # Fallback: use IdentifyHeaders for structure detection
        try:
            pymupdf4llm.IdentifyHeaders(doc)
            # Even without TOC, split by max_chunk_size
            return build_size_based_chunks(doc, total_pages, max_chunk_size)
        except Exception:
            return build_size_based_chunks(doc, total_pages, max_chunk_size)

    # Sample once to estimate bytes per page (avoid repeated conversions)
    bytes_per_page = estimate_bytes_per_page(doc)

    # Build hierarchical structure
    chunks = []
    for i, (level, title, page) in enumerate(toc):
        # Find next same-or-higher level entry
        next_page = total_pages
        for j in range(i + 1, len(toc)):
            if toc[j][0] <= level:
                next_page = toc[j][2] - 1  # Page before next section
                break

        entry = (level, title, page - 1, next_page)  # Convert to 0-indexed

        # Split if too large
        split_chunks = split_large_chunk(entry, max_chunk_size,
                                         bytes_per_page)
        chunks.extend(split_chunks)

    return chunks


def build_size_based_chunks(doc, total_pages, max_chunk_size):
    """Fallback: split by size when no TOC available"""
    sample_text = pymupdf4llm.to_markdown(doc, pages=[0])
    bytes_per_page = len(sample_text.encode('utf-8'))
    pages_per_chunk = max(1, int(max_chunk_size / bytes_per_page))

    chunks = []
    for i in range(0, total_pages, pages_per_chunk):
        end = min(i + pages_per_chunk, total_pages)
        title = f"Section {i//pages_per_chunk + 1}"
        chunks.append((1, title, i, end))

    return chunks


def cleanup_markdown(text, fix_lists=True, fix_headers=True):
    """Clean up common markdown formatting issues from PDF conversion"""
    import re

    # Remove excessive dot leaders (TOC artifact)
    # Match patterns like ". . . . . . . ." with 3+ dot sequences
    text = re.sub(r'(\s*\.\s+){3,}', ' ', text)

    # Fix orphaned list items (numbered lists)
    if fix_lists:
        # Pattern 1: Orphan numbers (e.g., "1.\n") - merge with following
        text = re.sub(
            r'^(\s*)(\d+\.)\s*\n+(.+)$', r'\1\2 \3',
            text, flags=re.MULTILINE)

        # Pattern 2: Bullet points that got separated
        bullets = r'[•◦▪▸▹►◆◇○●■□▶▷]'
        text = re.sub(
            rf'^(\s*)({bullets})\s*\n+(.+)$', r'\1\2 \3',
            text, flags=re.MULTILINE)

        # Pattern 3: Hyphen/asterisk bullets
        text = re.sub(
            r'^(\s*)([-*])\s*\n+([^\n-*].+)$', r'\1\2 \3',
            text, flags=re.MULTILINE)

        # Fix multi-level lists (e.g., "a.", "i.", etc.)
        text = re.sub(
            r'^(\s*)([a-z]\.)\s*\n+(.+)$', r'\1\2 \3',
            text, flags=re.MULTILINE | re.IGNORECASE)
        text = re.sub(
            r'^(\s*)([ivxIVX]+\.)\s*\n+(.+)$', r'\1\2 \3',
            text, flags=re.MULTILINE)

    # Fix headers that weren't detected (lines that look like headers)
    if fix_headers:
        # Pattern: Short lines (< 60 chars) in Title Case or ALL CAPS
        lines = text.split('\n')
        for i, line in enumerate(lines):
            stripped = line.strip()
            is_candidate = (
                stripped and len(stripped) < 60 and
                not stripped.startswith('#') and
                not re.match(r'^\d+\.', stripped)
            )
            if not is_candidate:
                continue

            # Check if it looks like a header (Title Case)
            words = stripped.split()
            if len(words) <= 8:  # Headers are usually short
                cap_words = sum(1 for w in words if w and w[0].isupper())
                # 60% or more capitalized words
                if cap_words >= len(words) * 0.6:
                    # Check context: followed by paragraph/blank
                    next_line = lines[i + 1] if i + 1 < len(lines) else ""
                    next_is_longer = len(next_line) > len(stripped)
                    if not next_line.strip() or next_is_longer:
                        lines[i] = f"## {stripped}"
                elif stripped.isupper() and len(stripped) > 3:
                    # ALL CAPS headers
                    lines[i] = f"## {stripped.title()}"

        text = '\n'.join(lines)

    # Collapse excessive blank lines (3+ → 2)
    text = re.sub(r'\n{3,}', '\n\n', text)

    # Clean up standalone page numbers that aren't part of content
    # More sophisticated: only remove if truly standalone (not part of lists)
    text = re.sub(r'^(?!\s*\d+\.)\s*\d{1,4}\s*$', '', text, flags=re.MULTILINE)

    # Remove trailing whitespace from lines
    text = re.sub(r'[ \t]+$', '', text, flags=re.MULTILINE)

    # Fix broken paragraphs: merge lines that should be continuous
    # (no punctuation at end + next line starts lowercase)
    lines = text.split('\n')
    merged_lines = []
    list_pattern = r'^\s*[\d•◦▪▸▹►◆◇○●■□▶▷\-*]'
    end_punct = ('.', '!', '?', ':', ';', '"', "'")
    i = 0
    while i < len(lines):
        line = lines[i]
        has_next = i + 1 < len(lines)
        next_line = lines[i + 1] if has_next else ""
        should_merge = (
            has_next and line and
            not line.startswith('#') and
            not re.match(list_pattern, line) and
            not line.rstrip().endswith(end_punct) and
            next_line and next_line[0].islower()
        )
        if should_merge:
            merged_lines.append(line + ' ' + next_line)
            i += 2
        else:
            merged_lines.append(line)
            i += 1

    text = '\n'.join(merged_lines)

    return text


def process_chunk(chunk_info, input_path, output_dir, kwargs, progress_dict,
                  lock):
    """Process a single chunk in parallel"""
    level, title, start_page, end_page = chunk_info
    chunk_id = f"{start_page:04d}"
    safe_title = sanitize_filename(title)

    # Open document (each worker gets its own handle)
    doc = pymupdf.open(input_path)

    # Set up header detection based on strategy
    header_strategy = progress_dict.get('header_strategy', 'both')
    hdr_info = None

    if header_strategy in ('toc', 'both'):
        # Try TOC-based header detection first
        try:
            hdr_info = pymupdf4llm.TocHeaders(doc)
        except Exception:
            if header_strategy == 'toc':
                # TOC-only mode failed, no headers
                hdr_info = False

    if header_strategy in ('font', 'both') and hdr_info is None:
        # Use font-based header detection
        try:
            body_limit = progress_dict.get('body_limit', 11)
            max_levels = progress_dict.get('max_header_levels', 4)
            # Analyze first few pages for font sizes
            sample_pages = list(range(min(3, end_page - start_page)))
            hdr_info = pymupdf4llm.IdentifyHeaders(
                doc,
                pages=[start_page + p for p in sample_pages],
                body_limit=body_limit,
                max_levels=max_levels
            )
        except Exception:
            # Fallback to no headers
            hdr_info = False

    if header_strategy == 'none':
        hdr_info = False

    # Update kwargs with header info
    kwargs_with_headers = {**kwargs}
    if hdr_info is not None:
        kwargs_with_headers['hdr_info'] = hdr_info

    # Process pages
    pages = list(range(start_page, end_page))
    md_text = pymupdf4llm.to_markdown(doc, pages=pages,
                                      **kwargs_with_headers)

    # Clean up markdown formatting issues (unless disabled)
    if not progress_dict.get('no_cleanup', False):
        fix_lists = progress_dict.get('fix_lists', True)
        do_fix_headers = (
            progress_dict.get('fix_headers', True) and
            header_strategy != 'none')
        md_text = cleanup_markdown(
            md_text, fix_lists=fix_lists, fix_headers=do_fix_headers)

    # Generate output filename
    base_name = pathlib.Path(input_path).stem
    output_file = output_dir / f"{base_name}-{chunk_id}-{safe_title}.md"

    # Write output
    output_file.write_bytes(md_text.encode('utf-8'))

    # Update progress
    with lock:
        progress_dict['chunks_done'] += 1
        done = progress_dict['chunks_done']
        total = progress_dict['total_chunks']
        pct = 100 * done / total
        print(f"[{pct:5.1f}%] Completed: {title} "
              f"(pages {start_page+1}-{end_page})")

    doc.close()

    return {
        'title': title,
        'file': output_file.name,
        'pages': (start_page + 1, end_page),
        'level': level
    }


def generate_index(results, output_dir, base_name):
    """Generate index.md with links to all chunks"""
    index_file = output_dir / f"{base_name}-index.md"

    with open(index_file, 'w') as f:
        f.write(f"# {base_name}\n\n")
        f.write("## Table of Contents\n\n")

        for result in sorted(results, key=lambda x: x['pages'][0]):
            indent = "  " * (result['level'] - 1)
            title = result['title']
            link = result['file']
            pages = f"(pages {result['pages'][0]}-{result['pages'][1]})"
            f.write(f"{indent}- [{title}](./{link}) {pages}\n")

    return index_file


def main():
    parser = argparse.ArgumentParser(
        prog='pdf2md',
        description='Parallel TOC-aware PDF to Markdown converter',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  pdf2md book.pdf                    # Auto-chunk by TOC, use all cores
  pdf2md book.pdf -o ./md/           # Specify output directory
  pdf2md book.pdf --max-chunk-size 2M --workers 8
  pdf2md book.pdf --header-strategy font --body-limit 12

Output:
  Creates directory: {input}-markdown/
  Files: {input}-{page:04d}-{chapter-title}.md
  Index: {input}-index.md (with cross-document links)

Chunking Strategy:
  1. Extract TOC → split by chapters/sections
  2. No TOC → font-based header detection (IdentifyHeaders)
  3. Fallback → equal page distribution
  Chunks exceeding --max-chunk-size are automatically split.

Header Detection:
  --header-strategy both     # Try TOC first, fallback to font-based (default)
  --header-strategy toc      # TOC metadata only
  --header-strategy font     # Font-size based detection
  --header-strategy none     # No header detection
  --body-limit 12            # Font size threshold for headers (default: 11pt)
  --max-header-levels 3      # Detect up to h3 (default: 4)

List & Format Fixes:
  --no-fix-lists             # Disable list reconstruction
  --no-fix-headers           # Disable header promotion
  List reconstruction merges orphan numbers/bullets with their content.
  Header promotion detects Title Case/ALL CAPS lines as headers.

Performance:
  --table-strategy none      # Skip tables for 2-3x speedup
  --ignore-graphics          # Skip vector graphics
  --ignore-images            # Text-only extraction

Quality:
  --margins 72               # Skip 1" top/bottom (headers/footers)
  --margins 0,72,0,72        # Same as above, explicit l,t,r,b format
  --no-cleanup               # Disable all cleanup features
""")

    parser.add_argument('input', metavar='PDF', help='input PDF file')
    parser.add_argument('-o', '--output', metavar='DIR',
                        help='output directory (default: {input}-markdown)')

    # Chunking
    chunk = parser.add_argument_group('chunking')
    chunk.add_argument('--max-chunk-size', metavar='SIZE', default='1M',
                       help='max chunk size: 1M, 500K, 2G (default: 1M)')
    chunk.add_argument('--workers', metavar='N', type=int,
                       default=cpu_count(),
                       help=f'parallel workers (default: {cpu_count()})')

    # Images
    img = parser.add_argument_group('images')
    img.add_argument('--embed-images', action='store_true',
                     help='embed as base64')
    img.add_argument('--write-images', action='store_true',
                     help='save to files')
    img.add_argument('--image-path', metavar='DIR', default='./images',
                     help='image directory')
    img.add_argument('--image-format', metavar='FMT', default='png',
                     help='png|jpg|webp')
    img.add_argument('--ignore-images', action='store_true',
                     help='skip all images')

    # Performance
    perf = parser.add_argument_group('performance')
    perf.add_argument('--ignore-graphics', action='store_true',
                      help='skip vector graphics')
    perf.add_argument('--table-strategy', metavar='STRAT',
                      choices=['lines_strict', 'lines', 'text', 'none'],
                      default='lines_strict',
                      help='table detection: lines_strict|lines|text|none')

    # Quality
    quality = parser.add_argument_group('quality')
    quality.add_argument('--margins', metavar='PTS', type=str,
                         default='0,36,0,36',
                         help='margins to ignore: N (top/bottom only) or '
                              'l,t,r,b (default: 0,36,0,36)')
    quality.add_argument('--no-cleanup', action='store_true',
                         help='skip cleanup (dots, whitespace)')
    quality.add_argument('--no-fix-lists', action='store_true',
                         help='disable list reconstruction')
    quality.add_argument('--no-fix-headers', action='store_true',
                         help='disable header promotion')

    # Header detection
    headers = parser.add_argument_group('header detection')
    headers.add_argument('--header-strategy', metavar='STRAT',
                         choices=['toc', 'font', 'both', 'none'],
                         default='both',
                         help='header detection: toc|font|both|none')
    headers.add_argument('--body-limit', metavar='PTS', type=int,
                         default=11,
                         help='font size threshold for headers (11pt)')
    headers.add_argument('--max-header-levels', metavar='N', type=int,
                         default=4,
                         help='max header levels to detect (default: 4)')

    args = parser.parse_args()

    # Parse margins parameter
    margins_str = args.margins
    if ',' in margins_str:
        # Comma-separated: left,top,right,bottom
        try:
            margins = tuple(int(x.strip()) for x in margins_str.split(','))
            if len(margins) != 4:
                raise ValueError("Must provide exactly 4 values")
        except (ValueError, AttributeError):
            print(f"❌ Error: Invalid margins '{margins_str}'. "
                  f"Use single value or left,top,right,bottom",
                  file=sys.stderr)
            sys.exit(1)
    else:
        # Single value applies to top/bottom only (for header/footer removal)
        # Left/right margins stay at 0 to avoid truncating line beginnings
        try:
            margin_val = int(margins_str)
            # (left, top, right, bottom)
            margins = (0, margin_val, 0, margin_val)
        except ValueError:
            print(f"❌ Error: Invalid margins '{margins_str}'",
                  file=sys.stderr)
            sys.exit(1)

    # Parse max chunk size
    size_match = re.match(r'(\d+(?:\.\d+)?)\s*([KMG]?)',
                          args.max_chunk_size.upper())
    if not size_match:
        print(f"❌ Error: Invalid chunk size '{args.max_chunk_size}'",
              file=sys.stderr)
        sys.exit(1)

    size_value = float(size_match.group(1))
    size_unit = size_match.group(2) or ''
    multipliers = {'K': 1024, 'M': 1024**2, 'G': 1024**3, '': 1}
    max_chunk_size = int(size_value * multipliers[size_unit])

    # Determine output directory
    input_path = pathlib.Path(args.input)
    if args.output:
        output_dir = pathlib.Path(args.output)
    else:
        output_dir = input_path.parent / f"{input_path.stem}-markdown"

    output_dir.mkdir(parents=True, exist_ok=True)

    try:
        print(f"📄 Processing: {args.input}")
        print(f"📁 Output directory: {output_dir}")
        print(f"🧩 Max chunk size: {max_chunk_size:,} bytes")
        print(f"⚙️  Workers: {args.workers}")
        print()

        # Open document to analyze structure
        doc = pymupdf.open(str(input_path))
        total_pages = len(doc)

        print(f"📊 Total pages: {total_pages}")
        print("🔍 Analyzing document structure...")

        # Build chunks from TOC
        chunks = build_toc_chunks(doc, max_chunk_size)
        print(f"✂️  Split into {len(chunks)} chunks")
        print()

        doc.close()

        # Build kwargs for to_markdown
        table_strat = (None if args.table_strategy == 'none'
                       else args.table_strategy)
        kwargs = {
            'embed_images': args.embed_images,
            'write_images': args.write_images,
            'ignore_images': args.ignore_images,
            'ignore_graphics': args.ignore_graphics,
            'table_strategy': table_strat,
            'margins': margins,  # Skip headers/footers (parsed above)
        }

        if args.write_images:
            kwargs['image_path'] = args.image_path
            kwargs['image_format'] = args.image_format

        # Set up parallel processing with progress tracking
        manager = Manager()
        progress_dict = manager.dict()
        progress_dict['chunks_done'] = 0
        progress_dict['total_chunks'] = len(chunks)
        progress_dict['no_cleanup'] = args.no_cleanup
        progress_dict['fix_lists'] = not args.no_fix_lists
        progress_dict['fix_headers'] = not args.no_fix_headers
        progress_dict['header_strategy'] = args.header_strategy
        progress_dict['body_limit'] = args.body_limit
        progress_dict['max_header_levels'] = args.max_header_levels
        lock = manager.Lock()

        # Process chunks in parallel
        worker_func = partial(
            process_chunk,
            input_path=str(input_path),
            output_dir=output_dir,
            kwargs=kwargs,
            progress_dict=progress_dict,
            lock=lock
        )

        with Pool(args.workers) as pool:
            results = pool.map(worker_func, chunks)

        print()
        print("✅ Conversion complete!")
        print(f"📝 Generated {len(results)} markdown files")

        # Generate index
        index_file = generate_index(results, output_dir, input_path.stem)
        print(f"📑 Index: {index_file}")
        print(f"📁 All files: {output_dir}/")

    except FileNotFoundError:
        print(f"❌ Error: File '{args.input}' not found", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"❌ Error: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == '__main__':
    main()
