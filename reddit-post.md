# Reddit Post for r/SteamDeck

---

**Title:** 120Hz Unlock for Steam Deck OLED (BOE panels) - Survives SteamOS Updates

---

Finally got 120Hz working on my OLED Limited Edition and it survives SteamOS updates (no binary patching).

**Install** (Desktop Mode → Konsole):
```
curl -sL https://raw.githubusercontent.com/2-X/steamdeck-oled-120hz/main/install.sh | bash
```

Reboot, then the refresh rate slider goes to 120Hz.

**Requirements:**
- BOE OLED panel only (all Limited Editions have BOE, some standard OLEDs too)
- Installer auto-detects your panel and blocks Samsung panels (hardware limited to ~99Hz)

**Uninstall:**
```
rm ~/.config/gamescope/scripts/99-user/displays/oled-120hz.lua && sudo reboot
```

If screen goes black: hold power 10 sec, boot Desktop Mode, run the uninstall command.

GitHub: https://github.com/2-X/steamdeck-oled-120hz
