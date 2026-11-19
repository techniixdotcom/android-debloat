#!/usr/bin/env bash

set -u

DNS_HOST="dns.adguard-dns.com"

FDROID_MIRRORS="https://mirror.init7.net/fdroid/repo https://ftp.fau.de/fdroid/repo https://f-droid.org/repo"

STATE_DIR="./lockdown-state"
TMP_DIR="$STATE_DIR/apk-cache"
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
PROFILE="other"; DEVICE_NAME="Android phone"; MAKER=""; BRAND=""; MTE_SUPPORTED=""

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

PLAY_APPS=(
  "app.lawnchair.play|Lawnchair launcher (looks like the Pixel Launcher, no Google search bar)"
  "org.thoughtcrime.securesms|Signal (private messaging; Play version updates itself)"
  "app.attestation.auditor|Auditor by GrapheneOS (verifies the OS hasn't been tampered with)"
)
BROWSER_PKGS="org.ironfoxoss.ironfox org.mozilla.fennec_fdroid"

IRONFOX_PKG="org.ironfoxoss.ironfox"
IRONFOX_REPOS="https://fdroid.ironfoxoss.org/fdroid/repo https://gitlab.com/ironfox-oss/fdroid/-/raw/main/fdroid/repo https://codeberg.org/ironfox-oss/fdroid/raw/branch/main/fdroid/repo"
IRONFOX_CERT="C5E291B5A571F9C8CD9A9799C2C94E02EC9703948893F2CA756D67B94204F904"

TIER1=(
  com.google.android.youtube
  com.google.android.apps.youtube.music
  com.google.android.apps.tachyon
  com.google.android.videos
  com.google.android.apps.subscriptions.red
  com.google.android.apps.docs
  com.google.android.apps.magazines
  com.google.android.apps.podcasts
  com.google.android.keep
  com.google.android.apps.tips
  com.google.android.apps.restore
  com.google.android.projection.gearhead
  com.google.ar.core
  com.google.android.apps.chromecast.app
  com.google.android.apps.wellbeing
  com.google.android.apps.turbo
  com.google.android.apps.fitness
  com.google.android.apps.wearables.maestro.companion
  com.google.android.apps.wellbeing.home
  com.google.android.partnersetup
  com.google.android.apps.docs.editors.docs
  com.google.android.apps.translate
  com.google.android.apps.weather
  com.google.android.apps.wear.companion
  com.fitbit.FitbitMobile
  com.google.android.apps.pixel.aurelius
  com.google.android.apps.pixel.nowplaying
  com.google.android.apps.credentialmanager
)

TELEMETRY=(
  com.google.mainline.telemetry
  com.google.android.feedback
)

TIER2=(
  com.android.chrome
  com.google.android.gm
  com.google.android.apps.maps
  com.google.android.calendar
  com.google.android.apps.nbu.files
  com.google.android.apps.recorder
  com.google.android.apps.safetyhub
  com.google.android.apps.adm
  com.google.android.tts
)

AI_PKGS=(
  com.google.android.apps.bard
  com.google.android.apps.googleassistant
  com.google.android.aicore
  com.google.android.as
  com.google.android.as.oss
  com.google.android.apps.pixel.creativeassistant
  com.google.assistant.hubui
  com.google.android.apps.labs.language.tailwind
  com.google.android.googlequicksearchbox.nga_resources
)
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
KEEP_EXTRA=""
SWEEP_NEEDS_REPLACEMENT="
com.google.android.deskclock|org.fossify.clock
com.google.android.calculator|org.fossify.math
com.android.chrome|org.ironfoxoss.ironfox
com.google.android.gm|com.fsck.k9
com.google.android.apps.maps|app.organicmaps
com.google.android.calendar|org.fossify.calendar
com.google.android.apps.nbu.files|org.fossify.filemanager
"

OEM_PKGS=(
  com.aura.oobe.solutions
  com.nothing.ntessentialspace
  com.nothing.ntessentialrecorder
  com.nothing.weather
  com.nothing.aiwidget
  com.nothing.essentialintelligence
  com.nothing.experience
  com.nothing.logkit
  com.nothing.enginnerservice
  com.nothing.experimental
  com.nothing.smartcenter
  com.nothing.agreement
  com.nothing.games
  com.nothing.ntgamedashboard
  com.nothing.userguide
  com.nothing.introduction16
  com.nothing.user.center
  com.nothing.universal.search
  com.nothing.gallery
  com.facebook.appmanager
  com.facebook.services
  com.facebook.system
  com.facebook.katana
)
DISABLE_ONLY="com.aura.oobe.solutions"

GBOARD=com.google.android.inputmethod.latin
GOOGLE_APP=com.google.android.googlequicksearchbox

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

DRY=0; YES=0
c_ok=$'\e[32m'; c_warn=$'\e[33m'; c_err=$'\e[31m'; c_h=$'\e[1;36m'; c_0=$'\e[0m'
say()  { echo "$*"; }
ok()   { echo "${c_ok}  ✓${c_0} $*"; }
warn() { echo "${c_warn}  !${c_0} $*" >&2; }
die()  { echo "${c_err}Error:${c_0} $*" >&2; exit 1; }
head_() { echo; echo "${c_h}== $* ==${c_0}"; }

