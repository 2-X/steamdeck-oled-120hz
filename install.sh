#!/bin/bash
#
# Steam Deck OLED Refresh Rate Unlock - Installer
# https://github.com/2-X/steamdeck-oled-120hz
#
# Automatically detects your OLED panel (BOE or Samsung), extracts timing
# values, calculates safe limits, and installs a gamescope Lua script to
# unlock higher refresh rates.
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

# Panel type detection (set later)
PANEL_TYPE=""
PANEL_MAX_CLOCK=""
SAFE_MAX_REFRESH=""

# Top end of the refresh rate range to expose to gamescope. Override with:
#   curl -sL https://.../install.sh | MAX_REFRESH=100 bash
# (Note: env var MUST go on the `bash` side of the pipe, not on `curl` -
# otherwise it stays in curl's environment and never reaches this script.)
#
# For BOE panels: 120 is the panel max; 100-110 is a common "best balance"
# For Samsung panels: auto-calculated safe max (~96-99Hz based on pixel clock)
MAX_REFRESH="${MAX_REFRESH:-}"

# Home screen / UI refresh rate. Gamescope uses the LAST entry in the refresh
# rate array as the idle/home target. By default we put 90Hz at the end so the
# home screen stays at stock 90Hz (avoiding gamma issues some panels have at
# higher rates), while games can still select up to MAX_REFRESH.
#
# Set HOME_REFRESH=120 to make the home screen also run at max refresh.
# Set HOME_REFRESH=100 for a middle ground (experimental).
HOME_REFRESH="${HOME_REFRESH:-90}"

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()   { error "$*"; exit 1; }

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║       Steam Deck OLED Refresh Rate Unlock - Installer         ║"
echo "║       Supports BOE (120Hz) and Samsung (up to ~96Hz) panels   ║"
echo "║       Home screen stays at 90Hz by default (configurable)     ║"
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
        PANEL_TYPE="boe"
        ok "BOE OLED panel detected - safe for 120Hz"
        ;;
    03)
        PANEL_TYPE="samsung"
        ok "Samsung OLED panel detected - will calculate safe max refresh"
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
        echo "This script expects BOE OLED (0x3004) or Samsung OLED (0x3003)."
        echo "Your panel code is unknown. Proceeding may cause display issues."
        echo ""
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            die "Installation aborted."
        fi
        PANEL_TYPE="unknown"
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
read -r _ _ REFRESH_RATE HDISPLAY HSS HSE HTOTAL VDISPLAY VSS VSE VTOTAL PIXEL_CLOCK _ <<< "$TIMINGS"

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
echo "  Pixel clock at ${REFRESH_RATE}Hz: ${PIXEL_CLOCK} kHz"
echo ""

# Sanity check values
if [[ $H_FP -le 0 ]] || [[ $H_SYNC -le 0 ]] || [[ $H_BP -le 0 ]] || \
   [[ $V_FP -le 0 ]] || [[ $V_SYNC -le 0 ]] || [[ $V_BP -le 0 ]]; then
    die "Timing values look invalid. Please report this issue with your modetest output."
fi

ok "Timing values extracted successfully"

# --- Step 5: Calculate safe max refresh rate ---
info "Calculating safe refresh rate limits..."

# pixel_clock (kHz) = htotal * vtotal * refresh / 1000
# refresh = pixel_clock * 1000 / (htotal * vtotal)
TOTAL_PIXELS=$((HTOTAL * VTOTAL))

if [[ "$PANEL_TYPE" == "boe" ]]; then
    # BOE panels can handle up to ~133Hz theoretically, we cap at 120
    SAFE_MAX_REFRESH=120
    ok "BOE panel: safe max = 120Hz"
