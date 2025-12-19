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
declare -r BLUE=$'\033[0;34m'
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
    # Ensure protocol v2 is used globally for Git 2.52 efficiency
    [GIT_PROTOCOL_FROM_USER]=2
)

# Git configuration settings applied to each repository
# Modern Git 2.52+ defaults are usually good, but these ensure consistency
declare -A GIT_REPO_CONFIG=(
    [core.fsmonitor]=true
    [core.untrackedCache]=true
    [feature.manyFiles]=true
    [fetch.writeCommitGraph]=true
    # Re-enabling parallel fetch for modern environments
    [fetch.parallel]=4
    [submodule.fetchJobs]=4
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
        *) color="${NC}" ;;
    esac

    printf "%b[%s]%b %s\n" "${color}" "${level}" "${NC}" "${message}"
}

# Function to get current time in seconds (optimized: no subshell/fork)
get_time_s() {
    printf '%(%s)T' -1
}

# --- Core Logic Functions ---

# Function to optimize git repository settings
optimize_repo_settings() {
    local repo_path="$1"
    # Quietly apply settings
    for config_key in "${!GIT_REPO_CONFIG[@]}"; do
        git -C "$repo_path" config "$config_key" "${GIT_REPO_CONFIG[$config_key]}" >/dev/null 2>&1 || \
            log "${WARN}" "Failed to set Git config: $config_key for $(basename "$repo_path")"
    done
    
    # Modern Git Maintenance (prefetch, commit-graph, loose-objects, incremental-repack)
    git -C "$repo_path" maintenance register --quiet >/dev/null 2>&1 || true
}

# Function to update a single repository
# Returns: 0 = Updated, 1 = Error, 2 = Skipped/No-Op
update_single_repo() {
    local repo_path="$1"
    local repo_name
    repo_name=$(basename "$repo_path")
    local start_time
    start_time=$(get_time_s)

    log "${INFO}" "Processing repository: $repo_name"

    # 1. Access Check
    if [[ ! -d "$repo_path" ]]; then
        log "${ERROR}" "Directory not found: $repo_path"
        return 1
    fi

    # Subshell for safety
    (
        cd "$repo_path" || exit 1

        # 2. Validate Git Repository (Handles .git dirs and Worktree files)
        if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            log "${WARN}" "Not a valid Git work tree: $repo_path"
            exit 1
        fi

        # 3. Remote Check
        local remote_url
        if ! remote_url=$(git remote get-url origin 2>/dev/null); then
            log "${WARN}" "Skipping $repo_name: no remote origin found."
            exit 2 # Exit code 2 for SKIP
        fi

        # 4. Get Current Branch (Plumbing command)
        local current_branch
        if ! current_branch=$(git symbolic-ref --short HEAD 2>/dev/null); then
            log "${ERROR}" "Detached HEAD or invalid branch state in $repo_name."
            exit 1
        fi

        # 5. Fetch (Optimized)
        # Using --jobs and --prune. Protocol v2 handles the negotiation efficiently.
        if ! git fetch origin --prune --jobs=4 --quiet >/dev/null 2>&1; then
            log "${ERROR}" "Failed to fetch $repo_name."
            exit 1
        fi

        # 6. Check Upstream Configuration
        local upstream
        if ! upstream=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null); then
             log "${WARN}" "Skipping $repo_name: Branch '$current_branch' has no upstream configured."
             exit 2
        fi

        # 7. Check Divergence (The Modern Way: rev-list)
        # This returns "A	B" where A is ahead count, B is behind count.
        local counts
        counts=$(git rev-list --left-right --count "${upstream}...HEAD" 2>/dev/null)
        
        local ahead=${counts%	*}
        local behind=${counts#*	}

        # 8. Uncommitted Changes Check (Porcelain v2 is correct here)
        if [[ -n $(git status --porcelain=v2 -uno) ]]; then
            # If we are behind, this is a blocker. If we are up to date, it's just a warning.
            if [[ "$behind" -gt 0 ]]; then
                log "${WARN}" "Skipping update for $repo_name: Uncommitted changes present."
                exit 1
            fi
        fi

        # 9. Update Logic
        if [[ "$behind" -gt 0 && "$ahead" -eq 0 ]]; then
            log "${INFO}" "$repo_name is behind by $behind commits. Pulling..."
            
            if git pull --ff-only origin "$current_branch" --quiet >/dev/null 2>&1; then
                local end_time
                end_time=$(get_time_s)
                local duration=$((end_time - start_time))
                log "${GREEN}" "Successfully updated $repo_name in ${duration}s"
                
                # Background maintenance trigger
                git maintenance run --auto --quiet >/dev/null 2>&1 &
                exit 0 # Success
            else
                log "${ERROR}" "Failed to fast-forward $repo_name."
                exit 1
            fi
        elif [[ "$behind" -gt 0 && "$ahead" -gt 0 ]]; then
             log "${WARN}" "$repo_name has diverged (Ahead: $ahead, Behind: $behind). Manual intervention required."
             exit 1
        else
            log "${BLUE}" "$repo_name is up-to-date."
            exit 2 # Skip
        fi
    )
    return $?
}

