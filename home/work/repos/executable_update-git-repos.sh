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

# Function to get current time in seconds
get_time() {
    date +%s
}

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
    local start_time=$(get_time)
    local status=0
    local current_dir=$PWD

    # Verify repository path exists and is a directory
    if [[ ! -d "$repo_path" ]]; then
        log "ERROR" "Directory not found: $repo_path"
        return 1
    fi

    # Verify it's a git repository
    if [[ ! -d "$repo_path/.git" ]]; then
        log "ERROR" "Not a git repository: $repo_path"
        return 1
    fi

    # Change to repository directory
    if ! cd "$repo_path" 2>/dev/null; then
        log "ERROR" "Cannot access directory: $repo_path"
        return 1
    fi

    # Quick check for remote repository
    if ! git remote get-url origin >/dev/null 2>&1; then
        log "WARN" "Skipping $repo_name: no remote origin"
        cd "$current_dir" 2>/dev/null
        return 0
    fi

    # Use built-in status check (fastest method)
    local branch_status
    if ! branch_status=$(git status -uno --porcelain=v2 --branch 2>/dev/null); then
        log "ERROR" "Failed to get status for $repo_name"
        cd "$current_dir" 2>/dev/null
        return 1
    fi

    # Check if repository needs update
    if ! echo "$branch_status" | grep -q "behind"; then
        log "INFO" "Already up-to-date: $repo_name"
        cd "$current_dir" 2>/dev/null
        return 0
    fi

    # Quick check for uncommitted changes using porcelain v2
    if [[ -n $(git status --porcelain=v2 -uno) ]]; then
        log "WARN" "Skipping $repo_name: uncommitted changes"
        cd "$current_dir" 2>/dev/null
        return 1
    fi

    # Get current branch using modern command
    local current_branch
    if ! current_branch=$(git branch --show-current 2>/dev/null); then
        log "ERROR" "Failed to determine current branch for $repo_name"
        cd "$current_dir" 2>/dev/null
        return 1
    fi
    
    # Perform optimized pull
    if git -c protocol.version=2 pull --ff-only --no-tags --prune origin "$current_branch" >/dev/null 2>&1; then
        local end_time=$(get_time)
        local duration=$((end_time - start_time))
        log "INFO" "Updated $repo_name (${duration}s)"
        
        # Trigger background maintenance
        (git maintenance run --quiet --auto >/dev/null 2>&1 &)
        status=0
    else
        log "ERROR" "Failed to update $repo_name"
        status=1
    fi

    # Return to original directory
    cd "$current_dir" 2>/dev/null
    return $status
}

main() {
    local start_time=$(get_time)
    local success_count=0
    local failed_count=0
    local skipped_count=0

    # Store the starting directory
    local initial_dir=$PWD

    # Find git repositories
    local git_dirs=()
    while IFS= read -r -d $'\0' git_dir; do
        # Get the parent directory of .git
        repo_path=$(dirname "$git_dir")
        # Convert to absolute path if relative
        [[ "$repo_path" != /* ]] && repo_path="$initial_dir/$repo_path"
        git_dirs+=("$repo_path")
    done < <(find "$initial_dir" -type d -name ".git" -print0)

    local total_count=${#git_dirs[@]}
    
    if [[ $total_count -eq 0 ]]; then
        log "WARN" "No Git repositories found"
        exit 0
    fi

    log "INFO" "Found $total_count repositories"
    echo "------------------------------"

    # Process repositories
    for repo_path in "${git_dirs[@]}"; do
        # Skip if path doesn't exist
        [[ ! -d "$repo_path" ]] && continue

        # Optimize repository configuration first
        optimize_repo "$repo_path"
        
        # Update repository and track result
        if update_repo "$repo_path"; then
            ((success_count++))
        else
            case $? in
                1) ((failed_count++));;
                0) ((skipped_count++));;
            esac
        fi
    done

    # Calculate total execution time using simple integer arithmetic
    local end_time=$(get_time)
    local total_duration=$((end_time - start_time))

    # Print summary
    echo
    log "INFO" "==== Summary ===="
    log "INFO" "Total execution time: ${total_duration} seconds"
    log "INFO" "Total repositories: $total_count"
    log "INFO" "Successfully updated: $success_count"
    [[ $failed_count -gt 0 ]] && log "WARN" "Failed: $failed_count"
    [[ $skipped_count -gt 0 ]] && log "WARN" "Skipped: $skipped_count"

    # Return to initial directory
    cd "$initial_dir" 2>/dev/null || true
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