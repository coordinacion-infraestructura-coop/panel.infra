#!/usr/bin/env bash
# =============================================================================
# GestorCooperativo — Deploy del API Gateway
# Prerequisito: haber ejecutado gcp-setup.sh y tener openapi.yaml configurado
# =============================================================================
set -euo pipefail

PROJECT_ID="gestorcooperativo"
REGION="us-central1"   # API Gateway no está disponible en southamerica-east1
API_ID="ministerio-api"
API_CONFIG_ID="ministerio-api-config-v2"
GATEWAY_ID="ministerio-gateway"
OPENAPI_FILE="$(dirname "$0")/openapi.yaml"

gcloud config set project "$PROJECT_ID"

echo ">>> Creando API en API Gateway..."
gcloud api-gateway apis create "$API_ID" \
  --project="$PROJECT_ID" 2>/dev/null || echo "API ya existe, continuando..."

echo ">>> Creando config del API Gateway..."
gcloud api-gateway api-configs create "$API_CONFIG_ID" \
  --api="$API_ID" \
  --openapi-spec="$OPENAPI_FILE" \
  --project="$PROJECT_ID" \
  --backend-auth-service-account="api-gateway-sa@${PROJECT_ID}.iam.gserviceaccount.com"

echo ">>> Creando/actualizando gateway..."
gcloud api-gateway gateways create "$GATEWAY_ID" \
  --api="$API_ID" \
  --api-config="$API_CONFIG_ID" \
  --location="$REGION" \
  --project="$PROJECT_ID" 2>/dev/null || \
gcloud api-gateway gateways update "$GATEWAY_ID" \
  --api="$API_ID" \
  --api-config="$API_CONFIG_ID" \
  --location="$REGION" \
  --project="$PROJECT_ID"

GATEWAY_URL=$(gcloud api-gateway gateways describe "$GATEWAY_ID" \
  --location="$REGION" \
  --project="$PROJECT_ID" \
  --format="value(defaultHostname)")

echo ""
echo "=== API Gateway desplegado ==="
echo "URL: https://${GATEWAY_URL}"
echo ""
echo "Próximos pasos:"
echo "  1. Configurar dominio custom: api.ministerio-coop.gob.ar"
echo "  2. Actualizar openapi.yaml con las URLs reales de Cloud Run (reemplazar REPLACE)"
echo "  3. Volver a ejecutar este script para actualizar la configuración"
echo "  4. Probar: curl -H 'Authorization: Bearer \$TOKEN' https://${GATEWAY_URL}/health"
