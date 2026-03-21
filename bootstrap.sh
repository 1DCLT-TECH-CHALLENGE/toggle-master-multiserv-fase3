#!/usr/bin/env bash
# bootstrap.sh — Executa tudo do zero em sequência
# Uso: ./bootstrap.sh <github_org> <github_repo>
set -euo pipefail

GITHUB_ORG="${1:-SEU_GITHUB_ORG}"
GITHUB_REPO="${2:-toggle-master-fase3}"
AWS_REGION="us-east-1"
TFSTATE_BUCKET="togglemaster-tfstate-fase3"
TF_DIR="terraform/environments/prod"

echo "=============================================="
echo " ToggleMaster Fase 3 — Bootstrap"
echo " GitHub: ${GITHUB_ORG}/${GITHUB_REPO}"
echo " Região: ${AWS_REGION}"
echo "=============================================="

# 1. Verificar dependências
for cmd in aws terraform kubectl helm; do
  command -v $cmd >/dev/null 2>&1 || { echo "❌ $cmd não encontrado"; exit 1; }
done
echo "✅ Dependências OK"

# 2. Criar bucket S3 para tfstate
if aws s3 ls "s3://${TFSTATE_BUCKET}" 2>/dev/null; then
  echo "✅ Bucket ${TFSTATE_BUCKET} já existe"
else
  echo "🪣 Criando bucket S3 para tfstate..."
  aws s3 mb "s3://${TFSTATE_BUCKET}" --region "${AWS_REGION}"
  aws s3api put-bucket-versioning \
    --bucket "${TFSTATE_BUCKET}" \
    --versioning-configuration Status=Enabled
  echo "✅ Bucket criado com versionamento"
fi

# 3. Atualizar tfvars com o GitHub org/repo
sed -i "s/SEU_GITHUB_ORG/${GITHUB_ORG}/g" "${TF_DIR}/terraform.tfvars"
sed -i "s/toggle-master-fase3/${GITHUB_REPO}/g" "${TF_DIR}/terraform.tfvars"

# 4. Terraform init + plan + apply
cd "${TF_DIR}"
echo "🔧 terraform init..."
terraform init

echo "📋 terraform validate..."
terraform validate

echo "📋 terraform plan..."
terraform plan -out=tfplan

echo ""
echo "⚠️  Revisar o plano acima. Continuar com apply? (s/N)"
read -r CONFIRM
[[ "${CONFIRM}" =~ ^[Ss]$ ]] || { echo "Cancelado."; exit 0; }

echo "🚀 terraform apply..."
terraform apply tfplan

# 5. Configurar kubectl
CLUSTER_NAME=$(terraform output -raw eks_cluster_name)
echo "⚙️  Configurando kubeconfig para ${CLUSTER_NAME}..."
aws eks update-kubeconfig --region "${AWS_REGION}" --name "${CLUSTER_NAME}"
kubectl get nodes

# 6. Mostrar outputs importantes
echo ""
echo "=============================================="
echo " ✅ Infraestrutura criada com sucesso!"
echo "=============================================="
echo ""
echo "📌 Adicionar como secrets no GitHub:"
echo "   GHA_ROLE_ARN   = $(terraform output -raw github_actions_role_arn)"
echo "   AWS_ACCOUNT_ID = $(aws sts get-caller-identity --query Account --output text)"
echo ""
echo "📌 Próximos passos:"
echo "   1. Adicionar os secrets acima em Settings → Secrets do repo GitHub"
echo "   2. Editar gitops/apps/togglemaster-apps.yaml com o repoURL correto"
echo "   3. kubectl apply -f gitops/apps/togglemaster-apps.yaml -n argocd"
echo "   4. Acessar ArgoCD: kubectl get svc argocd-server -n argocd"