# Main execution logic
main() {
    local start_total_time
    start_total_time=$(get_time_s)
    local success_count=0
    local failed_count=0
    local skipped_count=0

    # Set Git environment variables
    for var_name in "${!GIT_ENV_VARS[@]}"; do
        export "$var_name"="${GIT_ENV_VARS[$var_name]}"
    done

    # Find git repositories
    # We look for .git (dir or file) to support worktrees
    local git_items=()
    while IFS= read -r -d $'\0' item; do
        local repo_root
        if [[ -d "$item" ]]; then
            repo_root=$(dirname "$item")
        else
            # It's a file (worktree or submodule), parent is the root
            repo_root=$(dirname "$item")
        fi
        git_items+=("$(readlink -f "$repo_root")")
    done < <(find "$REPO_SEARCH_ROOT" -name ".git" -print0)

    # Sort and remove duplicates (in case find hits nested things oddly)
    IFS=$'\n' read -d '' -r -a unique_repos < <(printf "%s\n" "${git_items[@]}" | sort -u && printf '\0')

    local total_count=${#unique_repos[@]}
    
    if [[ $total_count -eq 0 ]]; then
        log "${WARN}" "No Git repositories found in $REPO_SEARCH_ROOT."
        return 0
    fi

    log "${INFO}" "Found $total_count unique repositories in $REPO_SEARCH_ROOT"
    echo "------------------------------"

    for repo_path in "${unique_repos[@]}"; do
        optimize_repo_settings "$repo_path"
        
        update_single_repo "$repo_path"
        local exit_code=$?
        
        case $exit_code in
            0) ((success_count++)) ;;
            1) ((failed_count++)) ;;
            2) ((skipped_count++)) ;;
        esac
    done

    local end_total_time
    end_total_time=$(get_time_s)
    local total_duration=$((end_total_time - start_total_time))

    echo
    log "${INFO}" "==== Summary ===="
    log "${INFO}" "Total execution time: ${total_duration} seconds"
    log "${INFO}" "Total repositories: $total_count"
    log "${GREEN}" "Successfully updated: $success_count"
    if [[ $failed_count -gt 0 ]]; then
        log "${ERROR}" "Failed / Manual Check Needed: $failed_count"
    fi
    if [[ $skipped_count -gt 0 ]]; then
        log "${BLUE}" "Skipped (Up-to-date/No Remote): $skipped_count"
    fi
}

# --- Pre-execution Checks and Script Entry Point ---

initial_dir="$PWD"
trap 'cd "$initial_dir" 2>/dev/null || true' EXIT

# Parse command-line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--directory)
                if [[ -n "${2:-}" && -d "$2" ]]; then
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
                echo "  -h, --help              Display this help message."
                exit 0
                ;;
            *)
                log "${ERROR}" "Unknown argument: $1"
                exit 1
                ;;
        esac
    done
}

parse_args "$@"
main "$@"