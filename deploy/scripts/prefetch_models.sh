#!/usr/bin/env bash
# Download models using a user-provided HY-World runtime and persistent cache.
# Gated repositories require the user's own authorization/HF_TOKEN.
set -euo pipefail

HF_HOME="${HF_HOME:-/models/hf-cache}"
TORCH_HOME="${TORCH_HOME:-/models/torch-cache}"
export HF_HOME TORCH_HOME

if [ "${1:-}" = "--k8s" ]; then
    : "${GSSTUDIO_IMAGE:?Set GSSTUDIO_IMAGE to your image built from Dockerfile.a800}"
    NAMESPACE="${GSSTUDIO_NAMESPACE:-gsstudio}"
    MODELS_PVC="${GSSTUDIO_MODELS_PVC:-gsstudio-models}"
    # These values are rendered as YAML scalars; reject whitespace/control data.
    [[ "$GSSTUDIO_IMAGE" =~ ^[a-zA-Z0-9][a-zA-Z0-9./_:@-]*$ ]] || { echo "Invalid image reference" >&2; exit 1; }
    for name in "$NAMESPACE" "$MODELS_PVC"; do
        [[ "$name" =~ ^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$ ]] || { echo "Invalid Kubernetes name" >&2; exit 1; }
    done
    kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: gsstudio-prefetch-models
  namespace: ${NAMESPACE}
spec:
  backoffLimit: 1
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: prefetch
          image: ${GSSTUDIO_IMAGE}
          command: ["bash", "/app/prefetch_models.sh"]
          env:
            - name: HF_HOME
              value: /models/hf-cache
            - name: TORCH_HOME
              value: /models/torch-cache
            - name: HF_HUB_OFFLINE
              value: "0"
            - name: HF_TOKEN
              valueFrom:
                secretKeyRef:
                  name: gsstudio-huggingface
                  key: token
                  optional: true
          volumeMounts:
            - name: models
              mountPath: /models
          resources:
            requests:
              cpu: "4"
              memory: 8Gi
            limits:
              cpu: "8"
              memory: 16Gi
      volumes:
        - name: models
          persistentVolumeClaim:
            claimName: ${MODELS_PVC}
      # Add imagePullSecrets when your registry requires authentication.
EOF
    echo "Monitor: kubectl -n $NAMESPACE logs -f job/gsstudio-prefetch-models"
    echo "Wait: kubectl -n $NAMESPACE wait --for=condition=complete job/gsstudio-prefetch-models --timeout=24h"
    exit 0
fi
if [ "$#" -gt 0 ]; then
    echo "Usage: $0 [--k8s]" >&2
    exit 1
fi

echo "Hugging Face cache: $HF_HOME; Torch cache: $TORCH_HOME"
python3 - <<'PY'
import hashlib
import os
from pathlib import Path
from huggingface_hub import snapshot_download
from torch.hub import download_url_to_file

models = [
    ('tencent/HY-World-2.0', None),
    ('Qwen/Qwen3-VL-8B-Instruct', None),
    ('facebook/sam3', None),
    ('Ruicheng/moge-2-vitl-normal', None),
    ('naver-iv/zim-anything-vitl', ['zim_vit_l_2092/*']),
    ('IDEA-Research/grounding-dino-tiny', ['*.json', '*.txt', 'model.safetensors']),
    ('facebook/dinov2-base', None),
    # Both full and DMD checkpoints are required by the startup preflight.
    ('hanshanxue/WorldStereo', None),
    (
        'Wan-AI/Wan2.1-I2V-14B-480P-Diffusers',
        ['transformer/*', 'text_encoder/*', 'image_encoder/*',
         'image_processor/*', 'tokenizer/*', 'vae/*', 'scheduler/*'],
    ),
]
for repo_id, allow in models:
    print(f'Downloading {repo_id}...')
    snapshot_download(repo_id, allow_patterns=allow)
    print(f'Done: {repo_id}')

checkpoint_dir = Path(os.environ['TORCH_HOME']) / 'hub' / 'checkpoints'
checkpoint_dir.mkdir(parents=True, exist_ok=True)
checkpoint = checkpoint_dir / 'vgg16-397923af.pth'
expected = '397923af8e79cdbb6a7127f12361acd7a2f83e06b05044ddf496e83de57a5bf0'
def checkpoint_digest():
    digest = hashlib.sha256()
    with checkpoint.open('rb') as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()
if not checkpoint.is_file() or checkpoint_digest() != expected:
    print('Downloading VGG16 perceptual-loss checkpoint...')
    download_url_to_file(
        'https://download.pytorch.org/models/vgg16-397923af.pth',
        str(checkpoint), hash_prefix=expected, progress=True,
    )
print(f'VGG16 checkpoint verified: {checkpoint}')
print('Downloads complete. Follow your HY-World runtime setup for its local weight layout.')
print('The application startup preflight checks the required offline cache paths.')
PY
