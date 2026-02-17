# HOL2 SaveGuard v1.0

**Free automatic save backup & restore tool for High On Life 2**

Tired of losing progress to softlocks and corrupted saves? SaveGuard watches your save files and automatically creates timestamped backups so you can always roll back.

---

## Quick Start (30 seconds)

1. **Extract** this folder anywhere (Desktop, Documents, wherever)
2. **Double-click** `Launch_SaveGuard.bat`
3. **Press 1** to start monitoring
4. **Play the game** — backups happen automatically

That's it. Leave the window open while you play.

---

## Features

- **Automatic backups** every 10 minutes (configurable 1-60 min)
- **Change detection** — only backs up when saves actually change (saves disk space)
- **One-click restore** — browse backups and restore with confirmation
- **Safety net** — automatically backs up current saves before any restore
- **All save slots** — monitors Slot0, Slot1, Slot2, and Profile.sav
- **Locked file handling** — retries if the game is mid-save
- **Configurable** — settings saved to config.ini
- **Portable** — no install needed, no admin rights needed
- **Lightweight** — uses virtually no CPU or RAM

## Menu Options

| Option | What it does |
|--------|-------------|
| **1 - Start Monitoring** | Begins automatic backup loop |
| **2 - Backup Now** | Creates an immediate snapshot |
| **3 - Restore a Backup** | Browse and restore a previous save |
| **4 - Settings** | Change interval, slots, retention, paths |
| **5 - Open Backup Folder** | Opens your backups in Explorer |
| **6 - Set Save Folder** | Manually set save location if auto-detect fails |

## Settings (Press 4 in main menu)

- **Backup interval** — How often to check for changes (default: 10 min)
- **Save slot** — All, Slot0, Slot1, or Slot2
- **Include Profile** — Also back up Profile.sav (recommended)
- **Max backups** — Limit total snapshots (0 = unlimited)
- **Max age** — Auto-delete backups older than X days (0 = keep forever)
- **Backup folder** — Where backups are stored

Settings are saved to `config.ini` in the same folder.

## Auto-Start on Login (Optional)

Double-click `Setup_AutoStart.bat` and choose option 1. SaveGuard will launch minimized every time you log in.

## How Restoring Works

1. **Close High On Life 2 completely**
2. Open SaveGuard and press **3**
3. Pick a backup from the list
4. Type **YES** to confirm
5. Your current saves are backed up first (safety net), then the selected backup is restored
6. Launch the game

## Where Are My Saves?

High On Life 2 saves are typically in:
```
%LocalAppData%\HighOnLife2\Saved\SaveGames\
```
SaveGuard auto-detects this. If it can't find them, use option 6 to set the path manually.

## FAQ

**Q: Does this affect game performance?**
A: No. It checks file timestamps every 10 minutes and copies small files. Negligible impact.

**Q: How much disk space does this use?**
A: Save files are tiny (usually under 1 MB each). Even 1000 backups would use well under 1 GB. You can set retention limits in Settings.

**Q: Can I move the SaveGuard folder?**
A: Yes. It's fully portable. Just move the whole folder.

**Q: Windows Defender / antivirus flagged it?**
A: Some antivirus tools flag unsigned PowerShell scripts. This is a false positive. The script only reads and copies your save files — you can read the full source code in `HOL2_SaveGuard.ps1`.

**Q: I'm on Steam Deck / Linux?**
A: This is Windows-only. For Steam Deck, the save path and scripting would be different.

---

## Files in This Package

| File | Purpose |
|------|---------|
| `Launch_SaveGuard.bat` | Double-click this to run |
| `HOL2_SaveGuard.ps1` | Main script (PowerShell) |
| `Setup_AutoStart.bat` | Optional: add/remove auto-start on login |
| `config.ini` | Settings (created on first run) |
| `README.md` | This file |
| `LICENSE.txt` | MIT License |

---

## License

MIT License — Free to use, share, modify. No warranty.
See LICENSE.txt for full text.

---

**Made with care for the High On Life 2 community.**
If this saved your playthrough, pass it along!
