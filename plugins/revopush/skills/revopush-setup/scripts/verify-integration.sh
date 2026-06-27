#!/usr/bin/env bash
# verify-integration.sh — static completeness check for a Revopush integration.
# Read-only. Prints PASS / WARN / FAIL per check and a summary. Exit 0 if no FAIL.
#
# Usage: scripts/verify-integration.sh [project-root]   (defaults to cwd)
#
# WARN = something to confirm (e.g. placeholder keys, 1.x SDK). FAIL = missing
# wiring that will break OTA. This does not run a build — it checks files only.

set -uo pipefail
ROOT="${1:-$(pwd)}"
PKG="$ROOT/package.json"
pass=0; warn=0; fail=0

ok()   { echo "  PASS  $1"; pass=$((pass+1)); }
wn()   { echo "  WARN  $1"; warn=$((warn+1)); }
no()   { echo "  FAIL  $1"; fail=$((fail+1)); }

has() { grep -rqs "$1" "${@:2}" 2>/dev/null; }
# Find the project's own file, skipping vendored/generated trees (Pods, build,
# node_modules, DerivedData) that contain many same-named files (e.g. dozens of
# Pods/*/Info.plist). Without these excludes, `find ... | head` grabs the wrong one.
firstfile() {
  find "$@" \
    -not -path '*/Pods/*' -not -path '*/build/*' \
    -not -path '*/node_modules/*' -not -path '*/DerivedData/*' \
    2>/dev/null | head -n1
}

if [ ! -f "$PKG" ]; then
  echo "FAIL: no package.json at $ROOT"; exit 2
fi

echo "==================== Revopush integration check ===================="
echo "Project: $ROOT"

IS_EXPO="$(node -e 'try{const p=require(process.argv[1]);process.stdout.write(((p.dependencies||{}).expo)?"yes":"no")}catch(e){process.stdout.write("no")}' "$PKG" 2>/dev/null)"

# ---- SDK dependency ----
SDK_VER="$(node -e 'try{const p=require(process.argv[1]);const v=(p.dependencies||{})["@revopush/react-native-code-push"]||(p.devDependencies||{})["@revopush/react-native-code-push"];process.stdout.write(v||"")}catch(e){}' "$PKG" 2>/dev/null)"
if [ -n "$SDK_VER" ]; then
  ok "@revopush/react-native-code-push in package.json ($SDK_VER)"
  case "$SDK_VER" in
    *2.*|*"^2"*|*"~2"*) : ;;
    *1.*|*"^1"*|*"~1"*) wn "SDK is on the 1.x line ($SDK_VER) — 2.x is recommended for differential updates (see versions.md)";;
  esac
elif [ "$IS_EXPO" = "yes" ]; then
  wn "@revopush/react-native-code-push not yet in package.json — run 'npx expo install @revopush/react-native-code-push@2.5.1' (added by expo install, not hand-edited)"
else
  no "@revopush/react-native-code-push not found in package.json"
fi
if has '"react-native-code-push"' "$PKG"; then
  wn "Microsoft 'react-native-code-push' still in package.json — finish the migration (see migration.md)"
fi

# ---- JS wrap / usage ----
if has 'codePush(' "$ROOT/App.tsx" "$ROOT/App.js" "$ROOT/src" "$ROOT/app" 2>/dev/null \
   || grep -rqs --include=*.ts --include=*.tsx --include=*.js --include=*.jsx 'codePush(' "$ROOT/app" "$ROOT/src" 2>/dev/null; then
  ok "codePush() used in JS (HOC wrap or manual sync flow)"
elif grep -rqs --include=*.ts --include=*.tsx --include=*.js 'codePush\.\(sync\|checkForUpdate\)' "$ROOT" 2>/dev/null; then
  ok "manual codePush.sync()/checkForUpdate() used in JS"
else
  no "no codePush() wrap or codePush.sync()/checkForUpdate() found in JS — the SDK is installed but never invoked"
fi

# ---- Expo config (when the managed config plugin is in use) ----
if [ "$IS_EXPO" = "yes" ]; then
  echo "-- Expo (config-plugin) --"
  CFGS=("$ROOT/app.json" "$ROOT/app.config.js" "$ROOT/app.config.ts")
  if has '@revopush/expo-code-push-plugin' "${CFGS[@]}"; then ok "@revopush/expo-code-push-plugin configured in app config"; else no "@revopush/expo-code-push-plugin not found in app.json / app.config.* plugins"; fi
  if has 'CodePushServerUrl' "${CFGS[@]}"; then ok "CodePushServerUrl set in Expo config"; else no "CodePushServerUrl missing from the Expo config plugin"; fi
  if has 'CodePushDeploymentKey' "${CFGS[@]}"; then ok "CodePushDeploymentKey present in Expo config"; else no "CodePushDeploymentKey missing from the Expo config plugin"; fi
  if [ ! -d "$ROOT/ios" ] && [ ! -d "$ROOT/android" ]; then
    wn "no ios/ or android/ yet — run 'npx expo prebuild --clean', then re-run this check to confirm the plugin actually wired the native code (it can silently mis-wire; see expo.md step 6)"
  fi