elif [[ "$PANEL_TYPE" == "samsung" ]]; then
    # Samsung panels are limited by pixel clock. We use a conservative 10% headroom
    # above the stock 90Hz clock, capped at 99Hz absolute max.
    # 
    # Calculate: max_clock = stock_clock * 1.10 (10% headroom)
    #            safe_refresh = floor(max_clock * 1000 / total_pixels)
    #            final = min(safe_refresh, 99)
    
    # Stock clock with 10% headroom
    MAX_CLOCK_KHZ=$(( (PIXEL_CLOCK * 110) / 100 ))
    
    # Calculate max refresh from that clock
    # refresh = clock * 1000 / (htotal * vtotal)
    # We need integer math, so: refresh = (clock * 1000) / total_pixels
    CALC_MAX_REFRESH=$(( (MAX_CLOCK_KHZ * 1000) / TOTAL_PIXELS ))
    
    # Cap at 99Hz for Samsung (hard limit based on reported hardware constraints)
    if [[ $CALC_MAX_REFRESH -gt 99 ]]; then
        SAFE_MAX_REFRESH=99
    else
        SAFE_MAX_REFRESH=$CALC_MAX_REFRESH
    fi
    
    ok "Samsung panel: calculated safe max = ${SAFE_MAX_REFRESH}Hz (based on ${PIXEL_CLOCK}kHz clock + 10% headroom, capped at 99)"
else
    # Unknown panel - be conservative, cap at 99Hz
    SAFE_MAX_REFRESH=99
    warn "Unknown panel: using conservative max = 99Hz"
fi

# Now validate/set MAX_REFRESH
if [[ -z "$MAX_REFRESH" ]]; then
    # No override specified, use calculated safe max
    MAX_REFRESH=$SAFE_MAX_REFRESH
    info "Using calculated safe max: MAX_REFRESH=$MAX_REFRESH"
else
    # User specified a value, validate it
    if ! [[ "$MAX_REFRESH" =~ ^[0-9]+$ ]]; then
        die "MAX_REFRESH must be an integer (got: $MAX_REFRESH)"
    fi
    
    if [[ "$MAX_REFRESH" -lt 91 ]]; then
        die "MAX_REFRESH must be at least 91 (got: $MAX_REFRESH)"
    fi
    
    if [[ "$MAX_REFRESH" -gt "$SAFE_MAX_REFRESH" ]]; then
        warn "MAX_REFRESH=$MAX_REFRESH exceeds calculated safe max ($SAFE_MAX_REFRESH) for your panel"
        echo ""
        echo "This may cause visual artifacts, black screen, or panel damage."
        echo ""
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            die "Installation aborted. Use MAX_REFRESH=$SAFE_MAX_REFRESH or lower."
        fi
        warn "Proceeding with MAX_REFRESH=$MAX_REFRESH at your own risk"
    else
        ok "User override: MAX_REFRESH=$MAX_REFRESH (within safe range)"
    fi
fi

# Validate HOME_REFRESH
if ! [[ "$HOME_REFRESH" =~ ^[0-9]+$ ]]; then
    die "HOME_REFRESH must be an integer (got: $HOME_REFRESH)"
fi

if [[ "$HOME_REFRESH" -lt 45 ]] || [[ "$HOME_REFRESH" -gt "$MAX_REFRESH" ]]; then
    die "HOME_REFRESH must be between 45 and MAX_REFRESH ($MAX_REFRESH). Got: $HOME_REFRESH"
fi

if [[ "$HOME_REFRESH" -eq 90 ]]; then
    info "Home screen will stay at stock 90Hz (default)"
elif [[ "$HOME_REFRESH" -gt 90 ]]; then
    info "Home screen will run at ${HOME_REFRESH}Hz (experimental - may have gamma issues)"
else
    info "Home screen will run at ${HOME_REFRESH}Hz"
fi

# --- Step 6: Generate and install the Lua script ---
info "Installing refresh rate unlock script..."

mkdir -p "$INSTALL_DIR"

# Check for existing file
if [[ -f "$INSTALL_DIR/$SCRIPT_NAME" ]]; then
    warn "Existing $SCRIPT_NAME found, backing up to ${SCRIPT_NAME}.bak"
    cp "$INSTALL_DIR/$SCRIPT_NAME" "$INSTALL_DIR/${SCRIPT_NAME}.bak"
