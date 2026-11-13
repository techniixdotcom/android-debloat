#!/usr/bin/env bash
# =============================================================================
#  android-lockdown.sh: one-shot GrapheneOS-style lockdown for a STOCK phone
#  that keeps Google Wallet tap-to-pay working. Detects the phone automatically:
#    - Google Pixel 10a      ("stallion")
#    - CMF Phone 2 Pro       ("Galaga", Nothing OS)
#    - anything else: Google apps/AI/settings still work, phone extras are skipped
#  Each phone gets its own backups + logs, so one PC can manage several phones.
#
#  You don't need to unlock or root. Everything goes through ADB:
#    - "pm uninstall --user 0" hides apps without touching the system image,
#      so the Play Integrity checks still pass and Wallet keeps working.
#    - Everything is logged and can be undone with:  ./android-lockdown.sh restore
#    - A factory reset always brings the phone back to stock.
#
#  USAGE
#    ./android-lockdown.sh                 # do EVERYTHING (asks before risky steps)
#    ./android-lockdown.sh all --yes       # everything, no questions
#    ./android-lockdown.sh all --dry-run   # show what would happen, change nothing
#
#    Individual steps:
#    ./android-lockdown.sh apps            # install privacy replacement apps (F-Droid)
#    ./android-lockdown.sh debloat         # remove Google apps + telemetry
#    ./android-lockdown.sh settings        # network/privacy settings
#    ./android-lockdown.sh manual          # walk through every setting you change by hand (Google, security,
#                                        #   and the phone maker's own telemetry/ad switches, any brand)
#    ./android-lockdown.sh lock            # lock screen, NFC unlock, SIM PIN, Google account access
#    ./android-lockdown.sh harden          # restrict any Google apps you kept
#    ./android-lockdown.sh camera          # camera without GPS, Photos as offline viewer
#    ./android-lockdown.sh install x.apk   # sideload over ADB (skips developer verification)
#    ./android-lockdown.sh verify          # check the phone's ACTUAL state (PASS/FAIL), changes nothing
#    ./android-lockdown.sh sweep           # disable EVERY pre-installed drawer app that isn't needed (works on any brand;
#                                        #   keeps calls/SMS/camera/gallery/alarms/launcher/Wallet/Play and every
#                                        #   app you installed; extra keeps: lockdown-state/keep-apps.txt)
#    ./android-lockdown.sh telemetry       # disable the phone maker's telemetry/analytics/ads (UAD-ng list, any brand)
#    ./android-lockdown.sh scan            # list every app in the app drawer and what the script does with it
#    ./android-lockdown.sh status          # show what's been done
#    ./android-lockdown.sh restore         # undo everything
#
#  NEEDS on the computer: bash, curl, python3. adb is downloaded automatically
#         from Google if it's missing. Mac/Linux: run in Terminal. Windows: use Git Bash.
#  NEEDS on the phone: USB debugging on (the script walks you through it).
#
#  LOGS: every run writes a timestamped log of everything shown on screen PLUS every
#        command sent to the phone and the phone's answer:
#          lockdown-state/logs/run-<date>-<mode>.log   (latest.log = newest)
#        Watch live in a second terminal:  tail -f lockdown-state/logs/latest.log
#        Every run that changes something ends with a full PASS/FAIL check of the phone.
#
#  DO NOT turn on Advanced Protection afterwards. It blocks sideloading.
# =============================================================================

set -u

# ----------------------------------------------------------------- config ----
DNS_HOST="dns.adguard-dns.com"     # or your NextDNS: abc123.dns.nextdns.io

# F-Droid download mirrors, tried in order (f-droid.org itself is often slow).
# Init7 is in Switzerland, FAU in Germany. All are official F-Droid mirrors.
FDROID_MIRRORS="https://mirror.init7.net/fdroid/repo https://ftp.fau.de/fdroid/repo https://f-droid.org/repo"

STATE_DIR="./lockdown-state"
TMP_DIR="$STATE_DIR/apk-cache"
# Per-phone backup files (set once the phone is identified, see set_device_paths)
DEV_DIR="$STATE_DIR/unknown-device"
set_device_paths() {
  DEV_DIR="$STATE_DIR/$1"
  LOG_REMOVED="$DEV_DIR/removed-packages.txt"
  LOG_DISABLED="$DEV_DIR/disabled-packages.txt"
  LOG_HARDENED="$DEV_DIR/hardened-packages.txt"
  LOG_SETTINGS="$DEV_DIR/settings-backup.txt"
  LOG_ROLES="$DEV_DIR/defaults-backup.txt"
}
set_device_paths unknown-device
PROFILE="generic"; DEVICE_NAME="Android phone"; MAKER=""; BRAND=""

# NEVER touched by this script (tap-to-pay, calls, SMS, eSIM, core system):
NEVER_TOUCH="
com.google.android.gms
com.google.android.gsf
com.android.vending
com.google.android.apps.walletnfcrel
com.android.nfc
com.google.android.webview
com.google.android.permissioncontroller
com.google.android.ext.services
com.google.android.networkstack
com.google.android.packageinstaller
com.google.android.documentsui
com.google.android.setupwizard
com.google.android.cellbroadcastreceiver
com.google.android.euicc
com.google.android.ims
com.google.android.dialer
com.google.android.contacts
com.google.android.apps.messaging
com.google.android.GoogleCamera
com.google.android.apps.nexuslauncher
com.google.android.apps.wallpaper
com.nothing.launcher
com.nothing.camera
com.android.camera
com.android.settings
com.android.systemui
com.android.phone
com.android.providers.telephony
com.nothing.ntfactorytest
com.nothing.factorytool
"

# ------------------------------------------------- replacement apps (F-Droid)
# package id | what it replaces
FDROID_APPS=(
  "com.looker.droidify|Droid-ify app store (F-Droid client; keeps everything below updated)"
  "io.ente.auth|Ente Auth (2FA codes, end-to-end encrypted backup)"
  "helium314.keyboard|HeliBoard keyboard (replaces Gboard)"
  "app.organicmaps|Organic Maps (replaces Google Maps)"
  "org.fossify.gallery|Fossify Gallery (replaces Photos)"
  "org.fossify.filemanager|Fossify File Manager (replaces Files)"
  "org.fossify.calendar|Fossify Calendar (replaces Google Calendar)"
  "com.fsck.k9|K-9 Mail (replaces Gmail)"
  "net.typeblog.shelter|Shelter (sandboxed work profile)"
  "com.celzero.bravedns|RethinkDNS (per-app firewall)"
  "org.fossify.clock|Fossify Clock (replaces the Google Clock; alarms, timer)"
  "org.fossify.math|Fossify Calculator (replaces the Google Calculator)"
)

# Play Store-only apps: the script opens their Play pages for you to tap Install
#   Auditor: GrapheneOS's own hardware attestation app; works on stock Pixels
PLAY_APPS=(
  "app.lawnchair.play|Lawnchair launcher (looks like the Pixel Launcher, no Google search bar)"
  "org.thoughtcrime.securesms|Signal (private messaging; Play version updates itself)"
  "app.attestation.auditor|Auditor by GrapheneOS (verifies the OS hasn't been tampered with)"
)
BROWSER_PKGS="org.ironfoxoss.ironfox org.mozilla.fennec_fdroid"

# IronFox: hardened Firefox with no telemetry. It comes from IronFox's own F-Droid repo,
# and the script checks the download against IronFox's published signing key.
IRONFOX_PKG="org.ironfoxoss.ironfox"
IRONFOX_REPOS="https://fdroid.ironfoxoss.org/fdroid/repo https://gitlab.com/ironfox-oss/fdroid/-/raw/main/fdroid/repo https://codeberg.org/ironfox-oss/fdroid/raw/branch/main/fdroid/repo"
IRONFOX_CERT="C5E291B5A571F9C8CD9A9799C2C94E02EC9703948893F2CA756D67B94204F904"

# ------------------------------------------------- packages to remove --------
TIER1=(
  com.google.android.youtube                 # YouTube
  com.google.android.apps.youtube.music      # YouTube Music
  com.google.android.apps.tachyon            # Meet
  com.google.android.videos                  # Google TV
  com.google.android.apps.subscriptions.red  # Google One
  com.google.android.apps.docs               # Drive
  com.google.android.apps.magazines          # Google News
  com.google.android.apps.podcasts           # Podcasts
  com.google.android.keep                    # Keep
  com.google.android.apps.tips               # Pixel Tips
  com.google.android.apps.restore            # Data restore tool (setup only)
  com.google.android.projection.gearhead     # Android Auto
  com.google.ar.core                         # ARCore
  com.google.android.apps.chromecast.app     # Google Home
  com.google.android.apps.wellbeing          # Digital Wellbeing
  com.google.android.apps.turbo              # Device Health Services
  com.google.android.partnersetup            # Partner setup
  com.google.android.apps.docs.editors.docs  # Google Docs
  com.google.android.apps.translate          # Google Translate
  com.google.android.apps.weather            # Pixel Weather
  com.google.android.apps.wear.companion     # Pixel Watch app
  com.fitbit.FitbitMobile                    # Fitbit / Health
  com.google.android.apps.pixel.aurelius     # Pixel Journal
  com.google.android.apps.pixel.nowplaying   # Now Playing history
  com.google.android.apps.credentialmanager  # "Passwords" (Google Password Manager app)
)

TELEMETRY=(
  com.google.mainline.telemetry              # Mainline module telemetry
  com.google.android.feedback                # Feedback / crash reports
)

# Replaced apps
TIER2=(   # always removed (each one waits for its replacement)
  com.android.chrome                         # -> Fennec
  com.google.android.gm                      # -> K-9 Mail
  com.google.android.apps.maps               # -> Organic Maps
  com.google.android.calendar                # -> Fossify Calendar
  com.google.android.apps.nbu.files          # -> Fossify File Manager
  com.google.android.apps.recorder           # Recorder
  com.google.android.apps.safetyhub          # Personal Safety (loses crash detection)
  com.google.android.apps.adm                # Find Hub app (service stays in Play Services)
  com.google.android.tts                     # Speech Services (loses text-to-speech)
)

# ALL AI: always removed, no prompt
AI_PKGS=(
  com.google.android.apps.bard               # Gemini
  com.google.android.apps.googleassistant    # Assistant
  com.google.android.aicore                  # AICore: on-device Gemini Nano runtime
  com.google.android.as                      # Android System Intelligence (Now Playing,
                                             #   Live Caption, smart replies, Magic Cue)
  com.google.android.as.oss                  # Private Compute Services (feeds the AI features)
  com.google.android.apps.pixel.creativeassistant  # Pixel Studio (AI image generator)
  com.google.assistant.hubui                 # Assistant / Gemini hub UI
  com.google.android.apps.labs.language.tailwind  # NotebookLM
  com.google.android.googlequicksearchbox.nga_resources  # "Next-gen Assistant" voice resources
)
# ---------------------------------------------------------- app drawer sweep --
# The sweep disables EVERY pre-installed app in the app drawer that isn't listed here.
# Apps you installed yourself (banking apps etc.) are never touched.
# Hidden system packages are never touched by the sweep (that can stop the phone booting).
KEEP_ALWAYS="
com.android.settings
com.android.vending
com.google.android.apps.walletnfcrel
com.google.android.dialer
com.google.android.apps.messaging
com.google.android.contacts
com.android.stk
com.google.android.documentsui
com.android.documentsui
"
# Add your own: packages to keep even though they're pre-installed (space separated)
KEEP_EXTRA=""
# Pre-installed apps that are only swept once their replacement is installed
#   pre-installed app | replacement
SWEEP_NEEDS_REPLACEMENT="
com.google.android.deskclock|org.fossify.clock
com.google.android.calculator|org.fossify.math
com.android.chrome|org.ironfoxoss.ironfox
com.google.android.gm|com.fsck.k9
com.google.android.apps.maps|app.organicmaps
com.google.android.calendar|org.fossify.calendar
com.google.android.apps.nbu.files|org.fossify.filemanager
"

# Phone-maker extras (packages that don't exist on a phone are skipped automatically)
OEM_PKGS=(
  # CMF Phone 2 Pro / Nothing OS
  com.aura.oobe.solutions                    # "AppServices" (Aura): pushes app installs; comes back if uninstalled
  com.nothing.ntessentialspace               # Essential Space (AI, sends content to cloud AI models)
  com.nothing.ntessentialrecorder            # Essential Space recorder (AI summaries)
  com.nothing.weather                        # Nothing Weather
  com.nothing.aiwidget                       # AI widget
  com.nothing.essentialintelligence          # AI engine behind Essential Space / AI features
  com.nothing.experience                     # "Experience" framework: usage data collection
  com.nothing.logkit                         # hidden log collection tool
  com.nothing.enginnerservice                # hidden diagnostics service
  com.nothing.experimental                   # experimental features
  com.nothing.smartcenter                    # Nothing X (earbuds companion; reinstall from Play if you use Nothing earbuds)
  com.nothing.agreement                      # privacy-policy / agreement prompts
  com.nothing.games                          # games launcher
  com.nothing.ntgamedashboard                # game dashboard overlay
  com.nothing.userguide                      # user guide
  com.nothing.introduction16                 # "what's new" intro tour
  com.nothing.user.center                    # Nothing account / community centre
  com.nothing.universal.search               # Nothing Launcher search (web suggestions)
  com.nothing.gallery                        # Nothing Gallery (photos then open in Fossify Gallery)
  com.facebook.appmanager                    # Facebook preload services (some regions)
  com.facebook.services
  com.facebook.system
  com.facebook.katana                        # Facebook app (some regions)
)
# These must be disabled, never uninstalled (they reinstall themselves after an uninstall)
DISABLE_ONLY="com.aura.oobe.solutions"

# The Google app is removed too (it handles "Hey Google", Circle to Search, the Gemini overlay)
# Removed only after the replacement is the active default:
GBOARD=com.google.android.inputmethod.latin
GOOGLE_APP=com.google.android.googlequicksearchbox

# Google apps to restrict if you KEEP them (background off + permissions reset)
HARDEN_TARGETS=(
  com.google.android.googlequicksearchbox com.google.android.apps.maps
  com.android.chrome com.google.android.youtube
  com.google.android.gm com.google.android.apps.docs com.google.android.calendar
  com.google.android.keep com.google.android.apps.tachyon com.google.android.apps.bard
  com.google.android.apps.youtube.music com.google.android.videos
  com.google.android.apps.magazines com.google.android.apps.subscriptions.red
  com.google.android.apps.nbu.files com.google.android.apps.recorder
  com.google.android.apps.chromecast.app
)
HARDEN_PERMS="ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION ACCESS_BACKGROUND_LOCATION
RECORD_AUDIO CAMERA READ_CONTACTS READ_CALL_LOG READ_SMS READ_PHONE_STATE
BODY_SENSORS ACTIVITY_RECOGNITION NEARBY_WIFI_DEVICES BLUETOOTH_SCAN"

# ------------------------------------------------------------- helpers -------
DRY=0; YES=0
c_ok=$'\e[32m'; c_warn=$'\e[33m'; c_err=$'\e[31m'; c_h=$'\e[1;36m'; c_0=$'\e[0m'
say()  { echo "$*"; }
ok()   { echo "${c_ok}  ✓${c_0} $*"; }
warn() { echo "${c_warn}  !${c_0} $*" >&2; }
die()  { echo "${c_err}Error:${c_0} $*" >&2; exit 1; }
head_() { echo; echo "${c_h}== $* ==${c_0}"; }

# If the USB link stalls, restart adb and wait for the phone again
adb_recover() {
  warn "USB connection stalled, restarting adb..."
  adb kill-server >/dev/null 2>&1; sleep 2; adb start-server >/dev/null 2>&1
  local i; for i in $(seq 1 30); do
    [[ "$(adb get-state 2>/dev/null)" == "device" ]] && timeout 10 adb shell true </dev/null >/dev/null 2>&1 && return 0
    sleep 2
  done
  die "Phone stopped responding. Unplug and replug it, keep it unlocked, then run the script again (finished steps are skipped)."
}
# adb shell with a timeout + one automatic recovery; no stdin, CR stripped
ash() {
  local out rc
  out="$(timeout 30 adb shell "$@" </dev/null 2>&1)"; rc=$?
  if [[ $rc == 124 ]]; then adb_recover; out="$(timeout 30 adb shell "$@" </dev/null 2>&1)"; fi
  printf '%s\n' "$out" | tr -d '\r'
}
# adb install: copy to the phone first (--no-streaming), with a timeout + one recovery
adb_install() {
  local apk=$1 out rc
  logline "    \$ adb install --no-streaming -r $apk"
  out="$(timeout 180 adb install --no-streaming -r "$apk" </dev/null 2>&1)"; rc=$?
  if [[ $rc == 124 ]]; then
    warn "Install timed out. If the phone shows a Play Protect popup, tap Install anyway."
    adb_recover
    out="$(timeout 180 adb install --no-streaming -r "$apk" </dev/null 2>&1)"
  fi
  logout "$out"
  printf '%s\n' "$out"
}
# ---------------------------------------------------------------- logging ---
RUN_LOG=""
# fd 3 = the log writer. Screen output (via tee) and command details share it, so they stay in order.
logline() { [[ -n "$RUN_LOG" ]] && printf '%s\n' "$*" >&3; return 0; }
logout()  { [[ -n "$RUN_LOG" && -n "$1" ]] && printf '%s\n' "$1" | sed 's/^/        → /' >&3; return 0; }
stamp() {                                            # timestamp + strip colours for the log file
  if awk 'BEGIN{strftime()}' 2>/dev/null; then
    awk '{ gsub(/\033\[[0-9;]*m/, ""); print strftime("[%Y-%m-%d %H:%M:%S]"), $0; fflush() }'
  else
    while IFS= read -r l; do printf '[%s] %s\n' "$(date '+%F %T')" "$(sed 's/\x1b\[[0-9;]*m//g' <<<"$l")"; done
  fi
}
setup_logging() {
  mkdir -p "$STATE_DIR/logs"
  RUN_LOG="$(cd "$STATE_DIR/logs" && pwd)/run-$(date +%Y%m%d-%H%M%S)-$MODE.log"
  : > "$RUN_LOG"
  ln -sfn "$RUN_LOG" "$STATE_DIR/logs/latest.log"
  # Everything shown on screen also goes to the log file, live
  exec 3> >(stamp >> "$RUN_LOG")
  exec > >(tee /dev/fd/3) 2>&1
  say "Log file: $RUN_LOG"
  say "  (watch it live in another terminal: tail -f $STATE_DIR/logs/latest.log)"
  logline "=== pixel-debloat.sh mode=$MODE dry_run=$DRY yes=$YES ==="
  trap 'logline "=== finished (exit $?) ==="; echo; echo "Full log: $RUN_LOG"' EXIT
}

act() {                                              # state-changing adb shell, logged
  if [[ $DRY == 1 ]]; then echo "    [dry-run] adb shell $*"; logline "    [dry-run] adb shell $*"; return 0; fi
  logline "    \$ adb shell $*"
  local out; out="$(ash "$@")"
  logout "$out"
  [[ -n "$out" ]] && printf '%s\n' "$out"
  return 0
}
confirm() {                                          # confirm "question"
  [[ $YES == 1 || $DRY == 1 ]] && return 0
  read -r -p "  ? $1 [y/N] " a; [[ "$a" =~ ^[Yy] ]]
}
pause() {
  [[ $YES == 1 || $DRY == 1 ]] && return 0
  while read -r -t 0.05 -n 10000 _; do :; done   # throw away Enter presses typed earlier
  read -r -p "  → $1 (press Enter) " _
}

refresh_installed() { INSTALLED="$(ash pm list packages -e --user 0 | sed 's/^package://')"; }   # enabled apps only
DRY_GONE=""                                          # packages a dry run "removed"
is_installed() { grep -qx "$1" <<<"$INSTALLED" && ! grep -qx "$1" <<<"$DRY_GONE"; }
is_protected() { grep -qx "$1" <<<"$NEVER_TOUCH"; }

remove_pkg() {
  local pkg=$1
  is_protected "$pkg" && { warn "$pkg is protected, skipping"; return; }
  is_installed "$pkg" || return 0
  local out=""
  [[ " $DISABLE_ONLY " == *" $pkg "* ]] || out="$(act pm uninstall --user 0 "$pkg")"
  if [[ $DRY == 1 || "$out" == Success* ]]; then
    ok "removed $pkg"
    if [[ $DRY == 1 ]]; then DRY_GONE+="$pkg"$'\n'; else echo "$pkg" >> "$LOG_REMOVED"; fi
    return 0
  fi
  # Android 17 blocks uninstalling system apps over ADB. Disabling still works:
  # the app can't run, has no network, sends nothing, and vanishes from the app drawer.
  # Its data is wiped first.
  act pm clear --user 0 "$pkg" >/dev/null 2>&1
  out="$(act pm disable-user --user 0 "$pkg")"
  if [[ "$out" == *disabled* ]]; then
    ok "disabled $pkg (data wiped)"
    echo "$pkg" >> "$LOG_DISABLED"
  else
    warn "$pkg: couldn't remove or disable ($out)"
  fi
}

set_setting() {                                      # set_setting ns key value
  local ns=$1 key=$2 val=$3 old
  old="$(ash settings get "$ns" "$key")"
  if [[ $DRY == 0 ]] && ! grep -q "^$ns $key " "$LOG_SETTINGS" 2>/dev/null; then
    echo "$ns $key $old" >> "$LOG_SETTINGS"
  fi
  act settings put "$ns" "$key" "$val" >/dev/null
  if [[ $DRY == 1 ]]; then ok "$ns/$key = $val"; return; fi
  local now; now="$(ash settings get "$ns" "$key")"
  if [[ "$now" == "$val" ]]; then ok "$ns/$key = $val"
  else warn "$ns/$key did NOT change (phone says: $now)"; fi
}

# ------------------------------------------------------------ preflight ------
# Get adb: use the one on this computer, or download Google's official platform-tools
ensure_adb() {
  command -v adb >/dev/null && { ok "adb found: $(command -v adb)"; return 0; }
  local here; here="$(cd "$(dirname "$0")" && pwd)"
  if [[ -x "$here/platform-tools/adb" || -x "$here/platform-tools/adb.exe" ]]; then
    export PATH="$here/platform-tools:$PATH"; ok "Using downloaded platform-tools"; return 0
  fi
  local os
  case "$(uname -s)" in
    Linux*)  os=linux ;;
    Darwin*) os=darwin ;;
    MINGW*|MSYS*|CYGWIN*) os=windows ;;
    *) die "Unknown OS. Install Android platform-tools yourself: https://developer.android.com/tools/releases/platform-tools" ;;
  esac
  say "  Downloading Google's Android platform-tools (adb) for $os..."
  local zip="$here/platform-tools.zip"
  curl -fL --progress-bar --retry 3 --retry-delay 2 --connect-timeout 20 --speed-limit 20000 --speed-time 30 -o "$zip" "https://dl.google.com/android/repository/platform-tools-latest-$os.zip" \
    || die "Download failed. Check your internet connection."
  if command -v unzip >/dev/null; then unzip -q -o "$zip" -d "$here"
  else python3 -c 'import sys,zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$zip" "$here"
       chmod +x "$here/platform-tools/"* 2>/dev/null; fi
  rm -f "$zip"
  export PATH="$here/platform-tools:$PATH"
  command -v adb >/dev/null || die "Couldn't set up adb."
  ok "platform-tools installed next to the script"
}

