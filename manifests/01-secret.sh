#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# 01-secret.sh
# Cria o Secret com todas as variáveis necessárias para o RHDH
# Executar ANTES de aplicar os ConfigMaps
# ──────────────────────────────────────────────────────────────────────────────

NAMESPACE="devhub"

# Gerar AZURE_SP_BASIC: base64("clientId:clientSecret")
AZURE_SP_BASIC=$(echo -n "<AZURE_CLIENT_ID>:<AZURE_CLIENT_SECRET>" | base64)

oc create secret generic developer-hub-env \
  --namespace=${NAMESPACE} \
  --from-literal=AZURE_CLIENT_ID="<AZURE_CLIENT_ID>" \
  --from-literal=AZURE_CLIENT_SECRET="<AZURE_CLIENT_SECRET>" \
  --from-literal=AZURE_TENANT_ID="<AZURE_TENANT_ID>" \
  --from-literal=AZURE_SP_BASIC="${AZURE_SP_BASIC}" \
  --from-literal=BACKEND_SECRET="$(openssl rand -base64 24)"

echo "Secret criado. Verificar:"
echo "  oc get secret developer-hub-env -n ${NAMESPACE} -o jsonpath='{.data}' | tr ',' '\n'"
