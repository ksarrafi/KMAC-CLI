#!/bin/bash
# _pilot-bot.sh — Telegram bot daemon for KMac Pilot
# Runs in background, long-polls Telegram API, dispatches commands.
# Not meant to be called directly — use `pilot start` instead.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_pilot-lib.sh
source "$SCRIPT_DIR/_pilot-lib.sh"
# shellcheck source=_vault.sh
source "$SCRIPT_DIR/_vault.sh" 2>/dev/null

# Load credentials from vault into environment
vault_export_all 2>/dev/null

# Strip placeholder API keys that override real OAuth/session auth.
[[ "${ANTHROPIC_API_KEY:-}" == "your-api-key-here" ]] && unset ANTHROPIC_API_KEY
[[ "${OPENAI_API_KEY:-}" == "your-api-key-here" ]]    && unset OPENAI_API_KEY

pilot_ensure_dirs

CHAT_ID=$(pilot_chat_id)
TOKEN=$(pilot_token)

if [[ -z "$TOKEN" ]]; then
    echo "No Telegram token configured. Run: pilot config"
    exit 1
fi

# ─── Logging ─────────────────────────────────────────────────────────────

BOT_LOG="$PILOT_DIR/bot.log"

log() { echo "[$(date '+%H:%M:%S')] $*" >> "$BOT_LOG"; }

STREAM_PID_FILE="$PILOT_DIR/stream.pid"

