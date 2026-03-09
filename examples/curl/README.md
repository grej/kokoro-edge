# curl examples

Status:

```bash
curl http://localhost:7777/v1/status
```

Voices:

```bash
curl http://localhost:7777/v1/voices
```

Speech:

```bash
curl -X POST http://localhost:7777/v1/audio/speech \
  -H "Content-Type: application/json" \
  -d '{"input":"Hello from curl","voice":"af_sky"}' \
  --output hello.wav -D headers.txt
afplay hello.wav
```

WebSocket:

```bash
echo '{"type":"tts","text":"Hello world","voice":"af_heart","format":"wav"}' | websocat ws://localhost:7777/ws > ws.wav
afplay ws.wav
```