adb_recover() {
  warn "USB connection stalled, restarting adb..."
  adb kill-server >/dev/null 2>&1; sleep 2; adb start-server >/dev/null 2>&1
  local i; for i in $(seq 1 30); do
    [[ "$(adb get-state 2>/dev/null)" == "device" ]] && timeout 10 adb shell true </dev/null >/dev/null 2>&1 && return 0
    sleep 2
  done
  die "Phone stopped responding. Unplug and replug it, keep it unlocked, then run the script again (finished steps are skipped)."
}
TTY=""
{ : >/dev/tty; } 2>/dev/null && TTY=/dev/tty
run_timed() {
  local limit=$1 label=$2; shift 2
  local tmp; tmp="$(mktemp)"
  timeout "$limit" "$@" </dev/null >"$tmp" 2>&1 &
  local pid=$! t=0 shown=0 rc
  while kill -0 "$pid" 2>/dev/null; do
    sleep 0.2; t=$((t+1))
    if [[ -n "$TTY" && $t -ge 10 && $((t % 5)) == 0 ]]; then
      local sec=$((t/5)) pct=$(( t*100/(limit*5) )) w=20 fill
      fill=$(( pct*w/100 ))
      printf '\r      ⏳ %s: %3ds [%-*s] %3d%% of the %ds limit ' "$label" "$sec" "$w" \
        "$(printf '%*s' "$fill" '' | tr ' ' '#')" "$pct" "$limit" >"$TTY"
      shown=1
    fi
  done
  wait "$pid"; rc=$?
  [[ $shown == 1 ]] && printf '\r%*s\r' 100 '' >"$TTY"
  cat "$tmp"; rm -f "$tmp"
  return $rc
}

P_I=0; P_N=0
progress_start() { P_I=0; P_N=$1; }
progress_end() { P_I=0; P_N=0; }
count_installed() { local n=0 x; for x in "$@"; do is_installed "$x" && n=$((n+1)); done; echo "$n"; }
progress_tick() {
  P_I=$((P_I+1))
  local pct=0; [[ $P_N -gt 0 ]] && pct=$(( P_I*100/P_N ))
  printf '    %b[%3d/%-3d %3d%%]%b %s\n' "$c_h" "$P_I" "$P_N" "$pct" "$c_0" "$*"
}

ash() {
  local out rc
  out="$(run_timed 30 "waiting for the phone" adb shell "$@")"; rc=$?
  if [[ $rc == 124 ]]; then adb_recover; out="$(run_timed 30 "waiting for the phone (retry)" adb shell "$@")"; fi
  printf '%s\n' "$out" | tr -d '\r'
}
adb_install() {
  local apk=$1 out rc
  logline "    \$ adb install --no-streaming -r $apk"
  out="$(run_timed 180 "installing $(basename "$apk")" adb install --no-streaming -r "$apk")"; rc=$?
  if [[ $rc == 124 ]]; then
    warn "Install timed out. If the phone shows a Play Protect popup, tap Install anyway."
    adb_recover
    out="$(run_timed 180 "installing $(basename "$apk") (retry)" adb install --no-streaming -r "$apk")"
  fi
  logout "$out"
  printf '%s\n' "$out"
}
RUN_LOG=""
logline() { [[ -n "$RUN_LOG" ]] && printf '%s\n' "$*" >&3; return 0; }
logout()  { [[ -n "$RUN_LOG" && -n "$1" ]] && printf '%s\n' "$1" | sed 's/^/        → /' >&3; return 0; }
stamp() {
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
  exec 3> >(stamp >> "$RUN_LOG")
  exec > >(tee /dev/fd/3) 2>&1
  say "Log file: $RUN_LOG"
  say "  (watch it live in another terminal: tail -f $STATE_DIR/logs/latest.log)"
  logline "=== pixel-debloat.sh mode=$MODE dry_run=$DRY yes=$YES ==="
  trap 'logline "=== finished (exit $?) ==="; echo; echo "Full log: $RUN_LOG"' EXIT
}

act_long() {
  if [[ $DRY == 1 ]]; then echo "    [dry-run] adb shell <loop over all apps>"; logline "    [dry-run] $1"; return 0; fi
  logline "    \$ adb shell $1"
  local out; out="$(run_timed 300 "working through every app on the phone" adb shell "$1" | tr -d '\r')"
  logout "$out"; [[ -n "$out" ]] && printf '%s\n' "$out"; return 0
}

act() {
  if [[ $DRY == 1 ]]; then echo "    [dry-run] adb shell $*"; logline "    [dry-run] adb shell $*"; return 0; fi
  logline "    \$ adb shell $*"
  local out; out="$(ash "$@")"
  logout "$out"
  [[ -n "$out" ]] && printf '%s\n' "$out"
  return 0
}
confirm() {
  [[ $YES == 1 || $DRY == 1 ]] && return 0
  read -r -p "  ? $1 [y/N] " a; [[ "$a" =~ ^[Yy] ]]
}
pause() {
  [[ $YES == 1 || $DRY == 1 ]] && return 0
  while read -r -t 0.05 -n 10000 _; do :; done
  read -r -p "  → $1 (press Enter) " _
}

refresh_installed() { INSTALLED="$(ash pm list packages -e --user 0 | sed 's/^package://')"; }
DRY_GONE=""
is_installed() { grep -qx "$1" <<<"$INSTALLED" && ! grep -qx "$1" <<<"$DRY_GONE"; }
is_protected() { grep -qx "$1" <<<"$NEVER_TOUCH"; }

