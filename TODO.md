# Remote Multi-Agent Roadmap

## V1 Boundary

- Mobile/iOS app only; Web is unsupported.
- Gateway has no authentication; use trusted LAN or Tailscale.
- App does not execute code and does not read project files directly.
- Gateway owns project directories, agent CLIs, filesystem, git, and credentials.

## Near-Term Cleanup

- Split gateway agent adapters into one file per agent.
- Keep command discovery dynamic through gateway metadata.
- Remove UI controls that imply unsupported gateway authentication.
- Keep documentation free of mojibake and aligned with the current product.

## Functional Follow-Up

- Decide whether approve/reject/handoff should be implemented or hidden.
- Add contract tests for any API endpoint surfaced in the app.
- Add CI checks for docs encoding and mobile test commands.

## Later Product Work

- Expand agent-specific command palettes only when the gateway exposes matching
  capabilities.
- Improve streaming, attachment, and diff rendering tests.
- Document any future authentication model before adding UI for it.
