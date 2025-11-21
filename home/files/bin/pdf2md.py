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


def cleanup_markdown(text):
    """Clean up common markdown formatting issues from PDF conversion"""
    import re

    # Remove excessive dot leaders (TOC artifact)
    # Match patterns like ". . . . . . . ." with 3+ dot sequences
    text = re.sub(r'(\s*\.\s+){3,}', ' ', text)

    # Collapse excessive blank lines (3+ → 2)
    text = re.sub(r'\n{3,}', '\n\n', text)

    # Clean up standalone page numbers that aren't part of content
    # (Page numbers usually appear alone on a line)
    text = re.sub(r'^\s*\d+\s*$', '', text, flags=re.MULTILINE)

    # Remove trailing whitespace from lines
    text = re.sub(r'[ \t]+$', '', text, flags=re.MULTILINE)

    return text


def process_chunk(chunk_info, input_path, output_dir, kwargs, progress_dict,
                  lock):
    """Process a single chunk in parallel"""
    level, title, start_page, end_page = chunk_info
    chunk_id = f"{start_page:04d}"
    safe_title = sanitize_filename(title)

    # Open document (each worker gets its own handle)
    doc = pymupdf.open(input_path)

    # Set up TOC-based header detection for better structure
    try:
        toc_headers = pymupdf4llm.TocHeaders(doc)
        kwargs_with_headers = {**kwargs, 'hdr_info': toc_headers}
    except Exception:
        kwargs_with_headers = kwargs

    # Process pages
    pages = list(range(start_page, end_page))
    md_text = pymupdf4llm.to_markdown(doc, pages=pages,
                                      **kwargs_with_headers)

    # Clean up markdown formatting issues (unless disabled)
    if not progress_dict.get('no_cleanup', False):
        md_text = cleanup_markdown(md_text)

    # Generate output filename
    base_name = pathlib.Path(input_path).stem
    output_file = output_dir / f"{base_name}-{chunk_id}-{safe_title}.md"

    # Write output
    output_file.write_bytes(md_text.encode('utf-8'))

    # Update progress
    with lock:
        progress_dict['completed'] += len(pages)
        progress_dict['chunks_done'] += 1
        pct = 100 * progress_dict['completed'] / progress_dict['total']
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

Output:
  Creates directory: {input}-markdown/
  Files: {input}-{page:04d}-{chapter-title}.md
  Index: {input}-index.md (with cross-document links)

Chunking Strategy:
  1. Extract TOC → split by chapters/sections
  2. No TOC → font-based header detection (IdentifyHeaders)
  3. Fallback → equal page distribution
  Chunks exceeding --max-chunk-size are automatically split.

Performance:
  --table-strategy none      # Skip tables for 2-3x speedup
  --ignore-graphics          # Skip vector graphics
  --ignore-images            # Text-only extraction

Quality:
  --margins 0,72,0,72        # Skip top/bottom 1" margins (headers/footers)
  --margins 36               # Skip 0.5" on all sides (use single value)
  --no-cleanup               # Disable dot leader/whitespace cleanup
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
                         help='margins: N or l,t,r,b (default: 0,36,0,36)')
    quality.add_argument('--no-cleanup', action='store_true',
                         help='skip cleanup (dots, whitespace)')

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
        # Single value applies to all sides
        try:
            margins = int(margins_str)
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
        progress_dict['completed'] = 0
        progress_dict['total'] = total_pages
        progress_dict['chunks_done'] = 0
        progress_dict['no_cleanup'] = args.no_cleanup
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
