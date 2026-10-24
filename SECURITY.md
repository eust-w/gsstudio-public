# Security

This is an initial source preview for local evaluation and trusted-team use.
Application tests do not establish production security. The release retains
existing dependency versions and has unresolved dependency advisories; see
[release validation](docs/release-validation.md) for the dated audit results.

## Deployment boundaries

- Follow the loopback-only local examples. Basic Auth is optional and is
  disabled unless both `GSSTUDIO_BASIC_AUTH_USER` and
  `GSSTUDIO_BASIC_AUTH_PASSWORD` are set. Do not expose an unconfigured
  instance to the Internet.
- Use TLS, authentication, and a restricted reverse proxy for remote access.
  The API has permissive CORS defaults. It does not provide per-user task
  isolation, quotas, or an authorization model for mutually untrusted tenants.
- Uploaded data, logs, and task artifacts are accessible to the configured
  application users. Restrict input sizes at the proxy, review data-retention
  rules, and protect the persistent task and model volumes.
- Run one API worker and one replica. The task queue uses SQLite and a single
  in-process worker. GPU images and upstream dependencies require a separate
  security and license review.
- Keep Hugging Face tokens, registry credentials, TLS keys, and runtime data
  outside Git and image build contexts. Use your secret manager or Kubernetes
  Secrets; never place real credentials in manifests or issue reports.

The CPU demo is designed to exercise queue and UI behavior, with placeholder
artifacts. It is not a hardened public service or a validation of GPU inference.
The public repository does not include a complete GPU runtime or a hosted demo.

## Dependency audit

Run the following in a fresh environment:

```sh
npm --prefix web audit
.venv/bin/python -m pip install pip-audit
.venv/bin/python -m pip_audit -r requirements-dev.txt
```

Audit tools may return a nonzero exit status for known findings. The
`Application checks` workflow verifies tests and builds; a passing workflow
does not imply a clean dependency audit. The dependency file named
`deploy/requirements-security.txt` is a retained compatibility baseline, not a
claim that its versions are free of current advisories. Upgrading the API and
GPU stack requires compatibility testing, including any major-version changes.

## Reporting a vulnerability

Use this repository's [private vulnerability reporting](https://github.com/eust-w/gsstudio-public/security/advisories/new)
for sensitive findings. Include the affected revision, a minimal synthetic
reproduction, and the impact. Do not include live credentials, personal data,
model weights, or private deployment details. If private reporting is
temporarily unavailable, do not publish sensitive details in a public issue.

This preview has no long-term support or response-time commitment. Security
changes will be documented in the repository and release notes.
