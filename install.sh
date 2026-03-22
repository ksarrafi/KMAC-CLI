#!/bin/bash
# install.sh — Install and configure KMac Toolkit on this Mac

set -euo pipefail

# ─── Colors ───────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

ICON_SUCCESS="✓"
ICON_WARNING="!"
ICON_INFO=">"

# ─── Get Toolkit Path ─────────────────────────────────────────────────────
TOOLKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$TOOLKIT_DIR/scripts"
ALIASES_FILE="$TOOLKIT_DIR/aliases.sh"
ENV_TEMPLATE="$TOOLKIT_DIR/env.template"
ZSHRC_FILE="$HOME/.zshrc"
BASHRC_FILE="$HOME/.bashrc"

echo ""
echo -e "${BOLD}${CYAN}Installing KMac Toolkit...${NC}"
echo ""

# ─── 1. Check for iCloud Drive ────────────────────────────────────────────
# Detect install method
ICLOUD_GLOB=~/Library/CloudStorage/iCloudDrive*/com~apple~CloudDocs/Scripts/toolkit
if ls $ICLOUD_GLOB &>/dev/null 2>&1; then
    INSTALL_MODE="icloud"
    echo -e "${GREEN}${ICON_SUCCESS} iCloud Drive detected — syncs across all Macs${NC}"
else
    INSTALL_MODE="local"
    echo -e "${GREEN}${ICON_SUCCESS} Local install from ${TOOLKIT_DIR}${NC}"
fi

# ─── 2. Make all scripts executable ───────────────────────────────────────
echo -e "${CYAN}${ICON_INFO} Making scripts executable...${NC}"
chmod +x "$TOOLKIT_DIR/toolkit.sh" 2>/dev/null || true
chmod +x "$TOOLKIT_DIR/install.sh" 2>/dev/null || true
chmod +x "$SCRIPTS_DIR"/* 2>/dev/null || true
echo -e "${GREEN}${ICON_SUCCESS} Scripts are executable${NC}"

# ─── 3. Add toolkit alias to .zshrc (if zsh is available) ────────────────
echo -e "${CYAN}${ICON_INFO} Setting up .zshrc...${NC}"

if [[ "$INSTALL_MODE" == "icloud" ]]; then
    TOOLKIT_ALIAS="alias toolkit='bash \$(echo ~/Library/CloudStorage/iCloudDrive*/com~apple~CloudDocs/Scripts/toolkit/toolkit.sh)'"
    ALIAS_EXPORT="source ~/Library/CloudStorage/iCloudDrive*/com~apple~CloudDocs/Scripts/toolkit/aliases.sh"
    ENV_SOURCE="[[ -f ~/Library/CloudStorage/iCloudDrive*/com~apple~CloudDocs/Scripts/toolkit/env.sh ]] && source ~/Library/CloudStorage/iCloudDrive*/com~apple~CloudDocs/Scripts/toolkit/env.sh"
else
    TOOLKIT_ALIAS="alias toolkit='bash ${TOOLKIT_DIR}/toolkit.sh'"
    ALIAS_EXPORT="source ${TOOLKIT_DIR}/aliases.sh"
    ENV_SOURCE="[[ -f ${TOOLKIT_DIR}/env.sh ]] && source ${TOOLKIT_DIR}/env.sh"
fi
KMAC_ALIAS="alias kmac='toolkit'"

if [[ -f "$ZSHRC_FILE" ]]; then
    # Check if toolkit alias already exists
    if ! grep -q "alias toolkit=" "$ZSHRC_FILE"; then
        echo "" >> "$ZSHRC_FILE"
        echo "# KMac Toolkit" >> "$ZSHRC_FILE"
        echo "$TOOLKIT_ALIAS" >> "$ZSHRC_FILE"
        echo "$KMAC_ALIAS" >> "$ZSHRC_FILE"
        echo "$ALIAS_EXPORT" >> "$ZSHRC_FILE"
        echo "$ENV_SOURCE" >> "$ZSHRC_FILE"
        echo -e "${GREEN}${ICON_SUCCESS} Added toolkit + kmac aliases to .zshrc${NC}"
    else
        if ! grep -q "alias kmac=" "$ZSHRC_FILE"; then
            sed -i '' "/alias toolkit=/a\\
$KMAC_ALIAS" "$ZSHRC_FILE"
            echo -e "${GREEN}${ICON_SUCCESS} Added kmac alias to .zshrc${NC}"
        fi
        echo -e "${YELLOW}${ICON_WARNING} toolkit alias already in .zshrc${NC}"
    fi
else
    echo -e "${YELLOW}${ICON_WARNING} .zshrc not found${NC}"
fi

# ─── 4. Add toolkit alias to .bashrc (if bash is available) ──────────────
echo -e "${CYAN}${ICON_INFO} Setting up .bashrc...${NC}"

