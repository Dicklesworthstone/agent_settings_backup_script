# Agent Settings Backup (asb)

A smart backup tool for AI coding agent configuration folders. Each agent type gets its own git repository, providing full version history and easy restoration.

## Features

- **Git-versioned backups**: Every backup is a git commit with full history
- **Multiple agent support**: Claude, Codex, Cursor, Gemini, Cline, Amp, Aider, OpenCode, Factory, Windsurf
- **Efficient syncing**: Uses rsync for incremental backups
- **Easy restoration**: Restore to any point in history
- **Diff support**: See what changed since last backup
- **Restore preview & confirmation**: See changes before restoring
- **Config file support**: Persistent settings in `~/.config/asb/config`
- **Export/import archives**: Move backups between machines
- **Shell completion**: Bash, Zsh, and Fish completions
- **Dry-run mode**: Preview operations without changes
- **Scheduled backups**: Install cron or systemd timers with `asb schedule`
- **Hooks**: Run scripts before/after backup and restore

## New in v0.2

- **Dry-run mode**: Preview changes with `--dry-run` or `-n`
- **Restore confirmation**: See exactly what will change before restoring
- **Configuration file**: Persistent settings in `~/.config/asb/config`
- **Export/Import**: Portable archives with `asb export` and `asb import`
- **Shell completion**: Tab completion for bash, zsh, and fish

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

### Shell Completion

Enable tab completion for commands and agent names:

```bash
# Bash (~/.bashrc)
eval "$(asb completion bash)"

# Zsh (~/.zshrc)
eval "$(asb completion zsh)"

# Fish (~/.config/fish/config.fish)
asb completion fish | source
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
asb [options] <command> [args]

Global options:
  -n, --dry-run           Show what would happen without making changes
  -f, --force             Skip confirmation prompts (use with caution)
  -v, --verbose           Show detailed output

Commands:
  backup [agents...]        Backup agent settings (all if none specified)
  restore <agent> [commit]  Restore agent from backup (prompts for confirmation)
  export <agent> [file]     Export backup as portable archive
  import <file>             Import backup from archive
  list                      List all agents and backup status
  history <agent>           Show backup history for an agent
  diff <agent>              Show changes since last backup
  verify [agents...]        Verify backup integrity (all if none specified)
  schedule [options]        Set up automated scheduled backups
  hooks --list              List configured hooks
  init                      Initialize backup location
  config [init|show]        Manage configuration
  completion [bash|zsh|fish] Output shell completion script
  help                      Show help message
  version                   Show version
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
| `plandex` | `~/.plandex-home` | Plandex |
| `qwencode` | `~/.qwen` | Qwen Code |
| `amazonq` | `~/.q` | Amazon Q |

## Examples

### Backup Operations

```bash
# Backup all detected agents
asb backup

# Preview backup without changes
asb --dry-run backup

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

# Restore without confirmation (scripting)
asb --force restore claude

# Preview restore without changes
asb --dry-run restore claude

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

## Portability

Export backups for transfer between machines:

```bash
asb export claude                    # Create archive
asb export claude my-backup.tar.gz   # Custom filename
asb import claude-backup.tar.gz      # Import on new machine
```

Pipe support for remote transfer or encryption:

```bash
asb export claude - | ssh remote "asb import -"
asb export claude - | gpg -c > backup.gpg
```

## Configuration

asb can be configured via config file or environment variables.

### Config File

```bash
asb config init    # Create config file
asb config show    # View current settings
```

Config file location: `~/.config/asb/config` (XDG-compliant).
Precedence: config file > environment variable > default.

Environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `ASB_BACKUP_ROOT` | `~/.agent_settings_backups` | Backup location |
| `ASB_AUTO_COMMIT` | `true` | Auto-commit on backup |
| `ASB_VERBOSE` | `false` | Verbose output |

## Hooks

asb can run user-defined scripts before and after backup/restore operations.

Hook directories (created by `asb config init`):

```
~/.config/asb/hooks/
  pre-backup.d/    # Run before any backup
  post-backup.d/   # Run after successful backup
  pre-restore.d/   # Run before any restore
  post-restore.d/  # Run after successful restore
```

Rules:
- Hooks run in alphabetical order (e.g., `01-*.sh`, `02-*.sh`)
- Scripts must be executable
- Pre-hook failure aborts the operation
- Post-hook failure logs a warning but continues

Environment variables passed to hooks:

| Variable | Description |
|----------|-------------|
| `ASB_AGENT` | Agent name (e.g., `claude`) |
| `ASB_SOURCE` | Source config path (e.g., `~/.claude`) |
| `ASB_BACKUP_DIR` | Backup directory path |
| `ASB_OPERATION` | `backup` or `restore` |
| `ASB_COMMIT` | Commit hash (post-backup) or restore target |

List active hooks:

```bash
asb hooks --list
```

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

### Quick Scheduling (Recommended)

Use the built-in scheduler to install cron jobs or systemd timers:

```bash
# Install daily systemd timer
asb schedule --systemd --interval daily

# Install weekly cron job
asb schedule --cron --interval weekly

# Check status or remove
asb schedule --status
asb schedule --remove --systemd
```

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
