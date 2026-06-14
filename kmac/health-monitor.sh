#!/bin/bash

###############################################################################
# KMac Health Monitor - Collects machine, Docker, Git, Email, and app health
# Usage: ./health-monitor.sh [--json] [--threshold] [--verbose]
###############################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
JSON_OUTPUT=false
VERBOSE=false
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Health thresholds
CPU_THRESHOLD=80
MEMORY_THRESHOLD=85
DISK_THRESHOLD=90
DOCKER_UNHEALTHY_THRESHOLD=0  # Alert if any container is unhealthy

# ============================================================================
# SYSTEM HEALTH
# ============================================================================

check_cpu_usage() {
  # macOS CPU usage
  if [[ "$OSTYPE" == "darwin"* ]]; then
    local cpu=$(ps aux | awk 'BEGIN {sum=0} {sum+=$3} END {print int(sum)}')
    echo "$cpu"
  else
    # Linux fallback
    local cpu=$(top -bn1 | grep "Cpu(s)" | awk '{print int($2)}')
    echo "$cpu"
  fi
}

check_memory_usage() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS memory
    local memory=$(vm_stat | grep "Pages active" | awk '{print $3}' | sed 's/\.$//')
    local total=$(sysctl hw.memsize | awk '{print $2}')
    echo "scale=2; ($memory * 4096 * 100) / $total" | bc
  else
    # Linux fallback
    local memory=$(free | grep Mem | awk '{printf("%.0f", $3/$2 * 100)}')
    echo "$memory"
  fi
}

check_disk_usage() {
  local mount="/"
  [[ -d /System/Volumes/Data ]] && mount="/System/Volumes/Data"
  local disk
  disk=$(df -h "$mount" | tail -1 | awk '{print $5}' | sed 's/%//')
  echo "$disk"
}

check_system_temp() {
  if command -v istats &> /dev/null; then
    istats cpu temp | grep "CPU" | awk '{print $NF}' | sed 's/°.*//'
  else
    echo "N/A (istats not installed)"
  fi
}

# ============================================================================
# DOCKER HEALTH
# ============================================================================

check_docker_health() {
  if ! command -v docker &> /dev/null; then
    echo '{"status": "not_installed", "containers": []}'
    return
  fi

  if ! docker ps &> /dev/null 2>&1; then
    echo '{"status": "not_running", "containers": []}'
    return
  fi

  local containers=$(docker ps -a --format "{{.Names}}|{{.Status}}" 2>/dev/null || echo "")
  
  if [[ -z "$containers" ]]; then
    echo '{"status": "running", "container_count": 0, "containers": []}'
    return
  fi

  local container_count=$(echo "$containers" | wc -l)
  local unhealthy=0
  local container_json="["

  while IFS='|' read -r name status; do
    [[ -z "$name" ]] && continue
    
    local state="running"
    if [[ "$status" == *"Exited"* ]]; then
      state="stopped"
      ((unhealthy++))
    elif [[ "$status" == *"unhealthy"* ]]; then
      state="unhealthy"
      ((unhealthy++))
    fi
    
    local resource=$(docker stats "$name" --no-stream --format "{{.CPUPerc}}|{{.MemUsage}}" 2>/dev/null || echo "0%|0MB")
    IFS='|' read -r cpu mem <<< "$resource"
    
    container_json="${container_json}{\"name\":\"$name\",\"state\":\"$state\",\"cpu\":\"$cpu\",\"memory\":\"$mem\"},"
  done <<< "$containers"

  container_json="${container_json%,}]"
  echo "{\"status\": \"running\", \"container_count\": $container_count, \"unhealthy\": $unhealthy, \"containers\": $container_json}"
}

# ============================================================================
# GIT HEALTH
# ============================================================================

check_git_health() {
  local git_repos=$(find ~ -maxdepth 4 -type d -name ".git" 2>/dev/null | head -20)
  local repo_json="["
  local unpushed_count=0

  if [[ -z "$git_repos" ]]; then
    echo '{"status": "no_repos_found", "repositories": []}'
    return
  fi

  while IFS= read -r repo_path; do
    local repo_dir=$(dirname "$repo_path")
    local repo_name=$(basename "$repo_dir")
    
    cd "$repo_dir" || continue
    
    # Check for unpushed commits
    local unpushed=$(git rev-list --left-only --count origin/main...HEAD 2>/dev/null || git rev-list --left-only --count origin/master...HEAD 2>/dev/null || echo "0")
    local branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    local status=$(git status --porcelain 2>/dev/null | wc -l)
    
    if [[ "$unpushed" -gt 0 ]]; then
      ((unpushed_count++))
    fi
    
    repo_json="${repo_json}{\"name\":\"$repo_name\",\"path\":\"$repo_dir\",\"branch\":\"$branch\",\"unpushed\":$unpushed,\"uncommitted\":$status},"
  done <<< "$git_repos"

  repo_json="${repo_json%,}]"
  echo "{\"status\": \"ok\", \"total_repos\": $(echo \"$git_repos\" | wc -l), \"repos_with_unpushed\": $unpushed_count, \"repositories\": $repo_json}"
}

# ============================================================================
# EMAIL/CALENDAR HEALTH
# ============================================================================