wait_for_phone() {
  # Linux: adb's libusb driver can stall after a few seconds (seen with adb 37 on Arch).
  # Use the kernel's native USB driver instead, and restart the adb server so it applies.
  if [[ "$(uname -s)" == Linux* ]]; then
    export ADB_LIBUSB="${ADB_LIBUSB:-0}"
    adb kill-server >/dev/null 2>&1
  fi
  adb start-server >/dev/null 2>&1
  _wait_for_phone || return 1
  # Make sure the phone actually answers commands (catches half-authorized connections)
  if ! timeout 15 adb shell true </dev/null >/dev/null 2>&1; then
    die "The phone is connected but doesn't answer. Run: adb kill-server, revoke USB debugging authorizations on the phone, replug, tap Allow (tick 'Always allow'), then run the script again."
  fi
}
# Is a Samsung plugged in over USB (even if adb can't see it)?
samsung_on_usb() {
  if command -v lsusb >/dev/null; then lsusb 2>/dev/null | grep -qi '04e8:\|samsung'; return; fi
  if command -v system_profiler >/dev/null; then system_profiler SPUSBDataType 2>/dev/null | grep -qi samsung; return; fi
  return 1
}
samsung_unblock_help() {
  say ""
  say "  ${c_warn}A Samsung phone is plugged in, but it isn't accepting commands from this computer.${c_0}"
  say "  ${c_warn}That's Samsung's 'Auto Blocker': it blocks USB commands AND apps from outside${c_0}"
  say "  ${c_warn}Google Play / Galaxy Store. It can only be switched off on the phone itself:${c_0}"
  say "    1. Settings → Security and privacy → Auto Blocker → Off"
  say "       (if a 'turn back on after 30 minutes' option appears, choose NOT to, the script"
  say "        needs more time and F-Droid apps need it off to update)"
  say "    2. Settings → About phone → Software information → tap 'Build number' 7 times"
  say "    3. Settings → Developer options → USB debugging ON (no longer greyed out)"
  say "    4. Unplug and replug, unlock the phone, tap 'Allow'"
}

_wait_for_phone() {
  local n; n="$(adb devices 2>/dev/null | grep -cE '\s(device|unauthorized)$')"
  if [[ "${n:-0}" -gt 1 && -z "${ANDROID_SERIAL:-}" ]]; then
    die "More than one phone is plugged in. Unplug one (or run: ANDROID_SERIAL=<serial> bash android-lockdown.sh ...)."
  fi
  local state; state="$(adb get-state 2>&1)"
  [[ "$state" == "device" ]] && { ok "Phone connected and authorized"; return 0; }
  say ""
  say "  ${c_warn}Waiting for your phone...${c_0}"
  say "    1. Phone: Settings → About phone → tap 'Build number' 7 times"
  say "    2. Settings → System → Developer options → USB debugging ON"
  say "    3. Plug in the USB cable, unlock the phone, tap 'Allow' on the"
  say "       'Allow USB debugging?' popup (tick 'Always allow from this computer')"
  local i shown_samsung=0
  for i in $(seq 1 120); do
    sleep 2
    state="$(adb get-state 2>&1)"
    [[ "$state" == "device" ]] && { ok "Phone connected and authorized"; return 0; }
    # A Samsung that USB sees but adb doesn't = Auto Blocker / USB debugging greyed out
    if [[ $shown_samsung == 0 && $i -ge 3 && "$state" != *unauthorized* ]] && samsung_on_usb; then
      samsung_unblock_help; shown_samsung=1
    fi
    if [[ "$state" == *unauthorized* && $((i % 10)) == 1 ]]; then
      say "    → Phone found, but tap 'Allow' on the phone screen"
    fi
  done
  die "No phone after 4 minutes. Check the cable (it must carry data, not just charge) and try again."
}

check_tools() {
  command -v curl >/dev/null || die "curl is missing. Install it and run again."
  if ! command -v python3 >/dev/null; then
    warn "python3 missing: apps from F-Droid can't be downloaded automatically."
    case "$(uname -s)" in
      Darwin*) say "      Install with: xcode-select --install" ;;
      Linux*)  say "      Install with your package manager, e.g. sudo apt install python3" ;;
      *)       say "      Install from https://www.python.org/downloads/" ;;
    esac
    confirm "Continue without automatic app installs?" || exit 1
  fi
}

preflight() {
  head_ "Preflight"
  check_tools
  ensure_adb
  wait_for_phone
  mkdir -p "$STATE_DIR" "$TMP_DIR"
  local model vbs sdk
  model="$(ash getprop ro.product.model)"
  vbs="$(ash getprop ro.boot.verifiedbootstate)"
  sdk="$(ash getprop ro.build.version.sdk)"
  ok "Device: $model (SDK $sdk)"
  local codename serial
  codename="$(ash getprop ro.product.device)"
  local lc; lc="$(tr '[:upper:]' '[:lower:]' <<<"$codename")"
  serial="$(adb get-serialno 2>/dev/null | tr -d '\r')"
  case "$lc" in
    stallion) PROFILE=pixel; DEVICE_NAME="Pixel 10a"; ok "Pixel 10a (stallion) detected" ;;
    galaga*)  PROFILE=cmf;   DEVICE_NAME="CMF Phone 2 Pro"; ok "CMF Phone 2 Pro (Galaga, Nothing OS) detected" ;;
    *)
      PROFILE=generic; DEVICE_NAME="$model"
      warn "$model ($codename) has no dedicated profile. Google apps, AI, settings and checks still apply;"
      warn "phone-maker extras are skipped. Run './android-lockdown.sh scan' afterwards to review leftovers."
      confirm "Continue?" || exit 1 ;;
  esac
  # Separate backups per phone, so restore only ever touches this phone
  set_device_paths "$lc-${serial:-unknown}"
  mkdir -p "$DEV_DIR"
  # One-time move of backups made by the old Pixel-only script
  if [[ $PROFILE == pixel && -d ./pixel-lockdown-state && ! -s "$LOG_DISABLED" && ! -s "$LOG_SETTINGS" ]]; then
    cp ./pixel-lockdown-state/*.txt* "$DEV_DIR/" 2>/dev/null && ok "Imported backups from the old pixel-lockdown-state folder"
  fi
  MAKER="$(ash getprop ro.product.manufacturer | tr '[:upper:]' '[:lower:]')"
  BRAND="$(ash getprop ro.product.brand | tr '[:upper:]' '[:lower:]')"
  ok "Maker: ${MAKER:-unknown} (brand: ${BRAND:-unknown})"
  [[ "$MAKER" == *samsung* ]] && ok "Samsung Auto Blocker is off (USB commands work), so apps can be installed"
  logline "device: $DEVICE_NAME model=$model codename=$codename serial=$serial sdk=$sdk profile=$PROFILE maker=$MAKER brand=$BRAND"
  ok "Backups for this phone: $DEV_DIR"
  detect_camera
  if [[ "$vbs" == "green" ]]; then ok "Bootloader locked + verified boot green (Wallet-compatible)"
  else warn "Verified boot state is '$vbs'. Wallet tap-to-pay will not work on this phone anyway."; fi
  refresh_installed
  is_installed com.google.android.apps.walletnfcrel && ok "Google Wallet present" || warn "Google Wallet not installed"
  is_installed com.google.android.gms || die "Play Services missing. Don't run this on a de-Googled phone."
  [[ $DRY == 1 ]] && warn "DRY RUN: nothing will be changed"
}

# ------------------------------------------------------- F-Droid installer ---
fdroid_install() {                                   # fdroid_install pkg label
  local pkg=$1 label=$2
  if is_installed "$pkg"; then ok "$label: already installed"; return 0; fi
  if [[ $DRY == 1 ]]; then echo "    [dry-run] download + install $pkg"; return 0; fi
  command -v curl >/dev/null || { warn "curl missing, can't install $pkg"; return 1; }
  local codes
  # Ask the F-Droid API for the newest version codes (several when there's one APK per CPU type)
  codes="$(curl -fsSL "https://f-droid.org/api/v1/packages/$pkg" 2>/dev/null | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
p=d.get("packages") or []
if p:
    top=p[0].get("versionName")
    print(" ".join(str(x["versionCode"]) for x in p if x.get("versionName")==top))
elif d.get("suggestedVersionCode"): print(d["suggestedVersionCode"])
' 2>/dev/null)"
  [[ -n "$codes" ]] || { warn "$label: not found on F-Droid, install it manually"; return 1; }
  local vc out
  local mirror got
  for vc in $codes; do
    got=0
    for mirror in $FDROID_MIRRORS; do
      say "    downloading $label from ${mirror#https://}..."
      if curl -fL --progress-bar --retry 2 --retry-delay 2 --connect-timeout 15 --speed-limit 200000 --speed-time 15 \
           -o "$TMP_DIR/$pkg.apk" "$mirror/${pkg}_${vc}.apk"; then got=1; break; fi
      warn "slow or unavailable, trying the next mirror"
    done
    [[ $got == 1 ]] || continue
    say "    installing on the phone..."
    out="$(adb_install "$TMP_DIR/$pkg.apk")"
    if [[ "$out" == *Success* ]]; then ok "$label"; return 0; fi
  done
  warn "$label: install failed ($(tail -1 <<<"$out"))"; return 1
}

ironfox_install() {
  if is_installed "$IRONFOX_PKG"; then ok "IronFox: already installed"; return 0; fi
  if [[ $DRY == 1 ]]; then echo "    [dry-run] download + verify + install IronFox"; return 0; fi
  local repo apk="$TMP_DIR/ironfox.apk" info name sha
  for repo in $IRONFOX_REPOS; do
    # Pick the newest arm64 build from the repo index (v2 format, falls back to v1)
    info="$( { curl -fsSL "$repo/index-v2.json" 2>/dev/null || curl -fsSL "$repo/index-v1.json" 2>/dev/null; } | python3 -c '
import json,sys
pkg="org.ironfoxoss.ironfox"
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
c=[]
p=d.get("packages",{}).get(pkg)
if isinstance(p,dict):                      # index-v2
    for v in p.get("versions",{}).values():
        m=v.get("manifest",{}); f=v.get("file",{})
        c.append((m.get("versionCode",0), m.get("nativecode") or [], f.get("name",""), f.get("sha256","")))
elif isinstance(p,list):                    # index-v1
    for v in p:
        c.append((v.get("versionCode",0), v.get("nativecode") or [], "/"+v.get("apkName",""), v.get("hash","")))
c=[x for x in c if x[2] and (not x[1] or "arm64-v8a" in x[1])]
if c:
    best=max(c,key=lambda x:x[0]); print(best[2].lstrip("/"), best[3])
' 2>/dev/null)"
    [[ -n "$info" ]] || continue
    name="${info%% *}"; sha="${info#* }"
    say "    downloading IronFox from $repo ..."
    curl -fL --progress-bar --retry 3 --retry-delay 2 --connect-timeout 20 --speed-limit 20000 --speed-time 30 -o "$apk" "$repo/$name" || continue
    if [[ -n "$sha" ]] && ! { sha256sum "$apk" 2>/dev/null || shasum -a 256 "$apk"; } | grep -qi "^$sha"; then
      warn "IronFox download checksum mismatch from $repo, trying next mirror"; continue
    fi
    if command -v apksigner >/dev/null; then
      if apksigner verify --print-certs "$apk" 2>/dev/null | tr -d ':' | grep -qi "SHA-256 digest $IRONFOX_CERT"; then
        ok "IronFox signature verified"
      else warn "IronFox signing certificate doesn't match. NOT installing."; return 1; fi
    fi
    say "    installing on the phone..."
    if adb_install "$apk" | grep -q Success; then ok "IronFox installed"; return 0; fi
  done
  # Fallback: add IronFox's repo to Droid-ify (it checks the repo signature itself)
  warn "Couldn't download IronFox automatically. Add its repo in Droid-ify instead:"
  say  "      Droid-ify → Settings → Repositories → +"
  say  "      Address:     https://fdroid.ironfoxoss.org/fdroid/repo"
  say  "      Fingerprint: $IRONFOX_CERT"
  act am start -a android.intent.action.VIEW \
    -d "fdroidrepos://fdroid.ironfoxoss.org/fdroid/repo?fingerprint=$IRONFOX_CERT" >/dev/null
  pause "In Droid-ify: add the repo, install IronFox, then come back here"
  refresh_installed
}

step_apps() {
  head_ "Installing privacy replacement apps (F-Droid repo, managed by Droid-ify)"
  # Stop Play Protect from pausing each USB install with a popup (normal Play Protect stays on)
  set_setting global verifier_verify_adb_installs 0
  for entry in "${FDROID_APPS[@]}"; do
    fdroid_install "${entry%%|*}" "${entry#*|}"
  done
  refresh_installed
  ironfox_install

  head_ "Play Store apps (install these on the phone)"
  local need=0
  for entry in "${PLAY_APPS[@]}"; do
    local pkg="${entry%%|*}" label="${entry#*|}"
    if [[ "$pkg" == app.attestation.auditor && $PROFILE != pixel ]]; then continue; fi   # Auditor doesn't support this phone
    if is_installed "$pkg"; then ok "$label: already installed"; continue; fi
    need=1
    act am start -a android.intent.action.VIEW -d "market://details?id=$pkg" >/dev/null
    say "    opened Play Store: $label"
    pause "Tap Install on the phone, then come back here"
  done
  [[ $need == 1 ]] && refresh_installed
  step_launcher
  detect_camera          # re-check now that Fossify Gallery may be installed
}

# ---------------------------------------------------- default app switching --
set_default_keyboard() {
  is_installed helium314.keyboard || return 1
  local id cur
  id="$(ash ime list -a -s | grep '^helium314\.keyboard/' | head -1)"
  [[ -n "$id" ]] || return 1
  [[ $DRY == 0 && ! -s "$LOG_ROLES.ime" ]] && ash settings get secure default_input_method > "$LOG_ROLES.ime"
  act ime enable "$id" >/dev/null; act ime set "$id" >/dev/null
  [[ $DRY == 1 ]] && return 0
  cur="$(ash settings get secure default_input_method)"
  [[ "$cur" == "$id" ]]
}
BROWSER=""
pick_browser() { local b; for b in $BROWSER_PKGS; do is_installed "$b" && { BROWSER=$b; return 0; }; done; return 1; }
set_default_browser() {
  pick_browser || return 1
  act cmd role add-role-holder android.app.role.BROWSER "$BROWSER" >/dev/null
  [[ $DRY == 1 ]] && return 0
  ash cmd role get-role-holders android.app.role.BROWSER | grep -q "$BROWSER"
}
LAUNCHER_PKG=app.lawnchair.play
set_default_launcher() {
  is_installed "$LAUNCHER_PKG" || return 1
  [[ $DRY == 1 ]] && { act cmd role add-role-holder android.app.role.HOME "$LAUNCHER_PKG"; return 0; }
  # The proper way (home-screen role), then the older way as a fallback
  act cmd role add-role-holder android.app.role.HOME "$LAUNCHER_PKG" >/dev/null
  if ! ash cmd role get-role-holders android.app.role.HOME | grep -q "$LAUNCHER_PKG"; then
    local comp
    comp="$(ash cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME \
            | grep -o "${LAUNCHER_PKG//./\\.}/[^ ]*" | head -1)"
    [[ -n "$comp" ]] && act cmd package set-home-activity "$comp" >/dev/null
  fi
  ash cmd role get-role-holders android.app.role.HOME | grep -q "$LAUNCHER_PKG"
}
step_launcher() {
  head_ "Home screen: Lawnchair"
  if ! is_installed "$LAUNCHER_PKG"; then
    warn "Lawnchair isn't installed yet. Install it from the Play Store, then run: bash android-lockdown.sh launcher"
    return 0
  fi
  if set_default_launcher; then ok "Lawnchair is the default home screen"
  else warn "Couldn't set it automatically: Settings → Apps → Default apps → Home app → Lawnchair"; fi
}

# --------------------------------------------------------------- debloat -----
step_debloat() {
  head_ "Removing Google apps (safe tier)"
  for p in "${TIER1[@]}"; do remove_pkg "$p"; done

  head_ "Removing telemetry packages"
  for p in "${TELEMETRY[@]}"; do remove_pkg "$p"; done

  head_ "Removing $DEVICE_NAME extras (phone-maker apps, AI, app installers)"
  local any_oem=0
  for p in "${OEM_PKGS[@]}"; do
    is_installed "$p" || continue
    any_oem=1
    # galleries only go once Fossify Gallery is there to open the camera's photos
    if [[ "$p" == *gallery* ]] && ! is_installed org.fossify.gallery; then
      warn "$p kept until Fossify Gallery is installed (the camera needs a photo viewer)"; continue
    fi
    remove_pkg "$p"
  done
  [[ $any_oem == 0 ]] && ok "None found on this phone"

  head_ "Removing ALL AI (Gemini, Assistant, AICore, \"Hey Google\", Circle to Search)"
  for p in "${AI_PKGS[@]}"; do remove_pkg "$p"; done
  if is_installed "$GOOGLE_APP"; then
    if set_default_launcher; then ok "Lawnchair is the default launcher"
    else warn "Stock launcher stays; its Google search bar will stop working (install Lawnchair)"; fi
    remove_pkg "$GOOGLE_APP"
  fi

  head_ "Turning off assistant gestures (long-press home / power button)"
  act cmd role clear-role-holders android.app.role.ASSISTANT >/dev/null 2>&1
  local holder; holder="$(ash cmd role get-role-holders android.app.role.ASSISTANT)"
  if [[ -z "${holder//[[:space:]]/}" || $DRY == 1 ]]; then ok "No default assistant app"
  else warn "Assistant is still set to: $holder (Settings → Apps → Default apps → Digital assistant app → None)"; fi
  set_setting secure assist_long_press_home_enabled 0
secure clock_seconds 1
system status_bar_show_battery_percent 1
global window_animation_scale 0
global transition_animation_scale 0
global animator_duration_scale 0
secure lockdown_in_power_menu 1
global wifi_networks_available_notification_on 0
  set_setting secure assist_touch_gesture_enabled 0
  set_setting global power_button_long_press 1          # 1 = power menu (not the assistant)

  head_ "Keyboard: Gboard -> HeliBoard (Gboard has Gemini built in)"
  if is_installed "$GBOARD"; then
    if set_default_keyboard; then ok "HeliBoard is now the default keyboard"; remove_pkg "$GBOARD"
    else warn "HeliBoard isn't active, so Gboard stays (removing it could leave you with no keyboard)"; fi
  else ok "Gboard already gone"; fi

  head_ "Removing Chrome, Gmail, Maps, Calendar, Files, Recorder, Speech, Personal Safety, Find Hub app"
  if is_installed com.android.chrome; then
    if set_default_browser; then ok "$BROWSER is the default browser"; else warn "Couldn't set default browser; set it in Settings → Apps → Default apps"; fi
  fi
  # Each app is only removed once its replacement is installed, so you're never left without one
  for p in "${TIER2[@]}"; do
    case "$p" in
      com.android.chrome)              pick_browser || { warn "IronFox not installed yet, keeping Chrome for now"; continue; } ;;
      com.google.android.gm)           is_installed com.fsck.k9 || { warn "K-9 not installed yet, keeping Gmail for now"; continue; } ;;
      com.google.android.apps.maps)    is_installed app.organicmaps || { warn "Organic Maps not installed yet, keeping Maps for now"; continue; } ;;
      com.google.android.calendar)     is_installed org.fossify.calendar || { warn "Fossify Calendar not installed yet, keeping Calendar for now"; continue; } ;;
      com.google.android.apps.nbu.files) is_installed org.fossify.filemanager || { warn "Fossify Files not installed yet, keeping Files for now"; continue; } ;;
    esac
    remove_pkg "$p"
  done
  refresh_installed

  head_ "Leftover AI / assistant packages"
  local left
  left=""
  local p
  for p in $(grep -Ei 'gemini|bard|aicore|assistant|intelligence|\.as$|\.as\.oss|creativeassistant|googlequicksearchbox|pixel\.agent|magiccue|journal|essential|glimpse|aura\.|facebook' <<<"$INSTALLED" \
             | grep -vx 'com.google.android.settings.intelligence'); do   # Settings search, not AI
    is_installed "$p" && left+="$p"$'\n'
  done
  left="${left%$'\n'}"
  if [[ -n "$left" ]]; then
    warn "Still installed (remove with: adb shell pm uninstall --user 0 <name>):"
    sed 's/^/      /' <<<"$left"
  else ok "No AI/assistant packages found"; fi
}

# -------------------------------------------------------------- settings -----
# Private DNS in "hostname" mode is strict: on networks that block it, NOTHING resolves.
# So test it, and fall back to Android's automatic mode if names stop working.
check_dns() {
  [[ $DRY == 1 ]] && return 0
  sleep 3
  if [[ "$(ash 'ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1 && echo up')" != up ]]; then
    warn "Phone has no internet right now, so Private DNS can't be tested. Re-run 'settings' later on Wi-Fi."
    return 0
  fi
  if [[ "$(ash 'ping -c 1 -W 5 play.googleapis.com >/dev/null 2>&1 && echo up')" == up ]]; then
    ok "Internet + Private DNS ($DNS_HOST) working"
  else
    warn "Private DNS blocks name lookups on this network. Switching to Automatic so the phone keeps working."
    set_setting global private_dns_mode opportunistic
  fi
}

step_settings() {
  head_ "Network and privacy settings"
  set_setting global private_dns_mode hostname
  set_setting global private_dns_specifier "$DNS_HOST"
  check_dns
  set_setting global wifi_scan_always_enabled 0         # no Wi-Fi scanning while Wi-Fi is off
  set_setting global ble_scan_always_enabled 0          # no Bluetooth scanning while BT is off
  set_setting global wifi_wakeup_enabled 0              # don't auto-enable Wi-Fi near saved networks
  # Connectivity checks: use GrapheneOS's servers instead of Google's (sends no data, just a 204)
  set_setting global captive_portal_http_url  "http://connectivitycheck.grapheneos.network/generate_204"
  set_setting global captive_portal_https_url "https://connectivitycheck.grapheneos.network/generate_204"
  set_setting global captive_portal_fallback_url "http://grapheneos.online/gen_204"
  set_setting global captive_portal_other_fallback_urls "http://grapheneos.online/generate_204"
  set_setting global ntp_server time.cloudflare.com     # time sync without Google's NTP
  set_setting global non_persistent_mac_randomization_force_enabled 1   # new random Wi-Fi MAC per connection (GrapheneOS default)
  set_setting global adb_wifi_enabled 0                 # no wireless debugging
  set_setting secure lock_screen_allow_private_notifications 0   # hide notification content when locked
  set_setting secure lock_screen_lock_after_timeout 0   # lock immediately when the screen turns off
  set_setting system show_password 0
  set_setting secure clock_seconds 1                    # status-bar clock shows seconds (AOSP System UI Tuner setting)
  set_setting system status_bar_show_battery_percent 1  # battery percentage in the status bar
  [[ "$MAKER" == *samsung* ]] && set_setting system display_battery_percentage 1   # Samsung's own switch
  # No animations: windows, transitions and app animations happen instantly (snappier)
  set_setting global window_animation_scale 0
  set_setting global transition_animation_scale 0
  set_setting global animator_duration_scale 0
}

# ---------------------------------------------------------------- camera -----
# The stock camera often opens photos in Google Photos (Pixel Camera ONLY works with it),
# so Photos stays installed but offline, with no location access.
CAMERA_PKG=com.google.android.GoogleCamera
detect_camera() {
  local c
  c="$(ash cmd package resolve-activity --brief -a android.media.action.IMAGE_CAPTURE | tail -1 | cut -d/ -f1)"
  if [[ -n "$c" && "$c" == *.* && "$c" != *"No activity"* ]]; then CAMERA_PKG="$c"
  else case $PROFILE in pixel) CAMERA_PKG=com.google.android.GoogleCamera ;; cmf) CAMERA_PKG=com.nothing.camera ;; esac; fi
  ok "Camera app: $CAMERA_PKG"
  # Pixel Camera ONLY opens photos in Google Photos. Other cameras use the maker's own gallery.
  PHOTOS_NEEDED=1; PHOTO_VIEWER="$PHOTOS_PKG"
  if [[ "$CAMERA_PKG" != com.google.android.GoogleCamera ]]; then
    local sys v
    sys="$(ash pm list packages -s --user 0 | sed 's/^package://')"
    for v in $(ash cmd package query-activities --brief -a com.android.camera.action.REVIEW -t 'image/*' \
               | grep -o '[A-Za-z0-9_.]*/' | tr -d / | sort -u); do
      [[ "$v" == "$PHOTOS_PKG" ]] && continue
      printf '%s\n' "${OEM_PKGS[@]}" | grep -qx "$v" && continue     # being removed (e.g. Nothing Gallery)
      if [[ "$v" == "$CAMERA_PKG" ]] || grep -qx "$v" <<<"$sys"; then PHOTOS_NEEDED=0; PHOTO_VIEWER="$v"; break; fi
    done
    # No maker gallery left: Fossify Gallery opens the camera's photos
    if [[ $PHOTOS_NEEDED == 1 ]] && ash pm list packages org.fossify.gallery | grep -q fossify; then
      PHOTOS_NEEDED=0; PHOTO_VIEWER=org.fossify.gallery
    fi
  fi
  # You can always force-keep Photos via the keep file
  [[ -f "$KEEP_FILE" ]] && grep -qx "$PHOTOS_PKG" "$KEEP_FILE" && PHOTOS_NEEDED=1
  if [[ $PHOTOS_NEEDED == 1 ]]; then ok "Photo viewer: Google Photos (this camera needs it; kept offline)"
  else ok "Photo viewer: $PHOTO_VIEWER (Google Photos isn't needed on this phone)"; fi
}
PHOTOS_PKG=com.google.android.apps.photos
PHOTOS_NEEDED=1; PHOTO_VIEWER=com.google.android.apps.photos
# -------------------------------------------------------------- lock screen --
open_screen() {                                      # open_screen "intent action" ["data uri"]
  [[ $YES == 1 || $DRY == 1 ]] && return 0
  local out
  if [[ -n "${2:-}" ]]; then out="$(ash am start -a "$1" -d "$2")"
  else out="$(ash am start -a "$1")"; fi
  # This phone doesn't have that exact screen: open the main Settings page instead
  [[ "$out" == *Error* || "$out" == *"unable to resolve"* ]] && ash am start -a android.settings.SETTINGS >/dev/null
  return 0
}
GUIDED_DONE=0
# guide "title" "intent" "Pixel path" "Nothing path" "search word" ["uri"]
#   The right instructions for THIS phone are shown. A path of "-" means "this phone doesn't
#   have it" and the step is skipped automatically. Unknown phones get the Settings-search word.
GUIDED_NA=()
guide() {
  local title=$1 action=$2 pix=$3 not=$4 word=$5 uri=${6:-} where=""
  case $PROFILE in
    pixel) [[ "$pix" == "-" ]] && { logline "    guided step not on this phone: $title"; return 0; }; where=$pix ;;
    cmf)   [[ "$not" == "-" ]] && { logline "    guided step not on this phone: $title"; return 0; }; where=$not ;;
  esac
  [[ -z "$where" ]] && where="Settings → tap the search bar → type: $word"
  say "  → $title"
  say "      $where"
  if [[ $YES == 1 || $DRY == 1 ]]; then return 0; fi
  open_screen "$action" "$uri"
  while read -r -t 0.05 -n 10000 _; do :; done          # ignore keys pressed earlier
  local ans
  read -r -p "      [Enter] done   [n] not on this phone   " ans
  if [[ "$ans" == [nN]* ]]; then
    GUIDED_NA+=("$title"); logline "    guided step NOT AVAILABLE on this phone: $title"
  else
    GUIDED_DONE=$((GUIDED_DONE+1)); logline "    guided step confirmed by user: $title"
  fi
}
# search_guide "title" "search word"   (maker-specific extras: always via Settings search)
search_guide() { guide "$1" android.settings.SETTINGS "" "" "$2"; }

