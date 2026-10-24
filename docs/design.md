# Architecture

GSStudio is an application and orchestration layer for HY-World 2.0. The React
frontend talks to a FastAPI service that stores task metadata in SQLite and
runs one asynchronous pipeline worker. The worker launches model commands as
subprocesses in a separately installed GPU runtime.

## Components

| Component | Role |
| --- | --- |
| React + Vite frontend | Task creation, progress, logs, artifact browsing, panorama and 3DGS viewers |
| FastAPI service | REST endpoints, WebSocket logs, optional Basic Auth, static frontend serving |
| SQLite database | Durable task queue, configuration, stage state, and artifact metadata |
| Pipeline worker | Serial task execution, cancellation, checkpoints, and recovery |
| HY-World runtime | Panorama generation, trajectory planning/rendering, video generation, reconstruction, and 3DGS training |
| vLLM process | Qwen3-VL trajectory-planning inference over HTTP |

In the GPU container template, supervisord manages the API and vLLM as
separate processes. The API starts the worker. vLLM uses its own Python
environment to avoid coupling its dependencies to the model pipelines.
The worker can stop and restart vLLM around memory-intensive stages; set
`GSSTUDIO_MANAGE_VLLM=false` when managing that service externally.

The application runs a single worker and processes all task types serially.
Run one API process and one deployment replica against its SQLite queue;
multiple workers are not a supported scaling configuration.

## Task paths

| Task type | Input | Execution |
| --- | --- | --- |
| `worldgen` | Text prompt, source image, or both | Source/panorama generation followed by the world-generation stages |
| `worldgen_from_pano` | Panorama image | World-generation stages, skipping source/panorama generation |
| `worldrecon` | Multi-view images or video | WorldMirror reconstruction |

World generation proceeds through `traj_generate`, `traj_render`, `video_gen`,
`gen_gs_data`, and `gs_training`. Prompt-only generation first creates a source
image using the panorama runtime. The integration expects that runtime's
image-generation method to support an omitted source image.

Tasks move from `pending` to `running`, then to `completed`, `failed`, or
`cancelled`. Individual stages additionally support `skipped` when reusing
checkpointed work. See the [API reference](api.md) for input requirements and
retry eligibility.

## Generation quality and delivery

For high-quality world generation, trajectory acceptance determines the
training mode:

| Accepted trajectories | Delivery tier | Training inputs |
| --- | --- | --- |
| At least 6 | `strict_3d` | Accepted trajectories |
| 1–5 | `degraded_3d` | Accepted trajectories and RGB-D anchors |
| 0 | `anchored_3d` | Panorama/polar RGB-D anchors |

Rejected trajectories are excluded from training. Each current tier proceeds
to data preparation and 3DGS training; an anchored result carries less
multi-view evidence than a strict result. The tier describes the inputs and
recovery outcome, not an assurance of geometric accuracy.

For real world-generation tasks, completion requires artifact validation:
an SPZ, Gaussian PLY, matching-step trainer checkpoint, and parseable viewer
pose metadata. The validator checks that the SPZ decodes into at least 50,000
Gaussians, attributes and opacities are finite, and the bounds are
non-degenerate. Results are written to `artifact_validation.json`.
These structural checks do not establish visual quality or reconstruction
accuracy. Reconstruction and mock tasks do not use this world-generation
completion gate.

If training produces a valid export before a later auxiliary evaluation
failure, that export may still be accepted. Otherwise, a bounded safe retry
can reduce the initialization cloud, freeze means, and disable densification.
Failure to produce valid artifacts leaves the task failed.

## Checkpoints and recovery

Completed stages write `.stage_<name>_done` markers. Retrying a failed or
cancelled task reuses its input, configuration, checkpoints, and recovery
journal. Existing real 3D delivery is revalidated before training output is
reused.

High-quality generation with automatic recovery also keeps an atomic
`auto_recovery.json` journal. It records candidate batches, source attempts,
quality decisions, budgets, and transient retries. The default recovery
budgets allow 32 video paths, 90 minutes of recorded video-generation time,
and one additional generated source. Time is checked between batches; it is
not an end-to-end task timeout.

Manual source retry archives previous downstream output under the relevant
recovery attempt and queues a replacement source. Prior attempts remain
available, and cumulative path/time usage is retained. Completed degraded or
anchored deliveries are eligible only when their recovery budget is exhausted;
other status and configuration restrictions are documented in
[the source-retry API](api.md#retry-source).

Legacy `panorama_only` journal values are mapped to the current delivery tiers
when read. This migration does not create or validate missing 3D artifacts.

## Storage

`GSSTUDIO_DATA_DIR` contains the database and task directories:

```text
<data-dir>/
├── gsstudio.db
└── tasks/
    └── <task-id>/
        ├── input/
        ├── scene/
        ├── output/
        ├── logs/
        ├── auto_recovery.json
        ├── recovery_attempts/
        ├── training_input_manifest.json
        └── artifact_validation.json
```

Model snapshots use `GSSTUDIO_HF_HOME`/`HF_HOME`; Torch checkpoints use
`TORCH_HOME`. The deployment templates mount persistent volumes at `/data`
and `/models`. Keep task storage and model caches outside the source checkout
and back up task data before replacing a deployment.

## GPU and mock execution

The provided GPU template describes five GPUs on one node. The orchestration
allocates GPU 0 to vLLM and trajectory planning by default; panorama
preparation, trajectory rendering, data preparation, and training can use
multiple GPUs. WorldStereo uses a compatible subset because its sequence
parallelism must divide its attention-head count. Reconstruction defaults to
one GPU and accepts a `recon_gpus` configuration option.

GPU count alone does not establish compatibility. Model memory needs, CUDA
extensions, PyTorch versions, cache layout, and upstream runtime behavior must
be validated together. `Dockerfile.a800` extends a user-supplied runtime;
this repository does not provide a complete reproducible GPU base build.

Mock mode requires no GPU and simulates stage progress and logs. Its PLY/SPZ
outputs are placeholder bytes. The GPU status endpoint also returns synthetic
values in mock mode. A successful mock task therefore validates application
flow, not model execution or viewer rendering.

## Operational boundaries

`/api/health` reports API liveness. It does not validate model caches, GPU
availability, vLLM, or scene generation. The real GPU status endpoint reads
`nvidia-smi` but may return an empty list on query failure; its vLLM label is
not process-level ownership detection.

Basic Auth is optional and must be enabled for a remotely accessible service,
with TLS terminated by the deployment. The included application does not
provide per-user task isolation or a multi-tenant scheduler. Read the
[deployment guide](deployment.md) and [security policy](../SECURITY.md) before
exposing it beyond local development.
