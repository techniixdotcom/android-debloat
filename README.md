# android-lockdown

A single Bash script that de-Googles and hardens a stock Android phone over USB (ADB), **without root and without unlocking the bootloader**. Google Wallet tap-to-pay, calls and SMS keep working.

Works best on Pixel and Nothing phones; also has profiles for Samsung, Xiaomi, OnePlus/Oppo/Realme, Motorola, Vivo and Honor.

## What it does

- **Installs privacy apps** from F-Droid: Droid-ify, IronFox, HeliBoard, Organic Maps, K-9 Mail, Fossify apps, Ente Auth, Shelter, RethinkDNS (plus Signal and Lawnchair from the Play Store)
- **Removes Google bloat and all AI**: Gemini, Assistant, AICore, the Google app, YouTube, Chrome, Gmail, Maps and more (each one only after its replacement is installed)
- **Optionally replaces Google Messages and Phone** with Fossify Messages and Fossify Phone (no Google, no Gemini). It asks first, because you lose RCS chat, Google's spam filter and caller ID, Call Screen and visual voicemail. Calls, SMS/MMS, VoLTE and Wi-Fi calling keep working.
- **Removes phone-maker extras and telemetry** using the [UAD-ng](https://github.com/Universal-Debloater-Alliance/universal-android-debloater-next-generation) list
- **Applies privacy settings**: Private DNS (AdGuard), no Wi-Fi/Bluetooth scanning, GrapheneOS connectivity checks, MAC randomization, lock screen hardening
- **Blocks tracking**: movement/activity recognition, body sensors, background location, camera location
- **Walks you through** the settings ADB can't change (ad ID, Google Location Accuracy, theft protection, 2G, SIM PIN, Gemini in Messages, AI call features, …)
- **Verifies** the result with a PASS/FAIL report
- **Everything is reversible** with `restore`

Apps are removed for the current user only (`pm uninstall --user 0`), so nothing is deleted from the system partition and a factory reset brings everything back.

## Requirements

- A computer with Linux, macOS or Windows (Git Bash / WSL)
- `bash`, `curl` and `python3`
- A USB data cable
- `adb` (downloaded automatically if missing)

On the phone: **Settings → About phone → tap "Build number" 7 times**, then **Developer options → USB debugging ON**.

## Usage

```bash
bash android-lockdown.sh            # interactive menu
bash android-lockdown.sh all        # full run (recommended first time)
bash android-lockdown.sh --dry-run all   # show what would happen, change nothing
```

| Command     | What it does                                              |
|-------------|-----------------------------------------------------------|
| `all`       | Everything below, in order                                |
| `apps`      | Install privacy apps, set Lawnchair as home screen        |
| `debloat`   | Remove Google apps, AI, maker extras, telemetry + sweep   |
| `telemetry` | Phone-maker telemetry only                                |
| `sweep`     | Disable unneeded pre-installed apps                       |
| `motion`    | Block movement / body-sensor / background-location access |
| `camera`    | Camera without location, pick photo viewer                |
| `settings`  | Network & privacy settings                                |
| `lock`      | Lock screen, power menu, NFC, SIM                         |
| `manual`    | Guided walk-through of on-phone settings                  |
| `harden`    | Restrict the Google apps you kept                         |
| `replace`   | Swap Google Messages + Phone for Fossify (asks first)     |
| `verify`    | PASS/FAIL check (changes nothing)                         |
| `scan`      | List every app and what the script does with it           |
| `install`   | Sideload APKs: `install app.apk [...]`                    |
| `status`    | Short summary                                             |
| `restore`   | Undo everything on this phone                             |

Flags: `--dry-run`, `--yes` / `-y` (no prompts).

To keep an app the sweep would remove, add its package name to `lockdown-state/keep-apps.txt`.

## After system updates

Updates can turn disabled apps (Gemini, the Google app) back on. Run `verify` after every update, and if anything shows FAIL, run `debloat` again.

For extra protection, block Gemini at the network level in RethinkDNS → DNS → custom rules: `gemini.google.com`, `bard.google.com`, `generativelanguage.googleapis.com`.

## Files

Backups and logs are written to `./lockdown-state/` (one folder per phone). Don't delete it if you might want to `restore` later.

## Disclaimer

Use at your own risk. Back up your photos and data first, and run with `--dry-run` if you're unsure. Test tap-to-pay after running.
