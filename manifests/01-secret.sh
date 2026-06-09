#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# 01-secret.sh
#
# EN:    Creates the Secret with all required variables for RHDH
#        Run BEFORE applying the ConfigMaps
#
# PT-BR: Cria o Secret com as variáveis necessárias para o RHDH
#        Executar ANTES de aplicar os ConfigMaps
#
# NOTE / NOTA:
#   EN:    AZURE_SP_BASIC does NOT go into the Secret — it goes directly in template.yaml
#          The Authorization: Basic header is passed by the template in the get-sp-token step
#   PT-BR: AZURE_SP_BASIC NÃO vai para o Secret — vai diretamente no template.yaml
#          O header Authorization: Basic é passado pelo template no step get-sp-token
# ──────────────────────────────────────────────────────────────────────────────

NAMESPACE="devhub"

oc create secret generic developer-hub-env \
  --namespace=${NAMESPACE} \
  --from-literal=AZURE_CLIENT_ID="<AZURE_CLIENT_ID>" \
  --from-literal=AZURE_CLIENT_SECRET="<AZURE_CLIENT_SECRET>" \
  --from-literal=AZURE_TENANT_ID="<AZURE_TENANT_ID>" \
  --from-literal=BACKEND_SECRET="$(openssl rand -base64 24)"

echo "Secret created / Secret criado. Verify / Verificar:"
echo "  oc get secret developer-hub-env -n ${NAMESPACE}"
