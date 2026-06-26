#!/usr/bin/env node
/*
 * wrap-entry.js — wrap a React Native / Expo root component with the Revopush
 * codePush() higher-order component, idempotently.
 *
 * Usage:
 *   node wrap-entry.js <entry-file> [--dry-run]
 *
 * Behavior:
 *   - Adds `import codePush from "@revopush/react-native-code-push";` if missing.
 *   - Wraps the default export so it becomes `codePush(<Component>)`.
 *   - Idempotent: if already wrapped, it reports and makes no change.
 *   - Creates a one-time `<file>.revopush.bak` backup before writing.
 *   - With --dry-run, prints what it would do and writes nothing.
 *
 * It handles the two common export shapes:
 *   1)  export default SomeComponent;
 *   2)  export default function Name() { ... }   (and  export default class ...)
 *
 * For anything more exotic, it bails out with guidance rather than guessing — a
 * wrong edit to the entry file is worse than asking a human to do it.
 */

const fs = require("fs");
const path = require("path");

const args = process.argv.slice(2);
const DRY = args.includes("--dry-run");
const file = args.find((a) => !a.startsWith("--"));

function fail(msg) {
  console.error(`ERROR: ${msg}`);
  process.exit(1);
}

if (!file) fail("missing entry file. Usage: node wrap-entry.js <entry-file> [--dry-run]");
const abs = path.resolve(file);
if (!fs.existsSync(abs)) fail(`file not found: ${abs}`);

const IMPORT_LINE = 'import codePush from "@revopush/react-native-code-push";';
const src = fs.readFileSync(abs, "utf8");

const alreadyImported =
  /from\s+["']@revopush\/react-native-code-push["']/.test(src);
const alreadyWrapped = /export\s+default\s+codePush\s*\(/.test(src) ||
  /codePush\s*\([^)]*\)\s*\(/.test(src);

if (alreadyWrapped) {
  console.log(`OK (already wrapped): ${file} — no change needed.`);
  process.exit(0);
}

let out = src;

// 1) Add the import after the last existing top-level import, else at the top.
if (!alreadyImported) {
  const importRe = /^import .*?;[ \t]*$/gm;
  let lastEnd = -1;
  let m;
  while ((m = importRe.exec(out)) !== null) lastEnd = m.index + m[0].length;
  if (lastEnd >= 0) {
    out = out.slice(0, lastEnd) + "\n" + IMPORT_LINE + out.slice(lastEnd);
  } else {
    out = IMPORT_LINE + "\n" + out;
  }
}

// 2) Wrap the default export.
let wrapped = false;

// Shape: `export default <Identifier>` (with or without a trailing semicolon).
// Anchored to end-of-line so it won't match `export default App.foo`,
// `export default function ...`, or `export default React.memo(App)`.
const idExport = /export\s+default\s+([A-Za-z_$][\w$]*)[ \t]*;?[ \t]*$/m;
// Shape: `export default function Name(` or `export default class Name`
const inlineExport = /export\s+default\s+(?:async\s+)?(function|class)\b/;

if (idExport.test(out)) {
  out = out.replace(idExport, (_full, name) => `export default codePush(${name});`);
  wrapped = true;
} else if (inlineExport.test(out)) {
  // Pull a name from the declaration; if anonymous, give it one so we can wrap.
  const declMatch = out.match(
    /export\s+default\s+(?:async\s+)?(function|class)\s*([A-Za-z_$][\w$]*)?/
  );
  const kind = declMatch[1];
  let name = declMatch[2];
  if (!name) {
    name = "RevopushRoot";
    out = out.replace(
      /export\s+default\s+(async\s+)?(function|class)\b/,
      (_f, asyncKw = "", k) => `${asyncKw || ""}${k} ${name}`
    );
  } else {
    // Strip the `export default` from the declaration so we can re-export wrapped.
    out = out.replace(/export\s+default\s+(?=(?:async\s+)?(?:function|class)\b)/, "");
  }
  // Append the wrapped export at the end of the file.
  const sep = out.endsWith("\n") ? "" : "\n";
  out = `${out}${sep}\nexport default codePush(${name});\n`;
  wrapped = true;
}

if (!wrapped) {
  console.error(
    "Could not find a recognizable `export default` to wrap in " + file + ".\n" +
    "Wrap it by hand: import codePush and change your root export to\n" +
    "  export default codePush(YourRootComponent);\n" +
    "See references/js-api.md for options."
  );
  process.exit(3);
}

if (DRY) {
  console.log(`--- DRY RUN: would update ${file} ---`);
  console.log(out);
  console.log(`--- end dry run (no file written) ---`);
  process.exit(0);
}

const bak = `${abs}.revopush.bak`;
if (!fs.existsSync(bak)) fs.copyFileSync(abs, bak);
fs.writeFileSync(abs, out);
console.log(`PATCHED: ${file} (backup at ${path.basename(bak)})`);
