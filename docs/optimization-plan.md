# Optimization Plan

## Current Priorities

1. Keep v1 mobile-only and remove Web-facing expectations.
2. Keep gateway access limited to trusted LAN/Tailscale without adding auth.
3. Split `gateway/src/agents.js` into focused modules.
4. Align app UI with implemented gateway capabilities.
5. Add focused tests around streaming, agent adapters, and endpoint contracts.

## Code Health Targets

- One adapter file per agent: Codex, Claude Code, OpenCode.
- Shared helpers live under `gateway/src/agents/`.
- UI pages should delegate command routing and sheets to smaller widgets or controllers when they are next modified.
- Documentation should be readable UTF-8 and describe the actual v1 boundary.
