async function playKokoro() {
  const response = await fetch("http://localhost:7777/v1/audio/speech", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ input: "Hello from the browser", voice: "af_heart" }),
  });

  if (!response.ok) {
    throw new Error(`kokoro-edge request failed: ${response.status}`);
  }

  const blob = await response.blob();
  const url = URL.createObjectURL(blob);
  const audio = new Audio(url);
  audio.play();
}

playKokoro().catch((error) => console.error(error));
