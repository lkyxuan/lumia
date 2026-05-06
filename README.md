# Lumia

A lightweight screen recorder for macOS with picture-in-picture webcam overlay.

## What it does

- Records your entire screen
- Overlays your webcam feed as a draggable PiP window (great for tutorials, walkthroughs, demos)
- Lets you reposition the webcam overlay anytime — before or during recording
- Saves recordings as `.mp4` to your Desktop
- Stays out of your way: a small floating control bar sits on top of all windows

## Features

- **Floating control bar** — always on top, shows timer + start/pause/stop
- **Global shortcuts** — control recording without clicking (`⌘⇧R` start/stop, `⌘⇧P` pause)
- **Draggable webcam overlay** — drag the PiP window anywhere on screen; position is reflected live in the recording
- **Native macOS** — built with SwiftUI + ScreenCaptureKit, no Electron overhead

## Requirements

- macOS 13 (Ventura) or later
- Camera and Screen Recording permissions (prompted on first launch)

## Tech Stack

| Layer | Technology |
|---|---|
| Screen capture | ScreenCaptureKit |
| Webcam capture | AVCaptureSession |
| Video compositing | Custom per-frame compositor |
| Output | AVAssetWriter → `.mp4` |
| UI | SwiftUI |

## Architecture

```
┌─────────────────────────────────────────────────┐
│                  Floating Control Bar            │
│   ● 00:12    [⏸ Pause]  [⏹ Stop]               │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│              Recording Engine                   │
│                                                 │
│  ScreenCaptureKit ──┐                           │
│                     ├──► Compositor ──► AVAssetWriter ──► .mp4
│  AVCaptureSession ──┘         ▲                 │
│                               │                 │
│                         PiP position            │
│                       (updated live)            │
└─────────────────────────────────────────────────┘
```

## Usage

1. Launch Lumia — a small control bar appears at the top of your screen
2. Drag the webcam preview window to where you want the PiP overlay
3. Press `⌘⇧R` or click **Record** to start
4. Do your thing — minimize, switch apps, work normally
5. Press `⌘⇧R` again or click **Stop** to finish
6. Find your recording on the Desktop

## Development

```bash
# Open in Xcode
open Lumia.xcodeproj
```

Requires Xcode 15+.

## License

MIT
