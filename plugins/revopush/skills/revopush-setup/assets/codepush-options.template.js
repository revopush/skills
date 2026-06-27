// Revopush codePush() options — copy into your entry file and adjust.
// See references/js-api.md for the full option reference and the manual sync() flow.
import codePush from "@revopush/react-native-code-push";

const codePushOptions = {
  // When to check the server for updates.
  // ON_APP_START | ON_APP_RESUME | MANUAL
  checkFrequency: codePush.CheckFrequency.ON_APP_RESUME,

  // When a downloaded update is applied.
  // IMMEDIATE | ON_NEXT_RESTART | ON_NEXT_RESUME | ON_NEXT_SUSPEND
  installMode: codePush.InstallMode.ON_NEXT_RESUME,

  // With resume-based install modes, require the app to have been backgrounded
  // for this many seconds before applying — avoids interrupting active users.
  minimumBackgroundDuration: 60 * 10,

  // Set to an options object to show a prompt before applying updates.
  // updateDialog: { title: "Update available" },
};

// Usage at your root export (do NOT default-export the options object itself):
//   export default codePush(codePushOptions)(App);
export { codePushOptions };