# Settings Android only lets YOU change on the phone. Everything that CAN be set over USB
# is set automatically in the settings/lock steps; only these are left.
step_guided() {
  head_ "Settings you change on the phone (each one opens; [Enter] = done, [n] = not on this phone)"
  local sdk; sdk="$(ash getprop ro.build.version.sdk)"

  say ""; say "  ${c_h}Google${c_0}"
  guide "Delete your advertising ID" com.google.android.gms.settings.ADS_PRIVACY \
        "Security & privacy → More privacy settings → Ads → Delete advertising ID" \
        "Google → All services → Ads → Delete advertising ID" "advertising ID"
  guide "Usage & diagnostics OFF (Google's telemetry)" android.settings.SETTINGS \
        "Security & privacy → More privacy settings → Usage & diagnostics → Off" \
        "Google → All services → Usage & diagnostics → Off" "Usage & diagnostics"
  guide "Google Location Accuracy OFF (keep Emergency Location Service ON)" android.settings.LOCATION_SOURCE_SETTINGS \
        "Location → Location services → Google Location Accuracy → Off" \
        "Location → Location services → Google Location Accuracy → Off" "Location Accuracy"
  guide "Find Hub network OFF (or keep it if you want lost-phone tracking)" android.settings.SETTINGS \
        "Security & privacy → Device finders → Find Hub → Find Hub network" \
        "Google → All services → Find Hub → Find Hub network" "Find Hub"
  if is_installed com.google.android.dialer; then
    guide "Phone app: Caller ID & spam OFF (stops sending numbers to Google)" android.settings.SETTINGS \
          "Phone app → ⋮ → Settings → Caller ID & spam → Off" \
          "Phone app → ⋮ → Settings → Caller ID & spam → Off" "Caller ID"
  fi

  say ""; say "  ${c_h}Security${c_0}"
  guide "Theft protection: Theft Detection Lock, Offline Device Lock, Identity Check ON" android.settings.SETTINGS \
        "Security & privacy → Device unlock → Theft protection" \
        "Google → All services → Theft protection" "Theft protection"
  guide "Extend Unlock / Smart Lock OFF (the phone never unlocks itself)" android.settings.SECURITY_SETTINGS \
        "Security & privacy → More security & privacy → Extend Unlock → turn everything off" \
        "Security & privacy → More security & privacy → Extend Unlock (or Smart Lock) → off" "Extend Unlock"
  guide "Allow 2G OFF (blocks fake cell towers)" android.settings.NETWORK_OPERATOR_SETTINGS \
        "Network & internet → SIMs → your SIM → Allow 2G → Off" \
        "Network & internet → SIMs → your SIM → Allow 2G → Off" "2G"
  if [[ "$(ash service check advanced_protection)" == *found* && "$(ash service check advanced_protection)" != *"not found"* ]]; then
    guide "Advanced Protection → Expert features: USB protection ON only (leave 'Unknown apps' OFF to keep sideloading)" \
          android.settings.SECURITY_SETTINGS \
          "Security & privacy → Advanced Protection → Expert features → USB protection" \
          "" "Advanced Protection"
  else
    logline "    Advanced Protection not on this phone (Android $sdk), USB protection step skipped"
  fi

  case "$PROFILE/$MAKER/$BRAND" in
    pixel/*|*google*)
      say ""; say "  ${c_h}Pixel${c_0}"
      guide "Memory Tagging Extension ON (hardware exploit protection), reboot, then re-test Wallet" \
            android.settings.APPLICATION_DEVELOPMENT_SETTINGS \
            "Developer options → Memory Tagging Extension → On (turn off again if an app crashes)" "-" "Memory Tagging" ;;
    cmf/*|*nothing*|*cmf*)
      say ""; say "  ${c_h}Nothing / CMF${c_0}"
      search_guide "Lock Glimpse OFF (internet feed on the lock screen)" "Glimpse"
      search_guide "Nothing's diagnostics / experience-improvement sharing OFF" "diagnostic"
      search_guide "Intelligence toolkit / AI features OFF" "Intelligence"
      search_guide "Essential Key: assign it to something else or turn it off" "Essential Key" ;;
    */samsung*)
      say ""; say "  ${c_h}Samsung${c_0}"
      search_guide "Customization Service OFF (and delete its data)" "Customization Service"
      search_guide "Send diagnostic data OFF" "diagnostic data"
      search_guide "Marketing information OFF" "Marketing"
      search_guide "Galaxy AI: process data only on device; unused features OFF" "Galaxy AI"
      search_guide "Bixby off, side button = power menu" "Bixby"
      say ""
      say "      Auto Blocker: it's off now. Your choice:"
      say "        • leave it OFF: Droid-ify keeps your F-Droid apps (IronFox, HeliBoard, ...) updated"
      say "        • turn it ON: blocks USB attacks and outside apps, but F-Droid apps stop updating"
      say "          (Play Store apps like Signal and Lawnchair keep updating either way)"
      guide "Auto Blocker: decide (see above), recommended OFF if you use F-Droid apps" android.settings.SECURITY_SETTINGS \
            "" "" "Auto Blocker" ;;
    */xiaomi*|*/redmi*|*/poco*|*/*redmi*|*/*poco*)
      say ""; say "  ${c_h}Xiaomi / HyperOS${c_0}"
      search_guide "Personalized ad recommendations OFF" "ad services"
      search_guide "User Experience Program OFF" "User Experience"
      search_guide "Send diagnostic data automatically OFF" "diagnostic"
      search_guide "Authorization & revocation: revoke 'msa' (Xiaomi ads)" "revocation" ;;
    */oneplus*|*/oppo*|*/realme*)
      say ""; say "  ${c_h}OnePlus / Oppo / Realme${c_0}"
      search_guide "User Experience Program OFF" "User Experience"
      search_guide "Personalized recommendations OFF" "recommendations"
      search_guide "Diagnostics / system stability data sharing OFF" "diagnostic" ;;
    */motorola*|*/lenovo*)
      say ""; say "  ${c_h}Motorola${c_0}"
      search_guide "Share product improvement data OFF" "improve" ;;
    */vivo*|*/iqoo*|*/honor*|*/huawei*)
      say ""; say "  ${c_h}${MAKER}${c_0}"
      search_guide "User Experience Improvement Program OFF" "User Experience"
      search_guide "Personalized recommendations OFF" "recommend" ;;
    *)
      say ""; say "  ${c_h}${MAKER:-This phone}${c_0}"
      search_guide "The maker's diagnostics / improvement program OFF" "diagnostic"
      search_guide "Personalized ads / recommendations OFF" "recommend" ;;
  esac
  guided_summary
}
guided_summary() {
  echo
  ok "$GUIDED_DONE settings confirmed by you"
  if [[ ${#GUIDED_NA[@]} -gt 0 ]]; then
    warn "Not on this $DEVICE_NAME (send me this list and the script will skip them next time):"
    printf '      - %s\n' "${GUIDED_NA[@]}"
  fi
}

step_lock() {
  head_ "Lock screen, power menu, NFC and SIM"
  # Set over USB, no questions
  set_setting secure lockscreen_show_wallet 0            # no Wallet button on the lock screen
  set_setting secure lockscreen_show_controls 0          # no smart-home device controls on the lock screen
  set_setting secure lockscreen_allow_trivial_controls 0 # device controls need an unlock
  set_setting secure lockdown_in_power_menu 1            # "Lockdown" button in the power menu
  set_setting global wifi_networks_available_notification_on 0   # no "open Wi-Fi nearby" prompts

  # Only these need you on the phone
  guide "Enhanced PIN privacy ON (hides each digit's animation as you type your PIN)" android.settings.SECURITY_SETTINGS \
        "Security & privacy → Device unlock → Screen lock (⚙) → Enhanced PIN privacy" \
        "" "PIN privacy"
  guide "Require device unlock for NFC ON (tap-to-pay still works once unlocked)" android.settings.NFC_SETTINGS \
        "Connected devices → Connection preferences → NFC → Require device unlock for NFC" \
        "" "NFC"
  guide "Lock screen shortcuts: both set to None" android.settings.SETTINGS \
        "Wallpaper & style → Lock screen → Shortcuts → None / None" \
        "" "shortcuts"
  guide "SIM PIN ON (needs your SIM's current PIN; 3 wrong tries = PUK lock)" android.settings.SECURITY_SETTINGS \
        "Security & privacy → More security & privacy → SIM lock → Lock SIM" \
        "" "SIM lock"
}

step_camera() {
  if [[ $PHOTOS_NEEDED == 0 ]]; then
    head_ "Camera ($CAMERA_PKG): no location; photos open in $PHOTO_VIEWER"
    for perm in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION ACCESS_BACKGROUND_LOCATION; do
      act pm revoke "$CAMERA_PKG" "android.permission.$perm" >/dev/null 2>&1
    done
    act cmd appops set "$CAMERA_PKG" FINE_LOCATION ignore >/dev/null 2>&1
    act cmd appops set "$CAMERA_PKG" COARSE_LOCATION ignore >/dev/null 2>&1
    [[ $DRY == 0 ]] && echo "$CAMERA_PKG" >> "$LOG_HARDENED"
    ok "$CAMERA_PKG: location blocked"
    if is_installed "$PHOTOS_PKG"; then
      say "  Google Photos isn't needed by this camera, so it's disabled:"
      remove_pkg "$PHOTOS_PKG"
    fi
    return 0
  fi
  head_ "Camera ($CAMERA_PKG): no location; Google Photos kept as an offline viewer"
  if ! is_installed "$PHOTOS_PKG"; then
    act cmd package install-existing "$PHOTOS_PKG" >/dev/null
    act pm enable --user 0 "$PHOTOS_PKG" >/dev/null 2>&1
    ok "Google Photos re-enabled (the camera's photo preview needs it)"
    if [[ $DRY == 0 && -f "$LOG_REMOVED" ]]; then
      grep -vxF "$PHOTOS_PKG" "$LOG_REMOVED" > "$LOG_REMOVED.tmp"; mv "$LOG_REMOVED.tmp" "$LOG_REMOVED"
    fi
    refresh_installed
  fi
  for pkg in "$CAMERA_PKG" "$PHOTOS_PKG"; do
    for perm in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION ACCESS_BACKGROUND_LOCATION; do
      act pm revoke "$pkg" "android.permission.$perm" >/dev/null 2>&1
    done
    # appops "ignore" = permanently denied without asking again
    act cmd appops set "$pkg" FINE_LOCATION ignore >/dev/null 2>&1
    act cmd appops set "$pkg" COARSE_LOCATION ignore >/dev/null 2>&1
    [[ $DRY == 0 ]] && echo "$pkg" >> "$LOG_HARDENED"
    ok "$pkg: location blocked"
  done
  # Photos: no background running (it only opens when you tap the thumbnail)
  act cmd appops set "$PHOTOS_PKG" RUN_ANY_IN_BACKGROUND ignore >/dev/null 2>&1
  act am set-standby-bucket "$PHOTOS_PKG" restricted >/dev/null 2>&1
  ok "Google Photos: background activity blocked"
}

# ---------------------------------------------------------------- harden -----
step_harden() {
  head_ "Restricting Google apps you kept"
  local any=0
  for pkg in "${HARDEN_TARGETS[@]}"; do
    is_installed "$pkg" || continue
    is_protected "$pkg" && continue
    any=1
    printf '    restricting %s ... ' "$pkg"
    # One round trip per app instead of 16 (much faster, fewer chances to stall)
    local cmds="cmd appops set $pkg RUN_ANY_IN_BACKGROUND ignore; cmd appops set $pkg RUN_IN_BACKGROUND ignore; am set-standby-bucket $pkg restricted"
    for perm in $HARDEN_PERMS; do cmds+="; pm revoke $pkg android.permission.$perm"; done
    act sh -c "'$cmds' 2>/dev/null; true" >/dev/null
    echo "done"
    [[ $DRY == 0 ]] && echo "$pkg" >> "$LOG_HARDENED"
    ok "restricted $pkg (it will ask again for permissions when you open it)"
  done
  [[ $any == 0 ]] && ok "No user-facing Google apps left to restrict"
}

# --------------------------------------------------------------- restore -----
step_restore() {
  head_ "Restoring"
  if [[ -f "$LOG_DISABLED" ]]; then
    sort -u "$LOG_DISABLED" | while read -r pkg; do
      act pm enable --user 0 "$pkg" >/dev/null && ok "re-enabled $pkg"
    done
  fi
  if [[ -f "$LOG_REMOVED" ]]; then
    sort -u "$LOG_REMOVED" | while read -r pkg; do
      act cmd package install-existing "$pkg" >/dev/null && ok "reinstalled $pkg"
    done
  fi
  if [[ -f "$LOG_HARDENED" ]]; then
    sort -u "$LOG_HARDENED" | while read -r pkg; do
      act cmd appops reset "$pkg" >/dev/null
      act am set-standby-bucket "$pkg" active >/dev/null
      ok "unrestricted $pkg"
    done
  fi
  if [[ -f "$LOG_SETTINGS" ]]; then
    while read -r ns key old; do
      if [[ "$old" == "null" || -z "$old" ]]; then act settings delete "$ns" "$key" >/dev/null
      else act settings put "$ns" "$key" "$old" >/dev/null; fi
      ok "restored $ns/$key"
    done < "$LOG_SETTINGS"
  fi
  if [[ -s "$LOG_ROLES.ime" ]]; then
    local ime; ime="$(cat "$LOG_ROLES.ime")"
    [[ "$ime" != "null" ]] && act ime set "$ime" >/dev/null && ok "restored keyboard"
  fi
  if [[ $DRY == 0 ]]; then
    mkdir -p "$DEV_DIR/old"; mv "$DEV_DIR"/*.txt* "$DEV_DIR/old/" 2>/dev/null
  fi
  say "Replacement apps from F-Droid were left installed. Uninstall them normally if you want."
}

# ------------------------------------------------------- maker telemetry -----
# Uses the community-maintained Universal Android Debloater (UAD-ng) list: ~5,400 packages
# from every brand, each with a description and a safety rating. Only entries rated
# "Recommended" (safe), described as telemetry/analytics/ads/diagnostics, that nothing else
# depends on, and that are actually on this phone, are disabled. Keep rules still apply.
UAD_URL="https://raw.githubusercontent.com/Universal-Debloater-Alliance/universal-android-debloater-next-generation/main/resources/assets/uad_lists.json"
UAD_CACHE="$STATE_DIR/uad_lists.json"

get_uad_list() {
  mkdir -p "$STATE_DIR"
  if [[ ! -s "$UAD_CACHE" ]] || [[ -n "$(find "$UAD_CACHE" -mtime +7 2>/dev/null)" ]]; then
    say "    downloading the UAD-ng package list..."
    curl -fsSL --connect-timeout 15 -m 120 -o "$UAD_CACHE.new" "$UAD_URL" && mv "$UAD_CACHE.new" "$UAD_CACHE" \
      || warn "Couldn't download the UAD-ng list; using the saved copy if there is one"
  fi
  [[ -s "$UAD_CACHE" ]]
}

# Prints "pkg|short description" for telemetry packages present on this phone
telemetry_candidates() {
  local tmp; tmp="$(mktemp)"
  printf '%s\n' "$INSTALLED" > "$tmp"
  python3 -I - "$UAD_CACHE" "$tmp" <<'PY'
import json, re, sys
uad = json.load(open(sys.argv[1]))
installed = set(open(sys.argv[2]).read().split())
tele = re.compile(r'telemetr|analytic|tracking|tracker|diagnos|data collect|collection|collects|usage data|statistic|'
                  r'crash report|bug ?report|log ?collect|logs? service|dumplog|feedback|advertis|\bads\b|spyware|user behavio', re.I)
# never: anything that sounds like a phone function, even if it also mentions logs/feedback
skip = re.compile(r'\bcalls?\b|\bsms\b|call & text|dialer|telephony|\bims\b|volte|wi-?fi calling|accessib|screen reader|'
                  r'keyboard|launcher|camera|gallery|clock|alarm|contacts|messag|update|\bota\b|fota|bootloop|'
                  r'needed for|required for|don.t remove|do not remove|breaks?|soft-?brick|'
                  r'wallet|payment|\bpay\b|secure ?ui|password|fingerprint|biometric|knox|container|peripheral|'
                  r'push|notification service|battery|power|thermal|modem|quality of service|network performance|'
                  r'location provider|fused|bluetooth|ant radio|wi-?fi|esim|backup|sync|calibrat|calendar', re.I)
for pkg, v in sorted(uad.items()):
    if pkg not in installed or v.get('removal') != 'Recommended' or v.get('neededBy'):
        continue
    desc = ' '.join(v.get('description', '').split())
    if tele.search(desc) and not skip.search(desc) and not skip.search(pkg):
        print(f"{pkg}|{desc[:110]}")
PY
  rm -f "$tmp"
}

step_telemetry() {
  head_ "Phone-maker telemetry, analytics and ad services (UAD-ng 'Recommended' list)"
  command -v python3 >/dev/null || { warn "python3 is needed for this step; skipped"; return 0; }
  get_uad_list || { warn "No UAD-ng list available; skipped"; return 0; }
  ensure_keep_file
  refresh_installed
  local keep list go=() pkg desc
  keep="$(compute_keep)"
  list="$(telemetry_candidates)"
  while IFS='|' read -r pkg desc; do
    [[ -z "$pkg" ]] && continue
    if is_protected "$pkg" || grep -qx "$pkg" <<<"$keep" || grep -qEi "$KEEP_PATTERN" <<<"$pkg"; then
      printf '    %bkeep%b    %s (needed on this phone)\n' "$c_ok" "$c_0" "$pkg"; continue
    fi
    go+=("$pkg"); printf '    %b✗%b       %s\n              %s\n' "$c_err" "$c_0" "$pkg" "$desc"
  done <<<"$list"
  if [[ ${#go[@]} == 0 ]]; then ok "No known maker telemetry found on this $DEVICE_NAME"; return 0; fi
  say "  To keep one, add its name to $KEEP_FILE"
  confirm "Disable these ${#go[@]} telemetry/analytics packages? (undo: bash android-lockdown.sh restore)" \
    || { warn "Telemetry step skipped"; return 0; }
  [[ $DRY == 0 ]] && printf '%s\n' "${go[@]}" >> "$DEV_DIR/telemetry-packages.txt"
  for pkg in "${go[@]}"; do remove_pkg "$pkg"; done
  refresh_installed
}

# ----------------------------------------------------------------- sweep -----
# UNIVERSAL: works out from the phone itself which pre-installed drawer apps are needed.
KEEP_FILE="$STATE_DIR/keep-apps.txt"
# Drawer apps whose package name contains one of these words are always kept
# (security centres, permission managers, SIM menus, emergency apps on various brands)
KEEP_PATTERN='settings|systemui|launcher|security|permission|providers|telephony|bluetooth|nfc|keychain|wallet|setupwizard|emergency|\.sos|\.stk|cellbroadcast|documentsui|packageinstaller|webview|framework|update|updater|\.ota|fota|\.dm$|wifi|wlan|network|connectivity|\.ims|carrier|euicc|esim|\.mms|\.phone|dialer|contacts|messaging|incallui|telecom|simsettings|backup'

ensure_keep_file() {
  [[ -f "$KEEP_FILE" ]] && return 0
  mkdir -p "$STATE_DIR"
  cat > "$KEEP_FILE" <<'EOK'
# Apps the sweep must NEVER disable, one package name per line (applies to every phone).
# Find names with:  bash android-lockdown.sh scan
# Examples (remove the # in front to keep them):
#com.google.android.calculator
#com.sec.android.app.popupcalculator
EOK
}

# Package names this phone needs, one per line (asked from the phone, so it works on any brand)
compute_keep() {
  {
    printf '%s\n' $NEVER_TOUCH $KEEP_ALWAYS $KEEP_EXTRA
    printf '%s\n' "${FDROID_APPS[@]%%|*}" "${PLAY_APPS[@]%%|*}" "$IRONFOX_PKG" "${LAUNCHER_PKG:-}"
    echo "$CAMERA_PKG"
    local r
    # whatever this phone uses for calls, SMS, home screen and browser
    for r in DIALER SMS HOME BROWSER; do ash cmd role get-role-holders "android.app.role.$r" | tr ';, ' '\n\n\n'; done
    # every launcher, the gallery the camera opens, the alarm clock, the contacts app
    ash cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME | grep -o '[A-Za-z0-9_.]*/' | tr -d /
    ash cmd package query-activities --brief -a com.android.camera.action.REVIEW -t 'image/*' | grep -o '[A-Za-z0-9_.]*/' | tr -d /
    ash cmd package query-activities --brief -a android.intent.action.SET_ALARM | grep -o '[A-Za-z0-9_.]*/' | tr -d /
    ash cmd package query-activities --brief -a android.intent.action.INSERT -t vnd.android.cursor.dir/contact | grep -o '[A-Za-z0-9_.]*/' | tr -d /
    # the keyboard in use
    ash settings get secure default_input_method | cut -d/ -f1
    # your own keep list
    [[ -f "$KEEP_FILE" ]] && grep -vE '^[[:space:]]*(#|$)' "$KEEP_FILE"
    [[ $PHOTOS_NEEDED == 1 ]] && echo "$PHOTOS_PKG"
  } | grep -vxF -f <(printf '%s\n' "${OEM_PKGS[@]}") | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -E '^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)+$' \
    | { if [[ $PHOTOS_NEEDED == 1 ]]; then cat; else grep -vx "$PHOTOS_PKG"; fi; } | sort -u
}

# Prints "pkg|reason" for every pre-installed drawer app: remove / WAIT / keep
sweep_candidates() {
  local drawer system pkg repl keep
  keep="$(compute_keep)"
  drawer="$(ash cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER \
            | grep -o '[A-Za-z0-9_.]*/' | tr -d / | sort -u)"
  system="$(ash pm list packages -s --user 0 | sed 's/^package://')"
  for pkg in $drawer; do
    grep -qx "$pkg" <<<"$system" || continue                     # installed by you: never touched
    is_protected "$pkg" && { echo "$pkg|keep"; continue; }
    # Apps with a privacy replacement go as soon as the replacement is installed
    repl="$(grep "^$pkg|" <<<"$SWEEP_NEEDS_REPLACEMENT" | cut -d'|' -f2)"
    if [[ -n "$repl" ]]; then
      if is_installed "$repl"; then echo "$pkg|remove"; else echo "$pkg|WAIT: kept until $repl is installed"; fi
      continue
    fi
    if grep -qx "$pkg" <<<"$keep" || grep -qEi "$KEEP_PATTERN" <<<"$pkg"; then echo "$pkg|keep"; continue; fi
    echo "$pkg|remove"
  done
}

step_sweep() {
  head_ "Universal sweep: every pre-installed app in the app drawer that isn't needed"
  ensure_keep_file
  say "  Kept automatically: whatever this phone uses for calls, SMS, contacts, camera, the"
  say "  camera's gallery, alarms, home screen, keyboard and browser; Wallet, Play Store, Settings,"
  say "  security/SIM/emergency apps, your privacy apps, and EVERY app you installed yourself."
  say "  Hidden system parts are not touched. Extra keeps: $KEEP_FILE"
  local list go=() line pkg why
  list="$(sweep_candidates)"
  while IFS='|' read -r pkg why; do
    [[ -z "$pkg" ]] && continue
    case "$why" in
      remove) go+=("$pkg") ;;
      keep)   printf '    %bkeep%b    %s\n' "$c_ok" "$c_0" "$pkg" ;;
      *)      printf '    %bwait%b    %s (%s)\n' "$c_warn" "$c_0" "$pkg" "${why#WAIT: }" ;;
    esac
  done <<<"$list"
  if [[ ${#go[@]} -gt 0 ]]; then
    say "  Will be disabled (data wiped):"
    for pkg in "${go[@]}"; do printf '    %b✗%b       %s\n' "$c_err" "$c_0" "$pkg"; done
    say "  To keep one, add its name to $KEEP_FILE and run: bash android-lockdown.sh sweep"
  fi
  if [[ ${#go[@]} == 0 ]]; then ok "Nothing left to sweep"; return; fi
  confirm "Disable/remove these ${#go[@]} apps? (undo any time with: bash android-lockdown.sh restore)" \
    || { warn "Sweep skipped"; return; }
  for pkg in "${go[@]}"; do remove_pkg "$pkg"; done
  refresh_installed
}

# ---------------------------------------------------------------- verify -----
# Reads the phone's ACTUAL state and reports PASS/FAIL. Nothing is changed.
step_verify() {
  head_ "Verifying the phone's actual state"
  local all en dis fails=0 pkg st
  all="$(ash pm list packages --user 0 | sed 's/^package://')"
  en="$(ash pm list packages -e --user 0 | sed 's/^package://')"
  dis="$(ash pm list packages -d --user 0 | sed 's/^package://')"
  local P="${c_ok}PASS${c_0}" F="${c_err}FAIL${c_0}"

  say "  Google apps / AI / telemetry (should be removed or disabled):"
  local tele=""; [[ -f "$DEV_DIR/telemetry-packages.txt" ]] && tele="$(sort -u "$DEV_DIR/telemetry-packages.txt")"
  for pkg in "${TIER1[@]}" "${TELEMETRY[@]}" "${OEM_PKGS[@]}" "${AI_PKGS[@]}" "$GOOGLE_APP" "${TIER2[@]}" "$GBOARD" $tele; do
    if ! grep -qx "$pkg" <<<"$all"; then continue          # never on this phone / removed
    elif grep -qx "$pkg" <<<"$dis"; then st="$P  disabled"
    elif grep -qx "$pkg" <<<"$en"; then st="$F  STILL ACTIVE"; fails=$((fails+1))
    else st="$P  removed"; fi
    printf '    %b  %s\n' "$st" "$pkg"
  done

  say "  Other pre-installed apps still in the app drawer (the sweep removes these):"
  local leftover=0 why
  while IFS='|' read -r pkg why; do
    [[ -z "$pkg" ]] && continue
    if [[ "$why" == remove ]]; then printf '    %b  %s still active\n' "$F" "$pkg"; fails=$((fails+1)); leftover=1
    elif [[ "$why" == WAIT* ]]; then printf '    %b  %s (%s)\n' "${c_warn}WAIT${c_0}" "$pkg" "${why#WAIT: }"; fi
  done <<<"$(sweep_candidates)"
  [[ $leftover == 0 ]] && printf '    %b  only kept apps left\n' "$P"

  say "  Must stay enabled (tap-to-pay, calls, camera):"
  for pkg in com.google.android.gms com.android.vending com.google.android.apps.walletnfcrel \
             com.google.android.dialer com.google.android.apps.messaging "$CAMERA_PKG" \
             "$( [[ $PHOTOS_NEEDED == 1 ]] && echo "$PHOTOS_PKG" || echo "$PHOTO_VIEWER" )"; do
    if grep -qx "$pkg" <<<"$en"; then printf '    %b  %s\n' "$P" "$pkg"
    else printf '    %b  %s is not enabled\n' "$F" "$pkg"; fails=$((fails+1)); fi
  done

  say "  Defaults:"
  local v
  v="$(ash cmd role get-role-holders android.app.role.ASSISTANT)"
  [[ -z "${v//[[:space:]]/}" ]] && printf '    %b  no assistant app\n' "$P" || { printf '    %b  assistant app: %s\n' "$F" "$v"; fails=$((fails+1)); }
  v="$(ash cmd role get-role-holders android.app.role.HOME)"
  if [[ "$v" == *"$LAUNCHER_PKG"* ]]; then printf '    %b  home screen: Lawnchair\n' "$P"
  else printf '    %b  home screen: %s (run: bash android-lockdown.sh launcher)\n' "$F" "${v:-none}"; fails=$((fails+1)); fi
  v="$(ash cmd role get-role-holders android.app.role.BROWSER)"
  [[ "$v" == *ironfox* ]] && printf '    %b  browser: %s\n' "$P" "$v" || { printf '    %b  browser: %s\n' "$F" "$v"; fails=$((fails+1)); }
  v="$(ash settings get secure default_input_method)"
  [[ "$v" == helium314* ]] && printf '    %b  keyboard: HeliBoard\n' "$P" || { printf '    %b  keyboard: %s\n' "$F" "$v"; fails=$((fails+1)); }

  say "  Settings:"
  v="$(ash settings get global private_dns_mode)"
  case "$v" in
    hostname)      printf '    %b  Private DNS: %s (tracker blocking on)\n' "$P" "$DNS_HOST" ;;
    opportunistic) printf '    %b  Private DNS: Automatic (fallback, %s was blocked on your network)\n' "${c_warn}INFO${c_0}" "$DNS_HOST" ;;
    *)             printf '    %b  Private DNS: %s\n' "$F" "$v"; fails=$((fails+1)) ;;
  esac
  local line ns key want
  while read -r ns key want; do
    [[ -z "$ns" ]] && continue
    v="$(ash settings get "$ns" "$key")"
    [[ "$v" == "$want" ]] && printf '    %b  %s/%s = %s\n' "$P" "$ns" "$key" "$v" \
      || { printf '    %b  %s/%s = %s (want %s)\n' "$F" "$ns" "$key" "$v" "$want"; fails=$((fails+1)); }
  done <<EOV
global private_dns_specifier $DNS_HOST
global wifi_scan_always_enabled 0
global ble_scan_always_enabled 0
global captive_portal_https_url https://connectivitycheck.grapheneos.network/generate_204
global ntp_server time.cloudflare.com
secure lock_screen_allow_private_notifications 0
secure lockscreen_show_wallet 0
secure assist_long_press_home_enabled 0
global power_button_long_press 1
EOV

  say "  Camera location:"
  local campkgs="$CAMERA_PKG"; [[ $PHOTOS_NEEDED == 1 ]] && campkgs+=" $PHOTOS_PKG"
  for pkg in $campkgs; do
    v="$(ash cmd appops get "$pkg" FINE_LOCATION)"
    [[ "$v" == *ignore* || "$v" == *deny* ]] && printf '    %b  %s: location blocked\n' "$P" "$pkg" \
      || { printf '    %b  %s: location %s\n' "$F" "$pkg" "${v:-unknown}"; fails=$((fails+1)); }
  done

  say "  Phone still works:"
  local role holder
  local label
  for role in DIALER SMS HOME; do
    case $role in DIALER) label="phone (calls)";; SMS) label="SMS";; HOME) label="home screen";; esac
    holder="$(ash cmd role get-role-holders "android.app.role.$role" | tr -d '[:space:]')"
    if [[ -n "$holder" ]] && grep -qx "$holder" <<<"$en"; then printf '    %b  %s app: %s\n' "$P" "$label" "$holder"
    else printf '    %b  no working %s app (%s)\n' "$F" "$label" "${holder:-none}"; fails=$((fails+1)); fi
  done
  for pkg in com.google.android.ims com.android.phone com.android.providers.telephony com.android.cellbroadcastreceiver \
             com.google.android.cellbroadcastreceiver com.android.server.telecom com.google.android.euicc \
             com.android.vending com.google.android.gms com.google.android.gsf com.google.android.webview \
             com.google.android.apps.walletnfcrel com.android.nfc com.android.settings com.android.systemui; do
    grep -qx "$pkg" <<<"$all" || continue                      # not on this phone
    grep -qx "$pkg" <<<"$en" && printf '    %b  %s\n' "$P" "$pkg" || { printf '    %b  %s is DISABLED\n' "$F" "$pkg"; fails=$((fails+1)); }
  done
  # anything update-related must be enabled (system + app updates)
  local upd; upd="$(grep -Ei 'update|updater|\.ota|fota' <<<"$dis")"
  [[ -z "$upd" ]] && printf '    %b  system/app updaters enabled\n' "$P" || { printf '    %b  updater disabled: %s\n' "$F" "$upd"; fails=$((fails+1)); }
  if [[ "$(ash 'ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1 && echo up')" == up ]]; then
    printf '    %b  internet reachable\n' "$P"
    [[ "$(ash 'ping -c 1 -W 5 play.googleapis.com >/dev/null 2>&1 && echo up')" == up ]] && printf '    %b  name lookups (DNS) working\n' "$P" \
      || { printf '    %b  DNS NOT working (run: bash android-lockdown.sh settings)\n' "$F"; fails=$((fails+1)); }
  else
    printf '    %b  no internet right now (Wi-Fi/data off?), connectivity not tested\n' "${c_warn}SKIP${c_0}"
  fi
  local sim; sim="$(ash getprop gsm.sim.state)"
  printf '    %b  SIM state: %s\n' "$( [[ "$sim" == *READY* ]] && echo "$P" || echo "${c_warn}INFO${c_0}")" "${sim:-unknown}"

  say "  Boot:"
  v="$(ash getprop ro.boot.verifiedbootstate)"
  [[ "$v" == green ]] && printf '    %b  verified boot green, bootloader locked\n' "$P" || { printf '    %b  verified boot: %s\n' "$F" "$v"; fails=$((fails+1)); }

  echo
  if [[ $fails == 0 ]]; then ok "Everything checked is in place."
  else warn "$fails check(s) FAILED. Send this output and we'll fix each one."; fi
}

