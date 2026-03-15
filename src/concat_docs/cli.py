"""concat-docs — Concatenate markdown files into a single output file."""

import argparse
import re
import sys
from datetime import UTC, datetime
from pathlib import Path


def collect_from_dir(directory: Path, recursive: bool) -> list[Path]:
    pattern = "**/*.md" if recursive else "*.md"
    return sorted(directory.glob(pattern))


def file_header(filepath: Path, separator: str, no_header: bool) -> str:
    lines: list[str] = []

    if separator == "banner":
        lines += [
            "",
            "<!-- ================================================================ -->",
            f"<!-- FILE: {filepath} -->",
            "<!-- ================================================================ -->",
            "",
        ]
    elif separator == "rule":
        lines += ["", "---", ""]

    if not no_header:
        lines += [f"> **Source file:** `{filepath}`", ""]

    return "\n".join(lines) + ("\n" if lines else "")


def build_file_list(inputs: list[str], recursive: bool) -> list[Path]:
    all_files: list[Path] = []
    for raw in inputs:
        p = Path(raw)
        if p.is_file():
            all_files.append(p)
        elif p.is_dir():
            all_files.extend(collect_from_dir(p, recursive))
        else:
            print(f"ERROR: Path not found: {raw}", file=sys.stderr)
            sys.exit(1)
    return all_files


def apply_filters(
    files: list[Path],
    pattern: str | None,
    exclude: str | None,
) -> list[Path]:
    pat_re = re.compile(pattern) if pattern else None
    exc_re = re.compile(exclude) if exclude else None

    result: list[Path] = []
    for f in files:
        if pat_re and not pat_re.search(f.name):
            continue
        if exc_re and exc_re.search(str(f)):
            continue
        result.append(f)
    return result


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="concat-docs",
        description="Concatenate markdown files into a single output file.",
        epilog=(
            "Examples:\n"
            "  concat-docs -o out.md README.md docs/\n"
            "  concat-docs -r -o out.md docs/\n"
            "  concat-docs -r -p 'WRITING|RUNNING' -o out.md docs/\n"
            "  concat-docs -r -x 'archive|build/' -o out.md .\n"
            "  concat-docs --dry-run -r docs/"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "inputs",
        nargs="+",
        metavar="FILE_OR_DIR",
        help="Input .md files and/or directories",
    )
    parser.add_argument(
        "-o", "--output",
        default="combined_docs.md",
        metavar="FILE",
        help="Output file (default: combined_docs.md)",
    )
    parser.add_argument(
        "-r", "--recursive",
        action="store_true",
        help="Recurse into subdirectories (default: off)",
    )
    parser.add_argument(
        "-p", "--pattern",
        metavar="REGEX",
        help="Only include files whose name matches REGEX",
    )
    parser.add_argument(
        "-x", "--exclude",
        metavar="REGEX",
        help="Exclude files whose path matches REGEX",
    )
    parser.add_argument(
        "-s", "--separator",
        choices=["banner", "rule", "none"],
        default="banner",
        metavar="STYLE",
        help="Separator style: banner, rule, or none (default: banner)",
    )
    parser.add_argument(
        "-n", "--no-header",
        action="store_true",
        help="Omit the source file label above each file's content",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print files that would be included; do not write output",
    )

    args = parser.parse_args()

    all_files = build_file_list(args.inputs, args.recursive)
    filtered = apply_filters(all_files, args.pattern, args.exclude)

    if not filtered:
        print("ERROR: No matching markdown files found.", file=sys.stderr)
        sys.exit(1)

    if args.dry_run:
        print(f"Dry run — files that would be included ({len(filtered)} total):")
        for f in filtered:
            print(f"  {f}")
        return

    output_path = Path(args.output)
    now = datetime.now(UTC).strftime("%Y-%m-%d %H:%M UTC")

    with output_path.open("w", encoding="utf-8") as out:
        out.write("<!-- concat-docs output -->\n")
        out.write(f"<!-- Generated: {now} -->\n")
        out.write(f"<!-- Files included: {len(filtered)} -->\n\n")

        for f in filtered:
            out.write(file_header(f, args.separator, args.no_header))
            out.write(f.read_text(encoding="utf-8"))
            out.write("\n")

    print(f"✓ Wrote {len(filtered)} file(s) to: {output_path}")
    for f in filtered:
        print(f"    {f}")


if __name__ == "__main__":
    main()
