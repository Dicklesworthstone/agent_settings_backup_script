#!/usr/bin/env bash
#
# asb installer
# Downloads and installs asb (Agent Settings Backup) to your system
#
# Usage:
#   curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agent_settings_backup_script/main/install.sh" | bash
#
# Options (via environment variables):
#   DEST=/path/to/dir      Install directory (default: ~/.local/bin)
#   ASB_SYSTEM=1           Install to /usr/local/bin (requires sudo)
#   ASB_VERSION=x.y.z      Install specific version (default: latest release)
#   ASB_UNSAFE_MAIN=1      Install from main branch (NOT RECOMMENDED)
#
# Repository: https://github.com/Dicklesworthstone/agent_settings_backup_script
# License: MIT
#
#==============================================================================

set -uo pipefail

#==============================================================================
# CONSTANTS
#==============================================================================

REPO_OWNER="Dicklesworthstone"
REPO_NAME="agent_settings_backup_script"
SCRIPT_NAME="asb"
GITHUB_RAW="https://raw.githubusercontent.com"
GITHUB_RELEASE_HOST="https://github.com"

#==============================================================================
# COLORS
#==============================================================================

if [[ -t 2 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' BOLD='' RESET=''
fi

#==============================================================================
# LOGGING
#==============================================================================

log_info() { printf '%b\n' "${BLUE}ℹ${RESET} $*" >&2; }
log_success() { printf '%b\n' "${GREEN}✓${RESET} $*" >&2; }
log_warn() { printf '%b\n' "${YELLOW}⚠${RESET} $*" >&2; }
log_error() { printf '%b\n' "${RED}✗${RESET} $*" >&2; }
log_step() { printf '%b\n' "${BLUE}→${RESET} $*" >&2; }

#==============================================================================
# UTILITIES
#==============================================================================

command_exists() {
    command -v "$1" &>/dev/null
}

mktemp_dir() {
    mktemp -d 2>/dev/null || mktemp -d -t asb 2>/dev/null
}

get_shell_config() {
    local shell_name
    shell_name=$(basename "${SHELL:-/bin/bash}")

    case "$shell_name" in
        zsh)
            [[ -f "$HOME/.zshrc" ]] && echo "$HOME/.zshrc" || echo "$HOME/.zprofile"
            ;;
        bash)
            if [[ -f "$HOME/.bashrc" ]]; then
                echo "$HOME/.bashrc"
            elif [[ -f "$HOME/.bash_profile" ]]; then
                echo "$HOME/.bash_profile"
            else
                echo "$HOME/.profile"
            fi
            ;;
        fish)
            echo "$HOME/.config/fish/config.fish"
            ;;
        *)
            echo "$HOME/.profile"
            ;;
    esac
}

get_install_dir() {
    if [[ -n "${DEST:-}" ]]; then
        echo "$DEST"
    elif [[ -n "${ASB_SYSTEM:-}" ]] && [[ "$ASB_SYSTEM" == "1" ]]; then
        echo "/usr/local/bin"
    else
        echo "$HOME/.local/bin"
    fi
}

in_path() {
    local dir="$1"
    [[ ":$PATH:" == *":$dir:"* ]]
}

download_file() {
    local url="$1"
    local dest="$2"

    if command_exists curl; then
        curl -fsSL "$url" -o "$dest" || return 1
    elif command_exists wget; then
        wget -q "$url" -O "$dest" || return 1
    else
        log_error "Neither curl nor wget found"
        return 1
    fi
}

#==============================================================================
# INSTALLATION
#==============================================================================

install_from_main() {
    local install_dir="$1"
    local temp_dir="${2:-}"

    # Only create temp_dir if not provided (avoid nested traps)
    local owns_temp=false
    if [[ -z "$temp_dir" ]]; then
        if ! temp_dir=$(mktemp_dir); then
            log_error "Failed to create temp directory"
            return 1
        fi
        owns_temp=true
        trap "rm -rf '$temp_dir'" EXIT
    fi

    log_warn "Installing from main branch."
    echo "" >&2

    local script_url="$GITHUB_RAW/$REPO_OWNER/$REPO_NAME/main/$SCRIPT_NAME"

    log_step "Downloading asb from main branch..."
    if ! download_file "$script_url" "$temp_dir/$SCRIPT_NAME"; then
        log_error "Failed to download asb from main branch"
        return 1
    fi

    install_script "$temp_dir/$SCRIPT_NAME" "$install_dir"
}

