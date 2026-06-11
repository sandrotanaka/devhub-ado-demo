# devhub-ado-demo

**[EN](#english-version)** | **[PT-BR](#versão-em-português)**

---

## English Version

Red Hat Developer Hub — Azure DevOps Integration via OAuth2 (no PAT).

### Structure

```
devhub-ado-demo/
├── all-templates.yaml                        # Location file — registers templates in RHDH catalog
├── README.md
├── manifests/
│   ├── 01-secret.sh                          # Script to create the Secret with credentials
│   ├── 02-configmap-app-config.yaml          # RHDH app-config
│   ├── 03-configmap-dynamic-plugins.yaml     # Enabled dynamic plugins
│   └── 04-backstage-cr.yaml                  # Backstage CR (RHDH Operator)
├── templates/
│   └── quarkus-ado-oauth/
│       ├── template.yaml                     # Scaffolder template — 8 validated steps
│       └── skeleton/
│           ├── azure-pipelines.yml
│           ├── catalog-info.yaml
│           ├── pom.xml
│           └── src/main/java/com/example/
│               └── GreetingResource.java
└── docs/
    ├── devhub-ado-demo-guia.md               # Full technical guide (14 sections — PT-BR)
    └── runbook-instalacao.md                 # Installation runbook (bilingual)
```

### Prerequisites

> **Where to host this repository:** the template reads its content directly from the ADO catalog location configured in `app-config.yaml`. For a working deployment, this repository must be hosted in **Azure DevOps** — the RHDH catalog uses the `integrations.azure` Service Principal credentials to read `all-templates.yaml` and the template files at runtime. The GitHub repository serves as a public reference only. For your own deployment, clone it into your ADO organization and update the catalog location in `manifests/02-configmap-app-config.yaml` accordingly.


- OpenShift with RHDH Operator v1.9.4 installed
- App Registration in Microsoft Entra ID with `Azure DevOps — user_impersonation` permission
- Service Principal added as user in the ADO organization (`Basic` + `Project Administrators`)
- ADO organization connected to the Entra ID tenant

### Quick Start

```bash
# 1. Create namespace
oc new-project devhub

# 2. Create Secret with credentials (edit script first)
bash manifests/01-secret.sh

# 3. Apply ConfigMaps (replace <CLUSTER_DOMAIN> and <AZURE_TENANT_ID>)
oc apply -f manifests/02-configmap-app-config.yaml -n devhub
oc apply -f manifests/03-configmap-dynamic-plugins.yaml -n devhub

# 4. Create RHDH instance
oc apply -f manifests/04-backstage-cr.yaml -n devhub

# 5. Wait for pod to be ready
oc rollout status deployment/backstage-developer-hub -n devhub
```

### Template — End-to-End Flow

| Step | Action | Description |
|---|---|---|
| 1 | `http:backstage:request` | Obtain OAuth2 token via client_credentials |
| 2 | `http:backstage:request` | Create ADO repository |
| 3 | `azure:repository:clone` | Clone empty repo (initializes local git) |
| 4 | `fetch:template` | Generate skeleton in cloned directory |
| 5 | `azure:repository:push` | Push skeleton |
| 6 | `http:backstage:request` | Create ADO pipeline |
| 7 | `azure:pipeline:run` | Run pipeline |
| 8 | `catalog:register` | Register in RHDH catalog |

### Key Findings

1. **`${VAR}` is NOT expanded in `proxy.endpoints.target` or `proxy.endpoints.headers`** — Tenant ID must be hardcoded in target
2. **`Authorization: Basic` only in the template, NOT in the proxy** — the plugin sends the header before proxy processing; any proxy `Authorization` would be ignored
3. **`http:backstage:request` overwrites `Authorization`** — unless the template explicitly sets the header (`if (token && !authToken)` logic)
4. **`azure:repository:push` requires HEAD** — cloning the repo before pushing resolves the `Could not find HEAD` error
5. **`pipelineId` must be a string** — use Nunjucks filter `| string`
6. **Service Principal must be `Project Administrator`** in ADO to create repositories

### Azure DevOps Fixed GUIDs (valid in any tenant)

| Item | Value |
|---|---|
| Resource ID (audience) | `499b84ac-1321-427f-aa17-267ca6975798` |
| Scope for client_credentials | `499b84ac-1321-427f-aa17-267ca6975798/.default` |

### References

| Document | URL |
|---|---|
| Azure DevOps CLI — Entra tokens | https://learn.microsoft.com/en-us/azure/devops/cli/entra-tokens?view=azure-devops&tabs=azure-cli |
| Azure DevOps REST API — Tokens | https://learn.microsoft.com/pt-br/rest/api/azure/devops/tokens/?view=azure-devops-rest-7.1&tabs=powershell |
| OAuth 2.0 — client_credentials | https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-client-creds-grant-flow |
| OAuth 2.0 — Authorization Code Flow | https://learn.microsoft.com/pt-br/entra/identity-platform/v2-oauth2-auth-code-flow |
| Azure DevOps — Resource ID | https://learn.microsoft.com/en-us/azure/devops/integrate/get-started/authentication/oauth |
| Scaffolder Built-in Actions | https://backstage.io/docs/features/software-templates/builtin-actions/ |
| Roadie HTTP Request Action | https://github.com/RoadieHQ/roadie-backstage-plugins/tree/main/plugins/scaffolder-actions/scaffolder-backend-module-http-request |

---

## Versão em Português

Red Hat Developer Hub — Integração Azure DevOps via OAuth2 sem PAT.

### Estrutura

```
devhub-ado-demo/
├── all-templates.yaml                        # Location file — registra templates no catálogo RHDH
├── README.md
├── manifests/
│   ├── 01-secret.sh                          # Script para criar o Secret com as credenciais
│   ├── 02-configmap-app-config.yaml          # app-config do RHDH
│   ├── 03-configmap-dynamic-plugins.yaml     # Plugins dinâmicos habilitados
│   └── 04-backstage-cr.yaml                  # Backstage CR (RHDH Operator)
├── templates/
│   └── quarkus-ado-oauth/
│       ├── template.yaml                     # Template scaffolder — 8 steps validados
│       └── skeleton/
│           ├── azure-pipelines.yml
│           ├── catalog-info.yaml
│           ├── pom.xml
│           └── src/main/java/com/example/
│               └── GreetingResource.java
└── docs/
    ├── devhub-ado-demo-guia.md               # Guia técnico completo (14 seções)
    └── runbook-instalacao.md                 # Runbook de instalação (bilíngue)
```

### Pré-requisitos

- OpenShift com RHDH Operator v1.9.4 instalado
- App Registration no Microsoft Entra ID com permissão `Azure DevOps — user_impersonation`
- Service Principal adicionado como usuário na organização ADO (`Basic` + `Project Administrators`)
- Organização ADO conectada ao tenant Entra ID

### Instalação rápida

```bash
# 1. Criar namespace
oc new-project devhub

# 2. Criar Secret com credenciais (editar o script antes)
bash manifests/01-secret.sh

# 3. Aplicar ConfigMaps (substituir <CLUSTER_DOMAIN> e <AZURE_TENANT_ID>)
oc apply -f manifests/02-configmap-app-config.yaml -n devhub
oc apply -f manifests/03-configmap-dynamic-plugins.yaml -n devhub

# 4. Criar instância do RHDH
oc apply -f manifests/04-backstage-cr.yaml -n devhub

# 5. Aguardar pod subir
oc rollout status deployment/backstage-developer-hub -n devhub
```

### Template — Fluxo end-to-end

| Step | Action | Descrição |
|---|---|---|
| 1 | `http:backstage:request` | Obter token OAuth2 via client_credentials |
| 2 | `http:backstage:request` | Criar repositório ADO |
| 3 | `azure:repository:clone` | Clonar repo vazio (inicializa git local) |
| 4 | `fetch:template` | Gerar skeleton no diretório clonado |
| 5 | `azure:repository:push` | Push do skeleton |
| 6 | `http:backstage:request` | Criar pipeline ADO |
| 7 | `azure:pipeline:run` | Executar pipeline |
| 8 | `catalog:register` | Registrar no catálogo RHDH |

### Descobertas críticas

1. **`${VAR}` não é expandido em `proxy.endpoints.target` nem em `proxy.endpoints.headers`** — Tenant ID hardcoded no target
2. **`Authorization: Basic` apenas no template, não no proxy** — o plugin envia o header antes do proxy; qualquer `Authorization` no proxy seria ignorado
3. **`http:backstage:request` sobrescreve `Authorization`** — a menos que o template já defina o header explicitamente
4. **`azure:repository:push` requer HEAD** — clonar o repo antes do push resolve o problema
5. **`pipelineId` deve ser string** — usar filtro `| string` no Nunjucks
6. **Service Principal precisa ser `Project Administrator`** no ADO para criar repositórios

### GUIDs fixos do Azure DevOps

| Item | Valor |
|---|---|
| Resource ID (audience) | `499b84ac-1321-427f-aa17-267ca6975798` |
| Scope para client_credentials | `499b84ac-1321-427f-aa17-267ca6975798/.default` |
