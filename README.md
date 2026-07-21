# Fix Steam Shortcut Icons

Fix broken or blank Steam desktop shortcut icons on Windows.

Steam shortcuts sometimes point to `.ico` files that no longer exist, leaving games with a generic white/blank icon. This PowerShell script scans your Desktop Steam shortcuts, downloads the original icons from Steam's CDN, patches the shortcut files, and refreshes the Windows icon cache.

## Features

- Finds Steam `.url` desktop shortcuts automatically
- Detects missing Steam game icon files
- Downloads original `.ico` files from Steam's CDN
- Updates each shortcut's `IconFile` entry
- Clears the Windows icon cache and restarts Explorer
- Shows exactly what will be changed before doing it

## Requirements

- Windows
- Steam installed
- PowerShell 5+ or PowerShell 7+
- Internet connection

## Quick start

1. Download [`Fix-SteamShortcutIcons.ps1`](./Fix-SteamShortcutIcons.ps1).
2. Right-click the file and choose **Run with PowerShell**.
3. Review the repair plan.
4. Type `Y` to fix missing icons.

Or run it from PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\Fix-SteamShortcutIcons.ps1
```

## What it changes

The script only edits Steam desktop shortcut `.url` files that have missing icon files. It saves replacement icons to:

```text
<Steam folder>\steam\games
```

Then it refreshes Windows icons by restarting Explorer and clearing the icon cache.

## Is it safe?

The script asks for confirmation before making changes. It does not modify game files, Steam libraries, or your Steam account. It only repairs desktop shortcut icon paths.

If you are unsure, open the script in a text editor first. It is small and readable on purpose.

## Troubleshooting

### PowerShell blocks the script

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\Fix-SteamShortcutIcons.ps1
```

### Some icons still look broken

Restart Windows, or delete and recreate the Steam desktop shortcut for that game.

### Steam is installed in a custom location

The script checks the Steam registry keys first, then common install folders. If Steam cannot be found, open an issue with your Steam install path.

## Keywords

Steam shortcut icon fix, Steam broken icons, Steam desktop icons blank, Windows icon cache, Steam `.url` shortcuts, PowerShell Steam repair.

## License

MIT License. See [LICENSE](./LICENSE).
