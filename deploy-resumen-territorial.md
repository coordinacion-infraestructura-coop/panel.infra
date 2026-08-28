# Deploy — Módulo Resumen Territorial

Spec: `docs/files/spec-resumen-territorial.md`. Todo lo que sigue se corre en **Cloud Shell**
(proyecto `gestorcooperativo`, región `southamerica-east1`).

Orden: **1) migración → 2) backend → 3) gateway → 4) Cloud Scheduler → 5) carga inicial → 6) frontend**.

---

## 1. Migración Alembic (`0023`)

```bash
# Proxy a Cloud SQL
cloud-sql-proxy gestorcooperativo:southamerica-east1:ministerio-postgres --port=5432 &
sleep 4

cd ~/gestorcooperativo/backend/svc-vivienda   # o donde esté el checkout de panel.backend
git pull origin_back main   # rama/remote según el checkout

PASS=$(gcloud secrets versions access latest --secret="svc-vivienda-db-url" --project=gestorcooperativo)
# el secret ya viene como postgresql+asyncpg://... apuntando al socket; para el proxy TCP:
DATABASE_URL="postgresql+asyncpg://user_vivienda:<PASS_URL_ENCODED>@127.0.0.1:5432/db_vivienda" \
  python -m alembic upgrade head

python -m alembic current   # debe mostrar 0023
```

Crea `viv_resumen_territorial_snapshot` + índice `ix_resumen_territorial_snapshot_fecha`.

## 2. Deploy backend

```bash
cd ~/gestorcooperativo/backend/svc-vivienda
gcloud run deploy svc-vivienda --source . \
  --region=southamerica-east1 --project=gestorcooperativo
```

(El deploy trae el módulo `app/resumen_territorial/`, el endpoint interno y el rol `Autoridad`
en `ROLES_VALIDOS`. No hace falta tocar env vars — `gateway_base_url` y `privada_resumen_path`
tienen default en `config.py`; si el `audience` del gateway resultara distinto, setear
`PRIVADA_GATEWAY_AUDIENCE` como env var.)

Verificación directa (sin gateway):

```bash
TOKEN=$(gcloud auth print-identity-token)
curl -s -X POST -H "Authorization: Bearer $TOKEN" \
  "$(gcloud run services describe svc-vivienda --region=southamerica-east1 \
      --project=gestorcooperativo --format='value(status.url)')/internal/resumen-territorial/actualizar"
# → {"computed_at": ..., "total_localidades": N, "generado_para_areas": ["vivienda", ...]}
```

## 3. API Gateway — nueva config

`infra/gateway/openapi.yaml` ya tiene los 2 paths nuevos (`/api/v1/resumen-territorial` GET +
`/actualizar` POST, con sus `options:`). Esta config **también publica** los paths de
`checklist-tecnico` y `/informe` que estaban commiteados sin deployar (coordinado, ver spec §11).

```bash
cd ~/panel.infra/gateway && git pull origin_infra main

CFG=ministerio-config-v20260828
gcloud api-gateway api-configs create "$CFG" \
  --api=ministerio-api --openapi-spec=openapi.yaml \
  --project=gestorcooperativo \
  --backend-auth-service-account=api-gateway-sa@gestorcooperativo.iam.gserviceaccount.com

gcloud api-gateway gateways update ministerio-gateway \
  --api=ministerio-api --api-config="$CFG" \
  --location=us-central1 --project=gestorcooperativo
```

Si `api-configs create` da `ALREADY_EXISTS`, incrementar la letra (`...v20260828b`).
Actualizar en el `CLAUDE.md` raíz la línea "Current active gateway config".

Verificación vía gateway (con un JWT de Firebase real):

```bash
curl -s -H "Authorization: Bearer $FIREBASE_JWT" \
  "https://ministerio-gateway-3j5k00ma.uc.gateway.dev/api/v1/resumen-territorial"
```

## 4. Cloud Scheduler

`svc-vivienda@…` ya tiene `roles/run.invoker` sobre sí mismo (lo dejó el sync de checklist CC).
Sólo el job:

```bash
SVC_URL=$(gcloud run services describe svc-vivienda --region=southamerica-east1 \
  --project=gestorcooperativo --format='value(status.url)')

gcloud scheduler jobs create http resumen-territorial-refresh \
  --location=southamerica-east1 \
  --schedule="*/30 * * * *" \
  --uri="${SVC_URL}/internal/resumen-territorial/actualizar" \
  --http-method=POST \
  --oidc-service-account-email="svc-vivienda@gestorcooperativo.iam.gserviceaccount.com" \
  --oidc-token-audience="${SVC_URL}" \
  --project=gestorcooperativo
```

## 5. Carga inicial

```bash
gcloud scheduler jobs run resumen-territorial-refresh --location=southamerica-east1 \
  --project=gestorcooperativo
```

Confirmar que quedó una fila en `viv_resumen_territorial_snapshot` con
`computed_by = 'cloud-scheduler'`.

## 6. Frontend

```bash
cd ~/gestorcooperativo/frontend   # checkout de panel.front
git pull origin main
npm run build && firebase deploy --only hosting --project gestorcooperativo
```

---

## Notas

- El endpoint interno `POST /internal/resumen-territorial/actualizar` **no** está en
  `openapi.yaml` a propósito — sólo lo alcanza Cloud Scheduler por IAM (mismo patrón que
  `/internal/sync/cordon-cuneta-checklist`).
- El fetch de Privada (`fetch_privada_lineas`) es **tolerante**: si el gateway/svc-privada no
  responde o la forma no es la esperada, el snapshot se guarda sólo con Vivienda y
  `generado_para_areas` no incluye `"privada"`. Revisar los logs de Cloud Run
  (`resumen_territorial: fetch de Privada falló`) tras la primera corrida para confirmar el
  contrato real del endpoint `/api/v1/privada/gestiones/resumen-territorial` y ajustar
  `_map_privada_payload` si hace falta.
