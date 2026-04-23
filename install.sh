#!/bin/bash
#
# Steam Deck OLED 120Hz Unlock - Installer
# https://github.com/2-X/steamdeck-oled-120hz
#
# Automatically detects your BOE OLED panel, extracts timing values,
# and installs a gamescope Lua script to unlock 120Hz refresh rate.
#
# Usage:
#   curl -sL https://raw.githubusercontent.com/2-X/steamdeck-oled-120hz/main/install.sh | bash
#
# Or:
#   git clone https://github.com/2-X/steamdeck-oled-120hz.git
#   cd steamdeck-oled-120hz
#   ./install.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

INSTALL_DIR="$HOME/.config/gamescope/scripts/99-user/displays"
SCRIPT_NAME="oled-120hz.lua"

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()   { error "$*"; exit 1; }

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║       Steam Deck OLED 120Hz Unlock - Installer                ║"
echo "║       For BOE OLED panels only (Limited Edition safe)         ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# --- Step 1: Check we're on SteamOS ---
info "Checking operating system..."

if [[ ! -f /etc/os-release ]]; then
    die "Cannot detect OS. This script only works on SteamOS."
fi

source /etc/os-release

if [[ "${ID:-}" != "steamos" ]]; then
    die "This script only works on SteamOS. Detected: ${ID:-unknown}"
fi

# Extract version (e.g., "3.6.21" -> "3.6")
STEAMOS_VERSION="${VERSION_ID:-0.0}"
MAJOR_MINOR=$(echo "$STEAMOS_VERSION" | cut -d. -f1,2)

if [[ $(echo "$MAJOR_MINOR < 3.6" | bc -l 2>/dev/null || echo 1) -eq 1 ]]; then
    # bc might not be available, do a simpler check
    MAJOR=$(echo "$STEAMOS_VERSION" | cut -d. -f1)
    MINOR=$(echo "$STEAMOS_VERSION" | cut -d. -f2)
    if [[ "$MAJOR" -lt 3 ]] || { [[ "$MAJOR" -eq 3 ]] && [[ "$MINOR" -lt 6 ]]; }; then
        die "SteamOS 3.6+ required. Detected: $STEAMOS_VERSION"
    fi
fi

ok "SteamOS $STEAMOS_VERSION detected"

# --- Step 2: Find the eDP connector ---
info "Locating internal display..."

CONNECTOR=""
for c in card1-eDP-1 card0-eDP-1; do
    if [[ -d "/sys/class/drm/$c" ]]; then
        CONNECTOR="$c"
        break
    fi
done

if [[ -z "$CONNECTOR" ]]; then
    die "Could not find internal display (eDP-1). Are you running this on a Steam Deck?"
fi

ok "Found connector: $CONNECTOR"

# --- Step 3: Read EDID and detect panel type ---
info "Reading panel EDID..."

EDID_PATH="/sys/class/drm/$CONNECTOR/edid"
if [[ ! -r "$EDID_PATH" ]]; then
    die "Cannot read EDID at $EDID_PATH"
fi

EDID_HEX=$(xxd -p -l 12 "$EDID_PATH" | tr -d '\n')
if [[ ${#EDID_HEX} -lt 24 ]]; then
    die "EDID data too short. Got: $EDID_HEX"
fi

# Bytes 8-9 = manufacturer ID (VLV = Valve)
# Bytes 10-11 = product code (little-endian)
PRODUCT_LO="${EDID_HEX:20:2}"
PRODUCT_HI="${EDID_HEX:22:2}"
PRODUCT_CODE="0x${PRODUCT_HI}${PRODUCT_LO}"

info "EDID product code: $PRODUCT_CODE"

case "$PRODUCT_LO" in
    04)
        ok "BOE OLED panel detected - safe for 120Hz"
        ;;
    03)
        echo ""
        error "Samsung OLED panel detected (product code 0x3003)"
        echo ""
        echo "Samsung panels have hardware limitations above ~99Hz and may"
        echo "exhibit visual artifacts or damage at 120Hz."
        echo ""
        echo "This unlock is only for BOE OLED panels (Steam Deck OLED"
        echo "Limited Edition and some standard OLED units)."
        echo ""
        die "Installation aborted for your safety."
        ;;
    01)
        echo ""
        error "LCD panel detected (product code 0x3001)"
        echo ""
        echo "This unlock is for OLED panels only. For LCD Steam Decks,"
        echo "use the 70Hz unlock instead:"
        echo "  https://github.com/ryanrudolfoba/SteamDeck-RefreshRateUnlocker"
        echo ""
        die "Installation aborted."
        ;;
    *)
        warn "Unknown panel type (product code: $PRODUCT_CODE)"
        echo ""
        echo "This script expects BOE OLED (0x3004). Your panel code is unknown."
        echo "Proceeding may cause display issues."
        echo ""
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            die "Installation aborted."
        fi
        ;;
