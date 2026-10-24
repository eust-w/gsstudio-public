# GSStudio

A web workspace for creating, monitoring, and previewing 3D world generation
and reconstruction tasks with [HY-World 2.0](https://github.com/Tencent-Hunyuan/HY-World-2.0).
GSStudio combines a React interface, a FastAPI task queue, recovery journals,
and a browser-based Gaussian Splatting viewer.

This repository provides the application source and deployment templates.
There is no hosted public demo. Local mock mode runs on a CPU; real generation
requires a separately prepared GPU runtime and model weights.

This source preview has unresolved dependency advisories. Read the
[security notes](SECURITY.md) before deployment.

## What it does

- **Generate worlds:** orchestrate text or single-image input into a panorama
  and a 3D Gaussian Splatting scene, or start from an uploaded panorama.
- **Reconstruct scenes:** submit multi-view images or video to WorldMirror.
- **Track work:** queue tasks, inspect stage progress and logs, cancel work,
  resume failed tasks, and retry eligible generation tasks with a new source.
- **Inspect results:** browse artifacts, view panoramas, and navigate valid
  3DGS exports in the browser.
- **Recover generation:** persist quality reports and source attempts, reject
  unsuitable trajectories, and validate real world-generation artifacts
  before marking delivery complete.

These model workflows depend on the external runtime described in the
[deployment guide](docs/deployment.md). Mock mode simulates stages and logs;
its PLY/SPZ files are placeholders, not renderable 3D scenes.

## Local quickstart

Use Python 3.11 and Node.js 22 or newer with npm. Clone the repository:

```sh
git clone https://github.com/eust-w/gsstudio-public.git
cd gsstudio-public
```

Start both development servers:

```sh
PYTHON_BIN=python3.11 ./scripts/dev_local.sh
```

The script creates `.venv`, installs Python and frontend dependencies, and
starts mock mode. Open [the interface](http://127.0.0.1:5173) or
[interactive API documentation](http://127.0.0.1:8000/docs). Press Ctrl+C to stop.

For manual setup:

```sh
python3.11 -m venv .venv
.venv/bin/python -m pip install -r requirements-dev.txt
npm --prefix web ci
```

In one terminal, start the API:

```sh
GSSTUDIO_MOCK_PIPELINE=true \
GSSTUDIO_MANAGE_VLLM=false \
GSSTUDIO_DATA_DIR=./data \
.venv/bin/python -m uvicorn server.main:app --host 127.0.0.1 --port 8000 --reload
```

In another terminal, start the frontend:

```sh
npm --prefix web run dev -- --host 127.0.0.1 --port 5173
```

### Try a task without model downloads

Use **World Reconstruction** with two synthetic PNGs to exercise the queue,
progress reporting, logs, and artifact list. Create sample inputs locally:

```sh
.venv/bin/python - <<'PY'
from pathlib import Path
from PIL import Image

out = Path("data/demo-inputs")
out.mkdir(parents=True, exist_ok=True)
for index, color in enumerate(((40, 100, 180), (180, 100, 40)), start=1):
    Image.new("RGB", (128, 128), color).save(out / f"view-{index}.png")
PY
```

Upload them through the interface, or submit them to the API:

```sh
curl --fail-with-body http://127.0.0.1:8000/api/tasks \
  -F type=worldrecon \
  -F name='Mock reconstruction' \
  -F 'images=@data/demo-inputs/view-1.png;type=image/png' \
  -F 'images=@data/demo-inputs/view-2.png;type=image/png'
```

This tests application flow only. Synthetic images and mock artifacts do not
validate reconstruction quality, GPU inference, or the 3D viewer.

The creation endpoints for `worldgen` and `worldgen_from_pano` retain their
SAM3 prerequisite check even in mock mode: they require a complete cached
`facebook/sam3` snapshot or an `HF_TOKEN` with approved model access. Use the
reconstruction example above for a demo without credentials or model downloads.

## Verify the application

After installing the dependencies, run the frontend checks and build before
the backend tests. The backend's SPA navigation test requires `web/dist`:

```sh
npm --prefix web test
npm --prefix web run build
GSSTUDIO_MANAGE_VLLM=false .venv/bin/python -m pytest -q
```

The Python and frontend tests use mocks. A successful build or test suite does
not establish that a real GPU runtime can generate a scene. See
[release validation](docs/release-validation.md) for the checks performed on
this public snapshot.

## Deployment and documentation

- [Deployment](docs/deployment.md): CPU demo container, GPU runtime contract,
  model caches, and Kubernetes templates.
- [Architecture](docs/design.md): task execution, quality tiers, and recovery.
- [API reference](docs/api.md): task creation, retries, logs, and artifacts.
- [Security](SECURITY.md): deployment boundaries and reporting a vulnerability.

## License

Original GSStudio application code is licensed under [Apache-2.0](LICENSE).
Upstream code, model runtimes, weights, and other dependencies retain their
own licenses and access conditions; this license does not grant rights to
those materials. See [third-party notices](THIRD_PARTY_NOTICES.md) before
installing or distributing a GPU runtime. Model weights and a complete GPU
base image are not included in this repository.
