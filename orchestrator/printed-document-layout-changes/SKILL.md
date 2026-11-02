---
name: printed-document-layout-changes
description: "Use when changing, or comparing old vs new, a printed form."
---

# Change a printed business form (PDF) safely

Applies to: adjusting one document's print (surat jalan, invoice, PO...) in a shared PDF
layout service where many documents share one drawing routine, usually to match a legacy
pre-printed / carbon form.

## Procedure
1. **Pin the layout before building.**
   - Ask for (or use) a photo/scan of the legacy form; it settles column order, relative widths,
     alignment, rules and placeholders faster than prose. If it arrives mid-build, steer the
     running worker with the concrete deltas (widths as fractions, alignment, placeholder text)
     and update the spec row in the same turn.
   - Ask in ONE clarify round only what the request leaves open, with options: what fills a
     description column (stored note vs always blank), where a known value prints (heading vs
     inside/under the signature mark), whether an existing column is dropped when one is added.
   - State-dependent print ("blank write-in line until the document is started"): name the exact
     status signal from code and say how reverted / voided rows print. Prefer the positive state
     (`status === VERIFIED`) over negating one (`!== PENDING`): the negation silently counts
     VOID and any later status as "started". Read what the cancel/void path clears on the row
     first; if it wipes the start fields, "voided before vs after start" is indistinguishable and
     both must print the same. Record each as a spec decision.
   - Never promise existing print behaviour ("it carries the VOID stamp") from memory: grep the
     document's layout for the property (`stamp:`, the status map) before telling the user or
     writing it into a spec/brief. Give the worker a stop condition for every such assumption
     ("if the stamp does not exist, stop and report"); when it fires, correct the claim to the
     user plainly and ask the business choice (which word, or none) with options.
2. **Isolate the change to the one document.**
   - Extend the layout model with a typed column variant (e.g. `string | {kind:'signature'|'note'}`)
     that only the target document passes; plain strings keep the old drawing path. Never change
     the shared routine's default output.
   - Brief rule for the worker: "if this can only be done by changing every document, stop and ask".
3. **Find every test that asserts the old print**, not only the ones named in the ticket:
   grep the suites for the document's PDF endpoint and for its printed labels/values. A
   state-dependent change (value hidden before start) breaks older suites that print an unstarted
   row and expect the value; update them to assert both states (before: placeholder; after Start:
   value).
