# MoraClean

A maintenance app for macOS that runs entirely on your Mac. It cleans up unneeded files, finds updates for your installed
apps, and installs them one by one or all at once. No account, no subscription, no telemetry, no analytics.

The app is available in **English** and **Turkish**. It follows your macOS language by default; you can pick a
language in **Settings › Language**, or per app in **System Settings › General › Language & Region › Applications**.

## Download and install

1. Download `MoraClean-<version>.zip` from the [Releases](../../releases/latest) page (one universal build for Apple
   Silicon and Intel).
2. Unzip it and move `MoraClean.app` to your **Applications** folder.
3. First launch: the app is not notarized by Apple, so macOS blocks it the first time you open it. Try to open it once,
   then click **Open Anyway** for MoraClean in **System Settings › Privacy & Security**.

You can check the download against the SHA-256 value in the release notes:

```bash
shasum -a 256 MoraClean-<version>.zip
```

## What else you need to install

Cleanup works out of the box. The updater relies on a few other tools for some update sources; install the ones you
need. MoraClean finds them in `/opt/homebrew/bin` (Apple Silicon) or `/usr/local/bin` (Intel).

| Tool | Needed? | What it enables | Without it | How to install |
|---|---|---|---|---|
| [Homebrew](https://brew.sh) | Optional, recommended | Finding and updating apps you installed with Homebrew (`brew upgrade --cask`) | Those apps are only checked if they also have a Sparkle feed or come from the App Store | `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"` |
| [mas](https://github.com/mas-cli/mas) | Optional | Updating Mac App Store apps directly from MoraClean | MoraClean still finds App Store updates, but opens each app's App Store page so you finish the update there | `brew install mas` (needs Homebrew) |

Notes:

- The Homebrew installer asks for your administrator password and installs Apple's Command Line Tools if they are
  missing.
- `mas` recommends macOS 14 or later. To update an app with it, you must be signed in to the App Store with the Apple
  Account that owns the app, and macOS asks for your administrator password.
- Nothing else is required for cleanup, for checking App Store versions, or for Sparkle updates; those use tools built
  into macOS (`ditto`, `tar`, `hdiutil`, `codesign`).
- Apps that were dragged into Applications by hand are not managed by Homebrew, even if Homebrew is installed.

## Features

### Cleanup

| Category | Location | Default |
|---|---|---|
| User caches | `~/Library/Caches` | selected |
| Log files | `~/Library/Logs` | selected |
| Xcode leftovers | DerivedData, DeviceSupport and simulator caches under `~/Library/Developer` | selected |
| Developer caches | `~/.npm/_cacache`, `~/.composer/cache`, `~/.cache/composer`, `~/.gradle/caches`, `~/.yarn/berry/cache`, `~/.cargo/registry/cache` | selected |
| Trash | `~/.Trash` (always deleted permanently) | not selected |
| Installer files | `.dmg .pkg .mpkg .xip` files in `~/Downloads` | not selected |

- Each category opens as an accordion. User caches are grouped by app, with the app's icon and name; you can browse
  any folder as a tree to see what takes up space.
- Scanning only reads. Nothing is deleted until you confirm.
- By default, files are **moved to the Trash**, so you can undo. You can switch to permanent deletion in Settings.
- The app can only delete the **direct children** of the folders above. Any other path is rejected in code.

### Updater

MoraClean scans `/Applications` and `~/Applications`, skipping the system apps that ship with macOS. For each app it looks
for an update source in this order:

1. **Homebrew cask:** if the app was installed with Homebrew, it is updated with `brew upgrade --cask`.
2. **Mac App Store:** the latest version number comes from Apple's public lookup service. If the `mas` command-line tool
   is installed, the app is updated directly. Otherwise the app's App Store page opens.
3. **Sparkle feed:** if the app publishes its own update feed (`SUFeedURL`), the new version is downloaded and installed.

You can update apps one by one, update the selected ones, or update them all. To hide an app from the list, right-click
it and choose *Ignore This App*.

## Permissions and access

MoraClean runs outside the App Sandbox so it can reach cache folders and `/Applications`. This section lists **every**
permission the app asks for or that macOS may ask for, and why.

### macOS permissions

| Permission | When it is requested | Why | If you deny it |
|---|---|---|---|
| **Access to the Downloads folder** | During a cleanup scan; macOS asks the first time | The "Installer files" category lists `.dmg/.pkg/.xip` files in `~/Downloads` | That category stays empty; the others still work |
| **Full Disk Access** (optional) | Never requested unless you grant it; the app only shows a notice | The Trash (`~/.Trash`) and some cache folders that macOS protects cannot be read without it | Those folders are marked "Permission required" and skipped |
| **App Management** | While updating an app, if macOS requires it | macOS may require this permission for programs that modify apps from another developer | That app's update fails |
| **Administrator password** | Only if a Homebrew or `mas` update needs admin rights | Packages that install system-wide require `sudo` | That update fails |

To grant Full Disk Access, add MoraClean under **System Settings › Privacy & Security › Full Disk Access**, then restart
the app.

**About the administrator password:** the password is requested through a standard macOS dialog (`osascript`) and passed
straight to the `sudo` process. MoraClean does not store it, log it, or send it anywhere. The small script that shows the
dialog is written to `~/Library/Application Support/MoraClean/askpass.sh` with permissions that only you can read (0700).

### Network connections

The app only goes online when you click **Scan** or **Update**:

| Destination | Purpose |
|---|---|
| `itunes.apple.com` | Look up the latest version of App Store apps (only bundle identifiers are sent) |
| Each app's own update feed and download URL | Check for and download new versions of apps updated through Sparkle |
| Homebrew's own servers | Through the `brew update` / `brew upgrade` commands (Homebrew's own behavior) |

No usage data, device information or personal data is sent anywhere.

The *Sponsor on GitHub* and *Buy Me a Coffee* links in the app menu and in Settings only open your browser when you
click them.

### File system and other actions

- **Reads:** the folders in the cleanup table, and the `Info.plist` files of apps in `/Applications` and
  `~/Applications`.
- **Deletes or moves to the Trash:** only the direct children of the folders in the cleanup table, and only after you
  confirm. When an app is updated, its old version is moved to the Trash.
- **Writes:** settings (`~/Library/Preferences/works.mora.moraclean.plist`), the `askpass.sh` script above, and a temporary
  folder for downloads (deleted when the job finishes).
- **Quits apps:** if an app being updated through Sparkle is running, MoraClean asks it to quit and reopens it after the
  update.
- **Commands it runs:** `brew`, `mas`, `/usr/bin/ditto`, `/usr/bin/tar`, `/usr/bin/hdiutil`, `/usr/bin/codesign`,
  `/usr/bin/osascript` (only for the password dialog).

### Update safety

Before an update from a Sparkle source is installed:

1. If the app publishes an EdDSA key (`SUPublicEDKey`), the downloaded file's signature is verified. If the signature is
   missing or invalid, installation stops.
2. The new version's code signature is checked with `codesign --verify --deep --strict`.
3. The new version's developer identity (Team ID) must match the installed version.
4. If any step fails, the old version stays in place.

## Building from source

Requirements: macOS 14 Sonoma or later, Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project MoraClean.xcodeproj -scheme MoraClean -configuration Release -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Release/MoraClean.app
```

Tests:

```bash
xcodebuild -project MoraClean.xcodeproj -scheme MoraClean -derivedDataPath build/DerivedData test
```

## Project structure

```
MoraClean/
  App/       App entry point, sidebar, settings
  Core/      Command runner, version comparison, formatting
  Cleaner/   Cleanup categories, scan/delete engine, UI
  Updater/   App inventory, Homebrew / App Store / Sparkle sources, installer, UI
MoraCleanTests/
tools/make-icon.swift   Generates the app icon (geometric drawing)
```

## Support

MoraClean is free and open source. If it saves you time, you can support its development:

- [GitHub Sponsors](https://github.com/sponsors/ozanmora)
- [Buy Me a Coffee](https://buymeacoffee.com/ozanmora)

## License

[MIT](LICENSE) © 2026 Ozan Mora

## Trademarks

MoraClean is an independent project. It is not affiliated with, endorsed by, or sponsored by any company or project
mentioned here. Apple, macOS, Mac App Store and Xcode are trademarks of Apple Inc. Homebrew, Sparkle, `mas`, npm,
Composer, Gradle, Yarn and Cargo are named only to identify the tools MoraClean works with, and belong to their
respective owners.
