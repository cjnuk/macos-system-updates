#!/usr/bin/env zsh
#
# Script: brew_and_conda_update.sh
# Purpose: Elegant system update script with beautiful visual output
#          Shows clear status for each component with intelligent alerting
# Author: Chris Norris
# Version: 3.0
#
# Usage:
#   ./brew_and_conda_update.sh [options]
#
# Options:
#   -h, --help         Show this help message
#   -n, --dry-run      Show what would be updated without making changes
#   -a, --audit        Show what this script covers vs. other update mechanisms
#   -l, --list-unmanaged  List apps not managed by this script (by category)
#   -s, --skip         Skip specific updates (comma-separated: macos,zsh,brew,conda,appstore,node,uv,npm)
#   -v, --verbose      Enable verbose output (includes dates with --list-unmanaged)
#
# Dependencies:
#   - macOS with softwareupdate
#   - Homebrew (brew)
#   - Conda (conda)
#   - Oh My Zsh (optional)
#   - Mac App Store CLI (mas) (optional)
#   - Node Version Manager (nvm) (optional)
#   - UV Python package manager (uv) (optional)
#   - Node Package Manager (npm) (optional)
#
# Examples:
#   ./brew_and_conda_update.sh                      # Run all updates
#   ./brew_and_conda_update.sh --skip macos,appstore     # Skip macOS and App Store updates
#   ./brew_and_conda_update.sh --dry-run            # Show what would be updated

# Enable strict error handling
# set -euo pipefail

# --- Configuration ---
readonly SCRIPT_NAME="${0:t}"
readonly SCRIPT_DIR="${0:A:h}"
readonly LOG_FILE="${SCRIPT_DIR}/brew_conda_update.log"
readonly TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
readonly NVM_DIR="${HOME}/.nvm"
readonly OH_MY_ZSH_DIR="${HOME}/.oh-my-zsh"

# Default options
DRY_RUN=false
VERBOSE=false
AUDIT=false
LIST_UNMANAGED=false
SKIP_UPDATES=""

# Update tracking
declare -a UPDATE_SUMMARY=()
declare -a SIGNIFICANT_ISSUES=()
declare -A UPDATE_GROUPS=(
    ["system"]=""
    ["dev_tools"]=""
    ["languages"]=""
    ["apps"]=""
)

# Timing
START_TIME=$(date +%s)

# --- Utility Functions ---

# log: Write message to both stdout and log file
# Args: $1 - message to log
log() {
    local message="$1"
    echo "${message}" | tee -a "${LOG_FILE}"
}

# error: Log error message and exit
# Args: $1 - error message, $2 - exit code (default: 1)
error() {
    local message="$1"
    local exit_code="${2:-1}"
    log "ERROR: ${message}" >&2
    exit "${exit_code}"
}

# verbose_log: Log only if verbose mode is enabled
# Args: $1 - message to log
verbose_log() {
    [[ "${VERBOSE}" == true ]] && log "VERBOSE: $1"
}

# check_command: Verify command exists in PATH
# Args: $1 - command name
# Returns: 0 if found, 1 if not found
check_command() {
    local cmd="$1"
    if command -v "${cmd}" &>/dev/null; then
        verbose_log "Found command: ${cmd}"
        return 0
    else
        verbose_log "Command not found: ${cmd}"
        return 1
    fi
}

# should_skip: Check if an update type should be skipped
# Args: $1 - update type to check
# Returns: 0 if should skip, 1 if should run
should_skip() {
    local update_type="$1"
    [[ ",${SKIP_UPDATES}," == *",${update_type},"* ]]
}

# run_command: Execute command with dry-run support and verbose control
# Args: $@ - command and arguments
run_command() {
    if [[ "${DRY_RUN}" == true ]]; then
        log "DRY-RUN: Would execute: $*"
        return 0
    fi
    
    verbose_log "Executing: $*"
    
    # Capture output
    local output
    local exit_code
    output=$("$@" 2>&1)
    exit_code=$?
    
    # Always log to file
    echo "${output}" >> "${LOG_FILE}"
    
    # Show output based on verbosity
    if [[ "${VERBOSE}" == true ]]; then
        echo "${output}"
    elif [[ ${exit_code} -ne 0 ]]; then
        # Always show errors
        echo "ERROR: Command failed with exit code ${exit_code}"
        echo "${output}"
    fi
    
    return ${exit_code}
}

# run_command_with_output: Execute command and return output (for parsing)
# Args: $@ - command and arguments
run_command_with_output() {
    if [[ "${DRY_RUN}" == true ]]; then
        log "DRY-RUN: Would execute: $*"
        return 0
    fi
    
    verbose_log "Executing: $*"
    
    local output
    local exit_code
    output=$("$@" 2>&1)
    exit_code=$?
    
    # Always log to file
    echo "${output}" >> "${LOG_FILE}"
    
    # Return output for processing
    echo "${output}"
    return ${exit_code}
}

# add_to_summary: Add update information to summary
# Args: $1 - category, $2 - message
add_to_summary() {
    local category="$1"
    local message="$2"
    UPDATE_SUMMARY+=("${category}: ${message}")
}

