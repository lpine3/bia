#!/bin/bash
set -e

# Configurações
REGION="us-east-1"
CLUSTER="${CLUSTER:-cluster-bia}"
SERVICE="${SERVICE:-service-bia}"
TASK_FAMILY="${TASK_FAMILY:-task-def-bia}"

echo "=== Rollback BIA ==="
echo ""

# Obter revisão atual
CURRENT_REVISION=$(aws ecs describe-services --cluster $CLUSTER --services $SERVICE --region $REGION --query 'services[0].taskDefinition' --output text | grep -oP ':\K[0-9]+$')
echo "📌 Revisão atual: $TASK_FAMILY:$CURRENT_REVISION"
echo ""

# Listar últimas 10 revisões
echo "📋 Revisões disponíveis:"
echo ""
REVISIONS=$(aws ecs list-task-definitions --family-prefix $TASK_FAMILY --region $REGION --sort DESC --max-items 10 --query 'taskDefinitionArns' --output text)

if [ -z "$REVISIONS" ]; then
    echo "❌ Nenhuma revisão encontrada"
    exit 1
fi

# Mostrar revisões com detalhes
counter=1
declare -A revision_map
for arn in $REVISIONS; do
    rev=$(echo $arn | grep -oP ':\K[0-9]+$')
    image=$(aws ecs describe-task-definition --task-definition $TASK_FAMILY:$rev --region $REGION --query 'taskDefinition.containerDefinitions[0].image' --output text)
    tag=$(echo $image | grep -oP ':[^:]+$' | tr -d ':')
    
    if [ "$rev" == "$CURRENT_REVISION" ]; then
        echo "  $counter) Revisão $rev (ATUAL) - Tag: $tag"
    else
        echo "  $counter) Revisão $rev - Tag: $tag"
    fi
    
    revision_map[$counter]=$rev
    counter=$((counter + 1))
done

echo ""
read -p "Escolha o número da revisão para rollback (ou Enter para cancelar): " choice

if [ -z "$choice" ]; then
    echo "❌ Rollback cancelado"
    exit 0
fi

# Validar escolha
if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ -z "${revision_map[$choice]}" ]; then
    echo "❌ Opção inválida"
    exit 1
fi

TARGET_REVISION=${revision_map[$choice]}

if [ "$TARGET_REVISION" == "$CURRENT_REVISION" ]; then
    echo "❌ Revisão escolhida já está em uso"
    exit 1
fi

TARGET_IMAGE=$(aws ecs describe-task-definition --task-definition $TASK_FAMILY:$TARGET_REVISION --region $REGION --query 'taskDefinition.containerDefinitions[0].image' --output text)

echo ""
echo "🔄 Rollback para: $TASK_FAMILY:$TARGET_REVISION"
echo "   Imagem: $TARGET_IMAGE"
echo ""

read -p "Confirma rollback? (s/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Ss]$ ]]; then
    echo "❌ Rollback cancelado"
    exit 0
fi

# Executar rollback
echo "🔄 Executando rollback..."
aws ecs update-service --region $REGION --cluster $CLUSTER --service $SERVICE --task-definition $TASK_FAMILY:$TARGET_REVISION --query 'service.taskDefinition' --output text

echo ""
echo "✅ Rollback concluído!"
echo "   De: $TASK_FAMILY:$CURRENT_REVISION"
echo "   Para: $TASK_FAMILY:$TARGET_REVISION"
echo "   Cluster: $CLUSTER"
echo "   Service: $SERVICE"
