# OpenCode: Zen vs Go (same key, different products)

One OpenCode API key (`oc_sk_...`) can work on one surface and fail on the other. Probe both before
concluding a key is bad or unfunded.

| | Zen (pay per request) | Go (subscription) |
|---|---|---|
| Base URL (OpenAI chat) | `https://opencode.ai/zen/v1` | `https://opencode.ai/zen/go/v1` |
| Billing | account credit balance | monthly Go allowance (`billing_source: "go"`, cost 0 per call) |
| Required extras | none | `x-opencode-session` header (stable id per conversation) + own `User-Agent` (e.g. `my-app/1.0`) |
| Typical failures | 402 "Insufficient account funds" (key valid, no credit); 401 "Invalid credential" (bad key) | 400 `MissingSessionID` without the header |
| `*-free` models | 429 FreeUsageLimitError outside the OpenCode app | n/a |

## Diagnose "works in my agent, not in the app"
1. Probe with the key read via `node --env-file=.env` (never print it): Zen `/chat/completions`, and a
   bogus key for contrast (402 vs 401 tells funded-vs-valid apart).
2. Probe Go `/models` (lists the Go model ids) and `/chat/completions` with and without
   `x-opencode-session`. Coding agents (Hermes, Claude Code, Codex) already send it, which is why the
   same key "works" there.
3. OpenCode docs say Go is meant for coding agents and traffic is monitored: using it for a non-coding
   app (ERP chat) is a business/terms decision for the user, not a technical default. Offer
   Zen credit (recommended), Go (demo only), or another provider.

## Wiring Go with the AI SDK (`@ai-sdk/openai-compatible`)
- Separate provider value (`opencode-go`) rather than a flag, so switching is one `.env` line.
- Session header per call: `generateText({ headers })` from a per-conversation hash
  (sha256 of app prefix + user + tenant, first 32 hex) so no raw ids go on the wire; send it ONLY for Go.
- The provider-level `User-Agent` is overwritten by `generateText` (`ai/x.y`); prepend yours with a small
  fetch wrapper. Wire value then: `my-app/1.0 ai/... ai-sdk-provider-utils/... node.js/...`.

## Related pitfalls
- Any launcher script that pre-checks "the chosen provider's key" must list every provider explicitly and
  fail on unknown values; a `*)` fallback to one provider asks for the wrong key when a new provider is added.
- A model's answer to "what model are you?" is not evidence (DeepSeek answered "Claude" and "ChatGPT").
  Verify from the API response `model` field and the service's startup log; recommend an explicit
  identity line in the system prompt.
