---
name: llm-provider-integration
description: "Use for an app's LLM provider/key or a new assistant UI."
---

# Choosing and wiring an LLM provider into an app (bot, assistant, MCP client)

Covers: "use Claude OAuth like Hermes", "what free API key can I use", "Gemini keeps failing",
"add provider X". The user wants the reasoning and a clear recommendation; the business/cost call is theirs.

## 1. Answer the auth question first (terms before code)
- Subscription OAuth (Claude Free/Pro/Max/Ultra) is only allowed in Claude Code / Claude.ai. A product
  or bot serving other users through one person's subscription violates the Consumer Terms and risks
  the account. Cite https://code.claude.com/docs/en/legal-and-compliance, refuse to build it, and offer
  the API-key path. Do not claim how Hermes itself authenticates unless you checked.
- The Claude API has no free tier (paid usage tiers with spend caps). Say so plainly; do not promise
  trial credit you could not verify.

## 2. Free/demo options: present as a table (cost, limits, training use, code change)
- **Try a different model on the same key before any code change**: free limits are per model, and a
  `-lite` model often has more headroom. List what the key can use, without printing the key:
  `curl -s "https://generativelanguage.googleapis.com/v1beta/models?key=$K&pageSize=200" | grep -oE '"name": "models/[^"]*"'`
  (read `K` from `.env` with `grep '^KEY=' | cut -d= -f2-` inside a script).
- Groq free (check console.groq.com/docs/rate-limits for current numbers): high RPM but a small
  tokens-per-minute budget; an agent loop (tool schemas + history + several tool steps) can exhaust it
  in 2-3 questions. One request over the TPM budget -> 413; several summing past it in a minute -> 429.
- OpenRouter `:free` models: many models, variable tool-calling quality; verify limits before quoting.
- Every free tier may use prompts for training: demo/test data only; real company data needs a paid
  project (paid Gemini or Claude API keep data out of training).
- Ask what actually fails (busy/quota vs slow vs wrong answers): limits are fixed by plan/model;
  wrong answers are model quality and a free model won't fix them.

## 3. Making the provider switchable (Vercel AI SDK pattern)
Design decisions to put in the spec (technical, PM decides):
- `LLM_PROVIDER=<a|b>` enum, default = today's provider so the existing `.env` is unchanged.
- Only the chosen provider's key is required; the missing-key error names the variable, never a value.
- `LLM_MODEL` optional; empty resolves to a per-provider default. `.env.example` ships it EMPTY with a
  comment, and the README says to clear/change it when switching (a leftover model id from the old
  provider makes every request 404 -> generic error).
- Log `{provider, model}` once at startup (no keys) so a wrong pairing is diagnosable.
- One tiny `createModel(cfg)` switch passing the key explicitly (`createGroq({ apiKey })`), not ambient env.
- Map the new provider's HTTP statuses into the existing error classes (413 -> quota) with tests.
- Pin the new `@ai-sdk/<provider>` to the version that shares the installed `ai` core's
  `@ai-sdk/provider` / `provider-utils` versions (check with `yarn why @ai-sdk/provider`); the newest
  release of the same major can pull a newer provider package and break typecheck. Find it by scanning
  `https://registry.npmjs.org/@ai-sdk/<pkg>` `versions[*].dependencies` for the exact installed
  provider/provider-utils versions (often exactly one match), then `yarn add <pkg>@<v> --exact`.
- OpenAI-compatible gateways (OpenCode Zen, etc.): `createOpenAICompatible({ name, baseURL, apiKey, fetch }).chatModel(id)`;
  base URL from env with a default, trailing slash stripped; test the request URL `<base>/chat/completions`,
  bearer header, body `model`, and that a tool goes out as OpenAI `tools`.
- Custom User-Agent with AI SDK v7: a provider-level `headers: {'User-Agent': ...}` is LOST, because
  `generateText` sets its own per-call `user-agent: ai/<v>` and `combineHeaders` lets it win. Prefix
  ours in a `fetch` wrapper (read the final `user-agent`, set `ours + ' ' + sdk`) and assert the wire UA
  with a stub fetch. Per-request headers (session ids) go via `generateText({ headers })`; one helper
  `requestHeadersFor(provider)` returning `undefined` for others keeps entries free of provider checks.
- Pick the default model id from the gateway's LIVE catalog (`GET <base>/models`, list ids, grep the
  family), not its docs table: docs keep retired ids that 404. Prefer the paid id over a `-free` one
  when the docs say free models only work inside the vendor's own app; mark that ASSUMED until a real
  key confirms, and mention the free id in `.env.example` as an option.
- The user wants every provider's model chosen the same way: the shared `LLM_MODEL` env, no
  per-provider model variable. `.env.example` carries a commented block per provider
  (`# LLM_PROVIDER=x`, `# LLM_MODEL=<id>`, `X_API_KEY=`, optional base URL) and the `LLM_MODEL`
  comment lists each provider's default; add a test that `LLM_MODEL` overrides the default.

