# Installation Runbook / Runbook de Instalação

Red Hat Developer Hub v1.9.4 + Microsoft Entra ID + Azure DevOps OAuth2 (no PAT / sem PAT)

---

## Prerequisites / Pré-requisitos

- [ ] OpenShift cluster with `cluster-admin` access / Cluster OpenShift com acesso `cluster-admin`
- [ ] `oc` CLI configured and authenticated / `oc` CLI configurado e autenticado
- [ ] Entra ID tenant access (Global Administrator) / Acesso ao tenant Entra ID (Global Administrator)
- [ ] ADO organization access (Project Collection Administrator) / Acesso à org ADO (Project Collection Administrator)
- [ ] App Registration `devhub` already created in Entra ID / App Registration `devhub` já criado no Entra ID

---

## 1. Install the RHDH Operator / Instalar o RHDH Operator

```
Operators → OperatorHub → "Red Hat Developer Hub"
→ Install / Instalar → version / versão 1.9.4 → All namespaces
```

```bash
oc get csv -n openshift-operators | grep -i rhdh
# Expected / Esperado: rhdh-operator.v1.9.4  ...  Succeeded
```

---

## 2. Create Namespace / Criar Namespace

```bash
oc new-project devhub
```

---

## 3. Generate AZURE_SP_BASIC / Gerar AZURE_SP_BASIC

```bash
echo -n "<AZURE_CLIENT_ID>:<AZURE_CLIENT_SECRET>" | base64
```

> **EN:** Save the value — use it directly in `template.yaml` in the `Authorization: Basic <value>` header of the `get-sp-token` step. It does NOT need to go into the Secret or proxy app-config.
>
> **PT-BR:** Guarde o valor — use diretamente no `template.yaml` no header `Authorization: Basic` do step `get-sp-token`. Não precisa ir para o Secret nem para o proxy do app-config.

---

## 4. Create Secret / Criar Secret

```bash
oc create secret generic developer-hub-env \
  --namespace=devhub \
  --from-literal=AZURE_CLIENT_ID="<AZURE_CLIENT_ID>" \
  --from-literal=AZURE_CLIENT_SECRET="<AZURE_CLIENT_SECRET>" \
  --from-literal=AZURE_TENANT_ID="<AZURE_TENANT_ID>" \
  --from-literal=BACKEND_SECRET="$(openssl rand -base64 24)"
```

```bash
oc get secret developer-hub-env -n devhub
```

---

## 5. Get RHDH URL / Identificar URL do RHDH

```bash
oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}'
```

```
https://backstage-developer-hub-devhub.apps.<CLUSTER_DOMAIN>
```

---

## 6. Update Redirect URI in Entra ID / Atualizar Redirect URI no Entra ID

```
portal.azure.com → Microsoft Entra ID → App registrations → devhub
→ Authentication → Add a platform → Web
→ Redirect URI: https://backstage-developer-hub-devhub.apps.<CLUSTER_DOMAIN>/api/auth/microsoft/handler/frame
```

> ⚠️ **EN:** Mandatory — the URI must exactly match the new cluster URL.
> ⚠️ **PT-BR:** Obrigatório — a URI deve corresponder exatamente à URL do novo cluster.

---

## 7. Apply app-config / Aplicar app-config

**EN:** Edit `manifests/02-configmap-app-config.yaml` replacing:
**PT-BR:** Edite `manifests/02-configmap-app-config.yaml` substituindo:

- `<CLUSTER_DOMAIN>` — cluster domain / domínio do cluster (3 occurrences / ocorrências)
- `<AZURE_TENANT_ID>` — Tenant ID in the `/azure-token` proxy `target` field
- `<ADO_ORG>` and/e `<ADO_PROJECT>`

```bash
oc apply -f manifests/02-configmap-app-config.yaml -n devhub
```

---

## 8. Apply plugins / Aplicar plugins

```bash
oc apply -f manifests/03-configmap-dynamic-plugins.yaml -n devhub
```

---

## 9. Create RHDH instance / Criar instância RHDH

```bash
oc apply -f manifests/04-backstage-cr.yaml -n devhub
oc rollout status deployment/backstage-developer-hub -n devhub
```

