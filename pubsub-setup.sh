#!/usr/bin/env bash
# =============================================================================
# GestorCooperativo — Setup de Cloud Pub/Sub
# Prerequisito: haber ejecutado gcp-setup.sh
# =============================================================================
set -euo pipefail

PROJECT_ID="gestorcooperativo"
REGION="southamerica-east1"

gcloud config set project "$PROJECT_ID"

SECRETARIAS=(vivienda infraestructura territorial gasifera desarrollo)

# -----------------------------------------------------------------------------
# 1. Dead Letter Topic (debe crearse primero)
# -----------------------------------------------------------------------------
echo ">>> Creando dead letter topic..."
gcloud pubsub topics create ministerio-eventos-dl 2>/dev/null || echo "  (ya existe)"

gcloud pubsub subscriptions create dl-sub \
  --topic=ministerio-eventos-dl \
  --ack-deadline=60 2>/dev/null || echo "  dl-sub ya existe"

# -----------------------------------------------------------------------------
# 2. Tópicos por secretaría
# -----------------------------------------------------------------------------
echo ">>> Creando tópicos por secretaría..."
for SEC in "${SECRETARIAS[@]}"; do
  TOPIC="ministerio-eventos-${SEC}"
  echo "  Creando tópico: $TOPIC"
  gcloud pubsub topics create "$TOPIC" 2>/dev/null || echo "  (ya existe)"

  # Subscripción para BigQuery (a implementar con Dataflow/BigQuery subscription)
  echo "  Creando subscripción BigQuery: bigquery-sub-${SEC}"
  gcloud pubsub subscriptions create "bigquery-sub-${SEC}" \
    --topic="$TOPIC" \
    --ack-deadline=60 \
    --dead-letter-topic=ministerio-eventos-dl \
    --max-delivery-attempts=5 \
    --message-retention-duration=7d 2>/dev/null || echo "  (ya existe)"

  # Subscripción para svc-notificaciones (futuro)
  echo "  Creando subscripción notificaciones: notificaciones-sub-${SEC}"
  gcloud pubsub subscriptions create "notificaciones-sub-${SEC}" \
    --topic="$TOPIC" \
    --ack-deadline=30 \
    --dead-letter-topic=ministerio-eventos-dl \
    --max-delivery-attempts=5 2>/dev/null || echo "  (ya existe)"

  # Dar permisos de Publisher al service account del servicio correspondiente
  gcloud pubsub topics add-iam-policy-binding "$TOPIC" \
    --member="serviceAccount:svc-${SEC}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/pubsub.publisher"
done

# -----------------------------------------------------------------------------
# 3. Permisos sobre dead letter para todos los service accounts
# -----------------------------------------------------------------------------
for SEC in "${SECRETARIAS[@]}"; do
  gcloud pubsub topics add-iam-policy-binding ministerio-eventos-dl \
    --member="serviceAccount:svc-${SEC}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/pubsub.publisher"
done

echo ""
echo "=== Pub/Sub configurado ==="
echo "Tópicos creados:"
gcloud pubsub topics list --format="value(name)" | grep ministerio
