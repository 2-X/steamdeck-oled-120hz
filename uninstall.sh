#!/bin/bash
#
# Steam Deck Refresh Rate Unlock - Uninstaller
#
# Removes the refresh rate unlock script and restores stock behavior.

set -euo pipefail

GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

INSTALL_DIR="$HOME/.config/gamescope/scripts/99-user/displays"
OLED_SCRIPT="$INSTALL_DIR/oled-120hz.lua"
LCD_SCRIPT="$INSTALL_DIR/lcd-70hz.lua"

info() { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }

echo ""
echo "Steam Deck Refresh Rate Unlock - Uninstaller"
echo "============================================="
echo ""

FOUND=0

for script in "$OLED_SCRIPT" "$LCD_SCRIPT"; do
    if [[ -f "$script" ]]; then
        rm -f "$script"
        ok "Removed: $script"
        FOUND=1
    fi
    if [[ -f "${script}.bak" ]]; then
        rm -f "${script}.bak"
        ok "Removed backup: ${script}.bak"
    fi
done

if [[ $FOUND -eq 0 ]]; then
    info "No unlock scripts found (already uninstalled?)"
fi

# Clean up empty directories
rmdir "$INSTALL_DIR" 2>/dev/null || true
rmdir "$HOME/.config/gamescope/scripts/99-user" 2>/dev/null || true

echo ""
ok "Uninstallation complete."
echo ""
echo "Reboot your Steam Deck to restore stock refresh rate."
echo ""

read -p "Reboot now? [Y/n] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    info "Rebooting..."
    sudo reboot
fi
