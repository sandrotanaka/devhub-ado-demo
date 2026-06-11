# devhub-ado-demo
## Red Hat Developer Hub — Azure Entra ID + Azure DevOps
### PAT-free OAuth Authentication — Validated Guide / Autenticação OAuth sem PAT fixo — Guia Validado

**[EN](#english-version)** | **[PT-BR](#versão-em-português)**

---

# English Version


| Item | Value |
|---|---|
| RHDH Version | 1.9.4 / Backstage 1.45.3 |
| Operator | rhdh-operator.v1.9.4 |
| Namespace | devhub |
| Reference repository | devhub-ado-demo |
| Cluster | `<CLUSTER_DOMAIN>` |
| Validation date | 06/05/2026 |

> **🚫 SECURITY NOTICE — REVOKED CREDENTIALS**
>
> All sensitive values shown in this document (Client IDs, Client Secrets, Tenant IDs, OAuth tokens, cluster addresses and other credentials) were generated exclusively for demonstration purposes and are **REVOKED, EXPIRED or INVALIDATED**.
>
> Screenshots preserve the original values only to illustrate the configuration flow. None of these values grant access to any system.
>
> When replicating this procedure, replace all `<VARIABLE>` placeholders with the real values from your environment.

---


> **Where to host this repository:** for a working deployment, this repository must be hosted in **Azure DevOps** — not GitHub. The RHDH catalog uses the `integrations.azure` Service Principal credentials to read `all-templates.yaml` and the template files at runtime. Hosting on GitHub requires a separate GitHub integration and a different catalog location URL format. The GitHub repository serves as a public reference only. For your own deployment, clone it into your ADO organization and update the catalog location in `manifests/02-configmap-app-config.yaml` accordingly.

> **Onde hospedar este repositório:** para um ambiente funcional, este repositório deve estar hospedado no **Azure DevOps** — não no GitHub. O catálogo do RHDH usa as credenciais do Service Principal em `integrations.azure` para ler o `all-templates.yaml` em runtime. O repositório GitHub é apenas referência pública. Clone-o na sua organização ADO e atualize o catalog location em `manifests/02-configmap-app-config.yaml`.

## 1. Overview

This document describes the complete configuration process for Red Hat Developer Hub (RHDH) integrated with Microsoft Entra ID for authentication and Azure DevOps for scaffolder operations — using the OAuth2 client_credentials token from the Service Principal instead of a fixed PAT.

> ✅ All Azure DevOps operations are performed using the Service Principal identity. No shared credentials or broadly-scoped PATs are stored on the platform.

### Authentication Flow

1. User signs in to RHDH with their Microsoft account (Entra ID)
2. RHDH stores the user's OAuth session
3. When executing a template, the scaffolder calls `POST /proxy/azure-token/token` with `grant_type=client_credentials`
4. Entra ID returns a token with `aud: 499b84ac-...` (Azure DevOps)
5. The template uses that token in the proxy `/proxy/azure-devops` to operate in ADO
6. All operations (create repo, pipeline, etc.) are performed using the Service Principal identity

---

## 2. Prerequisites

| Item | Requirement |
|---|---|
| OpenShift | OCP cluster with RHDH Operator v1.9.4 installed |
| Azure | Account with Global Administrator access in the Entra ID tenant |
| Azure DevOps | Existing organization with admin access |
| oc CLI | Configured with cluster-admin access |

---

## 3. Microsoft Entra ID Configuration

### 3.1 Verify the correct tenant

Access the Azure portal (`portal.azure.com`) and navigate to **Microsoft Entra ID**. Confirm you are in the correct tenant by checking the name in the upper right corner. Note the Tenant ID and Primary domain shown in the Overview.

| Variable | Where to find |
|---|---|
| `AZURE_TENANT_ID` | "Directory (tenant) ID" field in Overview |
| Primary domain | "Primary domain" field — format `<tenant>.onmicrosoft.com` |

### 3.2 Create the App Registration

Navigate to: **Microsoft Entra ID → App registrations → New registration**

| Field | Value |
|---|---|
| Name | `devhub` (or name of your choice) |
| Supported account types | Single tenant only — Default Directory |
| Redirect URI (Web) | `https://backstage-developer-hub-<NAMESPACE>.apps.<CLUSTER_DOMAIN>/api/auth/microsoft/handler/frame` |

> ⚠️ The Redirect URI must **exactly** match the RHDH URL followed by `/api/auth/microsoft/handler/frame`. Any difference causes an authentication error.

### 3.3 Collect Client ID and Tenant ID

After creating the App Registration, the **Overview** screen displays the required values:

| Variable | Portal field |
|---|---|
| `AZURE_CLIENT_ID` | Application (client) ID |
| `AZURE_TENANT_ID` | Directory (tenant) ID |

### 3.4 Create Client Secret

Navigate to: **Manage → Certificates & secrets → Client secrets → New client secret**

| Field | Value |
|---|---|
| Description | `rhdh-secret` |
| Expires | 24 months (recommended) |

> ⚠️ The secret value is only visible **once**, immediately after creation. Copy and store it securely before leaving the page.

| Variable | How to obtain |
|---|---|
| `AZURE_CLIENT_SECRET` | "Value" field — visible only at creation |

### 3.5 Add Azure DevOps permission

Navigate to: **Manage → API permissions → Add a permission → APIs my organization uses → Azure DevOps → Delegated → user_impersonation**

Then click **Grant admin consent for `<your tenant>`** and confirm with **Yes**.

> ✅ Admin consent is mandatory. Without it, Entra ID will not issue ADO tokens for users.

Required permissions after grant:

| Permission | Type | Status |
|---|---|---|
| Azure DevOps — `user_impersonation` | Delegated | ✅ Granted |
| Microsoft Graph — `email` | Delegated | ✅ Granted |
| Microsoft Graph — `offline_access` | Delegated | ✅ Granted |
| Microsoft Graph — `openid` | Delegated | ✅ Granted |
| Microsoft Graph — `profile` | Delegated | ✅ Granted |
| Microsoft Graph — `User.Read` | Delegated | ✅ Granted |

---

## 4. Azure DevOps Configuration

### 4.1 Connect organization to Entra ID

For OAuth to work, the ADO organization must be connected to the same tenant as the App Registration.

Navigate to:
```
https://dev.azure.com/<YOUR_ORG>/_settings/organizationAad
```

Click **Connect directory** and select the correct tenant.

> ⚠️ Connecting to Entra ID requires using a **native tenant account** (not MSA/personal account). If the ADO admin account is `@gmail.com` or similar, create a native user in the tenant before connecting (see 4.2).

### 4.2 Create native tenant user (if needed)

Navigate to: **Microsoft Entra ID → Users → New user → Create new user**

| Field | Value |
|---|---|
| User principal name | `rhdhadmin@<TENANT_DOMAIN>.onmicrosoft.com` |
| Role | Global Administrator |
| Password | Set on first login |

### 4.3 Add Service Principal as ADO user

For the Service Principal to operate in ADO, it must be added as a user in the organization:

1. Navigate to: `https://dev.azure.com/<ORG>/_settings/users`
2. Click **Add users**
3. Search by the App Registration **name or Client ID**
4. Access level: **Basic**
5. Add to required projects with **Project Administrators** role
6. Click **Add**

> ✅ The Service Principal appears in the user list with its Client ID as identifier.

---

## 5. Installing RHDH on OpenShift

### 5.1 Verify operator installed

```bash
oc get csv -n openshift-operators | grep -i rhdh
# Expected: rhdh-operator.v1.9.4  ...  Succeeded
```

### 5.2 Create namespace

```bash
oc new-project devhub
```

### 5.3 Create Secret with credentials

```bash
oc create secret generic developer-hub-env \
  --namespace=devhub \
  --from-literal=AZURE_CLIENT_ID="<AZURE_CLIENT_ID>" \
  --from-literal=AZURE_CLIENT_SECRET="<AZURE_CLIENT_SECRET>" \
  --from-literal=AZURE_TENANT_ID="<AZURE_TENANT_ID>" \
  --from-literal=BACKEND_SECRET="$(openssl rand -base64 24)"
```

### 5.4 app-config.yaml — critical points

> ⚠️ `${VAR}` is NOT expanded in `proxy.endpoints.target` — Tenant ID must be hardcoded.
> ⚠️ `Authorization: Basic` must be set in the **template**, not in the proxy. The `http:backstage:request` plugin sends the header before the request reaches the proxy — any proxy-level `Authorization` would be ignored.
> ⚠️ `allowedHeaders` is mandatory on the proxy endpoint. Without it the Bearer token is silently dropped and ADO returns 302.

```yaml
auth:
  environment: production
  providers:
    microsoft:
      production:
        clientId: ${AZURE_CLIENT_ID}
        clientSecret: ${AZURE_CLIENT_SECRET}
        tenantId: ${AZURE_TENANT_ID}
        additionalScopes:
          - https://app.vssps.visualstudio.com/user_impersonation
        signIn:
          resolvers:
            - resolver: emailMatchingUserEntityAnnotation
              dangerouslyAllowSignInWithoutUserInCatalog: true
signInPage: microsoft

proxy:
  endpoints:
    /azure-devops:
      target: https://dev.azure.com
      changeOrigin: true
      allowedMethods: [GET, POST, DELETE, PATCH, PUT]
      credentials: dangerously-allow-unauthenticated
      allowedHeaders:
        - Authorization        # REQUIRED — without this the token is dropped
        - Content-Type
    /azure-token:
      # Tenant ID hardcoded — ${AZURE_TENANT_ID} is NOT expanded in target
      target: https://login.microsoftonline.com/<TENANT_ID>/oauth2/v2.0
      changeOrigin: true
      allowedMethods: [POST]
      credentials: dangerously-allow-unauthenticated
      # Do NOT include Authorization here — the Basic header comes from the template
      allowedHeaders:
        - Authorization
        - Content-Type
```

### 5.5 Apply manifests

```bash
oc apply -f 02-configmap-app-config.yaml -n devhub
oc apply -f 03-configmap-dynamic-plugins.yaml -n devhub
oc apply -f 04-backstage-cr.yaml -n devhub
oc rollout status deployment/backstage-developer-hub -n devhub
```

---

## 6. Obtaining the Azure DevOps OAuth Token

### 6.1 Problem — audience conflict

The Backstage `microsoft` provider uses Microsoft Graph as the principal resource. The `additionalScopes` with `user_impersonation` belongs to a different resource (Azure DevOps). MSAL does not combine scopes from different resources in a single token — the ADO scope is silently ignored in the main session.

| Token | Audience | Result |
|---|---|---|
| Graph token | `aud: 00000003-...` (Microsoft Graph) | ❌ Does NOT work for ADO — returns 302 |
| ADO token | `aud: 499b84ac-...` (Azure DevOps) | ✅ Required for all ADO operations |

### 6.2 Solution — OAuth2 client_credentials via proxy

The Service Principal obtains the ADO token by calling the Entra ID OAuth2 endpoint directly with `grant_type=client_credentials`:

```
POST https://login.microsoftonline.com/<TENANT_ID>/oauth2/v2.0/token
Authorization: Basic <base64(client_id:client_secret)>
Content-Type: application/x-www-form-urlencoded
Body: grant_type=client_credentials&scope=499b84ac-1321-427f-aa17-267ca6975798/.default
```

Returns `access_token` with `aud: 499b84ac-...` ✅

### 6.3 Validated JWT token fields

| Field | Value / Meaning |
|---|---|
| `aud` | `499b84ac-1321-427f-aa17-267ca6975798` — Azure DevOps ✅ |
| `appid` | Client ID of the Service Principal |
| `idtyp` | `app` — application token (no user impersonation) |
| `tid` | Entra ID Tenant ID |
| `expires_in` | `3599` seconds (~1 hour) |
| `token_type` | `Bearer` |

---

## 7. Scaffolder Template — get-sp-token step

### Why Authorization: Basic only in the template, not the proxy

The `http:backstage:request` plugin (v5.5.1) automatically injects the Backstage token in the `Authorization` header of every request — **unless the template already passes an explicit `Authorization`**. The source code confirms:

```javascript
if (token && !authToken) {
  ctx.logger.info(`Token is defined. Setting authorization header.`);
  httpOptions.headers.authorization = `Bearer ${token}`;
}
```

So: if the template already defines `Authorization`, the plugin respects it and does not overwrite.

The Basic value must be in the **template only** — not in the proxy. Any `Authorization` configured in the proxy would be overwritten by the plugin before the request is forwarded.

```yaml
- id: get-sp-token
  name: Get ADO OAuth Token (Service Principal)
  action: http:backstage:request
  input:
    method: POST
    path: /proxy/azure-token/token
    headers:
      Content-Type: application/x-www-form-urlencoded
      # Basic = base64("clientId:clientSecret") — hardcoded because proxy headers
      # are overwritten by the plugin before reaching the proxy
      Authorization: "Basic <base64(clientId:clientSecret)>"
    body: "grant_type=client_credentials&scope=499b84ac-1321-427f-aa17-267ca6975798%2F.default"
```

---

## 8. Template — Validated 8-Step End-to-End Flow

| Step | Action | Status |
|---|---|---|
| 1. Get ADO OAuth token | `http:backstage:request` → `/proxy/azure-token/token` | ✅ |
| 2. Create repository | `http:backstage:request` → ADO REST API | ✅ |
| 3. Clone repository | `azure:repository:clone` | ✅ |
| 4. Generate skeleton | `fetch:template` with `targetPath: ./repo` | ✅ |
| 5. Push skeleton | `azure:repository:push` with `sourcePath: ./repo` | ✅ |
| 6. Create pipeline | `http:backstage:request` → ADO REST API | ✅ |
| 7. Run pipeline | `azure:pipeline:run` | ✅ |
| 8. Register in catalog | `catalog:register` | ✅ |

### clone → fetch → push pattern

The `Could not find HEAD` error on newly-created repos is solved with:

```yaml
# 1. Clone empty repo — initializes local git correctly
- id: clone-repo
  action: azure:repository:clone
  input:
    remoteUrl: ${{ steps['create-repo'].output.body.remoteUrl }}
    targetPath: ./repo
    token: ${{ steps['get-sp-token'].output.body.access_token }}

# 2. Generate skeleton IN THE SAME cloned directory
- id: fetch-skeleton
  action: fetch:template
  input:
    url: ./skeleton
    targetPath: ./repo

# 3. Push using sourcePath pointing to the cloned directory
- id: push-content
  action: azure:repository:push
  input:
    remoteUrl: ${{ steps['create-repo'].output.body.remoteUrl }}
    branch: main
    sourcePath: ./repo
    token: ${{ steps['get-sp-token'].output.body.access_token }}
```

### pipelineId must be a string

The `create-pipeline` step returns a number. Use the Nunjucks `| string` filter:

```yaml
pipelineId: "${{ steps['create-pipeline'].output.body.id | string }}"
```

---

## 9. Troubleshooting

| Error / Symptom | Cause | Solution |
|---|---|---|
| `AADSTS900023: $azure_tenant_id not valid` | Variable not expanded in app-config | Use `${VARIABLE}` with braces |
| Proxy ADO returns 302 | `allowedHeaders` missing on proxy endpoint | Add `allowedHeaders: [Authorization, Content-Type]` |
| Token with `aud: 00000003` (Graph) | ADO scope not correctly requested | Use `/proxy/azure-token/token` with `client_credentials` |
| `Could not find HEAD` on push | Pushing to empty repo without prior clone | Use clone → fetch:template → push pattern |
| `pipelineId is not of type string` | Missing `| string` filter | Use `"${{ steps['create-pipeline'].output.body.id | string }}"` |
| `instance is not allowed to have the additional property` | Wrong parameters on `azure:repository:push` | Use only: `remoteUrl`, `branch`, `sourcePath`, `gitCommitMessage`, `token` |
| Pod stuck `Init:0/1` | OCI plugin not found or incompatible version | `oc logs <pod> -c install-dynamic-plugins` |

---

## 10. Origin of GUID `499b84ac-1321-427f-aa17-267ca6975798`

### What this value is

This GUID is the **official Application ID of Azure DevOps**, registered by Microsoft in the global Entra ID. It is not a user-generated value — it is fixed, public, and **identical in all tenants worldwide**.

### How to verify

**Via Azure portal:**
1. Navigate to **Microsoft Entra ID → Enterprise applications**
2. Remove the filter and search for `Azure DevOps`
3. The Application ID shown will be exactly `499b84ac-1321-427f-aa17-267ca6975798`

**Via Microsoft Graph API:**
```
GET https://graph.microsoft.com/v1.0/servicePrincipals?$filter=displayName eq 'Azure DevOps'
```

### Why use GUID instead of URL

| Form | Scope |
|---|---|
| URL | `https://app.vssps.visualstudio.com/user_impersonation` |
| GUID + `.default` | `499b84ac-1321-427f-aa17-267ca6975798/.default` |

The `/.default` form requests **all delegated scopes already consented** for that resource — in this case, the `user_impersonation` granted in the App Registration.

### Discovery path

| Attempt | Result |
|---|---|
| Token without ADO scope | `aud: 00000003-...` (Graph) — ADO returned 302 |
| `additionalScopes` with `user_impersonation` in app-config | Ignored — Backstage doesn't combine scopes from different resources |
| `/refresh` without parameters | 400 — `Must specify 'env' query` |
| `/refresh` without `X-Requested-With` header | 401 — `Invalid X-Requested-With header` |
| `client_credentials` with scope `499b84ac-.../.default` | ✅ 200 — `aud: 499b84ac-...` |

---

## 11. Service Principal via OAuth2 — Key Findings

### Proxy limitations discovered

| Limitation | Impact | Solution |
|---|---|---|
| `${VAR}` not expanded in proxy `target` | `target: .../=${AZURE_TENANT_ID}/...` stays literal | Hardcode Tenant ID in target (public GUID) |
| `${VAR}` not expanded in `proxy.headers` | `Authorization: Basic ${AZURE_SP_BASIC}` doesn't work | Use Secret as env var — but even then proxy doesn't expand |
| `Authorization` from proxy is overwritten | Plugin injects Bearer token before proxy | Pass `Authorization: Basic` directly in template |
| `http:backstage:request` ignores `params` | `params: {env: production}` ignored | Include query params inline in path |

### azure:repository:push schema (bs_1.45.3__0.18.0)

| Parameter | Type | Description |
|---|---|---|
| `remoteUrl` | string | **Required** — Git URL of the repository |
| `branch` | string | Branch to checkout |
| `sourcePath` | string | Subdirectory of working directory |
| `gitCommitMessage` | string | Commit message |
| `gitAuthorName` | string | Author name |
| `gitAuthorEmail` | string | Author email |
| `token` | string | Authentication token |

> ⚠️ Parameters `organization`, `project`, `repositoryName`, `defaultBranch` do **NOT exist** in this version — they cause the error `instance is not allowed to have the additional property`.

---

## 12. Authorization Basic in the Template — Rationale

### Why only in the template and not in the proxy

1. The template calls `/proxy/azure-token/token` with `Authorization: Basic <value>` in the header
2. The `http:backstage:request` plugin checks: `if (token && !authToken)` — since `authToken` is already set, it does not overwrite
3. The request reaches the proxy **already with the correct header**
4. Any `Authorization` configured in the proxy would be ignored — what arrived takes precedence

### Security comparison

| Approach | Where credential is stored | Who can see |
|---|---|---|
| Basic hardcoded in template | `template.yaml` in private ADO repo | Users with access to the ADO project |
| Basic in app-config ConfigMap | ConfigMap in OpenShift namespace | Namespace admins |
| Basic in OpenShift Secret | Secret in OpenShift namespace | Namespace admins (encrypted at rest) |

> ⚠️ ConfigMap is **less secure** than Secret — not encrypted at rest. Template in a private repo has equivalent security to ConfigMap.

---

## 13. Final Validated Template — 8 Steps

### Complete validated flow

| Step | Action | Status |
|---|---|---|
| 1. Get ADO OAuth token | `http:backstage:request` → `/proxy/azure-token/token` | ✅ |
| 2. Create repository | `http:backstage:request` → ADO REST API | ✅ |
| 3. Clone repository | `azure:repository:clone` | ✅ |
| 4. Generate skeleton | `fetch:template` with `targetPath: ./repo` | ✅ |
| 5. Push skeleton | `azure:repository:push` with `sourcePath: ./repo` | ✅ |
| 6. Create pipeline | `http:backstage:request` → ADO REST API | ✅ |
| 7. Run pipeline | `azure:pipeline:run` — `InProgress` | ✅ |
| 8. Register in catalog | `catalog:register` | ✅ |

---

## 14. References

### Microsoft — Authentication and Azure DevOps Tokens

| Document | URL |
|---|---|
| Azure DevOps CLI — Entra tokens | https://learn.microsoft.com/en-us/azure/devops/cli/entra-tokens?view=azure-devops&tabs=azure-cli |
| Azure DevOps REST API — Tokens | https://learn.microsoft.com/pt-br/rest/api/azure/devops/tokens/?view=azure-devops-rest-7.1&tabs=powershell |
| OAuth 2.0 — client_credentials | https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-client-creds-grant-flow |
| OAuth 2.0 — Authorization Code Flow | https://learn.microsoft.com/pt-br/entra/identity-platform/v2-oauth2-auth-code-flow |
| Azure DevOps — Resource ID (audience) | https://learn.microsoft.com/en-us/azure/devops/integrate/get-started/authentication/oauth |

### Red Hat Developer Hub

| Document | URL |
|---|---|
| RHDH — Scaffolder Built-in Actions | https://backstage.io/docs/features/software-templates/builtin-actions/ |
| RHDH — Dynamic Plugins | https://docs.redhat.com/en/documentation/red_hat_developer_hub/1.4/html/configuring_plugins_in_red_hat_developer_hub/rhdh-installing-dynamic-plugins |
| RHDH — Proxy Configuration | https://backstage.io/docs/plugins/proxying |
| Roadie HTTP Request Action | https://github.com/RoadieHQ/roadie-backstage-plugins/tree/main/plugins/scaffolder-actions/scaffolder-backend-module-http-request |

### Azure DevOps Community Plugins (RHDH)

| Plugin | Validated version | URL |
|---|---|---|
| backstage-community-plugin-azure-devops | bs_1.45.3__0.23.0 | https://github.com/backstage/community-plugins/tree/main/workspaces/azure-devops |
| backstage-community-plugin-scaffolder-backend-module-azure-devops | bs_1.45.3__0.18.0 | https://github.com/backstage/community-plugins/tree/main/workspaces/azure-devops |

### Azure DevOps Fixed GUIDs (valid in any tenant)

| Item | Value |
|---|---|
| Resource ID / Audience | `499b84ac-1321-427f-aa17-267ca6975798` |
| Scope client_credentials | `499b84ac-1321-427f-aa17-267ca6975798/.default` |
| Delegated scope | `https://app.vssps.visualstudio.com/user_impersonation` |


---

# Versão em Português


| Item | Valor |
|---|---|
| Versão RHDH | 1.9.4 / Backstage 1.45.3 |
| Operador | rhdh-operator.v1.9.4 |
| Namespace | devhub |
| Repositório de referência | devhub-ado-demo |
| Cluster | `<CLUSTER_DOMAIN>` |
| Data de validação | 05/06/2026 |

> **🚫 AVISO DE SEGURANÇA — CREDENCIAIS REVOGADAS**
>
> Todos os valores sensíveis exibidos neste documento (Client IDs, Client Secrets, Tenant IDs, tokens OAuth, endereços de cluster e demais credenciais) foram gerados exclusivamente para fins de demonstração e estão **REVOGADOS, EXPIRADOS ou INVALIDADOS**.
>
> As screenshots incluídas preservam os valores originais apenas para ilustração do fluxo de configuração. Nenhum desses valores confere acesso a qualquer sistema.
>
> Ao replicar este procedimento, substitua todos os placeholders do tipo `<VARIAVEL>` pelos valores reais do seu ambiente.

---

## 1. Visão Geral

Este documento descreve o processo completo de configuração do Red Hat Developer Hub (RHDH) integrado ao Microsoft Entra ID para autenticação e ao Azure DevOps para operações de scaffolder — usando o token OAuth do usuário logado em vez de PAT fixo.

> ✅ Cada operação no Azure DevOps é rastreável pelo usuário real que iniciou o template. Não há credenciais compartilhadas ou PATs com acesso amplo armazenados na plataforma.

### Fluxo de autenticação

1. Usuário faz login no RHDH com sua conta Microsoft (Entra ID)
2. O RHDH armazena a sessão OAuth do usuário
3. Ao executar um template, o scaffolder chama `/api/auth/microsoft/refresh` com o scope do Azure DevOps
4. O Entra ID retorna um token com `aud: 499b84ac-...` (Azure DevOps)
5. O template usa esse token no proxy `/api/proxy/azure-devops` para operar no ADO
6. Todas as operações (criar repo, pipeline, etc.) são feitas em nome do usuário real

---

## 2. Pré-requisitos

| Item | Requisito |
|---|---|
| OpenShift | Cluster OCP com RHDH Operator v1.9.4 instalado |
| Azure | Conta com acesso Global Administrator no tenant Entra ID |
| Azure DevOps | Organização existente com acesso admin |
| oc CLI | Configurado com acesso cluster-admin |

---

## 3. Configuração do Microsoft Entra ID

### 3.1 Verificar o tenant correto

Acesse o portal Azure (`portal.azure.com`) e navegue até **Microsoft Entra ID**. Confirme que está no tenant correto verificando o nome no canto superior direito. Anote o Tenant ID e o Primary domain exibidos no Overview.

| Variável | Onde obter |
|---|---|
| `AZURE_TENANT_ID` | Campo "Directory (tenant) ID" no Overview |
| Primary domain | Campo "Primary domain" — formato `<tenant>.onmicrosoft.com` |

### 3.2 Criar o App Registration

Acesse: **Microsoft Entra ID → App registrations → New registration**

| Campo | Valor |
|---|---|
| Name | `devhub` (ou nome de sua preferência) |
| Supported account types | Single tenant only — Default Directory |
| Redirect URI (Web) | `https://backstage-developer-hub-<NAMESPACE>.apps.<CLUSTER_DOMAIN>/api/auth/microsoft/handler/frame` |

> ⚠️ A Redirect URI deve corresponder **exatamente** à URL do RHDH seguida de `/api/auth/microsoft/handler/frame`. Qualquer diferença causa erro de autenticação.

### 3.3 Coletar Client ID e Tenant ID

Após criar o App Registration, a tela **Overview** exibe os valores necessários:

| Variável | Campo no portal |
|---|---|
| `AZURE_CLIENT_ID` | Application (client) ID |
| `AZURE_TENANT_ID` | Directory (tenant) ID |

### 3.4 Criar Client Secret

Acesse: **Manage → Certificates & secrets → Client secrets → New client secret**

| Campo | Valor |
|---|---|
| Description | `rhdh-secret` |
| Expires | 24 months (recomendado) |

> ⚠️ O valor do secret só é visível **uma vez**, imediatamente após a criação. Copie e armazene com segurança antes de sair da página.

| Variável | Como obter |
|---|---|
| `AZURE_CLIENT_SECRET` | Campo "Value" — visível apenas na criação |

### 3.5 Adicionar permissão Azure DevOps

Acesse: **Manage → API permissions → Add a permission → APIs my organization uses → Azure DevOps → Delegated → user_impersonation**

Em seguida clique em **Grant admin consent for `<seu tenant>`** e confirme com **Yes**.

> ✅ O Grant admin consent é obrigatório. Sem ele, o Entra ID não emite tokens ADO para os usuários.

Permissões necessárias após o Grant:

| Permissão | Tipo | Status |
|---|---|---|
| Azure DevOps — `user_impersonation` | Delegated | ✅ Granted |
| Microsoft Graph — `email` | Delegated | ✅ Granted |
| Microsoft Graph — `offline_access` | Delegated | ✅ Granted |
| Microsoft Graph — `openid` | Delegated | ✅ Granted |
| Microsoft Graph — `profile` | Delegated | ✅ Granted |
| Microsoft Graph — `User.Read` | Delegated | ✅ Granted |

---

## 4. Configuração do Azure DevOps

### 4.1 Conectar organização ao Entra ID

Para que o OAuth funcione, a organização ADO deve estar conectada ao mesmo tenant do App Registration.

Acesse:
```
https://dev.azure.com/<SUA_ORG>/_settings/organizationAad
```

Clique em **Connect directory** e selecione o tenant correto.

> ⚠️ Para conectar ao Entra ID é necessário usar uma conta **nativa do tenant** (não MSA/conta pessoal). Se a conta de admin do ADO é `@gmail.com` ou similar, crie um usuário nativo no tenant antes de conectar (ver 4.2).

### 4.2 Criar usuário nativo no tenant (se necessário)

Se a conta de admin do ADO é MSA, crie um usuário nativo no Entra ID:

Acesse: **Microsoft Entra ID → Users → New user → Create new user**

| Campo | Valor |
|---|---|
| User principal name | `rhdhadmin@<TENANT_DOMAIN>.onmicrosoft.com` |
| Role | Global Administrator |
| Senha | Definida no primeiro login |

### 4.3 Verificar conexão e projetos

Após conectar, acesse `https://dev.azure.com/<SUA_ORG>` e confirme que os projetos estão visíveis com a conta Entra ID.

### 4.4 Criar repositório devhub-ado-demo

Crie o repositório que armazenará os templates. Via console do browser no RHDH (após login):

```javascript
const r = await fetch(
  '/api/auth/microsoft/refresh?env=production&scope=499b84ac-1321-427f-aa17-267ca6975798%2F.default',
  { credentials: 'include', headers: { 'X-Requested-With': 'XMLHttpRequest' } }
);
const d = await r.json();
const token = d.providerInfo.accessToken;

const r2 = await fetch(
  '/api/proxy/azure-devops/<ORG>/<PROJECT>/_apis/git/repositories?api-version=7.1',
  {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ name: 'devhub-ado-demo' })
  }
);
const repo = await r2.json();
console.log('status:', r2.status);   // Esperado: 201
console.log('remoteUrl:', repo.remoteUrl);
```

---

## 5. Instalação do RHDH no OpenShift

### 5.1 Verificar operador instalado

```bash
oc get csv -n openshift-operators | grep -i rhdh
# Esperado: rhdh-operator.v1.9.4  ...  Succeeded
```

### 5.2 Criar namespace

```bash
oc new-project devhub
```

### 5.3 Criar Secret com credenciais

> ℹ️ Execute no terminal — o `BACKEND_SECRET` é gerado localmente e nunca fica em arquivo.

```bash
oc create secret generic developer-hub-env \
  --namespace=devhub \
  --from-literal=AZURE_CLIENT_ID="<AZURE_CLIENT_ID>" \
  --from-literal=AZURE_CLIENT_SECRET="<AZURE_CLIENT_SECRET>" \
  --from-literal=AZURE_TENANT_ID="<AZURE_TENANT_ID>" \
  --from-literal=BACKEND_SECRET="$(openssl rand -base64 24)"
```

### 5.4 app-config.yaml — pontos críticos

> ⚠️ Usar `$VARIAVEL` (sem chaves) faz o Backstage **não expandir** a variável — a string literal é enviada ao Entra ID causando `AADSTS900023: tenant identifier is not valid`. Use sempre `${VARIAVEL}` com chaves.

> ⚠️ `allowedHeaders` é obrigatório no endpoint do proxy. Sem ele o Bearer token do usuário é descartado silenciosamente e o ADO retorna 302.

```yaml
auth:
  environment: production
  providers:
    microsoft:
      production:
        clientId: ${AZURE_CLIENT_ID}
        clientSecret: ${AZURE_CLIENT_SECRET}
        tenantId: ${AZURE_TENANT_ID}
        additionalScopes:
          - https://app.vssps.visualstudio.com/user_impersonation
        signIn:
          resolvers:
            - resolver: emailMatchingUserEntityAnnotation
              dangerouslyAllowSignInWithoutUserInCatalog: true
signInPage: microsoft

proxy:
  endpoints:
    /azure-devops:
      target: https://dev.azure.com
      changeOrigin: true
      allowedMethods: [GET, POST, DELETE, PATCH, PUT]
      credentials: dangerously-allow-unauthenticated
      allowedHeaders:
        - Authorization        # OBRIGATÓRIO — sem isso o token é descartado
        - Content-Type
```

### 5.5 Aplicar manifests

```bash
oc apply -f 02-configmap-app-config.yaml -n devhub
oc apply -f 03-configmap-dynamic-plugins.yaml -n devhub
oc apply -f 04-backstage-cr.yaml -n devhub

# Acompanhar pods
oc get pods -n devhub -w
# Aguardar Running:
#   backstage-developer-hub-<hash>
#   backstage-psql-developer-hub-0
```

### 5.6 Atualizar ConfigMap após edição

```bash
oc apply -f 02-configmap-app-config.yaml -n devhub
oc rollout restart deployment/backstage-developer-hub -n devhub
oc rollout status deployment/backstage-developer-hub -n devhub
```

---

## 6. Obtenção do Token OAuth do Azure DevOps

### 6.1 Problema — conflito de audiences

O provider `microsoft` do Backstage usa o Microsoft Graph como resource principal. O `additionalScopes` com `user_impersonation` pertence a um resource diferente (Azure DevOps). O MSAL não combina scopes de resources diferentes em um único token — o scope ADO é silenciosamente ignorado na sessão principal.

| Token | Audience | Resultado |
|---|---|---|
| Graph token | `aud: 00000003-...` (Microsoft Graph) | ❌ NÃO serve para ADO — retorna 302 |
| ADO token | `aud: 499b84ac-...` (Azure DevOps) | ✅ Necessário para todas as operações ADO |

### 6.2 Solução — /refresh com scope explícito do Resource ID ADO

```
GET /api/auth/microsoft/refresh
    ?env=production
    &scope=499b84ac-1321-427f-aa17-267ca6975798/.default

Headers obrigatórios:
  X-Requested-With: XMLHttpRequest
```

> ℹ️ O GUID `499b84ac-1321-427f-aa17-267ca6975798` é o Resource ID **fixo e público** do Azure DevOps — o mesmo em todos os tenants.

> ✅ O endpoint retorna um token separado com `aud: 499b84ac-...` sem afetar a sessão principal do usuário (Graph).

### 6.3 Validação no console do browser

Abra o console (Cmd+Option+J) na tela principal do RHDH após login:

```javascript
// Obter token ADO
const r = await fetch(
  '/api/auth/microsoft/refresh?env=production&scope=499b84ac-1321-427f-aa17-267ca6975798%2F.default',
  { credentials: 'include', headers: { 'X-Requested-With': 'XMLHttpRequest' } }
);
const d = await r.json();

// Decodificar e verificar audience
const payload = JSON.parse(atob(d.providerInfo.accessToken.split('.')[1]));
console.log('aud:', payload.aud);   // Esperado: 499b84ac-...
console.log('scp:', payload.scp);   // Esperado: user_impersonation
console.log('name:', payload.name); // Nome do usuário logado

// Testar proxy com token do usuário
const token = d.providerInfo.accessToken;
const r2 = await fetch(
  '/api/proxy/azure-devops/<ORG>/_apis/projects?api-version=7.1',
  { headers: { Authorization: `Bearer ${token}` } }
);
console.log('status:', r2.status); // Esperado: 200
const projects = await r2.json();
console.log('projetos:', projects.value?.map(p => p.name));
```

### 6.4 Uso no template scaffolder

```yaml
steps:

  # Passo 1: Obter token ADO com audience correto
  - id: get-ado-token
    name: Obter token OAuth ADO
    action: http:backstage:request
    input:
      method: GET
      path: /api/auth/microsoft/refresh
      params:
        env: production
        scope: "499b84ac-1321-427f-aa17-267ca6975798/.default"
      headers:
        X-Requested-With: XMLHttpRequest

  # Passo 2: Criar repositório no ADO com token do usuário
  - id: create-repo
    name: Criar repositório no Azure DevOps
    action: http:backstage:request
    input:
      method: POST
      path: /api/proxy/azure-devops/<ORG>/<PROJECT>/_apis/git/repositories?api-version=7.1
      headers:
        Authorization: Bearer ${{ steps['get-ado-token'].output.body.providerInfo.accessToken }}
        Content-Type: application/json
      body:
        name: ${{ parameters.appName }}

  # Passo 3: Criar pipeline no ADO
  - id: create-pipeline
    name: Criar pipeline no Azure DevOps
    action: http:backstage:request
    input:
      method: POST
      path: /api/proxy/azure-devops/<ORG>/<PROJECT>/_apis/pipelines?api-version=7.1
      headers:
        Authorization: Bearer ${{ steps['get-ado-token'].output.body.providerInfo.accessToken }}
        Content-Type: application/json
      body:
        name: <ORG>.${{ parameters.appName }}
        folder: /
        configuration:
          type: yaml
          path: azure-pipelines.yml
          repository:
            id: ${{ steps['create-repo'].output.body.id }}
            type: azureReposGit
            defaultBranch: refs/heads/main
```

---

## 7. Estrutura do Repositório devhub-ado-demo

```
devhub-ado-demo/
├── all-templates.yaml                          # Location file — registra templates no catálogo
└── templates/
    └── quarkus-ado-oauth/
        ├── template.yaml                       # Definição do template scaffolder
        └── skeleton/
            ├── catalog-info.yaml               # Registro no catálogo do RHDH
            ├── azure-pipelines.yml             # Pipeline ADO (com bloco pool obrigatório)
            ├── pom.xml                         # Projeto Quarkus
            └── src/
                └── main/java/com/example/
                    └── GreetingResource.java
```

### Registrar no catálogo do RHDH

Adicione no `app-config.yaml`:

```yaml
catalog:
  locations:
    - type: url
      target: https://dev.azure.com/<ORG>/<PROJECT>/_git/devhub-ado-demo?path=/all-templates.yaml&version=GBmain
```

---

## 8. Troubleshooting

| Erro / Sintoma | Causa | Solução |
|---|---|---|
| `AADSTS900023: $azure_tenant_id not valid` | Variável não expandida no app-config | Usar `${VARIAVEL}` com chaves, não `$VARIAVEL` |
| `AADSTS70011: .default scope invalid` | `additionalScopes` com `.default` misturado com Graph scopes | Usar `user_impersonation` em vez de `.default` no `additionalScopes` |
| Proxy ADO retorna 302 | `allowedHeaders` faltando no endpoint do proxy | Adicionar `allowedHeaders: [Authorization, Content-Type]` |
| Token com `aud: 00000003` (Graph) | Scope ADO não solicitado corretamente | Usar `/refresh?scope=499b84ac-.../.default` |
| `401 Invalid X-Requested-With` | Header obrigatório ausente na chamada ao `/refresh` | Adicionar `X-Requested-With: XMLHttpRequest` |
| `400 Must specify env query` | Parâmetro `env` ausente | Adicionar `?env=production` no `/refresh` |
| `PopupClosedError` no login | Popup de consentimento fechado antes de aceitar | Clicar **Accept** na tela de permissões do Entra ID |
| Pod travado `Init:0/1` | Plugin OCI não encontrado ou versão incompatível | `oc logs <pod> -c install-dynamic-plugins` |
| `additionalScopes` ignorado na sessão | Backstage não combina scopes de resources diferentes | Usar `/refresh` com scope explícito |
| `No pool was specified` no pipeline | `azure-pipelines.yml` sem bloco `pool` | Adicionar `pool: vmImage: ubuntu-latest` no skeleton |

---

## 9. Referência Rápida

### Variáveis do Secret OpenShift

| Variável | Como obter |
|---|---|
| `AZURE_CLIENT_ID` | Application (client) ID do App Registration |
| `AZURE_TENANT_ID` | Directory (tenant) ID |
| `AZURE_CLIENT_SECRET` | Value do client secret (visível apenas na criação) |
| `BACKEND_SECRET` | `openssl rand -base64 24` |

### URLs padrão

| Recurso | Padrão |
|---|---|
| RHDH | `https://backstage-developer-hub-<NAMESPACE>.apps.<CLUSTER_DOMAIN>` |
| Redirect URI | `https://backstage-developer-hub-<NAMESPACE>.apps.<CLUSTER_DOMAIN>/api/auth/microsoft/handler/frame` |
| ADO Org settings | `https://dev.azure.com/<ORG>/_settings/organizationAad` |
| Repo templates | `https://dev.azure.com/<ORG>/<PROJECT>/_git/devhub-ado-demo` |

### GUIDs fixos do Azure DevOps (públicos — iguais em todos os tenants)

| Item | Valor |
|---|---|
| Resource ID (audience) | `499b84ac-1321-427f-aa17-267ca6975798` |
| Scope para `/refresh` | `499b84ac-1321-427f-aa17-267ca6975798/.default` |
| Scope URL completo | `https://app.vssps.visualstudio.com/user_impersonation` |

### Comandos úteis

```bash
# Verificar variáveis no pod
oc exec -n devhub deployment/backstage-developer-hub -- env | grep AZURE

# Reiniciar após mudança de ConfigMap
oc rollout restart deployment/backstage-developer-hub -n devhub
oc rollout status deployment/backstage-developer-hub -n devhub

# Logs do pod
oc logs -f deployment/backstage-developer-hub -n devhub

# Filtrar erros de plugin
oc logs deployment/backstage-developer-hub -n devhub | grep -i "error\|failed\|plugin"

# Verificar token ADO no browser (console)
const r = await fetch(
  '/api/auth/microsoft/refresh?env=production&scope=499b84ac-1321-427f-aa17-267ca6975798%2F.default',
  { credentials: 'include', headers: { 'X-Requested-With': 'XMLHttpRequest' } }
);
const d = await r.json();
console.log('scope:', d.providerInfo?.scope);
```

---

## 10. Origem do GUID `499b84ac-1321-427f-aa17-267ca6975798`

### O que é esse valor

Esse GUID é o **Application ID oficial do Azure DevOps**, registrado pela Microsoft no Entra ID global. Não é um valor gerado pelo usuário — é fixo, público, e **igual em todos os tenants do mundo**.

### Como verificar

**Via portal Azure:**
1. Acesse **Microsoft Entra ID → Enterprise applications**
2. Remova o filtro e busque por `Azure DevOps`
3. O Application ID exibido será exatamente `499b84ac-1321-427f-aa17-267ca6975798`

**Via Microsoft Graph API:**
```
GET https://graph.microsoft.com/v1.0/servicePrincipals?$filter=displayName eq 'Azure DevOps'
```

### Por que usar GUID em vez da URL

Quando você solicita um token OAuth, o Entra ID precisa saber para qual **resource** (audience) o token será emitido. Isso é especificado pelo scope. Existem duas formas equivalentes:

| Forma | Scope |
|---|---|
| URL | `https://app.vssps.visualstudio.com/user_impersonation` |
| GUID + `.default` | `499b84ac-1321-427f-aa17-267ca6975798/.default` |

A diferença é que `/.default` solicita **todos os escopos delegados já consentidos** para aquele resource — no caso, o `user_impersonation` concedido no App Registration. É a forma mais robusta porque não depende de nomear o escopo explicitamente.

### Como chegamos a esse valor — caminho percorrido

Durante a validação desta configuração, o fluxo de descoberta foi o seguinte:

| Tentativa | Resultado |
|---|---|
| Token sem scope ADO | `aud: 00000003-...` (Microsoft Graph) — ADO retornava 302 |
| `additionalScopes` com `user_impersonation` no app-config | Ignorado — Backstage não combina scopes de resources diferentes |
| `/refresh` sem parâmetros | 400 — `Must specify 'env' query` |
| `/refresh?scope=https://app.vssps.visualstudio.com/user_impersonation` | 400 — scope inválido neste formato |
| `/refresh` sem header `X-Requested-With` | 401 — `Invalid X-Requested-With header` |
| `/refresh?env=production&scope=499b84ac-.../.default` + header `X-Requested-With: XMLHttpRequest` | ✅ 200 — `aud: 499b84ac-...`, `scp: user_impersonation` |

### Referência oficial

O GUID está documentado na documentação oficial da Microsoft:
```
https://learn.microsoft.com/en-us/azure/devops/integrate/get-started/authentication/oauth
```

> ℹ️ Este valor nunca muda — pode ser usado com segurança em qualquer tenant, organização ADO ou ambiente.

---

## 11. Integração ADO sem PAT — Service Principal via OAuth2

### Contexto

O objetivo é que o scaffolder execute operações no Azure DevOps (criar repositório, pipeline, push) **sem PAT fixo**, usando o Service Principal do App Registration.

O fluxo final validado usa **OAuth2 client_credentials** — o Service Principal obtém um token ADO diretamente do Entra ID via proxy do RHDH.

### Por que `requestUserCredentials` não funciona

O `requestUserCredentials` com `additionalScopes.microsoft: [user_impersonation]` não resolve o conflito de audiences:

- O provider `microsoft` do Backstage emite tokens com `aud: 00000003-...` (Microsoft Graph)
- O ADO requer tokens com `aud: 499b84ac-...` (Azure DevOps)
- O MSAL não combina scopes de resources diferentes em um único token
- Resultado: ADO retorna redirect 302 para login

### Solução — OAuth2 client_credentials via proxy

O Service Principal obtém o token ADO chamando diretamente o endpoint OAuth2 do Entra ID com `grant_type=client_credentials`:

```
POST https://login.microsoftonline.com/<TENANT_ID>/oauth2/v2.0/token
Authorization: Basic <base64(client_id:client_secret)>
Content-Type: application/x-www-form-urlencoded
Body: grant_type=client_credentials&scope=499b84ac-1321-427f-aa17-267ca6975798/.default
```

Retorna `access_token` com `aud: 499b84ac-...` ✅

### Limitações do proxy Backstage

Durante a implementação, três limitações importantes foram descobertas:

| Limitação | Impacto | Solução |
|---|---|---|
| Variáveis `${VAR}` não expandidas no campo `target` do proxy | `target: https://login.microsoftonline.com/${AZURE_TENANT_ID}/...` fica literal | Hardcode do Tenant ID no target (GUID público, não sensível) |
| Variáveis `${VAR}` não expandidas em `proxy.endpoints.headers` | `Authorization: Basic ${AZURE_SP_BASIC}` não funcionaria direto | Usar Secret OpenShift + env var injetada |
| `http:backstage:request` não aceita `params` como query string | `params: {env: production}` ignorado | Incluir query params inline no path |

### Configuração do proxy no app-config

```yaml
proxy:
  endpoints:
    /azure-devops:
      target: https://dev.azure.com
      changeOrigin: true
      allowedMethods: [GET, POST, DELETE, PATCH, PUT]
      credentials: dangerously-allow-unauthenticated
      allowedHeaders:
        - Authorization
        - Content-Type
    /azure-token:
      # Tenant ID hardcoded — ${VAR} não é expandido no campo target
      target: https://login.microsoftonline.com/<TENANT_ID>/oauth2/v2.0
      changeOrigin: true
      allowedMethods: [POST]
      credentials: dangerously-allow-unauthenticated
      # NOTA: NÃO incluir Authorization aqui
      # O header Basic vem diretamente do template (step get-sp-token)
      # O proxy nunca usa seu próprio Authorization — o template já envia o header
      # antes da requisição chegar ao proxy
      allowedHeaders:
        - Authorization
        - Content-Type
```

### Gerar o valor AZURE_SP_BASIC

```bash
echo -n "<AZURE_CLIENT_ID>:<AZURE_CLIENT_SECRET>" | base64
```

O valor gerado é usado **diretamente no `template.yaml`** — no header `Authorization: Basic <valor>` do step `get-sp-token`.

> ℹ️ O AZURE_SP_BASIC **não precisa** ser adicionado ao Secret OpenShift nem ao proxy do app-config. O plugin `http:backstage:request` envia o header `Authorization` do template antes da requisição chegar ao proxy — o proxy nunca usa seu próprio header Authorization.

### Template scaffolder — step get-sp-token

```yaml
- id: get-sp-token
  name: Obter token OAuth ADO (Service Principal)
  action: http:backstage:request
  input:
    method: POST
    path: /proxy/azure-token/token
    headers:
      Content-Type: application/x-www-form-urlencoded
    # Credenciais NÃO ficam no body — estão no header Authorization do proxy
    body: "grant_type=client_credentials&scope=499b84ac-1321-427f-aa17-267ca6975798%2F.default"

- id: create-repo
  name: Criar repositório no Azure DevOps
  action: http:backstage:request
  input:
    method: POST
    path: /proxy/azure-devops/<ORG>/<PROJECT>/_apis/git/repositories?api-version=7.1
    headers:
      Authorization: Bearer ${{ steps['get-sp-token'].output.body.access_token }}
      Content-Type: application/json
    body:
      name: ${{ parameters.appName }}
```

### Adicionar Service Principal como usuário no ADO

Para que o Service Principal possa operar no ADO, ele deve ser adicionado como usuário da organização:

1. Acesse: `https://dev.azure.com/<ORG>/_settings/users`
2. Clique em **Add users**
3. Busque pelo **nome ou Client ID** do App Registration
4. Access level: **Basic**
5. Adicione aos projetos necessários
6. Clique em **Add**

> ✅ O Service Principal aparece na lista de usuários com seu Client ID como identificador.

### Schema correto do azure:repository:push

Durante a validação, o schema da action `azure:repository:push` instalada (plugin `backstage-community-plugin-scaffolder-backend-module-azure-devops:bs_1.45.3__0.18.0`) foi confirmado via `/create/actions`:

| Parâmetro | Tipo | Descrição |
|---|---|---|
| `remoteUrl` | string | **Obrigatório** — Git URL do repositório |
| `branch` | string | Branch para checkout |
| `sourcePath` | string | Subdiretório do working directory |
| `gitCommitMessage` | string | Mensagem do commit |
| `gitAuthorName` | string | Nome do autor |
| `gitAuthorEmail` | string | Email do autor |
| `token` | string | Token para autenticação |

> ⚠️ Parâmetros `organization`, `project`, `repositoryName`, `defaultBranch` **não existem** nesta versão — causam erro `instance is not allowed to have the additional property`.

---

## 12. Authorization Basic no template — justificativa e implicações

### Contexto

O plugin `http:backstage:request` (v5.5.1) injeta automaticamente o token Backstage no header `Authorization` de toda requisição — **a menos que o template já passe um `Authorization` explícito**. O código fonte confirma:

```javascript
if (token && !authToken) {
  ctx.logger.info(`Token is defined. Setting authorization header.`);
  httpOptions.headers.authorization = `Bearer ${token}`;
}
```

Ou seja: se o template já definir o header `Authorization`, o plugin respeita e não sobrescreve.

### Solução aplicada

O valor Base64 do Service Principal é passado diretamente no header do step `get-sp-token`:

```yaml
- id: get-sp-token
  name: Obter token OAuth ADO (Service Principal)
  action: http:backstage:request
  input:
    method: POST
    path: /proxy/azure-token/token
    headers:
      Content-Type: application/x-www-form-urlencoded
      Authorization: "Basic <base64(clientId:clientSecret)>"
    body: "grant_type=client_credentials&scope=499b84ac-1321-427f-aa17-267ca6975798%2F.default"
```

### Por que é aceitável neste contexto

O valor `Basic <base64>` no template é o Base64 de `clientId:clientSecret` — decodificável por qualquer pessoa que leia o arquivo. No entanto:

| Aspecto | Avaliação |
|---|---|
| Repositório `devhub-ado-demo` | Privado no ADO — acesso restrito |
| Quem pode ler o template | Usuários com acesso ao projeto ADO — os mesmos que operam o ambiente |
| Elevação de privilégio | Nenhuma — o SP já tem acesso ao ADO para essas operações |
| Escopo do Service Principal | Limitado: apenas `user_impersonation` no ADO |

### Comparação de segurança entre abordagens

| Abordagem | Onde fica a credencial | Quem pode ver |
|---|---|---|
| Basic hardcoded no template | `template.yaml` no repo ADO privado | Usuários com acesso ao projeto ADO |
| Basic no app-config ConfigMap | ConfigMap no namespace OpenShift | Admins do namespace devhub |
| Basic no Secret OpenShift | Secret no namespace OpenShift | Admins do namespace devhub (criptografado) |
| PAT no Secret | Secret no namespace OpenShift | Admins do namespace devhub (criptografado) |

> ⚠️ O ConfigMap é **menos seguro** que o Secret — não é criptografado em repouso. O template em repositório privado tem segurança equivalente ao ConfigMap.

### Alternativa mais segura

Se o contexto exigir maior segurança, a única alternativa sem expor credenciais no template é implementar um **custom scaffolder action** no RHDH que obtém o token internamente via SDK do Backstage, sem passar pelo `http:backstage:request`. Isso requer desenvolvimento customizado.

### Por que só no template e não no proxy?

O `Authorization: Basic` precisa estar **apenas no template** — não no proxy. Isso porque:

1. O template chama `/proxy/azure-token/token` com `Authorization: Basic <valor>` no header
2. O plugin `http:backstage:request` verifica: `if (token && !authToken)` — como já há `authToken`, não sobrescreve
3. A requisição chega ao proxy **já com o header correto**
4. Qualquer `Authorization` configurado no proxy seria ignorado — o que chegou tem precedência

Configurar o `Authorization` no proxy (`proxy.endpoints./azure-token.headers`) é desnecessário e pode causar confusão. O proxy apenas roteia a requisição para o Entra ID.

### Limitação documentada do plugin

Esta é uma limitação arquitetural do `http:backstage:request` — o plugin foi projetado para chamadas ao próprio backend Backstage, não para autenticação em sistemas externos. Para sistemas externos que requerem autenticação própria, as opções são:

1. Passar `Authorization` explícito no template (solução aplicada)
2. Configurar autenticação no proxy (não funciona — o header do proxy é ignorado)
3. Custom scaffolder action

---

## 13. Template Final Validado — 8 Steps End-to-End

### Fluxo completo validado

| Step | Action | Status |
|---|---|---|
| 1. Obter token OAuth ADO | `http:backstage:request` → `/proxy/azure-token/token` | ✅ |
| 2. Criar repositório | `http:backstage:request` → ADO REST API | ✅ |
| 3. Clonar repositório | `azure:repository:clone` | ✅ |
| 4. Gerar skeleton | `fetch:template` com `targetPath: ./repo` | ✅ |
| 5. Push do skeleton | `azure:repository:push` com `sourcePath: ./repo` | ✅ |
| 6. Criar pipeline | `http:backstage:request` → ADO REST API | ✅ |
| 7. Executar pipeline | `azure:pipeline:run` | ✅ |
| 8. Registrar no catálogo | `catalog:register` | ✅ |

### Descobertas críticas do step azure:pipeline:run

1. **`pipelineId` deve ser string** — o output de `create-pipeline` retorna número. Usar filtro Nunjucks: `"${{ steps['create-pipeline'].output.body.id | string }}"`
2. **`token`** aceita o mesmo Bearer token do Service Principal

### Padrão clone → fetch → push

O problema de `Could not find HEAD` em repos recém-criados é resolvido com o padrão:

```yaml
# 1. Clonar o repo vazio — inicializa o git local corretamente
- id: clone-repo
  action: azure:repository:clone
  input:
    remoteUrl: ${{ steps['create-repo'].output.body.remoteUrl }}
    targetPath: ./repo
    token: ${{ steps['get-sp-token'].output.body.access_token }}

# 2. Gerar skeleton NO MESMO diretório clonado
- id: fetch-skeleton
  action: fetch:template
  input:
    url: ./skeleton
    targetPath: ./repo   # <- mesmo diretório do clone

# 3. Push usando sourcePath apontando para o diretório clonado
- id: push-content
  action: azure:repository:push
  input:
    remoteUrl: ${{ steps['create-repo'].output.body.remoteUrl }}
    branch: main
    sourcePath: ./repo   # <- mesmo diretório do clone
    token: ${{ steps['get-sp-token'].output.body.access_token }}
```

> ℹ️ O `azure:repository:clone` inicializa o git local mesmo com repo vazio, criando o HEAD necessário para o commit posterior.

---

## 14. Referências

### Microsoft — Autenticação e Tokens Azure DevOps

| Documento | URL |
|---|---|
| Azure DevOps CLI — Entra tokens | https://learn.microsoft.com/en-us/azure/devops/cli/entra-tokens?view=azure-devops&tabs=azure-cli |
| Azure DevOps REST API — Tokens | https://learn.microsoft.com/pt-br/rest/api/azure/devops/tokens/?view=azure-devops-rest-7.1&tabs=powershell |
| OAuth 2.0 — client_credentials | https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-client-creds-grant-flow |
| OAuth 2.0 — Authorization Code Flow | https://learn.microsoft.com/pt-br/entra/identity-platform/v2-oauth2-auth-code-flow |
| Azure DevOps — Resource ID (audience) | https://learn.microsoft.com/en-us/azure/devops/integrate/get-started/authentication/oauth |

### Red Hat Developer Hub

| Documento | URL |
|---|---|
| RHDH — Scaffolder Built-in Actions | https://backstage.io/docs/features/software-templates/builtin-actions/ |
| RHDH — Dynamic Plugins | https://docs.redhat.com/en/documentation/red_hat_developer_hub/1.4/html/configuring_plugins_in_red_hat_developer_hub/rhdh-installing-dynamic-plugins |
| RHDH — Proxy Configuration | https://backstage.io/docs/plugins/proxying |
| Roadie HTTP Request Action | https://github.com/RoadieHQ/roadie-backstage-plugins/tree/main/plugins/scaffolder-actions/scaffolder-backend-module-http-request |

### Azure DevOps Community Plugins (RHDH)

| Plugin | Versão validada | URL |
|---|---|---|
| backstage-community-plugin-azure-devops | bs_1.45.3__0.23.0 | https://github.com/backstage/community-plugins/tree/main/workspaces/azure-devops |
| backstage-community-plugin-scaffolder-backend-module-azure-devops | bs_1.45.3__0.18.0 | https://github.com/backstage/community-plugins/tree/main/workspaces/azure-devops |

### GUIDs fixos do Azure DevOps (válidos em qualquer tenant)

| Item | Valor |
|---|---|
| Resource ID / Audience | `499b84ac-1321-427f-aa17-267ca6975798` |
| Scope client_credentials | `499b84ac-1321-427f-aa17-267ca6975798/.default` |
| Scope delegado | `https://app.vssps.visualstudio.com/user_impersonation` |
