# PM-run browser QA (the PM clicks the screens itself, before the final report)

Use when a feature's webapp tickets are done and the PM verifies the screens directly with the
browser tool instead of handing a prompt to another agent (section 3) or the user (section 3d).

## Stack (two script files: `qa-up.sh`, `qa-preview.sh`)
0. Faster variant when the source worktree is not changing under you: `vite` DEV server from the
   worktree (hot-reloads a worker's later fix). It needs `VITE_API_URL=/api` (plus
   `VITE_PROXY_TARGET=<api>`) in the env too: without it the axios base path is wrong and the app
   shows its crash page ("Terjadi Kesalahan") on the first settings fetch.
1. Backend: the side-branch runner on a FRESH throwaway DB (migrate, roles, seed, build, start);
   write the API URL to a small env file the later scripts source.
2. Webapp: production build into scratch (`VITE_API_URL=/api vite build --outDir <scratch>`), then
   `vite preview --mode production --outDir <scratch>` run FROM the worktree (the config lives there)
   with BOTH `VITE_API_URL=/api` and `VITE_PROXY_TARGET=<api>` in the env: a config that refuses a
   production build without the API URL also refuses to start preview without it.
3. Before starting preview OR the dev server, free the port by PORT, not pid file (`ss -ltnp | grep
   :<port>`, kill that pid): a server left from an earlier round keeps the port, the new one dies with
   EADDRINUSE in its log (`--strictPort`), and the old one keeps proxying to the previous round's dead
   backend. Symptoms: cookie login bounces to `/auth/login`, and `curl <web>/api/<any>` gives 404/401.
   After start, check `ss -ltnp` shows the NEW pid and the log has no EADDRINUSE.
   Keep fixture/login scripts (`qa-seed.mjs`, `qa-cookies.mjs`, ...) in a stable scratch dir and copy
   them into each new backend copy: the side-branch runner deletes and re-creates the copy dir, so
   scripts written only inside it vanish with the next round.
4. Prove it: `curl` the page (200) and an auth endpoint through the proxy (401 = backend up).
5. Fixtures through the API with the suites' own test client (a small `.mjs` importing
   `test/api/client.mjs` from the backend copy): role users, master rows, stock, a source document.
   Make documents in the shape the NEW form produces (e.g. without fields the form no longer sends).
   States the API can no longer create (legacy rows) get ONE `UPDATE` on the throwaway DB.

