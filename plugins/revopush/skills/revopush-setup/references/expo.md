# Expo integration (SDK 52+)

For Expo apps (SDK 52+), Revopush ships an Expo **config plugin** that writes the
native wiring during prebuild — you do not edit `ios/`/`android/` by hand.
Revopush does **not** work in Expo Go (it needs native code), so the user must
use a dev/native build. Follow the live step-by-step at
https://docs.revopush.org/intro/expo as the source of truth.

## 1. Install BOTH packages — pin the plugin by Expo SDK

Two packages are required: the **SDK** and the **config plugin**. Pin both
explicitly — they are **not** in Expo's bundled-module compatibility metadata, so
a bare `npx expo install @revopush/...` resolves to the npm `latest` tag.

**Pin the SDK and the config plugin as a matched pair, keyed by Expo SDK.** The
SDK stays on the **2.x line** (differential updates, per `versions.md`); the
**plugin version is decoupled** and must match the Expo SDK, because the plugin
writes the Android wiring by *inspecting* the generated `MainApplication.kt`.
Plugin `1.0.1` is built for the SDK 52–54 host shape; **plugin `1.1.0` mis-wires
SDK 52–54** (silently inserts no Android bundle wiring). Use the matched pair:

| Expo SDK | Revopush SDK | Revopush Expo plugin |
|---|---|---|
| 52 – 54 | `@revopush/react-native-code-push@2.5.1` | `@revopush/expo-code-push-plugin@1.0.1` |
| 55 | `@revopush/react-native-code-push@2.6.0` | `@revopush/expo-code-push-plugin@1.1.0` |

```bash
# Expo SDK 52–54:
npx expo install @revopush/react-native-code-push@2.5.1 @revopush/expo-code-push-plugin@1.0.1
# Expo SDK 55:
npx expo install @revopush/react-native-code-push@2.6.0 @revopush/expo-code-push-plugin@1.1.0
```

For Expo SDK **newer than 55**, check the current pairing on
`docs.revopush.org/intro/expo` (or `npm view @revopush/expo-code-push-plugin versions`).
Don't rely on `npx expo install` auto-resolve (these packages aren't in Expo's
compat metadata, so it grabs the `latest` tag, which can pair the wrong plugin
with your SDK). Use `npx expo config` to see the RN version under your Expo SDK.

## 2. Add the config plugin

Add the plugin to the `plugins` array in `app.json` or `app.config.js`. Fill in
the user's iOS and Android deployment keys — ask for them, or point them at
https://app.revopush.org to sign up, log in, and create an app + deployments (see
`cli-and-releases.md`). Use placeholders only if they have no keys yet.

```json
[
  "@revopush/expo-code-push-plugin",
  {
    "ios": {
      "CodePushDeploymentKey": "YOUR_IOS_DEPLOYMENT_KEY",
      "CodePushServerUrl": "https://api.revopush.org"
    },
    "android": {
      "CodePushDeploymentKey": "YOUR_ANDROID_DEPLOYMENT_KEY",
      "CodePushServerUrl": "https://api.revopush.org"
    }
  }
]
```

> In the Expo config plugin, **both** platforms use `CodePushServerUrl`
> (lowercase `rl`) and the hosted URL `https://api.revopush.org`. Do not point it
> at any other server — Revopush is hosted-only.

In `app.config.js` the same value is a JS array entry inside the returned
`plugins: [...]`.

## 3. Prebuild

Regenerate the native projects so the plugin's edits are applied:

```bash
npx expo prebuild --clean
```

## 4. iOS deployment target (if needed)

If prebuild or the iOS build reports a deployment-target error, add
`expo-build-properties` and set the iOS target to 15.5:

```json
[
  "expo-build-properties",
  { "ios": { "deploymentTarget": "15.5" } }
]
```

Add this as another entry in the same `plugins` array, then re-run
`npx expo prebuild --clean`.

## 5. JS entry point

Wrap the root component with the `codePush()` HOC. For Expo Router this is the
root layout:

```javascript
import codePush from "@revopush/react-native-code-push";

// ...your RootLayout component...

export default codePush(RootLayout);
```

See `js-api.md` for HOC options and for the manual `sync()` / `checkForUpdate()`
flow if the user wants custom update UX. `scripts/wrap-entry.js` can apply the
wrap idempotently with a backup.

## 6. Verify the prebuild actually wired the native code

**Don't assume the config plugin succeeded.** It edits generated files by pattern
matching, and those patterns can drift from the current Expo/RN template — known
cases include the Android host-shape mismatch (above) and an iOS regex that misses
the modern Swift *implicit-return* `bundleURL()`. A mis-wire produces **no error**
and a build that simply never applies OTA updates.

After `npx expo prebuild --clean`, check the generated native files:

```bash
scripts/verify-integration.sh        # now also inspects the prebuilt ios/ + android/
```

Confirm specifically:
- iOS `ios/<App>/AppDelegate.*` returns `CodePush.bundleURL()` on the release path,
  Podfile target ≥ 15.5, and `Info.plist` has `CodePushServerURL` + the key.
- Android `android/app/build.gradle` applies `codepush.gradle`, `MainApplication`
  wires the bundle (per `android.md` §3a/§3b), and `strings.xml` has
  `CodePushServerUrl` + the key.

**If anything is missing, apply the bare-path edits by hand** (`ios.md` /
`android.md`) to the prebuilt `ios/`/`android/` — you now have real native
projects. Do this **after** your final `prebuild --clean`, since prebuild
regenerates native code and would overwrite manual edits.

Then build a dev/native build (not Expo Go) and confirm delivery:

```bash
npx expo run:ios     # or run:android
```

Cut a test release with the CLI (see `cli-and-releases.md`) and confirm the update
is delivered.