---

## 10. Verify installed plugins / Verificar plugins instalados

```bash
oc logs -c install-dynamic-plugins \
  $(oc get pod -n devhub -l app=backstage -o jsonpath='{.items[0].metadata.name}') \
  -n devhub | grep -E "Adding|Overriding|Error" | tail -30
```

---

## 11. Verify login / Verificar login

```
https://backstage-developer-hub-devhub.apps.<CLUSTER_DOMAIN>
```

---

## 12. Verify template in catalog / Verificar template no catálogo

```
https://backstage-developer-hub-devhub.apps.<CLUSTER_DOMAIN>/create
```

**EN:** The template **Quarkus App — ADO OAuth (no PAT)** should appear.
**PT-BR:** Deve aparecer o template **Quarkus App — ADO OAuth (sem PAT)**.

---

## 13. End-to-End Test / Teste end-to-end

| Field / Campo | Value / Valor |
|---|---|
| Application name / Nome da aplicação | `test-new-cluster` |
| ADO Organization / Organização ADO | `<ADO_ORG>` |
| ADO Project / Projeto ADO | `<ADO_PROJECT>` |

| Step | Expected / Esperado |
|---|---|
| Get token / Obter token | `Finished step` |
| Create repo / Criar repo | `Finished step` |
| Clone / Clonar | `Cloning repo {...}` |
| Skeleton | `Template result written` |
| Push | `Pushing directory to remote` |
| Create pipeline / Criar pipeline | `Finished step` |
| Run pipeline / Executar pipeline | `InProgress` |
| Catalog / Catálogo | `Registering ...` |

---

## Troubleshooting

| Symptom / Sintoma | Cause / Causa | Solution / Solução |
|---|---|---|
| Login fails — redirect_uri mismatch | URI not updated / não atualizada | Redo step 6 / Refazer passo 6 |
| Template not shown / não aparece | Catalog didn't read location / Catalog não leu | Check catalog logs / Ver logs do catalog |
| 401 on ADO proxy | allowedHeaders missing / faltando | Check app-config proxy / Verificar proxy |
| Token with aud: 00000003 | azure-token proxy issue | Check Basic in template / Verificar template |
| Could not find HEAD | Wrong order / Ordem errada | Template already fixed / Template correto |
| pipelineId not of type string | Missing `\| string` filter | Template already fixed / Template correto |

---

## Useful Commands / Comandos úteis

```bash
# Check env vars / Verificar envs
oc exec -n devhub deployment/backstage-developer-hub -- env | grep AZURE

# Restart / Reiniciar
oc rollout restart deployment/backstage-developer-hub -n devhub

# Real-time logs / Logs em tempo real
oc logs -f deployment/backstage-developer-hub -n devhub
```

---

## References / Referências

| Document | URL |
|---|---|
| Azure DevOps CLI — Entra tokens | https://learn.microsoft.com/en-us/azure/devops/cli/entra-tokens?view=azure-devops&tabs=azure-cli |
| Azure DevOps REST API — Tokens | https://learn.microsoft.com/pt-br/rest/api/azure/devops/tokens/?view=azure-devops-rest-7.1&tabs=powershell |
| OAuth 2.0 — client_credentials | https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-client-creds-grant-flow |
| OAuth 2.0 — Authorization Code Flow | https://learn.microsoft.com/pt-br/entra/identity-platform/v2-oauth2-auth-code-flow |

---

## File Reference / Arquivos de referência

| File / Arquivo | EN Description / PT-BR Descrição |
|---|---|
| `manifests/01-secret.sh` | Create the Secret / Criar o Secret |
| `manifests/02-configmap-app-config.yaml` | app-config — **edit before applying / editar antes de aplicar** |
| `manifests/03-configmap-dynamic-plugins.yaml` | Dynamic plugins / Plugins dinâmicos |
| `manifests/04-backstage-cr.yaml` | Backstage CR (RHDH Operator) |
| `templates/quarkus-ado-oauth/template.yaml` | Scaffolder template — 8 steps |
| `docs/devhub-ado-demo-guia.md` | Full technical guide / Guia técnico completo (PT-BR) |
