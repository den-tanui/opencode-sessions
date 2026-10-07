# opencode-sessions-fzf

Browse, filter, sort, and resume opencode sessions via fzf.

## Features

- 🔍 **Fuzzy search** across session titles, repos, and models
- 🎨 **Colored status indicators**: 🟡 needs-input, 🔴 error, 🟢 working, ⚪ idle (colored emoji with `--ansi`, plain ASCII without)
- 👁️ **Rich preview**: Last message, modified files, child sessions, full JSON
- 🔄 **Sort cycling**: Press `Ctrl-S` to cycle between time and directory (groups by project)
- 📁 **Projects mode**: Browse by project, drill down to sessions
- 📋 **Copy to clipboard**: Extract session IDs for sharing or scripting
- 🔀 **Multi-select**: TAB to mark multiple sessions
- 🪟 **Tmux popup**: Native fzf `--tmux` support for floating popups
- 🚀 **New window**: Resume sessions in a new tmux window without switching

## Quick Start

```bash
# Interactive mode (default)
./bin/opencode_sessions.sh

# List sessions as plain text
./bin/opencode_sessions.sh --list

# Browse by project, then drill down to sessions
./bin/opencode_sessions.sh --projects

# Copy session ID to clipboard
./bin/opencode_sessions.sh --copy

# Multi-select mode
./bin/opencode_sessions.sh --multi

# Filter by status
./bin/opencode_sessions.sh --filter working

# Start with directory sort (groups by project, newest first)
./bin/opencode_sessions.sh --sort directory

# Open in a tmux floating popup
./bin/opencode_sessions.sh --tmux

# Show all sessions regardless of age
./bin/opencode_sessions.sh --all

# Open in a new tmux window (don't switch from current)
./bin/opencode_sessions.sh --new-window
```

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `↑/↓` | Navigate sessions |
| `Enter` | Resume selected session |
| `Ctrl-S` | Cycle sort mode (time → directory) |
| `Ctrl-O` | Open session in new tmux window |
| `?` | Toggle preview window |
| `TAB` | Mark session (multi-select mode) |
| `Ctrl-C` | Cancel |

## CLI Options

| Option | Description |
|--------|-------------|
| `--list` | List sessions without fzf |
| `--copy` | Copy selected session ID to clipboard |
| `--multi` | Multi-select mode (TAB to mark) |
| `--filter STATUS` | Filter by: working, needs-input, error, idle |
| `--sort FIELD` | Initial sort: time (default), directory |
| `--dir DIR` | Filter by specific directory (exact match) |
| `--days N` | Show sessions from last N days (default: 14) |
| `--all` | Show all sessions regardless of age |
| `--projects` | Browse projects instead of sessions |
| `--tmux [OPTS]` | Open fzf in a floating tmux popup (requires tmux 3.3+) |
| `--ansi` | Enable ANSI colored output (status indicators, headers, preview) |
| `--fzf-opts OPTS` | Custom fzf options (overrides default) |
| `--prefix STR` | Tmux session name prefix |
| `--new-window` | Open session in new window without switching tmux |
| `-h, --help` | Show help |

## Tmux Integration

This project doubles as a tmux plugin.

### Installing via TPM (recommended)

Add this plugin to your TPM plugin list in `.tmux.conf`:

```tmux
# v2 schema (current, master branch)
set -g @plugin "den-tanui/opencode-sessions"

# Or pin to v1 schema (legacy, v1 branch)
set -g @plugin "den-tanui/opencode-sessions#v1"
```

### Manual installation

Clone into your tmux plugin directory (default `~/.tmux/plugins/`):

```bash
# v2 schema (current)
git clone -b master https://github.com/den-tanui/opencode-sessions.git ~/.tmux/plugins/opencode-sessions

# v1 schema (legacy)
git clone -b v1 https://github.com/den-tanui/opencode-sessions.git ~/.tmux/plugins/opencode-sessions
```

### Configuration

All options have sensible defaults — you only need to set the ones you want to change.

