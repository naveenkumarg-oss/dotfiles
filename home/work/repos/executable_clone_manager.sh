#!/bin/bash

# --- Script Configuration ---
set -euo pipefail
shopt -s nullglob

# Configuration
declare -r INPUT_FILE="repos.md"
declare -r TARGET_HOST_PREFIX="git@gitlab.otxlab.net"
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
declare -r SSH_SOCKET="/tmp/git-ssh-mux-%r@%h:%p-$$"
export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=5 -o ControlMaster=auto -o ControlPath=${SSH_SOCKET} -o ControlPersist=10m"
export GIT_TERMINAL_PROMPT=0
export GIT_PROTOCOL_FROM_USER=2

# --- Resource Management ---
cleanup() {
    local exit_code=$?
    # Ensure we close the socket and clean up the background SSH process
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

    # Precise path extraction
    local raw_path="${repo_url#*:}"
    local clean_path="${raw_path%.git}"

    local relative_dir
    relative_dir=$(dirname "$clean_path")
    local repo_name
    repo_name=$(basename "$clean_path")

    # Absolute path resolution
    local target_parent_dir
    if [[ "$relative_dir" == "." ]]; then
        target_parent_dir="${SCRIPT_DIR}"
    else
        target_parent_dir="${SCRIPT_DIR}/${relative_dir}"
    fi

    local final_repo_path="${target_parent_dir}/${repo_name}"

    # Idempotency check
    if [[ -d "$final_repo_path" ]]; then
        if git -C "$final_repo_path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            log "${BLUE}" "Skipping: ${repo_name} (Already exists at ${relative_dir})"
            return 0
        fi
    fi

    # Creation and Clone
    [[ ! -d "$target_parent_dir" ]] && mkdir -p "$target_parent_dir"

    log "${INFO}" "Cloning ${repo_name}..."
    
    if git clone --quiet --jobs=4 "$repo_url" "$final_repo_path"; then
        log "${GREEN}" "Successfully cloned ${repo_name}"
        git -C "$final_repo_path" maintenance register --quiet >/dev/null 2>&1 || true
    else
        log "${ERROR}" "Failed to clone ${repo_url}"
        [[ -d "$final_repo_path" ]] && rm -rf "$final_repo_path"
        return 1
    fi
}

main() {
    local input_path="${SCRIPT_DIR}/${INPUT_FILE}"

    if [[ ! -f "$input_path" ]]; then
        log "${ERROR}" "Input file not found: ${input_path}"
        exit 1
    fi

    log "${INFO}" "Scanning ${INPUT_FILE} for ${TARGET_HOST_PREFIX} repositories..."
    
    local processed_count=0

    # The Expert Approach:
    # Use grep to find only lines containing the host prefix.
    # Use 'tr' to strip potential Windows carriage returns.
    # Use 'sed' to trim any leading/trailing whitespace around the URL.
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        parse_and_clone "$line" || true
        processed_count=$((processed_count + 1))
    done < <(tr -d '\r' < "$input_path" | grep "${TARGET_HOST_PREFIX}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    echo "------------------------------"
    log "${INFO}" "Execution complete. $processed_count valid repository entries processed."
}

main