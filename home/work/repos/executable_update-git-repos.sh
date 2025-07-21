#!/bin/bash

# --- Script Configuration ---
# Set bash options for better performance and error handling
set -euo pipefail
shopt -s nullglob

# Default root directory to search for repositories
REPO_SEARCH_ROOT="${PWD}"

# Color codes for output
declare -r RED=$'\033[0;31m'
declare -r GREEN=$'\033[0;32m'
declare -r YELLOW=$'\033[1;33m'
declare -r NC=$'\033[0m' # No Color
 
# Log levels
declare -r INFO="INFO"
declare -r WARN="WARN"
declare -r ERROR="ERROR"

# Git environment variables for optimized performance
declare -A GIT_ENV_VARS=(
    [GIT_TERMINAL_PROMPT]=0
    [GIT_SSH_COMMAND]="ssh -o BatchMode=yes -o ConnectTimeout=5 -o ControlMaster=auto -o ControlPath=/tmp/ssh-git-%r@%h:%p -o ControlPersist=10m"
    [GIT_HTTP_LOW_SPEED_LIMIT]=1000
    [GIT_HTTP_LOW_SPEED_TIME]=10
    [GIT_TRACE_PACKET]=0
    [GIT_TRACE]=0
    [GIT_CURL_VERBOSE]=0
    [GIT_TRACE_PERFORMANCE]=0
)

# Git configuration settings applied to each repository
declare -A GIT_REPO_CONFIG=(
    [core.fsmonitor]=true
    [core.untrackedCache]=true
    [feature.manyFiles]=true
    # Note: Disabling parallel fetch/submodule jobs can sometimes stabilize operations
    # depending on Git version and system. Adjust if performance issues arise.
    [fetch.parallel]=0
    [submodule.fetchJobs]=0
)

# --- Helper Functions ---

# Function to log messages with color
log() {
    local level="$1"
    local message="$2"
    local color=""

    case "$level" in
        "${INFO}") color="${GREEN}" ;;
        "${WARN}") color="${YELLOW}" ;;
        "${ERROR}") color="${RED}" ;;
        *) color="${NC}" ;; # Default to no color for unknown levels
    esac

    # Using printf for better formatting and avoiding 'echo -e' quirks
    printf "%b[%s]%b %s\n" "${color}" "${level}" "${NC}" "${message}"
}

# Function to get current time in seconds (for duration calculation)
get_time_s() {
    date +%s
}

# --- Core Logic Functions ---

# Function to optimize git repository settings
optimize_repo_settings() {
    local repo_path="$1"
    log "${INFO}" "Optimizing settings for $(basename "$repo_path")..."
    for config_key in "${!GIT_REPO_CONFIG[@]}"; do
        git -C "$repo_path" config "$config_key" "${GIT_REPO_CONFIG[$config_key]}" >/dev/null 2>&1 || \
            log "${WARN}" "Failed to set Git config: $config_key for $(basename "$repo_path")"
    done
    # Use || true to prevent 'set -e' from exiting if maintenance register fails
    git -C "$repo_path" maintenance register --quiet >/dev/null 2>&1 || \
        log "${WARN}" "Failed to register maintenance for $(basename "$repo_path")" || true
}

# Function to update a single repository
update_single_repo() {
    local repo_path="$1"
    local repo_name=$(basename "$repo_path")
    local start_time=$(get_time_s)

    log "${INFO}" "Processing repository: $repo_name"

    # Validate if it's a directory and a git repository
    if [[ ! -d "$repo_path" ]]; then
        log "${ERROR}" "Directory not found: $repo_path"
        return 1
    fi
    if [[ ! -d "$repo_path/.git" ]]; then
        log "${ERROR}" "Not a Git repository: $repo_path"
        return 1
    fi

    # Change to repository directory (subshell to avoid changing caller's PWD)
    (
        cd "$repo_path" || { log "${ERROR}" "Cannot access directory: $repo_path"; exit 1; }

        # Quick check for remote repository
        if ! git remote get-url origin >/dev/null 2>&1; then
            log "${WARN}" "Skipping $repo_name: no remote origin found."
            exit 0 # Exit subshell with 0 to indicate skipped, not failed
        fi

        # Get current branch
        local current_branch
        if ! current_branch=$(git branch --show-current 2>/dev/null); then
            log "${ERROR}" "Failed to determine current branch for $repo_name."
            exit 1
        fi
        
        # --- IMPORTANT FIX: FETCH BEFORE STATUS CHECK ---
        log "${INFO}" "Fetching latest changes for $repo_name..."
        if ! git fetch origin >/dev/null 2>&1; then
            log "${ERROR}" "Failed to fetch from remote for $repo_name. Check network or authentication."
            exit 1
        fi
        # --- END IMPORTANT FIX ---

        # Use built-in status check (fastest method) - now it will be accurate
        local branch_status
        if ! branch_status=$(git status -uno --porcelain=v2 --branch 2>/dev/null); then
            log "${ERROR}" "Failed to get status for $repo_name."
            exit 1
        fi

        # --- CRITICAL FIX: Update regex for detecting 'behind' status ---
        # Look for the '# branch.ab +A -B' line.
        # We want to pull if A (ahead) is 0 AND B (behind) is greater than 0.
        if echo "$branch_status" | grep -qE '^# branch.ab \+0 -[1-9][0-9]*$'; then
            log "${INFO}" "Repository $repo_name is behind remote. Pulling changes..."
            # Proceed to pull, no exit here.
        else
            log "${INFO}" "Already up-to-date: $repo_name"
            exit 0 # Exit subshell, as no pull is needed
        fi
        # --- END CRITICAL FIX ---


        # Check for uncommitted changes using porcelain v2
        if [[ -n $(git status --porcelain=v2 -uno) ]]; then
            log "${WARN}" "Skipping $repo_name: uncommitted changes present."
            exit 1 # Treat as a failure to update, not a skip
        fi

        # Perform optimized pull
        log "${INFO}" "Updating $repo_name..."
        # We specify origin and current_branch explicitly for clarity and robustness
        if git -c protocol.version=2 pull --ff-only --no-tags --prune origin "$current_branch" >/dev/null 2>&1; then
            local end_time=$(get_time_s)
            local duration=$((end_time - start_time))
            log "${GREEN}" "Successfully updated $repo_name (${duration}s)"
            
            # Trigger background maintenance
            git maintenance run --quiet --auto >/dev/null 2>&1 &
            exit 0
        else
            log "${ERROR}" "Failed to update $repo_name."
            exit 1
        fi
    ) # End of subshell

    return $? # Return exit status of the subshell
}

