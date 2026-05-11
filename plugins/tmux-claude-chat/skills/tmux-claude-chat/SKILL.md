---
name: tmux-claude-chat
description: Send one prompt to Claude Code running in another tmux pane, wait for Claude's answer, and report it back. Use when the user wants to consult Claude, ask Claude for a review or second opinion, or route a question to a Claude Code CLI in a separate tmux pane, especially phrases like "Claude に聞いて", "ask Claude", "consult Claude", "別 pane の Claude にレビューさせて", or "%14 の Claude に <X>". Only panes in the current tmux session are considered. If multiple Claude panes are found or none can be confirmed, ask which pane id to target before sending.
---

# tmux-claude-chat

One invocation = one prompt -> one captured answer. Follow-ups require re-invocation. The skill never approves Claude permission dialogs or presses `Esc`/`Ctrl-C`; if Claude is paused, surface the dialog and stop.

## How completion is detected (no UI polling)

The skill injects a unique marker `[CLAUDE_CHAT_REQ:<full-uuid>]` into the visible prompt and creates a pending file. Claude's `Stop` hook (`~/.claude/hooks/tmux-claude-chat-stop.sh`) parses the latest user message of the transcript, and if the extracted UUID has a matching pending file it atomically writes `$RUNDIR/done-<uuid>.json`. The skill blocks on that file.

Permission dialogs do not end Claude's turn, so `Stop` never fires while paused on one — a parallel watcher subshell scans the pane every ~2 s (with a 1 s burst for the first 10 s) for dialog patterns and trips an approval sentinel file instead.

`$RUNDIR = /tmp/claude-chat-$UID` (mode 700, ownership-checked) holds: `pending-<uuid>`, `done-<uuid>.json`, `approval-<uuid>.txt`, `prompt-<ts>-<uuid>.md`, and `stop-hook.log`.

## Prerequisites

1. `~/.claude/settings.json` registers a `Stop` hook pointing at `~/.claude/hooks/tmux-claude-chat-stop.sh`.
2. The hook script is executable. `jq` is on `PATH`.
3. `uuidgen`, `/proc/sys/kernel/random/uuid`, or `python3` is available for request IDs.
4. **Claude Code was started AFTER the hook was installed.** Claude reads hook settings at session boot. If hook config changed since the target pane was started, the user must `Ctrl-D`/`/exit` and restart Claude in that pane — otherwise this skill silently times out.

Health-check:

```bash
hook_ok() {
  test -x ~/.claude/hooks/tmux-claude-chat-stop.sh || return 1
  jq -e '
    (.hooks.Stop // [])
    | [ .[]?.hooks[]?.command // empty
        | select(endswith("tmux-claude-chat-stop.sh")) ]
    | length > 0
  ' ~/.claude/settings.json >/dev/null 2>&1 || return 1
  command -v jq >/dev/null
}
hook_ok && echo OK_HOOK_READY || echo MISSING
```

If `MISSING`, fall back to UI polling (final section) and tell the user once.

## Workflow

### 0. Session guard

```bash
[ -n "$TMUX" ] || { echo "Not inside tmux"; exit 1; }
SESSION=$(tmux display-message -p '#S')
```

All pane operations target `$SESSION`. Other tmux sessions are out of scope.

### 1. Discover & confirm Claude pane

```bash
tmux list-panes -s -t "$SESSION" -F "#{pane_id} #{pane_current_command} #{pane_current_path}"
```

A pane is a candidate when `pane_current_command` is `claude` (high) or `node` (medium). Capture each candidate (`tmux capture-pane -t %N -p -S -`) and require at least one Claude Code signal:

- Input prompt line beginning with `>` or `Human:`
- Status or footer containing `Claude`, `Opus`, `Sonnet`, or `Haiku`
- Permission dialog text such as `Do you want to proceed?`, `Allow`, `Deny`, or `Yes`
- Startup or help text containing `Claude Code`

Decision: 1 confirmed -> use it; 2 or more -> list as `session:window.pane` and ask; 0 -> ask. Never guess.

### 2. Validate target pane

```bash
tmux display-message -p -t %N "#{pane_id} #{session_name} #{pane_current_command}"
```