# ------------------------------------------------------------------ scan -----
# Lists every app in the app drawer and what the script does with it. Changes nothing.
step_scan() {
  head_ "Apps in the app drawer on this $DEVICE_NAME"
  local drawer pkg tag known_remove known_mine
  drawer="$(ash cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER \
            | grep / | sed 's/^[[:space:]]*//' | cut -d/ -f1 | sort -u)"
  known_remove="$(printf '%s\n' "${TIER1[@]}" "${TELEMETRY[@]}" "${OEM_PKGS[@]}" "${AI_PKGS[@]}" "$GOOGLE_APP" "${TIER2[@]}" "$GBOARD")"
  known_mine="$(printf '%s\n' "${FDROID_APPS[@]%%|*}" "${PLAY_APPS[@]%%|*}" "$IRONFOX_PKG")"
  local review=0
  for pkg in $drawer; do
    if   grep -qx "$pkg" <<<"$known_remove"; then tag="${c_err}remove${c_0}   (on the script's list)"
    elif grep -qx "$pkg" <<<"$known_mine";   then tag="${c_ok}yours${c_0}    (privacy app installed by the script)"
    elif grep -qx "$pkg" <<<"$NEVER_TOUCH" || [[ "$pkg" == "$CAMERA_PKG" || "$pkg" == "$PHOTO_VIEWER" ]]; then
                                               tag="${c_ok}keep${c_0}     (needed: payments, calls, camera or system)"
    else tag="${c_warn}REVIEW${c_0}   (not on any list yet)"; review=$((review+1)); fi
    printf '    %-48s %b\n' "$pkg" "$tag"
  done
  head_ "Phone-maker / preload packages (including hidden ones)"
  local all en; all="$(ash pm list packages --user 0 | sed 's/^package://')"; en="$(ash pm list packages -e --user 0 | sed 's/^package://')"
  for pkg in $(grep -Ei '^com\.(nothing|cmf)\.|aura|facebook|glimpse|essential' <<<"$all" | sort); do
    grep -qx "$pkg" <<<"$en" && tag="enabled" || tag="disabled"
    printf '    %-48s %s\n' "$pkg" "$tag"
  done
  echo
  [[ $review -gt 0 ]] && warn "$review app(s) marked REVIEW. Send this output (or latest.log) to decide what to do with them." \
                      || ok "Every app in the drawer is accounted for."
}

step_status() {
  head_ "Status"
  [[ -f "$LOG_REMOVED" ]]  && say "Removed:    $(sort -u "$LOG_REMOVED" | wc -l | tr -d ' ') packages"
  [[ -f "$LOG_HARDENED" ]] && say "Restricted: $(sort -u "$LOG_HARDENED" | wc -l | tr -d ' ') apps"
  [[ -f "$LOG_SETTINGS" ]] && say "Settings changed: $(wc -l < "$LOG_SETTINGS" | tr -d ' ')"
  say "Private DNS: $(ash settings get global private_dns_specifier)"
  say "Keyboard:    $(ash settings get secure default_input_method)"
  say "Boot state:  $(ash getprop ro.boot.verifiedbootstate)"
}

# ----------------------------------------------------- manual checklist ------
device_# After an interactive run the settings were already walked through, so only
# app setup is left. With --yes / --dry-run the full manual list is printed instead.
checklist() {
  if [[ $YES == 1 || $DRY == 1 || $GUIDED_DONE == 0 ]]; then checklist_full; return; fi
  head_ "Done. Last steps on the phone"
  cat <<'EOC'
   1. TEST TAP-TO-PAY: Wallet → card shows "Ready to tap" → make a small payment.
   2. Restart the phone, then check long-press home / "Hey Google" do nothing.
   3. Open each new app once:
      • Droid-ify: let it sync; add the IronFox repo (Settings → Repositories → +):
          https://fdroid.ironfoxoss.org/fdroid/repo
      • Ente Auth: move your 2FA codes in, turn on its encrypted backup.
      • Signal: Settings → Privacy → Screen lock + Registration Lock ON.
      • IronFox: open once (uBlock Origin and hardening are built in).
      • Google Photos: backup OFF. Camera app: "Save location" OFF.
   4. RethinkDNS → Firewall: block internet for apps that don't need it
      (Photos, Camera, Calculator, ...). NEVER block Play Services or Wallet.
   5. Shelter: create the work profile for any Google app you still need.
   6. Sideloading later: Developer options → "advanced flow" once,
      or always:  bash android-lockdown.sh install app.apk
   7. On a computer or in IronFox: myaccount.google.com/connections → remove apps you
      don't use, and myaccount.google.com → Data & privacy → pause Web & App Activity,
      Timeline and YouTube history; Personalized ads OFF.
   8. Developer options → USB debugging OFF.
   Any time later (e.g. after a system update):  bash android-lockdown.sh verify
EOC
}

checklist_full() {
  case $PROFILE in
    pixel) cat <<'EOD'

  PIXEL 10a EXTRAS
   2. Hardware memory tagging (MTE). The Pixel 10a supports it (GrapheneOS's top hardening).
      Developer options → Memory Tagging Extension → On → reboot.
      Then re-test Wallet. If any app crashes, turn it back off.
   • Open Auditor (GrapheneOS app) → pair with a second phone, or use remote
     attestation to verify the OS hasn't been tampered with.
EOD
    ;;
    cmf) cat <<'EOD'

  CMF PHONE 2 PRO / NOTHING OS EXTRAS  (menu names vary a little between Nothing OS versions)
   2. Lock Glimpse OFF: Settings → Lock screen → Lock Glimpse → Off.
      It fills the lock screen with feed content fetched from the internet.
   • Essential Key: Settings → Essential Key → assign it to something else or turn it off
     (Essential Space, its AI app, has been disabled).
   • Settings → Intelligence toolkit: turn off every AI feature listed there.
   • Settings → System → find "Experience improvement" / "Share diagnostics data" /
     "Usage & diagnostics" → Off (this is Nothing's own telemetry, separate from Google's).
   • If you keep the Nothing Launcher: Home settings → turn off the Discover / Google News feed.
   • Not available on this phone: hardware memory tagging (MediaTek chip) and Auditor.
EOD
    ;;
    *) cat <<'EOD'

  THIS PHONE HAS NO DEDICATED PROFILE
   • Run './android-lockdown.sh scan' and send the output to get the maker's extras added.
EOD
    ;;
  esac
}

checklist() {
  head_ "Done. Finish on the phone (ADB can't change these)"
  cat <<'EOF2'
  FIRST
   1. TEST TAP-TO-PAY: Wallet → card shows "Ready to tap" → make a small payment.
EOF2
  device_checklist
  cat <<'EOF2'

  GRAPHENEOS-STYLE SECURITY
   3. USB lockdown (charge-only while locked), if your phone has Advanced Protection:
      Security & privacy → Advanced Protection → "expert features" → USB protection ON,
      Unknown apps OFF. If your build has no expert features, full Advanced
      Protection also blocks sideloading; your call.
      Also: Developer options → Default USB configuration → "No data transfer".
   4. Theft protection (Security & privacy → Device unlock → Theft protection):
      Identity Check ON, Theft Detection Lock ON, Offline Device Lock ON.
   4b. If you ran with --yes, do these yourself (otherwise the script already walked you through them):
      Enhanced PIN privacy ON · NFC → Require device unlock ON · Lock screen Shortcuts → None ·
      SIM lock ON · myaccount.google.com/connections → remove unused apps.
   5. Screen lock: use a 6+ digit PIN or a password. Turn OFF Extend Unlock / Smart Lock.
      Turn ON "Lockdown" in the power menu (turns off fingerprint unlock until you enter the PIN).
   6. Network → SIMs → "Allow 2G" OFF. Wi-Fi → "Notify for public networks" OFF.

  GRAPHENEOS-STYLE PRIVACY
   8. Privacy → Ads → Delete advertising ID.  Usage & diagnostics → Off.
   9. Location → Location services → Google Location Accuracy → Off,
      Emergency Location Service stays ON.  Find Hub → Find Hub network → Off (or "with network in all areas" if you want tracking).
  10. myaccount.google.com → Data & privacy: pause Web & App Activity, Timeline,
      YouTube history; Personalized ads OFF.
  11. Google → Backup → off (or keep it; device backups are end-to-end encrypted).
  12. Wallet → Settings → personalization / data from other Google products → OFF.
  13. Phone app → Settings → Caller ID & spam → Off (stops sending numbers to Google).
  14. Network permission per app (GrapheneOS "Network" toggle):
      RethinkDNS → Firewall → block every app that doesn't need internet.
      NEVER block Google Play Services or Wallet.
  15. Sensors permission: Developer options → Quick settings developer tiles →
      "Sensors Off" → add it to Quick Settings.
  16. Profiles (GrapheneOS secondary users): open Shelter → create the work profile →
      clone in any Google apps you still need, and freeze them when you're not using them.
      Keep Wallet + banking in the main profile.

  SIDELOADING
  17. Developer options → turn on the "advanced flow" once (restart + 24 h wait), or
      always install with:  ./android-lockdown.sh install app.apk

  CAMERA / PHOTOS
   • Open Google Photos once. If it asks about backup, choose not to back up
     (or Photos → profile icon → Photos settings → Backup → Off).
   • RethinkDNS → Firewall → block internet for Google Photos AND Pixel Camera.
     Photos then works purely as an offline viewer for the camera.
   • Pixel Camera → Settings → "Save location" → Off (belt and braces).

  APPS
   • Open Droid-ify once and let it sync. From then on it updates all the apps above.
     Also add the IronFox repo there (Settings → Repositories → +) so IronFox updates too:
     https://fdroid.ironfoxoss.org/fdroid/repo
   • Ente Auth: move your 2FA codes in (it can import from Google Authenticator),
     then turn on its encrypted backup or export a backup.
   • Signal: Settings → Privacy → turn on Screen lock and Registration Lock (PIN).

  BROWSER
   • Open IronFox once to finish setup. It comes with uBlock Origin and
     hardened settings, so there's nothing else to configure. To verify the app, compare
     its signing key in AppVerifier with C5:E2:91:B5:...:F9:04 (ironfoxoss.org).

  AI / "HEY GOOGLE"
  18. Settings → System → Gestures → Press & hold power button → "Power menu"
      (instead of the assistant).  Settings → Google → Gemini/Assistant → "Hey Google" OFF
      (only needed if you kept the Google app).

  LAST
  19. Developer options → USB debugging OFF.
EOF2
}

# ------------------------------------------------------------------ main -----
MODE="all"; ARGS=()
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --yes|-y)  YES=1 ;;
    *)         ARGS+=("$a") ;;
  esac
