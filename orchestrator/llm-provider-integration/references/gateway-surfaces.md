# Gateway product surfaces and their client requirements

## OpenCode (one account, one key, two billing surfaces)
| | Zen (pay per request) | Go (subscription) |
|---|---|---|
| Base URL (OpenAI chat models, e.g. DeepSeek) | `https://opencode.ai/zen/v1` | `https://opencode.ai/zen/go/v1` |
| Billing | account balance; 0 balance -> 402 "Insufficient account funds" | subscription allowance (`usage.opencode.billing_source: "go"`) |
| Model list | `GET <base>/models` (live; docs table keeps retired ids) | `GET <base>/models` with the key |
| Required headers | Bearer only | Bearer + `x-opencode-session: <stable id per conversation>` (else 400 `MissingSessionID`) + own `User-Agent` (e.g. `my-app/1.0`, not the SDK default) |
| Intended use | any client | coding agents; traffic monitored for abuse (risk to the account for other uses) |

- `-free` models answer 429 `FreeUsageLimitError` ("Free models work in OpenCode") from third-party
  clients: do not default to them.
- A key that "works in my coding agent" but 402s in the app is almost always a Go key used against
  the Zen base URL.

## Wiring a per-conversation header with the Vercel AI SDK
- Static headers go on the provider (`createOpenAICompatible({ name, baseURL, apiKey, headers, fetch })`),
  EXCEPT User-Agent: `generateText` overwrites it per call, so prefix it in a `fetch` wrapper (see
  SKILL.md §3) and assert the wire value with a stub fetch.
- Per-conversation headers go per call: `generateText({ ..., headers })`. Give the shared ask
  function an optional `requestHeaders(args)` hook; the entries set it only for the provider that
  needs it, decided by ONE helper (no provider checks duplicated across entries).
- Session id = hash of stable conversation keys (e.g. first 32 hex of sha256 of
  `<app>:<userId>:<tenantId>`), never raw user ids on the wire; same user+tenant -> same id.
- Make it a separate provider value (e.g. `LLM_PROVIDER=opencode-go`) sharing the key and
  `LLM_MODEL`, not a flag on the existing one: switching stays one `.env` line and the other
  surface's behaviour is untouched. Tests assert the header is present for that provider and ABSENT
  for every other provider, and update the runner script's provider->key map.
