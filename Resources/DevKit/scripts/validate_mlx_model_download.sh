#!/bin/zsh

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "[-] usage: $0 <downloaded-model-directory>" >&2
    exit 1
fi

MODEL_DIR="$1"

python3 - "$MODEL_DIR" <<'PY'
import json
import pathlib
import sys

model_dir = pathlib.Path(sys.argv[1])
required = [
    "config.json",
    "chat_template.jinja",
    "model.safetensors",
    "tokenizer.json",
    "tokenizer_config.json",
]

missing = [name for name in required if not (model_dir / name).is_file()]
if missing:
    raise SystemExit(f"[-] missing required model files: {', '.join(missing)}")

config = json.loads((model_dir / "config.json").read_text(encoding="utf-8"))
model_type = config.get("model_type")
architectures = config.get("architectures")

if model_type != "qwen3_5":
    raise SystemExit(f"[-] unsupported model_type: {model_type!r}")
if not isinstance(architectures, list) or "Qwen3_5ForConditionalGeneration" not in architectures:
    raise SystemExit(f"[-] unexpected architectures: {architectures!r}")

chat_template = (model_dir / "chat_template.jinja").read_text(encoding="utf-8")
required_template_tokens = ["<tools>", "<tool_call>", "<function="]
missing_template_tokens = [
    token
    for token in required_template_tokens
    if token not in chat_template
]
if missing_template_tokens:
    raise SystemExit(
        "[-] chat template is missing tool-call tokens: "
        + ", ".join(missing_template_tokens)
    )

print("[+] mlx model download validated")
print(f"[+] model_type: {model_type}")
print(f"[+] architectures: {', '.join(architectures)}")
print("[+] chat template supports XML tool calls")
PY