done
[[ ${#ARGS[@]} -gt 0 ]] && MODE="${ARGS[0]}"
setup_logging

case "$MODE" in
  all)
    preflight
    pause "Before starting, check that Wallet works and that your photos are backed up"
    step_apps
    step_debloat
    step_telemetry
    step_sweep
    step_camera
    step_settings
    step_lock
    step_guided
    step_harden
    step_verify
    step_scan
    checklist
    ;;
  apps)     preflight; step_apps; step_verify ;;
  debloat)  preflight; step_debloat; step_telemetry; step_sweep; step_verify ;;
  telemetry) preflight; step_telemetry; step_verify ;;
  verify)   preflight; step_verify ;;
  scan)     preflight; step_scan ;;
  sweep)    preflight; step_sweep; step_verify ;;
  settings) preflight; step_settings; step_verify ;;
  lock)     preflight; step_lock; guided_summary; step_verify ;;
  manual)   preflight; step_lock; step_guided ;;
  launcher) preflight; refresh_installed; step_launcher; step_verify ;;
  harden)   preflight; step_harden; step_verify ;;
  camera)   preflight; step_camera; step_verify ;;
  restore)  preflight; step_restore ;;
  status)   preflight; step_status ;;
  install)
    ensure_adb; wait_for_phone
    [[ ${#ARGS[@]} -gt 1 ]] || die "Usage: $0 install app1.apk [app2.apk ...]"
    for apk in "${ARGS[@]:1}"; do echo -n "$apk: "; adb_install "$apk" | tail -1; done
    ;;
  *) die "Unknown mode '$MODE'. Use: all | apps | launcher | debloat | telemetry | sweep | manual | verify | scan | camera | settings | lock | harden | install | status | restore" ;;
esac#!/usr/bin/env bash
# =============================================================================
#  android-lockdown.sh: one-shot GrapheneOS-style lockdown for a STOCK phone
#  that keeps Google Wallet tap-to-pay working. Detects the phone automatically:
#    - Google Pixel 10a      ("stallion")
#    - CMF Phone 2 Pro       ("Galaga", Nothing OS)
#    - anything else: Google apps/AI/settings still work, phone extras are skipped
#  Each phone gets its own backups + logs, so one PC can manage several phones.
#
#  You don't need to unlock or root. Everything goes through ADB:
#    - "pm uninstall --user 0" hides apps without touching the system image,
#      so the Play Integrity checks still pass and Wallet keeps working.
#    - Everything is logged and can be undone with:  ./android-lockdown.sh restore
#    - A factory reset always brings the phone back to stock.
#
#  USAGE
#    ./android-lockdown.sh                 # do EVERYTHING (asks before risky steps)
#    ./android-lockdown.sh all --yes       # everything, no questions
#    ./android-lockdown.sh all --dry-run   # show what would happen, change nothing
#
#    Individual steps:
#    ./android-lockdown.sh apps            # install privacy replacement apps (F-Droid)
#    ./android-lockdown.sh debloat         # remove Google apps + telemetry
#    ./android-lockdown.sh settings        # network/privacy settings
#    ./android-lockdown.sh manual          # walk through every setting you change by hand (Google, security,
#                                        #   and the phone maker's own telemetry/ad switches, any brand)
#    ./android-lockdown.sh lock            # lock screen, NFC unlock, SIM PIN, Google account access
#    ./android-lockdown.sh harden          # restrict any Google apps you kept
#    ./android-lockdown.sh camera          # camera without GPS, Photos as offline viewer
#    ./android-lockdown.sh install x.apk   # sideload over ADB (skips developer verification)
#    ./android-lockdown.sh verify          # check the phone's ACTUAL state (PASS/FAIL), changes nothing
#    ./android-lockdown.sh sweep           # disable EVERY pre-installed drawer app that isn't needed (works on any brand;
#                                        #   keeps calls/SMS/camera/gallery/alarms/launcher/Wallet/Play and every
#                                        #   app you installed; extra keeps: lockdown-state/keep-apps.txt)
#    ./android-lockdown.sh telemetry       # disable the phone maker's telemetry/analytics/ads (UAD-ng list, any brand)
#    ./android-lockdown.sh scan            # list every app in the app drawer and what the script does with it
#    ./android-lockdown.sh status          # show what's been done
#    ./android-lockdown.sh restore         # undo everything
#
#  NEEDS on the computer: bash, curl, python3. adb is downloaded automatically
#         from Google if it's missing. Mac/Linux: run in Terminal. Windows: use Git Bash.
#  NEEDS on the phone: USB debugging on (the script walks you through it).
#
#  LOGS: every run writes a timestamped log of everything shown on screen PLUS every
#        command sent to the phone and the phone's answer:
#          lockdown-state/logs/run-<date>-<mode>.log   (latest.log = newest)
#        Watch live in a second terminal:  tail -f lockdown-state/logs/latest.log
#        Every run that changes something ends with a full PASS/FAIL check of the phone.
#
#  DO NOT turn on Advanced Protection afterwards. It blocks sideloading.
# =============================================================================

set -u

# ----------------------------------------------------------------- config ----
DNS_HOST="dns.adguard-dns.com"     # or your NextDNS: abc123.dns.nextdns.io

# F-Droid download mirrors, tried in order (f-droid.org itself is often slow).
# Init7 is in Switzerland, FAU in Germany. All are official F-Droid mirrors.
FDROID_MIRRORS="https://mirror.init7.net/fdroid/repo https://ftp.fau.de/fdroid/repo https://f-droid.org/repo"

STATE_DIR="./lockdown-state"
TMP_DIR="$STATE_DIR/apk-cache"
# Per-phone backup files (set once the phone is identified, see set_device_paths)
DEV_DIR="$STATE_DIR/unknown-device"
set_device_paths() {
  DEV_DIR="$STATE_DIR/$1"
  LOG_REMOVED="$DEV_DIR/removed-packages.txt"
  LOG_DISABLED="$DEV_DIR/disabled-packages.txt"
  LOG_HARDENED="$DEV_DIR/hardened-packages.txt"
  LOG_SETTINGS="$DEV_DIR/settings-backup.txt"
  LOG_ROLES="$DEV_DIR/defaults-backup.txt"
}
set_device_paths unknown-device
PROFILE="generic"; DEVICE_NAME="Android phone"; MAKER=""; BRAND=""

# NEVER touched by this script (tap-to-pay, calls, SMS, eSIM, core system):
NEVER_TOUCH="
com.google.android.gms
com.google.android.gsf
com.android.vending
com.google.android.apps.walletnfcrel
com.android.nfc
com.google.android.webview
com.google.android.permissioncontroller
com.google.android.ext.services
com.google.android.networkstack
com.google.android.packageinstaller
com.google.android.documentsui
com.google.android.setupwizard
com.google.android.cellbroadcastreceiver
com.google.android.euicc
com.google.android.ims
com.google.android.dialer
com.google.android.contacts
com.google.android.apps.messaging
com.google.android.GoogleCamera
com.google.android.apps.nexuslauncher
com.google.android.apps.wallpaper
com.nothing.launcher
com.nothing.camera
com.android.camera
com.android.settings
com.android.systemui
com.android.phone
com.android.providers.telephony
com.nothing.ntfactorytest
com.nothing.factorytool
"

# ------------------------------------------------- replacement apps (F-Droid)
# package id | what it replaces
FDROID_APPS=(
  "com.looker.droidify|Droid-ify app store (F-Droid client; keeps everything below updated)"
  "io.ente.auth|Ente Auth (2FA codes, end-to-end encrypted backup)"
  "helium314.keyboard|HeliBoard keyboard (replaces Gboard)"
  "app.organicmaps|Organic Maps (replaces Google Maps)"
  "org.fossify.gallery|Fossify Gallery (replaces Photos)"
  "org.fossify.filemanager|Fossify File Manager (replaces Files)"
  "org.fossify.calendar|Fossify Calendar (replaces Google Calendar)"
  "com.fsck.k9|K-9 Mail (replaces Gmail)"
  "net.typeblog.shelter|Shelter (sandboxed work profile)"
  "com.celzero.bravedns|RethinkDNS (per-app firewall)"
  "org.fossify.clock|Fossify Clock (replaces the Google Clock; alarms, timer)"
  "org.fossify.math|Fossify Calculator (replaces the Google Calculator)"
)

# Play Store-only apps: the script opens their Play pages for you to tap Install
#   Auditor: GrapheneOS's own hardware attestation app; works on stock Pixels
PLAY_APPS=(
  "app.lawnchair.play|Lawnchair launcher (looks like the Pixel Launcher, no Google search bar)"
  "org.thoughtcrime.securesms|Signal (private messaging; Play version updates itself)"
  "app.attestation.auditor|Auditor by GrapheneOS (verifies the OS hasn't been tampered with)"
)
BROWSER_PKGS="org.ironfoxoss.ironfox org.mozilla.fennec_fdroid"

# IronFox: hardened Firefox with no telemetry. It comes from IronFox's own F-Droid repo,
# and the script checks the download against IronFox's published signing key.
IRONFOX_PKG="org.ironfoxoss.ironfox"
IRONFOX_REPOS="https://fdroid.ironfoxoss.org/fdroid/repo https://gitlab.com/ironfox-oss/fdroid/-/raw/main/fdroid/repo https://codeberg.org/ironfox-oss/fdroid/raw/branch/main/fdroid/repo"
IRONFOX_CERT="C5E291B5A571F9C8CD9A9799C2C94E02EC9703948893F2CA756D67B94204F904"

# ------------------------------------------------- packages to remove --------
TIER1=(
  com.google.android.youtube                 # YouTube
  com.google.android.apps.youtube.music      # YouTube Music
  com.google.android.apps.tachyon            # Meet
  com.google.android.videos                  # Google TV
  com.google.android.apps.subscriptions.red  # Google One
  com.google.android.apps.docs               # Drive
  com.google.android.apps.magazines          # Google News
  com.google.android.apps.podcasts           # Podcasts
  com.google.android.keep                    # Keep
  com.google.android.apps.tips               # Pixel Tips
  com.google.android.apps.restore            # Data restore tool (setup only)
  com.google.android.projection.gearhead     # Android Auto
  com.google.ar.core                         # ARCore
  com.google.android.apps.chromecast.app     # Google Home
  com.google.android.apps.wellbeing          # Digital Wellbeing
  com.google.android.apps.turbo              # Device Health Services
  com.google.android.partnersetup            # Partner setup
  com.google.android.apps.docs.editors.docs  # Google Docs
  com.google.android.apps.translate          # Google Translate
  com.google.android.apps.weather            # Pixel Weather
  com.google.android.apps.wear.companion     # Pixel Watch app
  com.fitbit.FitbitMobile                    # Fitbit / Health
  com.google.android.apps.pixel.aurelius     # Pixel Journal
  com.google.android.apps.pixel.nowplaying   # Now Playing history
  com.google.android.apps.credentialmanager  # "Passwords" (Google Password Manager app)
)

TELEMETRY=(
  com.google.mainline.telemetry              # Mainline module telemetry
  com.google.android.feedback                # Feedback / crash reports
)

# Replaced apps
TIER2=(   # always removed (each one waits for its replacement)
  com.android.chrome                         # -> Fennec
  com.google.android.gm                      # -> K-9 Mail
  com.google.android.apps.maps               # -> Organic Maps
  com.google.android.calendar                # -> Fossify Calendar
  com.google.android.apps.nbu.files          # -> Fossify File Manager
  com.google.android.apps.recorder           # Recorder
  com.google.android.apps.safetyhub          # Personal Safety (loses crash detection)
  com.google.android.apps.adm                # Find Hub app (service stays in Play Services)
  com.google.android.tts                     # Speech Services (loses text-to-speech)
)

# ALL AI: always removed, no prompt
AI_PKGS=(
  com.google.android.apps.bard               # Gemini
  com.google.android.apps.googleassistant    # Assistant
  com.google.android.aicore                  # AICore: on-device Gemini Nano runtime
  com.google.android.as                      # Android System Intelligence (Now Playing,
                                             #   Live Caption, smart replies, Magic Cue)
  com.google.android.as.oss                  # Private Compute Services (feeds the AI features)
  com.google.android.apps.pixel.creativeassistant  # Pixel Studio (AI image generator)
  com.google.assistant.hubui                 # Assistant / Gemini hub UI
  com.google.android.apps.labs.language.tailwind  # NotebookLM
  com.google.android.googlequicksearchbox.nga_resources  # "Next-gen Assistant" voice resources
)
# ---------------------------------------------------------- app drawer sweep --
# The sweep disables EVERY pre-installed app in the app drawer that isn't listed here.
# Apps you installed yourself (banking apps etc.) are never touched.
# Hidden system packages are never touched by the sweep (that can stop the phone booting).
KEEP_ALWAYS="
com.android.settings
com.android.vending
com.google.android.apps.walletnfcrel
com.google.android.dialer
com.google.android.apps.messaging
com.google.android.contacts
com.android.stk
com.google.android.documentsui
com.android.documentsui
"
# Add your own: packages to keep even though they're pre-installed (space separated)
KEEP_EXTRA=""
# Pre-installed apps that are only swept once their replacement is installed
#   pre-installed app | replacement
SWEEP_NEEDS_REPLACEMENT="
com.google.android.deskclock|org.fossify.clock
com.google.android.calculator|org.fossify.math
com.android.chrome|org.ironfoxoss.ironfox
com.google.android.gm|com.fsck.k9
com.google.android.apps.maps|app.organicmaps
com.google.android.calendar|org.fossify.calendar
com.google.android.apps.nbu.files|org.fossify.filemanager
"

# Phone-maker extras (packages that don't exist on a phone are skipped automatically)
OEM_PKGS=(
  # CMF Phone 2 Pro / Nothing OS
  com.aura.oobe.solutions                    # "AppServices" (Aura): pushes app installs; comes back if uninstalled
  com.nothing.ntessentialspace               # Essential Space (AI, sends content to cloud AI models)
  com.nothing.ntessentialrecorder            # Essential Space recorder (AI summaries)
  com.nothing.weather                        # Nothing Weather
  com.nothing.aiwidget                       # AI widget
  com.nothing.essentialintelligence          # AI engine behind Essential Space / AI features
  com.nothing.experience                     # "Experience" framework: usage data collection
  com.nothing.logkit                         # hidden log collection tool
  com.nothing.enginnerservice                # hidden diagnostics service
  com.nothing.experimental                   # experimental features
  com.nothing.smartcenter                    # Nothing X (earbuds companion; reinstall from Play if you use Nothing earbuds)
  com.nothing.agreement                      # privacy-policy / agreement prompts
  com.nothing.games                          # games launcher
  com.nothing.ntgamedashboard                # game dashboard overlay
  com.nothing.userguide                      # user guide
  com.nothing.introduction16                 # "what's new" intro tour
  com.nothing.user.center                    # Nothing account / community centre
  com.nothing.universal.search               # Nothing Launcher search (web suggestions)
  com.nothing.gallery                        # Nothing Gallery (photos then open in Fossify Gallery)
  com.facebook.appmanager                    # Facebook preload services (some regions)
  com.facebook.services
  com.facebook.system
  com.facebook.katana                        # Facebook app (some regions)
)
# These must be disabled, never uninstalled (they reinstall themselves after an uninstall)
DISABLE_ONLY="com.aura.oobe.solutions"

# The Google app is removed too (it handles "Hey Google", Circle to Search, the Gemini overlay)
# Removed only after the replacement is the active default:
GBOARD=com.google.android.inputmethod.latin
GOOGLE_APP=com.google.android.googlequicksearchbox

# Google apps to restrict if you KEEP them (background off + permissions reset)
HARDEN_TARGETS=(
  com.google.android.googlequicksearchbox com.google.android.apps.maps
  com.android.chrome com.google.android.youtube
  com.google.android.gm com.google.android.apps.docs com.google.android.calendar
  com.google.android.keep com.google.android.apps.tachyon com.google.android.apps.bard
  com.google.android.apps.youtube.music com.google.android.videos
  com.google.android.apps.magazines com.google.android.apps.subscriptions.red
  com.google.android.apps.nbu.files com.google.android.apps.recorder
  com.google.android.apps.chromecast.app
)
HARDEN_PERMS="ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION ACCESS_BACKGROUND_LOCATION
RECORD_AUDIO CAMERA READ_CONTACTS READ_CALL_LOG READ_SMS READ_PHONE_STATE
BODY_SENSORS ACTIVITY_RECOGNITION NEARBY_WIFI_DEVICES BLUETOOTH_SCAN"

# ------------------------------------------------------------- helpers -------
DRY=0; YES=0
c_ok=$'\e[32m'; c_warn=$'\e[33m'; c_err=$'\e[31m'; c_h=$'\e[1;36m'; c_0=$'\e[0m'
say()  { echo "$*"; }
ok()   { echo "${c_ok}  ✓${c_0} $*"; }
warn() { echo "${c_warn}  !${c_0} $*" >&2; }
die()  { echo "${c_err}Error:${c_0} $*" >&2; exit 1; }
head_() { echo; echo "${c_h}== $* ==${c_0}"; }

# If the USB link stalls, restart adb and wait for the phone again
adb_recover() {
  warn "USB connection stalled, restarting adb..."
  adb kill-server >/dev/null 2>&1; sleep 2; adb start-server >/dev/null 2>&1
  local i; for i in $(seq 1 30); do
    [[ "$(adb get-state 2>/dev/null)" == "device" ]] && timeout 10 adb shell true </dev/null >/dev/null 2>&1 && return 0
    sleep 2
  done
  die "Phone stopped responding. Unplug and replug it, keep it unlocked, then run the script again (finished steps are skipped)."
}
# adb shell with a timeout + one automatic recovery; no stdin, CR stripped
ash() {
  local out rc
  out="$(timeout 30 adb shell "$@" </dev/null 2>&1)"; rc=$?
  if [[ $rc == 124 ]]; then adb_recover; out="$(timeout 30 adb shell "$@" </dev/null 2>&1)"; fi
  printf '%s\n' "$out" | tr -d '\r'
}
# adb install: copy to the phone first (--no-streaming), with a timeout + one recovery
adb_install() {
  local apk=$1 out rc
  logline "    \$ adb install --no-streaming -r $apk"
  out="$(timeout 180 adb install --no-streaming -r "$apk" </dev/null 2>&1)"; rc=$?
  if [[ $rc == 124 ]]; then
    warn "Install timed out. If the phone shows a Play Protect popup, tap Install anyway."
    adb_recover
    out="$(timeout 180 adb install --no-streaming -r "$apk" </dev/null 2>&1)"
  fi
  logout "$out"
  printf '%s\n' "$out"
}
# ---------------------------------------------------------------- logging ---
RUN_LOG=""
# fd 3 = the log writer. Screen output (via tee) and command details share it, so they stay in order.
logline() { [[ -n "$RUN_LOG" ]] && printf '%s\n' "$*" >&3; return 0; }
logout()  { [[ -n "$RUN_LOG" && -n "$1" ]] && printf '%s\n' "$1" | sed 's/^/        → /' >&3; return 0; }
stamp() {                                            # timestamp + strip colours for the log file
  if awk 'BEGIN{strftime()}' 2>/dev/null; then
    awk '{ gsub(/\033\[[0-9;]*m/, ""); print strftime("[%Y-%m-%d %H:%M:%S]"), $0; fflush() }'
  else
    while IFS= read -r l; do printf '[%s] %s\n' "$(date '+%F %T')" "$(sed 's/\x1b\[[0-9;]*m//g' <<<"$l")"; done
  fi
}
setup_logging() {
  mkdir -p "$STATE_DIR/logs"
  RUN_LOG="$(cd "$STATE_DIR/logs" && pwd)/run-$(date +%Y%m%d-%H%M%S)-$MODE.log"
  : > "$RUN_LOG"
  ln -sfn "$RUN_LOG" "$STATE_DIR/logs/latest.log"
  # Everything shown on screen also goes to the log file, live
  exec 3> >(stamp >> "$RUN_LOG")
  exec > >(tee /dev/fd/3) 2>&1
  say "Log file: $RUN_LOG"
  say "  (watch it live in another terminal: tail -f $STATE_DIR/logs/latest.log)"
  logline "=== pixel-debloat.sh mode=$MODE dry_run=$DRY yes=$YES ==="
  trap 'logline "=== finished (exit $?) ==="; echo; echo "Full log: $RUN_LOG"' EXIT
}

act() {                                              # state-changing adb shell, logged
  if [[ $DRY == 1 ]]; then echo "    [dry-run] adb shell $*"; logline "    [dry-run] adb shell $*"; return 0; fi
  logline "    \$ adb shell $*"
  local out; out="$(ash "$@")"
  logout "$out"
  [[ -n "$out" ]] && printf '%s\n' "$out"
  return 0
}
confirm() {                                          # confirm "question"
  [[ $YES == 1 || $DRY == 1 ]] && return 0
  read -r -p "  ? $1 [y/N] " a; [[ "$a" =~ ^[Yy] ]]
}
pause() {
  [[ $YES == 1 || $DRY == 1 ]] && return 0
  while read -r -t 0.05 -n 10000 _; do :; done   # throw away Enter presses typed earlier
  read -r -p "  → $1 (press Enter) " _
}

refresh_installed() { INSTALLED="$(ash pm list packages -e --user 0 | sed 's/^package://')"; }   # enabled apps only
DRY_GONE=""                                          # packages a dry run "removed"
is_installed() { grep -qx "$1" <<<"$INSTALLED" && ! grep -qx "$1" <<<"$DRY_GONE"; }
is_protected() { grep -qx "$1" <<<"$NEVER_TOUCH"; }

remove_pkg() {
  local pkg=$1
  is_protected "$pkg" && { warn "$pkg is protected, skipping"; return; }
  is_installed "$pkg" || return 0
  local out=""
  [[ " $DISABLE_ONLY " == *" $pkg "* ]] || out="$(act pm uninstall --user 0 "$pkg")"
  if [[ $DRY == 1 || "$out" == Success* ]]; then
    ok "removed $pkg"
    if [[ $DRY == 1 ]]; then DRY_GONE+="$pkg"$'\n'; else echo "$pkg" >> "$LOG_REMOVED"; fi
    return 0
  fi
  # Android 17 blocks uninstalling system apps over ADB. Disabling still works:
  # the app can't run, has no network, sends nothing, and vanishes from the app drawer.
  # Its data is wiped first.
  act pm clear --user 0 "$pkg" >/dev/null 2>&1
  out="$(act pm disable-user --user 0 "$pkg")"
  if [[ "$out" == *disabled* ]]; then
    ok "disabled $pkg (data wiped)"
    echo "$pkg" >> "$LOG_DISABLED"
  else
    warn "$pkg: couldn't remove or disable ($out)"
  fi
}

set_setting() {                                      # set_setting ns key value
  local ns=$1 key=$2 val=$3 old
  old="$(ash settings get "$ns" "$key")"
  if [[ $DRY == 0 ]] && ! grep -q "^$ns $key " "$LOG_SETTINGS" 2>/dev/null; then
    echo "$ns $key $old" >> "$LOG_SETTINGS"
  fi
  act settings put "$ns" "$key" "$val" >/dev/null
  if [[ $DRY == 1 ]]; then ok "$ns/$key = $val"; return; fi
  local now; now="$(ash settings get "$ns" "$key")"
  if [[ "$now" == "$val" ]]; then ok "$ns/$key = $val"
  else warn "$ns/$key did NOT change (phone says: $now)"; fi
}

# ------------------------------------------------------------ preflight ------
# Get adb: use the one on this computer, or download Google's official platform-tools
ensure_adb() {
  command -v adb >/dev/null && { ok "adb found: $(command -v adb)"; return 0; }
  local here; here="$(cd "$(dirname "$0")" && pwd)"
  if [[ -x "$here/platform-tools/adb" || -x "$here/platform-tools/adb.exe" ]]; then
    export PATH="$here/platform-tools:$PATH"; ok "Using downloaded platform-tools"; return 0
  fi
  local os
  case "$(uname -s)" in
    Linux*)  os=linux ;;
    Darwin*) os=darwin ;;
    MINGW*|MSYS*|CYGWIN*) os=windows ;;
    *) die "Unknown OS. Install Android platform-tools yourself: https://developer.android.com/tools/releases/platform-tools" ;;
  esac
  say "  Downloading Google's Android platform-tools (adb) for $os..."
  local zip="$here/platform-tools.zip"
  curl -fL --progress-bar --retry 3 --retry-delay 2 --connect-timeout 20 --speed-limit 20000 --speed-time 30 -o "$zip" "https://dl.google.com/android/repository/platform-tools-latest-$os.zip" \
    || die "Download failed. Check your internet connection."
  if command -v unzip >/dev/null; then unzip -q -o "$zip" -d "$here"
  else python3 -c 'import sys,zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$zip" "$here"
       chmod +x "$here/platform-tools/"* 2>/dev/null; fi
  rm -f "$zip"
  export PATH="$here/platform-tools:$PATH"
  command -v adb >/dev/null || die "Couldn't set up adb."
  ok "platform-tools installed next to the script"
}

