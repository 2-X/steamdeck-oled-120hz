# Steam Deck Refresh Rate Unlock

Unlock higher refresh rates on your **Steam Deck**:
- **OLED (BOE panel)**: Up to **120Hz**
- **OLED (Samsung panel)**: Up to **~96Hz** (automatically calculated safe max)
- **LCD**: Up to **70Hz**

This is a pure Lua-based solution that:
- **Survives SteamOS updates** (no binary patching required)
- **Auto-detects your panel** (BOE, Samsung, or LCD) and calculates safe limits
- **Extracts your exact panel timings** for maximum compatibility (OLED)
- **No crashing issues** like the old binary patching method had
- **Easy one-command install and uninstall**

## Requirements

- Steam Deck with one of:
  - **BOE OLED panel** (0x3004) — up to 120Hz
  - **Samsung OLED panel** (0x3003) — up to ~96Hz  
  - **LCD panel** (0x3001) — up to 70Hz
- **SteamOS 3.6 or newer**

**OLED model guide:**
- **Limited Edition (orange thumbsticks, translucent shell)**: Always has BOE panel
- **Limited Edition (white)**: Has Samsung panel
- **Standard OLED**: May have either BOE or Samsung (check with command below)

## Quick Install

Open **Desktop Mode** → **Konsole** and run:

```bash
curl -sL https://raw.githubusercontent.com/2-X/steamdeck-oled-120hz/main/install.sh | bash
```

The installer will:
1. Verify you're on SteamOS 3.6+
2. Detect your panel type (BOE/Samsung/LCD)
3. Extract your panel's timing values and pixel clock
4. **Calculate the safe max refresh rate for your specific panel**
5. Install the unlock script
6. Prompt you to reboot

For **Samsung panels**, the installer automatically calculates a safe max (~96Hz) based on your panel's pixel clock with 10% headroom, giving you clean frame pacing multiples (96/48/24Hz) instead of the stock 90/45/22.5Hz.

### Want better color accuracy?

There's slight gamma shift above ~110Hz. For best balance:

```bash
curl -sL https://raw.githubusercontent.com/2-X/steamdeck-oled-120hz/main/install.sh | MAX_REFRESH=110 bash
```

### Control home screen refresh rate separately

By default, the home screen stays at 90Hz while games can use up to your max refresh rate. This avoids gamma issues on the UI while still giving you full speed in games.

To run the home screen at a higher rate:

```bash
# 100Hz home, 120Hz games (experimental middle ground)
curl -sL https://raw.githubusercontent.com/2-X/steamdeck-oled-120hz/main/install.sh | HOME_REFRESH=100 bash

# Everything at 120Hz (may have gamma issues on home screen)
curl -sL https://raw.githubusercontent.com/2-X/steamdeck-oled-120hz/main/install.sh | HOME_REFRESH=120 bash
```

You can combine both options:

```bash
# 100Hz home, 110Hz max for games
curl -sL https://raw.githubusercontent.com/2-X/steamdeck-oled-120hz/main/install.sh | MAX_REFRESH=110 HOME_REFRESH=100 bash
```

> **Important:** Environment variables MUST go on the `bash` side of the pipe, not before `curl`. If you write `MAX_REFRESH=110 curl ... | bash` the variable lives in `curl`'s environment and never reaches the install script.

### Configuration options

| Variable | Default | Description |
|----------|---------|-------------|
| `MAX_REFRESH` | Auto-detected | Maximum refresh rate for games (91 to panel max) |
| `HOME_REFRESH` | `90` | Home screen / UI refresh rate (45 to MAX_REFRESH) |

**BOE panels (safe max: 120Hz):**
- `MAX_REFRESH=120` (default) — full panel max
- `MAX_REFRESH=110` — **recommended** best balance for color accuracy vs refresh rate

**Samsung panels (safe max: ~96Hz):**
- Auto-calculated (default) — installer picks the safe max for your panel

> **Note:** If you specify a `MAX_REFRESH` above your panel's calculated safe max, the installer will warn you and ask for confirmation.

You can verify the values that got installed:
```bash
# For OLED:
grep -E 'MAX_REFRESH|HOME_REFRESH' ~/.config/gamescope/scripts/99-user/displays/oled-120hz.lua
# For LCD:
grep -E 'MAX_REFRESH|HOME_REFRESH' ~/.config/gamescope/scripts/99-user/displays/lcd-70hz.lua
```

