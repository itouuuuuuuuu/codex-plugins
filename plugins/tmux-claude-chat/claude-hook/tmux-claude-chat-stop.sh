#!/usr/bin/env bash
# Claude Stop hook for the tmux-claude-chat Codex skill.
#
# When Claude Code ends a turn containing a CLAUDE_CHAT_REQ marker and the
# matching pending file exists, write the final assistant message to
# /tmp/claude-chat-$UID/done-<uuid>.json so Codex can pick it up.
set -u

UID_REAL=${UID:-$(id -u)}
RUNDIR="/tmp/claude-chat-${UID_REAL}"
LOG="${RUNDIR}/stop-hook.log"
UUID_RE='[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'

log() {
  [ -d "$RUNDIR" ] || return 0
  printf '[%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >>"$LOG" 2>/dev/null || true
}

ensure_rundir() {
  if [ -L "$RUNDIR" ]; then
    log "$RUNDIR is a symlink, refusing"
    return 1
  fi
  if [ ! -d "$RUNDIR" ]; then
    mkdir -m 700 "$RUNDIR" 2>/dev/null || return 1
  fi
  [ -O "$RUNDIR" ] || return 1
  chmod 700 "$RUNDIR" 2>/dev/null || true
  return 0
}

INPUT=$(cat)

command -v jq >/dev/null 2>&1 || exit 0
ensure_rundir || exit 0

STOP_ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)
if [ "$STOP_ACTIVE" = "true" ]; then
  exit 0
fi

TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")
[ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ] || exit 0

LAST_MSG=$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // ""' 2>/dev/null || echo "")
SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || echo "")

TAIL_LINES=${CLAUDE_CHAT_TRANSCRIPT_TAIL_LINES:-5000}

REQS=$(tail -n "$TAIL_LINES" "$TRANSCRIPT" 2>/dev/null | jq -rs --arg re "CLAUDE_CHAT_REQ:${UUID_RE}" '
  def text_content:
    if type == "string" then .
    elif type == "array" then
      map(
        if type == "object" and .type == "text" then (.text // "")
        else ""
        end
      ) | join("\n")
    else ""
    end;

  [
    .[]
    | select(type == "object")
    | select((.type? == "user") and (.message?.role? == "user"))
    | (.message.content | text_content)
  ]
  | reverse
  | map([match($re; "g")? | .string | sub("^CLAUDE_CHAT_REQ:"; "")])
  | flatten
  | .[]
' 2>/dev/null || true)

REQ=""
for candidate in $REQS; do
  case "$candidate" in
    [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])
      if [ -e "${RUNDIR}/pending-${candidate}" ]; then
        REQ="$candidate"
        break
      fi
      ;;
  esac
done

if [ -z "$REQ" ]; then
  exit 0
fi

PENDING="${RUNDIR}/pending-${REQ}"
OUT="${RUNDIR}/done-${REQ}.json"

TMP=$(mktemp "${OUT}.XXXXXX") || { log "mktemp failed for REQ=$REQ"; exit 0; }
chmod 600 "$TMP" 2>/dev/null || true

if ! jq -n \
  --arg msg "$LAST_MSG" \
  --arg sid "$SESSION" \
  --arg req "$REQ" \
  --arg transcript "$TRANSCRIPT" \
  '{req_id: $req, last_assistant_message: $msg, session_id: $sid, transcript_path: $transcript, finished_at: now}' \
  >"$TMP" 2>>"$LOG"; then
  log "jq compose failed for REQ=$REQ"
  rm -f "$TMP"
  exit 0
fi

if ! mv -f "$TMP" "$OUT" 2>>"$LOG"; then
  log "rename failed for REQ=$REQ"
  rm -f "$TMP"
  exit 0
fi

rm -f "$PENDING" 2>/dev/null
log "wrote $OUT (session=$SESSION bytes=$(wc -c <"$OUT" | tr -d ' '))"
exit 0