wait_for_phone() {
  # Linux: adb's libusb driver can stall after a few seconds (seen with adb 37 on Arch).
  # Use the kernel's native USB driver instead, and restart the adb server so it applies.
  if [[ "$(uname -s)" == Linux* ]]; then
    export ADB_LIBUSB="${ADB_LIBUSB:-0}"
    adb kill-server >/dev/null 2>&1
  fi
  adb start-server >/dev/null 2>&1
  _wait_for_phone || return 1
  # Make sure the phone actually answers commands (catches half-authorized connections)
  if ! timeout 15 adb shell true </dev/null >/dev/null 2>&1; then
    die "The phone is connected but doesn't answer. Run: adb kill-server, revoke USB debugging authorizations on the phone, replug, tap Allow (tick 'Always allow'), then run the script again."
  fi
}
# Is a Samsung plugged in over USB (even if adb can't see it)?
samsung_on_usb() {
  if command -v lsusb >/dev/null; then lsusb 2>/dev/null | grep -qi '04e8:\|samsung'; return; fi
  if command -v system_profiler >/dev/null; then system_profiler SPUSBDataType 2>/dev/null | grep -qi samsung; return; fi
  return 1
}
samsung_unblock_help() {
  say ""
  say "  ${c_warn}A Samsung phone is plugged in, but it isn't accepting commands from this computer.${c_0}"
  say "  ${c_warn}That's Samsung's 'Auto Blocker': it blocks USB commands AND apps from outside${c_0}"
  say "  ${c_warn}Google Play / Galaxy Store. It can only be switched off on the phone itself:${c_0}"
  say "    1. Settings → Security and privacy → Auto Blocker → Off"
  say "       (if a 'turn back on after 30 minutes' option appears, choose NOT to, the script"
  say "        needs more time and F-Droid apps need it off to update)"
  say "    2. Settings → About phone → Software information → tap 'Build number' 7 times"
  say "    3. Settings → Developer options → USB debugging ON (no longer greyed out)"
  say "    4. Unplug and replug, unlock the phone, tap 'Allow'"
}

_wait_for_phone() {
  local n; n="$(adb devices 2>/dev/null | grep -cE '\s(device|unauthorized)$')"
  if [[ "${n:-0}" -gt 1 && -z "${ANDROID_SERIAL:-}" ]]; then
    die "More than one phone is plugged in. Unplug one (or run: ANDROID_SERIAL=<serial> bash android-lockdown.sh ...)."
  fi
  local state; state="$(adb get-state 2>&1)"
  [[ "$state" == "device" ]] && { ok "Phone connected and authorized"; return 0; }
  say ""
  say "  ${c_warn}Waiting for your phone...${c_0}"
  say "    1. Phone: Settings → About phone → tap 'Build number' 7 times"
  say "    2. Settings → System → Developer options → USB debugging ON"
  say "    3. Plug in the USB cable, unlock the phone, tap 'Allow' on the"
  say "       'Allow USB debugging?' popup (tick 'Always allow from this computer')"
  local i shown_samsung=0
  for i in $(seq 1 120); do
    sleep 2
    state="$(adb get-state 2>&1)"
    [[ "$state" == "device" ]] && { ok "Phone connected and authorized"; return 0; }
    # A Samsung that USB sees but adb doesn't = Auto Blocker / USB debugging greyed out
    if [[ $shown_samsung == 0 && $i -ge 3 && "$state" != *unauthorized* ]] && samsung_on_usb; then
      samsung_unblock_help; shown_samsung=1
    fi
    if [[ "$state" == *unauthorized* && $((i % 10)) == 1 ]]; then
      say "    → Phone found, but tap 'Allow' on the phone screen"
    fi
  done
  die "No phone after 4 minutes. Check the cable (it must carry data, not just charge) and try again."
}

check_tools() {
  command -v curl >/dev/null || die "curl is missing. Install it and run again."
  if ! command -v python3 >/dev/null; then
    warn "python3 missing: apps from F-Droid can't be downloaded automatically."
    case "$(uname -s)" in
      Darwin*) say "      Install with: xcode-select --install" ;;
      Linux*)  say "      Install with your package manager, e.g. sudo apt install python3" ;;
      *)       say "      Install from https://www.python.org/downloads/" ;;
    esac
    confirm "Continue without automatic app installs?" || exit 1
  fi
}

preflight() {
  head_ "Preflight"
  check_tools
  ensure_adb
  wait_for_phone
  mkdir -p "$STATE_DIR" "$TMP_DIR"
  local model vbs sdk
  model="$(ash getprop ro.product.model)"
  vbs="$(ash getprop ro.boot.verifiedbootstate)"
  sdk="$(ash getprop ro.build.version.sdk)"
  ok "Device: $model (SDK $sdk)"
  local codename serial
  codename="$(ash getprop ro.product.device)"
  local lc; lc="$(tr '[:upper:]' '[:lower:]' <<<"$codename")"
  serial="$(adb get-serialno 2>/dev/null | tr -d '\r')"
  case "$lc" in
    stallion) PROFILE=pixel; DEVICE_NAME="Pixel 10a"; ok "Pixel 10a (stallion) detected" ;;
    galaga*)  PROFILE=cmf;   DEVICE_NAME="CMF Phone 2 Pro"; ok "CMF Phone 2 Pro (Galaga, Nothing OS) detected" ;;
    *)
      PROFILE=generic; DEVICE_NAME="$model"
      warn "$model ($codename) has no dedicated profile. Google apps, AI, settings and checks still apply;"
      warn "phone-maker extras are skipped. Run './android-lockdown.sh scan' afterwards to review leftovers."
      confirm "Continue?" || exit 1 ;;
  esac
  # Separate backups per phone, so restore only ever touches this phone
  set_device_paths "$lc-${serial:-unknown}"
  mkdir -p "$DEV_DIR"
  # One-time move of backups made by the old Pixel-only script
  if [[ $PROFILE == pixel && -d ./pixel-lockdown-state && ! -s "$LOG_DISABLED" && ! -s "$LOG_SETTINGS" ]]; then
    cp ./pixel-lockdown-state/*.txt* "$DEV_DIR/" 2>/dev/null && ok "Imported backups from the old pixel-lockdown-state folder"
  fi
  MAKER="$(ash getprop ro.product.manufacturer | tr '[:upper:]' '[:lower:]')"
  BRAND="$(ash getprop ro.product.brand | tr '[:upper:]' '[:lower:]')"
  ok "Maker: ${MAKER:-unknown} (brand: ${BRAND:-unknown})"
  [[ "$MAKER" == *samsung* ]] && ok "Samsung Auto Blocker is off (USB commands work), so apps can be installed"
  logline "device: $DEVICE_NAME model=$model codename=$codename serial=$serial sdk=$sdk profile=$PROFILE maker=$MAKER brand=$BRAND"
  ok "Backups for this phone: $DEV_DIR"
  detect_camera
  if [[ "$vbs" == "green" ]]; then ok "Bootloader locked + verified boot green (Wallet-compatible)"
  else warn "Verified boot state is '$vbs'. Wallet tap-to-pay will not work on this phone anyway."; fi
  refresh_installed
  is_installed com.google.android.apps.walletnfcrel && ok "Google Wallet present" || warn "Google Wallet not installed"
  is_installed com.google.android.gms || die "Play Services missing. Don't run this on a de-Googled phone."
  [[ $DRY == 1 ]] && warn "DRY RUN: nothing will be changed"
}

# ------------------------------------------------------- F-Droid installer ---
fdroid_install() {                                   # fdroid_install pkg label
  local pkg=$1 label=$2
  if is_installed "$pkg"; then ok "$label: already installed"; return 0; fi
  if [[ $DRY == 1 ]]; then echo "    [dry-run] download + install $pkg"; return 0; fi
  command -v curl >/dev/null || { warn "curl missing, can't install $pkg"; return 1; }
  local codes
  # Ask the F-Droid API for the newest version codes (several when there's one APK per CPU type)
  codes="$(curl -fsSL "https://f-droid.org/api/v1/packages/$pkg" 2>/dev/null | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
p=d.get("packages") or []
if p:
    top=p[0].get("versionName")
    print(" ".join(str(x["versionCode"]) for x in p if x.get("versionName")==top))
elif d.get("suggestedVersionCode"): print(d["suggestedVersionCode"])
' 2>/dev/null)"
  [[ -n "$codes" ]] || { warn "$label: not found on F-Droid, install it manually"; return 1; }
  local vc out
  local mirror got
  for vc in $codes; do
    got=0
    for mirror in $FDROID_MIRRORS; do
      say "    downloading $label from ${mirror#https://}..."
      if curl -fL --progress-bar --retry 2 --retry-delay 2 --connect-timeout 15 --speed-limit 200000 --speed-time 15 \
           -o "$TMP_DIR/$pkg.apk" "$mirror/${pkg}_${vc}.apk"; then got=1; break; fi
      warn "slow or unavailable, trying the next mirror"
    done
    [[ $got == 1 ]] || continue
    say "    installing on the phone..."
    out="$(adb_install "$TMP_DIR/$pkg.apk")"
    if [[ "$out" == *Success* ]]; then ok "$label"; return 0; fi
  done
  warn "$label: install failed ($(tail -1 <<<"$out"))"; return 1
}

ironfox_install() {
  if is_installed "$IRONFOX_PKG"; then ok "IronFox: already installed"; return 0; fi
  if [[ $DRY == 1 ]]; then echo "    [dry-run] download + verify + install IronFox"; return 0; fi
  local repo apk="$TMP_DIR/ironfox.apk" info name sha
  for repo in $IRONFOX_REPOS; do
    # Pick the newest arm64 build from the repo index (v2 format, falls back to v1)
    info="$( { curl -fsSL "$repo/index-v2.json" 2>/dev/null || curl -fsSL "$repo/index-v1.json" 2>/dev/null; } | python3 -c '
import json,sys
pkg="org.ironfoxoss.ironfox"
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
c=[]
p=d.get("packages",{}).get(pkg)
if isinstance(p,dict):                      # index-v2
    for v in p.get("versions",{}).values():
        m=v.get("manifest",{}); f=v.get("file",{})
        c.append((m.get("versionCode",0), m.get("nativecode") or [], f.get("name",""), f.get("sha256","")))
elif isinstance(p,list):                    # index-v1
    for v in p:
        c.append((v.get("versionCode",0), v.get("nativecode") or [], "/"+v.get("apkName",""), v.get("hash","")))
c=[x for x in c if x[2] and (not x[1] or "arm64-v8a" in x[1])]
if c:
    best=max(c,key=lambda x:x[0]); print(best[2].lstrip("/"), best[3])
' 2>/dev/null)"
    [[ -n "$info" ]] || continue
    name="${info%% *}"; sha="${info#* }"
    say "    downloading IronFox from $repo ..."
    curl -fL --progress-bar --retry 3 --retry-delay 2 --connect-timeout 20 --speed-limit 20000 --speed-time 30 -o "$apk" "$repo/$name" || continue
    if [[ -n "$sha" ]] && ! { sha256sum "$apk" 2>/dev/null || shasum -a 256 "$apk"; } | grep -qi "^$sha"; then
      warn "IronFox download checksum mismatch from $repo, trying next mirror"; continue
    fi
    if command -v apksigner >/dev/null; then
      if apksigner verify --print-certs "$apk" 2>/dev/null | tr -d ':' | grep -qi "SHA-256 digest $IRONFOX_CERT"; then
        ok "IronFox signature verified"
      else warn "IronFox signing certificate doesn't match. NOT installing."; return 1; fi
    fi
    say "    installing on the phone..."
    if adb_install "$apk" | grep -q Success; then ok "IronFox installed"; return 0; fi
  done
  # Fallback: add IronFox's repo to Droid-ify (it checks the repo signature itself)
  warn "Couldn't download IronFox automatically. Add its repo in Droid-ify instead:"
  say  "      Droid-ify → Settings → Repositories → +"
  say  "      Address:     https://fdroid.ironfoxoss.org/fdroid/repo"
  say  "      Fingerprint: $IRONFOX_CERT"
  act am start -a android.intent.action.VIEW \
    -d "fdroidrepos://fdroid.ironfoxoss.org/fdroid/repo?fingerprint=$IRONFOX_CERT" >/dev/null
  pause "In Droid-ify: add the repo, install IronFox, then come back here"
  refresh_installed
}

step_apps() {
  head_ "Installing privacy replacement apps (F-Droid repo, managed by Droid-ify)"
  # Stop Play Protect from pausing each USB install with a popup (normal Play Protect stays on)
  set_setting global verifier_verify_adb_installs 0
  for entry in "${FDROID_APPS[@]}"; do
    fdroid_install "${entry%%|*}" "${entry#*|}"
  done
  refresh_installed
  ironfox_install

  head_ "Play Store apps (install these on the phone)"
  local need=0
  for entry in "${PLAY_APPS[@]}"; do
    local pkg="${entry%%|*}" label="${entry#*|}"
    if [[ "$pkg" == app.attestation.auditor && $PROFILE != pixel ]]; then continue; fi   # Auditor doesn't support this phone
    if is_installed "$pkg"; then ok "$label: already installed"; continue; fi
    need=1
    act am start -a android.intent.action.VIEW -d "market://details?id=$pkg" >/dev/null
    say "    opened Play Store: $label"
    pause "Tap Install on the phone, then come back here"
  done
  [[ $need == 1 ]] && refresh_installed
  step_launcher
  detect_camera          # re-check now that Fossify Gallery may be installed
}

# ---------------------------------------------------- default app switching --
set_default_keyboard() {
  is_installed helium314.keyboard || return 1
  local id cur
  id="$(ash ime list -a -s | grep '^helium314\.keyboard/' | head -1)"
  [[ -n "$id" ]] || return 1
  [[ $DRY == 0 && ! -s "$LOG_ROLES.ime" ]] && ash settings get secure default_input_method > "$LOG_ROLES.ime"
  act ime enable "$id" >/dev/null; act ime set "$id" >/dev/null
  [[ $DRY == 1 ]] && return 0
  cur="$(ash settings get secure default_input_method)"
  [[ "$cur" == "$id" ]]
}
BROWSER=""
pick_browser() { local b; for b in $BROWSER_PKGS; do is_installed "$b" && { BROWSER=$b; return 0; }; done; return 1; }
set_default_browser() {
  pick_browser || return 1
  act cmd role add-role-holder android.app.role.BROWSER "$BROWSER" >/dev/null
  [[ $DRY == 1 ]] && return 0
  ash cmd role get-role-holders android.app.role.BROWSER | grep -q "$BROWSER"
}
LAUNCHER_PKG=app.lawnchair.play
set_default_launcher() {
  is_installed "$LAUNCHER_PKG" || return 1
  [[ $DRY == 1 ]] && { act cmd role add-role-holder android.app.role.HOME "$LAUNCHER_PKG"; return 0; }
  # The proper way (home-screen role), then the older way as a fallback
  act cmd role add-role-holder android.app.role.HOME "$LAUNCHER_PKG" >/dev/null
  if ! ash cmd role get-role-holders android.app.role.HOME | grep -q "$LAUNCHER_PKG"; then
    local comp
    comp="$(ash cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME \
            | grep -o "${LAUNCHER_PKG//./\\.}/[^ ]*" | head -1)"
    [[ -n "$comp" ]] && act cmd package set-home-activity "$comp" >/dev/null
  fi
  ash cmd role get-role-holders android.app.role.HOME | grep -q "$LAUNCHER_PKG"
}
step_launcher() {
  head_ "Home screen: Lawnchair"
  if ! is_installed "$LAUNCHER_PKG"; then
    warn "Lawnchair isn't installed yet. Install it from the Play Store, then run: bash android-lockdown.sh launcher"
    return 0
  fi
  if set_default_launcher; then ok "Lawnchair is the default home screen"
  else warn "Couldn't set it automatically: Settings → Apps → Default apps → Home app → Lawnchair"; fi
}

# --------------------------------------------------------------- debloat -----
step_debloat() {
  head_ "Removing Google apps (safe tier)"
  for p in "${TIER1[@]}"; do remove_pkg "$p"; done

  head_ "Removing telemetry packages"
  for p in "${TELEMETRY[@]}"; do remove_pkg "$p"; done

  head_ "Removing $DEVICE_NAME extras (phone-maker apps, AI, app installers)"
  local any_oem=0
  for p in "${OEM_PKGS[@]}"; do
    is_installed "$p" || continue
    any_oem=1
    # galleries only go once Fossify Gallery is there to open the camera's photos
    if [[ "$p" == *gallery* ]] && ! is_installed org.fossify.gallery; then
      warn "$p kept until Fossify Gallery is installed (the camera needs a photo viewer)"; continue
    fi
    remove_pkg "$p"
  done
  [[ $any_oem == 0 ]] && ok "None found on this phone"

  head_ "Removing ALL AI (Gemini, Assistant, AICore, \"Hey Google\", Circle to Search)"
  for p in "${AI_PKGS[@]}"; do remove_pkg "$p"; done
  if is_installed "$GOOGLE_APP"; then
    if set_default_launcher; then ok "Lawnchair is the default launcher"
    else warn "Stock launcher stays; its Google search bar will stop working (install Lawnchair)"; fi
    remove_pkg "$GOOGLE_APP"
  fi

  head_ "Turning off assistant gestures (long-press home / power button)"
  act cmd role clear-role-holders android.app.role.ASSISTANT >/dev/null 2>&1
  local holder; holder="$(ash cmd role get-role-holders android.app.role.ASSISTANT)"
  if [[ -z "${holder//[[:space:]]/}" || $DRY == 1 ]]; then ok "No default assistant app"
  else warn "Assistant is still set to: $holder (Settings → Apps → Default apps → Digital assistant app → None)"; fi
  set_setting secure assist_long_press_home_enabled 0
secure clock_seconds 1
system status_bar_show_battery_percent 1
global window_animation_scale 0
global transition_animation_scale 0
global animator_duration_scale 0
secure lockdown_in_power_menu 1
global wifi_networks_available_notification_on 0
  set_setting secure assist_touch_gesture_enabled 0
  set_setting global power_button_long_press 1          # 1 = power menu (not the assistant)

  head_ "Keyboard: Gboard -> HeliBoard (Gboard has Gemini built in)"
  if is_installed "$GBOARD"; then
    if set_default_keyboard; then ok "HeliBoard is now the default keyboard"; remove_pkg "$GBOARD"
    else warn "HeliBoard isn't active, so Gboard stays (removing it could leave you with no keyboard)"; fi
  else ok "Gboard already gone"; fi

  head_ "Removing Chrome, Gmail, Maps, Calendar, Files, Recorder, Speech, Personal Safety, Find Hub app"
  if is_installed com.android.chrome; then
    if set_default_browser; then ok "$BROWSER is the default browser"; else warn "Couldn't set default browser; set it in Settings → Apps → Default apps"; fi
  fi
  # Each app is only removed once its replacement is installed, so you're never left without one
  for p in "${TIER2[@]}"; do
    case "$p" in
      com.android.chrome)              pick_browser || { warn "IronFox not installed yet, keeping Chrome for now"; continue; } ;;
      com.google.android.gm)           is_installed com.fsck.k9 || { warn "K-9 not installed yet, keeping Gmail for now"; continue; } ;;
      com.google.android.apps.maps)    is_installed app.organicmaps || { warn "Organic Maps not installed yet, keeping Maps for now"; continue; } ;;
      com.google.android.calendar)     is_installed org.fossify.calendar || { warn "Fossify Calendar not installed yet, keeping Calendar for now"; continue; } ;;
      com.google.android.apps.nbu.files) is_installed org.fossify.filemanager || { warn "Fossify Files not installed yet, keeping Files for now"; continue; } ;;
    esac
    remove_pkg "$p"
  done
  refresh_installed

  head_ "Leftover AI / assistant packages"
  local left
  left=""
  local p
  for p in $(grep -Ei 'gemini|bard|aicore|assistant|intelligence|\.as$|\.as\.oss|creativeassistant|googlequicksearchbox|pixel\.agent|magiccue|journal|essential|glimpse|aura\.|facebook' <<<"$INSTALLED" \
             | grep -vx 'com.google.android.settings.intelligence'); do   # Settings search, not AI
    is_installed "$p" && left+="$p"$'\n'
  done
  left="${left%$'\n'}"
  if [[ -n "$left" ]]; then
    warn "Still installed (remove with: adb shell pm uninstall --user 0 <name>):"
    sed 's/^/      /' <<<"$left"
  else ok "No AI/assistant packages found"; fi
}

# -------------------------------------------------------------- settings -----
# Private DNS in "hostname" mode is strict: on networks that block it, NOTHING resolves.
# So test it, and fall back to Android's automatic mode if names stop working.
check_dns() {
  [[ $DRY == 1 ]] && return 0
  sleep 3
  if [[ "$(ash 'ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1 && echo up')" != up ]]; then
    warn "Phone has no internet right now, so Private DNS can't be tested. Re-run 'settings' later on Wi-Fi."
    return 0
  fi
  if [[ "$(ash 'ping -c 1 -W 5 play.googleapis.com >/dev/null 2>&1 && echo up')" == up ]]; then
    ok "Internet + Private DNS ($DNS_HOST) working"
  else
    warn "Private DNS blocks name lookups on this network. Switching to Automatic so the phone keeps working."
    set_setting global private_dns_mode opportunistic
  fi
}

step_settings() {
  head_ "Network and privacy settings"
  set_setting global private_dns_mode hostname
  set_setting global private_dns_specifier "$DNS_HOST"
  check_dns
  set_setting global wifi_scan_always_enabled 0         # no Wi-Fi scanning while Wi-Fi is off
  set_setting global ble_scan_always_enabled 0          # no Bluetooth scanning while BT is off
  set_setting global wifi_wakeup_enabled 0              # don't auto-enable Wi-Fi near saved networks
  # Connectivity checks: use GrapheneOS's servers instead of Google's (sends no data, just a 204)
  set_setting global captive_portal_http_url  "http://connectivitycheck.grapheneos.network/generate_204"
  set_setting global captive_portal_https_url "https://connectivitycheck.grapheneos.network/generate_204"
  set_setting global captive_portal_fallback_url "http://grapheneos.online/gen_204"
  set_setting global captive_portal_other_fallback_urls "http://grapheneos.online/generate_204"
  set_setting global ntp_server time.cloudflare.com     # time sync without Google's NTP
  set_setting global non_persistent_mac_randomization_force_enabled 1   # new random Wi-Fi MAC per connection (GrapheneOS default)
  set_setting global adb_wifi_enabled 0                 # no wireless debugging
  set_setting secure lock_screen_allow_private_notifications 0   # hide notification content when locked
  set_setting secure lock_screen_lock_after_timeout 0   # lock immediately when the screen turns off
  set_setting system show_password 0
  set_setting secure clock_seconds 1                    # status-bar clock shows seconds (AOSP System UI Tuner setting)
  set_setting system status_bar_show_battery_percent 1  # battery percentage in the status bar
  [[ "$MAKER" == *samsung* ]] && set_setting system display_battery_percentage 1   # Samsung's own switch
  # No animations: windows, transitions and app animations happen instantly (snappier)
  set_setting global window_animation_scale 0
  set_setting global transition_animation_scale 0
  set_setting global animator_duration_scale 0
}

# ---------------------------------------------------------------- camera -----
# The stock camera often opens photos in Google Photos (Pixel Camera ONLY works with it),
# so Photos stays installed but offline, with no location access.
CAMERA_PKG=com.google.android.GoogleCamera
detect_camera() {
  local c
  c="$(ash cmd package resolve-activity --brief -a android.media.action.IMAGE_CAPTURE | tail -1 | cut -d/ -f1)"
  if [[ -n "$c" && "$c" == *.* && "$c" != *"No activity"* ]]; then CAMERA_PKG="$c"
  else case $PROFILE in pixel) CAMERA_PKG=com.google.android.GoogleCamera ;; cmf) CAMERA_PKG=com.nothing.camera ;; esac; fi
  ok "Camera app: $CAMERA_PKG"
  # Pixel Camera ONLY opens photos in Google Photos. Other cameras use the maker's own gallery.
  PHOTOS_NEEDED=1; PHOTO_VIEWER="$PHOTOS_PKG"
  if [[ "$CAMERA_PKG" != com.google.android.GoogleCamera ]]; then
    local sys v
    sys="$(ash pm list packages -s --user 0 | sed 's/^package://')"
    for v in $(ash cmd package query-activities --brief -a com.android.camera.action.REVIEW -t 'image/*' \
               | grep -o '[A-Za-z0-9_.]*/' | tr -d / | sort -u); do
      [[ "$v" == "$PHOTOS_PKG" ]] && continue
      printf '%s\n' "${OEM_PKGS[@]}" | grep -qx "$v" && continue     # being removed (e.g. Nothing Gallery)
      if [[ "$v" == "$CAMERA_PKG" ]] || grep -qx "$v" <<<"$sys"; then PHOTOS_NEEDED=0; PHOTO_VIEWER="$v"; break; fi
    done
    # No maker gallery left: Fossify Gallery opens the camera's photos
    if [[ $PHOTOS_NEEDED == 1 ]] && ash pm list packages org.fossify.gallery | grep -q fossify; then
      PHOTOS_NEEDED=0; PHOTO_VIEWER=org.fossify.gallery
    fi
  fi
  # You can always force-keep Photos via the keep file
  [[ -f "$KEEP_FILE" ]] && grep -qx "$PHOTOS_PKG" "$KEEP_FILE" && PHOTOS_NEEDED=1
  if [[ $PHOTOS_NEEDED == 1 ]]; then ok "Photo viewer: Google Photos (this camera needs it; kept offline)"
  else ok "Photo viewer: $PHOTO_VIEWER (Google Photos isn't needed on this phone)"; fi
}
PHOTOS_PKG=com.google.android.apps.photos
PHOTOS_NEEDED=1; PHOTO_VIEWER=com.google.android.apps.photos
# -------------------------------------------------------------- lock screen --
open_screen() {                                      # open_screen "intent action" ["data uri"]
  [[ $YES == 1 || $DRY == 1 ]] && return 0
  local out
  if [[ -n "${2:-}" ]]; then out="$(ash am start -a "$1" -d "$2")"
  else out="$(ash am start -a "$1")"; fi
  # This phone doesn't have that exact screen: open the main Settings page instead
  [[ "$out" == *Error* || "$out" == *"unable to resolve"* ]] && ash am start -a android.settings.SETTINGS >/dev/null
  return 0
}
GUIDED_DONE=0
# guide "title" "intent" "Pixel path" "Nothing path" "search word" ["uri"]
#   The right instructions for THIS phone are shown. A path of "-" means "this phone doesn't
#   have it" and the step is skipped automatically. Unknown phones get the Settings-search word.
GUIDED_NA=()
guide() {
  local title=$1 action=$2 pix=$3 not=$4 word=$5 uri=${6:-} where=""
  case $PROFILE in
    pixel) [[ "$pix" == "-" ]] && { logline "    guided step not on this phone: $title"; return 0; }; where=$pix ;;
    cmf)   [[ "$not" == "-" ]] && { logline "    guided step not on this phone: $title"; return 0; }; where=$not ;;
  esac
  [[ -z "$where" ]] && where="Settings → tap the search bar → type: $word"
  say "  → $title"
  say "      $where"
  if [[ $YES == 1 || $DRY == 1 ]]; then return 0; fi
  open_screen "$action" "$uri"
  while read -r -t 0.05 -n 10000 _; do :; done          # ignore keys pressed earlier
  local ans
  read -r -p "      [Enter] done   [n] not on this phone   " ans
  if [[ "$ans" == [nN]* ]]; then
    GUIDED_NA+=("$title"); logline "    guided step NOT AVAILABLE on this phone: $title"
  else
    GUIDED_DONE=$((GUIDED_DONE+1)); logline "    guided step confirmed by user: $title"
  fi
}
# search_guide "title" "search word"   (maker-specific extras: always via Settings search)
search_guide() { guide "$1" android.settings.SETTINGS "" "" "$2"; }

