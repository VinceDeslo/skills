#!/usr/bin/env python3
import re
import sys
from pathlib import Path

MAX_SIZE_BYTES = 16 * 1024 * 1024
TITLE_PATTERN = re.compile(r"<title[^>]*>\s*(\S.*?)\s*</title>", re.IGNORECASE | re.DOTALL)
DESCRIPTION_PATTERN = re.compile(r"<meta\s+[^>]*name=[\"']description[\"']", re.IGNORECASE)
EXTERNAL_RESOURCE_PATTERN = re.compile(
    r"<(?:script|link|img|iframe|video|audio|source)\b[^>]*\b(?:src|href)=[\"'](https?:)?//", re.IGNORECASE
)
EXTERNAL_IMPORT_PATTERN = re.compile(r"@import\s+(?:url\()?[\"']?(https?:)?//", re.IGNORECASE)


def check(path):
    problems = []
    text = path.read_text(encoding="utf-8", errors="replace")
    if path.stat().st_size > MAX_SIZE_BYTES:
        problems.append(f"file exceeds {MAX_SIZE_BYTES // (1024 * 1024)} MB")
    if not TITLE_PATTERN.search(text[:16384]):
        problems.append("missing <title> in the first 16 KB")
    if not DESCRIPTION_PATTERN.search(text[:16384]):
        problems.append('missing <meta name="description"> in the first 16 KB')
    if not re.search(r"<meta\s+[^>]*charset=", text[:4096], re.IGNORECASE):
        problems.append("missing <meta charset>")
    if not re.search(r"<meta\s+[^>]*name=[\"']viewport[\"']", text[:16384], re.IGNORECASE):
        problems.append('missing <meta name="viewport">')
    for match in EXTERNAL_RESOURCE_PATTERN.finditer(text):
        line = text.count("\n", 0, match.start()) + 1
        problems.append(f"external resource at line {line}: {match.group(0)[:80]}")
    for match in EXTERNAL_IMPORT_PATTERN.finditer(text):
        line = text.count("\n", 0, match.start()) + 1
        problems.append(f"external css import at line {line}")
    return problems


def main(argv):
    if len(argv) < 2:
        print("usage: check_artifact.py <file.html> [...]", file=sys.stderr)
        return 2
    exit_code = 0
    for argument in argv[1:]:
        path = Path(argument).expanduser()
        if not path.is_file():
            print(f"{path}: not a file")
            exit_code = 1
            continue
        problems = check(path)
        if problems:
            exit_code = 1
            print(f"{path}: {len(problems)} problem(s)")
            for problem in problems:
                print(f"  - {problem}")
        else:
            print(f"{path}: ok")
    return exit_code


if __name__ == "__main__":
    sys.exit(main(sys.argv))
