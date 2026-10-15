# Changelog

Every change to a skill gets an entry, newest first, naming the file. Skills are loaded by Hermes through
`skills.external_dirs`, so edits (by hand or by `skill_manage`) appear as git diffs here: add the entry in the
same commit. Mark an entry **action** when a profile or machine must do something after `git pull`.

Format: version, date, one line per change.

## 0.3.0 - 2026-10-15

- Repo (no skill content changed): README rewritten with install steps for a new device
  (`skills.external_dirs`, not a symlink), dependencies, sync habit and known limits.
- `check.sh`: read-only setup check (external_dirs, duplicate local copies, required skills, `omh`
  plugin, `developer`/`reviewer` profiles).
- `THIRD_PARTY.md`: the 10 `omh-*` skills are MIT, from witt3rd/oh-my-hermes @ 3b06e33a.

## 0.2.0 - 2026-10-15

- `thin-orchestrator`: new `decisions.md` section; resume step 1 now reads `decisions.md` first. Chat-only
  decisions (pause, skipped checks, ordering) are appended as one line each so a fresh session sees them.
- `orchestration-run-hygiene` (sections 3, 4): standing approval grants and pauses/resumes are recorded in
  `decisions.md`.
- Idea taken from LastNyx/hermes-dev-team (`decisions.md`, `CHANGELOG.md`); not copied, no code reused.

## 0.1.1 - 2026-10-15

- `omh-triage`: removed references to `role-triage-maintainer.md` / `role-triage-skeptic.md`, which never
  existed (role behaviour is defined by the Phase 1 dispatch goals).

## 0.1.0 - 2026-10-15

- Generalised for any project: dropped project-, database-, test-runner-, formatter- and model-name specifics from
  `thin-orchestrator` and `orchestration-run-hygiene`. Money-ticket rules moved to
  `orchestration-run-hygiene/references/precision-sensitive-tickets.md`.
- Initial import of 13 orchestrator skills from a Hermes profile: `omh-*` (10), `thin-orchestrator`,
  `orchestration-run-hygiene`, `coding-agent-delegation`.
