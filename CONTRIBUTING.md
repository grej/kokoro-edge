# Contributing

## Prerequisites

- Apple Silicon Mac
- macOS 15+
- Xcode 16.4+
- Swift 6.1+

## Build and Test

Compile-only check:

```bash
swift build
```

Supported source-build artifact:

```bash
./Scripts/build-source.sh
```

Supported test command:

```bash
xcodebuild test -scheme kokoro-edge -destination 'platform=macOS,arch=arm64'
```

Release tarball helper:

```bash
./Scripts/make-release.sh
```

## Project Decisions

### Why Hummingbird

Hummingbird keeps the daemon small, concurrency-native, and easy to reason about for a single-process local service. The project only needs local HTTP plus WebSocket support, so Vapor’s extra surface area is unnecessary here.

### Why Actor-Owned TTS State

`TTSEngine` is intentionally long-lived and reused. The server keeps exactly one initialized engine inside an actor-owned `TTSService`, which serializes synthesis requests and avoids racing direct access to MLX / Metal-backed state.

### Why `xcodebuild`

The runnable MLX artifact must come from `xcodebuild` because plain `swift build` does not package the Metal shader resources MLX needs at runtime. `swift build` remains useful for compile checks, but the supported runtime build is `./Scripts/build-source.sh`.

## Filing Issues

Please include:

- the output of `kokoro-edge doctor`
- the exact command you ran
- whether you used the curl installer or a source build
- any relevant daemon log lines from `~/.kokoro-edge/kokoro-edge.log`
