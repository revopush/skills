# Revopush Skills Repository

Official Revopush AI agent skills. The primary distribution format is a plugin
marketplace for Claude Code, Codex, and Cursor, but each skill is a portable
`SKILL.md` that any agent (via `npx skills add revopush/skills`) can consume.

This file guides agents and contributors **editing this repository**. For how the
skill itself works, read the skill's `SKILL.md`.

## Repository structure

```
.claude-plugin/marketplace.json          # Claude Code marketplace catalog
.agents/plugins/marketplace.json          # Codex marketplace catalog
.cursor-plugin/marketplace.json           # Cursor marketplace catalog
plugins/
  revopush/
    .claude-plugin/plugin.json            # Claude Code plugin manifest
    .codex-plugin/plugin.json             # Codex plugin manifest (camelCase `interface`)
    .cursor-plugin/plugin.json            # Cursor plugin manifest (`displayName`)
    agents/openai.yaml                    # Codex UI metadata (snake_case)
    skills/
      revopush-setup/
        SKILL.md                          # Router/workflow (keep lean, < ~500 lines)
        references/                       # Loaded on demand by the workflow
        scripts/                          # Bundled executables (detect / wrap / verify)
        assets/                           # Templates used in output
        evals/evals.json                  # Test prompts + assertions
README.md                                 # User-facing install instructions
skills.sh.json                            # skills.sh catalog grouping
LICENSE
```

All three marketplaces expose one plugin, `revopush`, whose `source` resolves to
`./plugins/revopush` and whose `skills` resolves to `./skills/`. The plugin name
in every marketplace entry **must match** the plugin manifest `name`.

## Product invariants — do not regress these

These are deliberate decisions (from the Revopush team) that are easy for a
well-meaning agent to "fix" and break. Preserve them unless the user explicitly
changes the policy:

- **Hosted / SaaS only.** Always target `https://api.revopush.org` (API) and
  `https://app.revopush.org` (dashboard). Revopush has **no** self-hosted option —
  never suggest a custom server URL, and there is no supported CLI flag for one.
- **SDK version policy: always the 2.x line** (for differential updates). RN
  `0.76–0.82 → @revopush/react-native-code-push@2.5.1`; RN `0.83+ → @2.6.x`; RN
  `< 0.76 → Microsoft CodePush`. Do **not** recommend the 1.x line for new setups.
  Source of truth: `skills/revopush-setup/references/versions.md`.
- **Keep the native package name `com.microsoft.codepush.react`.** Revopush keeps
  it for drop-in compatibility; renaming it breaks the build. (Migration agents
  especially must not "tidy" this.)
- **Server-URL key casing is asymmetric on purpose:** iOS `CodePushServerURL`
  (uppercase `URL`) vs Android/Expo `CodePushServerUrl` (lowercase `Url`).
- **`docs.revopush.org` is the reference, but it can lag the product.** When the
  docs and this repo's guidance conflict (e.g. the 1.x vs 2.x line), the repo's
  current policy is intentional — don't "correct" it back to stale docs.

## Plugin & skill schemas

**Plugin manifest** (`plugins/revopush/.claude-plugin/plugin.json` and the
`.codex-plugin` / `.cursor-plugin` variants): required `name` (kebab-case);
optional `version`, `description`, `author`, `license`, `keywords`, and the
pointer `skills: "./skills/"`. The Codex manifest adds a camelCase `interface`
block; the Cursor manifest adds `displayName`.

**Skill** (`skills/<name>/SKILL.md`): YAML frontmatter with required `name`
(lowercase-hyphen, ≤64 chars, must equal the folder name) and `description`
(≤1024 chars, states *what* and *when*). Optional `license`, `metadata` (we keep
`version`, `author`, `last-updated`). **No angle brackets anywhere in the
frontmatter** (portability/injection). Keep `SKILL.md` lean; push detail into
`references/` and load it only on the relevant branch; put repeated logic in
`scripts/`.

## Marketplace wrappers

- Claude Code and Cursor entries use a **string** `source` (`"./plugins/revopush"`)
  with `name`/`owner`/`metadata`/`plugins[]`.
- Codex entries use an **object** `source` (`{ "source": "local", "path": "./plugins/revopush" }`)
  plus `policy.installation`, `policy.authentication`, and `category`.

When you change the plugin in a way that warrants a release, **bump the version in
all of these together** so they stay in sync:
`plugins/revopush/.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`,
`.cursor-plugin/plugin.json`, the marketplaces' `metadata.version`, and the
skill's `metadata.version` in `SKILL.md`.

## Adding or changing a skill

1. Create `plugins/revopush/skills/<skill-name>/SKILL.md` (kebab-case; folder name
   must equal the frontmatter `name`).
2. Add `references/` for version-/variant-specific detail; cross-link them from
   `SKILL.md` and let the agent read only what its branch needs.
3. Add `scripts/` only for reusable, deterministic logic (detection, idempotent
   edits, verification) — not one-off command blocks.
4. Add test prompts (and assertions) to `evals/evals.json`.
5. List new skills in `skills.sh.json` and, if a new plugin, add matching entries
   to all three marketplace catalogs.
6. Update `README.md` only when the user-facing install/usage story changes.
7. Prefer keeping related capability inside an existing skill; create a sibling
   skill only when there's a clear distribution/triggering reason (e.g. a future
   `revopush-release` for publishing-only workflows).

## Validating changes

Verify JSON parses for every manifest you touched:

```bash
for f in \
  .claude-plugin/marketplace.json .agents/plugins/marketplace.json .cursor-plugin/marketplace.json \
  plugins/revopush/.claude-plugin/plugin.json plugins/revopush/.codex-plugin/plugin.json \
  plugins/revopush/.cursor-plugin/plugin.json; do
  python3 -m json.tool "$f" >/dev/null && echo "OK $f"
done
```

If available, also run `claude plugin validate .` and `claude plugin validate ./plugins/revopush`.

The bundled scripts are self-testable (read-only or `--dry-run`-first) — exercise
them against a sample project before relying on a change:

```bash
plugins/revopush/skills/revopush-setup/scripts/detect-project.sh <sample-app>
plugins/revopush/skills/revopush-setup/scripts/verify-integration.sh <sample-app>
node plugins/revopush/skills/revopush-setup/scripts/wrap-entry.js <entry-file> --dry-run
```

When iterating on the skill, the `skill-creator` eval loop drives the
`*-workspace/iteration-N/` directories (not committed as part of the skill).

## Conventions

- kebab-case for plugin, skill, and file names.
- Author email `support@revopush.org`; MIT license throughout.
- Keep `references/` next to the skill that uses them; keep `SKILL.md` lean.
- Avoid broad rewrites when editing a skill — preserve its scope and trigger
  intent, and re-check the **Product invariants** above before changing native
  edits, versions, or server URLs.