# parse_brew_updates: Extract updated packages from brew output
# Args: $1 - brew upgrade output
parse_brew_updates() {
    local output="$1"
    local updates=()
    
    # Extract package updates (format: "package old_version -> new_version")
    while IFS= read -r line; do
        if [[ "$line" =~ ^([a-zA-Z0-9_-]+)[[:space:]]+([0-9][^[:space:]]*)[[:space:]]+\-\>[[:space:]]+([0-9][^[:space:]]*) ]]; then
            local pkg="${BASH_REMATCH[1]}"
            local old_ver="${BASH_REMATCH[2]}"
            local new_ver="${BASH_REMATCH[3]}"
            updates+=("${pkg} (${old_ver} → ${new_ver})")
        fi
    done <<< "$output"
    
    printf '%s' "${updates[@]}"
}

# parse_cask_updates: Extract updated casks from brew cask output
# Args: $1 - brew cask upgrade output
parse_cask_updates() {
    local output="$1"
    local updates=()
    
    # Look for successful cask upgrades
    while IFS= read -r line; do
        if [[ "$line" =~ 🍺[[:space:]]+([a-z0-9_-]+)[[:space:]]+was[[:space:]]+successfully[[:space:]]+upgraded! ]]; then
            updates+=("${BASH_REMATCH[1]}")
        fi
    done <<< "$output"
    
    printf '%s' "${updates[@]}"
}

# parse_conda_updates: Extract updated packages from conda output
# Args: $1 - conda update output
parse_conda_updates() {
    local output="$1"
    local updates=()
    
    # Look for package updates in the "will be UPDATED" section
    local in_updated_section=false
    while IFS= read -r line; do
        if [[ "$line" =~ will[[:space:]]+be[[:space:]]+UPDATED ]]; then
            in_updated_section=true
            continue
        elif [[ "$line" =~ ^[[:space:]]*$ ]] && [[ "$in_updated_section" == true ]]; then
            break
        elif [[ "$in_updated_section" == true ]] && [[ "$line" =~ ^[[:space:]]+([a-zA-Z0-9_-]+)[[:space:]]+([^[:space:]]+)[[:space:]]+--\>[[:space:]]+([^[:space:]]+) ]]; then
            local pkg="${BASH_REMATCH[1]}"
            local old_ver="${BASH_REMATCH[2]}"
            local new_ver="${BASH_REMATCH[3]}"
            updates+=("${pkg} (${old_ver} → ${new_ver})")
        fi
    done <<< "$output"
    
    printf '%s' "${updates[@]}"
}

# parse_mas_updates: Extract updated apps from mas output
# Args: $1 - mas upgrade output
parse_mas_updates() {
    local output="$1"
    local updates=()
    
    # Return empty if no output or output contains "Everything up-to-date"
    if [[ -z "$output" ]] || [[ "$output" =~ "Everything up-to-date" ]]; then
        return 0
    fi
    
    # Only process if output contains actual content
    if [[ -n "$output" ]]; then
        while IFS= read -r line; do
            # Skip empty lines
            [[ -z "$line" ]] && continue
            
            # Look for installed apps with safer regex
            if [[ "$line" =~ "==> Installed" ]]; then
                # Extract app name from the line more safely
                local app_name
                app_name=$(echo "$line" | sed 's/.*==> Installed \([^(]*\).*/\1/' | sed 's/[[:space:]]*$//')
                if [[ -n "$app_name" ]]; then
                    updates+=("$app_name")
                fi
            fi
        done <<< "$output"
    fi
    
    printf '%s' "${updates[@]}"
}

# Beautiful display functions
show_section_header() {
    local section="$1"
    echo ""
    echo "${section}"
}

show_update_status() {
    local component="$1"
    local update_status="$2" 
    local details="$3"
    
    case "$update_status" in
        "success")
            echo "  ✅ ${component}"
            [[ -n "$details" ]] && echo "      ${details}"
            ;;
        "no_updates")
            echo "  💤 ${component}: Everything current"
            ;;
        "updated") 
            echo "  ⚡ ${component} updated"
            [[ -n "$details" ]] && echo "      ${details}"
            ;;
        "multiple_updates")
            echo "  📦 ${component}: ${details}"
            ;;
        "apps_updated")
            echo "  🛠️  ${component}"
            [[ -n "$details" ]] && echo "      ${details}"
            ;;
        "skipped")
            [[ "${VERBOSE}" == true ]] && echo "  ⏭️  ${component}: Skipped"
            ;;
        "warning")
            echo "  ⚠️  ${component}: ${details}"
            SIGNIFICANT_ISSUES+=("${component}: ${details}")
            ;;
        "error")
            echo "  ❌ ${component}: ${details}"
            SIGNIFICANT_ISSUES+=("${component}: ${details}")
            ;;
        "not_installed")
            [[ "${VERBOSE}" == true ]] && echo "  ➖ ${component}: Not installed"
            ;;
    esac
}

