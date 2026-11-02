# Setting up a local runner from a handoff ("set this up for me")

A handoff note describes a side-by-side runner of several repos (API, webapp, extra services) on
feature branches, with its own ports and DBs. The note was written on another machine or session:
treat every path, DB name, IP and port in it as a claim to verify, not a value to copy.

## Procedure
1. **Probe before writing** (one read-only script, `bash <file>`):
   - the named folder exists? the named source DB exists (`psql -Atc "select datname ... "`)?
   - this machine's tailnet IP (`tailscale ip -4`) vs the IP in the note;
   - each repo: `git worktree list` (is the branch already checked out elsewhere?),
     `git ls-remote origin refs/heads/<branch>`; new repos via HTTPS `git ls-remote` (SSH may lack
     host keys and fail non-interactively);
   - ports in use (`ss -ltnp`) so the runner does not collide with the dev stack;
   - each repo's `.env.example`, `package.json` scripts, README run section, and how it loads env
     (some read `.env` via dotenv, others need `node --env-file=.env`).
2. **Decide deviations yourself** when the note's value cannot exist here (missing folder, renamed DB,
   other IP): pick the obvious local equivalent (runner folder next to the project, the real source DB,
   this host's IP) and list each in a "handoff says / this machine / used" table in the report.
3. **Write `bin/setup.sh` (idempotent) + `bin/run.sh <piece>` + `bin/smoke.sh` + README** in the runner
   folder. setup.sh order: code -> DBs -> env files -> deps -> migrations.
   - Code: `git worktree add --track -b <branch> <dir> origin/<branch>` for repos already cloned;
     `git clone -b <branch>` for repos that only exist remotely.
   - Copy DB: `createdb <new>; pg_dump --no-owner --no-privileges <src> | psql -q -v ON_ERROR_STOP=1 <new>`;
     the source is only read. Create a dedicated role/DB for a service that owns its own tables.
   - Env: copy the main repo's `.env`, then set only the keys that differ (port, DB name, public URL)
     with a replace-or-append helper; generate fresh secrets (`openssl rand -hex 32`) for DB passwords
     and encryption keys; `chmod 600`. Never overwrite an existing `.env` on re-run (guard with
     `[ -f ]`), so user-filled secrets survive.
   - Leave third-party secrets (bot tokens, LLM API keys) empty; `run.sh` refuses to start that piece
     until they are filled. They are the user's to enter, never typed by the agent.
   - Webapp for phones: run the dev server with `--host 0.0.0.0 --strictPort --port <p>` and point the
     server's frontend-URL setting at `http://<tailnet-ip>:<p>`.
4. **Smoke test**: start the non-secret pieces in the background, wait for the API port, probe one
   endpoint per behaviour the note claims (validation 4xx, token rejection 401/403, page reachable on the
   tailnet IP, webapp proxy -> API), then kill them and confirm the ports are free. Long setups
   (installs) exceed the 600 s foreground cap: let them run as a tracked background process and wait.
5. **Report**: deviations table, what exists (table), what the smoke verified, what is NOT verified,
   the user's to-do (secrets, start order), side effects (the branch is now locked to this worktree;
   the DB copy is a snapshot). Add the runner location to the memory project registry.

## Pitfalls
- When the user then asks "how to run it", answer from the runner README: secrets to fill first,
  one terminal per piece in order with the "ready when" log line, the end-user flow, and short
  troubleshooting (tailnet off, provider quota, missing key, one process per bot token).
- Follow-up code changes to a runner piece (e.g. a new LLM provider in the bot) go through the normal
  ticket flow: spec + decisions table under the project's `docs/<feature>/`, brief, worker, PM gates +
  mutation, fresh review. The runner's clones are real branches; never edit their `.env` from a worker.
- A branch can be checked out in only one worktree: putting the feature branch in the runner blocks it
  in the main checkout; say so.
- A dev stack already running on the default port (e.g. 3000) must not be touched; pick the note's
  offset ports and verify they are free.
- API test suites for a runner piece never run against the runner DB: briefs copy it to a throwaway DB
  (`pg_dump | psql`), start the API from the worktree on a spare port with env overrides
  (`APP_PORT=… DB_DATABASE=…`, never editing `.env`), reset the suite's admin password in the COPY only
  (a real-data copy has the real password), and drop the DB + stop the API at the end. Give parallel
  workers distinct DB names and ports (builder vs reviewer).
- Read only the needed keys from `.env` (`grep '^KEY=' | cut -d= -f2-`), never `source` it.
- When a feature adds a runner piece or a migration, extend `run.sh` in the same pass: a new piece
  (e.g. `chat`) with the same secret check as its sibling (check the key of the configured
  `LLM_PROVIDER`, not a hard-coded one), a `migrate` piece the user runs once, the README start list,
  and `bash -n` + the usage line as the check. Migrating the runner DB is the user's step.
