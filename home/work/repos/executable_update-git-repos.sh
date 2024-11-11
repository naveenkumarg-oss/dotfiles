#!/bin/bash

# Set error handling
set -euo pipefail

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

# Function to get the default branch name
get_default_branch() {
    local repo_path=$1
    # Try to get the default branch from remote
    local default_branch=$(cd "$repo_path" && git remote show origin | grep 'HEAD branch' | cut -d' ' -f5)
    
    # If that fails, check locally for main or master
    if [[ -z "$default_branch" ]]; then
        if git -C "$repo_path" rev-parse --verify main >/dev/null 2>&1; then
            default_branch="main"
        elif git -C "$repo_path" rev-parse --verify master >/dev/null 2>&1; then
            default_branch="master"
        fi
    fi
    
    echo "$default_branch"
}

# Function to update a single repository
update_repo() {
    local repo_path=$1
    local repo_name=$(basename "$repo_path")
    
    log "INFO" "Processing repository: $repo_name"
    
    # Check if repository is clean
    if ! git -C "$repo_path" diff --quiet HEAD; then
        log "WARN" "Skipping $repo_name: uncommitted changes present"
        return 1
    fi
    
    # Get the default branch
    local default_branch=$(get_default_branch "$repo_path")
    
    if [[ -z "$default_branch" ]]; then
        log "ERROR" "Could not determine default branch for $repo_name"
        return 1
    fi
    
    # Fetch updates
    if ! git -C "$repo_path" fetch origin; then
        log "ERROR" "Failed to fetch updates for $repo_name"
        return 1
    fi
    
    # Pull changes
    if git -C "$repo_path" pull origin "$default_branch"; then
        log "INFO" "Successfully updated $repo_name"
        return 0
    else
        log "ERROR" "Failed to pull changes for $repo_name"
        return 1
    fi
}

# Main script
main() {
    local success_count=0
    local failed_count=0
    local skipped_count=0
    
    # Find all .git directories and process their parent directories
    while IFS= read -r git_dir; do
        repo_path=$(dirname "$git_dir")
        
        if update_repo "$repo_path"; then
            ((success_count++))
        else
            ((failed_count++))
        fi
    done < <(find . -type d -name ".git")
    
    # Print summary
    echo
    log "INFO" "Update complete!"
    log "INFO" "Successfully updated: $success_count repositories"
    [[ $failed_count -gt 0 ]] && log "WARN" "Failed/Skipped: $failed_count repositories"
}

# Execute main function
main