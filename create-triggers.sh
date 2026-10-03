#!/bin/bash
# Script para crear/actualizar Cloud Build triggers en GestorCooperativo
# Uso: bash infra/create-triggers.sh

set -e

PROJECT="gestorcooperativo"
REPO_NAME="panel.backend"
REPO_OWNER="coordinacion-infraestructura-coop"
BRANCH_PATTERN="^main$"
CONFIG_PATH="services/cloudbuild.yaml"

SERVICES=(
  "svc-vivienda"
  "svc-privada"
  "svc-gasifera"
  "svc-gralgob"
  "svc-datos-externos"
)

echo "=================================================="
echo "GestorCooperativo — Cloud Build Triggers Setup"
echo "=================================================="
echo ""
echo "Proyecto: $PROJECT"
echo "Repo: $REPO_OWNER/$REPO_NAME"
echo "Branch: $BRANCH_PATTERN"
echo "Config: $CONFIG_PATH"
echo ""

# Función para crear o actualizar un trigger
create_trigger() {
  local SERVICE=$1
  local TRIGGER_NAME="deploy-${SERVICE}"
  
  echo "🔨 Creando trigger: $TRIGGER_NAME"
  
  gcloud builds triggers create github \
    --repo-name="$REPO_NAME" \
    --repo-owner="$REPO_OWNER" \
    --branch-pattern="$BRANCH_PATTERN" \
    --build-config="$CONFIG_PATH" \
    --substitutions="_SERVICE=${SERVICE}" \
    --name="$TRIGGER_NAME" \
    --project="$PROJECT" \
    --included-files="services/${SERVICE}/**" \
    2>&1 || echo "⚠️  Trigger $TRIGGER_NAME ya existe o error de creación"
  
  echo ""
}

# Crear cada trigger
for SERVICE in "${SERVICES[@]}"; do
  create_trigger "$SERVICE"
done

echo "=================================================="
echo "✅ Triggers creados/actualizados"
echo "=================================================="
echo ""
echo "Verificar triggers:"
echo "  gcloud builds triggers list --project=$PROJECT --format=\"table(name,substitutions._SERVICE)\""
echo ""
echo "Ver logs de un build:"
echo "  gcloud builds log <BUILD_ID> --project=$PROJECT"
echo ""
echo "Ver lista de builds recientes:"
echo "  gcloud builds list --project=$PROJECT --limit=10"
