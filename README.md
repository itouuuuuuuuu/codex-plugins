# codex-plugins

Codex plugins by Masafumi Ito.

## Plugins

| Plugin | Description |
| --- | --- |
| [`tmux-claude-chat`](plugins/tmux-claude-chat) | Send a prompt from Codex to Claude Code running in another tmux pane and capture the answer through Claude's Stop hook. |

## Prerequisites

- macOS or Linux
- `tmux`
- Codex CLI
- Claude Code CLI
- `jq`
- `uuidgen`, `/proc/sys/kernel/random/uuid`, or `python3`

## Marketplace

This repository includes a Codex marketplace manifest at `.agents/plugins/marketplace.json`. Add this repository as a local or GitHub-backed Codex plugin marketplace, then install `tmux-claude-chat`.

The plugin also requires a Claude-side Stop hook. See the plugin README for the copy, settings, verify, update, and uninstall steps.

## License

[MIT](LICENSE)
