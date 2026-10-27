#!/usr/bin/env bash
# Google Play screenshots: raw captures of the real app, filled with made-up
# example content in one language at a time.
#
#   tool/store_shots/capture.sh [lang…]   → build/store-shots/raw/<lang>/<screen>.png
#
# Then frame them: swift tool/store_shots/frame_shots.swift [lang…]
#
# Runs a store screenshot build (--dart-define=STORE_SHOTS=true, see
# packages/base_framework/ox_common/lib/store_shots/) on a dedicated emulator,
# which it wipes: each language starts from cleared app data. The app never
# goes online in that mode. For each language this pushes
# tool/store_shots/content/<lang>.json, and the app shows each screen in turn,
# writing ready-<screen> when it has settled; this takes the picture and
# deletes the marker, and the app moves on. With no languages given, every
# content file is captured.
#
#   SERIAL=emulator-5558   the screenshot emulator (default; never the QA one)
#   BUILD=1                build the APK first (retries: Gradle downloads drop)
#   APK=…                  the APK to install (default: the profile build)
#   ADB=…, FLUTTER=…       when they are not on PATH
#
# The build: flutter build apk --profile --target-platform android-arm64 \
#              --dart-define=STORE_SHOTS=true
# Profile, not debug: no DEBUG banner, release speed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

SERIAL="${SERIAL:-emulator-5558}"
ADB="${ADB:-$(command -v adb || echo /opt/homebrew/share/android-commandlinetools/platform-tools/adb)}"
FLUTTER="${FLUTTER:-$(command -v flutter || echo "$HOME/development/flutter/bin/flutter")}"
APK="${APK:-build/app/outputs/flutter-apk/app-arm64-v8a-profile.apk}"
PKG=com.oxchat.lite
ACTIVITY=com.oxchat.nostr.MainActivity
# The app's external files dir: the app creates it, adb may write into it.
DEVICE_DIR="/sdcard/Android/data/$PKG/files/store-shots"
SCREEN_TIMEOUT=90

adb() { "$ADB" -s "$SERIAL" "$@"; }
demo() { adb shell am broadcast -a com.android.systemui.demo -e command "$@" >/dev/null; }

if [ "$#" -gt 0 ]; then
  LANGS=("$@")
else
  LANGS=()
  for f in tool/store_shots/content/*.json; do LANGS+=("$(basename "$f" .json)"); done
fi

if ! adb get-state >/dev/null 2>&1; then
  echo "$SERIAL is not running (AVD onboard_test)" >&2
  exit 1
fi

if [ "${BUILD:-}" = 1 ]; then
  if [ ! -x "$FLUTTER" ]; then
    echo "no flutter at $FLUTTER; set FLUTTER=" >&2
    exit 1
  fi
  started=$(date +%s)
  for attempt in 1 2 3 4 5 6; do
    echo "build, attempt $attempt"
    if "$FLUTTER" build apk --profile --target-platform android-arm64 --dart-define=STORE_SHOTS=true; then
      break
    fi
    sleep 5
  done
  # A failed build leaves the previous APK behind; never install that.
  if [ ! -f "$APK" ] || [ "$(stat -f %m "$APK")" -lt "$started" ]; then
    echo "build failed: $APK is missing or older than this build" >&2
    exit 1
  fi
fi

if [ ! -f "$APK" ]; then
  echo "no $APK; run with BUILD=1" >&2
  exit 1
fi
# A normal build compiles screenshot mode away, so its strings are not in it.
if ! unzip -p "$APK" lib/arm64-v8a/libapp.so | LC_ALL=C grep -ac 'store-shots' >/dev/null; then
  echo "$APK is not a store screenshot build (STORE_SHOTS=true)" >&2
  exit 1
fi
echo "installing $APK ($(stat -f '%Sm' "$APK"))"
# A profile build is debug-signed: replacing a release install means removing it.
if ! adb install -r -d "$APK" >/dev/null 2>&1; then
  adb uninstall "$PKG" >/dev/null 2>&1 || true
  adb install "$APK" >/dev/null
fi

# The status bar every screenshot shows: 9:41, full signal, full battery.
# The emulator's device-frame overlay (pixel_7 on onboard_test) draws a taller
# status bar that clips its own icons in half, so it is off while this runs.
time_12_24="$(adb shell settings get system time_12_24 | tr -d '\r')"
frames=($(adb shell cmd overlay list | tr -d '\r' | sed -n 's/^\[x\] \(com\.android\.internal\.emulation\..*\)$/\1/p'))
volumes=()
restore() {
  demo exit || true
  if [ "$time_12_24" = null ]; then
    adb shell settings delete system time_12_24 >/dev/null || true
  else
    adb shell settings put system time_12_24 "$time_12_24" || true
  fi
  for frame in ${frames[@]+"${frames[@]}"}; do
    adb shell cmd overlay enable "$frame" || true
  done
  for entry in ${volumes[@]+"${volumes[@]}"}; do
    adb shell cmd media_session volume --stream "${entry%%=*}" --set "${entry#*=}" >/dev/null || true
  done
  adb shell am force-stop "$PKG" || true
}
trap restore EXIT

if [ "${#frames[@]}" -gt 0 ]; then
  for frame in "${frames[@]}"; do adb shell cmd overlay disable "$frame"; done
  sleep 4 # SystemUI restarts
fi
adb shell settings put global sysui_demo_allowed 1
adb shell settings put system time_12_24 12

status_bar() {
  demo enter
  demo clock -e hhmm 0941
  demo network -e wifi show -e level 4 -e fully true
  # Shown once with a data type ("3G") before it takes "none"; hide it first.
  demo network -e mobile hide
  demo network -e mobile show -e slot 0 -e level 4 -e datatype none -e activity none -e fully true
  demo network -e airplane hide -e nosim hide
  demo battery -e level 100 -e plugged false -e powersave false
  demo notifications -e visible false
  demo status -e volume hide -e bluetooth hide -e location hide -e alarm hide -e zen hide \
    -e sync hide -e tty hide -e eri hide -e mute hide -e speakerphone hide -e managed_profile hide
}

# The call screen rings; keep the emulator quiet (ring, music, notification).
for stream in 2 3 5; do
  current="$(adb shell cmd media_session volume --stream "$stream" --get 2>/dev/null \
    | sed -n 's/.*volume is \([0-9]*\).*/\1/p')"
  [ -n "$current" ] && volumes+=("$stream=$current")
  adb shell cmd media_session volume --stream "$stream" --set 0 >/dev/null || true
