#!/bin/bash

# Usage:
# ./seal-secret.sh <secret-name> <namespace> <key=value> [<key=value> ...]
# Example:
# ./seal-secret.sh mysecret my-namespace DB_PASSWORD=hunter2 API_KEY=xyz123

set -e

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <secret-name> <namespace> <key=value> [<key=value> ...]"
  exit 1
fi

SECRET_NAME=$1
NAMESPACE=$2
shift 2

# Create temporary secret YAML
TMP_SECRET=$(mktemp)
kubectl create secret generic "$SECRET_NAME" --namespace "$NAMESPACE" \
  $(for kv in "$@"; do echo --from-literal="$kv"; done) \
  --dry-run=client -o yaml > "$TMP_SECRET"


export SEALED_SECRETS_CONTROLLER_NAMESPACE="sealed-secrets"
export SEALED_SECRETS_CONTROLLER_NAME="sealed-secrets"
export SEALED_SECRETS_SCOPE="cluster-wide"

# Output sealed secret
OUT_DIR="out"
mkdir -p "$OUT_DIR"
OUT_FILE="sealed-${SECRET_NAME}.yaml"
kubeseal --format yaml < "$TMP_SECRET" > "$OUT_DIR/$OUT_FILE"

echo "✅ Sealed secret written to: $OUT_DIR/$OUT_FILE"
rm "$TMP_SECRET"
