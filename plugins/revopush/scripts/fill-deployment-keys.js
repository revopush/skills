#!/usr/bin/env node
// PostToolUse hook (Claude Code). The deployment keys are sensitive plugin
// options, which only hook processes can read (CLAUDE_PLUGIN_OPTION_<KEY>), so
// the skill writes a placeholder and this swaps in the saved key. It only
// touches the config file that was just edited, never prints a key, and never
// fails the edit.
"use strict";

const fs = require("fs");
const path = require("path");

const KEYS = [
  ["iOS", "YOUR_IOS_DEPLOYMENT_KEY", "CLAUDE_PLUGIN_OPTION_IOS_DEPLOYMENT_KEY"],
  ["Android", "YOUR_ANDROID_DEPLOYMENT_KEY", "CLAUDE_PLUGIN_OPTION_ANDROID_DEPLOYMENT_KEY"],
];
const CONFIG_FILE = /^(Info\.plist|strings\.xml|app\.json|app\.config\.(js|ts|mjs|cjs))$/;
// Refuse anything that isn't a plain token, so a bad value can't break the XML/JSON.
const VALID_KEY = /^[A-Za-z0-9_-]{8,128}$/;

try {
  const file = JSON.parse(fs.readFileSync(0, "utf8")).tool_input.file_path;
  const name = path.basename(file);
  if (!CONFIG_FILE.test(name)) process.exit(0);

  const before = fs.readFileSync(file, "utf8");
  let after = before;
  const notes = [];

  for (const [platform, placeholder, envVar] of KEYS) {
    if (!after.includes(placeholder)) continue;
    const key = (process.env[envVar] || "").trim();
    if (VALID_KEY.test(key)) {
      after = after.replaceAll(placeholder, key);
      notes.push(`filled the ${platform} deployment key in ${name} from the user's saved plugin options (file changed on disk: re-read before editing, and don't repeat the key in chat)`);
    } else {
      const why = key ? "the saved value doesn't look like a deployment key" : "that plugin option isn't set";
      notes.push(`left ${placeholder} in ${name} because ${why}; ask the user to set it via /plugin or replace it themselves`);
    }
  }

  if (after !== before) fs.writeFileSync(file, after);
  if (notes.length) {
    console.log(JSON.stringify({
      hookSpecificOutput: { hookEventName: "PostToolUse", additionalContext: `Revopush plugin: ${notes.join("; ")}.` },
    }));
  }
} catch {
  // Not our file, unreadable input, or a write error: stay out of the way.
}
