# Batch discovery fan-out (several gap items in one request)

Use when the user asks to build a list of items at once (usually rows from a port-gap audit). The goal
is one `spec.md` with every open Q, produced by parallel read-only agents, before any ticket.

## Order
1. **Re-check scope against the newest base.** `git fetch`; for each item, probe `origin/main`
   (`git grep -n`, `git ls-tree -r --name-only`, the controller's `@Get|@Post|@Put|@Patch|@Delete`
   decorators) and the root `CHANGELOG.md`. Note the base SHA you read. Items already built go to the
   board as "already on main" with the author and commit.
2. **Write one shared brief** at `docs/<batch>-tickets/discovery-brief.md`. It holds:
   - paths (new repo, old app, knowledge dir, the audit report);
   - "read `origin/main` only" with the `git show origin/main:<path>` / `git grep ... origin/main --`
     forms, because the user's checkout is usually on another branch;
   - rules: VERIFIED `path:line` or ASSUMED, one file per read, quote recorded decisions, plain
     shell only (no `bash -c`, heredocs or `{ }` groups);
   - per feature, six sections: old behaviour (incl. side effects, reachable UI, print fields);
     new today; side effects the change must respect (stock, reservations, FIFO, journals,
     payables, invoices, status history, notifications, FKs/onDelete); the pattern to copy;
     open business Qs (2-4 options, recommended first, consequence each); risks + size + ticket split;
   - output path per agent and a 10-line summary as the final answer.
3. **Fan out by area, 2 related items per agent** (same module/service, e.g. DO edit + PO close),
   each with module hints (old and new file paths, the knowledge doc, the audit row numbers) in its
   context. Reports go to `docs/<batch>-tickets/discovery/<area>.md`. Run in the background and end
   the turn; the where-to-build question can be asked meanwhile.
4. **When they return:** compare their base SHA with the current `origin/main`
   (`git diff --stat <their-sha>..origin/main -- <cited module dirs>`). A changed module means an item
   may have been built in between: read the commits before relaying the agent's "missing".
5. **Read every report's Q section yourself** (not only the summaries), renumber all Qs into one
   global Q1..Qn series in `spec.md` (scope table with a one-line finding per item, decisions table,
   PM technical decisions, known risks, stale docs to fix in the docs ticket).
6. Mark which items touch money or stock: those get a fresh red-team of the spec after answers and
   before tickets; the rest can go straight to tickets.
7. **After the answers** (often "all recommended"): bulk-mark every OPEN row with the chosen option
   and the source in one scripted replace, then count the replacements against the number of Qs.
   A "coordinate with the other developer first" answer becomes a HOLD line in `decisions.md` and at
   the top of `tickets.md`: no developer worker starts until the user confirms the handover. Use the
   hold for everything that writes nothing to the repo: dispatch the money/stock red-team, write the
   ticket table for the other items, and run the baseline gate in the background, all at once.

## Pitfalls
- An agent's "missing" is a claim about the SHA it read. One item in a batch can be merged by
  another developer during the run.
- Agents tend to propose porting old behaviour verbatim. When their "old behaviour" section shows
  buggy or unreachable old code, make "design it new" the recommended option and say the old app
  gives no rule to copy.
- A permission enum value that exists but is used nowhere (and is not in the seed payload) is not a
  half-built feature: the build ticket must seed it.
