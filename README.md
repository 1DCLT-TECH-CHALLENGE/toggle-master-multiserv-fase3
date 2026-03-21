# ToggleMaster — Fase 3: IaC + DevSecOps + GitOps

> **Turma:** 1DCLT · **Fase:** 3 · **Stack:** Terraform · GitHub Actions · ArgoCD · AWS EKS

---

## Estrutura do Monorepo

```
toggle-master-fase3/
├── .github/
│   └── workflows/
│       ├── ci-reusable.yml        # Pipeline principal reutilizável (5 jobs)
│       ├── ci-auth.yml            # Chama ci-reusable para auth (Go)
│       ├── ci-flag.yml            # Chama ci-reusable para flag (Python)
│       ├── ci-targeting.yml       # Chama ci-reusable para targeting (Python)
│       ├── ci-evaluation.yml      # Chama ci-reusable para evaluation (Go)
│       └── ci-analytics.yml       # Chama ci-reusable para analytics (Python)
│
├── terraform/
│   ├── environments/
│   │   └── prod/
│   │       ├── main.tf            # Orquestra todos os módulos
│   │       ├── variables.tf
│   │       ├── outputs.tf
│   │       ├── versions.tf        # Backend S3 + providers
│   │       └── terraform.tfvars   # ← PREENCHER antes do apply
│   └── modules/
│       ├── networking/            # VPC, subnets, IGW, NAT, route tables
│       ├── iam-oidc/              # OIDC Provider + IAM Role GitHub Actions
│       ├── eks/                   # Cluster EKS + node group + IAM
│       ├── rds/                   # 3x PostgreSQL com senhas aleatórias
│       ├── elasticache/           # Redis cluster
│       ├── dynamodb/              # Tabela ToggleMasterAnalytics
│       ├── sqs/                   # Fila analytics + DLQ
│       └── ecr/                   # 5 repositórios com lifecycle policy
│
├── gitops/
│   ├── apps/
│   │   └── togglemaster-apps.yaml # ArgoCD Applications (App of Apps)
│   └── base/
│       ├── ingress.yaml           # Nginx Ingress com path-based routing
│       ├── auth/                  # deployment.yaml + service.yaml
│       ├── flag/                  # deployment.yaml + service.yaml
│       ├── targeting/             # deployment.yaml + service.yaml
│       ├── evaluation/            # deployment.yaml + service.yaml + HPA
│       └── analytics/             # deployment.yaml + service.yaml + HPA
│
└── services/                      # ← COPIAR os serviços da Fase 2 aqui
    ├── auth/
    ├── flag/
    ├── targeting/
    ├── evaluation/
    └── analytics/
```

---

## Pré-requisitos

- AWS CLI v2 configurado com credenciais de conta própria
- Terraform >= 1.6
- kubectl
- helm >= 3.14
- git

---

## Setup Inicial (fazer uma vez)

### 1. Criar o bucket S3 para o tfstate

> Fazer **antes** do `terraform init` — o bucket precisa existir primeiro.

```bash
aws s3 mb s3://togglemaster-tfstate-fase3 --region us-east-1
aws s3api put-bucket-versioning \
  --bucket togglemaster-tfstate-fase3 \
  --versioning-configuration Status=Enabled
```

### 2. Preencher terraform.tfvars

Editar `terraform/environments/prod/terraform.tfvars`:

```hcl
github_org  = "SEU_GITHUB_ORG"   # ex: "1DCLT-TECH-CHALLENGE"
github_repo = "toggle-master-fase3"
```

### 3. Copiar serviços da Fase 2

```bash
# Criar estrutura de serviços no monorepo
mkdir -p services/{auth,flag,targeting,evaluation,analytics}

# Copiar código da Fase 2 para cada pasta
# Cada pasta deve ter: Dockerfile + código fonte
```

---

## Deploy da Infraestrutura (Terraform)

```bash
cd terraform/environments/prod

# Inicializa com backend S3
terraform init

# Valida e visualiza o plano
terraform validate
terraform plan -out=tfplan

# Aplica (leva ~15-20 min — EKS é o mais demorado)
terraform apply tfplan
```

