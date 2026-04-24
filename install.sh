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

# Panel type detection (set later)
PANEL_TYPE=""
PANEL_MAX_CLOCK=""
SAFE_MAX_REFRESH=""
SCRIPT_NAME=""

# Top end of the refresh rate range to expose to gamescope. Override with:
#   curl -sL https://.../install.sh | MAX_REFRESH=100 bash
# (Note: env var MUST go on the `bash` side of the pipe, not on `curl` -
# otherwise it stays in curl's environment and never reaches this script.)
#
# For BOE panels: 120 is the panel max; 100-110 is a common "best balance"
# For Samsung panels: auto-calculated safe max (~96-99Hz based on pixel clock)
MAX_REFRESH="${MAX_REFRESH:-}"

# Home screen / UI refresh rate. Gamescope uses the LAST entry in the refresh
# rate array as the idle/home target. By default we use stock rate (90Hz OLED,
# 60Hz LCD) so the home screen stays at default while games can use higher rates.
#
# Set HOME_REFRESH to max to make the home screen also run at max refresh.
# Default is set after panel detection.
HOME_REFRESH="${HOME_REFRESH:-}"

# EXPERIMENTAL: Samsung panel modegen approach. Some Samsung panels show
# pixelation artifacts at overclocked refresh rates. Try different approaches:
#   - "clock" (default): Variable pixel clock, fixed blanking intervals
#   - "vfp": Variable front porch + slight clock boost (like ROG Ally)
#   - "hybrid": Blend of both approaches with smaller clock increase
#   - "stock": Don't override modegen at all, only extend refresh rates
#   - "hblank": Reduce horizontal blanking to keep clock lower (experimental)
#   - "round": Round pixel clock to nearest MHz (cleaner PLL lock)
#   - "syncshift": Shift sync pulse earlier in blanking period
#   - "even": Force even htotal (some DDICs have odd-width bugs)
#   - "lowclock": Conservative 93-94Hz target with minimal clock change
#   - "cvtrb": CVT Reduced Blanking v2 style timings
#
# Usage: curl -sL .../install.sh | SAMSUNG_MODE=vfp bash
SAMSUNG_MODE="${SAMSUNG_MODE:-clock}"

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()   { error "$*"; exit 1; }

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║         Steam Deck Refresh Rate Unlock - Installer            ║"
echo "║   OLED: BOE (120Hz), Samsung (~96Hz)  •  LCD: up to 70Hz      ║"
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
        PANEL_TYPE="lcd"
        ok "LCD panel detected - safe for 70Hz"
        ;;
    *)
        warn "Unknown panel type (product code: $PRODUCT_CODE)"
        echo ""
        echo "This script expects BOE OLED (0x3004), Samsung OLED (0x3003), or LCD (0x3001)."
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

# --- Step 4: Extract timing values (OLED only) ---
# LCD doesn't need custom timings - it just extends the refresh rate array

if [[ "$PANEL_TYPE" != "lcd" ]]; then
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
else
    info "LCD panel - skipping timing extraction (not needed)"
fi

# --- Step 5: Calculate safe max refresh rate ---
info "Calculating safe refresh rate limits..."

if [[ "$PANEL_TYPE" == "lcd" ]]; then
    # LCD panels cap at 70Hz
    SAFE_MAX_REFRESH=70
    ok "LCD panel: safe max = 70Hz"
elif [[ "$PANEL_TYPE" == "boe" ]]; then
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
    
    # pixel_clock (kHz) = htotal * vtotal * refresh / 1000
    # refresh = pixel_clock * 1000 / (htotal * vtotal)
    TOTAL_PIXELS=$((HTOTAL * VTOTAL))
    
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
# LCD starts at 61 (stock is 60), OLED starts at 91 (stock is 90)
if [[ "$PANEL_TYPE" == "lcd" ]]; then
    MIN_REFRESH=61
else
    MIN_REFRESH=91
fi

if [[ -z "$MAX_REFRESH" ]]; then
    # No override specified, use calculated safe max
    MAX_REFRESH=$SAFE_MAX_REFRESH
    info "Using calculated safe max: MAX_REFRESH=$MAX_REFRESH"
