# Steam Deck OLED Refresh Rate Unlock

Unlock higher refresh rates on your **Steam Deck OLED**:
- **BOE panels**: Up to **120Hz**
- **Samsung panels**: Up to **~96Hz** (automatically calculated safe max)

This is a pure Lua-based solution that:
- **Survives SteamOS updates** (no binary patching)
- **Auto-detects your panel** (BOE or Samsung) and calculates safe limits
- **Extracts your exact panel timings** for maximum compatibility
- **Easy one-command install and uninstall**

## Requirements

- Steam Deck OLED with **BOE panel** (0x3004) or **Samsung panel** (0x3003)
  - All Limited Edition models have BOE panels
  - Standard OLED models may have either BOE or Samsung
- **SteamOS 3.6 or newer**

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

### Want a lower cap? (Reduces OLED gamma drift / fixes home screen colors)

The SteamOS home screen / library always runs at the **highest** rate the script exposes — it doesn't honor the QAM slider. So if 120Hz makes the home screen colors look off (black crush, gamma shift), lower the cap at install time:

```bash
curl -sL https://raw.githubusercontent.com/2-X/steamdeck-oled-120hz/main/install.sh | MAX_REFRESH=110 bash
```

> **Important:** The `MAX_REFRESH=110` MUST go on the `bash` side of the pipe, not before `curl`. If you write `MAX_REFRESH=110 curl ... | bash` the variable lives in `curl`'s environment and never reaches the install script — it'll silently fall back to 120.

`MAX_REFRESH` accepts any integer from 91 up to your panel's safe max. Common picks:

**BOE panels (safe max: 120Hz):**
- `120` (default) — full panel max
- `110` — best balance for most BOE units
- `100` — very conservative, minimal gamma shift

**Samsung panels (safe max: ~96Hz):**
- Auto-calculated (default) — installer picks the safe max for your panel
- `96` — clean multiples: 96/48/24Hz
- `92` — even more conservative

> **Note:** If you specify a `MAX_REFRESH` above your panel's calculated safe max, the installer will warn you and ask for confirmation.

You can verify the value that actually got installed:
```bash
grep MAX_REFRESH ~/.config/gamescope/scripts/99-user/displays/oled-120hz.lua
```

To change it later: re-run the installer with a different value, or edit that line directly in the installed file and reboot.

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
rm ~/.config/gamescope/scripts/99-user/displays/oled-120hz.lua
sudo reboot
```

## Troubleshooting

### Screen goes black after reboot
1. Hold the **power button for 10 seconds** to force shutdown
2. Boot to **Desktop Mode**: hold **Volume Down + Power**, then select Desktop Mode from the boot menu
3. Open Konsole and run:
   ```bash
   rm ~/.config/gamescope/scripts/99-user/displays/oled-120hz.lua
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
- `01` = LCD (use [SteamDeck-RefreshRateUnlocker](https://github.com/ryanrudolfoba/SteamDeck-RefreshRateUnlocker) instead)

### Is this safe?

**Yes, for both BOE and Samsung panels.** The installer calculates safe limits based on your panel's actual pixel clock:

- **BOE panels** can handle up to ~133Hz theoretically (we cap at 120Hz)
- **Samsung panels** have tighter pixel clock limits (~99MHz), so we calculate the max safe refresh rate from your specific panel's timings — typically around 96-99Hz

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

### Why Lua instead of binary patching?

Previous 120Hz unlocks (like Nyaaori's) patched `/usr/bin/gamescope` directly. This broke with every SteamOS update and caused DirectX errors on newer versions. The Lua approach uses gamescope's official scripting system and is future-proof.

## Technical Details

The unlock works by:
1. Detecting your panel type (BOE or Samsung) via EDID
2. Extracting your panel's actual timing values and pixel clock from `modetest`
3. **Calculating the safe max refresh rate** based on pixel clock headroom
4. Extending the `dynamic_refresh_rates` table to include 91 up to the safe max
5. Replacing the panel profile's `dynamic_modegen` function with a variable-clock version
6. Using `calc_max_clock()` to compute the correct pixel clock for each refresh rate

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
