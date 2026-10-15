# Profiles

`SOUL.md` and `profile.yaml` for the three profiles the orchestrator skills expect:

| Profile | Role | Used by |
|---|---|---|
| `pm` | plans, decides, dispatches workers; writes no code | you talk to it |
| `developer` | builds one ticket from a brief | `thin-orchestrator` (`hermes -p developer chat`) |
| `reviewer` | attacks a diff; edits nothing | `thin-orchestrator` (`hermes -p reviewer chat`) |

Only these two files per profile are kept here. Config, credentials (`.env`, auth) and memories stay
on the machine and are never committed. All three read the project's own `PROJECT.md`, so nothing
here is project-specific.

## Create one on a new device

```bash
hermes profile create developer --no-alias --no-skills
cp profiles/developer/SOUL.md   ~/.hermes/profiles/developer/SOUL.md
cp profiles/developer/profile.yaml ~/.hermes/profiles/developer/profile.yaml
hermes -p developer setup        # provider + credentials, per device
```

Then add the repo to that profile's `skills.external_dirs` (see the root README) and run `./check.sh`.
