#!/usr/bin/env bash
# detect-project.sh — read-only inspection of a React Native / Expo project to
# decide which Revopush integration path applies. Prints a human-readable
# summary AND a machine-readable RESULT= line. Makes no changes.
#
# Usage: scripts/detect-project.sh [project-root]   (defaults to cwd)
#
# Exit codes: 0 = detected (see RESULT line), 2 = not a React Native project.

set -euo pipefail

ROOT="${1:-$(pwd)}"
PKG="$ROOT/package.json"

if [ ! -f "$PKG" ]; then
  echo "ERROR: no package.json at $ROOT — is this the project root?"
  echo "RESULT=not-react-native"
  exit 2
fi

# Pull a dependency version string from package.json (deps or devDeps).
dep_version() {
  node -e '
    const fs = require("fs");
    const p = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const name = process.argv[2];
    const v = (p.dependencies && p.dependencies[name]) ||
              (p.devDependencies && p.devDependencies[name]) || "";
    process.stdout.write(String(v));
  ' "$PKG" "$1" 2>/dev/null || true
}

RN_RAW="$(dep_version react-native)"
EXPO_RAW="$(dep_version expo)"
REVOPUSH_RAW="$(dep_version @revopush/react-native-code-push)"
MS_CODEPUSH_RAW="$(dep_version react-native-code-push)"

if [ -z "$RN_RAW" ] && [ -z "$EXPO_RAW" ]; then
  echo "ERROR: neither 'react-native' nor 'expo' found in dependencies."
  echo "RESULT=not-react-native"
  exit 2
fi

# Strip a leading semver range (^, ~, >=, etc.) down to MAJOR.MINOR.
clean_version() {
  echo "$1" | sed -E 's/[^0-9]*([0-9]+\.[0-9]+).*/\1/'
}
RN_VER="$(clean_version "$RN_RAW")"
EXPO_VER="$(clean_version "$EXPO_RAW")"

# Compare MAJOR.MINOR >= threshold. Args: "0.76" "0.76" -> 0 (true).
ge_version() {
  node -e '
    const a = process.argv[1].split(".").map(Number);
    const b = process.argv[2].split(".").map(Number);
    const ok = a[0] > b[0] || (a[0] === b[0] && (a[1]||0) >= (b[1]||0));
    process.exit(ok ? 0 : 1);
  ' "$1" "$2" 2>/dev/null
}

HAS_IOS="no";     [ -d "$ROOT/ios" ] && HAS_IOS="yes"
HAS_ANDROID="no"; [ -d "$ROOT/android" ] && HAS_ANDROID="yes"

