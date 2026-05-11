# tmux-claude-chat

A Codex skill that sends a prompt to Claude Code running in another tmux pane and captures Claude's answer through Claude's `Stop` hook. With the hook installed, completion detection is event-driven instead of based on fragile UI polling.

The skill spans two CLIs: the skill runs in Codex, while the completion signal comes from a hook installed on the Claude Code side. Codex plugin manifests cannot install Claude hooks, so the Claude-side setup is manual: copy one shell script and append one hook entry to `~/.claude/settings.json`.

## How it works

1. Codex creates `REQ=<uuid>` and `/tmp/claude-chat-$UID/pending-<REQ>`.
2. Codex sends `[CLAUDE_CHAT_REQ:<uuid>]` to the target Claude pane with the prompt.
3. When Claude finishes the turn, `tmux-claude-chat-stop.sh` reads the transcript, finds the newest marker whose pending file exists, and writes `/tmp/claude-chat-$UID/done-<REQ>.json`.
4. Codex waits for that file and reports `last_assistant_message`.
5. Permission dialogs are detected by a low-frequency pane watcher; the skill never approves or cancels them.

## Prerequisites

- macOS or Linux with `tmux`
- Codex CLI
- Claude Code CLI
- `jq` on `PATH`
- `uuidgen`, `/proc/sys/kernel/random/uuid`, or `python3` for request IDs

## Install

### 1. Install the Codex plugin

Install from the marketplace or local plugin source for `itouuuuuuuuu/codex-plugins`, then enable `tmux-claude-chat`.

From the Codex CLI:

```bash
codex plugin marketplace add itouuuuuuuuu/codex-plugins
```

Or, from inside an interactive Codex session:

1. Start Codex with `codex`.
2. Run `/plugin`.
3. Choose the marketplace option.
4. Add `itouuuuuuuuu/codex-plugins`.
5. Install and enable `tmux-claude-chat`.

### 2. Copy the Claude Stop hook

Resolve the plugin cache path dynamically:

```bash
HOOK_SRC=$(find ~/.codex/plugins/cache -path '*/tmux-claude-chat/*/claude-hook/tmux-claude-chat-stop.sh' -print -quit)
mkdir -p ~/.claude/hooks
cp "$HOOK_SRC" ~/.claude/hooks/tmux-claude-chat-stop.sh
chmod +x ~/.claude/hooks/tmux-claude-chat-stop.sh
```

For a manual checkout:

```bash
mkdir -p ~/.claude/hooks
cp plugins/tmux-claude-chat/claude-hook/tmux-claude-chat-stop.sh ~/.claude/hooks/tmux-claude-chat-stop.sh
chmod +x ~/.claude/hooks/tmux-claude-chat-stop.sh
```

### 3. Register the Stop hook in `~/.claude/settings.json`

Do not replace the file. Preserve existing top-level keys and existing hook entries; append only the new `Stop` matcher.

Before editing:

```bash
[ -f ~/.claude/settings.json ] && cp -p ~/.claude/settings.json ~/.claude/settings.json.bak.$(date +%Y%m%d-%H%M%S)
[ -f ~/.claude/settings.json ] && jq -e 'type == "object"' ~/.claude/settings.json >/dev/null && echo "settings.json: OK"
```

If the file does not exist, create it with:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/Users/<you>/.claude/hooks/tmux-claude-chat-stop.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

If `hooks.Stop` already exists, append one wrapper object:

```json
{
  "hooks": [
    {
      "type": "command",
      "command": "/Users/<you>/.claude/hooks/tmux-claude-chat-stop.sh",
      "timeout": 10
    }
  ]
}
```

Replace `/Users/<you>` with your home directory. Do not rely on `~` expansion inside JSON.

### 4. Restart Claude Code

Restart any Claude Code pane that should be targetable.

### 5. Verify

```bash
test -x ~/.claude/hooks/tmux-claude-chat-stop.sh && echo "hook script: OK"
jq -e '(.hooks.Stop // []) | [.[]?.hooks[]?.command // empty | select(endswith("tmux-claude-chat-stop.sh"))] | length > 0' ~/.claude/settings.json >/dev/null && echo "Stop hook: OK"
command -v jq >/dev/null && echo "jq: OK"
```

## Usage

In Codex, ask to consult Claude:

```text
Ask Claude in the other tmux pane to review my current changes.
```

or:

```text
%14 の Claude にこの設計をレビューさせて
```

The skill discovers Claude panes inside the current tmux session, validates that the pane is idle, submits the prompt, and returns the captured answer.

For long or multi-line prompts, the skill uses `tmux load-buffer -` before pasting into the Claude pane. That overwrites tmux buffer 0, but it does not modify the system clipboard on standard tmux setups.

## Update

If the bundled hook changes, re-copy it after updating the Codex plugin:

```bash
HOOK_SRC=$(find ~/.codex/plugins/cache -path '*/tmux-claude-chat/*/claude-hook/tmux-claude-chat-stop.sh' -print -quit)
cp "$HOOK_SRC" ~/.claude/hooks/tmux-claude-chat-stop.sh
chmod +x ~/.claude/hooks/tmux-claude-chat-stop.sh
```

Then restart Claude Code.

## Uninstall

1. Back up `~/.claude/settings.json`, then remove the `Stop` entry whose `command` ends in `tmux-claude-chat-stop.sh`.
2. Remove the copied hook script:

   ```bash
   rm ~/.claude/hooks/tmux-claude-chat-stop.sh
   ```

3. Restart Claude Code.
4. Optionally uninstall the Codex plugin.

Runtime files under `/tmp/claude-chat-$UID` are left in place.

## Troubleshooting

### The skill times out

Run the verify commands. Common causes:

- The hook entry was not appended to `~/.claude/settings.json`.
- The hook script is not executable.
- Claude Code was not restarted after hook installation.

### The skill reports a permission dialog

Claude is waiting for your decision. Resolve it directly in the Claude pane. The skill prints the `REQ` and `DONE_FILE` path so you can recover the answer after Claude finishes.

### The hook runs but no answer file appears

Inspect the hook log:

```bash
tail /tmp/claude-chat-$UID/stop-hook.log
```

For very large Claude transcripts, the hook scans the last 5000 JSONL lines by default to stay within Claude's hook timeout. Set `CLAUDE_CHAT_TRANSCRIPT_TAIL_LINES` in the hook environment if your turns can exceed that.

## License

[MIT](../../LICENSE) (c) Masafumi Ito
