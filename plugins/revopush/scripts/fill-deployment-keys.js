#!/usr/bin/env node
/*
 * PostToolUse hook (Claude Code): fill Revopush deployment-key placeholders.
 *
 * The plugin asks the user for their iOS / Android deployment keys through
 * `userConfig` (sensitive, kept in the platform's secure storage). Claude Code
 * exposes those values to hook processes only, as CLAUDE_PLUGIN_OPTION_<KEY>,
 * so the skill writes a placeholder and this hook swaps in the real key. The
 * key never has to be typed into the chat or read off the user's machine.
 *
 * Scope is deliberately narrow: it only touches the file the Edit/Write tool
 * just changed, only when that file is one of the config files a deployment
 * key lives in, and only the two exact placeholder tokens below.
 *
 * It never prints a key, and never fails the tool call (always exits 0).
 */
"use strict";

const fs = require("fs");
const path = require("path");

const PLACEHOLDERS = [
  { token: "YOUR_IOS_DEPLOYMENT_KEY", env: "CLAUDE_PLUGIN_OPTION_IOS_DEPLOYMENT_KEY", label: "iOS" },
  { token: "YOUR_ANDROID_DEPLOYMENT_KEY", env: "CLAUDE_PLUGIN_OPTION_ANDROID_DEPLOYMENT_KEY", label: "Android" },
];

// Files a deployment key is written to: bare RN (Info.plist, strings.xml) and
// the Expo config plugin (app.json / app.config.*).
const TARGET_FILE = /^(Info\.plist|strings\.xml|app\.json|app\.config\.(js|ts|mjs|cjs))$/;

// Deployment keys are opaque URL-safe tokens. Anything else is refused so a
// mistyped value can't break (or inject into) the XML / JSON it lands in.
const KEY_SHAPE = /^[A-Za-z0-9_-]{8,128}$/;

function readStdin() {
  try {
    return fs.readFileSync(0, "utf8");
  } catch (e) {
    return "";
  }
}

function tell(message) {
  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: { hookEventName: "PostToolUse", additionalContext: message },
    })
  );
}

function main() {
  let input;
  try {
    input = JSON.parse(readStdin() || "{}");
  } catch (e) {
    return;
  }

  const filePath = input && input.tool_input && input.tool_input.file_path;
  if (typeof filePath !== "string" || !TARGET_FILE.test(path.basename(filePath))) return;

  let src;
  try {
    src = fs.readFileSync(filePath, "utf8");
  } catch (e) {
    return;
  }

  let out = src;
  const filled = [];
  const missing = [];
  const invalid = [];

  for (const p of PLACEHOLDERS) {
    if (!out.includes(p.token)) continue;
    const value = (process.env[p.env] || "").trim();
    if (!value) {
      missing.push(p.label);
    } else if (!KEY_SHAPE.test(value)) {
      invalid.push(p.label);
    } else {
      out = out.split(p.token).join(value);
      filled.push(p.label);
    }
  }

  if (out !== src) {
    try {
      fs.writeFileSync(filePath, out);
    } catch (e) {
      return;
    }
  }

  const name = path.basename(filePath);
  const notes = [];
  if (filled.length) {
    notes.push(
      `Revopush plugin: filled the ${filled.join(" and ")} deployment key in ${name} from the user's saved plugin options. ` +
        "The file changed on disk; re-read it before editing it again, and do not repeat the key in chat."
    );
  }
  if (missing.length) {
    notes.push(
      `Revopush plugin: the ${missing.join(" and ")} deployment key placeholder in ${name} was left as-is because that plugin option is not set. ` +
        "Ask the user to set it in the revopush plugin's options (/plugin), or to replace the placeholder themselves."
    );
  }
  if (invalid.length) {
    notes.push(
      `Revopush plugin: the saved ${invalid.join(" and ")} deployment key does not look like a Revopush deployment key, so the placeholder in ${name} was left as-is. ` +
        "Ask the user to re-enter it in the revopush plugin's options (/plugin)."
    );
  }
  if (notes.length) tell(notes.join(" "));
}

try {
  main();
} catch (e) {
  // Never break the user's edit because of this hook.
}
process.exit(0);
