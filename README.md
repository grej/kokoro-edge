# kokoro-edge

Local voice engine daemon for Apple Silicon. The Ollama of voice.

Running local TTS on Apple Silicon today usually means fighting Python dependency hell. Kokoro is an exceptional 82M-parameter open-weight model, but getting it running often requires `mlx-audio`, `misaki`, `spacy`, `thinc`, and `blis` with fragile version pinning and opaque ABI failures. `kokoro-edge` replaces that stack with a native Swift daemon that downloads the model once, warms it up, and serves low-latency speech over local WebSocket and OpenAI-compatible HTTP APIs.

## Demo

Target install-to-first-audio flow (Homebrew is planned post-v0.1):

```bash
brew tap <org>/kokoro-edge && brew install kokoro-edge
kokoro-edge serve
curl -X POST localhost:7777/v1/audio/speech -H "Content-Type: application/json" \
  -d '{"input":"Hello world"}' -o hello.wav && afplay hello.wav
```

Current v0.1 install paths are the curl installer and building from source, both documented below.

## Install

### Curl Installer

```bash
curl -fsSL https://raw.githubusercontent.com/<org>/kokoro-edge/main/Scripts/install.sh -o install-kokoro-edge.sh
chmod +x install-kokoro-edge.sh
KOKORO_EDGE_REPO=<org>/kokoro-edge ./install-kokoro-edge.sh
```

The installer:

- installs `kokoro-edge` to `~/.local/bin`
- installs the supporting frameworks to `~/.local/lib`
- adds `~/.local/bin` to `PATH` in `~/.zshrc` if needed
- pulls `kokoro-82m` on install

### Build From Source

Source builds require `Xcode 16.4+` and `Swift 6.1+`.

```bash
git clone https://github.com/<org>/kokoro-edge.git
cd kokoro-edge
./Scripts/build-source.sh
.build-xcode/stage/bin/kokoro-edge serve
```

Supported source-build commands:

```bash
xcodebuild build -configuration Release -scheme kokoro-edge -destination 'platform=macOS,arch=arm64'
xcodebuild test -scheme kokoro-edge -destination 'platform=macOS,arch=arm64'
```

`swift build` is still useful as a compile check, but the runnable MLX artifact comes from `xcodebuild` and `./Scripts/build-source.sh`.

### Homebrew

Homebrew packaging is planned for post-v0.1, once the release workflow has seen a few stable releases.

## Usage

### CLI

Start the daemon in the foreground:

```bash
kokoro-edge serve
```

Start it in the background:

```bash
kokoro-edge serve -d
kokoro-edge status
kokoro-edge stop
```

First run is one uninterrupted flow:

```text
First run detected. Downloading kokoro-82m model (~330MB)...
...download progress...
kokoro-edge v0.1.0
Model: kokoro-82m (loaded)
Voices: 28 available
WebSocket: ws://localhost:7777/ws
HTTP API:  http://localhost:7777/v1/
Ready.
```

One-shot synthesis:

```bash
kokoro-edge tts "Hello from Kokoro Edge" --voice af_sky --output hello.wav
afplay hello.wav
```

Pipe mode:

```bash
echo "Testing stdin pipe" | kokoro-edge tts > pipe.wav
afplay pipe.wav
```

Diagnostics:

```bash
kokoro-edge doctor
```

### HTTP API

Status:

```bash
curl http://localhost:7777/v1/status
```

Voice discovery:

```bash
curl http://localhost:7777/v1/voices
```

Speech:

```bash
curl -X POST http://localhost:7777/v1/audio/speech \
  -H "Content-Type: application/json" \
  -d '{"input":"Hello from the API","voice":"af_sky"}' \
  --output api.wav -D headers.txt
afplay api.wav
```

The speech response includes `X-Request-Id` and permissive CORS headers so browser clients can call `localhost:7777` directly.

### WebSocket API

With `websocat`:

