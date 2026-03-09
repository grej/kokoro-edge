# Changelog

## v0.1.0

- Native Swift CLI for local Kokoro TTS on Apple Silicon
- Model download and local cache management under `~/.kokoro-edge/models`
- One-shot CLI synthesis with WAV output, stdin piping, and voice selection
- Foreground server with WebSocket and OpenAI-compatible HTTP APIs
- Voice discovery endpoint and request IDs on HTTP speech responses
- Daemon lifecycle commands: `serve -d`, `stop`, `status`, and `doctor`
- Xcode-backed source build helper and release tarball helper
- Curl installer targeting `~/.local`
- OSS docs, examples, and contributor guidance