install_from_latest_release() {
    local install_dir="$1"
    local temp_dir

    if ! temp_dir=$(mktemp_dir); then
        log_error "Failed to create temp directory"
        return 1
    fi
    trap "rm -rf '$temp_dir'" EXIT

    local latest_base="https://github.com/$REPO_OWNER/$REPO_NAME/releases/latest/download"
    local script_url="$latest_base/$SCRIPT_NAME"

    log_step "Downloading asb (latest release)..."
    if ! download_file "$script_url" "$temp_dir/$SCRIPT_NAME"; then
        log_warn "Could not download from latest release, falling back to main branch"
        # Pass temp_dir to avoid nested trap issues
        install_from_main "$install_dir" "$temp_dir"
        return $?
    fi

    # Sanity check
    local first_line=""
    IFS= read -r first_line < "$temp_dir/$SCRIPT_NAME" 2>/dev/null || true
    if [[ "$first_line" != "#!/usr/bin/env bash" ]]; then
        log_warn "Downloaded unexpected content, falling back to main branch"
        # Pass temp_dir to avoid nested trap issues
        install_from_main "$install_dir" "$temp_dir"
        return $?
    fi

    install_script "$temp_dir/$SCRIPT_NAME" "$install_dir"
}

install_script() {
    local source="$1"
    local install_dir="$2"
    local dest="$install_dir/$SCRIPT_NAME"

    # Create directory if needed
    if [[ ! -d "$install_dir" ]]; then
        log_step "Creating directory: $install_dir"
        if [[ "$install_dir" == "/usr/local/bin" ]]; then
            if ! command_exists sudo; then
                log_error "sudo is required to create $install_dir"
                return 1
            fi
            sudo mkdir -p "$install_dir" || return 1
        else
            mkdir -p "$install_dir" || return 1
        fi
    fi

    # Install with proper permissions
    log_step "Installing to $dest"
    if [[ "$install_dir" == "/usr/local/bin" ]]; then
        sudo cp "$source" "$dest" && sudo chmod +x "$dest"
    else
        cp "$source" "$dest" && chmod +x "$dest"
    fi

    log_success "Installed asb to $dest"
}

add_to_path() {
    local dir="$1"
    local shell_config
    shell_config=$(get_shell_config)

    if grep -qF "export PATH=\"$dir:" "$shell_config" 2>/dev/null; then
        log_info "$dir already in $shell_config"
        return 0
    fi

    log_step "Adding $dir to PATH in $shell_config"

    {
        printf '\n'
        printf '%s\n' "# Added by asb installer"
        printf '%s\n' "export PATH=\"$dir:\$PATH\""
    } >> "$shell_config" 2>/dev/null

    log_success "Added to $shell_config"
    log_info "Run 'source $shell_config' or start a new shell to update PATH"
}

#==============================================================================
# MAIN
#==============================================================================

main() {
    printf '\n' >&2
    printf '%b\n' "${BOLD}asb Installer${RESET}" >&2
    printf '%s\n' "───────────────────" >&2
    printf '\n' >&2

    local install_dir
    install_dir=$(get_install_dir)

    # Check for required tools
    if ! command_exists curl && ! command_exists wget; then
        log_error "Either curl or wget is required"
        exit 1
    fi

    if ! command_exists git; then
        log_error "git is required for asb to function"
        exit 1
    fi

    # Install
    if [[ -n "${ASB_UNSAFE_MAIN:-}" ]] && [[ "$ASB_UNSAFE_MAIN" == "1" ]]; then
        install_from_main "$install_dir" || exit 1
    else
        install_from_latest_release "$install_dir" || exit 1
    fi

    # Check PATH
    if ! in_path "$install_dir"; then
        log_warn "$install_dir is not in your PATH"

        if [[ -t 0 ]]; then
            printf '\n' >&2
            printf 'Add %s to PATH? [y/N] ' "$install_dir" >&2
            IFS= read -r response
            case "$response" in
                [yY]|[yY][eE][sS])
                    add_to_path "$install_dir"
                    ;;
                *)
                    log_info "Skipped adding to PATH"
                    log_info "You can manually add it with:"
                    log_info "  export PATH=\"$install_dir:\$PATH\""
                    ;;
            esac
        else
            log_info "Add it to your PATH with:"
            log_info "  export PATH=\"$install_dir:\$PATH\""
        fi
    fi

    # Verify installation
    printf '\n' >&2
    local installed_path="$install_dir/$SCRIPT_NAME"
    if [[ -x "$installed_path" ]]; then
        log_success "Installation complete!"
        printf '\n' >&2

        log_info "Get started with:"
        log_info "  asb init            Initialize backup location"
        log_info "  asb backup          Backup all detected agents"
        log_info "  asb list            Show backup status"
        log_info "  asb help            Show all commands"

        printf '\n' >&2
        log_info "Documentation: https://github.com/$REPO_OWNER/$REPO_NAME"
    else
        log_error "Installation may have failed"
        exit 1
    fi
}

main "$@"
