# Screenshot Search Automator

MacOS app that lets you:

1. Trigger a global hotkey.
2. Drag to select a screen area.
3. Enter a question in a floating input panel below that area.
4. Send the screenshot and prompt to an AI API.
5. Replace the input panel with a floating answer overlay.

The project uses SwiftPM for builds and a small shell script to assemble a signed `.app` bundle without `xcodebuild`.

## What is implemented

- SwiftUI + AppKit application shell
- Global hotkey via Carbon (`Command` + `Shift` + `9`)
- Full-screen area-selection overlay on every display
- Screen capture via ScreenCaptureKit for the chosen rectangle
- Floating prompt panel under the selected area
- Floating response panel that replaces the prompt panel
- Native Claude (Anthropic) and OpenAI API clients with vision support
- Manual `.app` bundle build and ad-hoc signing

## What still needs product work

- Custom hotkey configuration UI
- Better cancellation and escape handling polish
- Rich response rendering and copy actions
- Hardened TCC permission and error messaging flows

## Requirements

- macOS 14 or later
- Apple Command Line Tools with Swift installed
- Screen Recording permission granted to the built app

## Build and run

Debug build (no API baked in):

```bash
swift build
```

Build a runnable `.app` bundle with your API key embedded:

```bash
AI_PROVIDER="claude" \
AI_API_KEY="sk-ant-..." \
./Scripts/build-app.sh
```

Build and immediately launch:

```bash
AI_PROVIDER="claude" \
AI_API_KEY="sk-ant-..." \
./Scripts/build-app.sh --run
```

Use `--release` for an optimised binary:

```bash
AI_PROVIDER="claude" \
AI_API_KEY="sk-ant-..." \
./Scripts/build-app.sh --release --run
```

## Runtime configuration

The app reads configuration in this priority order:

1. Environment variables set at launch time
2. `RuntimeConfig.json` embedded in the app bundle by `build-app.sh`

### Environment variables

| Variable | Required | Description |
|---|---|---|
| `AI_PROVIDER` | Yes | `claude` or `openai` |
| `AI_API_KEY` | Yes | Your API key |
| `AI_MODEL` | No | Model name override (see defaults below) |

### Default models

| Provider | Default model |
|---|---|
| `claude` | `claude-sonnet-4-5` |
| `openai` | `gpt-4o-mini` |

### Switching provider

```bash
# Claude
AI_PROVIDER="claude" AI_API_KEY="sk-ant-..." ./Scripts/build-app.sh --run

# OpenAI
AI_PROVIDER="openai" AI_API_KEY="sk-..." ./Scripts/build-app.sh --run

# Override model
AI_PROVIDER="claude" AI_API_KEY="sk-ant-..." AI_MODEL="claude-sonnet-4-6" ./Scripts/build-app.sh --run
```

## API integration

### Claude

Uses the [Anthropic Messages API](https://docs.anthropic.com/en/api/messages) with a vision message. The image is sent as a base64-encoded PNG alongside your question.

Required headers set automatically:

- `x-api-key: <your key>`
- `anthropic-version: 2023-06-01`

### OpenAI

Uses the [Chat Completions API](https://platform.openai.com/docs/api-reference/chat) with a vision message (`image_url` content block, `data:image/png;base64,...` format).

Required headers set automatically:

- `Authorization: Bearer <your key>`

### Privacy

Both integrations include a system prompt that instructs the model to answer only what was asked and not describe or summarise other contents of the screenshot.

## Permissions

The first capture attempt requires Screen Recording permission. After granting it in System Settings, relaunch the built app bundle so the permission attaches to a stable app identity.

If permission was previously denied, the app shows a recovery panel with a direct link to the Screen Recording settings pane. macOS will continue blocking capture until the permission is enabled and the app is restarted.