# Main execution logic
main() {
    # initial_dir is now globally defined.
    # This function uses the global initial_dir set at script start.
    local start_total_time=$(get_time_s)
    local success_count=0
    local failed_count=0
    local skipped_count=0 # For repos explicitly skipped (e.g., no remote)

    # Set Git environment variables
    for var_name in "${!GIT_ENV_VARS[@]}"; do
        export "$var_name"="${GIT_ENV_VARS[$var_name]}"
    done

    # Find git repositories
    local git_dirs=()
    # Use -L for find to follow symlinks if desired, otherwise omit
    while IFS= read -r -d $'\0' git_dir; do
        # Get the parent directory of .git
        local repo_path=$(dirname "$git_dir")
        # Ensure absolute path
        repo_path=$(readlink -f "$repo_path")
        git_dirs+=("$repo_path")
    done < <(find "$REPO_SEARCH_ROOT" -type d -name ".git" -print0)

    local total_count=${#git_dirs[@]}
    
    if [[ $total_count -eq 0 ]]; then
        log "${WARN}" "No Git repositories found in $REPO_SEARCH_ROOT."
        return 0
    fi

    log "${INFO}" "Found $total_count repositories in $REPO_SEARCH_ROOT"
    echo "------------------------------"

    # Process repositories
    for repo_path in "${git_dirs[@]}"; do
        # Optimize repository configuration first
        optimize_repo_settings "$repo_path"
        
        # Update repository and track result
        if update_single_repo "$repo_path"; then
            ((success_count++))
        else
            local exit_code=$?
            # update_single_repo explicitly exits subshell with 0 for skipped, 1 for failed
            if [[ $exit_code -eq 0 ]]; then # This means it was explicitly skipped (e.g., no remote, already up-to-date)
                ((skipped_count++))
            else # Failed to update (e.g., uncommitted changes, pull error, directory access issue)
                ((failed_count++))
            fi
        fi
    done

    local end_total_time=$(get_time_s)
    local total_duration=$((end_total_time - start_total_time))

    # Print summary
    echo
    log "${INFO}" "==== Summary ===="
    log "${INFO}" "Total execution time: ${total_duration} seconds"
    log "${INFO}" "Total repositories: $total_count"
    log "${INFO}" "Successfully updated: $success_count"
    if [[ $failed_count -gt 0 ]]; then
        log "${ERROR}" "Failed to update: $failed_count"
    fi
    if [[ $skipped_count -gt 0 ]]; then
        log "${WARN}" "Skipped (no remote/no update needed): $skipped_count"
    fi
}

# --- Pre-execution Checks and Script Entry Point ---

# Global variable to store the initial directory
# This MUST be defined before the trap command.
initial_dir="$PWD"

# Trap to restore initial directory on exit
# This should come AFTER initial_dir is defined.
trap 'cd "$initial_dir" 2>/dev/null || true' EXIT

# Check for Git version for modern features
check_git_version() {
    if ! git version | grep -qE 'git version ((2\.(2[5-9]|[3-9][0-9])|[3-9])\..*|2\.47)'; then
        log "${WARN}" "This script recommends Git 2.25 or newer for optimal performance."
        log "${WARN}" "Some features may not be fully optimized with your current Git version."
    fi
}

# Parse command-line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--directory)
                if [[ -n "$2" && -d "$2" ]]; then
                    REPO_SEARCH_ROOT=$(readlink -f "$2")
                    shift 2
                else
                    log "${ERROR}" "Error: Directory not provided or does not exist for -d/--directory."
                    exit 1
                fi
                ;;
            -h|--help)
                echo "Usage: $0 [-d <directory>]"
                echo "  -d, --directory <path>  Specify the root directory to search for Git repositories."
                echo "                          Defaults to the current working directory."
                echo "  -h, --help              Display this help message."
                exit 0
                ;;
            *)
                log "${ERROR}" "Unknown argument: $1"
                exit 1
                ;;
        esac # Corrected from 'esutaac'
    done
}

# Main script execution flow
parse_args "$@"
check_git_version
main "$@"