To change settings later: re-run the installer with different values, or edit the file directly and reboot.

## Manual Install

If you prefer to review before running:

```bash
git clone https://github.com/2-X/steamdeck-oled-120hz.git
cd steamdeck-oled-120hz
./install.sh
```

## After Installation

1. Run `sudo reboot`
2. After reboot, you'll be in **Gaming Mode**
3. Press the **Quick Access button** (the **...** button below the right trackpad)
4. Go to the **Performance** tab (battery icon)
5. Set **Performance Overlay Level** to at least **1** to see your FPS/refresh rate
6. Scroll down to the **Refresh Rate** slider - it should now go up to **120Hz**

## Uninstall

### Option 1: Run the uninstaller
```bash
curl -sL https://raw.githubusercontent.com/2-X/steamdeck-oled-120hz/main/uninstall.sh | bash
```

### Option 2: Manual removal
```bash
# For OLED:
rm ~/.config/gamescope/scripts/99-user/displays/oled-120hz.lua
# For LCD:
rm ~/.config/gamescope/scripts/99-user/displays/lcd-70hz.lua
sudo reboot
```

## Troubleshooting

### Screen goes black after reboot
1. Hold the **power button for 10 seconds** to force shutdown
2. Boot to **Desktop Mode**: hold **Volume Down + Power**, then select Desktop Mode from the boot menu
3. Open Konsole and run:
   ```bash
   # For OLED:
   rm ~/.config/gamescope/scripts/99-user/displays/oled-120hz.lua
   # For LCD:
   rm ~/.config/gamescope/scripts/99-user/displays/lcd-70hz.lua
   ```
4. Run `sudo reboot` - your Deck will be back to normal

