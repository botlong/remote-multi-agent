# Agent Command Reference

Reference date: 2026-05-19

This file records the official command surfaces that matter for app-level chat UX.
Some commands are feature-gated or version-dependent.

## Claude Code

Official built-in slash commands documented by Anthropic:

- `/add-dir`
- `/agents`
- `/bug`
- `/clear`
- `/compact [instructions]`
- `/config`
- `/cost`
- `/doctor`
- `/help`
- `/init`
- `/login`
- `/logout`
- `/mcp`
- `/memory`
- `/model`
- `/permissions`
- `/pr_comments`
- `/review`
- `/status`
- `/terminal-setup`
- `/vim`

Official custom command surfaces:

- Project commands: `.claude/commands/*.md`
- User commands: `~/.claude/commands/*.md`
- Command syntax: `/<command-name> [arguments]`
- Arguments: `$ARGUMENTS`, `$1`, `$2`, etc.
- File references: `@path/to/file`
- Bash pre-exec blocks: `!` prefix in command content
- MCP prompts: `/mcp__<server-name>__<prompt-name>`

Notes:

- Current Claude Code docs indicate custom commands have been merged into skills, but existing `.claude/commands/` files still work.
- Skill frontmatter can control `description`, `allowed-tools`, `model`, `disable-model-invocation`, `user-invocable`, `context`, and `agent`.

## Codex

Official built-in slash commands documented by OpenAI:

- `/permissions`
- `/ide`
- `/keymap`
- `/vim`
- `/sandbox-add-read-dir`
- `/agent`
- `/apps`
- `/plugins`
- `/hooks`
- `/clear`
- `/compact`
- `/copy`
- `/diff`
- `/exit` and `/quit`
- `/experimental`
- `/approve`
- `/memories`
- `/skills`
- `/feedback`
- `/init`
- `/logout`
- `/mcp`
- `/mention`
- `/model`
- `/fast`
- `/plan`
- `/goal`
- `/personality`
- `/ps`
- `/stop`
- `/fork`
- `/side`
- `/raw`
- `/status`
- `/debug-config`

Notes:

- `/fast` is catalog-driven and only appears when the current model exposes a Fast tier.
- `/goal` is experimental and requires `features.goals` to be enabled.
- `/model` can also change reasoning effort when supported.

## OpenCode

Official built-in slash commands documented by OpenCode:

- `/help`
- `/editor`
- `/export`
- `/new`
- `/sessions`
- `/share`
- `/unshare`
- `/compact`
- `/details`
- `/models`
- `/themes`
- `/init`
- `/undo`
- `/redo`
- `/exit`

Aliases documented by OpenCode:

- `/new` alias: `/clear`
- `/sessions` aliases: `/resume`, `/continue`
- `/compact` alias: `/summarize`
- `/exit` aliases: `/quit`, `/q`

Custom command surface:

- Markdown command files in `.opencode/commands/`
- Commands can also be configured in `opencode.json`
- Command frontmatter supports `description`, `agent`, `model`, and `subtask`

Notes:

- OpenCode custom commands are part of the TUI command system.
- Custom commands can override built-in commands.

## Sources

- Anthropic slash commands: https://docs.anthropic.com/en/docs/claude-code/slash-commands
- Anthropic commands reference: https://code.claude.com/docs/en/commands
- OpenAI Codex slash commands: https://developers.openai.com/codex/cli/slash-commands
- OpenCode commands: https://opencode.ai/docs/commands
- OpenCode CLI: https://opencode.ai/docs/cli