# Sends periodic heartbeat updates while the agent is working.
# Shows elapsed time, output size, and keeps the typing indicator alive.
start_output_stream() {
    local cid="$1" project_name="$2" agent_name="$3"
    stop_output_stream

    (
        local start_ts
        start_ts=$(date +%s)
        local last_lines=0
        local update_num=0

        while pilot_agent_running; do
            sleep 8
            pilot_agent_running || break

            ((update_num++))
            tg_typing "$cid"

            local now elapsed_s elapsed_str
            now=$(date +%s)
            elapsed_s=$(( now - start_ts ))

            if (( elapsed_s < 60 )); then
                elapsed_str="${elapsed_s}s"
            else
                elapsed_str="$(( elapsed_s / 60 ))m $(( elapsed_s % 60 ))s"
            fi

            local cur_lines=0 cur_size="0"
            if [[ -f "$PILOT_AGENT_LOG" ]]; then
                cur_lines=$(wc -l < "$PILOT_AGENT_LOG" 2>/dev/null | tr -d ' ')
                cur_size=$(wc -c < "$PILOT_AGENT_LOG" 2>/dev/null | tr -d ' ')
            fi

            # Send a status heartbeat every ~24s (every 3rd tick)
            if (( update_num % 3 == 0 )); then
                local size_str
                if (( cur_size > 1024 )); then
                    size_str="$(( cur_size / 1024 ))KB"
                else
                    size_str="${cur_size}B"
                fi

                local preview=""
                if (( cur_lines > last_lines && cur_lines > 0 )); then
                    preview=$(tail -1 "$PILOT_AGENT_LOG" 2>/dev/null | head -c 100)
                    [[ -n "$preview" ]] && preview="
\`${preview}\`"
                fi
                last_lines=$cur_lines

                tg_send "$cid" "⏳ *${agent_name}* working on *${project_name}*...
_${elapsed_str} elapsed_ · ${cur_lines} lines · ${size_str}${preview}"
            fi
        done
    ) &
    echo $! > "$STREAM_PID_FILE"
}

stop_output_stream() {
    if [[ -f "$STREAM_PID_FILE" ]]; then
        kill "$(cat "$STREAM_PID_FILE" 2>/dev/null)" 2>/dev/null
        rm -f "$STREAM_PID_FILE"
    fi
}

# ─── Command Handlers ────────────────────────────────────────────────────

cmd_start_message() {
    local cid="$1"
    tg_send "$cid" "$(cat <<'MSG'
*KMac Pilot* is online 🟢

🤖 *AI Agent*
`/task <project> <prompt>` — Start a task
`/ask <question>` — Follow-up question
`/status` — Check progress
`/stop` — Stop agent
`/agent [claude|cursor]` — Switch AI

📂 *Browse*
`/projects [filter]` — List projects
`/tree [subdir]` — Directory tree
`/cat <file>` — View a file
`/run <cmd>` — Allowed read-only cmds only (see /help)

✅ *Review*
`/log` — Agent output
`/diff` — Git changes
`/approve [msg]` — Commit
`/reject` — Revert

`/ping` — Mac alive?
MSG
)"
}

cmd_agent() {
    local cid="$1" choice="$2"
    local current
    current=$(pilot_agent)

    if [[ -z "$choice" ]]; then
        tg_send "$cid" "Active agent: *$(pilot_agent_label)* (\`$current\`)

Switch with:
\`/agent claude\` — Claude Code (claude --print)
\`/agent cursor\` — Cursor Agent (cursor agent)"
        return
    fi

    choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]' | xargs)

    case "$choice" in
        claude|cursor|kmac-agent)
            if [[ "$choice" == "$current" ]]; then
                tg_send "$cid" "Already using *$(pilot_agent_label)*."
                return
            fi
            pilot_set_config "agent" "$choice"
            tg_send "$cid" "Switched to *$(pilot_agent_label)*. Next \`/task\` will use it."
            log "Agent switched to: $choice"
            ;;
        *)
            tg_send "$cid" "Unknown agent: \`$choice\`. Use \`claude\`, \`cursor\`, or \`kmac-agent\`."
            ;;
    esac
}

cmd_ping() {
    local cid="$1"
    local uptime_str
    uptime_str=$(uptime | sed 's/.*up /up /' | sed 's/,.*//')
    local load
    load=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')
    tg_send "$cid" "Pong. Mac is *${uptime_str}*, load: ${load:-?}"
}

cmd_projects() {
    local cid="$1" filter="$2"
    local list="" count=0 cur_label=""

    while IFS='|' read -r pname _ pbranch plabel; do
        [[ -z "$pname" ]] && continue
        if [[ -n "$filter" ]] && [[ "$pname" != *"$filter"* ]]; then
            continue
        fi
        # Group by scan dir label
        if [[ "$plabel" != "$cur_label" ]]; then
            cur_label="$plabel"
            list+=$'\n'"📁 *${plabel}*"$'\n'
        fi
        if [[ "$pbranch" == "—" ]]; then
            list+="  • \`${pname}\`"$'\n'
        else
            list+="  • \`${pname}\` (${pbranch})"$'\n'
        fi
        ((count++))
    done < <(pilot_list_projects)

    if (( count == 0 )); then
        local dirs
        dirs=$(pilot_project_dirs)
        tg_send "$cid" "No projects found in \`${dirs}\`${filter:+ matching *$filter*}"
    else
        if (( ${#list} > 3600 )); then
            list="${list:0:3600}"$'\n'"_(truncated — use \`/projects <filter>\` to narrow)_"
        fi
        tg_send "$cid" "*Projects* (${count}):
${list}
Use: \`/task <project-name> <description>\`
Filter: \`/projects <keyword>\`"
    fi
}

cmd_task() {
    local cid="$1" args="$2"
    local project_name task_desc

    project_name="${args%% *}"
    if [[ "$args" == *' '* ]]; then
        task_desc="${args#* }"
    else
        task_desc=""
    fi

    if [[ -z "$project_name" || -z "$task_desc" ]]; then
        tg_send "$cid" "Usage: \`/task <project> <description>\`
Example: \`/task KMac-CLI add a health check endpoint\`"
        return
    fi

    if pilot_agent_running; then
        local cur_proj
        cur_proj=$(pilot_task_field "project")
        tg_send "$cid" "Agent is already running on *${cur_proj}*. \`/stop\` first."
        return
    fi

    local project_dir
    project_dir=$(pilot_resolve_project "$project_name")

    if [[ -z "$project_dir" || ! -d "$project_dir" ]]; then
        tg_send "$cid" "Project \`$project_name\` not found. Try \`/projects\` to see available projects."
        return
    fi

    local agent_name
    agent_name=$(pilot_agent_label)

    # Save task metadata
    jq -n \
        --arg project "$project_name" \
        --arg dir "$project_dir" \
        --arg task "$task_desc" \
        --arg agent "$(pilot_agent)" \
        --arg started "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg status "running" \
        '{project: $project, dir: $dir, task: $task, agent: $agent, started: $started, status: $status}' \
        > "$PILOT_TASK_FILE"

    tg_send "$cid" "Starting *${agent_name}* on *${project_name}*...
Task: _${task_desc}_"

    log "Starting task ($agent_name): $project_name — $task_desc"

    : > "$PILOT_AGENT_LOG"

    # Start heartbeat updates to Telegram
    start_output_stream "$cid" "$project_name" "$agent_name"

    (
        cd "$project_dir" || exit 1

        local rc=0
        case "$(pilot_agent)" in
            cursor)
                cursor agent "$task_desc" >> "$PILOT_AGENT_LOG" 2>&1
                rc=$?
                ;;
            kmac-agent)
                bash "$SCRIPT_DIR/agent" ask "$task_desc" >> "$PILOT_AGENT_LOG" 2>&1
                rc=$?
                ;;
            *)
                claude --print "$task_desc" >> "$PILOT_AGENT_LOG" 2>&1
                rc=$?
                ;;
        esac

        # Stop streaming
        stop_output_stream

        # Update task status
        if [[ -f "$PILOT_TASK_FILE" ]]; then
            local tmp
            tmp=$(jq --arg s "$(( rc == 0 ? 1 : 0 ))" \
                'if $s == "1" then .status = "completed" else .status = "failed" end' \
                "$PILOT_TASK_FILE")
            echo "$tmp" > "$PILOT_TASK_FILE"
        fi

        if (( rc == 0 )); then
            tg_send "$CHAT_ID" "*${agent_name}* completed task on *${project_name}* ✓
Use \`/log full\` for complete output, \`/diff\` to review changes."
        else
            tg_send "$CHAT_ID" "*${agent_name}* failed on *${project_name}* (exit $rc)
Use \`/log\` to see what happened."
        fi

        # Send full output as a file if it's substantial
        local total_lines
        total_lines=$(wc -l < "$PILOT_AGENT_LOG" 2>/dev/null | tr -d ' ')
        if (( total_lines > 30 )); then
            tg_send_document "$CHAT_ID" "$PILOT_AGENT_LOG" "${agent_name} output — ${project_name}" &>/dev/null
        fi

        rm -f "$PILOT_AGENT_PID"
        log "Task finished (exit $rc): $project_name"
    ) &

    echo $! > "$PILOT_AGENT_PID"
    log "Agent PID: $(cat "$PILOT_AGENT_PID")"
}

cmd_status() {
    local cid="$1"

    if ! pilot_agent_running; then
        local last_status
        last_status=$(pilot_task_field "status")
        if [[ -n "$last_status" && "$last_status" != "running" ]]; then
            local proj
            proj=$(pilot_task_field "project")
            tg_send "$cid" "No agent running. Last task on *${proj}*: ${last_status}"
        else
            tg_send "$cid" "No agent running. Send \`/task\` to start one."
        fi
        return
    fi

    local proj task started agent_used
    proj=$(pilot_task_field "project")
    task=$(pilot_task_field "task")
    started=$(pilot_task_field "started")
    agent_used=$(pilot_task_field "agent")
    local agent_label
    case "$agent_used" in
        cursor) agent_label="Cursor Agent" ;;
        *)      agent_label="Claude Code" ;;
    esac
    local lines
    lines=$(wc -l < "$PILOT_AGENT_LOG" 2>/dev/null | tr -d ' ')
    local last_line
    last_line=$(tail -1 "$PILOT_AGENT_LOG" 2>/dev/null | head -c 200)

    tg_send "$cid" "*Running* on *${proj}* via *${agent_label}*
Task: _${task}_
Started: ${started}
Output: ${lines} lines

Last line:
\`${last_line}\`"
}

cmd_log() {
    local cid="$1" mode="$2"
    local lines=30
    [[ "$mode" == "full" ]] && lines=100

    if [[ ! -s "$PILOT_AGENT_LOG" ]]; then
        tg_send "$cid" "No agent output yet."
        return
    fi

    local output
    output=$(tail -"$lines" "$PILOT_AGENT_LOG" 2>/dev/null)
    tg_send_plain "$cid" "$(printf "\`\`\`\n%s\n\`\`\`" "$output")"
}

cmd_diff() {
    local cid="$1"
    local project_dir
    project_dir=$(pilot_task_field "dir")

    if [[ -z "$project_dir" || ! -d "$project_dir" ]]; then
        tg_send "$cid" "No project directory set. Run a \`/task\` first."
        return
    fi

    local diff_output
    diff_output=$(git -C "$project_dir" diff --stat 2>/dev/null)

    if [[ -z "$diff_output" ]]; then
        # Check for untracked files
        local untracked
        untracked=$(git -C "$project_dir" ls-files --others --exclude-standard 2>/dev/null)
        if [[ -n "$untracked" ]]; then
            tg_send "$cid" "*New files:*
\`\`\`
${untracked}
\`\`\`"
        else
            tg_send "$cid" "No changes detected in *$(pilot_task_field "project")*."
        fi
        return
    fi

    local full_diff
    full_diff=$(git -C "$project_dir" diff 2>/dev/null | head -200)

    tg_send_plain "$cid" "$(printf "Changes in %s:\n\`\`\`\n%s\n\`\`\`\n\nFull diff:\n\`\`\`\n%s\n\`\`\`" \
        "$(pilot_task_field "project")" "$diff_output" "$full_diff")"
}

cmd_approve() {
    local cid="$1" message="$2"
    local project_dir
    project_dir=$(pilot_task_field "dir")

    if [[ -z "$project_dir" || ! -d "$project_dir" ]]; then
        tg_send "$cid" "No project directory set."
        return
    fi

    if pilot_agent_running; then
        tg_send "$cid" "Agent is still running. \`/stop\` first or wait for completion."
        return
    fi

    [[ -z "$message" ]] && message="$(pilot_task_field "task")"

    local has_changes
    has_changes=$(git -C "$project_dir" status --porcelain 2>/dev/null)
    if [[ -z "$has_changes" ]]; then
        tg_send "$cid" "Nothing to commit."
        return
    fi

    git -C "$project_dir" add -A 2>/dev/null
    local commit_output
    commit_output=$(git -C "$project_dir" commit -m "$message" 2>&1)
    local rc=$?

    if (( rc == 0 )); then
        local short_hash
        short_hash=$(git -C "$project_dir" log -1 --format='%h' 2>/dev/null)
        tg_send "$cid" "Committed \`${short_hash}\`: _${message}_"
        log "Approved and committed: $short_hash"
    else
        tg_send_plain "$cid" "$(printf "Commit failed:\n\`\`\`\n%s\n\`\`\`" "$commit_output")"
    fi
}

cmd_reject() {
    local cid="$1"
    local project_dir
    project_dir=$(pilot_task_field "dir")

    if [[ -z "$project_dir" || ! -d "$project_dir" ]]; then
        tg_send "$cid" "No project directory set."
        return
    fi

    if pilot_agent_running; then
        tg_send "$cid" "Agent is still running. \`/stop\` first."
        return
    fi

    git -C "$project_dir" checkout -- . 2>/dev/null
    git -C "$project_dir" clean -fd 2>/dev/null
    tg_send "$cid" "Changes reverted in *$(pilot_task_field "project")*."
    log "Rejected changes"
}

cmd_ask() {
    local cid="$1" question="$2"

    if [[ -z "$question" ]]; then
        tg_send "$cid" "Usage: \`/ask <question about the project>\`
Example: \`/ask what framework is this using?\`"
        return
    fi

    if pilot_agent_running; then
        tg_send "$cid" "Agent is busy. Wait for it to finish or \`/stop\` first."
        return
    fi

    local project_dir
    project_dir=$(pilot_task_field "dir")
    if [[ -z "$project_dir" || ! -d "$project_dir" ]]; then
        tg_send "$cid" "No active project. Run \`/task\` first."
        return
    fi

    local project_name
    project_name=$(pilot_task_field "project")
    local agent_name
    agent_name=$(pilot_agent_label)

    tg_send "$cid" "Asking *${agent_name}* about *${project_name}*...
_${question}_"

    # Build context from previous output if available
    local context=""
    if [[ -s "$PILOT_AGENT_LOG" ]]; then
        context="Previous analysis context (last 50 lines):
$(tail -50 "$PILOT_AGENT_LOG")

---
Follow-up question: "
    fi

    : > "$PILOT_AGENT_LOG"

    (
        cd "$project_dir" || exit 1
        local prompt="${context}${question}"
        local rc=0

        case "$(pilot_agent)" in
            cursor)
                cursor agent "$prompt" >> "$PILOT_AGENT_LOG" 2>&1
                rc=$?
                ;;
            kmac-agent)
                bash "$SCRIPT_DIR/agent" ask "$prompt" >> "$PILOT_AGENT_LOG" 2>&1
                rc=$?
                ;;
            *)
                claude --print "$prompt" >> "$PILOT_AGENT_LOG" 2>&1
                rc=$?
                ;;
        esac

        if (( rc == 0 )); then
            local output
            output=$(cat "$PILOT_AGENT_LOG")
            if (( ${#output} > 3800 )); then
                tg_send_plain "$CHAT_ID" "$(printf "\`\`\`\n%s\n\`\`\`" "${output:0:3800}")"
                tg_send_document "$CHAT_ID" "$PILOT_AGENT_LOG" "Full answer — ${project_name}" &>/dev/null
            else
                tg_send_plain "$CHAT_ID" "$(printf "\`\`\`\n%s\n\`\`\`" "$output")"
            fi
        else
            tg_send "$CHAT_ID" "*${agent_name}* failed (exit $rc). Check \`/log\`."
        fi
        log "Ask finished (exit $rc): $question"
    ) &

    echo $! > "$PILOT_AGENT_PID"
}

cmd_cat() {
    local cid="$1" filepath="$2"

    if [[ -z "$filepath" ]]; then
        tg_send "$cid" "Usage: \`/cat <filepath>\`
Example: \`/cat src/app/page.tsx\`
\`/cat package.json\`"
        return
    fi

    local project_dir
    project_dir=$(pilot_task_field "dir")
    if [[ -z "$project_dir" || ! -d "$project_dir" ]]; then
        tg_send "$cid" "No active project. Run \`/task\` first."
        return
    fi

    local full_path="$project_dir/$filepath"
    local project_real
    project_real="$(realpath "$project_dir" 2>/dev/null)" || { tg_send "$cid" "Invalid path"; return; }
    full_path="$(realpath "$full_path" 2>/dev/null)" || { tg_send "$cid" "Invalid path"; return; }
    if [[ "$full_path" != "$project_real" && "$full_path" != "$project_real"/* ]]; then
        tg_send "$cid" "Access denied: path outside project"
        return
    fi

    if [[ ! -f "$full_path" ]]; then
        tg_send "$cid" "File not found: \`$filepath\`"
        return
    fi

    local size
    size=$(wc -c < "$full_path" | tr -d ' ')

    if (( size > 50000 )); then
        tg_send_document "$cid" "$full_path" "$filepath ($(( size / 1024 ))KB)"
    elif (( size > 3500 )); then
        tg_send_document "$cid" "$full_path" "$filepath"
    else
        local content
        content=$(cat "$full_path")
        local ext="${filepath##*.}"
        tg_send_plain "$cid" "$(printf "📄 %s:\n\`\`\`%s\n%s\n\`\`\`" "$filepath" "$ext" "$content")"
    fi
}

cmd_tree() {
    local cid="$1" subdir="$2"

    local project_dir
    project_dir=$(pilot_task_field "dir")
    if [[ -z "$project_dir" || ! -d "$project_dir" ]]; then
        tg_send "$cid" "No active project. Run \`/task\` first."
        return
    fi

    local target="$project_dir"
    [[ -n "$subdir" ]] && target="$project_dir/$subdir"

    local project_real
    project_real="$(realpath "$project_dir" 2>/dev/null)" || { tg_send "$cid" "Invalid path"; return; }
    target="$(realpath "$target" 2>/dev/null)" || { tg_send "$cid" "Invalid path"; return; }
    if [[ "$target" != "$project_real" && "$target" != "$project_real"/* ]]; then
        tg_send "$cid" "Access denied: path outside project"
        return
    fi

    if [[ ! -d "$target" ]]; then
        tg_send "$cid" "Directory not found: \`$subdir\`"
        return
    fi

    local project_name
    project_name=$(pilot_task_field "project")

    local tree_output
    if command -v tree &>/dev/null; then
        tree_output=$(tree -L 2 --dirsfirst -I 'node_modules|.git|.next|__pycache__|.venv|dist|build' "$target" 2>/dev/null)
    else
        tree_output=$(find "$target" -maxdepth 2 \
            ! -path '*/node_modules/*' ! -path '*/.git/*' ! -path '*/.next/*' \
            ! -path '*/__pycache__/*' ! -path '*/dist/*' ! -path '*/build/*' \
            -print 2>/dev/null | sed "s|$project_dir/||" | sort | head -80)
    fi

    if (( ${#tree_output} > 3800 )); then
        tree_output="${tree_output:0:3800}
...(truncated)"
    fi

    tg_send_plain "$cid" "$(printf "📁 %s%s:\n\`\`\`\n%s\n\`\`\`" "$project_name" "${subdir:+/$subdir}" "$tree_output")"
}

# Strict allowlist for /run — first word (and git/docker/brew subcommand) must match.
pilot_run_allowed() {
    local line="$1"
    read -r -a words <<< "$line"
    ((${#words[@]} == 0)) && return 1
    local w0="${words[0]}"
    local w1="${words[1]:-}"
    local w2="${words[2]:-}"

    case "$w0" in
        ls|cat|head|tail|wc|pwd|whoami|date|uptime|df|du)
            return 0
            ;;
        git)
            case "$w1" in
                status|log|diff|branch) return 0 ;;
                *) return 1 ;;
            esac
            ;;
        docker)
            case "$w1" in
                ps|images|logs) return 0 ;;
                *) return 1 ;;
            esac
            ;;
        brew)
            [[ "$w1" == "list" ]] && return 0
            [[ "$w1" == "services" && "$w2" == "list" ]] && return 0
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

pilot_run_allowed_list_msg() {
    cat <<'MSG'
*Allowed /run commands*

*Single commands:* `ls`, `cat`, `head`, `tail`, `wc`, `pwd`, `whoami`, `date`, `uptime`, `df`, `du`

*Git:* `git status`, `git log`, `git diff`, `git branch`

*Docker:* `docker ps`, `docker images`, `docker logs`

*Brew:* `brew list`, `brew services list`

Anything else is rejected. Set chat via `kmac pilot config`.
MSG
}

cmd_run() {
    local cid="$1" shell_cmd="$2"

    if [[ -z "$shell_cmd" ]]; then
        tg_send_plain "$cid" "$(pilot_run_allowed_list_msg)
Usage: \`/run <command>\`
Examples: \`/run ls -la src/\`, \`/run git log --oneline -5\`, \`/run docker ps\`"
        return
    fi

    local project_dir
    project_dir=$(pilot_task_field "dir")
    if [[ -z "$project_dir" || ! -d "$project_dir" ]]; then
        tg_send "$cid" "No active project. Run \`/task\` first."
        return
    fi

    if ! pilot_run_allowed "$shell_cmd"; then
        tg_send_plain "$cid" "Command not allowed.

$(pilot_run_allowed_list_msg)"
        return
    fi

    local project_name
    project_name=$(pilot_task_field "project")

    tg_send "$cid" "Running on *${project_name}*:
\`$shell_cmd\`"

    if [[ "$shell_cmd" == *';'* || "$shell_cmd" == *'|'* || "$shell_cmd" == *'&'* || "$shell_cmd" == *'$'* \
        || "$shell_cmd" == *'`'* || "$shell_cmd" == *'('* || "$shell_cmd" == *')'* || "$shell_cmd" == *'{'* \
        || "$shell_cmd" == *'}'* || "$shell_cmd" == *'!'* || "$shell_cmd" == *'<'* || "$shell_cmd" == *'>'* \
        || "$shell_cmd" == *\\* || "$shell_cmd" == *"'"* ]]; then
        tg_send "$cid" "Shell metacharacters not allowed in commands."
        return
    fi
    local -a _run_argv
    read -ra _run_argv <<< "$shell_cmd"
    local output
    output=$(cd "$project_dir" && timeout 30 "${_run_argv[@]}" 2>&1)
    local rc=$?

    if [[ -z "$output" ]]; then
        output="(no output)"
    fi

    if (( ${#output} > 3800 )); then
        local tmpfile="$PILOT_DIR/run_output.txt"
        echo "$output" > "$tmpfile"
        tg_send "$cid" "Exit: $rc (output too long, sending as file)"
        tg_send_document "$cid" "$tmpfile" "Output of: $shell_cmd"
    else
        tg_send_plain "$cid" "$(printf "Exit: %d\n\`\`\`\n%s\n\`\`\`" "$rc" "$output")"
    fi
    log "Run command (exit $rc): $shell_cmd"
}

cmd_stop() {
    local cid="$1"

    if ! pilot_agent_running; then
        tg_send "$cid" "No agent running."
        return
    fi

    stop_output_stream

    local pid
    pid=$(cat "$PILOT_AGENT_PID" 2>/dev/null)
    kill "$pid" 2>/dev/null
    rm -f "$PILOT_AGENT_PID"

    if [[ -f "$PILOT_TASK_FILE" ]]; then
        local tmp
        tmp=$(jq '.status = "stopped"' "$PILOT_TASK_FILE")
        echo "$tmp" > "$PILOT_TASK_FILE"
    fi

    tg_send "$cid" "Agent stopped."
    log "Agent stopped by user"
}

# ─── Message Dispatcher ──────────────────────────────────────────────────

handle_message() {
    local msg="$1"
    local cid text from_id

    cid=$(echo "$msg" | jq -r '.message.chat.id // empty')
    text=$(echo "$msg" | jq -r '.message.text // empty')
    from_id=$(echo "$msg" | jq -r '.message.from.id // empty')

    [[ -z "$cid" || -z "$text" ]] && return

    # Require explicit chat_id — never auto-bind from first sender
    if [[ -z "$CHAT_ID" ]]; then
        tg_send "$cid" "Bot not configured. Run \`kmac pilot config\` to set up."
        return
    fi

    # Security: only respond to authorized chat
    if [[ "$cid" != "$CHAT_ID" ]]; then
        log "Unauthorized message from chat $cid (expected $CHAT_ID)"
        tg_send "$cid" "Unauthorized. Your chat ID is: \`$cid\`
Set it with: \`kmac pilot config\` (or \`pilot config chat_id $cid\`)"
        return
    fi

    local cmd args
    cmd=$(echo "$text" | awk '{print $1}')
    args=$(echo "$text" | sed 's/^\/[^ ]* *//')
    [[ "$args" == "$cmd" ]] && args=""

    log "Received: $text (from $from_id)"

    # Show "typing..." immediately so user knows we got the message
    tg_typing "$cid"

    case "$cmd" in
        /start|/help)    cmd_start_message "$cid" ;;
        /ping)           cmd_ping "$cid" ;;
        /agent)          cmd_agent "$cid" "$args" ;;
        /projects)       cmd_projects "$cid" "$args" ;;
        /task)           cmd_task "$cid" "$args" ;;
        /ask)            cmd_ask "$cid" "$args" ;;
        /status)         cmd_status "$cid" ;;
        /log)            cmd_log "$cid" "$args" ;;
        /diff)           cmd_diff "$cid" ;;
        /approve)        cmd_approve "$cid" "$args" ;;
        /reject)         cmd_reject "$cid" ;;
        /stop)           cmd_stop "$cid" ;;
        /cat)            cmd_cat "$cid" "$args" ;;
        /tree)           cmd_tree "$cid" "$args" ;;
        /run)            cmd_run "$cid" "$args" ;;
        *)
            tg_send "$cid" "Unknown command: \`$cmd\`. Try \`/help\`"
            ;;
    esac
}

# ─── Main Loop (Long Polling) ────────────────────────────────────────────

log "Bot daemon starting"

# Recover offset from last run
OFFSET=0
[[ -f "$PILOT_OFFSET_FILE" ]] && OFFSET=$(cat "$PILOT_OFFSET_FILE")

# Notify on start
if [[ -n "$CHAT_ID" ]]; then
    tg_send "$CHAT_ID" "KMac Pilot is *online*. Type \`/help\` for commands."
fi

while true; do
    response=$(tg_call "getUpdates" \
        -d "offset=$OFFSET" \
        -d "timeout=60" \
        -d "allowed_updates=[\"message\"]" 2>/dev/null)

    if [[ -z "$response" ]]; then
        log "No response from Telegram (network issue?), retrying in 5s"
        sleep 5
        continue
    fi

    ok=$(echo "$response" | jq -r '.ok // false')
    if [[ "$ok" != "true" ]]; then
        log "Telegram API error: $response"
        sleep 10
        continue
    fi

    count=$(echo "$response" | jq '.result | length')

    for (( i=0; i<count; i++ )); do
        update=$(echo "$response" | jq ".result[$i]")
        update_id=$(echo "$update" | jq '.update_id')
        OFFSET=$(( update_id + 1 ))
        echo "$OFFSET" > "$PILOT_OFFSET_FILE"
        handle_message "$update"
    done
done
