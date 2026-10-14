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
HTTP_USER_AGENT="asb-installer (+https://github.com/Dicklesworthstone/agent_settings_backup_script)"

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
    mktemp -d 2>/dev/null || mktemp -d -t asb.XXXXXXXX 2>/dev/null
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
    local quiet_errors="${3:-false}"

    if command_exists curl; then
        if [[ "$quiet_errors" == "true" ]]; then
            curl -fsSL -A "$HTTP_USER_AGENT" "$url" -o "$dest" 2>/dev/null || return 1
        else
            curl -fsSL -A "$HTTP_USER_AGENT" "$url" -o "$dest" || return 1
        fi
    elif command_exists wget; then
        wget -q --tries=1 --user-agent="$HTTP_USER_AGENT" "$url" -O "$dest" || return 1
    else
        log_error "Neither curl nor wget found"
        return 1
    fi
}

verify_release_checksum() {
    local script="$1"
    local manifest="$2"
    local expected actual

    if ! expected=$(awk -v name="$SCRIPT_NAME" '
        { sub(/\r$/, "") }
        $2 == name || $2 == "*" name {
            count++
            if (NF != 2 || length($1) != 64 || $1 ~ /[^0-9a-fA-F]/) bad = 1
            digest = tolower($1)
        }
        END { if (count != 1 || bad) exit 1; print digest }
    ' "$manifest"); then
        log_error "Missing, malformed, or duplicate checksum for $SCRIPT_NAME"
        return 1
    fi

    if command_exists sha256sum; then
        actual=$(sha256sum < "$script") || return 1
    elif command_exists shasum; then
        actual=$(shasum -a 256 < "$script") || return 1
    else
        log_error "sha256sum or shasum is required to verify the release"
        return 1
    fi
    actual=${actual%%[[:space:]]*}
    if [[ "$actual" != "$expected" ]]; then
        log_error "Release checksum mismatch for $SCRIPT_NAME"
        return 1
    fi
}

#==============================================================================
# INSTALLATION
#==============================================================================

install_from_main() {
    local install_dir="$1"
    local temp_dir="${2:-}"

    if [[ -z "$temp_dir" ]]; then
        if ! temp_dir=$(mktemp_dir); then
            log_error "Failed to create temp directory"
            return 1
        fi
    fi

    log_info "Retaining downloaded files in $temp_dir"
    log_warn "ASB_UNSAFE_MAIN=1: installing unverified main-branch content."
    echo "" >&2

    local script_url="$GITHUB_RAW/$REPO_OWNER/$REPO_NAME/main/$SCRIPT_NAME"

    log_step "Downloading asb from main branch..."
    if ! download_file "$script_url" "$temp_dir/$SCRIPT_NAME"; then
        log_error "Failed to download asb from main branch"
        return 1
    fi

    local first_line=""
    IFS= read -r first_line < "$temp_dir/$SCRIPT_NAME" || true
    if [[ "$first_line" != "#!/usr/bin/env bash" ]]; then
        log_error "Downloaded unexpected content from main branch"
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
    log_info "Retaining downloaded files in $temp_dir"

    local tag="${ASB_VERSION:-}"
    if [[ -n "$tag" ]]; then
        tag="v${tag#v}"
    else
        local latest_url="https://github.com/$REPO_OWNER/$REPO_NAME/releases/latest"
        local release_prefix="https://github.com/$REPO_OWNER/$REPO_NAME/releases/tag/"
        local release_headers="$temp_dir/latest-headers.txt"
        local release_page
        if command_exists curl; then
            if ! release_page=$(curl -fsSLI -A "$HTTP_USER_AGENT" -D "$release_headers" \
                -o /dev/null -w '%{url_effective}' "$latest_url"); then
                log_error "Failed to resolve the latest release; no main-branch fallback"
                return 1
            fi
        elif command_exists wget; then
            if ! wget --spider --server-response --tries=1 --user-agent="$HTTP_USER_AGENT" \
                "$latest_url" > "$temp_dir/latest-stdout.txt" 2> "$release_headers"; then
                log_error "Failed to resolve the latest release; see retained headers"
                return 1
            fi
            release_page=$(awk '/^[[:space:]]*Location:/ { value = $2; sub(/\r$/, "", value) } END { print value }' "$release_headers") || return 1
        else
            log_error "curl or wget is required to resolve the latest release"
            return 1
        fi
        if [[ "$release_page" != "$release_prefix"* ]]; then
            log_error "Latest release did not resolve to a tag in this repository"
            return 1
        fi
        tag="${release_page#"$release_prefix"}"
    fi
    if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)*$ ]]; then
        log_error "Invalid ASB release version: $tag"
        return 1
    fi

    local release_base="https://github.com/$REPO_OWNER/$REPO_NAME/releases/download/$tag"
    local script_url="$release_base/$SCRIPT_NAME"
    local manifest="$temp_dir/asb-checksums.txt"

    log_step "Downloading asb ($tag)..."
    if ! download_file "$script_url" "$temp_dir/$SCRIPT_NAME"; then
        log_error "Failed to download release $tag; no main-branch fallback"
        return 1
    fi
    if ! download_file "$release_base/asb-checksums.txt" "$manifest"; then
        log_error "Failed to download the required release checksum"
        return 1
    fi
    verify_release_checksum "$temp_dir/$SCRIPT_NAME" "$manifest" || return 1

    # Sanity check
    local first_line=""
    IFS= read -r first_line < "$temp_dir/$SCRIPT_NAME" 2>/dev/null || true
    if [[ "$first_line" != "#!/usr/bin/env bash" ]]; then
        log_error "Verified release has unexpected script content"
        return 1
    fi

    install_script "$temp_dir/$SCRIPT_NAME" "$install_dir"
}

