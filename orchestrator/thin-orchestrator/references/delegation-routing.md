# Delegation routing: pick the cheapest route that can do the ticket

Applies when `delegate_task` offers an `option` per task (the `advanced-delegation` plugin, `model_map`
backend). Route names and models come from the profile's `delegation.backends.model_map`; the usual set is
`light` / `std` / `deep`. If the tool has no `option` parameter, skip this file.

## Choosing a route (decide per task, write it in the brief header: `route: std (why)`)
| Route | Use when | Never |
|---|---|---|
| `light` | The diff is fully specified by the brief: rename, move, mechanical edit across files, fixture or test-data update, running a scripted gate and summarising the log, reading files to answer one named question | New logic, anything needing a judgement call, anything that touches stored/posted values |
| `std` | A normal ticket: brief names files, a pattern file, invariants and acceptance tests, and gates will check the result | Tickets whose brief you could not make precise |
| `deep` | All code review; debugging where the cause is unknown; a ticket that must first trace or prove behaviour (every writer of a counter, every caller) before changing it; money or precision-sensitive changes; design or spec work; a task that already failed twice on a cheaper route | Mechanical work (it burns tokens for nothing) |

Default when unsure: `std`. Reviews are `deep` and never by the model that built the code, with one exception:
a diff that is purely a move, rename, comment or config change (no logic line added or changed; prove it with
`git diff --stat` and a read of the diff) whose gates are GREEN may be reviewed on `std`. Anything touching
logic, stored values, locking, permissions or SQL stays `deep`. A human instruction in chat overrides this.

## Escalation (never retry on the same route)
- Gates RED or report/diff mismatch on `light` -> one retry on `std`. On `std` -> one retry on `deep`.
- Two failed rounds in total -> stop and ask the human (the `thin-orchestrator` cap still applies).
- Log every escalation as one line on the board (`T4 light->std: reason`). If the same kind of ticket
  escalates twice in a run, route that kind one tier up from the start.

## Token discipline
- Write the brief ONCE, into its file (`runs/NN/build-brief.md`). The task `context` is a pointer of at most
  ~600 characters: route, brief path, report path, "not yours" file list, the one-line stop rule. Never copy
  the brief into `context`: that pays Opus output tokens twice for the same text.
- While a decision is parked on the human, plan and dispatch only what can run NOW (read-only scouting, other
  tickets). List later work as "after <decision>" without cutting briefs for it.
- A precise brief is the biggest saving: a cheap model with a precise brief beats a strong one with a vague
  brief. Spend your own tokens on the brief, not on reading code the worker will read anyway.
- Pass file PATHS and line ranges in `context`, never pasted file contents or logs.
- Put the whole ticket in the first message; do not drip-feed follow-ups to a running worker.
- Ask for a report of at most ~40 lines in a fixed shape: files changed, commands run with exit codes,
  test counts, NOT-VERIFIED list. Long narrative reports cost you tokens to read and add nothing.
- Independent tickets (disjoint files) go in ONE `delegate_task` call as a batch, each with its own route.
- Give each worker a stop rule ("stop and report if X") so a cheap model does not wander.
- Fresh worker per ticket; do not reuse a worker's context for the next ticket.
- Do not run a `deep` reviewer on a diff the gates have not passed yet; RED gates are cheaper to read.
- Read the `route` field of each result: if a task ran on a different model than you asked for, say so.

## Tally (one line per ticket in the report to the human)
`T4: build std, review deep, 1 retry (std->deep), est. relative cost 1+1+3`. Use relative cost (light=1,
std=3, deep=15 per equal-size call is a rough guide) so the human can see where tokens went and tune the rules.