remove_pkg() {
  local pkg=$1
  is_protected "$pkg" && { warn "$pkg is protected, skipping"; return; }
  is_installed "$pkg" || return 0
  [[ $P_N -gt 0 ]] && progress_tick "$pkg"
  local out=""
  [[ " $DISABLE_ONLY " == *" $pkg "* ]] || out="$(act pm uninstall --user 0 "$pkg")"
  if [[ $DRY == 1 || "$out" == Success* ]]; then
    ok "removed $pkg"
    if [[ $DRY == 1 ]]; then DRY_GONE+="$pkg"$'\n'; else echo "$pkg" >> "$LOG_REMOVED"; fi
    return 0
  fi
  act pm clear --user 0 "$pkg" >/dev/null 2>&1
  out="$(act pm disable-user --user 0 "$pkg")"
  if [[ "$out" == *disabled* ]]; then
    ok "disabled $pkg (data wiped)"
    echo "$pkg" >> "$LOG_DISABLED"
  else
    warn "$pkg: couldn't remove or disable ($out)"
  fi
}

set_setting() {
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
  if [[ "$(uname -s)" == Linux* ]]; then
    export ADB_LIBUSB="${ADB_LIBUSB:-0}"
    adb kill-server >/dev/null 2>&1
  fi
  adb start-server >/dev/null 2>&1
  _wait_for_phone || return 1
  if ! timeout 15 adb shell true </dev/null >/dev/null 2>&1; then
    die "The phone is connected but doesn't answer. Run: adb kill-server, revoke USB debugging authorizations on the phone, replug, tap Allow (tick 'Always allow'), then run the script again."
  fi
}
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