install_script() {
    local source="$1"
    local install_dir="$2"
    local dest="$install_dir/$SCRIPT_NAME"

    if [[ -L "$dest" || ( -e "$dest" && ! -f "$dest" ) ]]; then
        log_error "Refusing to replace a non-regular or symlink destination: $dest"
        return 1
    fi

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

    install_dir=$(cd -- "$install_dir" && pwd -P) || return 1
    dest="$install_dir/$SCRIPT_NAME"
    local perl_bin publisher
    perl_bin=$(type -P perl) || {
        log_error "Perl is required for locked, atomic installer publication"
        return 1
    }

    # Keep the kernel lock in the publishing process, including across failures.
    # All prepared and incumbent files are retained; only a complete candidate
    # is renamed onto the exact destination (never copied into a directory).
    publisher=$(cat <<'PERL'
use strict;
use warnings;
use Fcntl qw(:DEFAULT :flock S_ISREG O_NOFOLLOW);
use File::Temp qw(tempfile);
use File::Copy qw(copy);
use Digest::SHA;

my ($source, $directory, $name) = @ARGV;
my $destination = "$directory/$name";
my $lock_path = "$directory/.$name-install.lock";
sysopen(my $lock, $lock_path, O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW, 0600)
    or die "Cannot open installer lock $lock_path: $!\n";
my @lock_stat = stat($lock);
@lock_stat && S_ISREG($lock_stat[2]) or die "Installer lock is not a regular file\n";
flock($lock, LOCK_EX | LOCK_NB)
    or die "Another installation holds $lock_path: $!\n";
my @lock_path_stat = lstat($lock_path);
@lock_path_stat && $lock_stat[0] == $lock_path_stat[0] && $lock_stat[1] == $lock_path_stat[1]
    or die "Installer lock path changed\n";

sub digest {
    my ($path) = @_;
    sysopen(my $file, $path, O_RDONLY | O_NOFOLLOW) or die "Cannot read $path: $!\n";
    binmode($file) or die "Cannot read raw bytes from $path: $!\n";
    my $sha = Digest::SHA->new(256)->addfile($file)->hexdigest;
    close($file) or die "Cannot close $path: $!\n";
    return $sha;
}

my @incumbent = lstat($destination);
if (@incumbent && !S_ISREG($incumbent[2])) {
    die "Refusing to replace a non-regular or symlink destination: $destination\n";
}
sysopen(my $input, $source, O_RDONLY | O_NOFOLLOW) or die "Cannot read source $source: $!\n";
binmode($input) or die "Cannot read raw installer source: $!\n";
my @input_stat = stat($input);
@input_stat && S_ISREG($input_stat[2]) or die "Installer source is not a regular file\n";
my ($candidate_file, $candidate) = tempfile(".$name-install.XXXXXX", DIR => $directory, UNLINK => 0);
binmode($candidate_file) or die "Cannot prepare raw installer bytes: $!\n";
print STDERR "Retaining prepared installer file: $candidate\n";
copy($input, $candidate_file) or die "Cannot prepare installer file $candidate: $!\n";
close($input) or die "Cannot close installer source: $!\n";
close($candidate_file) or die "Cannot finish installer file $candidate: $!\n";
chmod(0755, $candidate) == 1 or die "Cannot set installer permissions: $!\n";
digest($candidate) eq digest($source) or die "Prepared installer bytes differ from source\n";

if (@incumbent) {
    sysopen(my $previous, $destination, O_RDONLY | O_NOFOLLOW)
        or die "Cannot read incumbent $destination: $!\n";
    binmode($previous) or die "Cannot read raw incumbent bytes: $!\n";
    my @opened = stat($previous);
    @opened && $opened[0] == $incumbent[0] && $opened[1] == $incumbent[1]
        or die "Incumbent changed before preservation\n";
    my ($backup_file, $backup) = tempfile(".$name-previous.XXXXXX", DIR => $directory, UNLINK => 0);
    binmode($backup_file) or die "Cannot preserve raw incumbent bytes: $!\n";
    print STDERR "Retaining incumbent backup: $backup\n";
    copy($previous, $backup_file) or die "Cannot preserve incumbent $backup: $!\n";
    close($previous) or die "Cannot close incumbent: $!\n";
    close($backup_file) or die "Cannot finish incumbent backup: $!\n";
    chmod($incumbent[2] & 0777, $backup) == 1 or die "Cannot preserve incumbent permissions: $!\n";
    digest($backup) eq digest($destination) or die "Incumbent changed during preservation\n";
}
my @current = lstat($destination);
if (@incumbent) {
    @current && S_ISREG($current[2]) && $current[0] == $incumbent[0] && $current[1] == $incumbent[1]
        or die "Incumbent path changed before publication\n";
} else {
    !@current or die "Destination appeared before publication\n";
}
rename($candidate, $destination) or die "Cannot publish prepared installer: $!\n";
PERL
    ) || return 1

    log_step "Installing to $dest"
    if [[ "$install_dir" == "/usr/local/bin" ]]; then
        if ! sudo "$perl_bin" -e "$publisher" "$source" "$install_dir" "$SCRIPT_NAME"; then
            log_error "Failed to install asb to $dest; prepared files and incumbent retained"
            return 1
        fi
    elif ! "$perl_bin" -e "$publisher" "$source" "$install_dir" "$SCRIPT_NAME"; then
        log_error "Failed to install asb to $dest; prepared files and incumbent retained"
        return 1
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
    local runtime_bash runtime_major
    if ! runtime_bash=$(type -P bash); then
        log_error "Bash is required on PATH for asb to run"
        exit 1
    fi
    if ! runtime_major=$("$runtime_bash" -c 'printf "%s" "${BASH_VERSINFO[0]}"') ||
       [[ ! "$runtime_major" =~ ^[0-9]+$ ]] || (( runtime_major < 4 )); then
        log_error "asb requires Bash 4 or later on PATH; install a supported Bash first"
        exit 1
    fi

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

    if ! type -P perl >/dev/null; then
        log_error "Perl is required for locked, atomic installer publication"
        exit 1
    fi

    # Install
    if [[ -n "${ASB_UNSAFE_MAIN:-}" ]] && [[ "$ASB_UNSAFE_MAIN" == "1" ]]; then
        if [[ -n "${ASB_VERSION:-}" ]]; then
            log_error "ASB_VERSION cannot be combined with ASB_UNSAFE_MAIN=1"
            exit 1
        fi
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
        log_info "Enable tab completion:"
        log_info "  Bash: eval \"\$(asb completion bash)\""
        log_info "  Zsh:  eval \"\$(asb completion zsh)\""
        log_info "  Fish: asb completion fish | source"

        printf '\n' >&2
        log_info "Documentation: https://github.com/$REPO_OWNER/$REPO_NAME"
    else
        log_error "Installation may have failed"
        exit 1
    fi
}

if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]:-}" == "$0" ]]; then
    main "$@"
fi
