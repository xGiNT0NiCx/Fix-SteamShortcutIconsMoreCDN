# Fix Steam Shortcut Icons (Plus)

Fix broken or blank Steam desktop shortcut icons on Windows.

> This is a fork of [RNZ01/Fix-SteamShortcutIcons](https://github.com/RNZ01/Fix-SteamShortcutIcons).
> It contains the original script **and** an extended version, `Fix-SteamShortcutIcons-Plus.ps1`, that also fixes shortcuts where the original gets a **404 Not Found** from Steam's CDN.

Steam shortcuts sometimes point to `.ico` files that no longer exist, leaving games with a generic white/blank icon. These PowerShell scripts scan your Desktop Steam shortcuts, get the right icon back, patch the shortcut files and refresh the Windows icon cache.

## Which script should I use?

| | `Fix-SteamShortcutIcons.ps1` (original) | `Fix-SteamShortcutIcons-Plus.ps1` |
|---|---|---|
| Icon source | 1 Steam CDN address | 7 Steam CDN addresses (Cloudflare, Akamai, Fastly, old and new paths) |
| When the CDN returns 404 | Shortcut stays broken | Falls back to the icon inside the game's own `.exe` |
| Checks the download is a real `.ico` | Size check only | Checks the `.ico` file header |
| Games on other drives / Steam libraries | – | Reads `libraryfolders.vdf` and `appmanifest_*.acf` to find them |
| Works in PowerShell ISE | Crashes at "Press any key" | Yes |

**Short answer:** use the Plus version. If you only want the original behaviour, use the original.

## Why do some icons give 404?

The shortcut stores a hash of the icon (e.g. `IconFile=...\steam\games\5236dcc5....ico`). The scripts download the icon from Steam's CDN using that hash. For some games – in my case Battlefield 6 and HELLDIVERS 2 – the CDN has no file for the stored hash, most likely because the icon changed with a game update. Trying other Steam CDN mirrors may help, but they all serve the same storage, so often none of them has it. That's what the `.exe` fallback is for.

## How the Plus version works

1. Finds Steam via the registry and reads all your Steam library folders.
2. Scans your Desktop and the Public Desktop for Steam `.url` shortcuts.
3. Lists every shortcut whose icon file is missing and asks for confirmation (`Y`).
4. For each broken shortcut:
   - tries 7 Steam CDN addresses one after another and keeps the first valid `.ico`
   - if none has it: looks up the game's install folder (any drive) and uses the icon from the game's `.exe`. Anti-cheat, launcher helpers, installers, redistributables and crash handlers are skipped; the biggest remaining `.exe` is used. The chosen `.exe` is shown in the output.
5. Updates the `IconFile=` / `IconIndex=` lines of the shortcut.
6. Clears the Windows icon cache and restarts Explorer.

## Requirements

- Windows
- Steam installed
- PowerShell 5.1 (built into Windows) or PowerShell 7+
- Internet connection (not needed for the `.exe` fallback)

## Quick start

1. Download [`Fix-SteamShortcutIcons-Plus.ps1`](./Fix-SteamShortcutIcons-Plus.ps1).
2. Right-click the file and choose **Run with PowerShell**.
3. Review the list of shortcuts that will be repaired.
4. Type `Y` to fix them – anything else cancels without changing anything.

Or run it from PowerShell in the folder where the script is:

```powershell
powershell -ExecutionPolicy Bypass -File .\Fix-SteamShortcutIcons-Plus.ps1
```

`-ExecutionPolicy Bypass` only applies to this one PowerShell process; your system-wide policy is not changed. Alternatively: right-click the `.ps1` → **Properties** → tick **Unblock**, then run it normally.

## What it changes

- Only Steam desktop shortcuts (`.url` with `steam://rungameid/...`) whose icon file is missing. Healthy shortcuts and non-Steam shortcuts are not touched.
- Downloaded icons are saved to `<Steam folder>\steam\games`.
- With the `.exe` fallback, nothing is downloaded – the shortcut just points to the game's `.exe` for its icon.
- Windows icon cache is cleared and Explorer is restarted (taskbar and desktop disappear for a second).

## Is it safe?

- Asks for confirmation before changing anything.
- No admin rights needed, nothing installed, no scheduled tasks or autostart entries.
- Only network access: downloading `.ico` files from Steam's own CDN domains (`*.steamstatic.com`, `steamcdn-a.akamaihd.net`).
- Does not touch game files, Steam libraries or your Steam account.

As with any script from the internet: **open it in a text editor and read it before running it.** It's plain PowerShell, no obfuscation, no downloaded code.

## Troubleshooting

### PowerShell blocks the script
Use the `-ExecutionPolicy Bypass` command above, or unblock the file via **Properties**.

### "No CDN had the icon and the game .exe was not found"
The game is probably not installed (anymore). Install it, or delete the shortcut.

### The fallback picked the wrong `.exe`
Right-click the shortcut → **Properties** → **Web Document** tab → **Change Icon…** and choose the right `.exe` manually. Feel free to open an issue with the game name.

### Icon is broken again after moving a game to another drive
Shortcuts fixed via the `.exe` fallback point to the game folder. Just run the script again after moving the game.

### Some icons still look blank
Sign out of Windows and back in (or reboot). Or delete the shortcut and recreate it in Steam: right-click the game → **Manage** → **Add desktop shortcut**.

### Shortcuts on the Public Desktop fail
`C:\Users\Public\Desktop` needs admin rights to modify. Run PowerShell as administrator if you need those fixed.

## Credits

Original script and idea: [RNZ01/Fix-SteamShortcutIcons](https://github.com/RNZ01/Fix-SteamShortcutIcons).
The Plus version adds CDN fallbacks, `.ico` validation, the game `.exe` fallback and a few small fixes.

## License

MIT License. See [LICENSE](./LICENSE).

## Keywords

Steam shortcut icon fix, Steam broken icons, Steam desktop icons blank, Steam icon 404, Windows icon cache, Steam `.url` shortcuts, PowerShell Steam repair.
