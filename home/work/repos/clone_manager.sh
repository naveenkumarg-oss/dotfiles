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

    local raw_path="${repo_url#*:}"
    local clean_path="${raw_path%.git}"

    local relative_dir
    relative_dir=$(dirname "$clean_path")
    
    local repo_name
    repo_name=$(basename "$clean_path")

    if [[ "$relative_dir" == "." ]]; then
        relative_dir=""
        local target_parent_dir="${SCRIPT_DIR}"
    else
        local target_parent_dir="${SCRIPT_DIR}/${relative_dir}"
    fi

    local final_repo_path="${target_parent_dir}/${repo_name}"

    if [[ -d "$final_repo_path" ]]; then
        if git -C "$final_repo_path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            log "${BLUE}" "Skipping: ${repo_name} (Already exists)"
            return 0
        fi
    fi

    if [[ ! -d "$target_parent_dir" ]]; then
        log "${INFO}" "Creating directory: ${relative_dir}"
        mkdir -p "$target_parent_dir"
    fi

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

    log "${INFO}" "Reading repositories from ${INPUT_FILE}..."
    
    local processed_count=0

    while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
        # 1. Strip Carriage Returns (CRLF handling) and Trim Whitespace
        local line
        line=$(echo "$raw_line" | tr -d '\r')
        line="${line#${line%%[![:space:]]*}}" # Leading trim
        line="${line%${line##*[![:space:]]}}" # Trailing trim

        # 2. Skip Logic (Improved for multiple hashes like ##)
        [[ -z "$line" ]] && continue
        [[ "$line" == "#"* ]] && continue

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