| Option | Default | Description |
|--------|---------|-------------|
| `@opencode-sessions-key` | `o` | Tmux key binding for sessions view (e.g. `o`, `M-o`, `C-o`) |
| `@opencode-sessions-projects-key` | `O` | Tmux key binding for projects view (e.g. `O`, `M-O`, `C-O`) |
| `@opencode-sessions-days` | `30` | Show sessions from last N days |
| `@opencode-sessions-sort` | `time` | Initial sort: `time` or `directory` |
| `@opencode-sessions-prefix` | `false` | Tmux session name prefix (or `false` for none) |
| `@opencode-sessions-fzf-opts` | `--height 80% --layout=reverse` | Custom fzf options (add `--ansi` for colored output) |
| `@opencode-sessions-popup-width` | `80%` | Tmux popup width |
| `@opencode-sessions-popup-height` | `80%` | Tmux popup height |
| `@opencode-sessions-popup-border` | `false` | Show border around tmux popup (`true`/`false`) |
| `@opencode-sessions-ansi` | `true` | Enable ANSI colored output with emoji icons (`true`/`false`) |
| `@opencode-sessions-filter` | `""` | Filter sessions by status: `working`, `needs-input`, `error`, `idle` (empty = all) |
| `@opencode-sessions-all` | `false` | Show all sessions regardless of age (`true`/`false`) |
| `@opencode-sessions-dir` | `""` | Filter by specific directory (exact match, empty = all) |
| `@opencode-sessions-new-window` | `false` | Open sessions in new tmux window without switching (`true`/`false`) |
| `@opencode-sessions-use-prefix` | `true` | Require tmux prefix key before binding (`true`/`false`) |

Example `.tmux.conf`:

```tmux
set -g @opencode-sessions-key "M-o"
set -g @opencode-sessions-projects-key "M-O"
set -g @opencode-sessions-days "30"
set -g @opencode-sessions-popup-width "90%"
# If installing manually (not via TPM), add:
run-shell ~/.tmux/plugins/opencode-sessions/opencode-sessions.tmux
```

## Dependencies

- **Required**: `bash` 4.0+, `sqlite3`, `fzf`
- **Required for resume**: `opencode` CLI
- **Optional for clipboard**: `xclip` (Linux/X11), `pbcopy` (macOS), `wl-copy` (Wayland)
- **Optional for tmux popup**: `tmux` 3.3+ (for `--tmux` flag)

## How It Works

1. Queries `~/.local/share/opencode/opencode.db` using a single combined CTE SQL query
2. Computes session status in-database (no per-session round trips)
3. Formats sessions with colored status icons and metadata
4. Pipes to fzf with preview window and sort cycling
5. On selection: `cd` to session directory and `exec opencode -s {sessionId}`

## v1 → v2 Migration

This project was originally built for the v1 database schema (`session`, `message`, `part` tables). It has since been migrated to the v2 schema (`session_v2`, `session_message`, no `part` table).

### Branch Layout

- **`master`** — v2 schema (current)
- **`v1`** — v1 schema (preserved, no longer maintained)

### Key Schema Changes

| v1 | v2 | Notes |
|---|---|---|
| `session` table | `session_v2` table | Renamed; added cost, tokens, metadata columns |
| `message` table | `session_message` table | Renamed |
| `part` table | removed | Parts now embedded in `session_message.data` JSON `content` array |
| `json_extract(data, '$.role')` | `session_message.type` column | Direct column, no JSON extraction |
| `json_extract(data, '$.modelID')` | `json_extract(session_v2.model, '$.id')` | Model is JSON object on session row |
| `json_extract(p.data, '$.tool')` | `json_extract(value, '$.name')` via `json_each` | Field renamed from `tool` to `name` |

See [`docs/DBSCHEMA.md`](docs/DBSCHEMA.md) for the full v2 schema reference and [`AGENTS.md`](AGENTS.md) for query-level migration details.

## License

MIT