esac

# --- Step 4: Extract timing values ---
info "Extracting panel timing values..."

# Try modetest first (more reliable), fall back to xrandr
TIMINGS=""

if command -v modetest >/dev/null 2>&1; then
    # modetest output format (line starting with #0 is preferred mode):
    # #0 800x1280 90.06 800 818 822 858 1280 1288 1290 1320 102000 flags: ...
    TIMINGS=$(sudo modetest -M amdgpu -c 2>/dev/null | \
        awk '/eDP-1/,/props:/' | \
        grep '#0' | \
        head -1)
fi

if [[ -z "$TIMINGS" ]] && command -v xrandr >/dev/null 2>&1; then
    warn "modetest unavailable, trying xrandr..."
    # xrandr --verbose output is more complex, need different parsing
    # Format: h: width 800 start 818 end 822 total 858 ...
    #         v: height 1280 start 1288 end 1290 total 1320 ...
    XRANDR_OUT=$(xrandr --verbose 2>/dev/null | awk '/eDP-1/,/^[A-Z]/' | head -20)
    
    H_LINE=$(echo "$XRANDR_OUT" | grep 'h:' | head -1)
    V_LINE=$(echo "$XRANDR_OUT" | grep 'v:' | head -1)
    
    if [[ -n "$H_LINE" ]] && [[ -n "$V_LINE" ]]; then
        # Parse xrandr format
        HDISPLAY=$(echo "$H_LINE" | awk '{print $3}')
        HSS=$(echo "$H_LINE" | awk '{print $5}')
        HSE=$(echo "$H_LINE" | awk '{print $7}')
        HTOTAL=$(echo "$H_LINE" | awk '{print $9}')
        
        VDISPLAY=$(echo "$V_LINE" | awk '{print $3}')
        VSS=$(echo "$V_LINE" | awk '{print $5}')
        VSE=$(echo "$V_LINE" | awk '{print $7}')
        VTOTAL=$(echo "$V_LINE" | awk '{print $9}')
        
        # Construct fake modetest-style line for unified parsing below
        TIMINGS="#0 ${HDISPLAY}x${VDISPLAY} 90.00 $HDISPLAY $HSS $HSE $HTOTAL $VDISPLAY $VSS $VSE $VTOTAL 102000"
    fi
fi

if [[ -z "$TIMINGS" ]]; then
    die "Could not extract panel timings. Neither modetest nor xrandr provided valid data."
fi

info "Raw timing data: $TIMINGS"

# Parse modetest format:
# #0 800x1280 90.06 800 818 822 858 1280 1288 1290 1320 102000 flags: ...
# Fields: index resolution refresh hdisplay hss hse htot vdisplay vss vse vtot clock
read -r _ _ _ HDISPLAY HSS HSE HTOTAL VDISPLAY VSS VSE VTOTAL _ <<< "$TIMINGS"

# Calculate timing parameters
H_FP=$((HSS - HDISPLAY))
H_SYNC=$((HSE - HSS))
H_BP=$((HTOTAL - HSE))

V_FP=$((VSS - VDISPLAY))
V_SYNC=$((VSE - VSS))
V_BP=$((VTOTAL - VSE))

echo ""
info "Calculated timing values:"
echo "  Horizontal: FP=$H_FP  SYNC=$H_SYNC  BP=$H_BP  (total=$HTOTAL)"
echo "  Vertical:   FP=$V_FP  SYNC=$V_SYNC  BP=$V_BP  (total=$VTOTAL)"
echo ""

