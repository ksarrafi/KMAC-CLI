#!/bin/bash
# TOOLKIT_NAME: Git Guardian
# TOOLKIT_DESC: Scan staged files for leaked secrets before commit
# TOOLKIT_KEY: 5
# TOOLKIT_HOOKS: pre-commit

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../scripts/_ui.sh
source "$SCRIPT_DIR/../scripts/_ui.sh"

_SECRET_PATTERNS=(
    'AKIA[0-9A-Z]{16}'
    'sk-[a-zA-Z0-9]{48}'
    'ghp_[a-zA-Z0-9]{36}'
    'glpat-[a-zA-Z0-9_-]{20}'
    'xox[bpoas]-[0-9]{10,13}-[a-zA-Z0-9-]+'
    'sk-ant-api[a-zA-Z0-9_-]{90,}'
    'AIza[0-9A-Za-z_-]{35}'
    'SG\.[a-zA-Z0-9_-]{22}\.[a-zA-Z0-9_-]{43}'
    'eyJ[a-zA-Z0-9_-]*\.eyJ[a-zA-Z0-9_-]*\.[a-zA-Z0-9_-]*'
)

git_guardian_scan() {
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        return 0
    fi

    local staged_files
    staged_files=$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null)
    [[ -z "$staged_files" ]] && return 0

    local found=0
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        [[ ! -f "$file" ]] && continue
        # Skip binary files
        file -b --mime "$file" 2>/dev/null | grep -q "text/" || continue

        for pattern in "${_SECRET_PATTERNS[@]}"; do
            local matches
            matches=$(grep -nE "$pattern" "$file" 2>/dev/null)
            if [[ -n "$matches" ]]; then
                if (( found == 0 )); then
                    ui_warn "Possible secrets detected in staged files:"
                    echo ""
                fi
                echo "  $file:"
                while IFS= read -r match; do
                    echo "    $match"
                done <<< "$matches"
                found=1
            fi
        done
    done <<< "$staged_files"

    if (( found )); then
        echo ""
        ui_fail "Commit blocked — review flagged lines above"
        echo "  Use 'git commit --no-verify' to bypass (not recommended)"
        return 1
    fi
    return 0
}

case "${1:-}" in
    pre-commit)
        git_guardian_scan
        exit $?
        ;;
    scan|"") git_guardian_scan ;;
    help) echo "Usage: kmac git-guardian [scan]" ;;
    *) echo "Unknown command: $1"; exit 1 ;;
esac
