# Expo integration (SDK 52+)

For Expo apps (SDK 52+), Revopush ships an Expo **config plugin** that writes the
native wiring during prebuild — you do not edit `ios/`/`android/` by hand.
Revopush does **not** work in Expo Go (it needs native code), so the user must
use a dev/native build. Follow the live step-by-step at
https://docs.revopush.org/intro/expo as the source of truth.

## 1. Install BOTH packages — with explicit versions

Two packages are required: the **SDK** and the **config plugin**. Pin both
explicitly — these packages are **not** in Expo's bundled-module compatibility
metadata, so a bare `npx expo install @revopush/...` resolves to the npm `latest`
tag, which can pair an SDK and plugin version that weren't tested together.

Use the **2.x SDK** (for differential updates — see `versions.md`) plus the
current **plugin `1.1.0`**:

```bash
# Pick the SDK version by the React Native version under your Expo SDK
# (see versions.md): 0.76–0.82 -> 2.5.1, 0.83+ -> 2.6.x.
npx expo install @revopush/react-native-code-push@2.5.1
npx expo install @revopush/expo-code-push-plugin@1.1.0
```

If you're unsure which RN version your Expo SDK uses, check `npx expo config` or
the Expo SDK release notes, then apply the `versions.md` table. Confirm the latest
plugin with `npm view @revopush/expo-code-push-plugin version`.

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

## 6. Verify

Build a dev/native build (not Expo Go):

```bash
npx expo run:ios     # or run:android
```

Then cut a test release with the CLI (see `cli-and-releases.md`) and confirm the
update is delivered.
