# Reddit Post for r/SteamDeck

---

**Title:** 120Hz Unlock for Steam Deck OLED (BOE panels) - Survives SteamOS Updates

---

Finally got 120Hz working on my OLED Limited Edition and it survives SteamOS updates (no binary patching).

**Install** (Desktop Mode → Konsole):
```
curl -sL https://raw.githubusercontent.com/2-X/steamdeck-oled-120hz/main/install.sh | bash
```

Then run `sudo reboot`.

**After reboot:**
1. Press the **...** button (below right trackpad) to open Quick Access Menu
2. Go to Performance tab (battery icon)
3. Turn on Performance Overlay (set to 1+) so you can see your refresh rate
4. Scroll down - Refresh Rate slider now goes to 120Hz

**Requirements:**
- BOE OLED panel only (all Limited Editions, some standard OLEDs)
- Installer auto-detects and blocks Samsung panels (they're hardware limited to ~99Hz)

**Uninstall:**
```
rm ~/.config/gamescope/scripts/99-user/displays/oled-120hz.lua
sudo reboot
```

If screen goes black: hold power 10 sec, boot Desktop Mode (Volume Down + Power at startup), delete the script, reboot.

GitHub: https://github.com/2-X/steamdeck-oled-120hz
