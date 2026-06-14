#!/usr/bin/env bash
# brief-query — terse NL verdicts + optional RUN (Docker/disk/hardware context).

set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR"
TOOLKIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=_auth-helper.sh
source "$SCRIPT_DIR/_auth-helper.sh"
# shellcheck source=_ui.sh
source "$SCRIPT_DIR/_ui.sh"

# Prefer KMAC_BRIEF_VERBOSE; legacy KMAC_COPILOT_VERBOSE still honored.
_verbose="${KMAC_BRIEF_VERBOSE:-${KMAC_COPILOT_VERBOSE:-0}}"

q="${*:-}"
if [[ -z "$q" ]] && [[ -t 0 ]]; then
    read -r -p "What do you want to check? " q || true
fi
if [[ -z "$q" ]]; then
    echo "Usage: kmac brief \"why is Docker slow\""
    exit 1
fi

_ensure_claude_auth || exit 3

uname_s=$(uname -s 2>/dev/null || echo '?')
dock=""
if docker info &>/dev/null; then dock="Docker: OK"; else dock="Docker: down or inaccessible"; fi
_disk_mount="/"
[[ -d /System/Volumes/Data ]] && _disk_mount="/System/Volumes/Data"
disk=$(df -H "$_disk_mount" 2>/dev/null | tail -1 | awk '{print $3 "/" $5 " used on data volume"}')

# Compact hardware hints — Darwin only.
_hw=""
if [[ "$uname_s" == Darwin ]]; then
    _hw=$(sysctl hw.memsize vm.swapusage vm.loadavg 2>/dev/null | awk '{ printf "%s ", $0 } END { print "" }' | sed 's/[[:space:]]*$//' || true)
    [[ -n "$_hw" ]] && _hw=$'\n'"Hardware: ${_hw}"
fi

ctx="SYSTEM: ${uname_s}
${dock}
Disk (boot vol): ${disk}
KMAC_ROOT: ${TOOLKIT_DIR}${_hw}"

if [[ "$_verbose" == "1" ]]; then
    prompt="You are KMac Brief — a local operator assistant.

CONTEXT:
${ctx}

USER:
${q}

Respond with SUMMARY (short paragraph), TRY_FIRST (numbered shell/kmac commands), SELF_HEAL (if scripts crashed: kmac heal …), MONITOR_HINT (one line or none). No markdown # headings."

    _rep_max=1024
else
    prompt="You are KMac Brief. The user wants a TINY verdict, not tutorials.

CONTEXT (facts only):
${ctx}

USER QUESTION:
${q}

RULES — break any rule and your answer fails:
• Entire reply ≤ 8 lines total, plain text only (no headings, fences, bullets, numbered lists unless exactly one RUN line as below).
• Line 1 EXACTLY one of these forms:
  STATUS: OK — <≤14 words tying to CONTEXT>
  STATUS: CHECK — <≤14 words what is uncertain or wrong>
• If STATUS: OK AND nothing in CONTEXT contradicts calm operation, STOP after line 1 (no RUN line).
• If STATUS: CHECK, add ONLY:
  RUN: <one shell line with ≤ 2 commands joined by '; ' OR the single best kmac subcommand>.
• NEVER invent kmac commands unless you know they exist here. Prefer POSIX/sysctl/ps/top/docker built-ins.
• No SELF_HEAL, TRY_FIRST, SUMMARY sections, MONITOR_HINT, preamble, apologies, or recap."

    _rep_max=320
fi

echo -e "${DIM}Checking…${NC}"
rep=$(_claude_ask "$prompt" "claude-sonnet-4-6" "$_rep_max" "Brief" 120)
[[ -z "$rep" ]] && { echo -e "${RED}No response from Claude.${NC}"; exit 4; }

echo ""
printf '%s\n' "$rep"
echo ""