check_email_calendar() {
  # Check for Mail.app or other mail clients
  if command -v notmuch &> /dev/null; then
    local unread=$(notmuch search tag:unread 2>/dev/null | wc -l || echo "0")
  else
    local unread="unknown"
  fi

  # Calendar data would typically come from Calendar.app API or command
  # For now, we'll return a placeholder
  echo "{\"unread_emails\": \"$unread\", \"calendar_status\": \"check_manually\"}"
}

# ============================================================================
# NETWORK/SSL HEALTH
# ============================================================================

check_network_health() {
  local vpn_status="unknown"
  
  # Check for common VPN tools
  if pgrep -f "openvpn" &> /dev/null; then
    vpn_status="connected"
  elif pgrep -f "wireguard" &> /dev/null; then
    vpn_status="connected"
  elif defaults read ~/Library/Preferences/com.apple.networkx.vpn.plist 2>/dev/null | grep -q "isConnected = 1"; then
    vpn_status="connected"
  else
    vpn_status="not_connected"
  fi

  echo "{\"vpn_status\": \"$vpn_status\", \"internet_reachable\": $(ping -c 1 8.8.8.8 &>/dev/null && echo 'true' || echo 'false')}"
}

# ============================================================================
# CUSTOM APPLICATIONS
# ============================================================================

check_custom_apps() {
  # Placeholder for custom app checks
  # User can define checks in a separate config file
  echo '{"custom_apps": []}'
}

# ============================================================================
# MAIN OUTPUT
# ============================================================================

output_json() {
  local system_cpu=$(check_cpu_usage)
  local system_memory=$(check_memory_usage)
  local system_disk=$(check_disk_usage)
  local system_temp=$(check_system_temp)
  local docker_health=$(check_docker_health)
  local git_health=$(check_git_health)
  local email_calendar=$(check_email_calendar)
  local network=$(check_network_health)
  local custom_apps=$(check_custom_apps)

  cat <<EOF
{
  "timestamp": "$TIMESTAMP",
  "system": {
    "cpu_percent": $system_cpu,
    "memory_percent": $(printf "%.0f" $system_memory),
    "disk_percent": $system_disk,
    "temperature_c": "$system_temp"
  },
  "docker": $docker_health,
  "git": $git_health,
  "email_calendar": $email_calendar,
  "network": $network,
  "custom_apps": $custom_apps,
  "thresholds": {
    "cpu": $CPU_THRESHOLD,
    "memory": $MEMORY_THRESHOLD,
    "disk": $DISK_THRESHOLD
  }
}
EOF
}

output_human() {
  echo ""
  echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
  echo -e "${BLUE}  KMac Health Report - $TIMESTAMP${NC}"
  echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
  
  # System
  local cpu=$(check_cpu_usage)
  local memory=$(printf "%.0f" $(check_memory_usage))
  local disk=$(check_disk_usage)
  
  echo -e "\n${BLUE}System Resources:${NC}"
  [[ $cpu -gt $CPU_THRESHOLD ]] && echo -e "  CPU:     ${RED}$cpu%${NC}" || echo -e "  CPU:     ${GREEN}$cpu%${NC}"
  [[ $memory -gt $MEMORY_THRESHOLD ]] && echo -e "  Memory:  ${RED}$memory%${NC}" || echo -e "  Memory:  ${GREEN}$memory%${NC}"
  [[ $disk -gt $DISK_THRESHOLD ]] && echo -e "  Disk:    ${RED}$disk%${NC}" || echo -e "  Disk:    ${GREEN}$disk%${NC}"
  echo -e "  Temp:    $(check_system_temp)°C"
  
  # Docker
  echo -e "\n${BLUE}Docker:${NC}"
  check_docker_health | jq '.container_count, .unhealthy' | {
    read count; read unhealthy
    echo "  Containers: $count"
    [[ $unhealthy -gt 0 ]] && echo -e "  Unhealthy:  ${RED}$unhealthy${NC}" || echo -e "  Unhealthy:  ${GREEN}0${NC}"
  }
  
  # Git
  echo -e "\n${BLUE}Git Repositories:${NC}"
  check_git_health | jq '.total_repos, .repos_with_unpushed' | {
    read total; read unpushed
    echo "  Total: $total"
    [[ $unpushed -gt 0 ]] && echo -e "  With unpushed commits: ${YELLOW}$unpushed${NC}" || echo -e "  With unpushed commits: ${GREEN}0${NC}"
  }
  
  # Email
  echo -e "\n${BLUE}Email/Calendar:${NC}"
  check_email_calendar | jq '.unread_emails' | {
    read unread
    echo "  Unread emails: $unread"
  }
  
  # Network
  echo -e "\n${BLUE}Network:${NC}"
  check_network_health | jq '.vpn_status, .internet_reachable' | {
    read vpn; read internet
    echo "  VPN: $vpn"
    echo "  Internet: $internet"
  }
  
  echo -e "\n${BLUE}═══════════════════════════════════════════════════════${NC}\n"
}

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

while [[ $# -gt 0 ]]; do
  case $1 in
    --json)
      JSON_OUTPUT=true
      shift
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--json] [--verbose]"
      exit 1
      ;;
  esac
done

# ============================================================================
# MAIN
# ============================================================================

if [[ "$JSON_OUTPUT" == true ]]; then
  output_json
else
  output_human
fi