else
    # User specified a value, validate it
    if ! [[ "$MAX_REFRESH" =~ ^[0-9]+$ ]]; then
        die "MAX_REFRESH must be an integer (got: $MAX_REFRESH)"
    fi
    
    if [[ "$MAX_REFRESH" -lt "$MIN_REFRESH" ]]; then
        die "MAX_REFRESH must be at least $MIN_REFRESH (got: $MAX_REFRESH)"
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

# Set HOME_REFRESH default based on panel type
if [[ "$PANEL_TYPE" == "lcd" ]]; then
    DEFAULT_HOME_REFRESH=60
else
    DEFAULT_HOME_REFRESH=90
fi

if [[ -z "$HOME_REFRESH" ]]; then
    HOME_REFRESH=$DEFAULT_HOME_REFRESH
fi

# Validate HOME_REFRESH
if ! [[ "$HOME_REFRESH" =~ ^[0-9]+$ ]]; then
    die "HOME_REFRESH must be an integer (got: $HOME_REFRESH)"
fi

if [[ "$HOME_REFRESH" -lt 40 ]] || [[ "$HOME_REFRESH" -gt "$MAX_REFRESH" ]]; then
    die "HOME_REFRESH must be between 40 and MAX_REFRESH ($MAX_REFRESH). Got: $HOME_REFRESH"
fi

if [[ "$HOME_REFRESH" -eq "$DEFAULT_HOME_REFRESH" ]]; then
    info "Home screen will stay at stock ${DEFAULT_HOME_REFRESH}Hz (default)"
elif [[ "$HOME_REFRESH" -gt "$DEFAULT_HOME_REFRESH" ]]; then
    info "Home screen will run at ${HOME_REFRESH}Hz"
else
    info "Home screen will run at ${HOME_REFRESH}Hz"
fi

# Validate SAMSUNG_MODE (only matters for Samsung panels but validate anyway)
case "$SAMSUNG_MODE" in
    clock|vfp|hybrid|stock|hblank|round|syncshift|even|lowclock|cvtrb)
        if [[ "$PANEL_TYPE" == "samsung" ]]; then
            info "Samsung modegen mode: $SAMSUNG_MODE"
        fi
        ;;
    *)
        die "SAMSUNG_MODE must be one of: clock, vfp, hybrid, stock, hblank, round, syncshift, even, lowclock, cvtrb (got: $SAMSUNG_MODE)"
        ;;
esac

# --- Step 6: Generate and install the Lua script ---
info "Installing refresh rate unlock script..."

mkdir -p "$INSTALL_DIR"

# Determine which gamescope profile and script name to use based on panel type
if [[ "$PANEL_TYPE" == "lcd" ]]; then
    GAMESCOPE_PROFILE="steamdeck_lcd"
    PROFILE_DISPLAY_NAME="LCD"
    SCRIPT_NAME="lcd-70hz.lua"
elif [[ "$PANEL_TYPE" == "samsung" ]]; then
    GAMESCOPE_PROFILE="steamdeck_oled_sdc"
    PROFILE_DISPLAY_NAME="Samsung OLED"
    SCRIPT_NAME="oled-120hz.lua"
else
    GAMESCOPE_PROFILE="steamdeck_oled_boe"
    PROFILE_DISPLAY_NAME="BOE OLED"
    SCRIPT_NAME="oled-120hz.lua"
fi

# Check for existing file
if [[ -f "$INSTALL_DIR/$SCRIPT_NAME" ]]; then
    warn "Existing $SCRIPT_NAME found, backing up to ${SCRIPT_NAME}.bak"
    cp "$INSTALL_DIR/$SCRIPT_NAME" "$INSTALL_DIR/${SCRIPT_NAME}.bak"
fi

# Generate panel-specific Lua script
if [[ "$PANEL_TYPE" == "lcd" ]]; then
    # LCD script - simpler, just extends refresh rates (no custom modegen needed)
    cat > "$INSTALL_DIR/$SCRIPT_NAME" << LUAEOF
-- Steam Deck LCD refresh rate unlock for gamescope (SteamOS 3.6+)
-- Auto-generated by install.sh
-- Uninstall: rm ~/.config/gamescope/scripts/99-user/displays/lcd-70hz.lua
--
-- Panel type: LCD
-- Max refresh: ${MAX_REFRESH}Hz
-- Home screen rate: ${HOME_REFRESH}Hz

local panel = gamescope.config.known_displays.$GAMESCOPE_PROFILE
if not panel then
    if warn then
        warn("[lcd-70hz] $GAMESCOPE_PROFILE profile not found; skipping.")
    end
    return
