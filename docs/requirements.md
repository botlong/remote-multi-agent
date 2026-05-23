# Project Requirements

## Goal

The mobile/iOS app should support three agent backends in one workspace:

- OpenCode
- Claude Code
- Codex

## Navigation and routing

- Add a project-based home route.
- The home screen should start from project directories.
- From a project directory, users can create a new conversation.

## Session hierarchy

The session structure inside each project should be:

`directory -> agent (optional model) -> session`

## New conversation flow

- User selects a project directory.
- User selects an agent.
- User selects a model when the selected agent supports it.
- App creates a new session under that directory and agent/model scope.

## Functional intent

- A single project directory can contain multiple agent groups.
- Each agent group can contain multiple sessions.
- Existing OpenCode behavior should be preserved while extending the app to support Claude Code and Codex.

## Agent-specific chat behavior

- Session chat UI must vary by agent.
- Different agents have different command and interaction conventions.
- Examples:
  - Codex supports commands such as `/fast`.
  - Claude Code has its own official command set and session behavior.
- The app should keep compatibility with each agent's official features instead of flattening them into one generic chat experience.
- Agent-specific input handling, actions, and shortcuts should be preserved where relevant.

## App and gateway split

- The mobile/iOS app and the server gateway should be implemented and deployed separately.
- The app is only responsible for sending and receiving messages and rendering conversation state.
- The app must not have code execution capability.
- All agent execution logic lives in the gateway.
- The gateway can be open source to build user trust.
- The app can remain closed source and paid.
- For the first version, the gateway can ship without authentication.
- V1 targets mobile/iOS. Flutter Web is not supported.
- V1 gateway access is trusted-network only. It does not require or validate a bearer token.
- Authentication remains outside the v1 implementation scope.
