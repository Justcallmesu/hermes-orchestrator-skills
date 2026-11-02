# Changelog

Every change to a skill gets an entry, newest first, naming the file. Skills are loaded by Hermes through
`skills.external_dirs`, so edits (by hand or by `skill_manage`) appear as git diffs here: add the entry in the
same commit. Mark an entry **action** when a profile or machine must do something after `git pull`.

Format: version, date, one line per change.

## 0.6.0 - 2026-11-02

- 25 new skills from the `pm` profile: `pm-feature-work`, `pm-release-readiness`, `pm-workspace-resume`,
  `parallel-ticket-waves`, `git-branch-integration`, `git-commit-in-dirty-tree`, `revert-merged-change`,
  `approval-safe-shell-runs`, `legacy-port-progress-audit`, `codebase-bug-hunt`, `codebase-data-flow-tracing`,
  `explain-system-behavior`, `flaky-test-triage`, `service-unresponsive-triage`, `frontend-ui-layout-bugs`,
  `api-input-validation`, `postgres-concurrency-guards`, `event-anchored-time-windows`,
  `field-removal-across-stack`, `derived-totals-design`, `ledger-posting-design`, `deploy-data-scripts`,
  `document-gate-placement`, `printed-document-layout-changes`, `llm-provider-integration`. Project names
  generalised; project-specific skills stay local. **action**: on a machine that already has these in a
  profile's own `skills/`, run `./check.sh` and remove the duplicates so the repo version loads.
- `orchestration-run-hygiene`: branch check before a new feature's first commit, long-job supervision
  (8b), merging long-diverged branches (8c).

## 0.5.0 - 2026-10-15

- `BOOTSTRAP.md`: paste-in Hermes prompt that clones the repo, runs `check.sh`, and fixes each MISS after
  approval (guardrails: no secrets, no other profiles, no `omh` plugin, no push). Not yet run on a clean machine.

## 0.4.1 - 2026-10-15

- `profiles/*/SOUL.md`: removed the "Teaching" section (author-specific). Live profiles on the author's machine are unchanged.

## 0.4.0 - 2026-10-15

- New skill `pm-discovery` (needed by `thin-orchestrator`), copied from the `pm` profile; example
  paths and the "Logistic"/"v9 §8" references generalised.
- New `profiles/`: `SOUL.md` + `profile.yaml` for `pm`, `developer`, `reviewer` (no config, credentials
  or memories). `pm` description no longer names a project.
- `check.sh`: `pm-discovery` is no longer an external dependency.

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
