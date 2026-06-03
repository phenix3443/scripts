#!/usr/bin/env bash

set -euo pipefail

if ! command -v kubectl >/dev/null 2>&1; then
    echo "kubectl is required" >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required" >&2
    exit 1
fi

INSTANCE_NAME="${1:-}"
if [[ -z "$INSTANCE_NAME" ]]; then
    echo "Usage: $0 <instance-name>" >&2
    exit 1
fi

NAMESPACE="${NAMESPACE:-openclaw}"
JOB_NAME="${INSTANCE_NAME}-pre-update-backup"
LONGHORN_LABEL_KEY="${LONGHORN_LABEL_KEY:-node.longhorn.io/create-default-disk}"
LONGHORN_LABEL_VALUE="${LONGHORN_LABEL_VALUE:-true}"
OPERATOR_NAMESPACE="${OPERATOR_NAMESPACE:-openclaw-operator-system}"
OPERATOR_DEPLOYMENT="${OPERATOR_DEPLOYMENT:-openclaw-operator}"

TMP_JOB_JSON="$(mktemp)"
trap 'rm -f "$TMP_JOB_JSON"' EXIT

kubectl get job -n "$NAMESPACE" "$JOB_NAME" -o json > "$TMP_JOB_JSON"

ORIGINAL_REPLICAS="$(
  kubectl get deployment -n "$OPERATOR_NAMESPACE" "$OPERATOR_DEPLOYMENT" \
    -o jsonpath='{.spec.replicas}'
)"

kubectl scale deployment -n "$OPERATOR_NAMESPACE" "$OPERATOR_DEPLOYMENT" --replicas=0
kubectl wait \
  --namespace "$OPERATOR_NAMESPACE" \
  --for=delete pod \
  --selector app.kubernetes.io/name=openclaw-operator \
  --timeout=120s

kubectl delete job -n "$NAMESPACE" "$JOB_NAME" --wait=true

jq \
  --arg key "$LONGHORN_LABEL_KEY" \
  --arg value "$LONGHORN_LABEL_VALUE" \
  '
  del(
    .metadata.uid,
    .metadata.resourceVersion,
    .metadata.creationTimestamp,
    .metadata.generation,
    .metadata.managedFields,
    .status
  )
  | .spec |= del(.selector, .manualSelector)
  | .spec.template.metadata.labels |= del(
      .["batch.kubernetes.io/controller-uid"],
      .["controller-uid"]
    )
  | .spec.template.spec.nodeSelector = {($key): $value}
  ' "$TMP_JOB_JSON" | kubectl create -f -

kubectl scale deployment -n "$OPERATOR_NAMESPACE" "$OPERATOR_DEPLOYMENT" --replicas="$ORIGINAL_REPLICAS"
kubectl rollout status deployment/"$OPERATOR_DEPLOYMENT" -n "$OPERATOR_NAMESPACE" --timeout=120s

kubectl get job -n "$NAMESPACE" "$JOB_NAME" -o wide
