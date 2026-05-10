# Screenshot Search Automator

macOS top bar app: press hotkey combination (default `Cmd+Shift+9`), drag to select any screen area, type a question or tap a numbered quick-prompt button, and get an AI answer in a floating overlay.

## What is implemented

- SwiftUI + AppKit application shell
- Global hotkey via Carbon (default `Command` + `Shift` + `9`, configurable from menu bar)
- Full-screen area-selection overlay on every display, with persistent crosshair cursor
- Screen capture via ScreenCaptureKit for the chosen rectangle
- Floating prompt panel under the selected area with numbered quick-prompt buttons (1–4)
- Quick Prompts settings window accessible from the menu bar icon
- Floating response panel that replaces the prompt panel
- Gemini API client with vision support and Google Search Grounding (live web search)
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
AI_API_KEY="AIza..." \
./Scripts/build-app.sh
```

Build and immediately launch:

```bash
AI_API_KEY="AIza..." \
./Scripts/build-app.sh --run
```

Use `--release` for an optimised binary:

```bash
AI_API_KEY="AIza..." \
./Scripts/build-app.sh --release --run
```

## Runtime configuration

The app reads configuration in this priority order:

1. Environment variables set at launch time
2. `RuntimeConfig.json` embedded in the app bundle by `build-app.sh`

### Environment variables

| Variable | Required | Description |
|---|---|---|
| `AI_API_KEY` | Yes | Your Gemini API key (`AIza...`) |
| `AI_MODEL` | No | Model name override (default: `gemini-2.5-flash`) |

> **Note:** Google Search Grounding requires a Gemini API key with billing enabled. The free tier supports it only up to a low quota.

### Overriding the model

```bash
AI_API_KEY="AIza..." AI_MODEL="gemini-2.5-pro" ./Scripts/build-app.sh --run
```

## API integration

### Gemini with Google Search Grounding

Uses the [Gemini generateContent API](https://ai.google.dev/gemini-api/docs/text-generation) with vision support and the `google_search` tool enabled. Before answering, the model searches Google in real-time, giving it access to up-to-date information. Grounding source URLs are appended to the answer as a plain-text "Sources:" block.

The image is sent as inline base64 PNG data. The API key is passed in the `x-goog-api-key` request header.

### Privacy

Both integrations include a system prompt that instructs the model to answer only what was asked and not describe or summarise other contents of the screenshot.

## Permissions

The first capture attempt requires Screen Recording permission. After granting it in System Settings, relaunch the built app bundle so the permission attaches to a stable app identity.

If permission was previously denied, the app shows a recovery panel with a direct link to the Screen Recording settings pane. macOS will continue blocking capture until the permission is enabled and the app is restarted.