end

local MAX_REFRESH = $MAX_REFRESH
local HOME_REFRESH = $HOME_REFRESH

-- Gamescope uses the LAST entry as the idle/home target.
-- Rebuild array: stock rates (minus HOME_REFRESH) + extended rates + HOME_REFRESH at end

local stock_rates = {}
for i, r in ipairs(panel.dynamic_refresh_rates) do
    if r ~= HOME_REFRESH then
        table.insert(stock_rates, r)
    end
end

panel.dynamic_refresh_rates = {}
for _, r in ipairs(stock_rates) do
    table.insert(panel.dynamic_refresh_rates, r)
end
for r = 61, MAX_REFRESH do
    if r ~= HOME_REFRESH then
        table.insert(panel.dynamic_refresh_rates, r)
    end
end
table.insert(panel.dynamic_refresh_rates, HOME_REFRESH)

if debug then
    debug("[lcd-70hz] LCD refresh unlock active (max: " .. MAX_REFRESH .. "Hz, home: " .. HOME_REFRESH .. "Hz)")
end
LUAEOF

else
    # OLED script - includes custom modegen for higher refresh rates
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

-- Samsung panel modegen mode (experimental options for pixelation fix)
local SAMSUNG_MODE = "$SAMSUNG_MODE"

panel.dynamic_modegen = function(base_mode, refresh)
    if refresh <= 90 and stock_modegen then
        return stock_modegen(base_mode, refresh)
    end

    local mode = base_mode
    local is_samsung = ("$PANEL_TYPE" == "samsung")
    
    -- "stock" mode: don't override modegen at all, let gamescope handle it
    if is_samsung and SAMSUNG_MODE == "stock" then
        if stock_modegen then
            if debug then
                debug("[oled-120hz] Samsung stock mode: using original modegen for " .. refresh .. "Hz")
            end
            return stock_modegen(base_mode, refresh)
        end
    end
    
    -- Calculate common values
    local htotal = 800 + PANEL_H_FP + PANEL_H_SYNC + PANEL_H_BP
    local base_vtotal = 1280 + PANEL_V_FP + PANEL_V_SYNC + PANEL_V_BP
    local stock_clock = math.floor((htotal * base_vtotal * 90) / 1000)
    
    -- "vfp" mode: Variable front porch with minimal clock boost (like ROG Ally)
    if is_samsung and SAMSUNG_MODE == "vfp" then
        -- Boost clock by only 5-7% instead of full calc_max_clock
        local boosted_clock = math.floor(stock_clock * 1.07)
        local target_vtotal = math.floor((boosted_clock * 1000) / (htotal * refresh))
        local new_vfp = target_vtotal - 1280 - PANEL_V_SYNC - PANEL_V_BP
        
        if new_vfp >= 2 then
            gamescope.modegen.set_resolution(mode, 800, 1280)
            gamescope.modegen.set_h_timings(mode, PANEL_H_FP, PANEL_H_SYNC, PANEL_H_BP)
            gamescope.modegen.set_v_timings(mode, new_vfp, PANEL_V_SYNC, PANEL_V_BP)
            mode.clock = boosted_clock
            mode.vrefresh = gamescope.modegen.calc_vrefresh(mode)
            
            if debug then
                debug("[oled-120hz] Samsung VFP mode: " .. refresh .. "Hz clock=" .. boosted_clock .. " vfp=" .. new_vfp)
            end
            return mode
        end
    end
    
    -- "hybrid" mode: Smaller clock increase + reduced blanking
    if is_samsung and SAMSUNG_MODE == "hybrid" then
        -- Split the difference: 50% from clock increase, 50% from blanking reduction
        local full_clock = gamescope.modegen.calc_max_clock(base_mode, refresh)
        local partial_clock = math.floor(stock_clock + (full_clock - stock_clock) * 0.5)
        
        -- Calculate VFP needed at partial clock
        local target_vtotal = math.floor((partial_clock * 1000) / (htotal * refresh))
        local new_vfp = target_vtotal - 1280 - PANEL_V_SYNC - PANEL_V_BP
        
        if new_vfp >= 2 then
            gamescope.modegen.set_resolution(mode, 800, 1280)
            gamescope.modegen.set_h_timings(mode, PANEL_H_FP, PANEL_H_SYNC, PANEL_H_BP)
            gamescope.modegen.set_v_timings(mode, new_vfp, PANEL_V_SYNC, PANEL_V_BP)
            mode.clock = partial_clock
            mode.vrefresh = gamescope.modegen.calc_vrefresh(mode)
            
            if debug then
                debug("[oled-120hz] Samsung hybrid mode: " .. refresh .. "Hz clock=" .. partial_clock .. " vfp=" .. new_vfp)
            end
            return mode
        end
    end
    
    -- "hblank" mode: Reduce horizontal blanking to minimize clock increase
    -- This keeps each scanline's timing closer to stock, which may help with
    -- horizontal line offset issues
    if is_samsung and SAMSUNG_MODE == "hblank" then
        -- Reduce H_FP and H_BP proportionally to lower htotal
        -- This allows same refresh at lower clock
        local refresh_ratio = refresh / 90
        local target_clock = math.floor(stock_clock * 1.03)  -- Only 3% clock increase
        
        -- Calculate htotal needed at this clock
        local target_htotal = math.floor((target_clock * 1000) / (base_vtotal * refresh))
        local h_blank_total = target_htotal - 800
        
        -- Distribute blanking: keep sync same, split remainder between FP and BP
        local new_h_fp = math.max(4, math.floor(h_blank_total * 0.3))
        local new_h_bp = math.max(4, h_blank_total - new_h_fp - PANEL_H_SYNC)
        local actual_htotal = 800 + new_h_fp + PANEL_H_SYNC + new_h_bp
        
        if new_h_fp >= 4 and new_h_bp >= 4 then
            gamescope.modegen.set_resolution(mode, 800, 1280)
            gamescope.modegen.set_h_timings(mode, new_h_fp, PANEL_H_SYNC, new_h_bp)
            gamescope.modegen.set_v_timings(mode, PANEL_V_FP, PANEL_V_SYNC, PANEL_V_BP)
            mode.clock = target_clock
            mode.vrefresh = gamescope.modegen.calc_vrefresh(mode)
            
            if debug then
                debug("[oled-120hz] Samsung hblank mode: " .. refresh .. "Hz clock=" .. target_clock .. 
                      " h_fp=" .. new_h_fp .. " h_bp=" .. new_h_bp)
            end
            return mode
        end
    end
    
    -- "round" mode: Round pixel clock to nearest MHz for cleaner PLL lock
    -- Some panels have trouble locking to arbitrary clock frequencies
    if is_samsung and SAMSUNG_MODE == "round" then
        local exact_clock = gamescope.modegen.calc_max_clock(base_mode, refresh)
        -- Round to nearest 1000 kHz (1 MHz)
        local rounded_clock = math.floor((exact_clock + 500) / 1000) * 1000
        
        gamescope.modegen.set_resolution(mode, 800, 1280)
        gamescope.modegen.set_h_timings(mode, PANEL_H_FP, PANEL_H_SYNC, PANEL_H_BP)
        gamescope.modegen.set_v_timings(mode, PANEL_V_FP, PANEL_V_SYNC, PANEL_V_BP)
        mode.clock = rounded_clock
        mode.vrefresh = gamescope.modegen.calc_vrefresh(mode)
        
        if debug then
            debug("[oled-120hz] Samsung round mode: " .. refresh .. "Hz exact_clock=" .. exact_clock .. 
                  " rounded_clock=" .. rounded_clock)
        end
        return mode
    end
    
    -- "syncshift" mode: Shift sync pulse earlier in blanking period
    -- The horizontal offset may be caused by sync-to-data timing mismatch
    if is_samsung and SAMSUNG_MODE == "syncshift" then
        local exact_clock = gamescope.modegen.calc_max_clock(base_mode, refresh)
        local rounded_clock = math.floor((exact_clock + 500) / 1000) * 1000
        
        -- Shift sync earlier: reduce front porch, increase back porch
        local shift = math.min(4, math.floor(PANEL_H_FP / 2))
        local new_h_fp = PANEL_H_FP - shift
        local new_h_bp = PANEL_H_BP + shift
        
        gamescope.modegen.set_resolution(mode, 800, 1280)
        gamescope.modegen.set_h_timings(mode, new_h_fp, PANEL_H_SYNC, new_h_bp)
        gamescope.modegen.set_v_timings(mode, PANEL_V_FP, PANEL_V_SYNC, PANEL_V_BP)
        mode.clock = rounded_clock
        mode.vrefresh = gamescope.modegen.calc_vrefresh(mode)
        
        if debug then
            debug("[oled-120hz] Samsung syncshift mode: " .. refresh .. "Hz h_fp=" .. new_h_fp .. 
                  " h_bp=" .. new_h_bp .. " clock=" .. rounded_clock)
        end
        return mode
    end
    
    -- "even" mode: Force even htotal (some DDICs have bugs with odd line widths)
    if is_samsung and SAMSUNG_MODE == "even" then
        local htotal = 800 + PANEL_H_FP + PANEL_H_SYNC + PANEL_H_BP
        local vtotal = 1280 + PANEL_V_FP + PANEL_V_SYNC + PANEL_V_BP
        
        -- If htotal is odd, add 1 pixel to back porch
        local adj_h_bp = PANEL_H_BP
        if htotal % 2 == 1 then
            adj_h_bp = PANEL_H_BP + 1
            htotal = htotal + 1
        end
        
        local exact_clock = math.floor((htotal * vtotal * refresh) / 1000)
        local rounded_clock = math.floor((exact_clock + 500) / 1000) * 1000
        
        gamescope.modegen.set_resolution(mode, 800, 1280)
        gamescope.modegen.set_h_timings(mode, PANEL_H_FP, PANEL_H_SYNC, adj_h_bp)
        gamescope.modegen.set_v_timings(mode, PANEL_V_FP, PANEL_V_SYNC, PANEL_V_BP)
        mode.clock = rounded_clock
        mode.vrefresh = gamescope.modegen.calc_vrefresh(mode)
        
        if debug then
            debug("[oled-120hz] Samsung even mode: " .. refresh .. "Hz htotal=" .. htotal .. 
                  " (even) clock=" .. rounded_clock)
        end
        return mode
    end
    
    -- "lowclock" mode: Very conservative - cap at 94Hz with minimal clock increase
    -- Some Samsung DDICs can only handle a ~4-5% clock increase cleanly
    if is_samsung and SAMSUNG_MODE == "lowclock" then
        local htotal = 800 + PANEL_H_FP + PANEL_H_SYNC + PANEL_H_BP
        local vtotal = 1280 + PANEL_V_FP + PANEL_V_SYNC + PANEL_V_BP
        local stock_clock = math.floor((htotal * vtotal * 90) / 1000)
        
        -- Cap effective refresh at 94Hz regardless of what was requested
        local effective_refresh = math.min(refresh, 94)
        
        -- Only allow 4% clock increase max
        local max_clock = math.floor(stock_clock * 1.04)
        local target_clock = math.floor((htotal * vtotal * effective_refresh) / 1000)
        local final_clock = math.min(target_clock, max_clock)
        
        -- Round to nearest MHz
        final_clock = math.floor((final_clock + 500) / 1000) * 1000
        
        gamescope.modegen.set_resolution(mode, 800, 1280)
        gamescope.modegen.set_h_timings(mode, PANEL_H_FP, PANEL_H_SYNC, PANEL_H_BP)
        gamescope.modegen.set_v_timings(mode, PANEL_V_FP, PANEL_V_SYNC, PANEL_V_BP)
        mode.clock = final_clock
        mode.vrefresh = gamescope.modegen.calc_vrefresh(mode)
        
        if debug then
            debug("[oled-120hz] Samsung lowclock mode: requested=" .. refresh .. "Hz effective=" .. 
                  effective_refresh .. "Hz clock=" .. final_clock .. " (max " .. max_clock .. ")")
        end
        return mode
    end
    
    -- "cvtrb" mode: CVT Reduced Blanking v2 style timings
    -- Modern panels often expect specific blanking ratios from VESA CVT-RB2
    if is_samsung and SAMSUNG_MODE == "cvtrb" then
        -- CVT-RB2 uses fixed blanking values:
        -- H_BLANK = 80 pixels (H_FP=8, H_SYNC=32, H_BP=40)
        -- V_BLANK = 45 lines minimum
        local cvt_h_fp = 8
        local cvt_h_sync = 32
        local cvt_h_bp = 40
        local cvt_htotal = 800 + cvt_h_fp + cvt_h_sync + cvt_h_bp  -- 880
        
        -- Keep vertical blanking from panel (it's already minimal)
        local vtotal = 1280 + PANEL_V_FP + PANEL_V_SYNC + PANEL_V_BP
        
        local target_clock = math.floor((cvt_htotal * vtotal * refresh) / 1000)
        -- Round to nearest 250kHz (CVT-RB2 spec)
        local rounded_clock = math.floor((target_clock + 125) / 250) * 250
        
        gamescope.modegen.set_resolution(mode, 800, 1280)
        gamescope.modegen.set_h_timings(mode, cvt_h_fp, cvt_h_sync, cvt_h_bp)
        gamescope.modegen.set_v_timings(mode, PANEL_V_FP, PANEL_V_SYNC, PANEL_V_BP)
        mode.clock = rounded_clock
        mode.vrefresh = gamescope.modegen.calc_vrefresh(mode)
        
        if debug then
            debug("[oled-120hz] Samsung cvtrb mode: " .. refresh .. "Hz htotal=" .. cvt_htotal .. 
                  " clock=" .. rounded_clock .. " (CVT-RB2 style)")
        end
        return mode
    end

    -- Default "clock" mode: Full clock increase, fixed blanking (original approach)
    if debug then
        debug("[oled-120hz] Generating " .. refresh .. "Hz mode for $PROFILE_DISPLAY_NAME (clock mode)")
    end
    
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
fi

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
echo "Modegen mode: $SAMSUNG_MODE"
echo "If you see pixelation/aliasing (horizontal line offset), try different modes:"
echo ""
echo "  Recommended first tries:"
echo "  SAMSUNG_MODE=lowclock  - Conservative 94Hz max, 4% clock limit (safest)"
echo "  SAMSUNG_MODE=round     - Round clock to nearest MHz (cleaner PLL lock)"
echo "  SAMSUNG_MODE=syncshift - Shift sync pulse timing (fixes some offset issues)"
echo ""
echo "  Alternative approaches:"
echo "  SAMSUNG_MODE=even      - Force even htotal (some DDIC bugs)"
echo "  SAMSUNG_MODE=cvtrb     - CVT Reduced Blanking v2 style timings"
echo "  SAMSUNG_MODE=hblank    - Reduce horizontal blanking"
echo "  SAMSUNG_MODE=vfp       - Variable front porch (like ROG Ally)"
echo "  SAMSUNG_MODE=hybrid    - Blend of clock + VFP adjustment"
echo ""
echo "  Other:"
echo "  SAMSUNG_MODE=stock     - Use original gamescope modegen (won't unlock)"
echo "  SAMSUNG_MODE=clock     - Full clock increase (default)"
echo ""
fi
if [[ "$HOME_REFRESH" -eq "$DEFAULT_HOME_REFRESH" ]]; then
echo "Home screen will stay at stock ${DEFAULT_HOME_REFRESH}Hz."
echo "Games can still select up to ${MAX_REFRESH}Hz via the QAM slider."
echo ""
else
echo "Home screen will run at ${HOME_REFRESH}Hz."
echo "If you have issues, reinstall with HOME_REFRESH=${DEFAULT_HOME_REFRESH} (default)."
echo ""
fi
echo "Configuration options (env vars go on the 'bash' side of the pipe):"
echo "  MAX_REFRESH=N   - Max refresh rate for games (default: auto-detected)"
echo "  HOME_REFRESH=N  - Home screen refresh rate (default: ${DEFAULT_HOME_REFRESH})"
echo ""
if [[ "$PANEL_TYPE" == "lcd" ]]; then
echo "Examples:"
echo "  # 65Hz max (conservative)"
echo "  curl -sL .../install.sh | MAX_REFRESH=65 bash"
echo ""
echo "  # 70Hz everywhere including home screen"
echo "  curl -sL .../install.sh | HOME_REFRESH=70 bash"
echo ""
else
echo "Examples:"
echo "  # Max out everything (may have gamma issues on home screen)"
echo "  curl -sL .../install.sh | MAX_REFRESH=120 HOME_REFRESH=120 bash"
echo ""
echo "  # 100Hz home, 120Hz games (experimental middle ground)"
echo "  curl -sL .../install.sh | HOME_REFRESH=100 bash"
echo ""
fi
echo "To uninstall:"
echo "  rm ~/.config/gamescope/scripts/99-user/displays/$SCRIPT_NAME"
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
