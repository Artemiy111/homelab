#!/usr/bin/env python3
"""Insert a blank line between semantic key groups in every compose file.

Complements dclint's `service-keys-order`: dclint reorders service keys into
semantic groups but does not separate them visually. This script walks each
compose file and inserts a blank line wherever the group of consecutive
service-level keys changes. It preserves comments (a blank line goes above a
comment that belongs to the key) and is idempotent.

Usage: python3 scripts/compose-format.py [path ...]
If no paths are given, every compose file under the repo root is processed.
"""

from __future__ import annotations

import os
import re
import sys

GROUP_ORDER = [
    # must mirror dclint's default `service-keys-order` groups
    ("Core", {"image", "build", "container_name"}),
    ("Dependencies", {"depends_on"}),
    ("Data", {"volumes", "volumes_from", "configs", "secrets"}),
    ("Environment", {"environment", "env_file"}),
    ("Networking", {"ports", "networks", "network_mode", "extra_hosts"}),
    ("Runtime", {"command", "entrypoint", "working_dir", "restart", "healthcheck"}),
    ("Metadata", {"logging", "labels"}),
    ("Security", {"user", "isolation"}),
]
GROUP_FOR_KEY = {key: i for i, (_name, keys) in enumerate(GROUP_ORDER) for key in keys}
OTHER_GROUP = len(GROUP_ORDER)

COMPOSE_RE = re.compile(r"(?:docker-)?compose.*\.ya?ml$")
SKIP_DIRS = {".git", "node_modules", ".venv", "venv"}


def group_of(key: str) -> int:
    return GROUP_FOR_KEY.get(key, OTHER_GROUP)


def is_map_key(line: str) -> bool:
    stripped = line.strip()
    if not stripped or stripped.startswith("#") or stripped.startswith("-"):
        return False
    return bool(re.match(r"^[^#][^:]*:\s*(?:#.*)?$", stripped))


def key_name(line: str) -> str:
    return line.strip().split(":", 1)[0].strip()


def indent_of(line: str) -> int:
    return len(line) - len(line.lstrip(" "))


def service_key_lines(lines: list[str]) -> list[int]:
    """Indices of the service-level key lines (one level below each service name)."""
    services_at = None
    for i, line in enumerate(lines):
        if is_map_key(line) and key_name(line) == "services":
            services_at = i
            break
    if services_at is None:
        return []

    services_indent = indent_of(lines[services_at])
    sn_indent = None
    for line in lines[services_at + 1:]:
        if not line.strip() or line.strip().startswith("#"):
            continue
        ind = indent_of(line)
        if ind > services_indent and is_map_key(line):
            sn_indent = ind
            break
    if sn_indent is None:
        return []

    sk_indent = sn_indent + 2
    result: list[int] = []
    for i, line in enumerate(lines[services_at + 1:], start=services_at + 1):
        if not line.strip() or line.strip().startswith("#"):
            continue
        ind = indent_of(line)
        if ind <= services_indent:
            break
        if ind == sk_indent and is_map_key(line):
            result.append(i)
    return result


def insert_blank_lines(lines: list[str], key_indices: list[int]) -> list[str]:
    if not key_indices:
        return lines

    out = list(lines)
    insert_positions: set[int] = set()
    prev_key = None
    for idx in key_indices:
        if prev_key is not None and group_of(key_name(out[prev_key])) != group_of(key_name(out[idx])):
            pos = idx
            while pos - 1 >= 0 and out[pos - 1].strip().startswith("#"):
                pos -= 1
            if pos == 0 or out[pos - 1].strip() != "":
                insert_positions.add(pos)
        prev_key = idx

    for pos in sorted(insert_positions, reverse=True):
        out.insert(pos, "")
    return out


def process_file(path: str) -> int:
    with open(path, "r", encoding="utf-8") as fh:
        original = fh.read()

    lines = original.split("\n")
    key_indices = service_key_lines(lines)
    if not key_indices:
        return 0

    updated = insert_blank_lines(lines, key_indices)
    result = "\n".join(updated)

    if result != original:
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(result)
        return len(insert_blank_lines(lines, key_indices)) if False else 1
    return 0


def find_compose_files(root: str) -> list[str]:
    found: list[str] = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            if COMPOSE_RE.match(name):
                found.append(os.path.join(dirpath, name))
    return sorted(found)


def main() -> int:
    args = sys.argv[1:]
    if args:
        paths = args
    else:
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        paths = find_compose_files(root)

    changed = 0
    for path in paths:
        changed += process_file(path)
    print(f"Проверено файлов: {len(paths)}, изменено: {changed}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
