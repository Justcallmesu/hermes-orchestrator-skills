# QA stack on a copy of the dev DB (owner checks with real data)

Use when the owner wants to click through a feature branch with his own data instead of a seeded
throwaway DB. The source dev DB is only read (`pg_dump`); every write goes to the copy.

## Script order (`qa-up.sh`, idempotent, `FRESH=1` re-copies)
1. Load the worktree backend `.env` with errors tolerated: `set +e; set -a; . ./.env >/dev/null 2>&1;
   set +a; set -e`. A `.env` with a line the shell can't parse kills a `set -e` script silently, before
   it prints anything.
2. Pick the source by size and freshness, read-only (`pg_database_size`, row counts of the feature's
   tables, `max(created_at)`); an empty `.env` DB is not the dev data.
3. `createdb <qa>` then `pg_dump --no-owner --no-privileges <src> | psql -d <qa>` WITHOUT
   `ON_ERROR_STOP` (one harmless dump warning would abort the restore); print `grep -c ERROR` of the
   restore log instead.
4. Prepare the copy (`qa-prepare-copy.sh`, guarded to the QA DB name), then start the backend with
   `DB_DATABASE=<qa> DB_SYNCHRONIZE=true APP_PORT=<free>`, BEFORE the seeders: the seeders boot the app
   and need the branch's new columns. Wait on an auth endpoint until it isn't `000`.
5. Run only the idempotent seeders (permissions, roles). Assert the result in SQL (new permission
   row exists, new columns in `information_schema.columns`, which roles got the permission).
6. Start vite with `VITE_PROXY_TARGET=<backend>`. Read `vite.config.ts` for the proxy PREFIX (e.g.
   `/api` rewritten away) and probe `<app>/<prefix>/v1/auth/me` -> 401. A 200 on an unprefixed path
   is the SPA's index.html fallback, not the backend.
7. Call binaries by absolute path from the worktree (`$WT/backend/node_modules/.bin/nest`, `ts-node`,
   `vite`). With symlinked `node_modules`, `yarn <script>` / `npx` may not resolve the bin.
   Background processes go inside the script file (`nohup ... &` + pid file); the terminal tool
   refuses a foreground `&`.

## Restarting the backend after a schema ticket lands
The running backend must restart for synchronize to add the new column/FK. Do it from a
`qa-restart-be.sh` that stops by PORT, not only by pid file:
- The pid file holds the `nest start` wrapper; killing it can leave the compiled `node dist/main`
  child holding the port. The new start then compiles (~60 s with swc + typeCheck) and dies with
  `EADDRINUSE`, while the OLD process keeps answering, so an early `401` proves nothing.
- Stop every pid from `ss -ltnpH "sport = :<port>"` whose cmd contains the worktree path (refuse to
  kill a foreign process), wait until the port is free, then start.
- Prove it after start: `ps -o etime` of the pid now on the port is seconds old, the log has no
  `EADDRINUSE`/`QueryFailedError`, and the new column + FK delete rule exist in
  `information_schema` (`columns`, `referential_constraints.delete_rule`).
- Put the same by-port stop into `qa-down.sh`.

## Stale dev data blocks synchronize
An older dev DB holds enum values the branch no longer has (renamed permission groups, codes from
dead branches); synchronize then crashes with `invalid input value for enum`. Fix it on the copy
only, while the column is still the enum:
- `ALTER TYPE <enum> ADD VALUE IF NOT EXISTS '<new>'` (own statement, outside the transaction),
  then `UPDATE` rows from the old value to the new one.
- Delete rows whose code is not in the code's enum: extract the enum values from the `.ts` file with
  a small Python regex into a file, `\copy` it into a temp table, delete join-table rows first (find
  them via `pg_constraint where confrelid = '<table>'::regclass`), then the rows, in one transaction.
- Never `ALTER COLUMN ... TYPE text` to clean up: synchronize sees a type change, drops and re-adds
  the column, and the NOT NULL add fails on existing rows. If you did, re-copy with `FRESH=1`.
- Tell the owner the dev DB itself has the same stale rows: booting `main` on it with synchronize
  fails the same way.

## Hand-over
URL, which DB is used and that the source/dev/prod DBs are untouched, which role holds the new
permission on the copy, the check file and its new steps, and that the stack keeps running until he
says done (`qa-down.sh`, drop the copy only on request). Record the stack and its scripts in
`STATUS.md`. A frontend `.env` created in the worktree must be git-ignored (`git check-ignore`).
