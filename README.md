# Agent Settings Backup (asb)

A smart backup tool for AI coding agent configuration folders. Each agent type gets its own git repository, providing full version history and easy restoration.

## Features

- **Git-versioned backups**: Every backup is a git commit with full history
- **Multiple agent support**: Claude, Codex, Cursor, Gemini, Cline, Amp, Aider, OpenCode, Factory, Windsurf
- **Efficient syncing**: Uses rsync for incremental backups
- **Easy restoration**: Restore to any point in history
- **Diff support**: See what changed since last backup

## Installation

```bash
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agent_settings_backup_script/main/install.sh" | bash
```

Or clone and install manually:

```bash
git clone https://github.com/Dicklesworthstone/agent_settings_backup_script.git
cd agent_settings_backup_script
cp asb ~/.local/bin/
```

## Quick Start

```bash
# Initialize backup location
asb init

# Backup all detected agents
asb backup

# Check backup status
asb list
```

## Usage

```bash
asb <command> [options]

Commands:
  backup [agents...]      Backup agent settings (all if none specified)
  restore <agent> [commit] Restore agent from backup
  list                    List all agents and backup status
  history <agent>         Show backup history for an agent
  diff <agent>            Show changes since last backup
  init                    Initialize backup location
  help                    Show help message
  version                 Show version
```

## Supported Agents

| Agent | Config Folder | Description |
|-------|--------------|-------------|
| `claude` | `~/.claude` | Claude Code |
| `codex` | `~/.codex` | OpenAI Codex CLI |
| `cursor` | `~/.cursor` | Cursor |
| `gemini` | `~/.gemini` | Google Gemini |
| `cline` | `~/.cline` | Cline |
| `amp` | `~/.amp` | Amp (Sourcegraph) |
| `aider` | `~/.aider` | Aider |
| `opencode` | `~/.opencode` | OpenCode |
| `factory` | `~/.factory` | Factory Droid |
| `windsurf` | `~/.windsurf` | Windsurf |

## Examples

### Backup Operations

```bash
# Backup all detected agents
asb backup

# Backup specific agents
asb backup claude codex

# Backup with verbose output
ASB_VERBOSE=true asb backup
```

### Restore Operations

```bash
# Restore from latest backup
asb restore claude

# Restore from specific commit
asb restore claude abc1234

# List available commits first
asb history claude
```

### Viewing History

```bash
# Show backup history
asb history claude

# Show last 50 backups
asb history claude 50

# Show changes since last backup
asb diff claude
```

## Configuration

Environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `ASB_BACKUP_ROOT` | `~/.agent_settings_backups` | Backup location |
| `ASB_AUTO_COMMIT` | `true` | Auto-commit on backup |
| `ASB_VERBOSE` | `false` | Verbose output |

## Backup Structure

```
~/.agent_settings_backups/
├── README.md
├── .claude/           # Git repo with Claude settings history
│   ├── .git/
│   ├── .gitignore
│   ├── settings.json
│   └── ...
├── .codex/            # Git repo with Codex settings history
│   ├── .git/
│   └── ...
└── ...
```

Each agent folder is a complete git repository. You can:
- `cd ~/.agent_settings_backups/.claude && git log` to see history
- `git diff HEAD~1` to see last changes
- `git checkout <commit>` to view old state

## Automation

### Cron Job

```bash
# Backup daily at midnight
0 0 * * * /home/user/.local/bin/asb backup >> /var/log/asb.log 2>&1
```

### Systemd Timer

```ini
# ~/.config/systemd/user/asb-backup.timer
[Unit]
Description=Daily agent settings backup

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
```

```ini
# ~/.config/systemd/user/asb-backup.service
[Unit]
Description=Agent Settings Backup

[Service]
Type=oneshot
ExecStart=%h/.local/bin/asb backup
```

```bash
systemctl --user enable asb-backup.timer
systemctl --user start asb-backup.timer
```

## Requirements

- `git` (required)
- `rsync` (recommended, falls back to `cp`)
- `curl` or `wget` (for installation)

## License

MIT

## Related Projects

- [repo_updater](https://github.com/Dicklesworthstone/repo_updater) - Multi-repo management tool
- [coding_agent_session_search (cass)](https://github.com/Dicklesworthstone/coding_agent_session_search) - Search agent session histories
- [mcp_agent_mail](https://github.com/Dicklesworthstone/mcp_agent_mail) - Agent coordination via MCP
