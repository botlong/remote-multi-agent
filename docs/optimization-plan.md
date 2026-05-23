# Optimization Plan

## Product Boundaries

1. Keep v1 mobile/iOS-only. Do not reintroduce Web-facing setup, routes, or
   product promises.
2. Keep gateway access limited to trusted LAN or Tailscale. V1 has no gateway
   authentication, so documentation and UI must not imply otherwise.
3. Keep the app as a thin client. Project directories, agent CLIs, filesystem,
   git, and credentials remain gateway-owned.

## Near-Term Technical Priorities

1. Keep the agent adapter split stable:
   - `codex.js`, `claude_code.js`, and `opencode.js` own agent-specific logic.
   - `registry.js` composes adapters.
   - `command_helpers.js`, `json_cli.js`, `model_cache.js`, and
     `opencode_helpers.js` hold shared support code.
2. Add endpoint contract tests for every route surfaced in the app, especially
   project session creation, message send, SSE events, abort, export, diff, and
   credential profile routes.
3. Add regression tests for streaming event normalization and adapter model
   discovery so CLI output changes are caught close to the gateway.

## Profile and Model Follow-Up

1. Make gateway profiles the single source of upstream API credentials.
2. Add per-profile default model settings for Codex, Claude Code, and OpenCode.
3. Keep model discovery dynamic through gateway metadata, with cached model
   lists refreshed on profile changes.
4. Ensure the app never stores upstream keys and only displays masked profile
   metadata returned by the gateway.

## Command Routing Follow-Up

1. Keep command discovery dynamic through `/agents/:agentId/commands`.
2. Route commands by capability instead of hard-coding app behavior where the
   gateway can report support.
3. Decide whether approve, reject, handoff, and permission actions are
   implemented in v1 or hidden until the gateway exposes a complete contract.
4. Prefer structured command result events over raw CLI text when commands need
   native mobile rendering.

## Documentation and CI Targets

- Keep documentation readable UTF-8 and aligned with the actual v1 boundary.
- Add a docs encoding check to CI.
- Add CI coverage for gateway tests and the mobile Flutter test command.
- Keep README endpoint tables synchronized with `gateway/README.md` and
  `docs/development-spec.md`.
