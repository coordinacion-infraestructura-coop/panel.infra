#!/usr/bin/env bash
# =============================================================================
# GestorCooperativo — Setup de Cloud SQL PostgreSQL
# Prerequisito: haber ejecutado gcp-setup.sh
# =============================================================================
set -euo pipefail

PROJECT_ID="gestorcooperativo"
REGION="southamerica-east1"
INSTANCE="ministerio-postgres"
TIER_DEV="db-f1-micro"    # desarrollo/staging
TIER_PROD="db-g1-small"   # producción

# Cambiar a TIER_PROD antes de ejecutar en producción
TIER="$TIER_DEV"

gcloud config set project "$PROJECT_ID"

# -----------------------------------------------------------------------------
# 1. Crear instancia Cloud SQL PostgreSQL 15
# -----------------------------------------------------------------------------
echo ">>> Creando instancia Cloud SQL: $INSTANCE (puede tardar 5-10 min)..."
gcloud sql instances create "$INSTANCE" \
  --database-version=POSTGRES_15 \
  --tier="$TIER" \
  --region="$REGION" \
  --no-assign-ip \
  --storage-type=SSD \
  --storage-size=10GB \
  --storage-auto-increase \
  --backup-start-time=03:00 \
  --maintenance-window-day=SUN \
  --maintenance-window-hour=4

echo ">>> Instancia creada: $INSTANCE"

# -----------------------------------------------------------------------------
# 2. Crear bases de datos (una por servicio — ADR-001)
# -----------------------------------------------------------------------------
DBS=(vivienda infraestructura territorial gasifera desarrollo)

for DB in "${DBS[@]}"; do
  echo ">>> Creando base de datos: db_${DB}"
  gcloud sql databases create "db_${DB}" \
    --instance="$INSTANCE" \
    --charset=UTF8 \
    --collation=es_AR.UTF-8
done

# -----------------------------------------------------------------------------
# 3. Crear usuarios de BD (uno por servicio)
# -----------------------------------------------------------------------------
echo ">>> Creando usuarios de base de datos..."
for SVC in "${DBS[@]}"; do
  PASSWORD=$(openssl rand -base64 32)
  echo ">>> Creando usuario: user_${SVC}"
  gcloud sql users create "user_${SVC}" \
    --instance="$INSTANCE" \
    --password="$PASSWORD"

  # Guardar la connection string en Secret Manager
  CONNECTION_NAME=$(gcloud sql instances describe "$INSTANCE" \
    --format="value(connectionName)")
  DB_URL="postgresql+asyncpg://user_${SVC}:${PASSWORD}@/db_${SVC}?host=/cloudsql/${CONNECTION_NAME}"

  echo ">>> Guardando secret: svc-${SVC}-db-url"
  echo -n "$DB_URL" | gcloud secrets create "svc-${SVC}-db-url" \
    --data-file=- \
    --replication-policy=automatic \
    --project="$PROJECT_ID" 2>/dev/null || \
  echo -n "$DB_URL" | gcloud secrets versions add "svc-${SVC}-db-url" \
    --data-file=-

  # Dar acceso al secret solo al service account correspondiente
  gcloud secrets add-iam-policy-binding "svc-${SVC}-db-url" \
    --member="serviceAccount:svc-${SVC}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor"
done

# -----------------------------------------------------------------------------
# 4. Otorgar permisos Cloud SQL al Cloud SQL Auth Proxy (via service accounts)
# -----------------------------------------------------------------------------
echo ">>> Los service accounts ya tienen roles/cloudsql.client (aplicado en gcp-setup.sh)"

echo ""
echo "=== Cloud SQL configurado ==="
echo "Instancia: $INSTANCE"
echo "Connection name: $(gcloud sql instances describe $INSTANCE --format='value(connectionName)')"
echo ""
echo "Para conectarse localmente con el proxy:"
echo "  cloud-sql-proxy ${PROJECT_ID}:${REGION}:${INSTANCE}"
echo "  PGPASSWORD=<password> psql -h 127.0.0.1 -U user_vivienda -d db_vivienda"
