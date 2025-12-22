#!/bin/bash

# --- Script Configuration ---
set -euo pipefail
shopt -s nullglob

# Configuration
declare -r INPUT_FILE="repos.md"
declare -r TARGET_HOST_PREFIX="git@gitlab.otxlab.net"
# Use readlink -f to resolve absolute path even if script is symlinked
declare -r SCRIPT_DIR="$(readlink -f "$(dirname "${BASH_SOURCE[0]}")")"

# Color codes
declare -r RED=$'\033[0;31m'
declare -r GREEN=$'\033[0;32m'
declare -r BLUE=$'\033[0;34m'
declare -r YELLOW=$'\033[1;33m'
declare -r NC=$'\033[0m'

# Log levels
declare -r INFO="INFO"
declare -r WARN="WARN"
declare -r ERROR="ERROR"

# --- Git Environment Optimization ---
# SSH Multiplexing: Reuse the connection socket for high-speed sequential clones.
# We define a specific socket path to allow easy cleanup later.
declare -r SSH_SOCKET="/tmp/git-ssh-mux-%r@%h:%p-$$"
export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=5 -o ControlMaster=auto -o ControlPath=${SSH_SOCKET} -o ControlPersist=10m"
export GIT_TERMINAL_PROMPT=0
export GIT_PROTOCOL_FROM_USER=2

# --- Resource Management ---

# Cleanup function to kill the SSH master process on exit
cleanup() {
    local exit_code=$?
    # Send strict check command to close the master connection if it exists
    ssh -O exit -o ControlPath="${SSH_SOCKET}" "${TARGET_HOST_PREFIX%%:*}" 2>/dev/null || true
    exit "$exit_code"
}
trap cleanup EXIT

# --- Helper Functions ---

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

# --- Core Logic ---

parse_and_clone() {
    local repo_url="$1"

    # 1. Path Tokenization (Native Bash string manipulation)
    # Remove host prefix (e.g., "git@gitlab.otxlab.net:")
    local raw_path="${repo_url#*:}"
    
    # Remove .git suffix
    local clean_path="${raw_path%.git}"

    # Extract directory and repo name
    local relative_dir
    relative_dir=$(dirname "$clean_path")
    
    local repo_name
    repo_name=$(basename "$clean_path")

    # Handle root-level repos (where dirname returns ".")
    if [[ "$relative_dir" == "." ]]; then
        relative_dir=""
        local target_parent_dir="${SCRIPT_DIR}"
    else
        local target_parent_dir="${SCRIPT_DIR}/${relative_dir}"
    fi

    local final_repo_path="${target_parent_dir}/${repo_name}"

    # 2. Idempotency Check
    if [[ -d "$final_repo_path" ]]; then
        # Check if it is actually a git repo
        if git -C "$final_repo_path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            log "${BLUE}" "Skipping: ${repo_name} (Already exists)"
            return 0
        else
            log "${WARN}" "Conflict: Directory ${final_repo_path} exists but is not a Git repo. Skipping for safety."
            return 1
        fi
    fi

    # 3. Directory Creation
    if [[ ! -d "$target_parent_dir" ]]; then
        log "${INFO}" "Creating directory: ${relative_dir}"
        mkdir -p "$target_parent_dir" || {
            log "${ERROR}" "Failed to create directory: $target_parent_dir"
            return 1
        }
    fi

    # 4. Efficient Clone
    log "${INFO}" "Cloning ${repo_name}..."
    
    # --jobs=4 aids submodule fetching if present; core clone speed comes from SSH mux + protocol v2
    if git clone --quiet --jobs=4 "$repo_url" "$final_repo_path"; then
        log "${GREEN}" "Successfully cloned ${repo_name}"
        
        # Post-clone: Register for maintenance and optimize local config
        # We ignore errors here as they are non-critical to the clone success
        git -C "$final_repo_path" maintenance register --quiet >/dev/null 2>&1 || true
        git -C "$final_repo_path" config fetch.parallel 0 >/dev/null 2>&1 || true
    else
        log "${ERROR}" "Failed to clone ${repo_url}"
        
        # Safety check: Ensure path is valid and not root before deleting
        if [[ -n "$final_repo_path" && "$final_repo_path" != "/" && -d "$final_repo_path" ]]; then
             rm -rf "$final_repo_path"
        fi
        return 1
    fi
}

main() {
    local input_path="${SCRIPT_DIR}/${INPUT_FILE}"

    if [[ ! -f "$input_path" ]]; then
        log "${ERROR}" "Input file not found: ${input_path}"
        exit 1
    fi

    log "${INFO}" "Reading repositories from ${INPUT_FILE}..."
    
    local processed_count=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        # 1. Native Bash Whitespace Trimming (High Performance)
        # Uses Regex to strip leading/trailing space without forking 'xargs'
        if [[ "$line" =~ ^[[:space:]]*(.*)[[:space:]]*$ ]]; then
            line="${BASH_REMATCH[1]}"
        fi

        # 2. Skip Logic
        [[ -z "$line" ]] && continue       # Empty lines
        [[ "$line" == \#* ]] && continue   # Comments

        # 3. Match Valid Git Host
        if [[ "$line" == "${TARGET_HOST_PREFIX}"* ]]; then
            parse_and_clone "$line"
            ((processed_count++))
        fi

    done < "$input_path"

    echo "------------------------------"
    log "${INFO}" "Processing complete. Checked $processed_count repositories."
}

main