if [[ -f "$BASHRC_FILE" ]]; then
    if ! grep -q "alias toolkit=" "$BASHRC_FILE"; then
        echo "" >> "$BASHRC_FILE"
        echo "# KMac Toolkit" >> "$BASHRC_FILE"
        echo "$TOOLKIT_ALIAS" >> "$BASHRC_FILE"
        echo "$KMAC_ALIAS" >> "$BASHRC_FILE"
        echo "$ALIAS_EXPORT" >> "$BASHRC_FILE"
        echo "$ENV_SOURCE" >> "$BASHRC_FILE"
        echo -e "${GREEN}${ICON_SUCCESS} Added toolkit + kmac aliases to .bashrc${NC}"
    else
        if ! grep -q "alias kmac=" "$BASHRC_FILE"; then
            sed -i '' "/alias toolkit=/a\\
$KMAC_ALIAS" "$BASHRC_FILE"
            echo -e "${GREEN}${ICON_SUCCESS} Added kmac alias to .bashrc${NC}"
        fi
        echo -e "${YELLOW}${ICON_WARNING} toolkit alias already in .bashrc${NC}"
    fi
else
    echo -e "${YELLOW}${ICON_WARNING} .bashrc not found${NC}"
fi

# ─── 5. Add ~/bin to PATH if not already there ────────────────────────────
echo -e "${CYAN}${ICON_INFO} Checking PATH for ~/bin...${NC}"

if [[ -f "$ZSHRC_FILE" ]]; then
    if ! grep -q "~/bin:.*PATH\|HOME/bin:.*PATH" "$ZSHRC_FILE"; then
        echo 'export PATH="$HOME/bin:$PATH"' >> "$ZSHRC_FILE"
        echo -e "${GREEN}${ICON_SUCCESS} Added ~/bin to PATH in .zshrc${NC}"
    else
        echo -e "${YELLOW}${ICON_WARNING} ~/bin already in PATH${NC}"
    fi
fi

# ─── 6. Symlink scripts to ~/bin (optional) ───────────────────────────────
echo -e "${CYAN}${ICON_INFO} Creating symlinks in ~/bin...${NC}"

mkdir -p ~/bin

for script in aicoder claudeme remote-terminal.sh ask review aicommit sessions project cursoragent killport pilot dotbackup update-check toolmaker; do
    if [[ -f "$SCRIPTS_DIR/$script" ]]; then
        if [[ ! -e ~/bin/$script ]]; then
            ln -s "$SCRIPTS_DIR/$script" ~/bin/$script
            echo -e "${GREEN}${ICON_SUCCESS} Symlinked $script${NC}"
        else
            echo -e "${YELLOW}${ICON_WARNING} ~/bin/$script already exists${NC}"
        fi
    fi
done

# Symlink kmac -> toolkit.sh for direct CLI access
if [[ ! -e ~/bin/kmac ]]; then
    ln -s "$TOOLKIT_DIR/toolkit.sh" ~/bin/kmac
    echo -e "${GREEN}${ICON_SUCCESS} Symlinked kmac${NC}"
else
    echo -e "${YELLOW}${ICON_WARNING} ~/bin/kmac already exists${NC}"
fi

# ─── 7. Install Homebrew dependencies ──────────────────────────────────────
echo -e "${CYAN}${ICON_INFO} Checking Homebrew dependencies...${NC}"

DEPS=(ttyd ngrok caddy qrencode tmux bat fzf)
MISSING=()

for dep in "${DEPS[@]}"; do
    if ! command -v "$dep" &>/dev/null; then
        MISSING+=("$dep")
    fi
done

if (( ${#MISSING[@]} )); then
    echo -e "${YELLOW}${ICON_WARNING} Missing: ${MISSING[*]}${NC}"
    read -r -p "Install with Homebrew? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if command -v brew &>/dev/null; then
            brew install "${MISSING[@]}"
            echo -e "${GREEN}${ICON_SUCCESS} Installed dependencies${NC}"
        else
            echo -e "${RED}${ICON_WARNING} Homebrew not found. Please install Homebrew first.${NC}"
            echo "Visit: https://brew.sh"
        fi
    else
        echo -e "${YELLOW}${ICON_WARNING} Skipping dependency installation${NC}"
    fi
else
    echo -e "${GREEN}${ICON_SUCCESS} All dependencies installed${NC}"
fi

# ─── 8. Create env.sh from template if it doesn't exist ─────────────────
echo -e "${CYAN}${ICON_INFO} Checking environment configuration...${NC}"

ENV_FILE="$TOOLKIT_DIR/env.sh"
if [[ ! -f "$ENV_FILE" ]]; then
    cp "$ENV_TEMPLATE" "$ENV_FILE"
    echo -e "${GREEN}${ICON_SUCCESS} Created env.sh from template${NC}"
    echo -e "${YELLOW}${ICON_WARNING} Remember to edit env.sh and add your API keys!${NC}"
else
    echo -e "${YELLOW}${ICON_WARNING} env.sh already exists${NC}"
fi

# ─── Final Summary ────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}✓ Installation Complete!${NC}"
echo ""
echo -e "${CYAN}Quick start:${NC}"
echo "  1. Reload shell: ${BOLD}source ~/.zshrc${NC}"
echo "  2. Launch toolkit: ${BOLD}toolkit${NC}"
echo ""
echo -e "${CYAN}Next steps:${NC}"
echo "  - Edit env.sh with your API keys"
echo "  - Run 'toolkit' from any directory"
echo ""
