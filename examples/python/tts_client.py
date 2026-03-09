import requests

response = requests.post(
    "http://localhost:7777/v1/audio/speech",
    json={"input": "Hello from Python", "voice": "af_heart"},
    timeout=30,
)
response.raise_for_status()

with open("hello.wav", "wb") as handle:
    handle.write(response.content)

print("Wrote hello.wav")