4. **Verify (PM, not the worker's claim):**
   - Render the target PDF to PNG (`pdftoppm -png -r 80`) and look at it against the photo.
   - Other documents: render the same set before and after and compare pixels; must be identical.
   - Text checks: `pdftotext -layout` for row contents (Via line, column headings, captions).
   - Overflow/geometry: `pdftotext -bbox` word boxes, assert every word of the long text has
     `xMax <` the x of the next column's heading. Words are NOT in reading order; locate the
     heading by its row (y), not by sequence. Include one very long unbroken word.
   - Prove the geometry test can fail: temporarily widen the text box, test must fail, restore,
     sha256 equal.
   - Mutation pass on the selection logic (state flag forced on/off, note dropped, fallback chain
     reordered, stamp removed AND stamp applied to every status: the second proves the
     "other states stay unstamped" checks bite). A surviving "chain order" mutant means no fixture has two non-blank sources;
     add one or accept it explicitly in the report.
5. **Report** with a rendered-sample description, which suites changed and why, and what is not
   verified (physical carbon print, multi-page pagination when no fixture reaches page 2).

## Comparing a legacy print with the remake (parity check, read-only)
Applies to "check print X in the old app against the remake". Answer first: per document, PORTED /
PORTED-WITH-GAPS / MISSING.
1. **Map names before comparing.** Documents get renamed across ports and class names collide
   (the remake's `DeliveryOrder` can be a different document than the old `DeliveryOrder`). Grep the
   Indonesian title in BOTH trees (`grep -rnoiE '.{0,60}surat ?jalan.{0,40}'` in old;
   `git grep -nioE ... origin/main -- frontend/src backend/src` in new) plus the printed title
   string (`title="SURAT ..."`), then confirm with the module knowledge doc (it usually names the old
   class: "Old program: Record of Delivery"). Never pair by class name alone.
2. **Read `origin/main` after `git fetch`**, not the current feature branch: prints are often ported
   by another developer on main.
3. **Check existing audits** (`docs/port-gap/**`, knowledge docs) for the document's status and any
   drop decision; cite them, and flag stale ones.
4. **Read both print components whole** (`cat -n`, one file per read) and the old entity/service for
   status side effects the print implies (approval moving child docs to ON_DELIVERY, etc.).
5. **Report as one table per document**: Part | Old (`file:line`) | Remake (`file:line`) | Gap.
   Rows: title, company header (hard-coded vs settings), number label, date format, recipient/
   destination, print date, header fields, table columns, quantity format, signatures (labels AND
   order), void/cancel stamp, footer setting. Mark remake additions as additions, not gaps.
   Call out legacy bugs (e.g. a box printing today's date instead of a field) as "do not port".
   Flag settings whose name points at a document that no longer prints (footer key shared by
   other prints).
6. **Close with business decisions as options** (restore missing columns vs replicate old layout
   exactly vs leave; for a MISSING document: confirm still needed vs full port vs record a drop),
   recommended first, then offer spec + tickets. State that the check was code-only, not rendered.

## Switching the print MECHANISM (browser print -> server PDF)
Applies when the user wants prints "like project Y": for example from client-side `react-to-print` / `window.print` on
hidden A4 divs to a server PDF endpoint (pdfkit, `GET /document-pdf/<kind>/:id` guarded by the
document's READ permission, Cetak opens the PDF in a tab that is opened synchronously in the click,
so the popup blocker allows it, Unduh PDF downloads it, and a print-log table feeds an "Info Cetak" history).
- Inventory first: every existing print in the target (`git grep -l useReactToPrint origin/main`),
  its author and date, its paper CSS (`@page`), and the shared layout component and settings keys it
  reads (company header, per-document footer). These keys move server-side.
- Grill, one Q each: which prints to convert; keep each document's current layout and paper vs adopt the
  reference's standard form (recommend keep, so users see the same form); print history yes/no; how
  VOID/cancelled documents print (recommend a BATAL stamp); old prints whose document does not exist
  in the target (recommend out of scope); reports (`?format=pdf` on the report endpoint), kept apart from
  document prints.
- Technical trade-off to state: pdfkit means every HTML layout is redrawn by hand in code, and that is the
  main cost of "keep layout". HTML-to-PDF through headless Chrome reuses the layouts but adds a browser
  dependency to the server. Recommend copying the reference project's engine unless the user objects.
- Verification is the same as below: render to PNG and compare with the old print, plus
  `pdftotext` asserts per status.

## Pitfalls
- Money summaries on an invoice/faktur print come from the STORED totals (subtotal, PPN, grand total),
  never a client recompute. When the document stores only the INPUTS of a deduction (discount %,
  covered-cost amount or %), brief the worker to derive the printed rows from the same backend
  formula and to show, per worked case (PPN 0; PPN with % discount; % covered cost with flat
  discount), that the printed rows add up to the stored grand total. Ask it to report any case where
  separately rounded stored fields (subtotal, PPN, total) differ by a cent: that is a backend rounding
  ticket, not a print fix.
- A print button for a priced document needs the same permission rule as the backend price
  redaction, plus the status/customer gate the spec decided; a button shown to users whose prices
  are redacted prints zeros.
- Name fallback chains must skip blank/whitespace values (`firstNonBlank` with trim), not use `||`,
  or a whitespace snapshot stops the chain and prints an empty caption.
- Long names/notes: clip to one line / box height with an ellipsis and a smaller font; never let
  them wrap into the signature mark or push the bottom block to a new page.
- Rotated stamps (BATAL / DRAFT watermark) come out split across lines in `pdftotext -layout`
  ("BA" / "TAL"); assert stamp text against `pdftotext -raw`, which keeps the word whole.
- A document's stamp must not reuse `STATUS_STAMP[status]` blindly when its status names collide
  with another document's (SJ `PENDING` would print "BELUM DISETUJUI"); map explicitly.
- A changelog line describing endpoints must use the verb from the controller decorator, not the
  brief's wording; grep `@Post(':id/...')` before writing it.