# Settings Android only lets YOU change on the phone. Everything that CAN be set over USB
# is set automatically in the settings/lock steps; only these are left.
step_guided() {
  head_ "Settings you change on the phone (each one opens; [Enter] = done, [n] = not on this phone)"
  local sdk; sdk="$(ash getprop ro.build.version.sdk)"

  say ""; say "  ${c_h}Google${c_0}"
  guide "Delete your advertising ID" com.google.android.gms.settings.ADS_PRIVACY \
        "Security & privacy → More privacy settings → Ads → Delete advertising ID" \
        "Google → All services → Ads → Delete advertising ID" "advertising ID"
  guide "Usage & diagnostics OFF (Google's telemetry)" android.settings.SETTINGS \
        "Security & privacy → More privacy settings → Usage & diagnostics → Off" \
        "Google → All services → Usage & diagnostics → Off" "Usage & diagnostics"
  guide "Google Location Accuracy OFF (keep Emergency Location Service ON)" android.settings.LOCATION_SOURCE_SETTINGS \
        "Location → Location services → Google Location Accuracy → Off" \
        "Location → Location services → Google Location Accuracy → Off" "Location Accuracy"
  guide "Find Hub network OFF (or keep it if you want lost-phone tracking)" android.settings.SETTINGS \
        "Security & privacy → Device finders → Find Hub → Find Hub network" \
        "Google → All services → Find Hub → Find Hub network" "Find Hub"
  if is_installed com.google.android.dialer; then
    guide "Phone app: Caller ID & spam OFF (stops sending numbers to Google)" android.settings.SETTINGS \
          "Phone app → ⋮ → Settings → Caller ID & spam → Off" \
          "Phone app → ⋮ → Settings → Caller ID & spam → Off" "Caller ID"
  fi

  say ""; say "  ${c_h}Security${c_0}"
  guide "Theft protection: Theft Detection Lock, Offline Device Lock, Identity Check ON" android.settings.SETTINGS \
        "Security & privacy → Device unlock → Theft protection" \
        "Google → All services → Theft protection" "Theft protection"
  guide "Extend Unlock / Smart Lock OFF (the phone never unlocks itself)" android.settings.SECURITY_SETTINGS \
        "Security & privacy → More security & privacy → Extend Unlock → turn everything off" \
        "Security & privacy → More security & privacy → Extend Unlock (or Smart Lock) → off" "Extend Unlock"
  guide "Allow 2G OFF (blocks fake cell towers)" android.settings.NETWORK_OPERATOR_SETTINGS \
        "Network & internet → SIMs → your SIM → Allow 2G → Off" \
        "Network & internet → SIMs → your SIM → Allow 2G → Off" "2G"
  if [[ "$(ash service check advanced_protection)" == *found* && "$(ash service check advanced_protection)" != *"not found"* ]]; then
    guide "Advanced Protection → Expert features: USB protection ON only (leave 'Unknown apps' OFF to keep sideloading)" \
          android.settings.SECURITY_SETTINGS \
          "Security & privacy → Advanced Protection → Expert features → USB protection" \
          "" "Advanced Protection"
  else
    logline "    Advanced Protection not on this phone (Android $sdk), USB protection step skipped"
  fi

  case "$PROFILE/$MAKER/$BRAND" in
    pixel/*|*google*)
      say ""; say "  ${c_h}Pixel${c_0}"
      guide "Memory Tagging Extension ON (hardware exploit protection), reboot, then re-test Wallet" \
            android.settings.APPLICATION_DEVELOPMENT_SETTINGS \
            "Developer options → Memory Tagging Extension → On (turn off again if an app crashes)" "-" "Memory Tagging" ;;
    cmf/*|*nothing*|*cmf*)
      say ""; say "  ${c_h}Nothing / CMF${c_0}"
      search_guide "Lock Glimpse OFF (internet feed on the lock screen)" "Glimpse"
      search_guide "Nothing's diagnostics / experience-improvement sharing OFF" "diagnostic"
      search_guide "Intelligence toolkit / AI features OFF" "Intelligence"
      search_guide "Essential Key: assign it to something else or turn it off" "Essential Key" ;;
    */samsung*)
      say ""; say "  ${c_h}Samsung${c_0}"
      search_guide "Customization Service OFF (and delete its data)" "Customization Service"
      search_guide "Send diagnostic data OFF" "diagnostic data"
      search_guide "Marketing information OFF" "Marketing"
      search_guide "Galaxy AI: process data only on device; unused features OFF" "Galaxy AI"
      search_guide "Bixby off, side button = power menu" "Bixby"
      say ""
      say "      Auto Blocker: it's off now. Your choice:"
      say "        • leave it OFF: Droid-ify keeps your F-Droid apps (IronFox, HeliBoard, ...) updated"
      say "        • turn it ON: blocks USB attacks and outside apps, but F-Droid apps stop updating"
      say "          (Play Store apps like Signal and Lawnchair keep updating either way)"
      guide "Auto Blocker: decide (see above), recommended OFF if you use F-Droid apps" android.settings.SECURITY_SETTINGS \
            "" "" "Auto Blocker" ;;
    */xiaomi*|*/redmi*|*/poco*|*/*redmi*|*/*poco*)
      say ""; say "  ${c_h}Xiaomi / HyperOS${c_0}"
      search_guide "Personalized ad recommendations OFF" "ad services"
      search_guide "User Experience Program OFF" "User Experience"
      search_guide "Send diagnostic data automatically OFF" "diagnostic"
      search_guide "Authorization & revocation: revoke 'msa' (Xiaomi ads)" "revocation" ;;
    */oneplus*|*/oppo*|*/realme*)
      say ""; say "  ${c_h}OnePlus / Oppo / Realme${c_0}"
      search_guide "User Experience Program OFF" "User Experience"
      search_guide "Personalized recommendations OFF" "recommendations"
      search_guide "Diagnostics / system stability data sharing OFF" "diagnostic" ;;
    */motorola*|*/lenovo*)
      say ""; say "  ${c_h}Motorola${c_0}"
      search_guide "Share product improvement data OFF" "improve" ;;
    */vivo*|*/iqoo*|*/honor*|*/huawei*)
      say ""; say "  ${c_h}${MAKER}${c_0}"
      search_guide "User Experience Improvement Program OFF" "User Experience"
      search_guide "Personalized recommendations OFF" "recommend" ;;
    *)
      say ""; say "  ${c_h}${MAKER:-This phone}${c_0}"
      search_guide "The maker's diagnostics / improvement program OFF" "diagnostic"
      search_guide "Personalized ads / recommendations OFF" "recommend" ;;
  esac
  guided_summary
}
guided_summary() {
  echo
  ok "$GUIDED_DONE settings confirmed by you"
  if [[ ${#GUIDED_NA[@]} -gt 0 ]]; then
    warn "Not on this $DEVICE_NAME (send me this list and the script will skip them next time):"
    printf '      - %s\n' "${GUIDED_NA[@]}"
  fi
}

step_lock() {
  head_ "Lock screen, power menu, NFC and SIM"
  # Set over USB, no questions
  set_setting secure lockscreen_show_wallet 0            # no Wallet button on the lock screen
  set_setting secure lockscreen_show_controls 0          # no smart-home device controls on the lock screen
  set_setting secure lockscreen_allow_trivial_controls 0 # device controls need an unlock
  set_setting secure lockdown_in_power_menu 1            # "Lockdown" button in the power menu
  set_setting global wifi_networks_available_notification_on 0   # no "open Wi-Fi nearby" prompts

  # Only these need you on the phone
  guide "Enhanced PIN privacy ON (hides each digit's animation as you type your PIN)" android.settings.SECURITY_SETTINGS \
        "Security & privacy → Device unlock → Screen lock (⚙) → Enhanced PIN privacy" \
        "" "PIN privacy"
  guide "Require device unlock for NFC ON (tap-to-pay still works once unlocked)" android.settings.NFC_SETTINGS \
        "Connected devices → Connection preferences → NFC → Require device unlock for NFC" \
        "" "NFC"
  guide "Lock screen shortcuts: both set to None" android.settings.SETTINGS \
        "Wallpaper & style → Lock screen → Shortcuts → None / None" \
        "" "shortcuts"
  guide "SIM PIN ON (needs your SIM's current PIN; 3 wrong tries = PUK lock)" android.settings.SECURITY_SETTINGS \
        "Security & privacy → More security & privacy → SIM lock → Lock SIM" \
        "" "SIM lock"
}

step_camera() {
  if [[ $PHOTOS_NEEDED == 0 ]]; then
    head_ "Camera ($CAMERA_PKG): no location; photos open in $PHOTO_VIEWER"
    for perm in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION ACCESS_BACKGROUND_LOCATION; do
      act pm revoke "$CAMERA_PKG" "android.permission.$perm" >/dev/null 2>&1
    done
    act cmd appops set "$CAMERA_PKG" FINE_LOCATION ignore >/dev/null 2>&1
    act cmd appops set "$CAMERA_PKG" COARSE_LOCATION ignore >/dev/null 2>&1
    [[ $DRY == 0 ]] && echo "$CAMERA_PKG" >> "$LOG_HARDENED"
    ok "$CAMERA_PKG: location blocked"
    if is_installed "$PHOTOS_PKG"; then
      say "  Google Photos isn't needed by this camera, so it's disabled:"
      remove_pkg "$PHOTOS_PKG"
    fi
    return 0
  fi
  head_ "Camera ($CAMERA_PKG): no location; Google Photos kept as an offline viewer"
  if ! is_installed "$PHOTOS_PKG"; then
    act cmd package install-existing "$PHOTOS_PKG" >/dev/null
    act pm enable --user 0 "$PHOTOS_PKG" >/dev/null 2>&1
    ok "Google Photos re-enabled (the camera's photo preview needs it)"
    if [[ $DRY == 0 && -f "$LOG_REMOVED" ]]; then
      grep -vxF "$PHOTOS_PKG" "$LOG_REMOVED" > "$LOG_REMOVED.tmp"; mv "$LOG_REMOVED.tmp" "$LOG_REMOVED"
    fi
    refresh_installed
  fi
  for pkg in "$CAMERA_PKG" "$PHOTOS_PKG"; do
    for perm in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION ACCESS_BACKGROUND_LOCATION; do
      act pm revoke "$pkg" "android.permission.$perm" >/dev/null 2>&1
    done
    # appops "ignore" = permanently denied without asking again
    act cmd appops set "$pkg" FINE_LOCATION ignore >/dev/null 2>&1
    act cmd appops set "$pkg" COARSE_LOCATION ignore >/dev/null 2>&1
    [[ $DRY == 0 ]] && echo "$pkg" >> "$LOG_HARDENED"
    ok "$pkg: location blocked"
  done
  # Photos: no background running (it only opens when you tap the thumbnail)
  act cmd appops set "$PHOTOS_PKG" RUN_ANY_IN_BACKGROUND ignore >/dev/null 2>&1
  act am set-standby-bucket "$PHOTOS_PKG" restricted >/dev/null 2>&1
  ok "Google Photos: background activity blocked"
}

# ---------------------------------------------------------------- harden -----
step_harden() {
  head_ "Restricting Google apps you kept"
  local any=0
  for pkg in "${HARDEN_TARGETS[@]}"; do
    is_installed "$pkg" || continue
    is_protected "$pkg" && continue
    any=1
    printf '    restricting %s ... ' "$pkg"
    # One round trip per app instead of 16 (much faster, fewer chances to stall)
    local cmds="cmd appops set $pkg RUN_ANY_IN_BACKGROUND ignore; cmd appops set $pkg RUN_IN_BACKGROUND ignore; am set-standby-bucket $pkg restricted"
    for perm in $HARDEN_PERMS; do cmds+="; pm revoke $pkg android.permission.$perm"; done
    act sh -c "'$cmds' 2>/dev/null; true" >/dev/null
    echo "done"
    [[ $DRY == 0 ]] && echo "$pkg" >> "$LOG_HARDENED"
    ok "restricted $pkg (it will ask again for permissions when you open it)"
  done
  [[ $any == 0 ]] && ok "No user-facing Google apps left to restrict"
}

# --------------------------------------------------------------- restore -----
step_restore() {
  head_ "Restoring"
  if [[ -f "$LOG_DISABLED" ]]; then
    sort -u "$LOG_DISABLED" | while read -r pkg; do
      act pm enable --user 0 "$pkg" >/dev/null && ok "re-enabled $pkg"
    done
  fi
  if [[ -f "$LOG_REMOVED" ]]; then
    sort -u "$LOG_REMOVED" | while read -r pkg; do
      act cmd package install-existing "$pkg" >/dev/null && ok "reinstalled $pkg"
    done
  fi
  if [[ -f "$LOG_HARDENED" ]]; then
    sort -u "$LOG_HARDENED" | while read -r pkg; do
      act cmd appops reset "$pkg" >/dev/null
      act am set-standby-bucket "$pkg" active >/dev/null
      ok "unrestricted $pkg"
    done
  fi
  if [[ -f "$LOG_SETTINGS" ]]; then
    while read -r ns key old; do
      if [[ "$old" == "null" || -z "$old" ]]; then act settings delete "$ns" "$key" >/dev/null
      else act settings put "$ns" "$key" "$old" >/dev/null; fi
      ok "restored $ns/$key"
    done < "$LOG_SETTINGS"
  fi
  if [[ -s "$LOG_ROLES.ime" ]]; then
    local ime; ime="$(cat "$LOG_ROLES.ime")"
    [[ "$ime" != "null" ]] && act ime set "$ime" >/dev/null && ok "restored keyboard"
  fi
  if [[ $DRY == 0 ]]; then
    mkdir -p "$DEV_DIR/old"; mv "$DEV_DIR"/*.txt* "$DEV_DIR/old/" 2>/dev/null
  fi
  say "Replacement apps from F-Droid were left installed. Uninstall them normally if you want."
}

# ------------------------------------------------------- maker telemetry -----
# Uses the community-maintained Universal Android Debloater (UAD-ng) list: ~5,400 packages
# from every brand, each with a description and a safety rating. Only entries rated
# "Recommended" (safe), described as telemetry/analytics/ads/diagnostics, that nothing else
# depends on, and that are actually on this phone, are disabled. Keep rules still apply.
UAD_URL="https://raw.githubusercontent.com/Universal-Debloater-Alliance/universal-android-debloater-next-generation/main/resources/assets/uad_lists.json"
UAD_CACHE="$STATE_DIR/uad_lists.json"

get_uad_list() {
  mkdir -p "$STATE_DIR"
  if [[ ! -s "$UAD_CACHE" ]] || [[ -n "$(find "$UAD_CACHE" -mtime +7 2>/dev/null)" ]]; then
    say "    downloading the UAD-ng package list..."
    curl -fsSL --connect-timeout 15 -m 120 -o "$UAD_CACHE.new" "$UAD_URL" && mv "$UAD_CACHE.new" "$UAD_CACHE" \
      || warn "Couldn't download the UAD-ng list; using the saved copy if there is one"
  fi
  [[ -s "$UAD_CACHE" ]]
}

# Prints "pkg|short description" for telemetry packages present on this phone
telemetry_candidates() {
  local tmp; tmp="$(mktemp)"
  printf '%s\n' "$INSTALLED" > "$tmp"
  python3 -I - "$UAD_CACHE" "$tmp" <<'PY'
import json, re, sys
uad = json.load(open(sys.argv[1]))
installed = set(open(sys.argv[2]).read().split())
tele = re.compile(r'telemetr|analytic|tracking|tracker|diagnos|data collect|collection|collects|usage data|statistic|'
                  r'crash report|bug ?report|log ?collect|logs? service|dumplog|feedback|advertis|\bads\b|spyware|user behavio', re.I)
# never: anything that sounds like a phone function, even if it also mentions logs/feedback
skip = re.compile(r'\bcalls?\b|\bsms\b|call & text|dialer|telephony|\bims\b|volte|wi-?fi calling|accessib|screen reader|'
                  r'keyboard|launcher|camera|gallery|clock|alarm|contacts|messag|update|\bota\b|fota|bootloop|'
                  r'needed for|required for|don.t remove|do not remove|breaks?|soft-?brick|'
                  r'wallet|payment|\bpay\b|secure ?ui|password|fingerprint|biometric|knox|container|peripheral|'
                  r'push|notification service|battery|power|thermal|modem|quality of service|network performance|'
                  r'location provider|fused|bluetooth|ant radio|wi-?fi|esim|backup|sync|calibrat|calendar', re.I)
for pkg, v in sorted(uad.items()):
    if pkg not in installed or v.get('removal') != 'Recommended' or v.get('neededBy'):
        continue
    desc = ' '.join(v.get('description', '').split())
    if tele.search(desc) and not skip.search(desc) and not skip.search(pkg):
        print(f"{pkg}|{desc[:110]}")
PY
  rm -f "$tmp"
}

step_telemetry() {
  head_ "Phone-maker telemetry, analytics and ad services (UAD-ng 'Recommended' list)"
  command -v python3 >/dev/null || { warn "python3 is needed for this step; skipped"; return 0; }
  get_uad_list || { warn "No UAD-ng list available; skipped"; return 0; }
  ensure_keep_file
  refresh_installed
  local keep list go=() pkg desc
  keep="$(compute_keep)"
  list="$(telemetry_candidates)"
  while IFS='|' read -r pkg desc; do
    [[ -z "$pkg" ]] && continue
    if is_protected "$pkg" || grep -qx "$pkg" <<<"$keep" || grep -qEi "$KEEP_PATTERN" <<<"$pkg"; then
      printf '    %bkeep%b    %s (needed on this phone)\n' "$c_ok" "$c_0" "$pkg"; continue
    fi
    go+=("$pkg"); printf '    %b✗%b       %s\n              %s\n' "$c_err" "$c_0" "$pkg" "$desc"
  done <<<"$list"
  if [[ ${#go[@]} == 0 ]]; then ok "No known maker telemetry found on this $DEVICE_NAME"; return 0; fi
  say "  To keep one, add its name to $KEEP_FILE"
  confirm "Disable these ${#go[@]} telemetry/analytics packages? (undo: bash android-lockdown.sh restore)" \
    || { warn "Telemetry step skipped"; return 0; }
  [[ $DRY == 0 ]] && printf '%s\n' "${go[@]}" >> "$DEV_DIR/telemetry-packages.txt"
  for pkg in "${go[@]}"; do remove_pkg "$pkg"; done
  refresh_installed
}

# ----------------------------------------------------------------- sweep -----
# UNIVERSAL: works out from the phone itself which pre-installed drawer apps are needed.
KEEP_FILE="$STATE_DIR/keep-apps.txt"
# Drawer apps whose package name contains one of these words are always kept
# (security centres, permission managers, SIM menus, emergency apps on various brands)
KEEP_PATTERN='settings|systemui|launcher|security|permission|providers|telephony|bluetooth|nfc|keychain|wallet|setupwizard|emergency|\.sos|\.stk|cellbroadcast|documentsui|packageinstaller|webview|framework|update|updater|\.ota|fota|\.dm$|wifi|wlan|network|connectivity|\.ims|carrier|euicc|esim|\.mms|\.phone|dialer|contacts|messaging|incallui|telecom|simsettings|backup'

ensure_keep_file() {
  [[ -f "$KEEP_FILE" ]] && return 0
  mkdir -p "$STATE_DIR"
  cat > "$KEEP_FILE" <<'EOK'
# Apps the sweep must NEVER disable, one package name per line (applies to every phone).
# Find names with:  bash android-lockdown.sh scan
# Examples (remove the # in front to keep them):
#com.google.android.calculator
#com.sec.android.app.popupcalculator
EOK
}

# Package names this phone needs, one per line (asked from the phone, so it works on any brand)
compute_keep() {
  {
    printf '%s\n' $NEVER_TOUCH $KEEP_ALWAYS $KEEP_EXTRA
    printf '%s\n' "${FDROID_APPS[@]%%|*}" "${PLAY_APPS[@]%%|*}" "$IRONFOX_PKG" "${LAUNCHER_PKG:-}"
    echo "$CAMERA_PKG"
    local r
    # whatever this phone uses for calls, SMS, home screen and browser
    for r in DIALER SMS HOME BROWSER; do ash cmd role get-role-holders "android.app.role.$r" | tr ';, ' '\n\n\n'; done
    # every launcher, the gallery the camera opens, the alarm clock, the contacts app
    ash cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME | grep -o '[A-Za-z0-9_.]*/' | tr -d /
    ash cmd package query-activities --brief -a com.android.camera.action.REVIEW -t 'image/*' | grep -o '[A-Za-z0-9_.]*/' | tr -d /
    ash cmd package query-activities --brief -a android.intent.action.SET_ALARM | grep -o '[A-Za-z0-9_.]*/' | tr -d /
    ash cmd package query-activities --brief -a android.intent.action.INSERT -t vnd.android.cursor.dir/contact | grep -o '[A-Za-z0-9_.]*/' | tr -d /
    # the keyboard in use
    ash settings get secure default_input_method | cut -d/ -f1
    # your own keep list
    [[ -f "$KEEP_FILE" ]] && grep -vE '^[[:space:]]*(#|$)' "$KEEP_FILE"
    [[ $PHOTOS_NEEDED == 1 ]] && echo "$PHOTOS_PKG"
  } | grep -vxF -f <(printf '%s\n' "${OEM_PKGS[@]}") | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -E '^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)+$' \
    | { if [[ $PHOTOS_NEEDED == 1 ]]; then cat; else grep -vx "$PHOTOS_PKG"; fi; } | sort -u
}

# Prints "pkg|reason" for every pre-installed drawer app: remove / WAIT / keep
sweep_candidates() {
  local drawer system pkg repl keep
  keep="$(compute_keep)"
  drawer="$(ash cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER \
            | grep -o '[A-Za-z0-9_.]*/' | tr -d / | sort -u)"
  system="$(ash pm list packages -s --user 0 | sed 's/^package://')"
  for pkg in $drawer; do
    grep -qx "$pkg" <<<"$system" || continue                     # installed by you: never touched
    is_protected "$pkg" && { echo "$pkg|keep"; continue; }
    # Apps with a privacy replacement go as soon as the replacement is installed
    repl="$(grep "^$pkg|" <<<"$SWEEP_NEEDS_REPLACEMENT" | cut -d'|' -f2)"
    if [[ -n "$repl" ]]; then
      if is_installed "$repl"; then echo "$pkg|remove"; else echo "$pkg|WAIT: kept until $repl is installed"; fi
      continue
    fi
    if grep -qx "$pkg" <<<"$keep" || grep -qEi "$KEEP_PATTERN" <<<"$pkg"; then echo "$pkg|keep"; continue; fi
    echo "$pkg|remove"
  done
}

step_sweep() {
  head_ "Universal sweep: every pre-installed app in the app drawer that isn't needed"
  ensure_keep_file
  say "  Kept automatically: whatever this phone uses for calls, SMS, contacts, camera, the"
  say "  camera's gallery, alarms, home screen, keyboard and browser; Wallet, Play Store, Settings,"
  say "  security/SIM/emergency apps, your privacy apps, and EVERY app you installed yourself."
  say "  Hidden system parts are not touched. Extra keeps: $KEEP_FILE"
  local list go=() line pkg why
  list="$(sweep_candidates)"
  while IFS='|' read -r pkg why; do
    [[ -z "$pkg" ]] && continue
    case "$why" in
      remove) go+=("$pkg") ;;
      keep)   printf '    %bkeep%b    %s\n' "$c_ok" "$c_0" "$pkg" ;;
      *)      printf '    %bwait%b    %s (%s)\n' "$c_warn" "$c_0" "$pkg" "${why#WAIT: }" ;;
    esac
  done <<<"$list"
  if [[ ${#go[@]} -gt 0 ]]; then
    say "  Will be disabled (data wiped):"
    for pkg in "${go[@]}"; do printf '    %b✗%b       %s\n' "$c_err" "$c_0" "$pkg"; done
    say "  To keep one, add its name to $KEEP_FILE and run: bash android-lockdown.sh sweep"
  fi
  if [[ ${#go[@]} == 0 ]]; then ok "Nothing left to sweep"; return; fi
  confirm "Disable/remove these ${#go[@]} apps? (undo any time with: bash android-lockdown.sh restore)" \
    || { warn "Sweep skipped"; return; }
  for pkg in "${go[@]}"; do remove_pkg "$pkg"; done
  refresh_installed
}

# ---------------------------------------------------------------- verify -----
# Reads the phone's ACTUAL state and reports PASS/FAIL. Nothing is changed.
step_verify() {
  head_ "Verifying the phone's actual state"
  local all en dis fails=0 pkg st
  all="$(ash pm list packages --user 0 | sed 's/^package://')"
  en="$(ash pm list packages -e --user 0 | sed 's/^package://')"
  dis="$(ash pm list packages -d --user 0 | sed 's/^package://')"
  local P="${c_ok}PASS${c_0}" F="${c_err}FAIL${c_0}"

  say "  Google apps / AI / telemetry (should be removed or disabled):"
  local tele=""; [[ -f "$DEV_DIR/telemetry-packages.txt" ]] && tele="$(sort -u "$DEV_DIR/telemetry-packages.txt")"
  for pkg in "${TIER1[@]}" "${TELEMETRY[@]}" "${OEM_PKGS[@]}" "${AI_PKGS[@]}" "$GOOGLE_APP" "${TIER2[@]}" "$GBOARD" $tele; do
    if ! grep -qx "$pkg" <<<"$all"; then continue          # never on this phone / removed
    elif grep -qx "$pkg" <<<"$dis"; then st="$P  disabled"
    elif grep -qx "$pkg" <<<"$en"; then st="$F  STILL ACTIVE"; fails=$((fails+1))
    else st="$P  removed"; fi
    printf '    %b  %s\n' "$st" "$pkg"
  done

  say "  Other pre-installed apps still in the app drawer (the sweep removes these):"
  local leftover=0 why
  while IFS='|' read -r pkg why; do
    [[ -z "$pkg" ]] && continue
    if [[ "$why" == remove ]]; then printf '    %b  %s still active\n' "$F" "$pkg"; fails=$((fails+1)); leftover=1
    elif [[ "$why" == WAIT* ]]; then printf '    %b  %s (%s)\n' "${c_warn}WAIT${c_0}" "$pkg" "${why#WAIT: }"; fi
  done <<<"$(sweep_candidates)"
  [[ $leftover == 0 ]] && printf '    %b  only kept apps left\n' "$P"

  say "  Must stay enabled (tap-to-pay, calls, camera):"
  for pkg in com.google.android.gms com.android.vending com.google.android.apps.walletnfcrel \
             com.google.android.dialer com.google.android.apps.messaging "$CAMERA_PKG" \
             "$( [[ $PHOTOS_NEEDED == 1 ]] && echo "$PHOTOS_PKG" || echo "$PHOTO_VIEWER" )"; do
    if grep -qx "$pkg" <<<"$en"; then printf '    %b  %s\n' "$P" "$pkg"
    else printf '    %b  %s is not enabled\n' "$F" "$pkg"; fails=$((fails+1)); fi
  done

  say "  Defaults:"
  local v
  v="$(ash cmd role get-role-holders android.app.role.ASSISTANT)"
  [[ -z "${v//[[:space:]]/}" ]] && printf '    %b  no assistant app\n' "$P" || { printf '    %b  assistant app: %s\n' "$F" "$v"; fails=$((fails+1)); }
  v="$(ash cmd role get-role-holders android.app.role.HOME)"
  if [[ "$v" == *"$LAUNCHER_PKG"* ]]; then printf '    %b  home screen: Lawnchair\n' "$P"
  else printf '    %b  home screen: %s (run: bash android-lockdown.sh launcher)\n' "$F" "${v:-none}"; fails=$((fails+1)); fi
  v="$(ash cmd role get-role-holders android.app.role.BROWSER)"
  [[ "$v" == *ironfox* ]] && printf '    %b  browser: %s\n' "$P" "$v" || { printf '    %b  browser: %s\n' "$F" "$v"; fails=$((fails+1)); }
  v="$(ash settings get secure default_input_method)"
  [[ "$v" == helium314* ]] && printf '    %b  keyboard: HeliBoard\n' "$P" || { printf '    %b  keyboard: %s\n' "$F" "$v"; fails=$((fails+1)); }

  say "  Settings:"
  v="$(ash settings get global private_dns_mode)"
  case "$v" in
    hostname)      printf '    %b  Private DNS: %s (tracker blocking on)\n' "$P" "$DNS_HOST" ;;
    opportunistic) printf '    %b  Private DNS: Automatic (fallback, %s was blocked on your network)\n' "${c_warn}INFO${c_0}" "$DNS_HOST" ;;
    *)             printf '    %b  Private DNS: %s\n' "$F" "$v"; fails=$((fails+1)) ;;
  esac
  local line ns key want
  while read -r ns key want; do
    [[ -z "$ns" ]] && continue
    v="$(ash settings get "$ns" "$key")"
    [[ "$v" == "$want" ]] && printf '    %b  %s/%s = %s\n' "$P" "$ns" "$key" "$v" \
      || { printf '    %b  %s/%s = %s (want %s)\n' "$F" "$ns" "$key" "$v" "$want"; fails=$((fails+1)); }
  done <<EOV
global private_dns_specifier $DNS_HOST
global wifi_scan_always_enabled 0
global ble_scan_always_enabled 0
global captive_portal_https_url https://connectivitycheck.grapheneos.network/generate_204
global ntp_server time.cloudflare.com
secure lock_screen_allow_private_notifications 0
secure lockscreen_show_wallet 0
secure assist_long_press_home_enabled 0
global power_button_long_press 1
EOV

  say "  Camera location:"
  local campkgs="$CAMERA_PKG"; [[ $PHOTOS_NEEDED == 1 ]] && campkgs+=" $PHOTOS_PKG"
  for pkg in $campkgs; do
    v="$(ash cmd appops get "$pkg" FINE_LOCATION)"
    [[ "$v" == *ignore* || "$v" == *deny* ]] && printf '    %b  %s: location blocked\n' "$P" "$pkg" \
      || { printf '    %b  %s: location %s\n' "$F" "$pkg" "${v:-unknown}"; fails=$((fails+1)); }
  done

  say "  Phone still works:"
  local role holder
  local label
  for role in DIALER SMS HOME; do
    case $role in DIALER) label="phone (calls)";; SMS) label="SMS";; HOME) label="home screen";; esac
    holder="$(ash cmd role get-role-holders "android.app.role.$role" | tr -d '[:space:]')"
    if [[ -n "$holder" ]] && grep -qx "$holder" <<<"$en"; then printf '    %b  %s app: %s\n' "$P" "$label" "$holder"
    else printf '    %b  no working %s app (%s)\n' "$F" "$label" "${holder:-none}"; fails=$((fails+1)); fi
  done
  for pkg in com.google.android.ims com.android.phone com.android.providers.telephony com.android.cellbroadcastreceiver \
             com.google.android.cellbroadcastreceiver com.android.server.telecom com.google.android.euicc \
             com.android.vending com.google.android.gms com.google.android.gsf com.google.android.webview \
             com.google.android.apps.walletnfcrel com.android.nfc com.android.settings com.android.systemui; do
    grep -qx "$pkg" <<<"$all" || continue                      # not on this phone
    grep -qx "$pkg" <<<"$en" && printf '    %b  %s\n' "$P" "$pkg" || { printf '    %b  %s is DISABLED\n' "$F" "$pkg"; fails=$((fails+1)); }
  done
  # anything update-related must be enabled (system + app updates)
  local upd; upd="$(grep -Ei 'update|updater|\.ota|fota' <<<"$dis")"
  [[ -z "$upd" ]] && printf '    %b  system/app updaters enabled\n' "$P" || { printf '    %b  updater disabled: %s\n' "$F" "$upd"; fails=$((fails+1)); }
  if [[ "$(ash 'ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1 && echo up')" == up ]]; then
    printf '    %b  internet reachable\n' "$P"
    [[ "$(ash 'ping -c 1 -W 5 play.googleapis.com >/dev/null 2>&1 && echo up')" == up ]] && printf '    %b  name lookups (DNS) working\n' "$P" \
      || { printf '    %b  DNS NOT working (run: bash android-lockdown.sh settings)\n' "$F"; fails=$((fails+1)); }
  else
    printf '    %b  no internet right now (Wi-Fi/data off?), connectivity not tested\n' "${c_warn}SKIP${c_0}"
  fi
  local sim; sim="$(ash getprop gsm.sim.state)"
  printf '    %b  SIM state: %s\n' "$( [[ "$sim" == *READY* ]] && echo "$P" || echo "${c_warn}INFO${c_0}")" "${sim:-unknown}"

  say "  Boot:"
  v="$(ash getprop ro.boot.verifiedbootstate)"
  [[ "$v" == green ]] && printf '    %b  verified boot green, bootloader locked\n' "$P" || { printf '    %b  verified boot: %s\n' "$F" "$v"; fails=$((fails+1)); }

  echo
  if [[ $fails == 0 ]]; then ok "Everything checked is in place."
  else warn "$fails check(s) FAILED. Send this output and we'll fix each one."; fi
}

