#!/bin/bash

# Set error handling
set -uo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to log messages with color
log() {
    local level=$1
    local message=$2
    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
    esac
}

# Function to update a single repository
update_repo() {
    local repo_path=$1
    local repo_name=$(basename "$repo_path")
    local status=0
    
    # Quick check if repo has remote changes before doing anything else
    if ! git -C "$repo_path" remote update --prune > /dev/null 2>&1; then
        log "ERROR" "Failed to check remote updates for $repo_name"
        return 1
    }

    # Check if we're already up to date
    local LOCAL=$(git -C "$repo_path" rev-parse @{0})
    local REMOTE=$(git -C "$repo_path" rev-parse @{u})

    if [ "$LOCAL" = "$REMOTE" ]; then
        log "INFO" "Already up to date: $repo_name"
        return 0
    }
    
    # Check if repository is clean only if we need to update
    if ! git -C "$repo_path" diff --quiet HEAD 2>/dev/null; then
        log "WARN" "Skipping $repo_name: uncommitted changes present"
        return 1
    }
    
    # Get current branch name directly (faster than checking remote)
    local current_branch=$(git -C "$repo_path" symbolic-ref --short HEAD 2>/dev/null)
    if [[ -z "$current_branch" ]]; then
        log "ERROR" "Could not determine current branch for $repo_name"
        return 1
    }
    
    # Pull changes only if we need to update
    if git -C "$repo_path" pull --ff-only origin "$current_branch" 2>/dev/null; then
        log "INFO" "Successfully updated $repo_name"
        status=0
    else
        log "ERROR" "Failed to pull changes for $repo_name"
        status=1
    fi
    
    return $status
}

# Main script
main() {
    local success_count=0
    local failed_count=0
    local total_count=0
    local start_time=$(date +%s)
    
    # Pre-find all git repositories to avoid repeated find operations
    mapfile -t git_dirs < <(find . -type d -name ".git" -prune)
    total_count=${#git_dirs[@]}
    
    log "INFO" "Found $total_count repositories to process"
    echo "------------------------------"
    
    # Process repositories
    for git_dir in "${git_dirs[@]}"; do
        repo_path=$(dirname "$git_dir")
        
        if update_repo "$repo_path"; then
            ((success_count++))
        else
            ((failed_count++))
        fi
    done
    
    # Calculate execution time
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Print summary
    echo
    log "INFO" "Update complete in ${duration} seconds!"
    log "INFO" "Total repositories found: $total_count"
    log "INFO" "Successfully updated: $success_count repositories"
    [[ $failed_count -gt 0 ]] && log "WARN" "Failed/Skipped: $failed_count repositories"
}

# Execute main function
main