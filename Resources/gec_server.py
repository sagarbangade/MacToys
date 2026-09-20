#!/usr/bin/env python3
"""
GEC Server - Grammar Error Correction sidecar for MacToys.

Loads Grammarly's CoEdit-Large (T5-based) model via Apple MLX framework
and provides grammar correction via JSON stdin/stdout protocol.

Protocol:
  Input  (one JSON per line on stdin):  {"text": "He go to school", "id": "1"}
  Output (one JSON per line on stdout): {"corrected": "He goes to school.", "id": "1"}

Special commands:
  {"command": "ping"}     -> {"status": "ok"}
  {"command": "shutdown"} -> exits
"""

import sys
import json
import os

# Add the T5 module path
T5_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "t5_module")
sys.path.insert(0, T5_DIR)


def load_model(model_name="grammarly/coedit-large"):
    """Load the T5 model using MLX."""
    import mlx.core as mx
    from t5 import T5, Tokenizer

    sys.stderr.write(f"[GEC] Loading model: {model_name}\n")
    sys.stderr.flush()

    dtype = mx.bfloat16
    model, tokenizer = T5.from_pretrained(model_name, dtype)

    sys.stderr.write(f"[GEC] Model loaded successfully\n")
    sys.stderr.flush()

    return model, tokenizer


def correct_text(model, tokenizer, text, max_tokens=256):
    """Generate corrected text from the T5 model."""
    import mlx.core as mx
    from t5 import generate

    tokens = []
    for i, token in enumerate(generate(text, model, tokenizer, temp=0.0)):
        if token.item() == tokenizer.eos_id:
            break
        tokens.append(token.item())
        if i >= max_tokens:
            break

    # Decode all tokens
    result = tokenizer.decode(tokens, with_sep=True).strip()
    return result


def main():
    # Signal readiness BEFORE loading model (so Swift knows process started)
    sys.stdout.write(json.dumps({"status": "loading"}) + "\n")
    sys.stdout.flush()

    model, tokenizer = load_model()

    # Signal ready
    sys.stdout.write(json.dumps({"status": "ready"}) + "\n")
    sys.stdout.flush()

    # Main loop: read JSON lines from stdin
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue

        try:
            request = json.loads(line)
        except json.JSONDecodeError:
            sys.stdout.write(json.dumps({"error": "invalid JSON"}) + "\n")
            sys.stdout.flush()
            continue

        # Handle commands
        if "command" in request:
            cmd = request["command"]
            if cmd == "ping":
                sys.stdout.write(json.dumps({"status": "ok"}) + "\n")
                sys.stdout.flush()
            elif cmd == "shutdown":
                sys.stderr.write("[GEC] Shutting down\n")
                sys.stderr.flush()
                break
            continue

        # Handle correction request
        text = request.get("text", "")
        req_id = request.get("id", "")

        if not text.strip():
            sys.stdout.write(json.dumps({"corrected": text, "id": req_id}) + "\n")
            sys.stdout.flush()
            continue

        try:
            # Prepend the CoEdit instruction
            instruction = f"Fix grammatical errors in this sentence: {text}"
            corrected = correct_text(model, tokenizer, instruction)
            sys.stdout.write(json.dumps({"corrected": corrected, "id": req_id}) + "\n")
            sys.stdout.flush()
        except Exception as e:
            sys.stderr.write(f"[GEC] Error: {e}\n")
            sys.stderr.flush()
            sys.stdout.write(json.dumps({"corrected": text, "id": req_id, "error": str(e)}) + "\n")
            sys.stdout.flush()


if __name__ == "__main__":
    main()
