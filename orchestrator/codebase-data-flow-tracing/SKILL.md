---
name: codebase-data-flow-tracing
description: Trace a feature's data flow from UI widget to DB entity.
---

# Codebase Data-Flow Tracing

Use when asked to analyze/understand a feature by tracing it end-to-end through a layered full-stack codebase (UI component -> API client -> controller -> service -> DB entity) — e.g. "analyze this dashboard, tell me the data flow" or "what entity backs this widget." Goal: produce a map a future session (or the user) can act on immediately, not a narrative of files you opened.

## Procedure

1. **Get the shape of the codebase first, in parallel.** One batched round of tool calls: repo root listing, README/CLAUDE.md/AGENTS.md files (they often state canonical conventions — e.g. "currency formatter to use", "query graphify before grepping" — follow those before hand-rolling your own search), and a `docs/` directory listing if present. Don't serialize these — they're independent reads.
2. **Find the entry points (UI layer) before the backend.** List the feature's component directory (e.g. `views/Home/**`). Read every widget file in that directory in parallel batches of 5-8 `read_file` calls per turn — one widget per file is a common convention, so this is usually a flat, boundable set.
3. **For each widget, extract exactly 3 things while reading it once:** (a) the axios/API-client call it makes, (b) the response TypeScript interface it consumes, (c) the query hook/params it passes (date range, pagination, groupBy). Don't re-open the file later to get (b) or (c) — capture all three on the first pass.
4. **Follow the axios factory to the controller, then the controller to the service, in the same batched-parallel style.** In NestJS-shaped backends the chain is `axios config (URL) -> @Get() handler (permission-gated) -> service method -> TypeORM createQueryBuilder`. Read the controller and every service method it calls together in one round, not one file per round.
5. **Read the entity files last, only for the fields actually referenced in the service query.** Don't dump full entity files speculatively before you know which columns matter — read the controller/service first so you know what to look for (`limitHm`, `contractFeeLimit`, `grandTotal`, etc.), then confirm those fields' types/relations in the entity.
6. **Treat doc comments on services/entities as load-bearing, not decoration.** In mature codebases, block comments above a query method often encode a real, previously-discovered bug or business-rule gotcha (a misleadingly-named column, a field that means the opposite of what it sounds like, an endpoint that's known-broken and deliberately left unfixed). Extract these verbatim into your map — they are exactly the information that saves the next session from re-deriving or re-breaking the same thing.
7. **Flag system-boundary widgets separately.** In any dashboard/aggregation feature, check whether each data source is the local DB or a proxied external service call (a `GET` that calls out to another microservice via an HTTP client). These behave differently under failure (hard throw vs local query) and won't show up as an entity at all — call this out explicitly, don't silently list them alongside local-DB widgets as if they were the same kind of thing.
8. **Deliver a table, not prose-per-file.** Group by page/tab, one row per widget: `Widget | Endpoint | Service method | Entity/fields | Notes`. Put cross-cutting findings (shared conventions, repeated field misuse across widgets, the entity-relationship backbone) in a short section after the table. This is the format that lets the user or a future session jump straight to "what backs widget X" without re-reading narrative.

## Variant: "how does X work / can we change X" design questions on a mature feature

Same tracing discipline, but the deliverable is a recommendation, not a map. Order:

1. **Find the written design first.** Grep the repo AND its sibling `docs/` dirs for the feature's spec/ticket/knowledge files (`terminal`: `grep -rIil --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist -E "term1|term2" .`). Read the spec's trailing "Implementation Notes"/"Deviations" section before the body — it records where what shipped differs from the design, and the body sections it supersedes will mislead you.
2. **Verify spec claims against code before asserting them.** Spec says "built" != it is; open the service/entity the claim names. State in the answer which parts you verified in code vs only read in docs, and say when you did not check whether a follow-up fix was implemented.
3. **Before proposing to delete/replace an entity, split it by job.** List every column and who reads it (billing/pricing, stock/rollup counters, FK from child tables, hooks). Grep every consumer of the entity. Propose keeping the part other modules depend on and moving the other part to its real source of truth; a whole-entity delete usually orphans one of the jobs.
4. **Check the premise of the user's worry.** E.g. "stock coming from upstream document X" — grep X's module for inventory/stock writes; often the upstream is only a quote/copy with nothing to migrate.
5. **When the redesign moves or re-points quantity writes, audit unit basis at every writer.** Compare the unit the store persists (e.g. base/small unit) against the unit each caller passes in (entered/billing unit). Two writers into one ledger with different conventions is a latent bug that a redesign will expose; find it by grepping the conversion helper's callers, then checking whether this writer calls it. Record it as a finding with a failing-test-first fix, not a footnote.
6. **End with explicit decisions for the user** (2-3 numbered questions, recommended option stated) and offer to write a spec/tickets before any code, when the user's repo convention is spec-first.

Project-specific notes live in local, unpushed reference files.

## Pitfalls

- When the user keeps pushing back on a design ("I mean X"), re-read their last message against the entity's *jobs* before answering again: they are usually pointing at a specific coupling (e.g. a copied quote line that must survive) that the previous option table glossed over. Answer that exact coupling first, then widen.
- `search_files(target="files")` takes a glob-ish filename pattern, not a regex with alternation/hyphen-or-underscore classes; a pattern like `work[-_ ]?order` silently returns 0. For "does this concept exist anywhere" use `grep -rIil` via `terminal` (content search), then narrow.

- `search_files(target="files")` on a broad glob (e.g. `*` at a package root) truncates at ~100 results with `total_count_is_lower_bound: true` — it is a directory listing, not a complete inventory. Narrow with a `path` scoped to the feature directory or a specific `file_glob` before trusting the result is exhaustive.
- When the same field/entity is reused across multiple widgets for different purposes (e.g. one cost/expense column used as "repair cost" in three unrelated widgets), note that reuse explicitly in the map — it's a common source of a future bug when someone changes the field's meaning in one place and breaks the others silently.
- Don't read entity files speculatively before reading the service that queries them — you'll waste calls pulling in fields nobody references, and mid-size entity files can be 150-250 lines.