# Sanity check values
if [[ $H_FP -le 0 ]] || [[ $H_SYNC -le 0 ]] || [[ $H_BP -le 0 ]] || \
   [[ $V_FP -le 0 ]] || [[ $V_SYNC -le 0 ]] || [[ $V_BP -le 0 ]]; then
    die "Timing values look invalid. Please report this issue with your modetest output."
fi

ok "Timing values extracted successfully"

# --- Step 5: Generate and install the Lua script ---
info "Installing 120Hz unlock script..."

mkdir -p "$INSTALL_DIR"

# Check for existing file
if [[ -f "$INSTALL_DIR/$SCRIPT_NAME" ]]; then
    warn "Existing $SCRIPT_NAME found, backing up to ${SCRIPT_NAME}.bak"
    cp "$INSTALL_DIR/$SCRIPT_NAME" "$INSTALL_DIR/${SCRIPT_NAME}.bak"
fi

cat > "$INSTALL_DIR/$SCRIPT_NAME" << LUAEOF
-- Steam Deck OLED (BOE) 120Hz unlock for gamescope (SteamOS 3.6+)
-- Auto-generated by install.sh with your panel's exact timings.
-- Uninstall: rm ~/.config/gamescope/scripts/99-user/displays/oled-120hz.lua
--
-- Only affects BOE OLED panels (EDID product=0x3004).
-- Samsung (SDC) and LCD panels are unaffected.

local boe = gamescope.config.known_displays.steamdeck_oled_boe
if not boe then
    if warn then
        warn("[oled-120hz] steamdeck_oled_boe profile not found; skipping.")
    end
    return
end

-- Extend supported refresh rates from 91-120Hz
for r = 91, 120 do
    table.insert(boe.dynamic_refresh_rates, r)
end

-- Panel timing values (auto-detected from your hardware)
local BOE_H_FP   = $H_FP
local BOE_H_SYNC = $H_SYNC
local BOE_H_BP   = $H_BP
local BOE_V_FP   = $V_FP
local BOE_V_SYNC = $V_SYNC
local BOE_V_BP   = $V_BP

-- Replace mode generator with variable-clock version
boe.dynamic_modegen = function(base_mode, refresh)
    if debug then
        debug("[oled-120hz] Generating " .. refresh .. "Hz mode for BOE OLED")
    end

    local mode = base_mode

    gamescope.modegen.set_resolution(mode, 800, 1280)
    gamescope.modegen.set_h_timings(mode, BOE_H_FP, BOE_H_SYNC, BOE_H_BP)
    gamescope.modegen.set_v_timings(mode, BOE_V_FP, BOE_V_SYNC, BOE_V_BP)

    mode.clock    = gamescope.modegen.calc_max_clock(mode, refresh)
    mode.vrefresh = gamescope.modegen.calc_vrefresh(mode)

    return mode
end

if debug then
    debug("[oled-120hz] BOE OLED 120Hz unlock active")
end
LUAEOF

# Verify installation
if [[ ! -f "$INSTALL_DIR/$SCRIPT_NAME" ]]; then
    die "Failed to write script to $INSTALL_DIR/$SCRIPT_NAME"
fi

ok "Script installed to: $INSTALL_DIR/$SCRIPT_NAME"

# --- Step 6: Done! ---
echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                    Installation Complete!                     ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "Next steps:"
echo "  1. Reboot your Steam Deck (required for gamescope to load the script)"
echo "  2. After reboot, open Quick Access Menu (...) → Performance"
echo "  3. The refresh rate slider should now go up to 120Hz"
echo ""
echo "To verify 120Hz is working:"
echo "  - Visit https://www.testufo.com/framerates in Desktop Mode browser"
echo "  - Or check: xrandr | grep eDP"
echo ""
echo "To uninstall:"
echo "  rm ~/.config/gamescope/scripts/99-user/displays/oled-120hz.lua"
echo "  (then reboot)"
echo ""
echo "If your screen goes black after reboot:"
echo "  - Hold power button 10 seconds to force shutdown"
echo "  - Boot to Desktop Mode"
echo "  - Delete the script file and reboot"
echo ""

# Only prompt if running interactively (not piped)
if [[ -t 0 ]]; then
    read -p "Reboot now? [Y/n] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        info "Rebooting..."
        sudo reboot
    fi
else
    echo "Run 'sudo reboot' when ready."
fi
