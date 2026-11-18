# Revopush Skills

Official AI agent skills from the Revopush team for building, deploying, and managing Revopush OTA updates.

## Overview

These skills help AI coding agents understand and assist with Revopush workflows such as:

- React Native integration
- OTA release creation
- Deployment management
- Release troubleshooting
- Production workflows

The skills are optimized for modern AI agents and work best with Claude Opus models, but they can also be used with other compatible agents.

## Installation

We primarily use [Claude Code](https://claude.com/claude-code) at Revopush, skills are fine-tuned for Opus models. But you can use these skills with any AI agent.

## Claude Code

Add the marketplace:

```
/plugin marketplace add revopush/skills
```

Install the plugin:

```
/plugin install revopush --marketplace revopush/skills
```

On install, Claude Code offers two optional settings: your **iOS deployment key**
and **Android deployment key** (from [app.revopush.org](https://app.revopush.org)).
They are stored in your system's secure storage. When the skill wires Revopush
into your app it writes placeholders, and the plugin fills in your saved keys, so
you never have to paste them into the chat. Leave them empty to fill the keys in
yourself later; change them any time from `/plugin`.

## Cursor

There are two ways to use these skills in Cursor.

**Option A — Plugin marketplace (recommended)**

This repo ships a Cursor plugin marketplace (`.cursor-plugin/marketplace.json`).
On a Cursor version that supports plugin marketplaces, add this repository as a
marketplace and install the `revopush` plugin from Cursor's plugin settings:

1. Open Cursor's plugin/marketplace settings.
2. Add the marketplace from GitHub: `revopush/skills`.
3. Install the **`revopush`** plugin.

Installing as a plugin keeps the skills updated through the marketplace, the same
way the Claude Code and Codex plugins do.

> Prefer a CLI? The portable [skills CLI](https://skills.sh/docs/cli) also works
> for Cursor and 70+ other agents:
>
> ```
> npx skills@latest add revopush/skills
> ```

**Option B — Remote Rule (GitHub)**

1. Open Cursor Settings (Cmd+Shift+J / Ctrl+Shift+J)
2. Navigate to `Rules & Command` → `Project Rules` → Add Rule → Remote Rule (GitHub)
3. Enter: `https://github.com/revopush/skills.git`

**How it works:** Skills are automatically discovered and used by the agent based on context. When you ask questions about Revopush, the agent will automatically use the relevant skills (e.g., `release`, `deployment`) based on the skill descriptions.

**Note:** Skills won't appear in the `/` slash command menu. The `/` menu in Cursor is for custom commands (stored in `.cursor/commands/`), not for skills. Skills work via auto-discovery - the agent uses them automatically when your questions match their descriptions.

**Verify installation:** After adding the Remote Rule, try asking the agent Revopush-related questions like:
- "How do I integrate revopush into React Native app?"
- "How do I create an OTA release?"

If the skills are working, the agent will use the relevant skill content to answer your questions.

## Any agent

```
bunx skills add revopush/skills
```

This will extract the skills individually so you'll need to manually upgrade them.

## License

MIT