If the pane is in a different session, refuse — do not silently retarget. Then capture the pane and treat these as not-ready:

- Claude is visibly generating or mid-stream
- A permission dialog is on screen
- No input prompt is visible
- The input prompt contains residual user text

Surface the capture and ask the user whether to wait, cancel, or overwrite. Do not press interrupt or approval keys.

### 3. Generate REQ + create pending file

```bash
gen_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen
  elif [ -r /proc/sys/kernel/random/uuid ]; then
    cat /proc/sys/kernel/random/uuid
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import uuid; print(uuid.uuid4())'
  else
    echo "No UUID generator found" >&2
    return 1
  fi
}

RUNDIR="/tmp/claude-chat-${UID:-$(id -u)}"
mkdir -m 700 -p "$RUNDIR" && chmod 700 "$RUNDIR"
[ -O "$RUNDIR" ] || { echo "$RUNDIR not owned by us"; exit 1; }

REQ=$(gen_uuid)
PENDING="$RUNDIR/pending-$REQ"
DONE_FILE="$RUNDIR/done-$REQ.json"
APPROVAL_FILE="$RUNDIR/approval-$REQ.txt"
PANE="%14"   # confirmed Claude pane id

touch "$PENDING"
```

The pending file is the load-bearing safety mechanism — it must be created before submission and it ensures stale markers in older transcript turns cannot ever overwrite a current run.

### 4. Send the prompt safely

The marker must appear in the visible user message, not only inside a referenced file — if Claude never reads the file, the hook will see no marker and the run will time out (better than writing to the wrong done-file). Two send paths:

#### 4a. Direct send (≤500 chars, ASCII-safe, single-line, no fenced code/diff/multi-heading)

```bash
tmux send-keys -t "$PANE" -l "[CLAUDE_CHAT_REQ:$REQ] (internal routing tag; ignore in your reply) <flattened safe text>"
tmux send-keys -t "$PANE" Enter
```

#### 4b. File path (everything else)

```bash
ts=$(date +%Y%m%d-%H%M%S)
PROMPT_FILE="$RUNDIR/prompt-$ts-$REQ.md"
umask 077
{
  printf '[CLAUDE_CHAT_REQ:%s]\n' "$REQ"
  printf '(internal routing tag; ignore in your reply)\n\n'
  cat <<'EOF'
<full prompt body>
EOF
} > "$PROMPT_FILE"

ref="[CLAUDE_CHAT_REQ:$REQ] Please read $PROMPT_FILE and respond to the request inside it. Do not echo or strip the [CLAUDE_CHAT_REQ:...] marker — it is internal."
printf '%s' "$ref" | tmux load-buffer -
tmux paste-buffer -t "$PANE"
tmux send-keys -t "$PANE" Enter
```

Notes:

- The reference text in 4b carries the marker too, so the marker is always in the visible user message regardless of whether Claude reads the file.
- `tmux load-buffer -` overwrites tmux clipboard buffer 0; mention to the user if they care about it.
- Prompt files are not auto-deleted (Claude may re-read mid-response). Clean periodically with `rm -f "$RUNDIR"/prompt-*.md`.

#### Hard rules

- Never embed a literal newline in one `send-keys -l` call.
- `Enter` is its own `send-keys` call without `-l`.
- Keep marker + body on one line for direct-send (a separate Enter would split into two messages).

### 5. Confirm submission

Wait about 1 s and capture once. If the prompt still sits visibly at the input line, send one more standalone `Enter`. If it still has not submitted, stop and report the capture. Do not try a third submit key.

### 6. Wait for completion

