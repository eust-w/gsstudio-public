#!/usr/bin/env bash
# Apply the reviewed examples to the user's current kubectl context.
set -euo pipefail

NAMESPACE="gsstudio"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
K8S_DIR="$(dirname "$SCRIPT_DIR")/k8s"
: "${GSSTUDIO_IMAGE:?Set GSSTUDIO_IMAGE to the application image you built and pushed}"
VARIANT="${DEPLOYMENT_VARIANT:-mock}"
case "$VARIANT" in
    mock) MANIFEST="$K8S_DIR/deployment.yaml" ;;
    gpu) MANIFEST="$K8S_DIR/deployment-gpu.yaml" ;;
    *) echo "ERROR: DEPLOYMENT_VARIANT must be mock or gpu" >&2; exit 1 ;;
esac
command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl not found" >&2; exit 1; }

echo "Deploying $VARIANT image $GSSTUDIO_IMAGE to context $(kubectl config current-context)"
echo "Review PVC capacity and storage class in deploy/k8s/pvc.yaml before running."
kubectl apply -f "$K8S_DIR/namespace.yaml"
if ! kubectl -n "$NAMESPACE" get secret gsstudio-basic-auth >/dev/null 2>&1; then
    echo "ERROR: Create secret gsstudio-basic-auth with username and password keys first." >&2
    exit 1
fi
kubectl apply -f "$K8S_DIR/pvc.yaml"
# Do not wait for PVC binding here: WaitForFirstConsumer storage binds only
# after the scheduler places a workload.
if [ "$VARIANT" = "gpu" ]; then
    echo "GPU mode requires populated model caches and a compatible runtime."
    echo "Prefetch first with: GSSTUDIO_IMAGE=<your-gpu-image> deploy/scripts/prefetch_models.sh --k8s"
fi
kubectl set image --local -f "$MANIFEST" "gsstudio=$GSSTUDIO_IMAGE" -o yaml | kubectl apply -f -
kubectl apply -f "$K8S_DIR/service.yaml"
# Ingress is opt-in; customize its hostname/TLS for your own installation.
if [ "${APPLY_INGRESS:-false}" = "true" ]; then
    kubectl apply -f "$K8S_DIR/ingress.yaml"
fi
kubectl -n "$NAMESPACE" rollout status deployment/gsstudio --timeout="${ROLLOUT_TIMEOUT:-300s}"
echo "Access locally: kubectl -n $NAMESPACE port-forward svc/gsstudio 8000:80"
