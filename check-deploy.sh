#!/bin/bash

# Configurações
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO_NAME="bia"
ECR_REPO="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$ECR_REPO_NAME"
CLUSTER="${CLUSTER:-cluster-bia}"
SERVICE="${SERVICE:-service-bia}"
TASK_FAMILY="${TASK_FAMILY:-task-def-bia}"

echo "=== Validação Pré-Deploy BIA ==="
echo ""

# Verificar Git
echo "🔍 Verificando Git..."
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "❌ Não é um repositório Git"
    exit 1
fi
COMMIT_HASH=$(git rev-parse --short=7 HEAD)
echo "✅ Commit Hash: $COMMIT_HASH"
echo ""

# Verificar dependências
echo "🔍 Verificando dependências..."
for cmd in aws docker jq; do
    if ! command -v $cmd &> /dev/null; then
        echo "❌ $cmd não encontrado"
        exit 1
    fi
    echo "✅ $cmd instalado"
done
echo ""

# Verificar credenciais AWS
echo "🔍 Verificando credenciais AWS..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "❌ Credenciais AWS inválidas"
    exit 1
fi
echo "✅ Account ID: $ACCOUNT_ID"
echo ""

# Verificar ECR
echo "🔍 Verificando repositório ECR..."
if ! aws ecr describe-repositories --repository-names $ECR_REPO_NAME --region $REGION > /dev/null 2>&1; then
    echo "❌ Repositório ECR '$ECR_REPO_NAME' não encontrado"
    exit 1
fi
echo "✅ Repositório ECR existe"
echo ""

# Verificar Cluster ECS
echo "🔍 Verificando cluster ECS..."
CLUSTER_STATUS=$(aws ecs describe-clusters --clusters $CLUSTER --region $REGION --query 'clusters[0].status' --output text 2>/dev/null)
if [ "$CLUSTER_STATUS" != "ACTIVE" ]; then
    echo "❌ Cluster '$CLUSTER' não encontrado ou inativo"
    exit 1
fi
echo "✅ Cluster: $CLUSTER (ACTIVE)"
echo ""

# Verificar Service ECS
echo "🔍 Verificando serviço ECS..."
SERVICE_STATUS=$(aws ecs describe-services --cluster $CLUSTER --services $SERVICE --region $REGION --query 'services[0].status' --output text 2>/dev/null)
if [ "$SERVICE_STATUS" != "ACTIVE" ]; then
    echo "❌ Service '$SERVICE' não encontrado ou inativo"
    exit 1
fi
RUNNING_COUNT=$(aws ecs describe-services --cluster $CLUSTER --services $SERVICE --region $REGION --query 'services[0].runningCount' --output text)
DESIRED_COUNT=$(aws ecs describe-services --cluster $CLUSTER --services $SERVICE --region $REGION --query 'services[0].desiredCount' --output text)
echo "✅ Service: $SERVICE (ACTIVE)"
echo "   Running: $RUNNING_COUNT | Desired: $DESIRED_COUNT"
echo ""

# Verificar Task Definition
echo "🔍 Verificando task definition..."
CURRENT_REVISION=$(aws ecs describe-task-definition --task-definition $TASK_FAMILY --region $REGION --query 'taskDefinition.revision' --output text 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "❌ Task Definition '$TASK_FAMILY' não encontrada"
    exit 1
fi
CURRENT_IMAGE=$(aws ecs describe-task-definition --task-definition $TASK_FAMILY --region $REGION --query 'taskDefinition.containerDefinitions[0].image' --output text)
echo "✅ Task Definition: $TASK_FAMILY:$CURRENT_REVISION"
echo "   Imagem atual: $CURRENT_IMAGE"
echo ""

# Verificar Dockerfile
echo "🔍 Verificando Dockerfile..."
if [ ! -f "Dockerfile" ]; then
    echo "❌ Dockerfile não encontrado"
    exit 1
fi
echo "✅ Dockerfile existe"
echo ""

# Listar últimas versões no ECR
echo "📦 Últimas 5 versões no ECR:"
aws ecr describe-images --repository-name $ECR_REPO_NAME --region $REGION \
    --query 'sort_by(imageDetails,&imagePushedAt)[-5:].[imageTags[0],imagePushedAt]' \
    --output table 2>/dev/null || echo "   Nenhuma imagem encontrada"
echo ""

# Resumo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ VALIDAÇÃO CONCLUÍDA COM SUCESSO"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Resumo do Deploy:"
echo "   Nova versão: $COMMIT_HASH"
echo "   Imagem: $ECR_REPO:$COMMIT_HASH"
echo "   Task: $TASK_FAMILY (nova revision será criada)"
echo "   Cluster: $CLUSTER"
echo "   Service: $SERVICE"
echo ""
echo "Para executar o deploy, rode:"
echo "   ./deploy-version.sh"
echo ""