PREFLIGHT_DONE=0
preflight() {
  [[ $PREFLIGHT_DONE == 1 ]] && return 0
  PREFLIGHT_DONE=1
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
  MAKER="$(ash getprop ro.product.manufacturer | tr '[:upper:]' '[:lower:]')"
  BRAND="$(ash getprop ro.product.brand | tr '[:upper:]' '[:lower:]')"
  case "$MAKER $BRAND" in
    *google*)                    PROFILE=google ;;
    *nothing*|*cmf*)             PROFILE=nothing ;;
    *samsung*)                   PROFILE=samsung ;;
    *xiaomi*|*redmi*|*poco*)     PROFILE=xiaomi ;;
    *oneplus*|*oppo*|*realme*)   PROFILE=oplus ;;
    *motorola*|*lenovo*)         PROFILE=motorola ;;
    *vivo*|*iqoo*)               PROFILE=vivo ;;
    *honor*|*huawei*)            PROFILE=honor ;;
    *)                           PROFILE=other ;;
  esac
  DEVICE_NAME="$(ash getprop ro.product.marketname)"
  [[ -z "$DEVICE_NAME" ]] && DEVICE_NAME="$model"
  [[ "$DEVICE_NAME" != *"$model"* && -n "$model" ]] && DEVICE_NAME="$DEVICE_NAME ($model)"
  MTE_SUPPORTED="$(ash getprop ro.arm64.memtag.bootctl_supported)"
  ok "Phone: $DEVICE_NAME, by ${MAKER:-unknown} (${PROFILE} software family), Android SDK $sdk"
  set_device_paths "$lc-${serial:-unknown}"
  mkdir -p "$DEV_DIR"
  if [[ $PROFILE == google && -d ./pixel-lockdown-state && ! -s "$LOG_DISABLED" && ! -s "$LOG_SETTINGS" ]]; then
    cp ./pixel-lockdown-state/*.txt* "$DEV_DIR/" 2>/dev/null && ok "Imported backups from the old pixel-lockdown-state folder"
  fi
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

fdroid_install() {
  local pkg=$1 label=$2
  if is_installed "$pkg"; then ok "$label: already installed"; return 0; fi
  if [[ $DRY == 1 ]]; then echo "    [dry-run] download + install $pkg"; return 0; fi
  command -v curl >/dev/null || { warn "curl missing, can't install $pkg"; return 1; }
  local codes
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
    info="$( { curl -fsSL "$repo/index-v2.json" 2>/dev/null || curl -fsSL "$repo/index-v1.json" 2>/dev/null; } | python3 -c '
import json,sys
pkg="org.ironfoxoss.ironfox"
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
c=[]
p=d.get("packages",{}).get(pkg)
if isinstance(p,dict):
    for v in p.get("versions",{}).values():
        m=v.get("manifest",{}); f=v.get("file",{})
        c.append((m.get("versionCode",0), m.get("nativecode") or [], f.get("name",""), f.get("sha256","")))
elif isinstance(p,list):
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
  set_setting global verifier_verify_adb_installs 0
  progress_start "${#FDROID_APPS[@]}"
  for entry in "${FDROID_APPS[@]}"; do
    progress_tick "${entry#*|}"
    fdroid_install "${entry%%|*}" "${entry#*|}"
  done; progress_end
  refresh_installed
  ironfox_install

  head_ "Play Store apps (install these on the phone)"
  local need=0
  for entry in "${PLAY_APPS[@]}"; do
    local pkg="${entry%%|*}" label="${entry#*|}"
    if [[ "$pkg" == app.attestation.auditor && $PROFILE != google ]]; then continue; fi
    if is_installed "$pkg"; then ok "$label: already installed"; continue; fi
    need=1
    act am start -a android.intent.action.VIEW -d "market://details?id=$pkg" >/dev/null
    say "    opened Play Store: $label"
    pause "Tap Install on the phone, then come back here"
  done
  [[ $need == 1 ]] && refresh_installed
  step_launcher
  detect_camera
}

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

step_debloat() {
  head_ "Removing Google apps (safe tier)"
  progress_start "$(count_installed "${TIER1[@]}")"
  for p in "${TIER1[@]}"; do remove_pkg "$p"; done; progress_end

  head_ "Removing telemetry packages"
  progress_start "$(count_installed "${TELEMETRY[@]}")"
  for p in "${TELEMETRY[@]}"; do remove_pkg "$p"; done; progress_end

  head_ "Removing $DEVICE_NAME extras (phone-maker apps, AI, app installers)"
  local any_oem=0
  progress_start "$(count_installed "${OEM_PKGS[@]}")"
  for p in "${OEM_PKGS[@]}"; do
    is_installed "$p" || continue
    any_oem=1
    if [[ "$p" == *gallery* ]] && ! is_installed org.fossify.gallery; then
      warn "$p kept until Fossify Gallery is installed (the camera needs a photo viewer)"; continue
    fi
    remove_pkg "$p"
  done; progress_end
  [[ $any_oem == 0 ]] && ok "None found on this phone"

  head_ "Removing ALL AI (Gemini, Assistant, AICore, \"Hey Google\", Circle to Search)"
  progress_start "$(count_installed "${AI_PKGS[@]}")"
  for p in "${AI_PKGS[@]}"; do remove_pkg "$p"; done; progress_end
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
  set_setting secure assist_touch_gesture_enabled 0
  set_setting global power_button_long_press 1

  head_ "Keyboard: Gboard -> HeliBoard (Gboard has Gemini built in)"
  if is_installed "$GBOARD"; then
    if set_default_keyboard; then ok "HeliBoard is now the default keyboard"; remove_pkg "$GBOARD"
    else warn "HeliBoard isn't active, so Gboard stays (removing it could leave you with no keyboard)"; fi
  else ok "Gboard already gone"; fi

  head_ "Removing Chrome, Gmail, Maps, Calendar, Files, Recorder, Speech, Personal Safety, Find Hub app"
  if is_installed com.android.chrome; then
    if set_default_browser; then ok "$BROWSER is the default browser"; else warn "Couldn't set default browser; set it in Settings → Apps → Default apps"; fi
  fi
  progress_start "$(count_installed "${TIER2[@]}")"
  for p in "${TIER2[@]}"; do
    case "$p" in
      com.android.chrome)              pick_browser || { warn "IronFox not installed yet, keeping Chrome for now"; continue; } ;;
      com.google.android.gm)           is_installed com.fsck.k9 || { warn "K-9 not installed yet, keeping Gmail for now"; continue; } ;;
      com.google.android.apps.maps)    is_installed app.organicmaps || { warn "Organic Maps not installed yet, keeping Maps for now"; continue; } ;;
      com.google.android.calendar)     is_installed org.fossify.calendar || { warn "Fossify Calendar not installed yet, keeping Calendar for now"; continue; } ;;
      com.google.android.apps.nbu.files) is_installed org.fossify.filemanager || { warn "Fossify Files not installed yet, keeping Files for now"; continue; } ;;
    esac
    remove_pkg "$p"
  done; progress_end
  refresh_installed

  head_ "Leftover AI / assistant packages"
  local left
  left=""
  local p
  for p in $(grep -Ei 'gemini|bard|aicore|assistant|intelligence|\.as$|\.as\.oss|creativeassistant|googlequicksearchbox|pixel\.agent|magiccue|journal|essential|glimpse|aura\.|facebook' <<<"$INSTALLED" \
             | grep -vx 'com.google.android.settings.intelligence'); do
    is_installed "$p" && left+="$p"$'\n'
  done
  left="${left%$'\n'}"
  if [[ -n "$left" ]]; then
    warn "Still installed (remove with: adb shell pm uninstall --user 0 <name>):"
    sed 's/^/      /' <<<"$left"
  else ok "No AI/assistant packages found"; fi
}

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
  set_setting global wifi_scan_always_enabled 0
  set_setting global ble_scan_always_enabled 0
  set_setting global wifi_wakeup_enabled 0
  set_setting global captive_portal_http_url  "http://connectivitycheck.grapheneos.network/generate_204"
  set_setting global captive_portal_https_url "https://connectivitycheck.grapheneos.network/generate_204"
  set_setting global captive_portal_fallback_url "http://grapheneos.online/gen_204"
  set_setting global captive_portal_other_fallback_urls "http://grapheneos.online/generate_204"
  set_setting global ntp_server time.cloudflare.com
  set_setting global non_persistent_mac_randomization_force_enabled 1
  set_setting global adb_wifi_enabled 0
  set_setting secure lock_screen_allow_private_notifications 0
  set_setting secure lock_screen_lock_after_timeout 0
  set_setting system show_password 0
  set_setting secure clock_seconds 1
  set_setting system status_bar_show_battery_percent 1
  [[ "$MAKER" == *samsung* ]] && set_setting system display_battery_percentage 1
  set_setting global window_animation_scale 0
  set_setting global transition_animation_scale 0
  set_setting global animator_duration_scale 0
}

CAMERA_PKG=com.google.android.GoogleCamera
detect_camera() {
  local c
  c="$(ash cmd package resolve-activity --brief -a android.media.action.IMAGE_CAPTURE | tail -1 | cut -d/ -f1)"
  if [[ -n "$c" && "$c" == *.* && "$c" != *"No activity"* ]]; then CAMERA_PKG="$c"
  else case $PROFILE in google) CAMERA_PKG=com.google.android.GoogleCamera ;; nothing) CAMERA_PKG=com.nothing.camera ;; esac; fi
  ok "Camera app: $CAMERA_PKG"
  PHOTOS_NEEDED=1; PHOTO_VIEWER="$PHOTOS_PKG"
  if [[ "$CAMERA_PKG" != com.google.android.GoogleCamera ]]; then
    local sys v
    sys="$(ash pm list packages -s --user 0 | sed 's/^package://')"
    for v in $(ash cmd package query-activities --brief -a com.android.camera.action.REVIEW -t 'image/*' \
               | grep -o '[A-Za-z0-9_.]*/' | tr -d / | sort -u); do
      [[ "$v" == "$PHOTOS_PKG" ]] && continue
      printf '%s\n' "${OEM_PKGS[@]}" | grep -qx "$v" && continue
      if [[ "$v" == "$CAMERA_PKG" ]] || grep -qx "$v" <<<"$sys"; then PHOTOS_NEEDED=0; PHOTO_VIEWER="$v"; break; fi
    done
    if [[ $PHOTOS_NEEDED == 1 ]] && ash pm list packages org.fossify.gallery | grep -q fossify; then
      PHOTOS_NEEDED=0; PHOTO_VIEWER=org.fossify.gallery
    fi
  fi
  [[ -f "$KEEP_FILE" ]] && grep -qx "$PHOTOS_PKG" "$KEEP_FILE" && PHOTOS_NEEDED=1
  if [[ $PHOTOS_NEEDED == 1 ]]; then ok "Photo viewer: Google Photos (this camera needs it; kept offline)"
  else ok "Photo viewer: $PHOTO_VIEWER (Google Photos isn't needed on this phone)"; fi
}
PHOTOS_PKG=com.google.android.apps.photos
PHOTOS_NEEDED=1; PHOTO_VIEWER=com.google.android.apps.photos
open_screen() {
  [[ $YES == 1 || $DRY == 1 ]] && return 0
  local out
  if [[ -n "${2:-}" ]]; then out="$(ash am start -a "$1" -d "$2")"
  else out="$(ash am start -a "$1")"; fi
  [[ "$out" == *Error* || "$out" == *"unable to resolve"* ]] && ash am start -a android.settings.SETTINGS >/dev/null
  return 0
}
GUIDED_DONE=0
GUIDED_NA=()
guide() {
  local title=$1 action=$2 pix=$3 not=$4 word=$5 uri=${6:-} where=""
  case $PROFILE in
    google)  [[ "$pix" == "-" ]] && { logline "    guided step not on this phone: $title"; return 0; }; where=$pix ;;
    nothing) [[ "$not" == "-" ]] && { logline "    guided step not on this phone: $title"; return 0; }; where=$not ;;
  esac
  [[ -z "$where" ]] && where="Settings → tap the search bar → type: $word"
  say "  → $title"
  say "      $where"
  if [[ $YES == 1 || $DRY == 1 ]]; then return 0; fi
  open_screen "$action" "$uri"
  while read -r -t 0.05 -n 10000 _; do :; done
  local ans
  read -r -p "      [Enter] done   [n] not on this phone   " ans
  if [[ "$ans" == [nN]* ]]; then
    GUIDED_NA+=("$title"); logline "    guided step NOT AVAILABLE on this phone: $title"
  else
    GUIDED_DONE=$((GUIDED_DONE+1)); logline "    guided step confirmed by user: $title"
  fi
}
search_guide() { guide "$1" android.settings.SETTINGS "" "" "$2"; }

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
  guide "Driving mode: turn OFF 'turn on automatically' (no more 'car mode' pop-ups)" android.settings.SETTINGS \
        "Modes → Driving → Turn on automatically → Off (or delete the Driving mode)" \
        "" "Driving"
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

  if [[ "$MTE_SUPPORTED" == 1 ]]; then
    say ""; say "  ${c_h}Hardware exploit protection (this phone supports it)${c_0}"
    guide "Memory Tagging Extension ON, reboot, then re-test Wallet (turn off again if an app crashes)" \
          android.settings.APPLICATION_DEVELOPMENT_SETTINGS \
          "Developer options → Memory Tagging Extension → On" "" "Memory Tagging"
  fi

  case "$PROFILE" in
    google) : ;;
    nothing)
      say ""; say "  ${c_h}Nothing OS${c_0}"
      search_guide "Lock Glimpse OFF (internet feed on the lock screen)" "Glimpse"
      search_guide "Nothing's diagnostics / experience-improvement sharing OFF" "diagnostic"
      search_guide "Intelligence toolkit / AI features OFF" "Intelligence"
      search_guide "Essential Key: assign it to something else or turn it off" "Essential Key" ;;
    samsung)
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
    xiaomi)
      say ""; say "  ${c_h}Xiaomi / HyperOS${c_0}"
      search_guide "Personalized ad recommendations OFF" "ad services"
      search_guide "User Experience Program OFF" "User Experience"
      search_guide "Send diagnostic data automatically OFF" "diagnostic"
      search_guide "Authorization & revocation: revoke 'msa' (Xiaomi ads)" "revocation" ;;
    oplus)
      say ""; say "  ${c_h}OnePlus / Oppo / Realme${c_0}"
      search_guide "User Experience Program OFF" "User Experience"
      search_guide "Personalized recommendations OFF" "recommendations"
      search_guide "Diagnostics / system stability data sharing OFF" "diagnostic" ;;
    motorola)
      say ""; say "  ${c_h}Motorola${c_0}"
      search_guide "Share product improvement data OFF" "improve" ;;
    vivo|honor)
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
  set_setting secure lockscreen_show_wallet 0
  set_setting secure lockscreen_show_controls 0
  set_setting secure lockscreen_allow_trivial_controls 0
  set_setting secure lockdown_in_power_menu 1
  set_setting global wifi_networks_available_notification_on 0

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
    act cmd appops set "$pkg" FINE_LOCATION ignore >/dev/null 2>&1
    act cmd appops set "$pkg" COARSE_LOCATION ignore >/dev/null 2>&1
    [[ $DRY == 0 ]] && echo "$pkg" >> "$LOG_HARDENED"
    ok "$pkg: location blocked"
  done
  act cmd appops set "$PHOTOS_PKG" RUN_ANY_IN_BACKGROUND ignore >/dev/null 2>&1
  act am set-standby-bucket "$PHOTOS_PKG" restricted >/dev/null 2>&1
  ok "Google Photos: background activity blocked"
}