fi

# ---- iOS native (bare, OR prebuilt Expo) ----
if [ -d "$ROOT/ios" ]; then
  echo "-- iOS --"
  APPD="$(firstfile "$ROOT/ios" -name 'AppDelegate.swift' -o -name 'AppDelegate.mm' -o -name 'AppDelegate.m')"
  if [ -n "$APPD" ] && grep -qs 'CodePush' "$APPD"; then
    ok "AppDelegate references CodePush ($(basename "$APPD"))"
  else
    no "AppDelegate does not reference CodePush (release bundle URL not wired)"
  fi
  # Search every app Info.plist (skipping the dozens of Pods/build copies) rather
  # than picking one file — a Tests or Pods plist would otherwise false-fail.
  plist_has() { grep -rqs --include='Info.plist' --exclude-dir=Pods --exclude-dir=build --exclude-dir=DerivedData "$1" "$ROOT/ios" 2>/dev/null; }
  if plist_has 'CodePushServerURL'; then ok "Info.plist has CodePushServerURL"; else no "Info.plist missing CodePushServerURL (note iOS uppercase URL)"; fi
  if plist_has 'CodePushDeploymentKey'; then ok "Info.plist has CodePushDeploymentKey"; else no "Info.plist missing CodePushDeploymentKey"; fi
  POD="$ROOT/ios/Podfile"
  if [ -f "$POD" ]; then
    PV="$(grep -oE "platform :ios, *['\"][0-9.]+['\"]" "$POD" | grep -oE "[0-9]+\.[0-9]+" | head -1)"
    if [ -n "$PV" ]; then
      if node -e 'const a=process.argv[1].split(".").map(Number);process.exit((a[0]>15||(a[0]===15&&a[1]>=5))?0:1)' "$PV"; then
        ok "Podfile iOS target $PV (>= 15.5)"
      else
        no "Podfile iOS target $PV is below the required 15.5"
      fi
    elif grep -qsE "^[[:space:]]*platform :ios," "$POD"; then
      wn "Podfile sets 'platform :ios' via a variable (e.g. min_ios_version_supported, 15.1) — confirm it resolves to >= 15.5, or pin platform :ios, '15.5' per ios.md"
    else
      wn "Podfile has no 'platform :ios' line"
    fi
  fi
fi

# ---- Android native (bare, OR prebuilt Expo) ----
if [ -d "$ROOT/android" ]; then
  echo "-- Android --"
  GR="$(firstfile "$ROOT/android/app" -name 'build.gradle.kts' -o -name 'build.gradle')"
  if [ -n "$GR" ] && grep -qs '@revopush/react-native-code-push/android/codepush.gradle' "$GR"; then
    ok "codepush.gradle applied in $(basename "$GR")"
  elif [ -n "$GR" ] && grep -qs 'react-native-code-push/android/codepush.gradle' "$GR"; then
    wn "codepush.gradle is applied from the OLD react-native-code-push path, not @revopush — finish the migration (see migration.md)"
  else
    no "codepush.gradle not applied in android/app/build.gradle(.kts)"
  fi
  MAINAPP="$(firstfile "$ROOT/android" -name 'MainApplication.kt' -o -name 'MainApplication.java')"
  if [ -n "$MAINAPP" ] && grep -qsE 'getJSBundleFile|jsBundleFilePath' "$MAINAPP"; then
    ok "MainApplication wires the CodePush JS bundle (getJSBundleFile override or getDefaultReactHost jsBundleFilePath) ($(basename "$MAINAPP"))"
  else
    no "MainApplication does not wire the CodePush JS bundle (getJSBundleFile() override, or jsBundleFilePath on New Architecture)"
  fi
  STR="$(firstfile "$ROOT/android" -name 'strings.xml' -path '*values*')"
  if [ -n "$STR" ] && grep -qs 'CodePushServerUrl' "$STR"; then ok "strings.xml has CodePushServerUrl"; else no "strings.xml missing CodePushServerUrl (note Android lowercase Url)"; fi
  if [ -n "$STR" ] && grep -qs 'CodePushDeploymentKey' "$STR"; then ok "strings.xml has CodePushDeploymentKey"; else no "strings.xml missing CodePushDeploymentKey"; fi
fi

# ---- placeholder keys ----
if grep -rqs -E 'YOUR_(IOS_|ANDROID_)?DEPLOYMENT_KEY|YOUR_DEPLOYMENT_KEY' \
     "$ROOT/ios" "$ROOT/android" "$ROOT/app.json" "$ROOT/app.config.js" "$ROOT/app.config.ts" 2>/dev/null; then
  wn "placeholder deployment key(s) still present — replace with real keys from app.revopush.org before releasing"
fi

echo "--------------------------------------------------------------------"
echo "Summary: $pass passed, $warn warning(s), $fail failure(s)."
if [ "$fail" -gt 0 ]; then
  echo "RESULT=incomplete"; exit 1
else
  echo "RESULT=ok"; exit 0
fi
