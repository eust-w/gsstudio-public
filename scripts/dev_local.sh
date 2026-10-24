#!/usr/bin/env bash
# Local API + Vite demo with synthetic pipeline progress.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PYTHON_BIN="${PYTHON_BIN:-python3}"

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
    echo "ERROR: Python 3.11+ is required. Set PYTHON_BIN to its executable." >&2
    exit 1
fi
"$PYTHON_BIN" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else "Python 3.11+ is required")'
command -v npm >/dev/null 2>&1 || { echo "ERROR: Node.js/npm are required" >&2; exit 1; }

VENV="$ROOT_DIR/.venv"
if [ ! -d "$VENV" ]; then
    "$PYTHON_BIN" -m venv "$VENV"
fi
source "$VENV/bin/activate"
python -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else "Existing .venv needs Python 3.11+; recreate it before continuing")'
python -m pip install -r "$ROOT_DIR/requirements-dev.txt"
(cd "$ROOT_DIR/web" && npm ci)

API_PID=""
VITE_PID=""
cleanup() {
    for pid in "$API_PID" "$VITE_PID"; do
        if [ -n "$pid" ]; then kill "$pid" 2>/dev/null || true; fi
    done
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

cd "$ROOT_DIR"
GSSTUDIO_MOCK_PIPELINE=true \
GSSTUDIO_MANAGE_VLLM=false \
GSSTUDIO_DATA_DIR="$ROOT_DIR/data" \
GSSTUDIO_PORT=8000 \
python -m uvicorn server.main:app --host 127.0.0.1 --port 8000 --reload &
API_PID=$!
(cd "$ROOT_DIR/web" && exec npm run dev -- --host 127.0.0.1 --port 5173 --strictPort) &
VITE_PID=$!

echo "API: http://127.0.0.1:8000 | UI: http://127.0.0.1:5173"
echo "Mock mode; no GPU or real model inference. Press Ctrl+C to stop."
# Stop the other process if either server exits, including startup failures.
while kill -0 "$API_PID" 2>/dev/null && kill -0 "$VITE_PID" 2>/dev/null; do
    sleep 1
done
if ! kill -0 "$API_PID" 2>/dev/null; then wait "$API_PID"; else wait "$VITE_PID"; fi