MOTION_EXCLUDE="com.google.android.gms com.google.android.gsf com.android.nfc com.android.phone"
step_motion() {
  head_ "Tracking OFF for every app: movement (driving/walking), body sensors, background location"
  ensure_keep_file
  local skip; skip="$MOTION_EXCLUDE $( [[ -f "$KEEP_FILE" ]] && grep -vE '^[[:space:]]*(#|$)' "$KEEP_FILE" | tr '\n' ' ')"
  local case_pat; case_pat="$(tr -s ' ' '\n' <<<"$skip" | grep . | paste -sd'|' -)"
  say "    working through every app on the phone (can take a minute)..."
  act_long "for p in \$(pm list packages -e --user 0 | cut -d: -f2); do
    cmd appops set \$p ACTIVITY_RECOGNITION ignore 2>/dev/null
    pm revoke \$p android.permission.ACTIVITY_RECOGNITION 2>/dev/null
    pm revoke \$p android.permission.BODY_SENSORS 2>/dev/null
    pm revoke \$p android.permission.BODY_SENSORS_BACKGROUND 2>/dev/null
    case \$p in ${case_pat:-__none__}) continue;; esac
    pm revoke \$p android.permission.ACCESS_BACKGROUND_LOCATION 2>/dev/null
  done; echo done" >/dev/null
  [[ $DRY == 0 ]] && touch "$DEV_DIR/motion-locked"
  local left; left="$(ash cmd appops query-op --user 0 ACTIVITY_RECOGNITION allow | grep -v '^$')"
  if [[ -z "$left" || $DRY == 1 ]]; then ok "No app can detect driving / walking any more (Play Services included)"
  else warn "Still allowed to detect movement: $(tr '\n' ' ' <<<"$left")"; fi
  ok "Body sensors and background location revoked (Play Services keeps location for emergency calls)"
  local p; for p in com.google.android.projection.gearhead com.google.android.apps.fitness; do
    is_installed "$p" && remove_pkg "$p"
  done
  say "  Apps that need a permission again will simply ask next time you open them."
}

