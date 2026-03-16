# Contributing

Thanks for contributing to WhisperMac.

## Development Setup

1. Install Xcode 16+ and select it:

```bash
sudo xcode-select -s /Applications/Xcode.app
```

2. Install build dependencies:

```bash
brew install cmake python@3.11
```

3. Prepare runtime assets:

```bash
./scripts/setup-whispercpp.sh
./scripts/prepare-model.sh
```

## Build and Test

```bash
swift build
swift test
```

Notes:

- `afconvert` is provided by macOS and is used for audio preprocessing.
- `python3.11` is recommended for Core ML model preparation in
  `scripts/prepare-model.sh`.

To build the app bundle:

```bash
./scripts/build-app-bundle.sh
```

## Pull Requests

- Keep changes focused.
- Include tests when behavior changes.
- Prefer updating `README.md` when setup or runtime behavior changes.
- Do not commit `Models/`, `.build/`, `dist/`, or local backups.