# Native source variants — so the agent knows which reference section to apply.
IOS_APPDELEGATE="none"
if ls "$ROOT"/ios/*/AppDelegate.swift >/dev/null 2>&1; then IOS_APPDELEGATE="swift"
elif ls "$ROOT"/ios/*/AppDelegate.mm >/dev/null 2>&1 || ls "$ROOT"/ios/*/AppDelegate.m >/dev/null 2>&1; then IOS_APPDELEGATE="objective-c"
fi

ANDROID_GRADLE="none"
if [ -f "$ROOT/android/app/build.gradle.kts" ]; then ANDROID_GRADLE="kotlin-dsl (build.gradle.kts)"
elif [ -f "$ROOT/android/app/build.gradle" ]; then ANDROID_GRADLE="groovy (build.gradle)"
fi

ANDROID_APP="none"
MAINAPP_FILE="$(find "$ROOT/android" -name MainApplication.kt -o -name MainApplication.java 2>/dev/null | grep -v '/build/' | head -1)"
if [ -n "$MAINAPP_FILE" ]; then
  case "$MAINAPP_FILE" in *.kt) ANDROID_APP="kotlin";; *.java) ANDROID_APP="java";; esac
fi

# Android host pattern decides which MainApplication wiring to use (android.md 3a vs 3b).
# The deciding factor is whether a DefaultReactNativeHost exists — NOT whether New
# Architecture is on. RN 0.76–0.82 New-Arch templates STILL have a
# DefaultReactNativeHost and a `reactHost` getter of the 2-arg form
# getDefaultReactHost(context, reactNativeHost) that DELEGATES to it, so they use
# the getJSBundleFile() override (3a). Only RN 0.83+ bridgeless templates build the
# host purely via getDefaultReactHost(packageList = …) with NO DefaultReactNativeHost,
# and there you pass jsBundleFilePath (3b). So check DefaultReactNativeHost first.
ANDROID_HOST="unknown"
if [ -n "$MAINAPP_FILE" ]; then
  if grep -qs 'DefaultReactNativeHost' "$MAINAPP_FILE"; then
    ANDROID_HOST="DefaultReactNativeHost present → override getJSBundleFile() (android.md 3a; correct even on New Arch with the 2-arg getDefaultReactHost(context, reactNativeHost))"
  elif grep -qsE 'getDefaultReactHost' "$MAINAPP_FILE"; then
    ANDROID_HOST="bridgeless getDefaultReactHost(packageList = …), no DefaultReactNativeHost → pass jsBundleFilePath (android.md 3b)"
  fi
fi

# New Architecture hints (best-effort, non-authoritative).
NEW_ARCH="unknown"
if grep -rqs "newArchEnabled=true" "$ROOT/android/gradle.properties" 2>/dev/null; then
  NEW_ARCH="yes"
elif grep -rqs '"newArchEnabled":[[:space:]]*true' "$ROOT/app.json" "$ROOT/app.config.js" 2>/dev/null; then
  NEW_ARCH="yes"
fi

# Decide the path.
IS_EXPO="no"; [ -n "$EXPO_VER" ] && IS_EXPO="yes"

PATH_RESULT="unknown"
REASON=""
if [ "$IS_EXPO" = "yes" ] && [ -n "$EXPO_VER" ]; then
  if ge_version "$EXPO_VER" "52.0"; then
    PATH_RESULT="expo"
    REASON="Expo SDK $EXPO_VER (>= 52) — use the config-plugin path."
  else
    PATH_RESULT="unsupported-expo"
    REASON="Expo SDK $EXPO_VER is below 52; Revopush needs Expo SDK 52+."
  fi
elif [ -n "$RN_VER" ]; then
  if ge_version "$RN_VER" "0.76"; then
    PATH_RESULT="bare-rn"
    REASON="Bare React Native $RN_VER (>= 0.76) — use the native-edits path."
  else
    PATH_RESULT="unsupported-rn"
    REASON="React Native $RN_VER is below 0.76; Revopush needs RN 0.76+ (use Microsoft CodePush, or upgrade)."
  fi
fi

echo "==================== Revopush project detection ===================="
echo "Project root      : $ROOT"
echo "react-native      : ${RN_RAW:-<none>}  (parsed: ${RN_VER:-?})"
echo "expo              : ${EXPO_RAW:-<none>}  (parsed: ${EXPO_VER:-?})"
echo "ios/ folder       : $HAS_IOS"
echo "android/ folder   : $HAS_ANDROID"
echo "iOS AppDelegate   : $IOS_APPDELEGATE"
echo "Android build      : $ANDROID_GRADLE"
echo "Android app class : $ANDROID_APP"
echo "Android host       : $ANDROID_HOST"
echo "New Architecture  : $NEW_ARCH"
if [ -n "$REVOPUSH_RAW" ]; then
  echo "NOTE: @revopush/react-native-code-push already present ($REVOPUSH_RAW) — integration may be partially done."
fi
if [ -n "$MS_CODEPUSH_RAW" ]; then
  echo "NOTE: Microsoft react-native-code-push present ($MS_CODEPUSH_RAW) — this is a migration; plan to replace it with @revopush/react-native-code-push."
fi
if [ "$PATH_RESULT" = "expo" ] && { [ "$HAS_IOS" = "yes" ] || [ "$HAS_ANDROID" = "yes" ]; }; then
  echo "WARNING: 'expo' is a dependency AND committed ios/ and/or android/ folders exist."
  echo "         If this is a MANAGED Expo app (CNG), use the Expo config-plugin path; 'npx expo prebuild --clean' regenerates native code."
  echo "         But if it's a BARE app that only uses expo modules and you maintain ios/android by hand, use the BARE path instead and do NOT run prebuild --clean (it would overwrite your native code). Confirm which workflow with the user before editing."
fi
echo "--------------------------------------------------------------------"
echo "Decision: $REASON"
echo "===================================================================="
echo "RESULT=$PATH_RESULT"
