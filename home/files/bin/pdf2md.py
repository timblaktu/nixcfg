import sys
import argparse
import pathlib
import re
import os
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


def estimate_chunk_size(doc, pages):
    """Estimate markdown size for a page range in bytes"""
    # Sample first page to estimate bytes-per-page ratio
    if not pages:
        return 0

    sample_page = min(pages)
    sample_text = pymupdf4llm.to_markdown(doc, pages=[sample_page])
    bytes_per_page = len(sample_text.encode('utf-8'))

    # Estimate total size
    return bytes_per_page * len(pages)


def split_large_chunk(doc, toc_entry, max_size):
    """Split a TOC entry into smaller chunks if it exceeds max_size"""
    level, title, start_page, end_page = toc_entry
    pages = list(range(start_page, end_page))

    estimated_size = estimate_chunk_size(doc, [start_page])
    total_estimated = estimated_size * len(pages)

    if total_estimated <= max_size:
        return [toc_entry]

    # Split into smaller chunks
    chunks = []
    pages_per_chunk = max(1, int(max_size / estimated_size))

    for i in range(0, len(pages), pages_per_chunk):
        chunk_pages = pages[i:i + pages_per_chunk]
        chunk_title = f"{title} (Part {i//pages_per_chunk + 1})"
        chunks.append((level, chunk_title, chunk_pages[0], chunk_pages[-1] + 1))

    return chunks


def build_toc_chunks(doc, max_chunk_size):
    """Build chunks from TOC with size limits"""
    toc = doc.get_toc()
    total_pages = len(doc)

    if not toc:
        # Fallback: use IdentifyHeaders for structure detection
        try:
            hdr_info = pymupdf4llm.IdentifyHeaders(doc)
            # Even without TOC, split by max_chunk_size
            return build_size_based_chunks(doc, total_pages, max_chunk_size)
        except:
            return build_size_based_chunks(doc, total_pages, max_chunk_size)

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
        split_chunks = split_large_chunk(doc, entry, max_chunk_size)
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


def process_chunk(chunk_info, input_path, output_dir, kwargs, progress_dict, lock):
    """Process a single chunk in parallel"""
    level, title, start_page, end_page = chunk_info
    chunk_id = f"{start_page:04d}"
    safe_title = sanitize_filename(title)

    # Open document (each worker gets its own handle)
    doc = pymupdf.open(input_path)

    # Process pages
    pages = list(range(start_page, end_page))
    md_text = pymupdf4llm.to_markdown(doc, pages=pages, **kwargs)

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
        print(f"[{pct:5.1f}%] Completed: {title} (pages {start_page+1}-{end_page})")

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
    examples = """
Examples:
  pdf2md input.pdf                           # Convert with smart chunking
  pdf2md input.pdf -o ./output/              # Specify output directory
  pdf2md input.pdf --max-chunk-size 2M       # 2MB chunks
  pdf2md input.pdf --embed-images            # Embed images as base64
  pdf2md input.pdf --write-images            # Save images to ./images/
  pdf2md input.pdf --workers 8               # Use 8 parallel workers
    """

    parser = argparse.ArgumentParser(
        description='Convert PDF to Markdown (parallel, TOC-aware)',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=examples
    )

    parser.add_argument('input', help='Input PDF file')
    parser.add_argument(
        '-o', '--output',
        help='Output directory (default: same as input)')
    parser.add_argument(
        '--max-chunk-size', default='1M',
        help='Maximum chunk size (e.g., 1M, 500K) (default: 1M)')
    parser.add_argument(
        '--workers', type=int, default=cpu_count(),
        help=f'Number of parallel workers (default: {cpu_count()})')
    parser.add_argument(
        '--embed-images', action='store_true',
        help='Embed images as base64 in markdown')
    parser.add_argument(
        '--write-images', action='store_true',
        help='Save images as separate files')
    parser.add_argument(
        '--image-path', default='./images',
        help='Directory for saved images (default: ./images)')
    parser.add_argument(
        '--image-format', default='png',
        help='Image format (default: png)')
    parser.add_argument(
        '--ignore-images', action='store_true',
        help='Skip all images')
    parser.add_argument(
        '--ignore-graphics', action='store_true',
        help='Skip all graphics')
    parser.add_argument(
        '--table-strategy',
        choices=['lines_strict', 'lines', 'text', 'none'],
        default='lines_strict',
        help='Table detection strategy')

    args = parser.parse_args()

    # Parse max chunk size
    size_match = re.match(r'(\d+(?:\.\d+)?)\s*([KMG]?)', args.max_chunk_size.upper())
    if not size_match:
        print(f"❌ Error: Invalid chunk size '{args.max_chunk_size}'", file=sys.stderr)
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
        print(f"🔍 Analyzing document structure...")

        # Build chunks from TOC
        chunks = build_toc_chunks(doc, max_chunk_size)
        print(f"✂️  Split into {len(chunks)} chunks")
        print()

        doc.close()

        # Build kwargs for to_markdown
        kwargs = {
            'embed_images': args.embed_images,
            'write_images': args.write_images,
            'ignore_images': args.ignore_images,
            'ignore_graphics': args.ignore_graphics,
            'table_strategy': None if args.table_strategy == 'none' else args.table_strategy,
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
        print(f"✅ Conversion complete!")
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
