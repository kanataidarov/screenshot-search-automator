# Screenshot Search Automator

This is a no-Xcode starter for a macOS app that lets you:

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
- URLSession-based API client with a flexible JSON parser
- Manual `.app` bundle build and ad-hoc signing

## What still needs product work

- Custom hotkey configuration UI
- Better cancellation and escape handling polish
- Rich response rendering and copy actions
- A finalized request/response contract for your exact AI API
- Hardened TCC permission and error messaging flows

## Requirements

- macOS 14 or later
- Apple Command Line Tools with Swift installed
- Screen Recording permission granted to the built app

## Build and run

Debug build:

```bash
swift build
```

Build a runnable `.app` bundle:

```bash
./Scripts/build-app.sh
```

Build and run the app from the bundle executable:

```bash
SCREENSHOT_SEARCH_API_URL="https://your-api.example/v1/ask" \
SCREENSHOT_SEARCH_API_KEY="replace-me" \
./Scripts/build-app.sh --run
```

The build script writes `RuntimeConfig.json` into the app bundle when those environment variables are present. That avoids depending on Finder-launched environment variables.

## Runtime configuration

The app reads API configuration in this order:

1. Environment variables at launch time
2. `RuntimeConfig.json` embedded in the app bundle by `build-app.sh`

Supported variables:

- `SCREENSHOT_SEARCH_API_URL`
- `SCREENSHOT_SEARCH_API_KEY`
- `SCREENSHOT_SEARCH_API_MODEL`
- `SCREENSHOT_SEARCH_API_KEY_HEADER` (defaults to `Authorization`)
- `SCREENSHOT_SEARCH_API_KEY_PREFIX` (defaults to `Bearer`)

## API payload shape

The starter client sends JSON in this form:

```json
{
  "question": "What is happening in this screenshot?",
  "imageBase64": "...",
  "mimeType": "image/png",
  "model": "optional-model-name"
}
```

The response parser accepts several common response shapes:

- `{ "answer": "..." }`
- `{ "content": "..." }`
- OpenAI-style `choices[0].message.content`
- Plain text responses

If your API differs, update `makeRequestBody` and `extractAnswer` in `Sources/ScreenshotSearchAutomator/APIClient.swift`.

## Permissions

The first capture attempt will require Screen Recording permission. After granting it in System Settings, relaunch the built app bundle so the permission attaches to a stable app identity.

If you previously denied the permission, the app now shows a recovery panel with a direct link to the Screen Recording settings pane. macOS will continue blocking capture until that permission is enabled and the app is restarted.
