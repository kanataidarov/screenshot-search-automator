# Screenshot Search Automator

macOS menu bar app: press `Cmd+Shift+9`, drag to select any screen area, type a question or tap a numbered quick-prompt button, and get an AI answer in a floating overlay.

## What is implemented

- SwiftUI + AppKit application shell
- Global hotkey via Carbon (`Command` + `Shift` + `9`)
- Full-screen area-selection overlay on every display, with persistent crosshair cursor
- Screen capture via ScreenCaptureKit for the chosen rectangle
- Floating prompt panel under the selected area with numbered quick-prompt buttons (1–4)
- Quick Prompts settings window accessible from the menu bar icon
- Floating response panel that replaces the prompt panel
- Native Claude (Anthropic) and OpenAI API clients with vision support
- Composite menu bar icon (viewfinder + magnifier SF Symbols)
- No Xcode required; builds with SwiftPM and a small shell script
- Manual `.app` bundle build and ad-hoc signing

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
| `AI_PROVIDER` | Yes | `claude`, `openai`, or `gemini` |
| `AI_API_KEY` | Yes | Your API key |
| `AI_MODEL` | No | Model name override (see defaults below) |

### Default models

| Provider | Default model |
|---|---|
| `claude` | `claude-sonnet-4-5` |
| `openai` | `gpt-4o-mini` |
| `gemini` | `gemini-2.5-flash` |

### Switching provider

```bash
# Claude
AI_PROVIDER="claude" AI_API_KEY="sk-ant-..." ./Scripts/build-app.sh --run

# OpenAI
AI_PROVIDER="openai" AI_API_KEY="sk-..." ./Scripts/build-app.sh --run

# Gemini
AI_PROVIDER="gemini" AI_API_KEY="AIza..." ./Scripts/build-app.sh --run

# Override model
AI_PROVIDER="claude" AI_API_KEY="sk-ant-..." AI_MODEL="claude-sonnet-4-6" ./Scripts/build-app.sh --run

# Override Gemini model
AI_PROVIDER="gemini" AI_API_KEY="AIza..." AI_MODEL="gemini-2.5-pro" ./Scripts/build-app.sh --run
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

### Gemini

Uses the [Gemini generateContent API](https://ai.google.dev/gemini-api/docs/text-generation) with a vision message. The image is sent as inline base64 PNG data and the API key is passed in the request URL.

### Privacy

Both integrations include a system prompt that instructs the model to answer only what was asked and not describe or summarise other contents of the screenshot.

## Permissions

The first capture attempt requires Screen Recording permission. After granting it in System Settings, relaunch the built app bundle so the permission attaches to a stable app identity.

If permission was previously denied, the app shows a recovery panel with a direct link to the Screen Recording settings pane. macOS will continue blocking capture until the permission is enabled and the app is restarted.
