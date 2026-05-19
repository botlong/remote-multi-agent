# remote_multi_agent

A Flutter mobile client for local coding agents. It connects to the gateway
running on your laptop, streams normalized agent events, and renders Codex,
Claude Code, and OpenCode sessions in one project workspace.

## Why

- OpenClaw + 一来一回式 IM bots can't show you the agent's *progress* — only
  the final answer.
- Agent CLIs emit progress, tool use, and final answers; the gateway normalizes
  that stream into one app protocol.
- This app is a thin client: it carries no model keys; your local gateway owns
  provider auth and project filesystem access.

## Architecture

```text
[Phone]      remote_multi_agent (Flutter)
                 HTTPS / SSE
                 |
[Tailscale]  100.x.x.x:4096
                 |
[Laptop]     gateway/ Node server
                 |
             Codex CLI / Claude Code CLI / OpenCode CLI
```

The gateway in `gateway/` owns local project directories, sessions, CLI
processes, and event normalization. The Flutter app does not execute shell
commands or read project files directly.

## Run / build matrix

| Target | Where to build | How to install |
|--------|----------------|----------------|
| iOS    | GitHub Actions (macOS runner) | Sideloadly + free Apple ID |
| Web    | `flutter build web` | Any static host |

iOS requires a macOS machine to build, but you don't need to own one — the
`ios.yml` workflow uses GitHub's free macOS runner. See `.github/workflows/`.

## Windows dev loop (no Mac, no Xcode)

```cmd
:: Install once: Flutter SDK
flutter doctor

:: Day-to-day: web development on Windows
flutter pub get
flutter run -d chrome

:: When you want to try the iOS build
git push                              # triggers .github/workflows/ios.yml
gh run watch                          # tail the build log
gh run download --name ios-ipa        # pull the unsigned .ipa
:: → Sideloadly → install to iPhone
```

## Project layout

```
lib/
├── main.dart                              # entry
├── api/
│   ├── opencode_client.dart               # GET /session, POST /session/:id/message, …
│   └── sse_stream.dart                    # /event subscriber with auto-reconnect
├── models/
│   ├── session.dart
│   ├── message.dart
│   └── part.dart                          # text / reasoning / tool / step-* / unknown
├── state/
│   ├── settings_store.dart                # SharedPreferences-backed config
│   ├── session_store.dart                 # session list controller
│   ├── chat_store.dart                    # SSE → ChatState reducer
│   └── providers.dart                     # Riverpod glue
├── ui/
│   ├── app.dart
│   ├── pages/
│   │   ├── settings_page.dart
│   │   ├── session_list_page.dart
│   │   └── chat_page.dart
│   └── widgets/
│       ├── connection_chip.dart
│       ├── message_bubble.dart
│       └── parts/
│           ├── text_part_view.dart        # Markdown rendering
│           ├── reasoning_part_view.dart   # collapsible "thinking" block
│           ├── tool_part_view.dart        # tool invocation card
│           └── step_part_view.dart        # LLM step boundary divider
└── theme.dart
```

## Settings the user provides

- Server URL: `http://<tailscale-ip-or-domain>:4096`
- Bearer token: matches `OPENCODE_SERVER_PASSWORD` on the server
- Default provider + model: any pair returned by `GET /provider`

That's the whole config. The app never holds API keys for upstream providers —
those live on your laptop with the OpenCode server.

## Open work / TODOs

- [ ] Persist last opened session so next launch jumps straight in
- [ ] Add `image` part rendering once we observe the wire shape
- [ ] Hook into QQBot when a session goes idle (push a "task done" QQ message)
- [ ] iOS push notifications (requires fastlane + APNs setup)
- [ ] Theme picker (dark/light/system) — currently follows system
- [ ] In-app log viewer for debugging SSE drops
