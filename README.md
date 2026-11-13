# Android-lockdown

A single Bash script that de-Googles and hardens a **stock** Android phone over ADB, as far as you can without unlocking the bootloader. **Google Wallet tap-to-pay keeps working.**

No root and no custom ROM: the bootloader stays locked, so Play Integrity and Google Wallet keep working. Every change is logged and can be undone.

> ⚠️ Use at your own risk. Back up your photos and 2FA codes first. The script shows each list of apps before it disables anything, and `restore` undoes the changes, but you are responsible for your own phone.

## What it does

- **Installs privacy apps:** Droid-ify, IronFox, HeliBoard, Lawnchair, Organic Maps, K-9 Mail, Fossify Gallery/Files/Calendar, Ente Auth, Signal, Shelter and RethinkDNS. Lawnchair, IronFox and HeliBoard become the default launcher, browser and keyboard.
- **Removes or disables Google apps, AI and telemetry:** Gemini, Assistant, AICore, "Hey Google", Circle to Search, YouTube, Chrome, Gmail, Maps and more.
- **Removes phone-maker telemetry** on any brand, using the community-maintained [UAD-ng](https://github.com/Universal-Debloater-Alliance/universal-android-debloater-next-generation) list. Only packages rated "Recommended" (safe to remove) are used.
- **Universal sweep:** disables every pre-installed app in the app drawer that isn't needed.
- **Privacy settings:** private DNS with automatic fallback, GrapheneOS connectivity checks, no Wi-Fi/Bluetooth background scanning, a new random MAC address per connection, a camera without location access, and lock-screen hardening.
- **Guided steps** for settings Android only lets you change on the phone. The script opens each screen and gives instructions written for your phone.
- **PASS/FAIL check** that reads the phone's actual state after every run.

## What it never touches

Calls, SMS, contacts, mobile data, Wi-Fi, system and app updates, emergency alerts, camera, alarms, launcher, keyboard, Google Wallet, Play Store, Play Services, **any app you installed yourself**, and hidden system components that aren't on a known-safe list.

## Supported phones

**Any Android phone** (stock firmware, locked bootloader, with Google Play). The script asks the phone itself which apps it needs, so the debloat, sweep, telemetry removal, settings and checks work on every brand.

Some phones also get extra tuning:

| Phone | Extra tuning |
|---|---|
| Google Pixel 10a | Exact Pixel menu paths, memory tagging (MTE), Auditor |
| CMF Phone 2 Pro (Nothing OS) | Nothing extras removed (Essential Space, Aura, Nothing Gallery, …), Nothing menu paths |
| Samsung, Xiaomi / Redmi / POCO, OnePlus / Oppo / Realme, Motorola, Vivo, Honor / Huawei | Guided steps for the maker's own telemetry and ad settings |
| Any other phone | Guided steps use a Settings-search word. Run `scan` and open an issue to get maker extras added. |

On **Android 17**, built-in apps can't be uninstalled over ADB, so the script disables them and wipes their data instead.

## Requirements

**Computer:** Linux, macOS or Windows (Git Bash), with `bash`, `curl` and `python3`. If `adb` is missing, the script downloads Google's platform-tools.

**Phone:**
- stock firmware with a **locked bootloader**
- latest updates installed
- a screen lock set
- USB debugging on (Settings → About phone → tap *Build number* 7×, then Developer options → USB debugging)

## Quick start

```bash
git clone <this-repo>
cd <this-repo>
bash phone-lockdown.sh --dry-run   # preview, changes nothing
bash phone-lockdown.sh             # full run
```

Keep the phone unlocked and plugged in, and only connect one phone at a time. When it finishes, **test a tap-to-pay payment first**.

## Commands

| Command | What it does |
|---|---|
| `bash phone-lockdown.sh` | Everything, in order |
| `apps` | Install the privacy apps and set Lawnchair as the home screen |
| `debloat` | Google apps, AI, maker extras, telemetry, and the sweep |
| `telemetry` | Maker telemetry only (UAD-ng list) |
| `sweep` | Disable unneeded pre-installed drawer apps |
| `settings` | Network and privacy settings |
| `lock` | Lock screen, power menu, NFC and SIM |
| `manual` | Walk through the settings you change on the phone |
| `camera` | Camera without location; picks the right photo viewer |
| `launcher` | Make Lawnchair the default home screen |
| `harden` | Restrict any Google apps you kept |
| `verify` | PASS/FAIL check of the phone's actual state (changes nothing) |
| `scan` | List every drawer app and what the script does with it |
| `install app.apk` | Sideload over ADB (not subject to developer verification) |
| `restore` | Undo everything for the connected phone |

Options: `--dry-run` (change nothing) and `--yes` (no questions).

## Keeping apps

To stop the sweep from disabling an app, add its package name to `lockdown-state/keep-apps.txt`, one per line. `scan` shows the package names.

## Logs and backups

- Every run writes a timestamped log of everything shown on screen, plus every command sent to the phone and the phone's reply, to `lockdown-state/logs/`. `latest.log` is always the newest.
- Watch a run live with `tail -f lockdown-state/logs/latest.log`.
- Backups are kept per phone in `lockdown-state/<codename>-<serial>/`, so `restore` only affects the phone that's plugged in.

## Troubleshooting

- **adb hangs on Linux:** add `export ADB_LIBUSB=0` to `~/.bashrc`. The script also sets this itself.
- **Samsung isn't detected, or USB debugging is greyed out:** Samsung's *Auto Blocker* blocks USB commands and apps from outside the Play Store and Galaxy Store. It can only be turned off on the phone: Settings → Security and privacy → Auto Blocker → Off. The script recognises a blocked Samsung and shows these steps. At the end it asks whether to turn Auto Blocker back on; F-Droid apps only update while it's off.
- **"unauthorized":** in Developer options, tap *Revoke USB debugging authorizations*, replug the phone and tap **Allow** with *Always allow* ticked.
- **No internet on some Wi-Fi networks:** the network is blocking private DNS. The script falls back to Automatic when it detects this; you can also set it yourself under Settings → Network → Private DNS → Automatic.

## Limits

- **Google Play Services stays.** Tap-to-pay needs it, and it can't be sandboxed on stock Android.
- **Telemetry inside core system components** can't be removed without root.
- **Disabled apps still take up storage**, because on Android 17 they can't be uninstalled over ADB.
- **What you lose:**
  - Pixel's Emergency SOS (in the Safety app)
  - Google's text-to-speech; RHVoice from Droid-ify is a replacement
  - Now Playing and Live Caption

## Credits

- [UAD-ng](https://github.com/Universal-Debloater-Alliance/universal-android-debloater-next-generation): package list and safety ratings
- [GrapheneOS](https://grapheneos.org): connectivity-check servers and Auditor
- [F-Droid](https://f-droid.org), [IronFox](https://ironfoxoss.org), [Lawnchair](https://lawnchair.app) and the other app projects
