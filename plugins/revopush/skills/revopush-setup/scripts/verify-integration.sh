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
firstfile() { find "$@" 2>/dev/null | head -n1; }

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

if [ "$IS_EXPO" = "yes" ]; then
  echo "-- Expo (config-plugin) --"
  CFG="$(firstfile "$ROOT" -maxdepth 1 -name 'app.json' -o -maxdepth 1 -name 'app.config.js' -o -maxdepth 1 -name 'app.config.ts')"
  if has '@revopush/expo-code-push-plugin' "$ROOT/app.json" "$ROOT/app.config.js" "$ROOT/app.config.ts"; then
    ok "@revopush/expo-code-push-plugin configured in app config"
  else
    no "@revopush/expo-code-push-plugin not found in app.json / app.config.* plugins"
  fi
  if has 'CodePushServerUrl' "$ROOT/app.json" "$ROOT/app.config.js" "$ROOT/app.config.ts"; then
    ok "CodePushServerUrl set in Expo config"
  else
    no "CodePushServerUrl missing from the Expo config plugin"
  fi
  if has 'CodePushDeploymentKey' "$ROOT/app.json" "$ROOT/app.config.js" "$ROOT/app.config.ts"; then
    ok "CodePushDeploymentKey present in Expo config"
  else
    no "CodePushDeploymentKey missing from the Expo config plugin"
  fi
else
  echo "-- iOS (bare) --"
  APPD="$(firstfile "$ROOT/ios" -name 'AppDelegate.swift' -o -name 'AppDelegate.mm' -o -name 'AppDelegate.m')"
  if [ -n "$APPD" ] && grep -qs 'CodePush' "$APPD"; then
    ok "AppDelegate references CodePush ($(basename "$APPD"))"
  else
    no "AppDelegate does not reference CodePush (release bundle URL not wired)"
  fi
  PLIST="$(firstfile "$ROOT/ios" -name 'Info.plist')"
  if [ -n "$PLIST" ] && grep -qs 'CodePushServerURL' "$PLIST"; then ok "Info.plist has CodePushServerURL"; else no "Info.plist missing CodePushServerURL (note iOS uppercase URL)"; fi
  if [ -n "$PLIST" ] && grep -qs 'CodePushDeploymentKey' "$PLIST"; then ok "Info.plist has CodePushDeploymentKey"; else no "Info.plist missing CodePushDeploymentKey"; fi
  POD="$ROOT/ios/Podfile"
  if [ -f "$POD" ]; then
    PV="$(grep -oE "platform :ios, *'[0-9.]+'" "$POD" | grep -oE "[0-9]+\.[0-9]+" | head -1)"
    if [ -n "$PV" ] && node -e 'const a=process.argv[1].split(".").map(Number);process.exit((a[0]>15||(a[0]===15&&a[1]>=5))?0:1)' "$PV"; then
      ok "Podfile iOS target $PV (>= 15.5)"
    else
      no "Podfile iOS target ${PV:-unset} is below the required 15.5"
    fi
  else
    wn "no ios/Podfile found"
  fi

  echo "-- Android (bare) --"
  GR="$(firstfile "$ROOT/android/app" -name 'build.gradle.kts' -o -name 'build.gradle')"
  if [ -n "$GR" ] && grep -qs 'react-native-code-push/android/codepush.gradle' "$GR"; then
    ok "codepush.gradle applied in $(basename "$GR")"
  else
    no "codepush.gradle not applied in android/app/build.gradle(.kts)"
  fi
  MAINAPP="$(firstfile "$ROOT/android" -name 'MainApplication.kt' -o -name 'MainApplication.java')"
  if [ -n "$MAINAPP" ] && grep -qs 'getJSBundleFile' "$MAINAPP"; then
    ok "MainApplication overrides getJSBundleFile() ($(basename "$MAINAPP"))"
  else
    no "MainApplication does not override getJSBundleFile()"
  fi
  STR="$(firstfile "$ROOT/android" -name 'strings.xml' -path '*values*')"
  if [ -n "$STR" ] && grep -qs 'CodePushServerUrl' "$STR"; then ok "strings.xml has CodePushServerUrl"; else no "strings.xml missing CodePushServerUrl (note Android lowercase Url)"; fi
  if [ -n "$STR" ] && grep -qs 'CodePushDeploymentKey' "$STR"; then ok "strings.xml has CodePushDeploymentKey"; else no "strings.xml missing CodePushDeploymentKey"; fi
fi

# ---- placeholder keys ----
if grep -rqs -E 'YOUR_(IOS_|ANDROID_)?DEPLOYMENT_KEY|YOUR_DEPLOYMENT_KEY' "$ROOT/ios" "$ROOT/android" "$ROOT/app.json" "$ROOT/app.config.js" 2>/dev/null; then
  wn "placeholder deployment key(s) still present — replace with real keys from app.revopush.org before releasing"
fi

echo "--------------------------------------------------------------------"
echo "Summary: $pass passed, $warn warning(s), $fail failure(s)."
if [ "$fail" -gt 0 ]; then
  echo "RESULT=incomplete"; exit 1
else
  echo "RESULT=ok"; exit 0
fi
