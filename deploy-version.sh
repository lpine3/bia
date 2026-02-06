#!/bin/bash
set -e

# Configurações
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO_NAME="bia"
ECR_REPO="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$ECR_REPO_NAME"
CLUSTER="${CLUSTER:-cluster-bia}"
SERVICE="${SERVICE:-service-bia}"
TASK_FAMILY="${TASK_FAMILY:-task-def-bia}"

# Obter commit hash
COMMIT_HASH=$(git rev-parse --short=7 HEAD)
IMAGE_TAG="$COMMIT_HASH"

echo "=== Deploy BIA - Versão $IMAGE_TAG ==="

# 1. Login ECR
echo "[1/5] Login no ECR..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REPO

# 2. Build
echo "[2/5] Build da imagem..."
docker build -t $ECR_REPO:$IMAGE_TAG -t $ECR_REPO:latest .

# 3. Push
echo "[3/5] Push para ECR..."
docker push $ECR_REPO:$IMAGE_TAG
docker push $ECR_REPO:latest

# 4. Criar Task Definition
echo "[4/5] Criando task definition..."
TASK_DEF=$(aws ecs describe-task-definition --task-definition $TASK_FAMILY --region $REGION)
NEW_TASK_DEF=$(echo "$TASK_DEF" | jq --arg img "$ECR_REPO:$IMAGE_TAG" '
  .taskDefinition |
  .containerDefinitions[0].image = $img |
  del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy)
')
echo "$NEW_TASK_DEF" > /tmp/task-def.json
NEW_REVISION=$(aws ecs register-task-definition --region $REGION --cli-input-json file:///tmp/task-def.json --query 'taskDefinition.revision' --output text)
rm /tmp/task-def.json

echo "Task Definition criada: $TASK_FAMILY:$NEW_REVISION"

# 5. Deploy
echo "[5/5] Atualizando serviço ECS..."
aws ecs update-service --region $REGION --cluster $CLUSTER --service $SERVICE --task-definition $TASK_FAMILY:$NEW_REVISION --query 'service.taskDefinition' --output text

echo ""
echo "✅ Deploy concluído!"
echo "   Versão: $IMAGE_TAG"
echo "   Task: $TASK_FAMILY:$NEW_REVISION"
echo "   Cluster: $CLUSTER"
echo "   Service: $SERVICE"
