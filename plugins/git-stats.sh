#!/bin/bash
# TOOLKIT_NAME: Git Stats
# TOOLKIT_DESC: Quick git activity (post-commit & startup hooks)
# TOOLKIT_KEY: 3
# TOOLKIT_HOOKS: post-commit,on-startup

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"
# shellcheck source=../scripts/_ui.sh
source "$SCRIPT_DIR/_ui.sh" 2>/dev/null

_git_commits_today() {
    git log --since=midnight --oneline 2>/dev/null | wc -l | tr -d ' '
}

_git_commits_on_day_offset() {
    local i="$1" d
    d=$(date -v-"${i}"d +%Y-%m-%d 2>/dev/null) || { echo 0; return; }
    git log --after="$d 00:00:00" --before="$d 23:59:59" --oneline 2>/dev/null | wc -l | tr -d ' '
}

_git_streak_days() {
    local s=0 i c
    for ((i = 0; i < 400; i++)); do
        c=$(_git_commits_on_day_offset "$i")
        ((c > 0)) || break
        ((s++))
    done
    echo "$s"
}

_git_hot_file_today() {
    local line
    line=$(git log --since=midnight --name-only --pretty=format: 2>/dev/null \
        | sed '/^$/d' | sort | uniq -c | sort -rn | head -1)
    if [[ -z "$line" ]]; then
        echo "n/a"
    else
        echo "$line" | awk '{ print $2 " (" $1 " touches)" }'
    fi
}

_git_summary_line() {
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        echo "not a git repo"
        return
    fi
    local today streak hot
    today=$(_git_commits_today)
    streak=$(_git_streak_days)
    hot=$(_git_hot_file_today)
    [[ -z "$hot" ]] && hot="n/a"
    echo "today ${today} commit(s) · streak ${streak} day(s) · busiest file: ${hot}"
}

_run_on_startup() {
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        return 0
    fi
    local branch dirty
    branch=$(git branch --show-current 2>/dev/null || echo "?")
    dirty=""
    [[ -n "$(git status --porcelain 2>/dev/null)" ]] && dirty=" · dirty"
    echo -e "  ${DIM}Git:${NC} ${branch}${dirty}"
}

_run_post_commit() {
    echo -e "  ${DIM}$(_git_summary_line)${NC}"
}

case "${1:-}" in
    post-commit)
        _run_post_commit
        ;;
    on-startup)
        _run_on_startup
        ;;
    *)
        title_box "Git Stats" "📊"
        if ! git rev-parse --is-inside-work-tree &>/dev/null; then
            echo -e "  ${YELLOW}⚠${NC}  Not inside a git repository."
        else
            echo -e "  $(_git_summary_line)"
            echo ""
            _run_on_startup
        fi
        ;;
esac
