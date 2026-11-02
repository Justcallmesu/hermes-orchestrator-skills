---
name: frontend-ui-layout-bugs
description: "Use when a UI element has wrong size/layout. Repro, measure."
---

# Frontend UI layout bugs (width, wrapping, overflow)

User asks "fix X, check it first": the deliverable of the first turn is a VERIFIED diagnosis + proposed fix + any business/look decision. Do not edit the repo before the user confirms.

## Procedure
1. **Read project context** (`PROJECT.md` / repo `CLAUDE.md`), note the UI lib version: `node -p "require('antd/package.json').version"`.
2. **Find the cause in the library source**, not in memory: read `node_modules/<lib>/es/<component>/index.js` and its `style/*.js`. Look for wrapper elements the component adds (the prop you pass often lands on the INNER element). Cite `file:line`.
3. **Inventory call sites**: `grep -rn "<prop>" src` and look at the neighbouring `style`/`className` lines. Note existing workarounds and comments claiming they work — test those claims too.
4. **Reproduce in an isolated harness** (no backend, no login needed):
   - scratch dir with `index.html` + `src/main.tsx`, `ln -s <repo>/node_modules node_modules`, run `node node_modules/vite/bin/vite.js --port <free> --strictPort` in background.
   - render every variant (plain, with workaround, each prop combination) inside a fixed-width container.
   - put the candidate fix in a CSS file gated on `body.with-fix` and toggle it with `?fix`, so one page shows before and after.
   - measure with `getBoundingClientRect()` via browser `js(...)` (outer wrapper vs form-item content width) and print a table; take a screenshot as well. Kill the vite process afterwards.
5. **Pick fix scope**: prefer one global, narrowly-selected CSS rule over editing N call sites (new call sites stay fixed). Then grep for call sites that may INTENTIONALLY want the old look (inline filter bars, toolbars) and turn each into an option for the user (opt-out class recommended).
   - **Widening to a global default** ("make every X full width"): before dispatching, run `python3 <skill_dir>/scripts/survey_component_usage.py src <Component> <generatorPropsKey> width`. It lists the usages with NO width (the only ones that change) and the ones with a FIXED width (POS cells, table cells). Inline `style` beats a stylesheet rule, so fixed widths survive; prove it by adding those cases to the harness, and tell the user exactly which screens change.
6. **Report**: cause (cited), before/after measurement table, proposed rule, the decision with options, and what is NOT verified (real pages, mobile, browser support of selectors like `:has()`). Real-page checks + build run after the fix is applied.
7. **Dispatch the fix** (after the user picks an option; state which one): one developer brief carrying the exact verified CSS, the decision (exceptions or none), the files allowed (CSS file, any comment that falsely claims the old workaround works, repo docs note, user-facing changelog per the repo's release rules), and verify commands: type-check, production build with `--outDir` in the scratch dir (repo `dist` untouched), and a grep of the built CSS for the selector (minifiers can rewrite or drop rules).
8. **Verify the shipped CSS yourself**, not the worker's claim: read `git diff` (only the allowed files), copy the built `dist/assets/*.css` into the harness (import it instead of the candidate CSS), and re-measure every variant. Include a case for each call site the decision affects (e.g. the inline filter-bar input, a half-width `md=12` column, a no-addon control that must stay unchanged). Kill the harness server, then report the measurement table plus what is still unverified (real logged-in pages, browser support).

## Pitfalls
- `style={{width:'100%'}}` / `className="w-full"` on a component that renders a wrapper does nothing for the wrapper — measure the outermost element, not the input.
- Dev-console deprecation warnings from the harness (vite log) reveal the library's intended replacement API; log the migration as a separate board item instead of folding it into the fix.
- Library-specific cases: `references/antd-quirks.md`.
- A global default rule must not out-rank an earlier, more specific fix (e.g. a plain `.x { width:100% }` vs a `:has()` wrapper rule that sets the inner `width:auto`): compare selector specificity and keep the harness case for the earlier fix in the re-measure.
- Reuse one harness across follow-ups: rewrite its `main.tsx` with the new cases (read it first; the file tool refuses blind overwrites) instead of creating a second scratch app.
