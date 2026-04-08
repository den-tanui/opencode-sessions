# opencode-sessions-fzf

Browse, filter, sort, and resume opencode sessions via fzf.

## Features

- 🔍 **Fuzzy search** across session titles, repos, and models
- 🎨 **Colored status icons**: 🟡 needs-input, 🔴 error, 🟢 working, ⚪ idle
- 👁️ **Rich preview**: Last message, modified files, child sessions, full JSON
- 🔄 **Sort cycling**: Press `Ctrl-S` to cycle between time, directory, and status
- 📋 **Copy to clipboard**: Extract session IDs for sharing or scripting
- 🔀 **Multi-select**: TAB to mark multiple sessions

## Quick Start

```bash
# Interactive mode (default)
./opencode-sessions-fzf.sh

# List sessions as plain text
./opencode-sessions-fzf.sh --list

# Copy session ID to clipboard
./opencode-sessions-fzf.sh --copy

# Multi-select mode
./opencode-sessions-fzf.sh --multi

# Filter by status
./opencode-sessions-fzf.sh --filter working

# Start with a specific sort
./opencode-sessions-fzf.sh --sort status
```

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `↑/↓` | Navigate sessions |
| `Enter` | Resume selected session |
| `Ctrl-S` | Cycle sort mode (time → directory → status) |
| `?` | Toggle preview window |
| `TAB` | Mark session (multi-select mode) |
| `Ctrl-C` | Cancel |

## Dependencies

- **Required**: `bash` 4.0+, `sqlite3`, `fzf`
- **Required for resume**: `opencode` CLI
- **Optional for clipboard**: `xclip` (Linux/X11), `pbcopy` (macOS), `wl-copy` (Wayland)

## How It Works

1. Queries `~/.local/share/opencode/opencode.db` using a single combined CTE SQL query
2. Computes session status in-database (no per-session round trips)
3. Formats sessions with colored status icons and metadata
4. Pipes to fzf with preview window and sort cycling
5. On selection: `cd` to session directory and `exec opencode -s {sessionId}`