```bash
echo '{"type":"tts","text":"Hello world","voice":"af_heart","format":"wav"}' | websocat ws://localhost:7777/ws > ws.wav
afplay ws.wav
```

Status over WebSocket:

```bash
echo '{"type":"status"}' | websocat ws://localhost:7777/ws
```

## Voices

The bundled voice inventory returned by `GET /v1/voices` is:

| Name | Language | Gender |
| --- | --- | --- |
| `af_alloy` | `en-us` | `F` |
| `af_aoede` | `en-us` | `F` |
| `af_bella` | `en-us` | `F` |
| `af_heart` | `en-us` | `F` |
| `af_jessica` | `en-us` | `F` |
| `af_kore` | `en-us` | `F` |
| `af_nicole` | `en-us` | `F` |
| `af_nova` | `en-us` | `F` |
| `af_river` | `en-us` | `F` |
| `af_sarah` | `en-us` | `F` |
| `af_sky` | `en-us` | `F` |
| `am_adam` | `en-us` | `M` |
| `am_echo` | `en-us` | `M` |
| `am_eric` | `en-us` | `M` |
| `am_fenrir` | `en-us` | `M` |
| `am_liam` | `en-us` | `M` |
| `am_michael` | `en-us` | `M` |
| `am_onyx` | `en-us` | `M` |
| `am_puck` | `en-us` | `M` |
| `am_santa` | `en-us` | `M` |
| `bf_alice` | `en-gb` | `F` |
| `bf_emma` | `en-gb` | `F` |
| `bf_isabella` | `en-gb` | `F` |
| `bf_lily` | `en-gb` | `F` |
| `bm_daniel` | `en-gb` | `M` |
| `bm_fable` | `en-gb` | `M` |
| `bm_george` | `en-gb` | `M` |
| `bm_lewis` | `en-gb` | `M` |

## API Reference

### `POST /v1/audio/speech`

OpenAI-compatible local TTS endpoint.

Request:

```json
{
  "model": "kokoro-82m",
  "input": "Hello from Kokoro Edge",
  "voice": "af_heart",
  "speed": 1.0,
  "response_format": "wav",
  "language": "en-us"
}
```

Behavior:

- `model` may be omitted or set to `kokoro-82m`
- `response_format` may be omitted or set to `wav`
- response body is `audio/wav`
- response header includes `X-Request-Id`

### `GET /v1/status`

Response:

```json
{
  "version": "0.1.0",
  "model": "kokoro-82m",
  "models_loaded": ["kokoro-82m"],
  "voices_available": ["af_heart", "af_sky"],
  "uptime_seconds": 42
}
```

### `GET /v1/voices`

Response:

```json
{
  "voices": [
    { "name": "af_heart", "language": "en-us", "gender": "F" },
    { "name": "bf_emma", "language": "en-gb", "gender": "F" }
  ]
}
```

## Building From Source

Use the staged build helper:

```bash
./Scripts/build-source.sh
.build-xcode/stage/bin/kokoro-edge tts "Hello from Kokoro Edge" --output hello.wav
```

To build a release tarball locally:

```bash
./Scripts/make-release.sh
```

This produces:

- `dist/kokoro-edge-<version>-macos-arm64.tar.gz`
- `dist/kokoro-edge-<version>-macos-arm64.tar.gz.sha256`

## Architecture

`kokoro-edge` is a small local daemon with one long-lived `TTSEngine` inside an actor-owned `TTSService`. The service loads the Kokoro model once, warms Metal on startup, and serializes synthesis requests so server code never races direct access to MLX state. Hummingbird handles the local HTTP and WebSocket surfaces on one port, while `xcodebuild` remains the supported source-build path because MLX requires Metal resources that plain SwiftPM CLI builds do not package correctly.

## Roadmap

- Homebrew tap after the release workflow has stabilized
- streaming / incremental TTS
- STT and duplex voice loops
- tutor integration with token timing and synchronized highlighting
- daemon lifecycle polish beyond raw PID management

## License

MIT. See [LICENSE](LICENSE).
