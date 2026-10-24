# Initial source-release validation

Validation date: **2026-10-25**. This report describes the independent public
source snapshot. It does not certify a hosted service or GPU deployment.

## Application checks

The source was installed into a fresh Python 3.11 environment and the frontend
was installed with `npm ci` on Node.js 24. Build the frontend before running the
backend tests because the SPA deep-link test needs `web/dist/index.html`.

```sh
python3.11 -m venv .venv
.venv/bin/python -m pip install -r requirements-dev.txt
npm --prefix web ci
npm --prefix web test
npm --prefix web run build
GSSTUDIO_MANAGE_VLLM=false .venv/bin/python -m pytest -q
```

| Check | Result |
| --- | --- |
| Fresh Python 3.11 environment | 159 tests passed; two upstream test-client deprecation warnings |
| Frontend | 56 tests passed across eight files |
| TypeScript and production frontend build | Passed; viewer bundle-size warning remains |
| Deployment templates and scripts | 19 deployment-contract tests passed; shell syntax, YAML parsing, local image replacement, and parameterized prefetch generation checked |
| CPU container | `Dockerfile.lite` built successfully for Linux ARM64 and served health, home, and SPA deep-link routes |
| Container task flow | Two synthetic PNGs submitted as `worldrecon`: HTTP 201, then `pending` → `running` → `completed`; artifact listing passed |
| Container packaging | License files and WebSocket dependency present; `.env` and `.git` absent; test container removed after verification |
| Patch notices | Four patch regression tests passed; fixed upstream source patching was idempotent and added notices did not change Python AST behavior |
| Secret scan | Gitleaks found no secrets in the candidate public snapshot |
| Private-content review | No known private endpoints, host/user paths, actual task identifiers, or private author email remained in the candidate source |

The CPU image was built for local verification only and is not a published
container artifact. Its mock PLY/SPZ outputs were checked as placeholders,
not as renderable scenes. GPU overlay construction and real inference were
not performed.

The pinned-action [Application checks workflow](../.github/workflows/ci.yml)
runs the frontend tests/build and backend tests on Linux, Python 3.11, and
Node.js 24. The actual remote run status is available in
[GitHub Actions](https://github.com/eust-w/gsstudio-public/actions/workflows/ci.yml).

## Dependency audit results

Audits were run on the public dependencies on the validation date. These are
unresolved findings, not a clean security audit. Package counts differ from
advisory counts, and audit results can change as advisory databases change.

`npm audit` reported **six affected packages: four high, two moderate**:

| Package | Severity |
| --- | --- |
| `nanoid` | High |
| `source-map-js` | High |
| `undici` | High |
| `vite` | High |
| `@vitest/mocker` | Moderate |
| `vitest` | Moderate |

`pip-audit -r requirements-dev.txt`, resolved with Python 3.11, reported
**44 advisories across four packages**:

| Package | Resolved version | Advisory count | Fix version reported by the audit |
| --- | --- | --- | --- |
| `filelock` | 3.32.2 | 3 | 4.2.1 |
| `urllib3` | 2.7.0 | 3 | 2.8.0 |
| `setuptools` | 84.0.0 | 1 | 84.1.0 |
| `Pillow` | 12.3.0 | 37 | 13.0.0 |

These are dependency-tool findings, not an exploitability assessment of every
GSStudio route. Fix versions are audit output, not compatibility-validated
upgrade recommendations. This publication keeps the existing dependency
baseline; major-version upgrades and GPU-stack verification remain future work.
See [security guidance](../SECURITY.md) for exposure boundaries and reporting.

## Publication scope

The public repository starts with an independent Git history. The snapshot
excludes private operational reports, deployment endpoints, historical task
records, model weights, local databases, and generated output. It uses generic
deployment examples and a user-supplied GPU base image.

Original application code uses Apache-2.0. Optional model runtimes and
upstream-derived excerpts retain their own terms; see
[third-party notices](../THIRD_PARTY_NOTICES.md). The five included license
copies have SHA-256 provenance records. Patch modification notices were checked
against the referenced upstream sources for idempotence and unchanged Python
AST behavior.

## Limits

- Real GPU inference, model quality, and real-scene browser rendering were
  not validated for this source release. The repository does not provide a
  complete GPU base-image build recipe.
- Mock reconstruction demonstrates application state transitions and artifact
  delivery only. Its placeholder PLY/SPZ files cannot be rendered as real scenes.
- World-generation creation retains the SAM3 access/cache requirement even in
  mock mode. Use synthetic reconstruction inputs for a demo without model access.
- The frontend build warns about large viewer bundles. This is a performance
  limitation, not a build failure.
- Dependency audits contain unresolved findings. See [security guidance](../SECURITY.md)
  before deploying; functional test success does not establish security.