fi

# Determine which gamescope profile to use based on panel type
if [[ "$PANEL_TYPE" == "samsung" ]]; then
    GAMESCOPE_PROFILE="steamdeck_oled_sdc"
    PROFILE_DISPLAY_NAME="Samsung OLED"
else
    GAMESCOPE_PROFILE="steamdeck_oled_boe"
    PROFILE_DISPLAY_NAME="BOE OLED"
fi

cat > "$INSTALL_DIR/$SCRIPT_NAME" << LUAEOF
-- Steam Deck OLED refresh rate unlock for gamescope (SteamOS 3.6+)
-- Auto-generated by install.sh with your panel's exact timings.
-- Uninstall: rm ~/.config/gamescope/scripts/99-user/displays/oled-120hz.lua
--
-- Panel type: $PROFILE_DISPLAY_NAME
-- Calculated safe max: ${SAFE_MAX_REFRESH}Hz
-- Configured max: ${MAX_REFRESH}Hz
-- Home screen rate: ${HOME_REFRESH}Hz

local panel = gamescope.config.known_displays.$GAMESCOPE_PROFILE
if not panel then
    if warn then
        warn("[oled-120hz] $GAMESCOPE_PROFILE profile not found; skipping.")
    end
    return
end

-- ============================================================
-- USER CONFIG
-- ============================================================
-- Max refresh rate available for games to select.
-- Panel: $PROFILE_DISPLAY_NAME
-- Safe max for your panel: ${SAFE_MAX_REFRESH}Hz
local MAX_REFRESH = $MAX_REFRESH

-- Home screen / UI refresh rate. Gamescope uses the LAST entry in the
-- refresh rate array as the idle/home target. Set to MAX_REFRESH for
-- full speed everywhere, or lower (e.g., 90) to avoid gamma issues.
local HOME_REFRESH = $HOME_REFRESH
-- ============================================================

-- Gamescope uses the LAST entry in dynamic_refresh_rates as the idle/home
-- target. The stock array ends at 90Hz. We need to rebuild the array so
-- HOME_REFRESH ends up last, while all other rates (stock + extended) are
-- available for games to select.

-- Save stock rates and clear the array
local stock_rates = {}
for i, r in ipairs(panel.dynamic_refresh_rates) do
    if r ~= HOME_REFRESH then
        table.insert(stock_rates, r)
    end
end

-- Rebuild: stock rates (minus HOME_REFRESH) + extended rates (minus HOME_REFRESH) + HOME_REFRESH
panel.dynamic_refresh_rates = {}
for _, r in ipairs(stock_rates) do
    table.insert(panel.dynamic_refresh_rates, r)
end
for r = 91, MAX_REFRESH do
    if r ~= HOME_REFRESH then
        table.insert(panel.dynamic_refresh_rates, r)
    end
end
table.insert(panel.dynamic_refresh_rates, HOME_REFRESH)

-- Panel timing values (auto-detected from your hardware)
local PANEL_H_FP   = $H_FP
local PANEL_H_SYNC = $H_SYNC
local PANEL_H_BP   = $H_BP
local PANEL_V_FP   = $V_FP
local PANEL_V_SYNC = $V_SYNC
local PANEL_V_BP   = $V_BP

-- Preserve Valve's stock modegen for refresh rates <= 90Hz so the existing
-- 45-90Hz behavior stays bit-identical to a vanilla Deck. Without this
-- guard we'd hijack the modegen for stock rates too, causing subtle gamma
-- regressions reported by some panels even at 90Hz.
local stock_modegen = panel.dynamic_modegen

