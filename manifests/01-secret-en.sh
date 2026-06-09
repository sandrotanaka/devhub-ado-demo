#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# 01-secret.sh
# Creates the Secret with all required variables for RHDH
# Run BEFORE applying the ConfigMaps
#
# NOTE: AZURE_SP_BASIC does NOT go into the Secret — it goes directly in template.yaml
# The Authorization: Basic header is passed by the template in the get-sp-token step
# ──────────────────────────────────────────────────────────────────────────────

NAMESPACE="devhub"

oc create secret generic developer-hub-env \
  --namespace=${NAMESPACE} \
  --from-literal=AZURE_CLIENT_ID="<AZURE_CLIENT_ID>" \
  --from-literal=AZURE_CLIENT_SECRET="<AZURE_CLIENT_SECRET>" \
  --from-literal=AZURE_TENANT_ID="<AZURE_TENANT_ID>" \
  --from-literal=BACKEND_SECRET="$(openssl rand -base64 24)"

echo "Secret created. Verify:"
echo "  oc get secret developer-hub-env -n ${NAMESPACE}"
