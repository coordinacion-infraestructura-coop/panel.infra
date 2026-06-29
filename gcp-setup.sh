#!/usr/bin/env bash
# =============================================================================
# GestorCooperativo — Setup inicial del proyecto GCP
# Ejecutar UNA SOLA VEZ por un admin con permisos de Owner en la organización.
# =============================================================================
set -euo pipefail

PROJECT_ID="gestorcooperativo"
REGION="southamerica-east1"
BILLING_ACCOUNT="01A941-877E5E-3658BE"

# -----------------------------------------------------------------------------
# 1. Configurar el proyecto (ya creado manualmente)
# -----------------------------------------------------------------------------
echo ">>> Usando proyecto GCP existente: $PROJECT_ID"
gcloud config set project "$PROJECT_ID"
gcloud config set run/region "$REGION"

# Vincular cuenta de facturación si no está vinculada
BILLING_LINKED=$(gcloud billing projects describe "$PROJECT_ID" --format="value(billingEnabled)" 2>/dev/null || echo "False")
if [[ "$BILLING_LINKED" == "False" ]]; then
  echo ">>> Vinculando cuenta de facturación..."
  gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT"
else
  echo ">>> Billing ya vinculado, continuando..."
fi

# -----------------------------------------------------------------------------
# 2. Habilitar APIs
# -----------------------------------------------------------------------------
echo ">>> Habilitando APIs..."
gcloud services enable \
  run.googleapis.com \
  sql-component.googleapis.com \
  sqladmin.googleapis.com \
  apigateway.googleapis.com \
  servicemanagement.googleapis.com \
  servicecontrol.googleapis.com \
  pubsub.googleapis.com \
  secretmanager.googleapis.com \
  firebase.googleapis.com \
  identitytoolkit.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  cloudscheduler.googleapis.com \
  iam.googleapis.com \
  cloudresourcemanager.googleapis.com

echo ">>> APIs habilitadas."

# -----------------------------------------------------------------------------
# 3. Artifact Registry — repositorio Docker
# -----------------------------------------------------------------------------
echo ">>> Creando Artifact Registry..."
gcloud artifacts repositories create ministerio-docker \
  --repository-format=docker \
  --location="$REGION" \
  --description="Imágenes Docker del sistema ministerial"

# Configurar Docker para usar Artifact Registry
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet

# -----------------------------------------------------------------------------
# 4. Service Accounts (uno por servicio — mínimo privilegio)
# -----------------------------------------------------------------------------
echo ">>> Creando service accounts..."

SERVICES=(vivienda infraestructura territorial gasifera desarrollo)

for SVC in "${SERVICES[@]}"; do
  SA="svc-${SVC}@${PROJECT_ID}.iam.gserviceaccount.com"
  echo "  Creando: $SA"
  gcloud iam service-accounts create "svc-${SVC}" \
    --display-name="Servicio ${SVC^}" \
    --project="$PROJECT_ID"

  # Permisos mínimos por servicio
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$SA" \
    --role="roles/cloudsql.client"

  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$SA" \
    --role="roles/secretmanager.secretAccessor"

  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$SA" \
    --role="roles/pubsub.publisher"
done

# Service account del API Gateway
gcloud iam service-accounts create "api-gateway-sa" \
  --display-name="API Gateway" \
  --project="$PROJECT_ID"

GATEWAY_SA="api-gateway-sa@${PROJECT_ID}.iam.gserviceaccount.com"

# El API Gateway necesita invocar todos los Cloud Run services
for SVC in "${SERVICES[@]}"; do
  echo "  Otorgando run.invoker al gateway para svc-${SVC}..."
  # Se aplica al momento del deploy del servicio:
  # gcloud run services add-iam-policy-binding svc-$SVC \
  #   --member="serviceAccount:$GATEWAY_SA" \
  #   --role="roles/run.invoker" \
  #   --region="$REGION"
  echo "  PENDIENTE: aplicar después del deploy de svc-${SVC}"
done

# -----------------------------------------------------------------------------
# 5. Cloud Build — permisos para hacer deploy a Cloud Run
# -----------------------------------------------------------------------------
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")
CLOUDBUILD_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"

echo ">>> Otorgando permisos a Cloud Build SA: $CLOUDBUILD_SA"
for ROLE in \
  roles/run.admin \
  roles/iam.serviceAccountUser \
  roles/secretmanager.secretAccessor \
  roles/artifactregistry.writer; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$CLOUDBUILD_SA" \
    --role="$ROLE"
done

echo ""
echo "=== Setup inicial completado ==="
echo "Próximos pasos:"
echo "  1. Ejecutar: infra/cloudsql-setup.sh"
echo "  2. Ejecutar: infra/pubsub-setup.sh"
echo "  3. Configurar Firebase en: https://console.firebase.google.com"
echo "  4. Conectar repositorio GitHub con Cloud Build"
echo "  5. Desplegar API Gateway: infra/gateway/deploy-gateway.sh"
