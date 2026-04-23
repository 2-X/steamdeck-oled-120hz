# Steam Deck OLED 120Hz Unlock

Unlock 120Hz refresh rate on your **Steam Deck OLED** with the **BOE panel** (including Limited Edition models).

This is a pure Lua-based solution that:
- **Survives SteamOS updates** (no binary patching)
- **Auto-detects your panel** and refuses to run on unsupported hardware
- **Extracts your exact panel timings** for maximum compatibility
- **Easy one-command install and uninstall**

## Requirements

- Steam Deck OLED with **BOE panel** (product code 0x3004)
  - All Limited Edition models have BOE panels
  - Some standard OLED models also have BOE panels
- **SteamOS 3.6 or newer**

> **Samsung panel owners:** Your panel (0x3003) has hardware limitations above ~99Hz. This unlock will detect Samsung panels and refuse to install to protect your display.

## Quick Install

Open **Desktop Mode** → **Konsole** and run:

```bash
curl -sL https://raw.githubusercontent.com/2-X/steamdeck-oled-120hz/main/install.sh | bash
```

The installer will:
1. Verify you're on SteamOS 3.6+
2. Detect your panel type (BOE/Samsung/LCD)
3. Extract your panel's timing values
4. Install the unlock script
5. Prompt you to reboot

## Manual Install

If you prefer to review before running:

```bash
git clone https://github.com/2-X/steamdeck-oled-120hz.git
cd steamdeck-oled-120hz
./install.sh
```

## After Installation

1. **Reboot** your Steam Deck (required for gamescope to load the script)
2. Switch to **Gaming Mode**
3. Press **...** (Quick Access Menu) → **Performance** tab
4. The **Refresh Rate** slider should now go up to **120Hz**

## Verify It's Working

### In Gaming Mode
Check the Performance overlay (QAM → Performance → show overlay) - it should show your current refresh rate.

### In Desktop Mode
Run this command:
```bash
xrandr | grep eDP
```
You should see 120Hz modes listed.

### UFO Test
Visit https://www.testufo.com/framerates in a browser to visually confirm 120Hz.

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
2. Turn on and boot to **Desktop Mode**
3. Open Konsole and run:
   ```bash
   rm ~/.config/gamescope/scripts/99-user/displays/oled-120hz.lua
   ```
4. Reboot - your Deck will be back to normal

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
xxd -p -l 12 /sys/class/drm/card1-eDP-1/edid | tail -c 5 | head -c 2
```
- `04` = BOE OLED (supported)
- `03` = Samsung OLED (not supported - hardware limited)
- `01` = LCD (use [SteamDeck-RefreshRateUnlocker](https://github.com/ryanrudolfoba/SteamDeck-RefreshRateUnlocker) instead)

### Is this safe?

Yes, for BOE panels. The BOE OLED panel is rated for higher refresh rates (theoretical max ~133Hz based on pixel clock capabilities). Samsung panels have tighter tolerances, which is why we block installation on those.

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
1. Extending the `dynamic_refresh_rates` table to include 91-120Hz
2. Replacing the BOE profile's `dynamic_modegen` function with a variable-clock version
3. Using `calc_max_clock()` to compute the correct pixel clock for each refresh rate

Stock gamescope uses a fixed-clock + variable-front-porch approach which mathematically caps at ~90Hz. Our approach adjusts the pixel clock directly (same technique used by the Zotac and LCD profiles).

## Credits

- Research and development by the Steam Deck modding community
- Built on gamescope's Lua scripting system by Valve
- Inspired by [Nyaaori's original 120Hz patch](https://git.spec.cat/Nyaaori/deck-refresh-rate-expander) and [ryanrudolfoba's LCD unlock](https://github.com/ryanrudolfoba/SteamDeck-RefreshRateUnlocker)

## License

MIT License - see [LICENSE](LICENSE)
