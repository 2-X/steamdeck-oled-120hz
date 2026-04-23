#!/bin/bash
#
# Steam Deck OLED 120Hz Unlock - Uninstaller
#
# Removes the 120Hz unlock script and restores stock 90Hz behavior.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_PATH="$HOME/.config/gamescope/scripts/99-user/displays/oled-120hz.lua"
BACKUP_PATH="${SCRIPT_PATH}.bak"

info() { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }

echo ""
echo "Steam Deck OLED 120Hz Unlock - Uninstaller"
echo "==========================================="
echo ""

if [[ -f "$SCRIPT_PATH" ]]; then
    rm -f "$SCRIPT_PATH"
    ok "Removed: $SCRIPT_PATH"
else
    info "Script not found at $SCRIPT_PATH (already uninstalled?)"
fi

if [[ -f "$BACKUP_PATH" ]]; then
    rm -f "$BACKUP_PATH"
    ok "Removed backup: $BACKUP_PATH"
fi

# Clean up empty directories
rmdir "$HOME/.config/gamescope/scripts/99-user/displays" 2>/dev/null || true
rmdir "$HOME/.config/gamescope/scripts/99-user" 2>/dev/null || true

echo ""
ok "Uninstallation complete."
echo ""
echo "Reboot your Steam Deck to restore stock 90Hz refresh rate cap."
echo ""

read -p "Reboot now? [Y/n] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    info "Rebooting..."
    sudo reboot
fi
