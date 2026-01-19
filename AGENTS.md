# AGENTS.md - AI Coding Agent Guidelines

## Project Overview

**asb** (Agent Settings Backup) is a bash-based CLI tool that backs up AI coding agent configuration folders to git-versioned repositories.

## Architecture

```
agent_settings_backup_script/
├── asb                 # Main CLI script (bash)
├── install.sh          # Installer script
├── README.md           # User documentation
├── AGENTS.md           # This file
├── VERSION             # Version number
├── LICENSE             # MIT license
├── .gitignore
├── .gitattributes
├── .github/
│   └── workflows/
│       └── release.yml # GitHub Actions for releases
└── scripts/
    └── (test scripts)
```

## Key Concepts

### Agent Definitions

Agents are defined in the `AGENT_FOLDERS` associative array:

```bash
declare -A AGENT_FOLDERS=(
    [claude]=".claude"
    [codex]=".codex"
    [cursor]=".cursor"
    # ...
)
```

To add a new agent:
1. Add entry to `AGENT_FOLDERS`
2. Add human-readable name to `AGENT_NAMES`
3. Test with `asb backup <agent>`

### Backup Structure

Each agent gets its own git repository in the backup location:

```
~/.agent_settings_backups/
├── .claude/
│   ├── .git/          # Full git history
│   ├── .gitignore     # Auto-generated exclusions
│   └── (agent files)
├── .codex/
│   └── ...
```

### Key Functions

| Function | Purpose |
|----------|---------|
| `backup_agent` | Syncs agent folder to backup, creates git commit |
| `restore_agent` | Restores agent folder from backup (optionally from specific commit) |
| `init_git_repo` | Initializes git repo with .gitignore for an agent |
| `create_backup_commit` | Stages changes and creates commit with timestamp |
| `show_history` | Displays git log for an agent's backup |

## Coding Standards

### Bash Style

- Use `set -uo pipefail` (no `-e` to handle expected failures gracefully)
- Quote all variables: `"$var"` not `$var`
- Use `local` for function-local variables
- Use `[[ ]]` not `[ ]` for conditionals
- Use `command_exists` to check for commands

### Error Handling

```bash
# Good: Check and provide helpful message
if [[ ! -d "$source" ]]; then
    log_warn "${agent_name} not found at ${source}"
    return 1
fi

# Good: Use || for fallbacks
rsync ... 2>/dev/null || cp -r ... 2>/dev/null
```

### Logging

Use the provided log functions:
- `log_info` - Informational messages
- `log_success` - Success confirmations
- `log_warn` - Warnings
- `log_error` - Errors
- `log_step` - Action being taken
- `log_debug` - Verbose output (only shown with ASB_VERBOSE=true)

## Testing

### Manual Testing

```bash
# Test backup
./asb backup claude

# Test restore
./asb restore claude

# Test list
./asb list

# Test with verbose
ASB_VERBOSE=true ./asb backup

# Test with custom location
ASB_BACKUP_ROOT=/tmp/test_backups ./asb backup
```

### Test Scenarios

1. **First backup**: Agent has no backup yet
2. **Incremental backup**: Agent already has backup history
3. **No changes**: Agent unchanged since last backup
4. **Restore latest**: Restore from HEAD
5. **Restore specific**: Restore from older commit
6. **Missing agent**: Agent not installed
7. **Unknown agent**: Invalid agent name

## Common Tasks

### Adding a New Agent

1. Find the config folder location (e.g., `~/.newagent`)
2. Add to `AGENT_FOLDERS`: `[newagent]=".newagent"`
3. Add to `AGENT_NAMES`: `[newagent]="New Agent Name"`
4. Test: `./asb backup newagent`

### Modifying Exclusions

Default exclusions are in `init_git_repo`:
- `*.log` - Log files
- `cache/`, `Cache/`, `.cache/` - Cache directories
- `*.sqlite3-wal`, `*.sqlite3-shm` - SQLite temp files

To add more, modify the `.gitignore` content in `init_git_repo`.

### Changing Backup Location

Users can set `ASB_BACKUP_ROOT` environment variable:
```bash
export ASB_BACKUP_ROOT=/path/to/backups
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ASB_BACKUP_ROOT` | `~/.agent_settings_backups` | Where backups are stored |
| `ASB_AUTO_COMMIT` | `true` | Create git commit on each backup |
| `ASB_VERBOSE` | `false` | Show debug output |

## Release Process

1. Update `VERSION` file
2. Update version in `asb` script (`ASB_VERSION`)
3. Create git tag: `git tag v0.x.x`
4. Push with tags: `git push --tags`
5. GitHub Actions creates release with `asb` artifact

## Dependencies

**Required:**
- `git` - For version control
- `bash` 4.0+ - For associative arrays

**Recommended:**
- `rsync` - For efficient file syncing (falls back to `cp`)

**For installation:**
- `curl` or `wget` - To download installer/script