> **Outputs importantes após o apply:**
> - `github_actions_role_arn` → adicionar como secret `GHA_ROLE_ARN` no GitHub
> - `eks_cluster_name` → usar no kubeconfig
> - `ecr_repositories` → URLs dos repos ECR
> - `kubeconfig_command` → comando para configurar o kubectl

### Configurar kubectl

```bash
# Executar o comando exibido no output "kubeconfig_command"
aws eks update-kubeconfig --region us-east-1 --name togglemaster-prod-cluster
kubectl get nodes
```

---

## Configurar GitHub Actions

### Secrets necessários no repositório

Ir em **Settings → Secrets and variables → Actions** e adicionar:

| Secret | Valor |
|--------|-------|
| `AWS_ACCOUNT_ID` | ID da sua conta AWS (12 dígitos) |
| `GHA_ROLE_ARN` | ARN da role do output `github_actions_role_arn` |

> O OIDC já está configurado — não precisa de Access Key nem Secret Key.

---

## Deploy do ArgoCD e GitOps

### 1. Verificar instalação do ArgoCD (feita pelo Terraform)

```bash
kubectl get pods -n argocd
kubectl get svc argocd-server -n argocd
```

### 2. Obter senha inicial do ArgoCD

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

### 3. Atualizar repoURL nos manifestos ArgoCD

Editar `gitops/apps/togglemaster-apps.yaml` e substituir `SEU_GITHUB_ORG`:

```bash
sed -i 's/SEU_GITHUB_ORG/sua-org-real/g' gitops/apps/togglemaster-apps.yaml
```

### 4. Aplicar as Applications no ArgoCD

```bash
kubectl apply -f gitops/apps/togglemaster-apps.yaml -n argocd
```

### 5. Instalar nginx-ingress (necessário para o Ingress funcionar)

```bash
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace
```

### 6. Acessar a UI do ArgoCD

```bash
# Obter o IP externo
kubectl get svc argocd-server -n argocd

# Acessar: http://<EXTERNAL-IP>
# Login: admin / <senha obtida acima>
```

---

## Fluxo GitOps (como funciona)

```
Developer → Push para main
    ↓
GitHub Actions (ci-<service>.yml)
    ↓
  Job 1: Build & Test
  Job 2: Lint (golangci-lint / flake8)
  Job 3: Security Scan → FALHA se CRITICAL encontrado
  Job 4: Docker Build → Trivy Image Scan → Push ECR
  Job 5: Atualiza gitops/base/<service>/deployment.yaml com nova tag
    ↓
ArgoCD detecta mudança no repo (polling a cada 3 min)
    ↓
ArgoCD sincroniza → kubectl apply automático no EKS
    ↓
Rolling update sem downtime
```

---

## Demonstração DevSecOps (para o vídeo)

### Inserir vulnerabilidade proposital (Go)

```go
// Em services/auth/main.go — adicionar import vulnerável
import "github.com/dgrijalva/jwt-go" // CVE conhecido
```

O pipeline vai falhar no Job 3 com:
```
CRITICAL: CVE-XXXX-XXXX in github.com/dgrijalva/jwt-go
```

### Correção

```go
// Substituir pelo fork mantido
import "github.com/golang-jwt/jwt/v5"
```

Pipeline passa, nova imagem é pushed, ArgoCD deploya automaticamente.

---

## Estimativa de Custo (us-east-1)

| Recurso | Configuração | Custo/mês estimado |
|---------|-------------|-------------------|
| EKS Cluster | 1 cluster | ~$72 |
| EC2 Nodes | 2x t3.medium | ~$60 |
| RDS PostgreSQL | 3x db.t3.micro | ~$45 |
| ElastiCache | 1x cache.t3.micro | ~$12 |
| NAT Gateway | 2x (HA) | ~$65 |
| ECR | 5 repos (~1GB) | ~$1 |
| DynamoDB | Pay per request | ~$1 |
| SQS | Pay per use | ~$1 |
| **Total estimado** | | **~$257/mês** |

> Para economia durante desenvolvimento: destruir com `terraform destroy` ao final do dia.

---

## Destruir o ambiente

```bash
cd terraform/environments/prod
terraform destroy
```

> O bucket S3 do tfstate **não** é destruído automaticamente (proteção de estado).