panel.dynamic_modegen = function(base_mode, refresh)
    if refresh <= 90 and stock_modegen then
        return stock_modegen(base_mode, refresh)
    end

    if debug then
        debug("[oled-120hz] Generating " .. refresh .. "Hz mode for $PROFILE_DISPLAY_NAME")
    end

    local mode = base_mode

    gamescope.modegen.set_resolution(mode, 800, 1280)
    gamescope.modegen.set_h_timings(mode, PANEL_H_FP, PANEL_H_SYNC, PANEL_H_BP)
    gamescope.modegen.set_v_timings(mode, PANEL_V_FP, PANEL_V_SYNC, PANEL_V_BP)

    mode.clock    = gamescope.modegen.calc_max_clock(mode, refresh)
    mode.vrefresh = gamescope.modegen.calc_vrefresh(mode)

    return mode
end

if debug then
    debug("[oled-120hz] $PROFILE_DISPLAY_NAME refresh unlock active (max: " .. MAX_REFRESH .. "Hz, home: " .. HOME_REFRESH .. "Hz)")
end
LUAEOF

# Verify installation
if [[ ! -f "$INSTALL_DIR/$SCRIPT_NAME" ]]; then
    die "Failed to write script to $INSTALL_DIR/$SCRIPT_NAME"
fi

ok "Script installed to: $INSTALL_DIR/$SCRIPT_NAME"

# --- Step 7: Done! ---
echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                    Installation Complete!                     ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "Panel type: $PROFILE_DISPLAY_NAME"
echo "Safe max for your panel: ${SAFE_MAX_REFRESH}Hz"
echo "Installed with MAX_REFRESH=$MAX_REFRESH, HOME_REFRESH=$HOME_REFRESH"
echo ""
echo "Next steps:"
echo "  1. Run: sudo reboot"
echo "  2. After reboot, you'll be in Gaming Mode"
echo "  3. Press the Quick Access button (... button below right trackpad)"
echo "  4. Go to Performance tab (battery icon)"
echo "  5. Set Performance Overlay Level to at least 1 to see your FPS/refresh"
echo "  6. Scroll down to Refresh Rate slider - it should now go up to ${MAX_REFRESH}Hz"
echo ""
if [[ "$PANEL_TYPE" == "samsung" ]]; then
echo "Samsung panel detected! Your refresh rate is capped at ${MAX_REFRESH}Hz for safety."
echo "This gives you clean frame pacing multiples (${MAX_REFRESH}/$((MAX_REFRESH/2))/$((MAX_REFRESH/4))Hz)."
echo ""
fi
if [[ "$HOME_REFRESH" -eq 90 ]]; then
echo "Home screen will stay at stock 90Hz (avoiding potential gamma issues)."
echo "Games can still select up to ${MAX_REFRESH}Hz via the QAM slider."
echo ""
echo "To run the home screen at a higher rate (experimental):"
echo "  curl -sL .../install.sh | HOME_REFRESH=100 bash"
echo ""
else
echo "Home screen will run at ${HOME_REFRESH}Hz."
echo "If home screen colors look off, reinstall with HOME_REFRESH=90 (default)."
echo ""
fi
echo "Configuration options (env vars go on the 'bash' side of the pipe):"
echo "  MAX_REFRESH=N   - Max refresh rate for games (default: auto-detected)"
echo "  HOME_REFRESH=N  - Home screen refresh rate (default: 90)"
echo ""
echo "Examples:"
echo "  # Max out everything (may have gamma issues on home screen)"
echo "  curl -sL .../install.sh | MAX_REFRESH=120 HOME_REFRESH=120 bash"
echo ""
echo "  # 100Hz home, 120Hz games (experimental middle ground)"
echo "  curl -sL .../install.sh | HOME_REFRESH=100 bash"
echo ""
echo "To uninstall:"
echo "  rm ~/.config/gamescope/scripts/99-user/displays/oled-120hz.lua"
echo "  sudo reboot"
echo ""
echo "If your screen goes black after reboot:"
echo "  - Hold power button 10 seconds to force shutdown"
echo "  - Boot to Desktop Mode (hold Volume Down + Power, select it from boot menu)"
echo "  - Open Konsole, delete the script, reboot"
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