step_harden() {
  head_ "Restricting Google apps you kept"
  local any=0
  progress_start "$(count_installed "${HARDEN_TARGETS[@]}")"
  for pkg in "${HARDEN_TARGETS[@]}"; do
    is_installed "$pkg" || continue
    is_protected "$pkg" && continue
    any=1
    P_I=$((P_I+1)); printf '    %b[%3d/%-3d %3d%%]%b restricting %s ... ' "$c_h" "$P_I" "$P_N" "$(( P_N>0 ? P_I*100/P_N : 100 ))" "$c_0" "$pkg"
    local cmds="cmd appops set $pkg RUN_ANY_IN_BACKGROUND ignore; cmd appops set $pkg RUN_IN_BACKGROUND ignore; am set-standby-bucket $pkg restricted"
    for perm in $HARDEN_PERMS; do cmds+="; pm revoke $pkg android.permission.$perm"; done
    act sh -c "'$cmds' 2>/dev/null; true" >/dev/null
    echo "done"
    [[ $DRY == 0 ]] && echo "$pkg" >> "$LOG_HARDENED"
    ok "restricted $pkg (it will ask again for permissions when you open it)"
  done
  progress_end
  [[ $any == 0 ]] && ok "No user-facing Google apps left to restrict"
}

step_restore() {
  head_ "Restoring"
  if [[ -f "$DEV_DIR/motion-locked" ]]; then
    act_long "for p in \$(pm list packages -e --user 0 | cut -d: -f2); do cmd appops set \$p ACTIVITY_RECOGNITION default 2>/dev/null; done; echo done" >/dev/null
    ok "movement detection allowed again (apps will ask for permissions when needed)"
  fi
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

telemetry_candidates() {
  local tmp; tmp="$(mktemp)"
  printf '%s\n' "$INSTALLED" > "$tmp"
  python3 -I - "$UAD_CACHE" "$tmp" <<'PY'
import json, re, sys
uad = json.load(open(sys.argv[1]))
installed = set(open(sys.argv[2]).read().split())
tele = re.compile(r'telemetr|analytic|tracking|tracker|diagnos|data collect|collection|collects|usage data|statistic|'
                  r'crash report|bug ?report|log ?collect|logs? service|dumplog|feedback|advertis|\bads\b|spyware|user behavio', re.I)
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
  progress_start "${#go[@]}"; for pkg in "${go[@]}"; do remove_pkg "$pkg"; done; progress_end
  refresh_installed
}

KEEP_FILE="$STATE_DIR/keep-apps.txt"
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

compute_keep() {
  {
    printf '%s\n' $NEVER_TOUCH $KEEP_ALWAYS $KEEP_EXTRA
    printf '%s\n' "${FDROID_APPS[@]%%|*}" "${PLAY_APPS[@]%%|*}" "$IRONFOX_PKG" "${LAUNCHER_PKG:-}"
    echo "$CAMERA_PKG"
    local r
    for r in DIALER SMS HOME BROWSER; do ash cmd role get-role-holders "android.app.role.$r" | tr ';, ' '\n\n\n'; done
    ash cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME | grep -o '[A-Za-z0-9_.]*/' | tr -d /
    ash cmd package query-activities --brief -a com.android.camera.action.REVIEW -t 'image/*' | grep -o '[A-Za-z0-9_.]*/' | tr -d /
    ash cmd package query-activities --brief -a android.intent.action.SET_ALARM | grep -o '[A-Za-z0-9_.]*/' | tr -d /
    ash cmd package query-activities --brief -a android.intent.action.INSERT -t vnd.android.cursor.dir/contact | grep -o '[A-Za-z0-9_.]*/' | tr -d /
    ash settings get secure default_input_method | cut -d/ -f1
    [[ -f "$KEEP_FILE" ]] && grep -vE '^[[:space:]]*(#|$)' "$KEEP_FILE"
    [[ $PHOTOS_NEEDED == 1 ]] && echo "$PHOTOS_PKG"
  } | grep -vxF -f <(printf '%s\n' "${OEM_PKGS[@]}") | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -E '^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)+$' \
    | { if [[ $PHOTOS_NEEDED == 1 ]]; then cat; else grep -vx "$PHOTOS_PKG"; fi; } | sort -u
}

sweep_candidates() {
  local drawer system pkg repl keep
  keep="$(compute_keep)"
  drawer="$(ash cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER \
            | grep -o '[A-Za-z0-9_.]*/' | tr -d / | sort -u)"
  system="$(ash pm list packages -s --user 0 | sed 's/^package://')"
  for pkg in $drawer; do
    grep -qx "$pkg" <<<"$system" || continue
    is_protected "$pkg" && { echo "$pkg|keep"; continue; }
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
  progress_start "${#go[@]}"; for pkg in "${go[@]}"; do remove_pkg "$pkg"; done; progress_end
  refresh_installed
}

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
    if ! grep -qx "$pkg" <<<"$all"; then continue
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
secure clock_seconds 1
system status_bar_show_battery_percent 1
global window_animation_scale 0
global transition_animation_scale 0
global animator_duration_scale 0
secure lockdown_in_power_menu 1
global wifi_networks_available_notification_on 0
EOV

  say "  Movement tracking:"
  v="$(ash cmd appops get com.google.android.gms ACTIVITY_RECOGNITION)"
  if [[ "$v" == *ignore* || "$v" == *deny* ]]; then printf '    %b  Play Services cannot detect driving or walking\n' "$P"
  else printf '    %b  Play Services activity recognition: %s (run: bash android-lockdown.sh motion)\n' "$F" "${v:-unknown}"; fails=$((fails+1)); fi
  v="$(ash cmd appops query-op --user 0 ACTIVITY_RECOGNITION allow | grep -v '^$' | tr '\n' ' ')"
  if [[ -z "${v// /}" ]]; then printf '    %b  no app can detect driving or walking\n' "$P"
  else printf '    %b  still allowed to detect movement: %s\n' "$F" "$v"; fails=$((fails+1)); fi

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
    grep -qx "$pkg" <<<"$all" || continue
    grep -qx "$pkg" <<<"$en" && printf '    %b  %s\n' "$P" "$pkg" || { printf '    %b  %s is DISABLED\n' "$F" "$pkg"; fails=$((fails+1)); }
  done
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
  local mk="${MAKER:-none}|${BRAND:-none}"; [[ $PROFILE == samsung ]] && mk+="|sec"; [[ $PROFILE == xiaomi ]] && mk+="|miui"
  [[ $PROFILE == oplus ]] && mk+="|oplus|coloros|heytap|nearme"; [[ $PROFILE == google ]] && mk+="|google\\.android\\.apps\\.pixel"
  for pkg in $(grep -Ei "^com\\.($mk)\\.|aura|facebook|glimpse|essential" <<<"$all" | sort); do
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

device_checklist() {
  if [[ "$MTE_SUPPORTED" == 1 ]]; then cat <<'EOD'

  HARDWARE EXPLOIT PROTECTION (this phone supports it)
   2. Developer options → Memory Tagging Extension → On → reboot.
      Then re-test Wallet. If any app crashes, turn it back off.
EOD
  fi
  case $PROFILE in
    google) cat <<'EOD'
   • Open Auditor (GrapheneOS app) → pair with a second phone, or use remote
     attestation to verify the OS hasn't been tampered with.
EOD
    ;;
    nothing) cat <<'EOD'

  NOTHING OS EXTRAS  (search these words in Settings; names vary between versions)
   • "Glimpse": Lock Glimpse OFF (internet feed on the lock screen).
   • "Essential Key": assign it to something else or turn it off.
   • "Intelligence": turn off every AI feature in the Intelligence toolkit.
   • "diagnostic": Nothing's own experience/diagnostics sharing OFF.
   • If you keep the Nothing Launcher: Home settings → Discover / Google News feed OFF.
