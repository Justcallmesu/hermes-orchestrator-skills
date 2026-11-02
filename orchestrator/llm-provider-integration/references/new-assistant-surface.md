# Adding a new surface (web chat bubble, widget) to an existing LLM assistant

Request shape: "make a chatbot bubble in the webapp that connects with the bot". The bot already has a
brain (LLM + MCP/tools + prompt + limits); the job is a second front door, not a second brain.

## 1. Grill first (one clarify form, recommended option = A)
- Q: what "connect with the bot" means: A same assistant (brain + tools, user's own permissions), own
  web conversation; B conversation shared with the other surface (needs server-side history store);
  C a link that opens the bot app.
- Q: who sees it: new permission vs every logged-in user. State the cost: a free LLM key is ONE shared
  quota across every surface and user.
- Q: which tenant/company it answers for: the one selected in the app (switch clears the chat) vs a
  picker in the chat.
- Q: history: last N in page memory (lost on refresh) vs browser storage vs DB (privacy + work).
- Q: if the user called the answers bad: fix quality first/in parallel vs build the surface only. Say
  plainly the new surface is exactly as smart as the existing one.
- Then ONE approval question summarising the design in plain words before tickets.

## 2. Verify the auth chain before designing
- Read what the tool server (MCP) accepts (often only a personal access token regex) and what the API
  treats as read-only (PAT path in the auth guard) vs the full session (cookie JWT).
- Never forward the webapp's session cookie/JWT to the tool server: it is not read-only.

## 3. Default technical design (PM decides, record as T-rows)
- **Server:** a short-lived, purpose-tagged read-only token for the web surface
  (`purpose` column, NOT NULL DEFAULT 'personal' so existing rows keep their meaning, new global
  migration with a gap above the newest). Endpoint on the cookie-auth, no-PAT controller, declared
  before `:id` routes; issuing revokes the user's previous web token; it does not count toward the
  personal-token cap (the cap counts only `personal`). Reuse the issue helper, do not duplicate it.
- **Chat service:** a second HTTP entry in the bot repo reusing the ask function; split config so it
  does not require the chat-app secrets (bot token, DB, enc key); system prompt passed as an option
  with a per-surface variant built from shared rules (old surface's prompt text byte-identical);
  error kinds mapped to HTTP (auth 401 -> client refetches token once, quota/rate 429 with
  Retry-After, busy 503, timeout 504, our own LLM key rejected -> 502 not 401, since a new user token
  cannot fix a bad server key); no message text or token in logs; same-origin via proxy, no CORS.
  - **Rate limit keyed on the USER, not the token:** the web token is re-issued on every page load,
    so a per-token budget resets on reload and does not protect the shared quota. Resolve the user
    with the API's `/auth/me` using the bearer, cache `sha256(token) -> userId` (bounded, ~10 min),
    and take a rate slot only after the user is known: a regex-only bearer check lets every made-up
    `etz_*` string add a limiter entry forever. Prune limiter keys older than the window.
  - **History is cut, never rejected:** keep the last N, then truncate each item. Answers have no
    length cap, so a per-item 400 makes one long answer block every later question until refresh.
  - Body limit enforced while streaming (413 + access-log line also for chunked bodies); client
    disconnect logged as aborted, not 500; abort the LLM call on disconnect if the ask accepts a signal.
  - Pino: never log an error field named `msg` (it clashes with pino's message key and the detail is
    lost); use `detail`.
  - Client-supplied assistant turns in history are acceptable when the token is the user's own
    read-only one and the tool server enforces tenant membership; say so in the README.
- **Server token route extras:** a per-user issue limit (e.g. 10/min) so a loop cannot mint fresh
  budgets. Copy an existing per-user in-service limiter (sliding window + `Retry-After`), not a
  controller-level guard: guards are often keyed by IP and cover every route of the controller; revoke only non-expired previous web tokens. One active
  web token per user means two tabs revoke each other: the client retries a 401 exactly ONCE.
- **Webapp:** floating button in the main layout only when a tenant is active; token held in memory
  only (not persisted), cleared on logout; dev-proxy path to the chat service; render answers as plain
  text (`white-space: pre-wrap`), never HTML, so no new markdown dependency or XSS sink.
  Client rules the reviews keep finding (put them in the brief):
  - record the account (user + impersonator) when a token request starts and discard the token if
    the account changed before it arrived; otherwise an impersonated session uses the admin's token;
  - only a 401 from the chat service triggers the token refetch; 502/503 keep the token and show the
    service's message ("retry later", not "log in again");
  - token-route errors show the server's message (e.g. a 429), not a generic "reload the page";
  - Enter-to-send ignores IME composition (`isComposing || keyCode === 229`, Safari needs the latter);
  - tenant switch clears the chat and aborts the in-flight request; keep drawer state in a child that
    unmounts when the tenant is lost;
  - dev-proxy target env uses `||` (an empty `.env` value must fall back), proxy key anchored
    (`^/assistant/`) in both `server` and `preview`.
- **Runner:** `run.sh chat` + proxy env, done by the PM after the code tickets.

## 4. Tickets and order
- Server token and chat service in parallel (disjoint repos); webapp after both report their exact
  contracts (route, request, response, status codes); runner last.
- Server API suites run on a throwaway DB copy on a spare port, never on the runner or main DB; the
  brief gives the copy/drop commands and says the old suite may be red for unrelated reasons.
- If the bot repo still holds another ticket's uncommitted change, say "build on top, do not revert"
  in the brief and record that both ship together in `decisions.md`.
- Dispatch the webapp build together with the fresh reviews of the server and chat-service tickets
  (it consumes their reported contracts read-only); steer it if a review changes a contract.

## 5. Tests that actually guard (put them in the briefs up front)
- Concurrent issue: fire ~6 parallel token requests, assert exactly one active web token and one
  working token; prove it by removing the row lock (the test must fail). Sequential calls never
  exercise the lock.
- "Tokens cannot call token routes": test with a GET that only the no-PAT decorator refuses. A POST
  check passes anyway because the read-only rule already returns 403, so it guards nothing.
- PM mutations for the chat service: drop the history trim, loosen the bearer regex; each must fail.
- Lock the old surface's system prompt with an exact-string test, since the new variant shares rules.
- Webapp without a unit runner: logic in small pure functions + a `node --test` script importing the
  shipped module (not a copy): 401 -> refetch -> retry once, second 401 surfaces the message, history N.

## 5b. PM end-to-end probe (before handing to the user for the browser check)
One script file, `bash <file>`, everything on spare ports so the runner/dev stack is untouched:
- copy the DB to a throwaway, reset the test admin password in the copy, run migrations there;
- start API, tool server, chat service and the webapp dev server with env overrides pointing at each
  other (no `.env` edits); wait on each port;
- a node probe logs in with the API test client (cookie + CSRF), issues the web token, then calls
  `<webapp>/assistant/chat` THROUGH the dev proxy: one simple question, one multi-step question, a
  fake token (expect 401), a write request (expect refusal); print statuses, latency and answer
  snippets, never tokens;
- grep the service logs for the token prefix (expect 0), kill the ports, drop the DB, confirm free.
Real answers expose quality gaps unit tests cannot (markdown despite a plain-text prompt, multi-step
questions hitting the tool-call cap and returning the fallback text): put them on the board as a
quality row and tell the user the new surface inherits them.

## 5c. User reports the generic "session could not be created" message
The client shows one text for every token-route failure without a usable message, so check the setup
before the code, read-only, in one script: listening ports of API / tool server / chat service /
webapp; the newest rows of the migrations table and whether the new column exists in the runner DB
(a 500 on insert = migration not run); the token route without a cookie through the API and through
the dev proxy (401/403 = route exists, 404 = old API build); `<webapp>/assistant/health` (502 = chat
service not running). Give the user the exact stop / migrate / start commands; never migrate their DB
yourself. If the user then says the copy is behind the target branch, follow `git-branch-integration`
(commit locally, merge the target in, renumber colliding migration/suite, gate, migrate commands).

## 6. Before merge
- Compare new global migration timestamps with every branch's migration dir (`git ls-tree
  --name-only origin/develop <dir>`): a feature branch cut earlier can reuse a timestamp already on
  develop/main and sort below develop's newest. Put a renumber row on the board as a merge-time call.

## Risks to list in the spec
- Production needs a reverse-proxy route to the chat service with a timeout above the question
  timeout (tool-server connect/close sit outside it; ~90 s).
- XSS could read the in-memory token; impact lower than the session it already has.
- Shared free quota: heavy use on one surface starves the other.
