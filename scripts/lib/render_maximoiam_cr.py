#!/usr/bin/env python3
"""Render the sample MaximoIAM CR with runtime values."""
from __future__ import annotations

import argparse
import pathlib
import re
import sys


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sample", type=pathlib.Path, help="Path to sample CR YAML")
    parser.add_argument("release", help="Release name to inject")
    parser.add_argument("namespace", help="Namespace to inject")
    parser.add_argument("pg_password", help="PostgreSQL password to inject")
    parser.add_argument("storage_class", nargs="?", default="", help="Optional storageClass override")
    args = parser.parse_args()

    content = args.sample.read_text()
    content = re.sub(r"^  name: .*$", f"  name: {args.release}", content, count=1, flags=re.MULTILINE)
    content = re.sub(r"^  namespace: .*$", f"  namespace: {args.namespace}", content, count=1, flags=re.MULTILINE)
    content = content.replace("__RELEASE__", args.release)
    content = content.replace("__PG_PASSWORD__", args.pg_password)

    if args.storage_class:
        def _replace(match: re.Match[str]) -> str:
            return f"{match.group(1)} {args.storage_class}"
        content = re.sub(r"^(\s*storageClass:).*$", _replace, content, flags=re.MULTILINE)

    sys.stdout.write(content)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