```bash
# Parallel approval watcher: 1s for first 10s, then 2s. Intentionally slower
# than tmux-codex-chat's 0.5s burst because Claude permission dialogs tend to
# remain visible until the user resolves them.
(
  i=0
  while :; do
    [ -f "$DONE_FILE" ] && exit 0
    cap=$(tmux capture-pane -t "$PANE" -p 2>/dev/null) || exit 0
    if printf '%s' "$cap" | grep -qE \
      '(Do you want to proceed\?|Allow|Deny|Yes, and don.t ask again|No, and tell Claude|Proceed\?|Continue\?|\(esc to cancel\)|^[[:space:]]*[❯>][[:space:]]+(Yes|No|Allow|Deny|Approve|Proceed|Continue))'; then
      printf '%s' "$cap" > "$APPROVAL_FILE"
      exit 0
    fi
    i=$((i+1))
    if [ "$i" -lt 10 ]; then sleep 1; else sleep 2; fi
  done
) &
WATCHER_PID=$!

DEADLINE=$(( $(date +%s) + 300 ))
RESULT=timeout
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  if [ -f "$DONE_FILE" ]; then RESULT=done; break; fi
  if [ -f "$APPROVAL_FILE" ]; then RESULT=approval; break; fi
  sleep 1
done
kill "$WATCHER_PID" 2>/dev/null
wait "$WATCHER_PID" 2>/dev/null || true

case "$RESULT" in
  done)
    ANSWER=$(jq -r '.last_assistant_message // ""' "$DONE_FILE")
    rm -f "$DONE_FILE" "$PENDING"
    ;;
  approval)
    DIALOG=$(cat "$APPROVAL_FILE")
    rm -f "$APPROVAL_FILE"
    # Pending file is left in place. Once the user resolves the dialog
    # in the Claude pane, Claude will finish the turn and the Stop hook
    # will write $DONE_FILE. The skill MUST surface the exact REQ and
    # DONE_FILE path so the user can recover the answer without losing
    # the routing context — either by re-invoking this skill with the
    # same $REQ to wait again, or by reading $DONE_FILE manually.
    cat <<EOF
APPROVAL DIALOG - Claude is paused waiting for your decision.
   REQ:       $REQ
   DONE_FILE: $DONE_FILE
   Resolve the dialog in the Claude pane.
   Once Claude finishes, the answer will appear at \$DONE_FILE.
Dialog text follows:
$DIALOG
EOF
    ;;
  timeout)
    LATEST=$(tmux capture-pane -t "$PANE" -p)
    rm -f "$PENDING"
    cat <<EOF
TIMEOUT - Claude did not finish within the 5-minute window.
   The pending file has been removed to prevent stale replay, so the
   Stop hook will not write $DONE_FILE even if Claude finishes later.
   Recover the answer manually from pane scrollback, or re-invoke with
   a longer DEADLINE (e.g. 600 or 900 seconds).
   Latest pane content follows:
$LATEST
EOF
    ;;
esac
```

### 7. Report

Return the pane id, REQ, prompt summary, `$PROMPT_FILE` if used, and `last_assistant_message` from the done file. Flag timeout, approval interruption, or fallback path use. Do not claim Claude approved or agreed unless its captured text literally says so.

### 8. Cleanup

The `done`/`approval` files of the current run are removed in §6. `$PROMPT_FILE` is intentionally retained. Periodically `rm -f "$RUNDIR"/prompt-*.md "$RUNDIR"/stop-hook.log`.

## Fallback: UI polling (best-effort, hook-missing only)

If the health-check failed, use best-effort UI polling: capture before sending, poll every 3 s, and complete when the bottom appears idle with an input prompt, no spinner/generation text, no permission dialog, and two consecutive captures are byte-identical or a new completion marker appears. Apply the same approval short-circuit and 5-minute timeout.

**This path is best-effort only.** It can mis-detect when output wraps mid-line, when prior prompt text is stale, when Claude changes its UI strings, or when the answer arrives faster than 3 s. Do not treat it as equivalent to the hook path. Tell the user the prerequisites failed (`MISSING`) so they fix it once and never come back here.

## Common commands

| Need | Command |
| --- | --- |
| Session name | `tmux display-message -p '#S'` |
| Panes | `tmux list-panes -s -t "$SESSION" -F "#{pane_id} #{pane_current_command}"` |
| Capture screen / scrollback | `tmux capture-pane -t %N -p` / `tmux capture-pane -t %N -p -S -` |
| Generate REQ | `uuidgen` or `/proc/sys/kernel/random/uuid` or `python3` |
| Submit | `tmux send-keys -t %N Enter` |
| Wait for done | `until [ -f "$DONE_FILE" ]; do sleep 1; done` |
| Inspect hook log | `tail "$RUNDIR/stop-hook.log"` |