EOD
    ;;
    *) cat <<'EOD'

  PHONE-MAKER EXTRAS
   • In Settings, search "diagnostic", "improvement" and "recommend" and turn those off.
   • Run './android-lockdown.sh scan' to review the maker's remaining apps.
EOD
    ;;
  esac
}

checklist_full() {
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

MENU_ITEMS=(
  "all|Full run: everything below, in order (recommended first time)"
  "apps|Install privacy apps + make Lawnchair the home screen"
  "debloat|Remove Google apps, AI, maker extras + telemetry + sweep"
  "telemetry|Phone-maker telemetry only"
  "sweep|Disable unneeded pre-installed apps in the app drawer"
  "motion|Block movement / driving / body-sensor / background-location tracking"
  "camera|Camera without location + pick the photo viewer"
  "settings|Network & privacy settings, clock seconds, battery %, no animations"
  "lock|Lock screen, power menu, NFC, SIM"
  "manual|Walk through the settings you change on the phone"
  "launcher|Make Lawnchair the default home screen"
  "harden|Restrict Google apps you kept"
  "verify|PASS/FAIL check of the phone (changes nothing)"
  "scan|List every app and what the script does with it (changes nothing)"
  "install|Sideload APK file(s) over USB"
  "restore|UNDO everything on this phone"
)
show_menu() {
  echo
  echo "${c_h}== android-lockdown: what do you want to do? ==${c_0}"
  local i=1 e
  for e in "${MENU_ITEMS[@]}"; do
    printf '  %b%2d%b) %-10s %s\n' "$c_ok" "$i" "$c_0" "${e%%|*}" "${e#*|}"; i=$((i+1))
  done
  echo
  printf '   %bd%b) dry run is %s (toggle: show what would happen, change nothing)\n' "$c_ok" "$c_0" "$( [[ $DRY == 1 ]] && echo "${c_warn}ON${c_0}" || echo OFF )"
  printf '   %bq%b) quit\n' "$c_ok" "$c_0"
}
menu_loop() {
  local choice mode apks
  while true; do
    show_menu
    read -r -p "  Choose [1-${#MENU_ITEMS[@]}, d, q]: " choice
    case "$choice" in
      q|Q|"") echo "  Bye."; return 0 ;;
      d|D) DRY=$((1-DRY)); continue ;;
      *[!0-9]*) warn "Not a valid choice"; continue ;;
    esac
    if (( choice < 1 || choice > ${#MENU_ITEMS[@]} )); then warn "Not a valid choice"; continue; fi
    mode="${MENU_ITEMS[$((choice-1))]%%|*}"
    logline "=== menu: $mode (dry_run=$DRY) ==="
    case "$mode" in
      install)
        read -r -p "  Path(s) to the .apk file(s), separated by spaces: " apks
        run_mode install $apks ;;
      restore)
        if confirm "Really undo EVERYTHING on this phone?"; then run_mode restore; fi ;;
      *) run_mode "$mode" ;;
    esac
    echo
    read -r -p "  Done. Press Enter to go back to the menu..." _
  done
}