done

capture() {
  local lang="$1"
  local content="tool/store_shots/content/$lang.json"
  local out="build/store-shots/raw/$lang"
  if [ ! -f "$content" ]; then
    echo "no $content" >&2
    return 1
  fi
  mkdir -p "$out"

  adb shell am force-stop "$PKG"
  adb shell pm clear "$PKG" >/dev/null
  adb shell rm -rf "$DEVICE_DIR"
  for permission in POST_NOTIFICATIONS RECORD_AUDIO; do
    adb shell pm grant "$PKG" "android.permission.$permission" 2>/dev/null || true
  done
  status_bar
  adb shell am start -n "$PKG/$ACTIVITY" >/dev/null

  # The app creates the folder, so that it owns it, then waits for the content.
  local deadline=$((SECONDS + 60))
  until adb shell ls "$DEVICE_DIR" >/dev/null 2>&1; do
    if [ "$SECONDS" -ge "$deadline" ]; then
      echo "$lang: the app never made $DEVICE_DIR" >&2
      return 1
    fi
    sleep 0.5
  done
  adb push "$content" "$DEVICE_DIR/content.json.part" >/dev/null 2>&1
  adb shell "chmod 644 $DEVICE_DIR/content.json.part && mv $DEVICE_DIR/content.json.part $DEVICE_DIR/content.json"

  local shots=0
  deadline=$((SECONDS + SCREEN_TIMEOUT))
  while :; do
    local listing marker screen
    listing="$(adb shell ls "$DEVICE_DIR" 2>/dev/null | tr -d '\r' || true)"
    marker="$(printf '%s\n' "$listing" | grep '^ready-' | head -n 1 || true)"
    if [ -n "$marker" ]; then
      screen="${marker#ready-}"
      adb exec-out screencap -p >"$out/$screen.png"
      adb shell rm "$DEVICE_DIR/$marker"
      echo "$lang: $screen"
      shots=$((shots + 1))
      deadline=$((SECONDS + SCREEN_TIMEOUT))
    elif printf '%s\n' "$listing" | grep -qx done; then
      break
    elif [ "$SECONDS" -ge "$deadline" ]; then
      echo "$lang: no screen for ${SCREEN_TIMEOUT}s after $shots; see adb -s $SERIAL logcat | grep StoreShots" >&2
      return 1
    fi
    sleep 0.3
  done
  adb shell am force-stop "$PKG"
  echo "$lang: $shots screens in $out"
}

failed=()
for lang in "${LANGS[@]}"; do
  capture "$lang" || failed+=("$lang")
done
if [ "${#failed[@]}" -gt 0 ]; then
  echo "failed: ${failed[*]}" >&2
  exit 1
fi