## 4. Gates that catch the real bugs
- Run tests + typecheck yourself; mutation-check the new error mapping.
- Require a test that FAILS if the two providers' keys are swapped in `createModel` (fake `fetch`,
  assert the auth header per provider): typecheck and unit tests on `provider`/`modelId` don't catch it.
- Fresh reviewer checks: provider-switch config pitfalls, tool JSON-schema compatibility with the new
  provider (strict mode, unsupported keywords), key leakage, version pin.
- PM startup smoke (no key needed): run the entry with the new provider and an empty key, with the
  entry's other required env set (MCP/API URLs) or zod reports those first and hides the key check;
  expect the error naming the key var. Then a dummy key: expect the `{provider, model}` startup line,
  `LLM_MODEL=<other>` changes it, and `grep -c <dummy>` on the log is 0.
- Grep the WHOLE workspace for every place that maps provider -> key, not just the app: runner/start
  scripts (`bin/run.sh` pre-start key checks), deploy env templates, docs. A shell `case` with a
  `*)` fallback to the old provider silently demands the wrong key for the new one. Name every
  provider explicitly and make an unknown value a clear error; test the script against temp `.env`
  copies (new provider with the other keys empty, missing key, typo).
- Mark as NOT verified until a live key runs a real tool loop: model tool-calling quality, real
  rate-limit responses.

## 4b. Diagnosing "the key fails here" / "the key works in my other tool"
- Probe from a scratch `.mjs` run as `node --env-file=.env probe.mjs` inside the app dir: the key is
  read from `.env`, never printed (replace it in any echoed body), and a pasted-in-chat key is
  refused (ask the user to put it in `.env`, suggest rotating it).
- Send the same request with the real key AND a bogus key: bogus -> 401 "invalid credential" while
  the real one gets 402/429/400 proves the key is valid and the problem is billing, plan or routing,
  not the key or the code.
- Read the error `type`/message literally before theorising: "insufficient funds" = no balance on
  that billing surface; "free usage limit / only within <vendor app>" = free tier blocked for
  third-party clients; "missing <header>" = a subscription surface with client requirements.
- "Works in my agent/IDE" usually means a different product surface of the same vendor (subscription
  plan vs pay-per-request) with its own base URL, model ids and required headers. Find the other
  surface's base URL, list its `/models` with the key, and retry with the headers its error names.
- Before wiring a subscription surface into an app, read the vendor's "where can I use it" terms:
  coding-agent subscriptions often exclude other traffic. Present it as a user choice (top up
  pay-per-request recommended / use the subscription with the stated account risk, demo only /
  free fallback provider) and record the pick in the spec.
- Gateway-specific facts (OpenCode Zen vs Go, session header, per-call headers wiring):
  `references/gateway-surfaces.md`.

## 4c. "Is it really using model X?" and switching the live provider
- Answer from evidence, not from what was built: active (uncommented) `LLM_PROVIDER`/`LLM_MODEL`
  lines in `.env`, whether the key line is active, and each running entry's start time vs the
  `.env` mtime (`ps -o lstart= -p <pid>`, `stat -c %y .env`; find the entries by port with
  `ss -ltnp` and by `readlink /proc/<pid>/cwd`). An entry started before the last `.env` save still
  runs the old provider. The `{provider, model}` startup log line is the final proof.
- When the user says "do it yourself" (away), switch `.env` with a script: copy to
  `.env.bak-before-<x>` (0600), comment out the old active provider/model lines, uncomment the
  existing key line (assert exactly one), insert the new provider/model lines, then print only
  per-variable active counts (`KEY=<set>`), never values. Restart EVERY entry that reads the file
  (web chat AND Telegram bot): kill by port/cwd, start with `nohup node --env-file=.env ...`, and
  confirm the startup line plus `grep -c <key prefix>` = 0 on the log. Tell the user the backup path
  and the restore steps.
- Live end-to-end needs a login; if the local admin password is not the test default, do not guess:
  run the same E2E on a throwaway DB copy with the chat entry overridden by env
  (`LLM_PROVIDER=... LLM_MODEL=...` before `node --env-file=.env`; process env wins over the file)
  and say the live bubble itself was not exercised.

## 5. Adding another surface to the assistant (web chat bubble, widget)
Grill questions, auth chain check, default design (short-lived purpose-tagged read-only token, chat
service reusing the ask function, rate limit keyed on the user not the token, history truncated not
rejected, plain-text rendering), tests that really guard, and ticket order:
`references/new-assistant-surface.md`.

## Handoff to the user
- Key page URLs (e.g. aistudio.google.com/api-keys, console.groq.com/keys); the user pastes keys into
  `.env` themselves, never in chat; tell them to revoke keys that were exposed.
- Give the exact `.env` lines for the switch (provider + model + key) and when to restart.