run_mode() {
  local MODE=$1; shift
  ARGS=("$MODE" "$@")
  case "$MODE" in
    all)
      preflight
      pause "Before starting, check that Wallet works and that your photos are backed up"
      local steps=(apps debloat telemetry sweep camera settings lock guided harden motion verify scan)
      local i=0 st
      for st in "${steps[@]}"; do
        i=$((i+1))
        echo
        printf '%b######## STEP %d of %d  [%-24s] %3d%% done before this step ########%b\n' "$c_h" "$i" "${#steps[@]}" \
          "$(printf '%*s' $(( (i-1)*24/${#steps[@]} )) '' | tr ' ' '#')" $(( (i-1)*100/${#steps[@]} )) "$c_0"
        "step_$st"
      done
      echo; printf '%b######## ALL %d STEPS DONE  [########################] 100%% ########%b\n' "$c_h" "${#steps[@]}" "$c_0"
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
    harden)   preflight; step_harden; step_motion; step_verify ;;
    motion)   preflight; step_motion; step_verify ;;
    camera)   preflight; step_camera; step_verify ;;
    restore)  preflight; step_restore ;;
    status)   preflight; step_status ;;
    install)
      ensure_adb; wait_for_phone
      [[ ${#ARGS[@]} -gt 1 ]] || die "Usage: $0 install app1.apk [app2.apk ...]"
      for apk in "${ARGS[@]:1}"; do echo -n "$apk: "; adb_install "$apk" | tail -1; done
      ;;
    *) die "Unknown mode '$MODE'. Use: all | apps | motion | launcher | debloat | telemetry | sweep | manual | verify | scan | camera | settings | lock | harden | install | status | restore" ;;
  esac
}

MODE=""; ARGS=()
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --yes|-y)  YES=1 ;;
    *)         ARGS+=("$a") ;;
  esac
done
if [[ ${#ARGS[@]} -gt 0 ]]; then MODE="${ARGS[0]}"
elif [[ -t 0 && $YES == 0 ]]; then MODE="menu"
else MODE="all"; fi
setup_logging

if [[ "$MODE" == menu ]]; then
  menu_loop
else
  run_mode "${ARGS[@]:-all}"
fi