show_package_list() {
    local packages=("$@")
    for pkg in "${packages[@]}"; do
        echo "      • ${pkg}"
    done
}

# show_final_summary: Display beautiful final summary
show_final_summary() {
    local end_time=$(date +%s)
    local duration=$((end_time - ${START_TIME:-0}))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))
    
    # Count total updates
    local total_updates=0
    local categories_with_updates=0
    
    for summary in "${UPDATE_SUMMARY[@]}"; do
        if [[ ! "$summary" =~ "No updates"$ ]] && [[ ! "$summary" =~ "Skipped"$ ]]; then
            categories_with_updates=$((categories_with_updates + 1))
            
            # Extract number of updates with robust checking
            if [[ "$summary" =~ ([0-9]+)[[:space:]]+(packages?|apps?|updated) ]]; then
                local num_updates="${BASH_REMATCH[1]}"
                # Ensure we have a valid number
                if [[ "$num_updates" =~ ^[0-9]+$ ]]; then
                    total_updates=$((total_updates + num_updates))
                fi
            elif [[ "$summary" =~ Updated ]]; then
                total_updates=$((total_updates + 1))
            fi
        fi
    done
    
    echo ""
    echo "✨ ────────────────────────────────────────────────────────────────────────────────"
    
    # Ensure variables are numeric (fallback to 0 if not)
    [[ ! "$total_updates" =~ ^[0-9]+$ ]] && total_updates=0
    [[ ! "$categories_with_updates" =~ ^[0-9]+$ ]] && categories_with_updates=0
    [[ ! "$minutes" =~ ^[0-9]+$ ]] && minutes=0
    [[ ! "$seconds" =~ ^[0-9]+$ ]] && seconds=0
    
    if [[ $total_updates -eq 0 ]]; then
        echo ""
        echo "🎯 Perfect! Everything is up to date"
        echo ""
        if [[ $minutes -gt 0 ]]; then
            echo "⏱️  Completed in ${minutes}m ${seconds}s"
        else
            echo "⏱️  Completed in ${seconds}s"
        fi
    else
        echo ""
        if [[ $total_updates -eq 1 ]]; then
            echo "🎉 Success! 1 item refreshed"
        elif [[ $total_updates -lt 5 ]]; then
            echo "🎉 Success! ${total_updates} items refreshed across ${categories_with_updates} categories"
        else
            echo "🚀 Excellent! ${total_updates} items refreshed across ${categories_with_updates} categories"
        fi
        echo ""
        if [[ $minutes -gt 0 ]]; then
            echo "⏱️  Completed in ${minutes}m ${seconds}s"
        else
            echo "⏱️  Completed in ${seconds}s"
        fi
    fi
    
    # Show significant issues if any
    if [[ ${#SIGNIFICANT_ISSUES[@]} -gt 0 ]]; then
        echo ""
        echo "🔍 Action Required:"
        for issue in "${SIGNIFICANT_ISSUES[@]}"; do
            echo "   ${issue}"
        done
    fi
    
    echo ""
    echo "✨ ────────────────────────────────────────────────────────────────────────────────"
}

# cleanup: Perform cleanup operations on exit
cleanup() {
    # Remove the guard variable to allow re-running
    unset BREW_CONDA_UPDATE_ALREADY_RUN
}

# --- Update Functions ---

# update_macos: Check for macOS software updates
update_macos() {
    if should_skip "macos"; then
        show_update_status "macOS" "skipped"
        return 0
    fi

    if ! check_command softwareupdate; then
        show_update_status "macOS" "not_installed"
        return 0
    fi

    local output
    output=$(run_command_with_output softwareupdate -l)
    
    if [[ "$output" =~ "No new software available" ]]; then
        show_update_status "macOS" "no_updates"
        add_to_summary "macOS" "No updates"
    else
        show_update_status "macOS" "warning" "System updates available - install manually"
        add_to_summary "macOS" "Updates available"
        [[ "${VERBOSE}" == false ]] && echo "      Run: sudo softwareupdate -i -a"
    fi
}

# update_oh_my_zsh: Update Oh My Zsh if installed
update_oh_my_zsh() {
    if should_skip "zsh"; then
        show_update_status "Oh My Zsh" "skipped"
        return 0
    fi

    if [[ ! -d "${OH_MY_ZSH_DIR}" ]]; then
        show_update_status "Oh My Zsh" "not_installed"
        return 0
    fi

    # Source Oh My Zsh if available
    if [[ -f "${OH_MY_ZSH_DIR}/oh-my-zsh.sh" ]]; then
        export ZSH="${OH_MY_ZSH_DIR}"
        source "${ZSH}/oh-my-zsh.sh" || verbose_log "WARNING: Failed to source Oh My Zsh"
    fi

    if check_command omz; then
        local output
        output=$(run_command_with_output omz update)
        
        if [[ "$output" =~ "Already up to date" ]] || [[ "$output" =~ "Oh My Zsh is already at the latest version" ]]; then
            show_update_status "Oh My Zsh" "no_updates"
            add_to_summary "Oh My Zsh" "No updates"
        else
            show_update_status "Oh My Zsh" "success" "Updated to latest"
            add_to_summary "Oh My Zsh" "Updated"
        fi
    else
        show_update_status "Oh My Zsh" "not_installed"
    fi
}

# update_homebrew: Update Homebrew packages and casks
update_homebrew() {
    if should_skip "brew"; then
        show_update_status "Homebrew" "skipped"
        return 0
    fi

    if ! check_command brew; then
        show_update_status "Homebrew" "not_installed"
        return 0
    fi

    # Update Homebrew itself
    local update_output
    update_output=$(run_command_with_output brew update --force)
    
    # Upgrade packages
    local upgrade_output
    upgrade_output=$(run_command_with_output brew upgrade)
    local package_updates
    package_updates=($(parse_brew_updates "$upgrade_output"))
    
    # Upgrade casks
    local cask_output
    cask_output=$(run_command_with_output brew upgrade --cask --greedy)
    local cask_updates
    cask_updates=($(parse_cask_updates "$cask_output"))
    
    # Cleanup
    run_command brew cleanup >/dev/null 2>&1
    
    # Show beautiful results
    if [[ ${#package_updates[@]} -eq 0 && ${#cask_updates[@]} -eq 0 ]]; then
        show_update_status "Homebrew" "no_updates"
        add_to_summary "Homebrew" "No updates"
    else
        if [[ ${#package_updates[@]} -gt 0 ]]; then
            show_update_status "Homebrew packages" "multiple_updates" "${#package_updates[@]} packages updated"
            show_package_list "${package_updates[@]}"
            add_to_summary "Homebrew packages" "${#package_updates[@]} updated"
        fi
        
        if [[ ${#cask_updates[@]} -gt 0 ]]; then
            show_update_status "Applications" "apps_updated" "${#cask_updates[@]} apps updated"
            show_package_list "${cask_updates[@]}"
            add_to_summary "Homebrew apps" "${#cask_updates[@]} updated"
        fi
    fi
    
    # Run doctor check if verbose
    if [[ "${VERBOSE}" == true ]]; then
        local doctor_output
        doctor_output=$(run_command_with_output brew doctor)
        if [[ "$doctor_output" != "Your system is ready to brew." ]]; then
            show_update_status "Homebrew" "warning" "Doctor found issues (check with: brew doctor)"
        fi
    fi
}

# update_conda: Update Conda and all packages
update_conda() {
    if should_skip "conda"; then
        show_update_status "Conda" "skipped"
        return 0
    fi

    if ! check_command conda; then
        show_update_status "Conda" "not_installed"
        return 0
    fi

    # Update conda itself
    local conda_output
    conda_output=$(run_command_with_output conda update -n base -c conda-forge conda --yes)

    # Update all packages
    local packages_output
    packages_output=$(run_command_with_output conda update --all --yes)
    local package_updates
    package_updates=($(parse_conda_updates "$packages_output"))
    
    if [[ ${#package_updates[@]} -eq 0 ]]; then
        show_update_status "Conda" "no_updates"
        add_to_summary "Conda" "No updates"
    else
        show_update_status "Conda packages" "multiple_updates" "${#package_updates[@]} packages updated"
        show_package_list "${package_updates[@]}"
        add_to_summary "Conda" "${#package_updates[@]} packages updated"
    fi
}

# update_mas: Update Mac App Store apps
update_mas() {
    if should_skip "appstore"; then
        show_update_status "App Store" "skipped"
        return 0
    fi

    if ! check_command mas; then
        show_update_status "App Store" "not_installed"
        return 0
    fi

    local output
    output=$(run_command_with_output mas upgrade)
    local app_updates
    app_updates=($(parse_mas_updates "$output"))
    
    if [[ ${#app_updates[@]} -eq 0 ]]; then
        show_update_status "App Store" "no_updates"
        add_to_summary "App Store" "No updates"
    else
        show_update_status "App Store apps" "apps_updated" "${#app_updates[@]} apps updated"
        show_package_list "${app_updates[@]}"
        add_to_summary "App Store" "${#app_updates[@]} apps updated"
    fi
}

# fetch_latest_nvm_version: Get latest NVM version from GitHub
# Returns: latest version string or empty on failure
fetch_latest_nvm_version() {
    local latest_version
    latest_version=$(curl -s -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/nvm-sh/nvm/releases/latest" 2>/dev/null |
        command grep -o '"tag_name": "v[^"]*"' |
        command sed 's/"tag_name": "v\(.*\)"/\1/')

    echo "${latest_version}"
}

# update_claudee_alias: Update claudee alias with current Node.js version path
# This function updates the claudee alias to point to the correct claude binary
# after NVM updates that might change Node.js version paths
update_claudee_alias() {
    local aliases_file="${OH_MY_ZSH_DIR}/custom/aliases.zsh"

    if [[ ! -f "${aliases_file}" ]]; then
        verbose_log "No aliases file found at ${aliases_file}, skipping claudee alias update"
        return 0
    fi

    # Check if claudee alias exists
    if ! grep -q "alias claudee=" "${aliases_file}"; then
        verbose_log "No claudee alias found in ${aliases_file}, skipping update"
        return 0
    fi

    # Find the current claude binary path
    local claude_path
    if check_command claude; then
        claude_path=$(command -v claude)
        log "Updating claudee alias to point to: ${claude_path}"

        if [[ "${DRY_RUN}" == true ]]; then
            log "DRY-RUN: Would update claudee alias in ${aliases_file}"
            return 0
        fi

        # Create backup of aliases file
        cp "${aliases_file}" "${aliases_file}.backup.$(date +%Y%m%d%H%M%S)"

        # Update the alias
        if sed -i '' "s|alias claudee=.*|alias claudee=\"${claude_path}\"|g" "${aliases_file}"; then
            log "✅ claudee alias updated successfully"
            log "NOTE: Run 'source ~/.zshrc' or restart terminal to use updated alias"
        else
            log "⚠️  Failed to update claudee alias"
            return 1
        fi
    else
        log "WARNING: claude command not found, cannot update claudee alias"
        return 1
    fi
}

# update_nvm: Update Node Version Manager
update_nvm() {
    if should_skip "node"; then
        show_update_status "NVM" "skipped"
        return 0
    fi

    # Check if NVM directory exists
    if [[ ! -d "${NVM_DIR}" ]]; then
        show_update_status "NVM" "not_installed"
        return 0
    fi

    # Load NVM
    export NVM_DIR
    [[ -s "${NVM_DIR}/nvm.sh" ]] && source "${NVM_DIR}/nvm.sh"
    [[ -s "${NVM_DIR}/bash_completion" ]] && source "${NVM_DIR}/bash_completion"

    # Verify NVM is loaded
    if ! check_command nvm; then
        show_update_status "NVM" "error" "Not loaded properly, skipping update"
        return 0
    fi

    # Get versions
    local current_version
    current_version=$(nvm --version)

    verbose_log "Current NVM version: v${current_version}"
    verbose_log "Fetching latest NVM version..."

    local latest_version
    latest_version=$(fetch_latest_nvm_version)

    if [[ -z "${latest_version}" ]]; then
        show_update_status "NVM" "error" "Failed to fetch latest version"
        return 1
    fi

    # Check if Claude is installed before NVM update
    local claude_installed=false
    local claude_package=""
    if check_command claude; then
        claude_installed=true
        # Get the exact package name and version
        claude_package=$(npm list -g --depth=0 2>/dev/null | grep -i claude | sed 's/[├└]─ //g' | tr -d ' ')
        if [[ -n "${claude_package}" ]]; then
            verbose_log "Found Claude package: ${claude_package}"
        fi
    fi

    # Compare and update if needed
    if [[ "${current_version}" != "${latest_version}" ]]; then
        if [[ "${DRY_RUN}" == true ]]; then
            show_update_status "NVM" "updated" "Would update to v${latest_version}"
            return 0
        fi

        # Create backup
        local backup_dir="${NVM_DIR}_backup_$(date +%Y%m%d%H%M%S)"
        verbose_log "Creating backup at ${backup_dir}..."
        cp -r "${NVM_DIR}" "${backup_dir}"

        # Run update
        curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/v${latest_version}/install.sh" | bash >/dev/null 2>&1

        # Reload and verify
        [[ -s "${NVM_DIR}/nvm.sh" ]] && source "${NVM_DIR}/nvm.sh"
        local new_version
        new_version=$(nvm --version)

        if [[ "${new_version}" == "${latest_version}" ]]; then
            show_update_status "NVM" "success" "Updated to v${new_version}"
            add_to_summary "NVM" "Updated to v${new_version}"

            # Reinstall Claude if it was previously installed
            if [[ "${claude_installed}" == true && -n "${claude_package}" ]]; then
                local package_name
                package_name=$(echo "${claude_package}" | cut -d'@' -f1-2)
                if npm install -g "${package_name}" >/dev/null 2>&1; then
                    echo "    Reinstalled Claude Code"
                    update_claudee_alias
                else
                    echo "    ⚠️  Failed to reinstall Claude Code: npm install -g ${package_name}"
                fi
            fi
        else
            show_update_status "NVM" "error" "Update failed (current: v${new_version}, expected: v${latest_version})"
            return 1
        fi
    else
        show_update_status "NVM" "no_updates"
        add_to_summary "NVM" "No updates"
    fi
}

# update_uv: Update UV Python package manager
update_uv() {
    if should_skip "uv"; then
        show_update_status "UV" "skipped"
        return 0
    fi

    if ! check_command uv; then
        show_update_status "UV" "not_installed"
        return 0
    fi

    local output
    output=$(run_command_with_output uv self update)
    
    if [[ "$output" =~ "already up to date" ]] || [[ "$output" =~ "No update available" ]]; then
        show_update_status "UV" "no_updates"
        add_to_summary "UV" "No updates"
    elif [[ "$output" =~ "Upgraded uv from" ]]; then
        # Extract version info from output
        local version_info
        version_info=$(echo "$output" | grep -o "from v[0-9.]* to v[0-9.]*" | head -1)
        show_update_status "UV" "updated" "${version_info}"
        add_to_summary "UV" "Updated ${version_info}"
    else
        show_update_status "UV" "success" "Updated to latest"
        add_to_summary "UV" "Updated"
    fi
}

# update_npm_global_packages: Update global npm packages
update_npm_global_packages() {
    if should_skip "npm"; then
        show_update_status "Global packages" "skipped"
        return 0
    fi

    if ! check_command npm; then
        show_update_status "Global packages" "not_installed"
        return 0
    fi

    local packages_updated=()
    
    # Update Gemini CLI
    local gemini_output
    gemini_output=$(run_command_with_output npm install -g @google/gemini-cli@latest)
    if [[ "$gemini_output" =~ "added".*"changed" ]]; then
        packages_updated+=("@google/gemini-cli")
    fi
    
    # Update Claude CLI
    local claude_output  
    claude_output=$(run_command_with_output npm install -g @anthropic-ai/claude-code@latest)
    if [[ "$claude_output" =~ "added".*"changed" ]]; then
        packages_updated+=("@anthropic-ai/claude-code")
    fi
    
    if [[ ${#packages_updated[@]} -eq 0 ]]; then
        show_update_status "Global packages" "no_updates"
        add_to_summary "NPM global packages" "No updates"
    else
        show_update_status "Global packages" "multiple_updates" "${#packages_updated[@]} packages updated"
        show_package_list "${packages_updated[@]}"
        add_to_summary "NPM global packages" "${#packages_updated[@]} packages updated"
    fi
}


# show_help: Display beautiful usage information
show_help() {
    cat << EOF

✨ ────────────────────────────────────────────────────────────────────────────────

🚀 ${SCRIPT_NAME}
   Elegant package manager update script with beautiful visual output
   Focuses on standard package managers - use --audit to see coverage

✨ ────────────────────────────────────────────────────────────────────────────────

📖 Usage:
   ${SCRIPT_NAME} [OPTIONS]

⚙️  Options:
   -h, --help         Show this help message
   -n, --dry-run      Preview updates without making changes  
   -a, --audit        Show what this script covers vs. other update mechanisms
   -l, --list-unmanaged  List apps not managed by this script (by category)
   -s, --skip         Skip specific categories (comma-separated)
                      Available: macos, zsh, brew, conda, appstore, node, uv, npm
   -v, --verbose      Show detailed technical output (includes dates with --list-unmanaged)

💡 Examples:
   ${SCRIPT_NAME}                        # Update everything we manage
   ${SCRIPT_NAME} --dry-run              # Preview what would be updated  
   ${SCRIPT_NAME} --audit                # See what we cover vs. other tools
   ${SCRIPT_NAME} --list-unmanaged       # Show apps not managed by this script
   ${SCRIPT_NAME} --list-unmanaged -v    # Show unmanaged apps with last modified dates
   ${SCRIPT_NAME} --skip macos,appstore  # Skip system and App Store updates
   ${SCRIPT_NAME} --skip zsh,node        # Skip shell framework and Node.js

🎯 What Each Category Updates:
   🖥️  macos       macOS system software updates
   🛠️  zsh         Oh My Zsh shell framework
   🛠️  brew        Homebrew packages & desktop applications  
   🐍 conda       Conda Python packages & environments
   🐍 node        Node Version Manager (NVM) & Node.js
   🐍 uv          UV Python package manager
   🐍 npm         Global npm packages (Claude, Gemini CLIs)
   📱 appstore    Mac App Store applications

📝 All operations are logged to: ${LOG_FILE}

✨ ────────────────────────────────────────────────────────────────────────────────

EOF
}

# show_audit: Display coverage analysis 
show_audit() {
    cat << EOF

✨ ────────────────────────────────────────────────────────────────────────────────

🔍 Update Coverage Audit
   What this script manages vs. other mechanisms

✨ ────────────────────────────────────────────────────────────────────────────────

✅ What We Manage (Package Managers):
   🖥️  macOS system updates
   🛠️  Oh My Zsh shell framework
   🛠️  Homebrew packages & desktop applications
   🐍 Conda Python packages & environments
   🐍 Node Version Manager (NVM) & Node.js
   🐍 UV Python package manager
   🐍 Global npm packages
   📱 Mac App Store applications

🔄 Self-Updating Applications:
   🎨 Adobe Creative Suite    → Adobe Creative Cloud handles updates
   🏢 Microsoft Office       → Microsoft AutoUpdate handles updates

⚙️  Other Applications (Manual Updates):
   🎵 Professional Audio     → Logic Pro, audio plugins, music software
   🔧 Hardware Utilities     → Focusrite, Loupedeck, CalDigit tools
   💼 Business Tools         → Specialized software with built-in updaters
   🧑‍💻 Development Tools      → JetBrains Toolbox, vendor-specific IDEs

💡 Recommendation:
   • This script handles your package manager ecosystem efficiently
   • Adobe & Microsoft apps update automatically via their own mechanisms
   • Other apps typically have built-in "Check for Updates" options
   • Use --dry-run to see exactly what this script will update

✨ ────────────────────────────────────────────────────────────────────────────────

EOF
}

# show_unmanaged_apps: Display apps not managed by this script
show_unmanaged_apps() {
    cat << EOF

✨ ────────────────────────────────────────────────────────────────────────────────

📋 Applications Not Managed by This Script
   Categorized by update mechanism
$(if [[ "${VERBOSE}" == true ]]; then echo "   📅 Sorted by oldest first (apps that may need updates)"; fi)

✨ ────────────────────────────────────────────────────────────────────────────────

EOF

    # Process each category manually for better compatibility
    local app_found=false
    
    # Define and process categories one by one
    local adobe_apps=()
    local microsoft_apps=()
    local audio_apps=()
    local hardware_apps=()
    local business_apps=()
    local dev_apps=()
    local media_apps=()
    local productivity_apps=()
    local browser_apps=()
    local security_apps=()
    local entertainment_apps=()
    local other_apps=()
    
    # Scan all applications once
    while IFS= read -r -d '' app_path; do
        local app_name=$(basename "$app_path" .app)
        
        # Skip system apps and empty entries
        [[ -z "$app_name" ]] && continue
        [[ "$app_name" =~ ^(Safari|Mail|Calendar|Contacts|Maps|Photos|Music|TV|News|Stocks|Weather|Clock|Calculator|Dictionary|Preview|TextEdit|Font Book|Digital Color Meter|Keychain Access|System Information|Activity Monitor|Console|Terminal|Disk Utility|Grapher|Screenshot|VoiceOver Utility|Bluetooth Screen Sharing|Migration Assistant|Boot Camp Assistant|System Preferences|App Store|Finder)$ ]] && continue
        
        # Skip apps we know are managed by our script
        [[ "$app_name" =~ ^(VLC|Discord|Claude|ChatGPT|Zed|Warp|Jan|Ollama|Homebrew|iTerm)$ ]] && continue
        
        # Get modification date and create sortable entry
        local app_entry="$app_name"
        local sort_key=""
        if [[ "${VERBOSE}" == true ]]; then
            local mod_date=$(stat -f "%Sm" -t "%Y-%m-%d" "$app_path" 2>/dev/null || echo "9999-12-31")  # Unknown dates go to end
            local display_date=$(stat -f "%Sm" -t "%Y-%m-%d" "$app_path" 2>/dev/null || echo "Unknown")
            app_entry="$app_name ($display_date)"
            sort_key="$mod_date|$app_entry"  # Use pipe separator for sorting
        else
            sort_key="$app_name|$app_entry"
        fi
        
        # Categorize the app using sort_key for potential sorting
        if [[ "$app_name" =~ (Adobe|Acrobat) ]]; then
            adobe_apps+=("$sort_key")
        elif [[ "$app_name" =~ Microsoft ]]; then
            microsoft_apps+=("$sort_key")
        elif [[ "$app_name" =~ (Logic Pro|GarageBand|Arturia|iZotope|Analog Lab|Piano V|VOX Continental|Wurli) ]]; then
            audio_apps+=("$sort_key")
        elif [[ "$app_name" =~ (Focusrite|Loupedeck|CalDigit|Elgato|Blackmagic) ]]; then
            hardware_apps+=("$sort_key")
        elif [[ "$app_name" =~ (Carbon Copy Cloner|Backblaze|Setapp|CleanMyMac|GoodSync|Keyboard Maestro) ]]; then
            business_apps+=("$sort_key")
        elif [[ "$app_name" =~ (JetBrains|Xcode|Developer|Cursor|Tower) ]]; then
            dev_apps+=("$sort_key")
        elif [[ "$app_name" =~ (Kindle|Prime Video|Netflix|Disney|Spotify) ]]; then
            media_apps+=("$sort_key")
        elif [[ "$app_name" =~ (Cardhop|Fantastical|OmniFocus|DEVONthink|Tinderbox|Scrivener|Notebooks) ]]; then
            productivity_apps+=("$sort_key")
        elif [[ "$app_name" =~ (Arc|Firefox|Chrome) ]]; then
            browser_apps+=("$sort_key")
        elif [[ "$app_name" =~ (Mozilla VPN|RoboForm|1Password) ]]; then
            security_apps+=("$sort_key")
        elif [[ "$app_name" =~ (Steam|Epic Games|Zoom|WhatsApp|Teams) ]]; then
            entertainment_apps+=("$sort_key")
        else
            other_apps+=("$sort_key")
        fi
    done < <(find /Applications -name "*.app" -maxdepth 2 -print0 2>/dev/null)
    
    # Helper function to sort and display a category
    display_category() {
        local category_name="$1"
        local emoji="$2"
        local array_name="$3"
        
        # Get array elements using indirect parameter expansion
        local category_array=()
        eval "category_array=(\"\${${array_name}[@]}\")"
        
        if [[ ${#category_array[@]} -gt 0 ]]; then
            echo "${emoji} ${category_name}:"
            
            # Sort array if verbose mode is enabled (by date, oldest first)
            local sorted_apps=()
            if [[ "${VERBOSE}" == true ]]; then
                # Sort by the date part (before the pipe)
                while IFS= read -r line; do
                    sorted_apps+=("$line")
                done < <(printf '%s\n' "${category_array[@]}" | sort)
            else
                sorted_apps=("${category_array[@]}")
            fi
            
            # Display apps (extract display part after pipe separator)
            for sort_key in "${sorted_apps[@]}"; do
                local display_text="${sort_key#*|}"  # Remove everything before and including the pipe
                echo "   • $display_text"
            done
            echo ""
            app_found=true
        fi
    }
    
    # Display categories using the helper function
    display_category "Adobe Creative Suite" "🎨" "adobe_apps"
    display_category "Microsoft Office" "🏢" "microsoft_apps"
    display_category "Professional Audio" "🎵" "audio_apps"
    display_category "Hardware Utilities" "🔧" "hardware_apps"
    display_category "Business Tools" "💼" "business_apps"
    display_category "Development Tools" "🧑‍💻" "dev_apps"
    display_category "Media & Content" "📱" "media_apps"
    display_category "Productivity" "🎯" "productivity_apps"
    display_category "Browsers & Web" "🌐" "browser_apps"
    display_category "Security & VPN" "🛡️" "security_apps"
    display_category "Entertainment" "🎮" "entertainment_apps"
    display_category "Other Applications" "🔍" "other_apps"
    
    if [[ "$app_found" == false ]]; then
        echo "✅ No unmanaged applications found!"
        echo ""
    fi
    
    echo "💡 Update Recommendations:"
    echo "   • Adobe apps: Use Adobe Creative Cloud for updates"
    echo "   • Microsoft apps: Use Microsoft AutoUpdate or built-in updaters"
    echo "   • Other apps: Check app menus for 'Check for Updates' options"
    echo ""
    echo "✨ ────────────────────────────────────────────────────────────────────────────────"
}

# parse_arguments: Process command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -a|--audit)
                AUDIT=true
                shift
                ;;
            -l|--list-unmanaged)
                LIST_UNMANAGED=true
                shift
                ;;
            -s|--skip)
                if [[ -z "${2:-}" ]]; then
                    error "Option --skip requires an argument"
                fi
                SKIP_UPDATES="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            *)
                error "Unknown option: $1\nUse --help for usage information"
                ;;
        esac
    done
}

# --- Main Script ---

main() {
    # Set up signal handlers for cleanup
    trap cleanup EXIT INT TERM

    # Parse command line arguments
    parse_arguments "$@"
    
    # Show audit if requested
    if [[ "${AUDIT}" == true ]]; then
        show_audit
        exit 0
    fi
    
    # Show unmanaged apps if requested
    if [[ "${LIST_UNMANAGED}" == true ]]; then
        show_unmanaged_apps
        exit 0
    fi

    # Guard against double execution
    if [[ -n "${BREW_CONDA_UPDATE_ALREADY_RUN:-}" ]]; then
        log "Update script already running in this session. Exiting."
        exit 0
    fi
    export BREW_CONDA_UPDATE_ALREADY_RUN=1

    # Beautiful opening
    echo ""
    echo "✨ ────────────────────────────────────────────────────────────────────────────────"
    echo ""
    if [[ "${DRY_RUN}" == true ]]; then
        echo "🔍 System Update Preview"
        echo "   Showing what would be updated (no changes will be made)"
    else
        echo "🚀 System Update Session"
        echo "   Refreshing your development environment"
    fi
    
    if [[ -n "${SKIP_UPDATES}" ]]; then
        echo "   Skipping: ${SKIP_UPDATES}"
    fi
    
    echo ""
    echo "✨ ────────────────────────────────────────────────────────────────────────────────"

    # Always log to file
    echo "==> Starting update process at ${TIMESTAMP}" >> "${LOG_FILE}"
    echo "==> Log file: ${LOG_FILE}" >> "${LOG_FILE}"
    [[ "${DRY_RUN}" == true ]] && echo "==> DRY-RUN MODE: No changes will be made" >> "${LOG_FILE}"
    [[ -n "${SKIP_UPDATES}" ]] && echo "==> Skipping updates: ${SKIP_UPDATES}" >> "${LOG_FILE}"

    # Check for required core commands
    verbose_log "Checking required tools..."
    local required_commands=(softwareupdate brew conda)
    local missing_commands=()

    for cmd in "${required_commands[@]}"; do
        if ! check_command "${cmd}"; then
            missing_commands+=("${cmd}")
        fi
    done

    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        error "Missing required commands: ${missing_commands[*]}"
    fi

    # Run updates with beautiful grouping
    show_section_header "🖥️  System"
    update_macos
    
    show_section_header "🛠️  Development Tools"
    update_oh_my_zsh
    update_homebrew
    
    show_section_header "🐍 Languages & Runtimes"
    update_conda
    update_uv
    update_nvm
    update_npm_global_packages
    
    show_section_header "📱 Applications"
    update_mas

    # Show summary
    show_final_summary
}

# Execute main function with all arguments
main "$@"
