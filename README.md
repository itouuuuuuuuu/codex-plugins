# codex-plugins

A small marketplace of Codex plugins maintained by Masafumi Ito. Each plugin under `plugins/` is independently installable through Codex's plugin workflow.

## Install

Add this marketplace once:

```bash
codex plugin marketplace add itouuuuuuuuu/codex-plugins
```

Then open Codex's plugin UI and install whichever plugins you want from `itouuuuuuuuu-codex-plugins`.

```text
codex
/plugin
```

Then restart Codex if prompted.

## Plugins

| Plugin | Description | Docs |
|---|---|---|
| [`tmux-claude-chat`](plugins/tmux-claude-chat/) | Send a prompt from Codex to Claude Code running in another tmux pane and capture the answer through Claude's `Stop` hook. | [README](plugins/tmux-claude-chat/README.md) |

## Repository layout

```text
.
├── .agents/plugins/
│   └── marketplace.json          # multi-plugin index for Codex
├── plugins/
│   └── <plugin-name>/
│       ├── .codex-plugin/plugin.json
│       ├── skills/               # plugin-provided skills
│       ├── README.md             # plugin-specific docs
│       └── ...                   # additional assets per plugin
└── README.md
```

## License

[MIT](LICENSE) © Masafumi Ito
