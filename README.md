# hermes-orchestrator-skills

Orchestrator skills for Hermes, under git so every hand-written or auto-learned
change has a history. `CHANGELOG.md` records each change; add an entry in the same
commit as any skill edit.

## Layout

`orchestrator/<skill>/SKILL.md`, 14 skills, plus `profiles/` (see `profiles/README.md`):

| Skills | Origin |
|---|---|
| `thin-orchestrator`, `orchestration-run-hygiene`, `coding-agent-delegation`, `pm-discovery` | Own work (generalised from a private project profile) |
| `omh-*` (10 skills) | Third party, MIT: see `THIRD_PARTY.md` and `LICENSES/` |

## Install on a new device

1. Clone anywhere (example uses `~/src`):
   `git clone https://github.com/Justcallmesu/hermes-orchestrator-skills ~/src/hermes-orchestrator-skills`
2. In each profile's `config.yaml` (`~/.hermes/profiles/<name>/config.yaml`, or `~/.hermes/config.yaml`), set:
   ```yaml
   skills:
     external_dirs:
       - ~/src/hermes-orchestrator-skills/orchestrator
   ```
   Use `external_dirs`, not a symlink: Hermes's `skill_manage` does not find skills behind a
   symlinked directory ("not found"), but it does edit skills in an external dir, and the
   edit shows up as a git diff here.
3. Remove same-named copies from the profile's own `skills/` folder. A local skill wins a
   name clash, so a stale copy would hide the repo version.
4. Run `./check.sh`. It changes nothing and lists what is missing.

## Dependencies this repo does not contain

- **`omh` plugin**: required by `omh-autopilot`, `omh-ralph`, `omh-ralph-driver` (they call
  `omh_state` and `omh_gather_evidence`). Without it those skills load but cannot run.
  Install with `hermes plugins install omh` (curated catalog, community tier; review it first).
- **Skills**: `claude-code` and `to-tickets` (used by `coding-agent-delegation`); install them from the
  Hermes skills hub.
- **Profiles**: `developer` and `reviewer`, which `thin-orchestrator` launches with
  `hermes -p <profile> chat`. Persona files are in `profiles/`; credentials are not and are set per device.

## Keeping devices in sync

Skills can change on any device (including by the agent). `git pull --rebase` before a
session and commit + `git push` after one. Two devices editing the same skill produce a
normal merge conflict; resolve it in git.

## Known limits

- `hermes chat -q` / `-Q` one-shot runs hide `skill_manage`, so no auto-learn there. Use an
  interactive session (desktop, CLI, gateway) to have skills learn into this repo.
- Skills the agent creates new may land in the profile's own `skills/`, not here; `external_dirs`
  is for editing the existing ones. Move such a skill into `orchestrator/` by hand to track it.
