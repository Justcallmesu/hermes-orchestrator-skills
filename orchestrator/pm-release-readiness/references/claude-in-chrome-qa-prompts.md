# Writing browser-QA prompts for Claude Code + Claude in Chrome

The user runs browser QA himself by pasting a PM-written prompt into Claude Code with Claude in Chrome. Lessons from earlier QA runs:

- Copy each check's wording from the source step list verbatim; never paraphrase. A reworded check ("drawer at ~375px width" instead of "fits the viewport at a 375 px phone width") produced a false FAIL.
- Never let passwords reach the report, test accounts included: say "ask me to log in", and "never write any password into any file".
- One Chrome profile shares the login across tabs: two-user checks (409 races) need two Chrome profiles or a guest window, else mark BLOCKED.
- The Chrome tool reports only method/URL/status: request/response bodies must come from DevTools Payload/Response (or the user reads them out). Never infer a body from the UI.
- Demand strictness: PASS only if every part was observed; partial = NOT TESTED with the missing part named.
- Use a throwaway DB, verify the DB the running backend uses via `/proc/<pid>/environ` or `SELECT current_database()` (Nest boot log does not print it), allow only listed SQL, and log every statement.
- A second run reuses the first run's DB/accounts/doc numbers (point at its report sections), re-runs only idempotent seeders the new build needs (not users/roles), and checks branch ancestry (`git merge-base --is-ancestor <sha> HEAD`).
- Before writing a reversal/reject step, read the code for the real path.
- After a merge from main, add a section for screens the merge touched (menus, conflicted views) plus a crash-smoke of the other side's new screens.
- Save a pasted report into the run dir (it may not exist on disk) and turn FAILs/side findings into board rows.
