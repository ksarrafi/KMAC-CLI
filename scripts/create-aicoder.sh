#!/bin/bash

# Create Global AICoder Command
# Creates a global 'aicoder' command similar to your 'claudeme'

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

ICON_SUCCESS="✅"
ICON_WARNING="⚠️"
ICON_INFO="ℹ️"
ICON_ROCKET="🚀"

echo -e "${BOLD}${CYAN}Creating Global AICoder Command${NC}"
echo ""

# Find the AICoder framework directory
AICODER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AICODER_SCRIPT="$AICODER_DIR/aicoder_package/scripts/ultra-clean-one-liner.sh"

if [[ ! -f "$AICODER_SCRIPT" ]]; then
    echo -e "${RED}${ICON_WARNING} Could not find AICoder installer script${NC}"
    echo "Expected location: $AICODER_SCRIPT"
    exit 1
fi

echo -e "${GREEN}${ICON_SUCCESS} Found AICoder framework: $AICODER_DIR${NC}"

# Create the global aicoder command
create_global_aicoder() {
    echo -e "${CYAN}${ICON_INFO} Creating aicoder command in ~/bin...${NC}"

    mkdir -p "$HOME/bin"
    if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
        # shellcheck disable=SC2016
        echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.zshrc" 2>/dev/null || true
        # shellcheck disable=SC2016
        echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc" 2>/dev/null || true
        echo -e "${GREEN}${ICON_SUCCESS} Added ~/bin to PATH${NC}"
    fi

    cat > "$HOME/bin/aicoder" << 'EOF'
#!/usr/bin/env bash
# aicoder — AICoder Enterprise Framework launcher
# Similar to claudeme but for AICoder with subagent support

set -euo pipefail

AICODER_DIR="${AICODER_DIR:-$HOME/Projects/AICoders-library}"
AICODER_SCRIPT="$AICODER_DIR/aicoder_package/scripts/ultra-clean-one-liner.sh"
AICODER_LAUNCHER="$AICODER_DIR/aicoder_package/scripts/aicoder-launcher.sh"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

ICON_SUCCESS="✅"
ICON_WARNING="⚠️"
ICON_INFO="ℹ️"
ICON_ROCKET="🚀"

# Available subagents
SUBAGENTS=(
    "architect:High-level system design and architecture"
    "developer:Code implementation and development"
    "typescript-pro:Advanced TypeScript development"
    "python-pro:Python development and frameworks"
    "rust-pro:Rust systems programming"
    "golang-pro:Go development and microservices"
    "java-pro:Java and Spring Boot development"
    "debugger:Systematic bug investigation"
    "quality-reviewer:Production-critical issue identification"
    "test-automator:Test strategy and automation"
    "security-auditor:Security vulnerability scanning"
    "performance-optimizer:Application performance optimization"
    "devops-engineer:DevOps and deployment automation"
    "docker-deployment:Containerization and Docker"
    "terraform-pro:Infrastructure as Code"
    "aws-pro:Amazon Web Services specialist"
    "azure-pro:Microsoft Azure specialist"
    "gcp-pro:Google Cloud Platform specialist"
    "kubernetes-pro:Kubernetes orchestration"
    "data-engineer:Data engineering and pipelines"
    "ai-engineer:AI/ML model development"
    "technical-writer:Technical documentation"
    "api-documenter:API documentation and specs"
    "file-manager:File organization and cleanup"
    "ai-orchestrator:Intelligent agent coordination"
)

logdbg() { [[ "${AICODER_DEBUG:-0}" = "1" ]] && echo "[aicoder] $*" >&2 || true; }
command_exists() { command -v "$1" >/dev/null 2>&1; }

usage() {
    cat <<USAGE_EOF
Usage: $(basename "$0") [command] [options]

Commands:
  install                 Install AICoder in current directory
  init                    Initialize project with AI agent context
  start                   Start development session
  start --agent <name>    Start with specific subagent
  agents                  List available subagents
  agent-help <name>       Show help for specific agent
  context                 Show available context files
  subagents               Show subagent usage guide
  help                    Show this help
  version                 Show version

Examples:
  aicoder install                    # Install AICoder in current directory
  aicoder start                      # Start development session
  aicoder start --agent architect    # Start with architect subagent
  aicoder start --agent developer "Build user authentication"
  aicoder agents                     # List all subagents
  aicoder agent-help architect       # Get help for specific agent

USAGE_EOF
}

pick_subagent_menu() {
    echo "Pick a subagent:" >&2
    local i=1
    while (( i <= ${#SUBAGENTS[@]} )); do
        IFS=':' read -r name description <<< "${SUBAGENTS[$((i-1))]}"
        printf "  %d) %-18s %s\n" "$i" "$name" "$description" >&2
        ((i++))
    done
    echo "" >&2
    read -r -p "Enter choice (1-${#SUBAGENTS[@]}): " choice
    case "$choice" in
        ''|*[!0-9]*) echo "Invalid choice" >&2; echo "" ;;
        *)
            local idx=$((choice - 1))
            if (( choice >= 1 && choice <= ${#SUBAGENTS[@]} )); then
                IFS=':' read -r name description <<< "${SUBAGENTS[$idx]}"
                echo "$name"
            fi
            ;;
    esac
}

pick_subagent_interactive() {
    # Prefer fzf if available and writing to a TTY
    if command_exists fzf && [[ -t 0 && -t 1 && -t 2 ]]; then
        logdbg "Using fzf picker"
        local picked
        picked="$(
            {
                local i
                for ((i=0; i<${#SUBAGENTS[@]}; i++)); do
                    IFS=':' read -r name description <<< "${SUBAGENTS[$i]}"
                    printf "%s\t%s\n" "$name" "$description"
                done
            } | fzf --prompt="Pick AICoder subagent > " \
                   --header="Subagent\tDescription" \
                   --with-nth=1,2 \
                   --height=15 --layout=reverse --border \
            || true
        )"
        picked="$(printf "%s" "$picked" | awk -F'\t' 'NR==1{print $1}')"
        if [[ -n "$picked" ]]; then
            echo "$picked"
            return 0
        fi
        logdbg "fzf returned empty selection; falling back to numbered menu"
    else
        logdbg "fzf not available or stdout not a TTY; using numbered menu"
    fi
    pick_subagent_menu
}

# Check if AICoder is installed in current directory
is_aicoder_installed() {
    [[ -f "./aicoder" && -d ".aicoder" ]]
}

# Install AICoder if not present
ensure_aicoder_installed() {
    if ! is_aicoder_installed; then
        echo -e "${YELLOW}${ICON_WARNING} AICoder not found in current directory${NC}"
        echo -e "${CYAN}${ICON_INFO} Installing AICoder...${NC}"
        
        if [[ ! -f "$AICODER_SCRIPT" ]]; then
            echo -e "${RED}${ICON_WARNING} AICoder installer not found at: $AICODER_SCRIPT${NC}"
            exit 1
        fi
        
        bash "$AICODER_SCRIPT"
        
        if is_aicoder_installed; then
            echo -e "${GREEN}${ICON_SUCCESS} AICoder installed successfully!${NC}"
        else
            echo -e "${RED}${ICON_WARNING} AICoder installation failed${NC}"
            exit 1
        fi
    fi
}

# Exec project aicoder via absolute path (never trust ./aicoder in CWD)
run_aicoder() {
    local AICODER_DIR
    AICODER_DIR="$(pwd -P)"
    exec "${AICODER_DIR}/aicoder" "$@"
}

# Main command handling
case "${1:-help}" in
    "install")
        if [[ ! -f "$AICODER_SCRIPT" ]]; then
            echo -e "${RED}${ICON_WARNING} AICoder installer not found at: $AICODER_SCRIPT${NC}"
            exit 1
        fi
        bash "$AICODER_SCRIPT"
        ;;
    "init"|"start"|"agents"|"agent-help"|"context"|"subagents"|"clean"|"help"|"version")
        ensure_aicoder_installed
        run_aicoder "$@"
        ;;
    "interactive"|"i")
        ensure_aicoder_installed
        echo -e "${BOLD}${CYAN}AICoder Interactive Mode${NC}"
        echo ""
        echo "1. Install AICoder"
        echo "2. Start development session"
        echo "3. Start with specific subagent"
        echo "4. List subagents"
        echo "5. Show help"
        echo ""
        read -r -p "Enter choice (1-5): " choice
        case "$choice" in
            1) run_aicoder init ;;
            2) run_aicoder start ;;
            3)
                subagent="$(pick_subagent_interactive || true)"
                if [[ -n "$subagent" ]]; then
                    run_aicoder start --agent "$subagent"
                else
                    run_aicoder start
                fi
                ;;
            4) run_aicoder agents ;;
            5) run_aicoder help ;;
            *) echo "Invalid choice" && exit 1 ;;
        esac
        ;;
    *)
        if [[ -z "${1:-}" ]]; then
            # No arguments - show interactive mode
            ensure_aicoder_installed
            echo -e "${BOLD}${CYAN}AICoder Enterprise Framework${NC}"
            echo ""
            echo "Quick start:"
            echo "  aicoder install    # Install AICoder in current directory"
            echo "  aicoder start      # Start development session"
            echo "  aicoder agents     # List all subagents"
            echo ""
            echo "For interactive mode: aicoder interactive"
            echo "For help: aicoder help"
        else
            echo -e "${RED}Unknown command: $1${NC}"
            usage
            exit 1
        fi
        ;;