# ------------------------------------------------------------------ scan -----
# Lists every app in the app drawer and what the script does with it. Changes nothing.
step_scan() {
  head_ "Apps in the app drawer on this $DEVICE_NAME"
  local drawer pkg tag known_remove known_mine
  drawer="$(ash cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER \
            | grep / | sed 's/^[[:space:]]*//' | cut -d/ -f1 | sort -u)"
  known_remove="$(printf '%s\n' "${TIER1[@]}" "${TELEMETRY[@]}" "${OEM_PKGS[@]}" "${AI_PKGS[@]}" "$GOOGLE_APP" "${TIER2[@]}" "$GBOARD")"
  known_mine="$(printf '%s\n' "${FDROID_APPS[@]%%|*}" "${PLAY_APPS[@]%%|*}" "$IRONFOX_PKG")"
  local review=0
  for pkg in $drawer; do
    if   grep -qx "$pkg" <<<"$known_remove"; then tag="${c_err}remove${c_0}   (on the script's list)"
    elif grep -qx "$pkg" <<<"$known_mine";   then tag="${c_ok}yours${c_0}    (privacy app installed by the script)"
    elif grep -qx "$pkg" <<<"$NEVER_TOUCH" || [[ "$pkg" == "$CAMERA_PKG" || "$pkg" == "$PHOTO_VIEWER" ]]; then
                                               tag="${c_ok}keep${c_0}     (needed: payments, calls, camera or system)"
    else tag="${c_warn}REVIEW${c_0}   (not on any list yet)"; review=$((review+1)); fi
    printf '    %-48s %b\n' "$pkg" "$tag"
  done
  head_ "Phone-maker / preload packages (including hidden ones)"
  local all en; all="$(ash pm list packages --user 0 | sed 's/^package://')"; en="$(ash pm list packages -e --user 0 | sed 's/^package://')"
  for pkg in $(grep -Ei '^com\.(nothing|cmf)\.|aura|facebook|glimpse|essential' <<<"$all" | sort); do
    grep -qx "$pkg" <<<"$en" && tag="enabled" || tag="disabled"
    printf '    %-48s %s\n' "$pkg" "$tag"
  done
  echo
  [[ $review -gt 0 ]] && warn "$review app(s) marked REVIEW. Send this output (or latest.log) to decide what to do with them." \
                      || ok "Every app in the drawer is accounted for."
}

step_status() {
  head_ "Status"
  [[ -f "$LOG_REMOVED" ]]  && say "Removed:    $(sort -u "$LOG_REMOVED" | wc -l | tr -d ' ') packages"
  [[ -f "$LOG_HARDENED" ]] && say "Restricted: $(sort -u "$LOG_HARDENED" | wc -l | tr -d ' ') apps"
  [[ -f "$LOG_SETTINGS" ]] && say "Settings changed: $(wc -l < "$LOG_SETTINGS" | tr -d ' ')"
  say "Private DNS: $(ash settings get global private_dns_specifier)"
  say "Keyboard:    $(ash settings get secure default_input_method)"
  say "Boot state:  $(ash getprop ro.boot.verifiedbootstate)"
}

# ----------------------------------------------------- manual checklist ------
device_# After an interactive run the settings were already walked through, so only
# app setup is left. With --yes / --dry-run the full manual list is printed instead.
checklist() {
  if [[ $YES == 1 || $DRY == 1 || $GUIDED_DONE == 0 ]]; then checklist_full; return; fi
  head_ "Done. Last steps on the phone"
  cat <<'EOC'
   1. TEST TAP-TO-PAY: Wallet → card shows "Ready to tap" → make a small payment.
   2. Restart the phone, then check long-press home / "Hey Google" do nothing.
   3. Open each new app once:
      • Droid-ify: let it sync; add the IronFox repo (Settings → Repositories → +):
          https://fdroid.ironfoxoss.org/fdroid/repo
      • Ente Auth: move your 2FA codes in, turn on its encrypted backup.
      • Signal: Settings → Privacy → Screen lock + Registration Lock ON.
      • IronFox: open once (uBlock Origin and hardening are built in).
      • Google Photos: backup OFF. Camera app: "Save location" OFF.
   4. RethinkDNS → Firewall: block internet for apps that don't need it
      (Photos, Camera, Calculator, ...). NEVER block Play Services or Wallet.
   5. Shelter: create the work profile for any Google app you still need.
   6. Sideloading later: Developer options → "advanced flow" once,
      or always:  bash android-lockdown.sh install app.apk
   7. On a computer or in IronFox: myaccount.google.com/connections → remove apps you
      don't use, and myaccount.google.com → Data & privacy → pause Web & App Activity,
      Timeline and YouTube history; Personalized ads OFF.
   8. Developer options → USB debugging OFF.
   Any time later (e.g. after a system update):  bash android-lockdown.sh verify
EOC
}

checklist_full() {
  case $PROFILE in
    pixel) cat <<'EOD'

  PIXEL 10a EXTRAS
   2. Hardware memory tagging (MTE). The Pixel 10a supports it (GrapheneOS's top hardening).
      Developer options → Memory Tagging Extension → On → reboot.
      Then re-test Wallet. If any app crashes, turn it back off.
   • Open Auditor (GrapheneOS app) → pair with a second phone, or use remote
     attestation to verify the OS hasn't been tampered with.
EOD
    ;;
    cmf) cat <<'EOD'

  CMF PHONE 2 PRO / NOTHING OS EXTRAS  (menu names vary a little between Nothing OS versions)
   2. Lock Glimpse OFF: Settings → Lock screen → Lock Glimpse → Off.
      It fills the lock screen with feed content fetched from the internet.
   • Essential Key: Settings → Essential Key → assign it to something else or turn it off
     (Essential Space, its AI app, has been disabled).
   • Settings → Intelligence toolkit: turn off every AI feature listed there.
   • Settings → System → find "Experience improvement" / "Share diagnostics data" /
     "Usage & diagnostics" → Off (this is Nothing's own telemetry, separate from Google's).
   • If you keep the Nothing Launcher: Home settings → turn off the Discover / Google News feed.
   • Not available on this phone: hardware memory tagging (MediaTek chip) and Auditor.
EOD
    ;;
    *) cat <<'EOD'

  THIS PHONE HAS NO DEDICATED PROFILE
   • Run './android-lockdown.sh scan' and send the output to get the maker's extras added.
EOD
    ;;
  esac
}

checklist() {
  head_ "Done. Finish on the phone (ADB can't change these)"
  cat <<'EOF2'
  FIRST
   1. TEST TAP-TO-PAY: Wallet → card shows "Ready to tap" → make a small payment.
EOF2
  device_checklist
  cat <<'EOF2'

  GRAPHENEOS-STYLE SECURITY
   3. USB lockdown (charge-only while locked), if your phone has Advanced Protection:
      Security & privacy → Advanced Protection → "expert features" → USB protection ON,
      Unknown apps OFF. If your build has no expert features, full Advanced
      Protection also blocks sideloading; your call.
      Also: Developer options → Default USB configuration → "No data transfer".
   4. Theft protection (Security & privacy → Device unlock → Theft protection):
      Identity Check ON, Theft Detection Lock ON, Offline Device Lock ON.
   4b. If you ran with --yes, do these yourself (otherwise the script already walked you through them):
      Enhanced PIN privacy ON · NFC → Require device unlock ON · Lock screen Shortcuts → None ·
      SIM lock ON · myaccount.google.com/connections → remove unused apps.
   5. Screen lock: use a 6+ digit PIN or a password. Turn OFF Extend Unlock / Smart Lock.
      Turn ON "Lockdown" in the power menu (turns off fingerprint unlock until you enter the PIN).
   6. Network → SIMs → "Allow 2G" OFF. Wi-Fi → "Notify for public networks" OFF.

  GRAPHENEOS-STYLE PRIVACY
   8. Privacy → Ads → Delete advertising ID.  Usage & diagnostics → Off.
   9. Location → Location services → Google Location Accuracy → Off,
      Emergency Location Service stays ON.  Find Hub → Find Hub network → Off (or "with network in all areas" if you want tracking).
  10. myaccount.google.com → Data & privacy: pause Web & App Activity, Timeline,
      YouTube history; Personalized ads OFF.
  11. Google → Backup → off (or keep it; device backups are end-to-end encrypted).
  12. Wallet → Settings → personalization / data from other Google products → OFF.
  13. Phone app → Settings → Caller ID & spam → Off (stops sending numbers to Google).
  14. Network permission per app (GrapheneOS "Network" toggle):
      RethinkDNS → Firewall → block every app that doesn't need internet.
      NEVER block Google Play Services or Wallet.
  15. Sensors permission: Developer options → Quick settings developer tiles →
      "Sensors Off" → add it to Quick Settings.
  16. Profiles (GrapheneOS secondary users): open Shelter → create the work profile →
      clone in any Google apps you still need, and freeze them when you're not using them.
      Keep Wallet + banking in the main profile.

  SIDELOADING
  17. Developer options → turn on the "advanced flow" once (restart + 24 h wait), or
      always install with:  ./android-lockdown.sh install app.apk

  CAMERA / PHOTOS
   • Open Google Photos once. If it asks about backup, choose not to back up
     (or Photos → profile icon → Photos settings → Backup → Off).
   • RethinkDNS → Firewall → block internet for Google Photos AND Pixel Camera.
     Photos then works purely as an offline viewer for the camera.
   • Pixel Camera → Settings → "Save location" → Off (belt and braces).

  APPS
   • Open Droid-ify once and let it sync. From then on it updates all the apps above.
     Also add the IronFox repo there (Settings → Repositories → +) so IronFox updates too:
     https://fdroid.ironfoxoss.org/fdroid/repo
   • Ente Auth: move your 2FA codes in (it can import from Google Authenticator),
     then turn on its encrypted backup or export a backup.
   • Signal: Settings → Privacy → turn on Screen lock and Registration Lock (PIN).

  BROWSER
   • Open IronFox once to finish setup. It comes with uBlock Origin and
     hardened settings, so there's nothing else to configure. To verify the app, compare
     its signing key in AppVerifier with C5:E2:91:B5:...:F9:04 (ironfoxoss.org).

  AI / "HEY GOOGLE"
  18. Settings → System → Gestures → Press & hold power button → "Power menu"
      (instead of the assistant).  Settings → Google → Gemini/Assistant → "Hey Google" OFF
      (only needed if you kept the Google app).

  LAST
  19. Developer options → USB debugging OFF.
EOF2
}

# ------------------------------------------------------------------ main -----
MODE="all"; ARGS=()
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --yes|-y)  YES=1 ;;
    *)         ARGS+=("$a") ;;
  esac
done
[[ ${#ARGS[@]} -gt 0 ]] && MODE="${ARGS[0]}"
setup_logging

case "$MODE" in
  all)
    preflight
    pause "Before starting, check that Wallet works and that your photos are backed up"
    step_apps
    step_debloat
    step_telemetry
    step_sweep
    step_camera
    step_settings
    step_lock
    step_guided
    step_harden
    step_verify
    step_scan
    checklist
    ;;
  apps)     preflight; step_apps; step_verify ;;
  debloat)  preflight; step_debloat; step_telemetry; step_sweep; step_verify ;;
  telemetry) preflight; step_telemetry; step_verify ;;
  verify)   preflight; step_verify ;;
  scan)     preflight; step_scan ;;
  sweep)    preflight; step_sweep; step_verify ;;
  settings) preflight; step_settings; step_verify ;;
  lock)     preflight; step_lock; guided_summary; step_verify ;;
  manual)   preflight; step_lock; step_guided ;;
  launcher) preflight; refresh_installed; step_launcher; step_verify ;;
  harden)   preflight; step_harden; step_verify ;;
  camera)   preflight; step_camera; step_verify ;;
  restore)  preflight; step_restore ;;
  status)   preflight; step_status ;;
  install)
    ensure_adb; wait_for_phone
    [[ ${#ARGS[@]} -gt 1 ]] || die "Usage: $0 install app1.apk [app2.apk ...]"
    for apk in "${ARGS[@]:1}"; do echo -n "$apk: "; adb_install "$apk" | tail -1; done
    ;;
  *) die "Unknown mode '$MODE'. Use: all | apps | launcher | debloat | telemetry | sweep | manual | verify | scan | camera | settings | lock | harden | install | status | restore" ;;
esac
