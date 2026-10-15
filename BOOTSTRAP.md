# Bootstrap on a new device

Install and configure Hermes first (`hermes setup`, provider + credentials). Then paste the
prompt below into a Hermes chat. It sets up this repo; you approve each step that changes something.

````text
Set up https://github.com/Justcallmesu/hermes-orchestrator-skills on this machine.

1. Clone it to ~/src/hermes-orchestrator-skills (if it exists, `git pull --rebase`). Read its
   README.md, BOOTSTRAP.md and profiles/README.md.
2. Run `./check.sh default pm developer reviewer` and show me the output. It changes nothing.
3. Propose a plan for every MISS line, then wait for my yes before changing anything. Allowed fixes:
   - Add `skills.external_dirs: [~/src/hermes-orchestrator-skills/orchestrator]` to the config.yaml of the
     profiles I name. Edit only that key; keep every other setting.
   - Create missing profiles `pm`, `developer`, `reviewer` with `hermes profile create <name> --no-alias
     --no-skills`, then copy profiles/<name>/SOUL.md and profile.yaml into them.
   - Remove same-named skill folders from a profile's own skills/ ONLY if check.sh reports them as
     duplicates; tar them to ~/hermes-skill-backup-<date>.tgz first.
   - Install the missing skills `claude-code` (bundled with Hermes; run `hermes skills list`) and
     `to-tickets` (Matt Pocock's pack, `hermes skills search to-tickets`; show me the source before installing).
4. Never: print or copy API keys, .env, auth files or memories; edit a profile I did not name; install the
   `omh` plugin (ask me first, it is third-party code with hooks); push to any git remote.
5. When done, run ./check.sh again and report what still fails. Tell me to run `hermes -p developer setup`
   (or equivalent) myself for each new profile's credentials.
````

## What stays manual

- Provider credentials, per profile and per device.
- The `omh` plugin: `omh-autopilot`, `omh-ralph` and `omh-ralph-driver` need it. Decide on your own; check
  the plugin first (`hermes plugins show omh`, community tier).
- Real profile configs and memories are not in this repo.

## Not yet verified

The prompt has not been run on a clean machine. The first run is the test: report what `check.sh` says.
