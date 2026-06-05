# devhub-ado-demo

Red Hat Developer Hub — Integração Azure DevOps via OAuth2 sem PAT.

## Estrutura

```
devhub-ado-demo/
├── all-templates.yaml                        # Location file — registra templates no catálogo RHDH
├── README.md
├── manifests/                                # Manifests OpenShift prontos para aplicar
│   ├── 01-secret.sh                          # Script para criar o Secret com as credenciais
│   ├── 02-configmap-app-config.yaml          # app-config do RHDH
│   ├── 03-configmap-dynamic-plugins.yaml     # Plugins dinâmicos habilitados
│   └── 04-backstage-cr.yaml                  # Backstage CR (RHDH Operator)
├── templates/
│   └── quarkus-ado-oauth/
│       ├── template.yaml                     # Template scaffolder — 8 steps validados
│       └── skeleton/                         # Arquivos gerados para cada nova aplicação
│           ├── azure-pipelines.yml
│           ├── catalog-info.yaml
│           ├── pom.xml
│           └── src/main/java/com/example/
│               └── GreetingResource.java
└── docs/
    └── devhub-ado-demo-guia.md               # Guia completo de configuração (13 seções)
```

## Pré-requisitos

- OpenShift com RHDH Operator v1.9.4 instalado
- App Registration no Microsoft Entra ID com permissão `Azure DevOps — user_impersonation`
- Service Principal adicionado como usuário na organização ADO (`Basic` + `Project Administrators`)
- Organização ADO conectada ao tenant Entra ID

## Instalação rápida

```bash
# 1. Criar namespace
oc new-project devhub

# 2. Criar Secret com credenciais (editar o script antes)
bash manifests/01-secret.sh

# 3. Aplicar ConfigMaps
oc apply -f manifests/02-configmap-app-config.yaml -n devhub
oc apply -f manifests/03-configmap-dynamic-plugins.yaml -n devhub

# 4. Criar instância do RHDH
oc apply -f manifests/04-backstage-cr.yaml -n devhub

# 5. Aguardar pod subir
oc rollout status deployment/backstage-developer-hub -n devhub
```

## Template — fluxo end-to-end

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

## Descobertas críticas

Veja a documentação completa em `docs/devhub-ado-demo-guia.md`.

As principais:

1. **`${VAR}` não é expandido em `proxy.endpoints.target` nem em `proxy.endpoints.headers`** — Tenant ID hardcoded no target; Basic hardcoded no template
2. **`http:backstage:request` sobrescreve `Authorization`** — a menos que o template já defina o header explicitamente
3. **`azure:repository:push` requer HEAD** — clonar o repo antes do push resolve o problema
4. **`pipelineId` deve ser string** — usar filtro `| string` no Nunjucks
5. **Service Principal precisa ser `Project Administrator`** no ADO para criar repositórios

## GUIDs fixos do Azure DevOps

| Item | Valor |
|---|---|
| Resource ID (audience) | `499b84ac-1321-427f-aa17-267ca6975798` |
| Scope para client_credentials | `499b84ac-1321-427f-aa17-267ca6975798/.default` |
