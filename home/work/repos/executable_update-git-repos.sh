#!/bin/bash

# Set bash options for better performance
set -uo pipefail
shopt -s nullglob

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Advanced Git settings for maximum performance
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=5 -o ControlMaster=auto -o ControlPath=/tmp/ssh-git-%r@%h:%p -o ControlPersist=10m"
export GIT_HTTP_LOW_SPEED_LIMIT=1000
export GIT_HTTP_LOW_SPEED_TIME=10
export GIT_TRACE_PACKET=0
export GIT_TRACE=0
export GIT_CURL_VERBOSE=0
export GIT_TRACE_PERFORMANCE=0
export GIT_QUICK_UPDATE=true  # Custom flag for our optimized mode

# Optional: Disable TLS verify if you trust your remotes (uncomment if needed)
# export GIT_SSL_NO_VERIFY=1

# Function to log messages with mutex lock for clean output
log() {
    local level=$1
    local message=$2
    local color

    case $level in
        "INFO") color=$GREEN ;;
        "WARN") color=$YELLOW ;;
        "ERROR") color=$RED ;;
    esac

    # Use flock for thread-safe output
    flock -x 1 echo -e "${color}[${level}]${NC} ${message}"
}

# Function to optimize git repository
optimize_repo() {
    local repo_path=$1
    git -C "$repo_path" config core.fsmonitor true >/dev/null 2>&1
    git -C "$repo_path" config core.untrackedCache true >/dev/null 2>&1
    git -C "$repo_path" config feature.manyFiles true >/dev/null 2>&1
    git -C "$repo_path" config fetch.parallel 0 >/dev/null 2>&1
    git -C "$repo_path" config submodule.fetchJobs 0 >/dev/null 2>&1
    git -C "$repo_path" maintenance register --quiet >/dev/null 2>&1
}

# Function to update a single repository
update_repo() {
    local repo_path=$1
    local repo_name=${repo_path##*/}
    local start_time=$(date +%s.%N)
    local status=0

    cd "$repo_path" || return 1

    # Quick check for remote repository
    if ! git remote get-url origin >/dev/null 2>&1; then
        log "WARN" "Skipping $repo_name: no remote origin"
        return 0
    fi

    # Use sparse-checkout if available (Git 2.27+)
    git sparse-checkout init --cone >/dev/null 2>&1

    # Use built-in status check (fastest method)
    local branch_status
    branch_status=$(git status -uno --porcelain=v2 --branch | grep -E "^# branch\.(ab|oid)" || echo "")

    # Skip if no upstream changes
    if [[ ! $branch_status =~ behind ]]; then
        log "INFO" "Already up-to-date: $repo_name"
        return 0
    fi

    # Quick check for uncommitted changes using porcelain v2
    if [[ -n $(git status --porcelain=v2 -uno) ]]; then
        log "WARN" "Skipping $repo_name: uncommitted changes"
        return 1
    fi

    # Get current branch using modern command
    local current_branch
    current_branch=$(git branch --show-current)
    
    # Perform optimized pull
    if git -c protocol.version=2 pull --ff-only --no-tags --prune --recurse-submodules=no origin "$current_branch" >/dev/null 2>&1; then
        local end_time=$(date +%s.%N)
        local duration=$(printf "%.2f" "$(echo "$end_time - $start_time" | bc)")
        log "INFO" "Updated $repo_name (${duration}s)"
        
        # Trigger background maintenance
        git maintenance run --quiet --auto >/dev/null 2>&1 &
        status=0
    else
        log "ERROR" "Failed to update $repo_name"
        status=1
    fi

    cd - >/dev/null || return 1
    return $status
}

main() {
    local start_time=$(date +%s.%N)
    local success_count=0
    local failed_count=0
    local skipped_count=0

    # Find git repositories using fd if available (much faster than find)
    local git_dirs
    if command -v fd >/dev/null 2>&1; then
        mapfile -t git_dirs < <(fd '^\.git$' --type d --hidden --prune | sed 's/\/\.git$//')
    else
        # Fallback to optimized find
        mapfile -t git_dirs < <(find . -type d -name ".git" -prune -exec dirname {} \;)
    fi

    local total_count=${#git_dirs[@]}
    
    if [[ $total_count -eq 0 ]]; then
        log "WARN" "No Git repositories found"
        exit 0
    fi

    log "INFO" "Found $total_count repositories"
    echo "------------------------------"

    # Process repositories
    for repo_path in "${git_dirs[@]}"; do
        # Optimize repository configuration first
        optimize_repo "$repo_path"
        
        # Update repository
        if update_repo "$repo_path"; then
            if [[ $? -eq 0 ]]; then
                ((success_count++))
            else
                ((skipped_count++))
            fi
        else
            ((failed_count++))
        fi
    done

    # Calculate total execution time
    local end_time=$(date +%s.%N)
    local total_duration=$(printf "%.2f" "$(echo "$end_time - $start_time" | bc)")

    # Print summary
    echo
    log "INFO" "==== Summary ===="
    log "INFO" "Total execution time: ${total_duration} seconds"
    log "INFO" "Total repositories: $total_count"
    log "INFO" "Successfully updated: $success_count"
    [[ $failed_count -gt 0 ]] && log "WARN" "Failed: $failed_count"
    [[ $skipped_count -gt 0 ]] && log "WARN" "Skipped: $skipped_count"

    # Optional: Run final maintenance tasks in background
    for repo_path in "${git_dirs[@]}"; do
        (git -C "$repo_path" maintenance run --quiet --auto >/dev/null 2>&1 &)
    done
}

# Version check for modern Git features
if ! git version | grep -qE 'git version ((2\.(2[5-9]|[3-9][0-9])|[3-9])\..*|2\.47)'; then
    log "WARN" "This script requires Git 2.25 or newer for optimal performance"
    log "WARN" "Some features may not be available with your Git version"
fi

# Check for required tools
if ! command -v bc >/dev/null 2>&1; then
    log "ERROR" "bc command is required but not found"
    exit 1
fi

# Execute main function
main