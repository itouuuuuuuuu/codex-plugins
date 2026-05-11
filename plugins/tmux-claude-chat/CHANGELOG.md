# Changelog - tmux-claude-chat

## [1.0.1] - 2026-05-11

### Skill (`SKILL.md`)

- Clarified that completion detection is hook-driven and keyed by the latest user message plus a pending-file gate.
- Documented the intentional approval-watcher polling cadence difference from the mirror `tmux-codex-chat` skill.
- Added explicit direct-send limits, recovery notes for approval/timeout paths, a cleanup section, and a common wait command.
- Expanded fallback UI polling warnings so it is treated as best-effort only.

### Claude hook (`tmux-claude-chat-stop.sh`)

- Extracts `CLAUDE_CHAT_REQ:<uuid>` only from the latest user message in the transcript tail instead of accepting older pending markers.
- Keeps the pending-file gate, strict UUID validation, symlink-rejected per-user runtime directory, and atomic write behavior.

### Docs

- README now documents the latest-user-message-only safety guarantee, restart requirement, and timeout recovery behavior.
