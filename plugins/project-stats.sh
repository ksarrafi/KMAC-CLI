#!/bin/bash
# TOOLKIT_NAME: Project Stats
# TOOLKIT_DESC: Display code statistics, dependency health, and repo metrics
# TOOLKIT_KEY: 6
# TOOLKIT_HOOKS: on-startup

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../scripts/_ui.sh
source "$SCRIPT_DIR/../scripts/_ui.sh"

_project_stats_startup_line() {
    local dir="${1:-.}"
    if ! git -C "$dir" rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
        return 0
    fi
    local total_commits dirty
    total_commits=$(git -C "$dir" rev-list --count HEAD 2>/dev/null || echo "0")
    dirty=$(git -C "$dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    echo -e "  ${DIM}Project stats:${NC} ${total_commits} commits · ${dirty} uncommitted change(s)"
}

project_stats_report() {
    local dir="${1:-.}"

    if ! git -C "$dir" rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
        ui_warn "Not a git repository"
        return 1
    fi

    title_box "Project Stats" "📊"

    local total_commits
    total_commits=$(git -C "$dir" rev-list --count HEAD 2>/dev/null || echo "0")
    local contributors
    contributors=$(git -C "$dir" shortlog -sn HEAD 2>/dev/null | wc -l | tr -d ' ')
    local first_commit
    first_commit=$(git -C "$dir" log --reverse --format='%ai' 2>/dev/null | head -1 | cut -d' ' -f1)
    local last_commit
    last_commit=$(git -C "$dir" log -1 --format='%ar' 2>/dev/null)
    local branches
    branches=$(git -C "$dir" branch -a 2>/dev/null | wc -l | tr -d ' ')
    local tags
    tags=$(git -C "$dir" tag 2>/dev/null | wc -l | tr -d ' ')

    echo "  Commits:       $total_commits"
    echo "  Contributors:  $contributors"
    echo "  Branches:      $branches"
    echo "  Tags:          $tags"
    echo "  First commit:  ${first_commit:-unknown}"
    echo "  Last commit:   ${last_commit:-unknown}"
    echo ""

    # File type breakdown
    echo "  File types:"
    git -C "$dir" ls-files 2>/dev/null | while IFS= read -r f; do
        echo "${f##*.}"
    done | sort | uniq -c | sort -rn | head -10 | while IFS= read -r line; do
        echo "    $line"
    done
    echo ""

    # Size
    local repo_size
    repo_size=$(du -sh "$dir/.git" 2>/dev/null | cut -f1)
    echo "  Repo size: ${repo_size:-unknown}"

    # Uncommitted changes
    local dirty
    dirty=$(git -C "$dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    if (( dirty > 0 )); then
        ui_warn "  $dirty uncommitted changes"
    else
        ui_success "  Working tree clean"
    fi
}

case "${1:-}" in
    on-startup) _project_stats_startup_line "${KMAC_PROJECT_DIR:-.}" ;;
    report|"") project_stats_report "${2:-.}" ;;
    help) echo "Usage: kmac project-stats [report] [directory]" ;;
    *) echo "Unknown command: $1"; exit 1 ;;
esac
