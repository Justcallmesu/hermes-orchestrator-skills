#!/usr/bin/env python3
"""Verify the `path:line` citations in a markdown answer against real files. Changes nothing.

Usage: check-cites.py ANSWER.md --root PREFIX=DIR [--root PREFIX=DIR ...] [--window 12]

A citation is `PREFIX/relative/path.ts:123` or `:123-130` (PREFIX = the name used in the answer,
e.g. bkm-backend; DIR = where that tree really is, e.g. a frozen snapshot), or a bare `name.ts:123`.
A bare name is looked up by file name in every --root tree; the cite passes if ANY candidate file fits.
Per citation:
  FILE   the file must exist
  RANGE  the line (both ends of a range) must be <= the file's line count
  IDENT  backticked identifiers on the same markdown line (fooBar, foo_bar, FooBar, name()) must appear
         within +-WINDOW lines of the cited range, otherwise WARN: the number probably belongs to another
         file (`cat -n a b c` numbers lines continuously across files). Only checked on lines that carry
         ONE citation (with several, a name usually belongs to another cite).
Limit: a second range after a comma (`file.ts:10-20, 30-40`) is not parsed; write each cite in full.
Exit 0 = clean, 1 = FILE/RANGE errors, 2 = only warnings.
"""
import argparse, os, re, sys

def idents(line):
    out = []
    for tok in re.findall(r"`([^`]+)`", line):
        if ':' in tok and '/' in tok:
            continue
        for m in re.findall(r"[A-Za-z_][A-Za-z0-9_]{3,}", tok):
            if re.search(r"[a-z][A-Z]|_", m) or m[0].isupper():
                out.append(m)
    return list(dict.fromkeys(out))

def read(cache, f):
    if f not in cache:
        cache[f] = open(f, encoding='utf-8', errors='replace').read().splitlines() if os.path.isfile(f) else None
    return cache[f]

def judge(lines, lo, hi, names, window):
    """-> ('ok'|'RANGE'|'IDENT', detail)"""
    if lines is None: return 'FILE', 'no such file'
    if hi < lo or hi > len(lines): return 'RANGE', f'file has {len(lines)} lines'
    seg = "\n".join(lines[max(0, lo - 1 - window): hi + window])
    if names and all(x not in seg for x in names): return 'IDENT', f"none of {names[:4]} within +-{window} lines"
    return 'ok', ''

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('answer'); ap.add_argument('--root', action='append', required=True)
    ap.add_argument('--window', type=int, default=12)
    a = ap.parse_args()
    roots = dict(r.split('=', 1) for r in a.root)
    index = {}
    for pre, d in roots.items():
        for dp, dn, fn in os.walk(d):
            dn[:] = [x for x in dn if x not in ('node_modules', '.git', 'dist', 'graphify-out')]
            for f in fn: index.setdefault(f, []).append(os.path.join(dp, f))
    pre_re = re.compile(r"(?P<p>(?:%s)/[\w@./\-\[\]]+?\.\w+):(?P<a>\d+)(?:-(?P<b>\d+))?" % '|'.join(map(re.escape, roots)))
    bare_re = re.compile(r"(?<![\w/.\-])(?P<n>[\w@.\-]+\.(?:ts|tsx|js|jsx|sql|md|json|ya?ml)):(?P<a>\d+)(?:-(?P<b>\d+))?")
    cache, err, warn, n = {}, [], [], 0
    for ln, text in enumerate(open(a.answer, encoding='utf-8'), 1):
        names, items, spans = idents(text), [], []
        for m in pre_re.finditer(text):
            pre, rel = m['p'].split('/', 1); spans.append(m.span())
            items.append((m['p'], [os.path.join(roots[pre], rel)], int(m['a']), int(m['b'] or m['a'])))
        for m in bare_re.finditer(text):
            if any(s0 <= m.start() < e0 for s0, e0 in spans): continue
            items.append((m['n'], index.get(m['n'], []), int(m['a']), int(m['b'] or m['a'])))
        for label, cands, lo, hi in items:
            n += 1
            res = [judge(read(cache, f), lo, hi, names if len(items) == 1 else [], a.window) for f in cands] or [('FILE', 'no file with that name')]
            if any(r[0] == 'ok' for r in res): continue
            kind, detail = min(res, key=lambda r: ['IDENT', 'RANGE', 'FILE'].index(r[0]))
            extra = f" (checked {len(cands)} files with that name)" if len(cands) > 1 else ''
            (warn if kind == 'IDENT' else err).append(f"{kind:6} answer:{ln} {label}:{lo}" + (f"-{hi}" if hi != lo else '') + f": {detail}{extra}")
    for x in err + warn: print(x)
    print(f"{n} citations: {len(err)} errors, {len(warn)} warnings")
    sys.exit(1 if err else 2 if warn else 0)
main()