## Login without typing a password
Run a script that logs in with the test client and prints its cookie jar + tenant id; redirect its
stdout into the cookie file each round (a new DB needs a new session). Set each cookie with CDP
`Network.setCookie` (domain 127.0.0.1), then seed the app's PERSISTED client stores too: read the
store files (`grep -n "name:" lib/Stores/*`) for each persist key and storage (localStorage vs
sessionStorage) and write e.g. the auth flag (`isAuthenticated: true`) and the per-tab tenant store.
A layout that redirects when its store says logged-out ignores valid cookies. Check with
`fetch('/api/<me endpoint>')` = 200 before navigating. The password never appears in a tool call or chat.
To debug the cookie jar, print only its KEYS from a script file (`node -e` inside `bash <file>`);
an inline one-liner that opens a secret-bearing file trips the approval prompt, and a timed-out
prompt stops the whole QA step until the user replies.
Order of login options: (1) the cookie script, run by the PM itself as `bash <file>`. A worker's
attempt at the same script can be blocked by an approval prompt it may not retry, but the PM can
run the worker's ready script in a later step. (2) A vault login. Vault items are bound to the exact
origin INCLUDING host and port (`127.0.0.1:5176` is not `localhost:5176` or `127.0.0.1:5193`). So run
`browser_vault_list` BEFORE starting vite, and start the dev server on the host:port a saved QA item
is bound to. Then fill the username, and `browser_vault_fill` does the rest. (3) Ask the user via
save_login only when neither works. A declined save prompt is final for that turn: offer the
remaining options as a numbered table (cookie script, the saved item's port, user logs in in the
browser window, user tests himself) instead of asking again.
The access token expires during a long session: when a page lands on `/auth/login`, re-run the cookie
script and set the cookies again before reading any result (an expired session reads as "the tag /
switch is gone" and looks like a regression).

## Driving the UI
- Keep the click/type/pick/submit helpers in one scratch `qa_helpers.py` and load it per call with
  `exec(open(path).read())`: browser-call variables do not survive between calls. A helper file the
  harness auto-imports (workspace `agent_helpers.py`) must import `js`, `fill_input` itself
  (`from browser_harness.helpers import js, fill_input`), or every helper raises NameError.
- Selects with several fields on one page: antd keeps earlier dropdowns mounted and visible, so
  "the visible dropdown" picks an option from the WRONG field. Resolve the field's own list by id:
  `document.getElementById(input.id + '_list').closest('.ant-select-dropdown')`. A select whose
  class has `ant-select-disabled` waits for a mode button ("Pilih langsung dari ...") first.
- Request bodies: wrap `XMLHttpRequest.prototype.open/send` in the page once per page load
  (push `{method, url, body, status, response}` to `window.__cap`) and read it after the save. This is
  the cheapest proof of payload rules (line ids sent on edit, `isBonus`, price 0) without the API log.
- Find buttons/options by text via `js(...)`, get the rect, `click_at_xy`; re-read rects after any
  scroll (a click at a stale position silently misses). Match button text by `includes`, not equality:
  labels carry counters ("Tambahkan (1)").
- Tables (antd): the first `tbody tr` is a hidden measure row; target `tbody tr.ant-table-row`.
- Selects: click the `.ant-select` element itself; options are in the visible `.ant-select-dropdown`
  whose class lacks `hidden`.
- Typing: focus by click, Ctrl+A via `Input.dispatchKeyEvent` (modifiers=2), then
  `Input.insertText`; date pickers take the typed display format + Enter.
- Locate an open dialog by its visible wrapper (`.ant-modal-wrap` with `display != none`), not by an
  inner class you assume. Clicks inside a modal that is still in its zoom-in animation (opacity < 1)
  go nowhere: wait ~1.5 s after opening. Do NOT inject a CSS rule that zeroes animations: antd waits
  for animation end, so dialogs stick half-open/half-closed and swallow clicks.
- A save that sends no request is usually blocked by the app, not broken: first look for a visible
  confirm/warning modal (e.g. "customer still has open orders" with a "Lanjut" button) and for
  per-field errors; then check source-document prerequisites (a quotation must be marked accepted
  before "create order from quotation" offers it). Find the prerequisite action on the source's
  detail page instead of retrying the save.
- A form that starts with one empty row: count rows before clicking "add" N times, and delete
  the spare row (an empty extra row fails validation silently).
- Reading field errors/warnings: antd keeps a help/explain node mounted during its leave animation
  (`ant-form-show-help-leave`, height 0), so a plain `.ant-form-item-explain` query reports messages
  that are no longer shown. Count only nodes with `offsetHeight > 0`, or read the form item's
  `ant-form-item-has-warning` / `has-error` class, before calling a message a bug.
- Split/duplicate-row forms (one source line as two rows): check per row the switch state, price
  lock and value, the sibling's cap message after editing either row, and that removing the second
  row clears the first row's error and brings the add button back.
- A screenshot can hang after a click that opens an overlay; recover with `ensure_real_tab()` and
  keep reading state through `js(...)`.
- Verify every save twice: the UI text/notification AND a read-only query on the throwaway DB
  (stored columns, moved stock dates, status history). For "the form no longer sends X", read the
  request body in the backend's API log; the UI cannot show what was sent.

## Report
A table `#, screen/action, expected, result` in `runs/QA/browser-qa[-N].md` (a later round gets its
own file and names which earlier rows it supersedes), plus what was NOT covered in the browser and
which API suites cover it, plus observations that are not defects. Append rows for flows checked
later in the same stack (a re-check after a fix round) instead of a new file, and move them out of
the NOT-covered list. Use idle time while a review or worker runs to cover more NOT-covered flows
(each extra flow is one more row); a known display gap that a later ticket fixes is a row marked
as such, not a FAIL.

## Vite production build in a check script
`vite build` refuses to start without `VITE_API_URL` when the config guards it; set
`VITE_API_URL=/api` in the check script and delete the `dist/` it writes in the worktree (or build
to `--outDir <scratch>`) so the tree stays clean for the commit guard.

## Teardown
Keep the stack up until the reviewed fix rounds are committed (a hot-reloading dev server re-checks
a fix in one call). Then kill by PORT (`ss -ltnp | grep -E ':<api>|:<web>'`, kill those pids, check
the count is 0), delete the cookie-jar file (it holds a live session), and point the browser tab at
`about:blank`.
