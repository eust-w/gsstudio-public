# Deployment

GSStudio has two execution modes. CPU mock mode runs the application and
simulates task stages. Real GPU mode calls an external HY-World runtime with
separately installed models and compiled extensions. This repository includes
no hosted service, model weights, or complete GPU base image.

## CPU demo container

Build the frontend first; the Dockerfile copies the generated `web/dist`
directory:

```sh
npm --prefix web ci
npm --prefix web run build
docker build -f Dockerfile.lite -t gsstudio:demo .
docker run --rm \
  -p 127.0.0.1:8000:8000 \
  -v gsstudio-data:/data \
  gsstudio:demo
```

Open [GSStudio](http://127.0.0.1:8000). The named Docker volume keeps task data
between container runs. The image uses a public Python base and defaults to
`GSSTUDIO_MOCK_PIPELINE=true` and `GSSTUDIO_MANAGE_VLLM=false`.

Follow the [synthetic reconstruction example](../README.md#try-a-task-without-model-downloads)
for a demo without credentials. World-generation creation still checks for
SAM3 model access/cache in mock mode. Mock outputs are placeholder files and
cannot demonstrate the 3D viewer or model quality.

## Real GPU runtime contract

`Dockerfile.a800` is an application overlay. Its required `HYWORLD_BASE_IMAGE`
build argument must name a runtime you have prepared and are licensed to use.
There is no default GPU base image or complete base-image build recipe here.
The overlay updates selected generic Python dependencies, installs SpatialIndex
and `rtree`, applies integration patches, and copies the application and built
frontend. It does not install the full model runtime.

The supplied base must provide:

| Requirement | Expected integration contract |
| --- | --- |
| Operating system | Debian/Ubuntu-compatible package management with root access during the build; Bash and standard Linux utilities |
| HY-World source/runtime | `/opt/hyworld2`, including `hyworld2/worldgen`, `hyworld2/worldrecon`, and the compatible `world_gs_trainer` integration |
| Panorama environment | `/opt/panogen/bin/python` with the expected HunyuanImage-3 image-optional generation interface |
| vLLM environment | `/opt/vllm/bin/python`, compatible with the configured Qwen3-VL model |
| GPU stack | Compatible NVIDIA drivers/runtime, CUDA, PyTorch, `torchrun`, and all upstream compiled extensions |
| API Python | Python 3.11 or newer; the overlay checks the interpreter version and required API imports before installing its dependency baseline |
| Service tools | `supervisord`, `supervisorctl`, and the API dependencies used by the application |
| Model storage | Downloaded weights, upstream-compatible cache paths, and required Torch checkpoints |

API dependencies include FastAPI, Pydantic, Uvicorn with WebSocket support,
`python-multipart`, `aiofiles`, NumPy, and Pillow. The CPU dependencies are
listed in `requirements-runtime.txt`; installing them into a GPU environment
requires checking compatibility with that environment's model stack. The GPU
overlay deliberately does not replace the entire model environment with the
CPU requirements.

Required upstream extensions include the compatible Gaussian Splatting and
MaskGaussian components, navigation mesh support, FlashAttention, SPZ support,
and other dependencies required by your HY-World checkout. Consult the
[upstream installation instructions](https://github.com/Tencent-Hunyuan/HY-World-2.0)
and [third-party notices](../THIRD_PARTY_NOTICES.md). Preparing and validating
this base is an operator responsibility; a successful overlay build alone
does not prove model execution works.

Once the base is available, build the application image:

```sh
npm --prefix web ci
npm --prefix web run build
docker build -f Dockerfile.a800 \
  --build-arg HYWORLD_BASE_IMAGE=registry.example.invalid/your-team/hyworld-runtime:YOUR_TAG \
  -t registry.example.invalid/your-team/gsstudio:YOUR_TAG .
```

Replace both image references with your own registry and immutable tags or
digests. Publish the resulting image to a registry accessible by your cluster.
The example registry is intentionally not a working download source.

## Models and cache preparation

Accept applicable model licenses and access conditions before downloading
weights. World generation uses gated `facebook/sam3`: its initial download
requires an `HF_TOKEN` with approved access. A complete local cache can be used
without retaining that token. Reconstruction does not require the SAM3 token.

The deployment stores Hugging Face snapshots at `/models/hf-cache` and Torch
checkpoints at `/models/torch-cache`. A prefetch helper is provided:

```sh
HF_HOME=/models/hf-cache \
TORCH_HOME=/models/torch-cache \
bash deploy/scripts/prefetch_models.sh
```

Run it inside the prepared GPU runtime, with persistent storage mounted and
credentials supplied through your secret-management mechanism. It requires
the relevant Python download libraries. Downloading snapshots is only one
part of preparation: arrange the cache and any upstream model paths to match
your installed HY-World runtime.

Startup checks require the VGG16 checkpoint, WorldStereo model files and Wan
scheduler configuration, `rtree`, and the expected panorama generation
interface. A failed check stops startup. Passing these checks is still not an
end-to-end GPU acceptance test.

## Kubernetes templates

The manifests are examples that require editing for your cluster. They use
persistent volume claims rather than node-specific host directories. The GPU
variant requests five GPUs on one node and substantial CPU memory; review
its resource requests and limits against your runtime before deployment.

1. Confirm the Kubernetes context and create the namespace:

   ```sh
   kubectl config current-context
   kubectl apply -f deploy/k8s/namespace.yaml
   ```

2. Review `deploy/k8s/pvc.yaml`, choose a storage class and capacity, then apply
   it. The sample allocates 500 GiB each for models and task data; these are
   example allocations, not measured minimum requirements.

   ```sh
   kubectl apply -f deploy/k8s/pvc.yaml
   ```

3. Provision a `gsstudio-basic-auth` Secret in the `gsstudio` namespace with
   `username` and `password` keys. If downloading gated models, also provision
   `gsstudio-huggingface` with a `token` key. Keep their values outside Git.
   Configure image-pull credentials separately if your registry requires them.

4. For GPU mode, populate the model volume before starting the application:

   ```sh
   GSSTUDIO_IMAGE=registry.example.invalid/your-team/gsstudio:YOUR_TAG \
     bash deploy/scripts/prefetch_models.sh --k8s
   kubectl -n gsstudio logs -f job/gsstudio-prefetch-models
   ```

   The Job uses the `gsstudio-models` PVC and does not request GPUs. The helper
   accepts `GSSTUDIO_NAMESPACE` and `GSSTUDIO_MODELS_PVC` overrides. Confirm the
   Job succeeds and complete any runtime-specific cache layout setup before
   deploying the service.

5. Deploy the image you built and published:

   ```sh
   GSSTUDIO_IMAGE=registry.example.invalid/your-team/gsstudio:YOUR_TAG \
   DEPLOYMENT_VARIANT=gpu \
     bash deploy/scripts/deploy.sh
   ```

   Use `DEPLOYMENT_VARIANT=mock` with a published `Dockerfile.lite` image for a
   CPU deployment. The default variant is `mock`. The deployment helper uses
   the current context and the `gsstudio` namespace. When applying manifests
   directly, replace their placeholder image references first.

Ingress is opt-in. Configure the hostname, ingress controller, and TLS values
in `deploy/k8s/ingress.yaml` before using `APPLY_INGRESS=true` with the deployment
helper. Use TLS and authentication for remote access. The application provides
no per-user task isolation and is intended for a trusted team environment.
Keep one replica and one API process because the task queue uses SQLite and a
single in-process worker.

## Configuration

| Variable | Purpose |
| --- | --- |
| `GSSTUDIO_MOCK_PIPELINE` | Simulate pipeline execution when `true` |
| `GSSTUDIO_MANAGE_VLLM` | Allow the worker to stop/restart the supervised vLLM process |
| `GSSTUDIO_DATA_DIR` | Database and task-data root |
| `GSSTUDIO_HF_HOME`, `HF_HOME` | Application and upstream Hugging Face cache paths; keep these aligned |
| `TORCH_HOME` | Torch checkpoint cache |
| `GSSTUDIO_HYWORLD_REPO` | HY-World runtime checkout path |
| `GSSTUDIO_PANOGEN_PYTHON` | Panorama environment's Python executable |
| `GSSTUDIO_NUM_GPUS` | GPU count used by pipeline command generation |
| `VLLM_HOST`, `VLLM_PORT`, `VLLM_MODEL` | Trajectory-planning service connection and model |
| `GSSTUDIO_BASIC_AUTH_USER`, `GSSTUDIO_BASIC_AUTH_PASSWORD` | Basic Auth credentials |
| `HF_TOKEN` | Approved model-download credential, when needed |

## Validate your deployment

`GET /api/health` checks only API liveness. In mock mode, GPU status is
synthetic. In real mode, `GET /api/gpu/status` queries `nvidia-smi` but can return
an empty list on failure; it is not an inference health check.

For real acceptance, inspect GPU and supervised-process state, run a task with
inputs you have permission to use, wait for its final status, inspect its
artifacts and quality report, and verify panorama/3DGS rendering in a browser.
For real world generation, confirm `artifact_validation.valid` alongside the
completed task status. Review failure logs if a model, cache, or extension is
incompatible. Local tests and CPU mock completion do not replace this check.
