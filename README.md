# AudioScribe

A universal iOS + macOS app that records or imports audio and produces a transcript on-device using [WhisperKit](https://github.com/argmaxinc/WhisperKit). No servers, no API keys, no audio leaves the device.

This is **Part 1** of a two-part project. Part 2 (translation of transcripts) will be added later.

---

## What this build delivers

- Record from microphone or import an audio file (WAV / MP3 / M4A / AIFF / CAF)
- On-device transcription via WhisperKit with selectable models (`tiny` → `large-v3`)
- Default model: **whisper-medium** (downloaded on first use, ~769 MB)
- Saved sessions in SwiftData (audio file + transcript + per-segment timestamps)
- Library view with search and delete
- Transcript view with synced playback highlighting (tap any segment to jump audio there)
- Playback controls: scrub, ±10 s, variable speed (0.5×–2×)
- Auto language detection (16 supported languages preset; Whisper actually supports ~99)
- Settings view: model selection, preferred language, model preload
- Universal codebase (one target, runs on iOS 17+ and macOS 14+)
- Privacy-first: app sandbox enabled, mic + network entitlements explicitly declared

---

## Project structure

```
.
├── project.yml                               # XcodeGen spec — single source of truth
├── AudioScribe.xcodeproj/                    # Generated from project.yml
├── AudioScribe/
│   ├── App/
│   │   ├── AudioScribeApp.swift              # @main + ModelContainer
│   │   └── RootView.swift                    # NavigationSplitView
│   ├── Models/                               # SwiftData models + WhisperModelOption
│   ├── Services/
│   │   ├── AudioRecorder.swift               # AVAudioRecorder, mic permission, metering
│   │   ├── AudioPlayer.swift                 # AVAudioPlayer, scrubbing, rate, observers
│   │   ├── TranscriptionService.swift        # WhisperKit wrapper + result mapping
│   │   ├── ModelManager.swift                # User prefs (selected model, language)
│   │   ├── AudioStorage.swift                # App-support folder for recordings
│   │   └── SessionStore.swift                # SwiftData persistence helper
│   ├── Utilities/
│   │   ├── AudioFileImporter.swift
│   │   ├── TimeFormatter.swift
│   │   └── Logger.swift
│   ├── Views/
│   │   ├── Recorder/                         # RecorderView, WaveformView
│   │   ├── Library/                          # LibraryView, SessionRowView
│   │   ├── Transcript/                       # TranscriptView, segment view, controls
│   │   ├── Settings/SettingsView.swift
│   │   └── Common/PlatformAdaptive.swift
│   └── Resources/
│       ├── Assets.xcassets/
│       ├── AudioScribe.entitlements
│       └── Info.generated.plist
└── AudioScribeTests/                         # 20 unit tests
```

---

## How to run

### macOS

1. Open `AudioScribe.xcodeproj` in Xcode 26+.
2. In the scheme bar, pick **My Mac** as the run destination.
3. Press **⌘R**.
4. On first launch, macOS asks for microphone access — click **OK**.
5. The first time you press Record (or open Settings → Preload), WhisperKit downloads `whisper-medium` (~769 MB) into `~/Library/Application Support/huggingface/...`. This takes a few minutes once.

### iOS Simulator

1. In the scheme bar, pick **iPhone 17 Pro** (or any iOS Simulator).
2. Press **⌘R**.
3. The simulator's microphone passes through your Mac's mic.
4. Same model download happens on first run.

### iOS device

1. In the scheme bar, pick your physical iPhone.
2. Open `AudioScribe.xcodeproj` → click the **AudioScribe** target → **Signing & Capabilities** → set your **Team** (any free Apple ID works for personal devices).
3. Press **⌘R** (the device must be unlocked + trust the developer profile in Settings → General → VPN & Device Management on first run).

---

## Re-generating the Xcode project

If you ever change `project.yml`, regenerate with:

```bash
cd "/Users/hammadahmad/Documents/video material/Audio Transcript."
xcodegen generate
```

Do not hand-edit `AudioScribe.xcodeproj` — your changes will be lost next regen. Always edit `project.yml` instead.

---

## Manual testing checklist

These cannot be automated from CLI; please run them in Xcode after the model has finished downloading:

### macOS
- [ ] App launches; sidebar shows Record / Library
- [ ] Record button → mic permission dialog → "OK"
- [ ] Waveform pulses while you speak
- [ ] Stop & Transcribe → status text walks through "Loading model…" → "Transcribing…" → "Done."
- [ ] Library shows the new session; tap it
- [ ] Transcript view shows segments with timestamps
- [ ] Press Play — audio plays, current segment highlights in real time
- [ ] Tap a different segment — audio jumps there
- [ ] Variable speed (0.5×, 1.5×, 2×) works
- [ ] Settings (⌘,) lets you pick a different model and preload it
- [ ] Import a `.mp3` or `.m4a` file → transcribes successfully
- [ ] Delete a session via swipe / toolbar — file is removed from disk

### iOS Simulator
- [ ] Same flow as macOS, plus:
- [ ] Rotation works (portrait, landscape)
- [ ] Search bar in Library filters sessions

### iOS device
- [ ] First-launch mic permission prompt appears with the description text from Info.plist
- [ ] Background mic-off behavior: lock the device — recording should stop cleanly when you return

---

## Model download paths

WhisperKit caches models at:
- macOS: `~/Library/Containers/com.hammadahmad.audioscribe/Data/Library/Application Support/huggingface/models/argmaxinc/whisperkit-coreml/`
- iOS: inside the app sandbox at the analogous path

To force a fresh download, delete that folder.

---

## Known limitations / future work

- Word-level timestamps are off by default (saves CPU). Set `wordTimestamps: true` in `TranscriptionService.swift` to enable.
- Live streaming transcription (transcribe-as-you-record) is not implemented yet. Currently we transcribe after Stop. WhisperKit supports streaming — would need an `AudioStreamTranscriber` integration.
- No iCloud sync. Recordings stay on the device.
- The bundle identifier is `com.hammadahmad.audioscribe`; change in `project.yml` and regenerate before App Store distribution.

---

## Build status (last verified)

- ✅ Debug build: macOS — **succeeded, 0 warnings, 0 errors**
- ✅ Debug build: iOS Simulator — **succeeded, 0 warnings, 0 errors**
- ✅ Release build: macOS — **succeeded, 0 warnings, 0 errors**
- ✅ Release build: iOS Simulator — **succeeded, 0 warnings, 0 errors**
- ✅ Test suite: macOS — **20/20 passed**
- ✅ Test suite: iOS Simulator — **20/20 passed**

WhisperKit version: `0.18.0`. Xcode: `26.3`. iOS SDK: `26.3`.