### Slider still maxes at 90Hz
- Make sure you **rebooted** after installation (switching modes isn't enough)
- Verify the script exists:
  ```bash
  ls -la ~/.config/gamescope/scripts/99-user/displays/
  ```
- Check gamescope logs for errors:
  ```bash
  journalctl --user -u gamescope* | grep oled-120hz
  ```

### "modetest not found" during install
The installer will fall back to xrandr automatically. If both fail, you may need to install libdrm:
```bash
sudo pacman -S libdrm
```

### Games crash or have DirectX errors
This shouldn't happen with the Lua approach (unlike old binary patches), but if it does:
1. Uninstall the script
2. Report the issue with your SteamOS version and game name

## FAQ

### Which panel do I have?

Run this in Desktop Mode → Konsole:
```bash
edid=$(xxd -p -l 12 /sys/class/drm/card*-eDP-1/edid | tr -d '\n'); echo ${edid:20:2}
```
- `04` = BOE OLED (supported — up to 120Hz)
- `03` = Samsung OLED (supported — up to ~96Hz)
- `01` = LCD (supported — up to 70Hz)

**Quick guide by model:**
- **LCD Steam Deck**: LCD panel (70Hz)
- **Limited Edition OLED (orange thumbsticks, translucent shell)**: BOE panel (120Hz)
- **Limited Edition OLED (white)**: Samsung panel (~96Hz)
- **Standard OLED**: Run the command above to check

### Is this safe?

**Yes, for all supported panels.** The installer calculates safe limits based on your panel's actual capabilities:

- **BOE OLED panels** can handle up to ~133Hz theoretically (we cap at 120Hz)
- **Samsung OLED panels** have tighter pixel clock limits (~99MHz), so we calculate the max safe refresh rate from your specific panel's timings — typically around 96-99Hz
- **LCD panels** are capped at 70Hz, which is a well-tested safe limit

The Samsung calculation uses your panel's 90Hz pixel clock plus 10% headroom, capped at 99Hz absolute maximum. This gives you the benefit of cleaner frame pacing multiples (96/48/24Hz vs 90/45/22.5Hz) without exceeding hardware limits.

### Why would Samsung users want this?

Even though Samsung panels can't reach 120Hz, going from 90Hz to 96Hz gives you:
- **Clean frame pacing multiples**: 96Hz halves to 48Hz, quarters to 24Hz (all integers)
- **vs stock 90Hz**: halves to 45Hz (odd), quarters to 22.5Hz (not even an integer)
- This matters for games that sync to half or quarter refresh rates

### Will this void my warranty?

This is a software modification that can be completely removed. It doesn't modify any system files or require disabling read-only mode.

### Will SteamOS updates break this?

No. Unlike binary patches, this Lua script lives in your user config directory (`~/.config/gamescope/`) which SteamOS updates don't touch.

### Can I use this with Decky Loader?

Yes, they're independent. This script runs at the gamescope level, not through Decky.

### What about battery life?

Higher refresh rate = more power draw. Expect roughly **10-15% less playtime** at 120Hz compared to 90Hz, depending on the game. You can always lower the refresh rate via the QAM slider to save battery when needed.

As for battery health/lifespan, the extra charge cycles from shorter playtime are negligible. Just don't leave your Deck at 100% charge for extended periods.

### Does VRR/frame pacing still work?

Yes. Gamescope's Variable Refresh Rate logic handles this automatically. The script only extends the available refresh rates (adding 91-120Hz to the existing 45-90Hz range) — it doesn't interfere with the refresh rate selection logic.

For example:
- 60 FPS limiter → gamescope can pick 60Hz (stock) or 120Hz (extended)
- 40 FPS limiter → gamescope uses 40Hz or 80Hz (stock), or 120Hz (extended)

The smart refresh selection that finds clean multiples of your FPS is handled by gamescope's core logic.

### Why does Desktop Mode stay at 90Hz?

Desktop Mode displays at whatever modes the panel natively advertises via EDID, which for the BOE OLED is 90Hz max. The unlock only works in Gaming Mode where gamescope can use the Lua scripting system.

### Can I use this on Windows?

No. Windows on Steam Deck doesn't use gamescope, so this Lua script won't work. You'd need a different approach like Custom Resolution Utility (CRU) or a custom EDID override. The panel hardware supports higher refresh rates, so it should be theoretically possible.

### Why Lua instead of binary patching?

Previous 120Hz unlocks (like Nyaaori's) patched `/usr/bin/gamescope` directly. This broke with every SteamOS update and caused DirectX errors on newer versions. The Lua approach uses gamescope's official scripting system and is future-proof.

## Technical Details

The 90Hz "rating" is a software limit Valve set, not a hardware limit. The BOE OLED panel physically supports higher refresh rates — its pixel clock can handle up to ~133Hz theoretically.

Valve likely capped it at 90Hz because:
1. The Samsung OLED variant is hardware-limited to ~99Hz and they wanted consistency
2. Battery life concerns
3. Slight gamma shift above ~110Hz on OLED

The unlock works by:
1. Detecting your panel type (BOE or Samsung) via EDID
2. Extracting your panel's actual timing values and pixel clock from `modetest`
3. **Calculating the safe max refresh rate** based on pixel clock headroom
4. Extending the `dynamic_refresh_rates` table to include 91 up to the safe max
5. Replacing the panel profile's `dynamic_modegen` function with a variable-clock version
6. Using `calc_max_clock()` to compute the correct pixel clock for each refresh rate

The bandwidth math works out fine: 800×1280×24bpp×120Hz is only ~3 Gbps, well within eDP spec.

### Safe max calculation (Samsung panels)

```
max_clock = stock_90Hz_clock × 1.10  (10% headroom)
safe_refresh = floor(max_clock / (htotal × vtotal))
final_max = min(safe_refresh, 99)  (hard cap at 99Hz)
```

This ensures we never exceed the panel's pixel clock capabilities while giving users the maximum safe refresh rate.

Stock gamescope uses a fixed-clock + variable-front-porch approach which mathematically caps at ~90Hz. Our approach adjusts the pixel clock directly (same technique used by the Zotac and LCD profiles).

## Credits

- Research and development by the Steam Deck modding community
- Built on gamescope's Lua scripting system by Valve
- Inspired by [Nyaaori's original 120Hz patch](https://git.spec.cat/Nyaaori/deck-refresh-rate-expander) and [ryanrudolfoba's LCD unlock](https://github.com/ryanrudolfoba/SteamDeck-RefreshRateUnlocker)

## License

MIT License - see [LICENSE](LICENSE)
