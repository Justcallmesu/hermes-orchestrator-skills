#!/usr/bin/env python3
"""Survey every usage of a JSX component (and its generator-props object) for a CSS property.

Usage: python3 survey_component_usage.py <src_dir> <Component> [propsKey] [pattern]
  e.g. python3 survey_component_usage.py src InputNumber inputNumberProps width

Prints: usages WITHOUT the pattern (these change under a new global default),
and usages with a FIXED (non-100%) width (these must keep their size; inline style wins over a stylesheet).
"""
import pathlib
import re
import sys

src, comp = pathlib.Path(sys.argv[1]), sys.argv[2]
props_key = sys.argv[3] if len(sys.argv) > 3 else None
pattern = sys.argv[4] if len(sys.argv) > 4 else r"width|w-full|w-\["


def jsx_tag(s, start):
    i, depth = start, 0
    while i < len(s):
        c = s[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
        elif depth == 0 and s.startswith("/>", i):
            return s[start:i + 2]
        elif depth == 0 and c == ">":
            return s[start:i + 1]
        i += 1
    return s[start:]


def braces(s, start):
    i, depth = start, 1
    while i < len(s) and depth:
        depth += {"{": 1, "}": -1}.get(s[i], 0)
        i += 1
    return s[start:i]


rows = []
for p in src.rglob("*.tsx"):
    s = p.read_text()
    for m in re.finditer(rf"<{comp}\b", s):
        rows.append((p, s.count("\n", 0, m.start()) + 1, jsx_tag(s, m.start())))
    if props_key:
        for m in re.finditer(rf"{props_key}:\s*\{{", s):
            rows.append((p, s.count("\n", 0, m.start()) + 1, braces(s, m.end())))

missing = [r for r in rows if not re.search(pattern, r[2]) and "..." not in r[2]]
fixed = [r for r in rows if re.search(r"width:\s*\d|width=\{\d", r[2])]
print(f"usages: {len(rows)}  without '{pattern}': {len(missing)}  fixed width: {len(fixed)}")
for title, group in (("WITHOUT", missing), ("FIXED", fixed)):
    print(f"\n{title}:")
    for p, line, tag in group:
        print(f"  {p.relative_to(src)}:{line}  {re.sub(r'\s+', ' ', tag)[:140]}")