esac
EOF

    chmod +x "$HOME/bin/aicoder"
    echo -e "${GREEN}${ICON_SUCCESS} aicoder command created: $HOME/bin/aicoder${NC}"
}

# Create local bin alternative
create_local_aicoder() {
    echo -e "${CYAN}${ICON_INFO} Creating local aicoder command...${NC}"
    
    # Create ~/bin directory if it doesn't exist
    mkdir -p "$HOME/bin"
    
    # Add to PATH if not already there
    if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
        # shellcheck disable=SC2016
        echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.zshrc" 2>/dev/null || true
        # shellcheck disable=SC2016
        echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc" 2>/dev/null || true
        echo -e "${GREEN}${ICON_SUCCESS} Added ~/bin to PATH${NC}"
    fi
    
    # Create the command
    cat > "$HOME/bin/aicoder" << 'EOF'
#!/usr/bin/env bash
# aicoder — AICoder Enterprise Framework launcher
# Similar to claudeme but for AICoder with subagent support

set -euo pipefail

AICODER_DIR="${AICODER_DIR:-$HOME/Projects/AICoders-library}"
AICODER_SCRIPT="$AICODER_DIR/aicoder_package/scripts/ultra-clean-one-liner.sh"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

ICON_SUCCESS="✅"
ICON_WARNING="⚠️"
ICON_INFO="ℹ️"
ICON_ROCKET="🚀"

# Available subagents
SUBAGENTS=(
    "architect:High-level system design and architecture"
    "developer:Code implementation and development"
    "typescript-pro:Advanced TypeScript development"
    "python-pro:Python development and frameworks"
    "rust-pro:Rust systems programming"
    "golang-pro:Go development and microservices"
    "java-pro:Java and Spring Boot development"
    "debugger:Systematic bug investigation"
    "quality-reviewer:Production-critical issue identification"
    "test-automator:Test strategy and automation"
    "security-auditor:Security vulnerability scanning"
    "performance-optimizer:Application performance optimization"
    "devops-engineer:DevOps and deployment automation"
    "docker-deployment:Containerization and Docker"
    "terraform-pro:Infrastructure as Code"
    "aws-pro:Amazon Web Services specialist"
    "azure-pro:Microsoft Azure specialist"
    "gcp-pro:Google Cloud Platform specialist"
    "kubernetes-pro:Kubernetes orchestration"
    "data-engineer:Data engineering and pipelines"
    "ai-engineer:AI/ML model development"
    "technical-writer:Technical documentation"
    "api-documenter:API documentation and specs"
    "file-manager:File organization and cleanup"
    "ai-orchestrator:Intelligent agent coordination"
)

logdbg() { [[ "${AICODER_DEBUG:-0}" = "1" ]] && echo "[aicoder] $*" >&2 || true; }
command_exists() { command -v "$1" >/dev/null 2>&1; }

usage() {
    cat <<USAGE_EOF
Usage: $(basename "$0") [command] [options]

Commands:
  install                 Install AICoder in current directory
  init                    Initialize project with AI agent context
  start                   Start development session
  start --agent <name>    Start with specific subagent
  agents                  List available subagents
  agent-help <name>       Show help for specific agent
  context                 Show available context files
  subagents               Show subagent usage guide
  help                    Show this help
  version                 Show version

Examples:
  aicoder install                    # Install AICoder in current directory
  aicoder start                      # Start development session
  aicoder start --agent architect    # Start with architect subagent
  aicoder start --agent developer "Build user authentication"
  aicoder agents                     # List all subagents
  aicoder agent-help architect       # Get help for specific agent

USAGE_EOF
}

pick_subagent_menu() {
    echo "Pick a subagent:" >&2
    local i=1
    while (( i <= ${#SUBAGENTS[@]} )); do
        IFS=':' read -r name description <<< "${SUBAGENTS[$((i-1))]}"
        printf "  %d) %-18s %s\n" "$i" "$name" "$description" >&2
        ((i++))
    done
    echo "" >&2
    read -r -p "Enter choice (1-${#SUBAGENTS[@]}): " choice
    case "$choice" in
        ''|*[!0-9]*) echo "Invalid choice" >&2; echo "" ;;
        *)
            local idx=$((choice - 1))
            if (( choice >= 1 && choice <= ${#SUBAGENTS[@]} )); then
                IFS=':' read -r name description <<< "${SUBAGENTS[$idx]}"
                echo "$name"
            fi
            ;;
    esac
}

pick_subagent_interactive() {
    # Prefer fzf if available and writing to a TTY
    if command_exists fzf && [[ -t 0 && -t 1 && -t 2 ]]; then
        logdbg "Using fzf picker"
        local picked
        picked="$(
            {
                local i
                for ((i=0; i<${#SUBAGENTS[@]}; i++)); do
                    IFS=':' read -r name description <<< "${SUBAGENTS[$i]}"
                    printf "%s\t%s\n" "$name" "$description"
                done
            } | fzf --prompt="Pick AICoder subagent > " \
                   --header="Subagent\tDescription" \
                   --with-nth=1,2 \
                   --height=15 --layout=reverse --border \
            || true
        )"
        picked="$(printf "%s" "$picked" | awk -F'\t' 'NR==1{print $1}')"
        if [[ -n "$picked" ]]; then
            echo "$picked"
            return 0
        fi
        logdbg "fzf returned empty selection; falling back to numbered menu"
    else
        logdbg "fzf not available or stdout not a TTY; using numbered menu"
    fi
    pick_subagent_menu
}

# Check if AICoder is installed in current directory
is_aicoder_installed() {
    [[ -f "./aicoder" && -d ".aicoder" ]]
}

# Install AICoder if not present
ensure_aicoder_installed() {
    if ! is_aicoder_installed; then
        echo -e "${YELLOW}${ICON_WARNING} AICoder not found in current directory${NC}"
        echo -e "${CYAN}${ICON_INFO} Installing AICoder...${NC}"
        
        if [[ ! -f "$AICODER_SCRIPT" ]]; then
            echo -e "${RED}${ICON_WARNING} AICoder installer not found at: $AICODER_SCRIPT${NC}"
            exit 1
        fi
        
        bash "$AICODER_SCRIPT"
        
        if is_aicoder_installed; then
            echo -e "${GREEN}${ICON_SUCCESS} AICoder installed successfully!${NC}"
        else
            echo -e "${RED}${ICON_WARNING} AICoder installation failed${NC}"
            exit 1
        fi
    fi
}

# Exec project aicoder via absolute path (never trust ./aicoder in CWD)
run_aicoder() {
    local AICODER_DIR
    AICODER_DIR="$(pwd -P)"
    exec "${AICODER_DIR}/aicoder" "$@"
}

# Main command handling
case "${1:-help}" in
    "install")
        if [[ ! -f "$AICODER_SCRIPT" ]]; then
            echo -e "${RED}${ICON_WARNING} AICoder installer not found at: $AICODER_SCRIPT${NC}"
            exit 1
        fi
        bash "$AICODER_SCRIPT"
        ;;
    "init"|"start"|"agents"|"agent-help"|"context"|"subagents"|"clean"|"help"|"version")
        ensure_aicoder_installed
        run_aicoder "$@"
        ;;
    "interactive"|"i")
        ensure_aicoder_installed
        echo -e "${BOLD}${CYAN}AICoder Interactive Mode${NC}"
        echo ""
        echo "1. Install AICoder"
        echo "2. Start development session"
        echo "3. Start with specific subagent"
        echo "4. List subagents"
        echo "5. Show help"
        echo ""
        read -r -p "Enter choice (1-5): " choice
        case "$choice" in
            1) run_aicoder init ;;
            2) run_aicoder start ;;
            3)
                subagent="$(pick_subagent_interactive || true)"
                if [[ -n "$subagent" ]]; then
                    run_aicoder start --agent "$subagent"
                else
                    run_aicoder start
                fi
                ;;
            4) run_aicoder agents ;;
            5) run_aicoder help ;;
            *) echo "Invalid choice" && exit 1 ;;
        esac
        ;;
    *)
        if [[ -z "${1:-}" ]]; then
            # No arguments - show interactive mode
            ensure_aicoder_installed
            echo -e "${BOLD}${CYAN}AICoder Enterprise Framework${NC}"
            echo ""
            echo "Quick start:"
            echo "  aicoder install    # Install AICoder in current directory"
            echo "  aicoder start      # Start development session"
            echo "  aicoder agents     # List all subagents"
            echo ""
            echo "For interactive mode: aicoder interactive"
            echo "For help: aicoder help"
        else
            echo -e "${RED}Unknown command: $1${NC}"
            usage
            exit 1
        fi
        ;;
esac
EOF

    chmod +x "$HOME/bin/aicoder"
    echo -e "${GREEN}${ICON_SUCCESS} Local aicoder command created: ~/bin/aicoder${NC}"
}

# Main installation (always ~/bin — no root required)
main() {
    create_global_aicoder
    echo -e "${GREEN}${ICON_SUCCESS} aicoder command installed successfully!${NC}"
    echo ""
    echo -e "${BOLD}Usage:${NC}"
    echo "  aicoder                    # Interactive mode"
    echo "  aicoder install            # Install AICoder in current directory"
    echo "  aicoder start              # Start development session"
    echo "  aicoder start --agent architect  # Start with specific subagent"
    echo "  aicoder agents             # List all subagents"
    echo ""
    echo -e "${YELLOW}${ICON_WARNING} Note: You may need to restart your terminal or run 'source ~/.zshrc'${NC}"
    echo -e "${CYAN}${ICON_ROCKET} Ready to use from anywhere!${NC}"
}

# Run main function
main "$@"
