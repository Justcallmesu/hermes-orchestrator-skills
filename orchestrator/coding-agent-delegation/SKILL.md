---
name: coding-agent-delegation
description: "Dispatch coding tickets to a CLI agent; verify the output."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [Coding-Agent, Delegation, Verification, Tickets, Claude-Code, Codex, OpenCode]
    related_skills: [claude-code, codex, opencode, to-tickets]
---

# Coding-agent delegation — dispatch and independently verify

## When to use

The user asks to dispatch/delegate a ticket or spec to a coding CLI (Claude Code,
Codex, OpenCode), wants a multi-ticket set implemented across one or more agent
sessions, or wants to watch/monitor an agent working on code. Pairs with `to-tickets`
(which produces the tickets this skill dispatches) and the tool-specific skill
(`claude-code`/`codex`/`opencode`, which has that CLI's own flags/modes).

For orchestrating an autonomous coding CLI (Claude Code, Codex, OpenCode, etc.) to
implement a ticket, and for the verification discipline around it. The tool-specific
flags/modes live in that tool's own skill (`claude-code`, `codex`, `opencode`) — this
skill is the judgment layer on top: how to dispatch without scope drift, and how to
confirm the work actually landed before relaying anything to the user.

## Core principle

**A coding agent's own "done"/"all tests pass"/"all green" report is a self-report,
not a verified fact.** Never relay it to the user as fact. After every dispatch:

1. `git log --oneline -5 <branch>` — confirm a real commit landed where expected.
2. `git show <commit> --stat` — confirm the right files changed, nothing stray.
3. Read the actual diff for the core logic change (not just the file list) and check
   it against the ticket's own checklist line by line.
4. Re-run the project's real build/typecheck/test commands yourself, in your own
   terminal call — do not accept the agent's own report of these as sufficient.
5. Only after 1-4 pass, tell the user it's done.

This catches real divergences, not hypothetical ones: a session can hit
`error_max_turns` from a print-mode run yet have the actual code already complete
and correct (it just ran out of turns before printing the closing summary) — and in
the other direction, a "summary of what I built" can quietly omit a piece of the
approved plan with no flag at all until the omission is caught by inspection. Exit
code / `subtype` and real state can disagree in either direction; only reading the
diff and rerunning the commands settles it.

## Dispatch mode selection

- **Print mode (`-p`) via `terminal(background=true, notify_on_complete=true)`** —
  default choice when you (the orchestrator) will poll/verify the result yourself and
  the user doesn't need to watch it live. Simpler than tmux, no dialog handling.
- **tmux, interactive, no `-p`** — only when the user explicitly wants to watch the
  agent work in their own terminal pane, or the task needs multi-turn steering
  (plan-approval prompts, mid-task course correction). Check `which tmux` and
  `tmux list-sessions` first — if the user says they "already have it open" in a
  session, find that session (`tmux list-panes -a -F '#{session_name}:#{window_index}.
  #{pane_index} #{pane_current_command} #{pane_current_path}'`) and send into it
  rather than starting a second, duplicate session.
- A background driver (headless Chrome, `computer_use`, etc.) for "let me watch" style
  requests is a different axis entirely from tmux — if the user wants to *see* browser
  automation, ask once whether headless-screenshots-in-chat or driving their actual
  visible browser is wanted, rather than assuming; a Wayland desktop may not support
  direct window capture for the latter, which only becomes visible by trying.

## Scope control (the single easiest thing to lose)

- State the scope boundary explicitly in the dispatch prompt ("implement ONLY ticket
  N, do not start ticket N+1") AND re-state it verbatim on every follow-up dispatch in
  the same session — a long-running agent session drifts into adjacent tickets or
  unprompted "research" between tasks on its own initiative, especially once several
  tickets have landed in the same pane and it has momentum. Catch this with a pane
  snapshot before assuming it stayed in scope; don't just trust the last instruction
  carried forward.
- When a plan-approval gate appears (e.g. Claude Code's plan mode presenting a written
  plan before executing), read the full plan file before approving — approve only
  when every planned file/change traces back to the ticket's own checklist. Do not
  rubber-stamp just because a plan exists; a plan can itself have silently dropped a
  checklist item (catch it the same way you'd catch it in the final diff).
- When a dispatched agent proposes extending scope mid-task ("I also need to touch
  file X in a different module/repo to make this work"), make the call explicit and
  narrow in your own next instruction rather than letting it decide unsupervised —
  name exactly what's approved and what stays excluded.

## Resuming a session

`--resume <session-id>` only works while that session is still paused on a real
tool-permission prompt. If it already answered via a plain text question or printed a
summary, `--resume` fails with "No deferred tool marker found in the resumed session."
Don't retry resume in a loop — start a fresh dispatch with the decision folded
directly into the new prompt instead.

## Ticket location when the user doesn't want planning data committed

When a project has its own ticket-writing convention (e.g. `.scratch/<slug>/spec.md` +
`issues/NN-<slug>.md` inside the repo) but the user doesn't want that data committed,
mirror the SAME structure into a sibling directory one level outside every affected
git repo (e.g. a `docs/<feature>-tickets/spec.md` + `issues/` next to, not inside, the
repos) rather than inventing a different format. The knowledge-doc / spec half (prose,
not task-tracking) can still live inside the repo under its own `knowledge/` convention
if the project has one and auto-reads it — only the ticket checklist files themselves
need to move out.

## Environment pitfall: package manager not on PATH

A forked non-interactive shell often doesn't source the project's version-manager init
script, so `yarn`/`npm`/`node` resolve to nothing even though they work fine in the
user's own terminal. Before running any project build/test command yourself (step 4
of Core principle), source the relevant init script first, e.g.
`source /usr/share/nvm/init-nvm.sh 2>/dev/null; yarn ...` for nvm-managed projects (or
the equivalent `asdf`/`rbenv`/`pyenv` shims) — don't conclude the tool is missing from
a bare `which yarn` failure in your own shell.
