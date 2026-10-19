# Deploy — Mi Lugar: valor fiscal sugerido y valor de mercado desde IDECOR

Spec: `docs/files/spec-mi-lugar-valor-fiscal-idecor.md` (approved v1.0.0) · ADR-031.

Toca 4 repos: `services/` (svc-datos-externos + svc-vivienda + `cloudbuild.yaml`), `frontend/`,
`infra/` (gateway) y `docs/`. Rama `mi-lugar-valuacion-idecor` en los tres de código.

**El orden importa**: la migración va antes de que el código nuevo de svc-vivienda quede en
producción (el listado de Mi Lugar lee las tablas nuevas). svc-datos-externos va antes que
svc-vivienda, para que el primer recálculo encuentre el endpoint.

## 0. Antes del deploy

- [ ] Confirmar con IDECOR o con el área que `vur_pesos` de `valor_tierra_rural_AAAA` está en
      **$/ha** (spec §4.2, criterio de aceptación 4). Si fuera otra unidad, corregir
      `_M2_POR_HA` en `svc-datos-externos/app/catastro/service.py` antes de seguir.

## 1. Migración 0043 (Cloud Shell, desde `svc-vivienda/`)

Solo crea `viv_ml_nomenclaturas` y `viv_ml_valuacion_idecor`; no toca tablas existentes, así que
es segura con el código viejo todavía corriendo.

```bash
~/cloud-sql-proxy gestorcooperativo:southamerica-east1:ministerio-postgres --port 5432 > /tmp/proxy.log 2>&1 &
sleep 4 && cat /tmp/proxy.log            # "Listening on 127.0.0.1:5432"
cd ~/gestorcooperativo/backend/svc-vivienda && git pull origin main
export DATABASE_URL="postgresql+asyncpg://user_vivienda:PASS@127.0.0.1:5432/db_vivienda"
python -m alembic upgrade head
python -m alembic current                # 0043 (head)
```

## 2. Backend (merge a `main` de `panel.backend`)

Los triggers de Cloud Build despliegan por separado (`deploy-svc-datos-externos` se dispara por
cambios en `svc-datos-externos/**`; `deploy-svc-vivienda`, en cada push). `cloudbuild.yaml` ya
lleva `_VALUACION_IDECOR_ENABLED: "true"`.

Verificar después del deploy:

```bash
gcloud run services describe svc-vivienda --region=southamerica-east1 --project=gestorcooperativo \
  --format="value(spec.template.spec.containers[0].env)" | tr ';' '\n' | grep -i VALUACION
```

No hace falta un grant nuevo: `svc-vivienda@` ya es invoker de `svc-datos-externos` (ADR-025).

## 3. Gateway

Un path nuevo: `POST /api/v1/vivienda/mi-lugar/proyectos/{proyecto_id}/valuacion-idecor` (+ su
`options`). Config activa antes de este deploy: `ministerio-config-v20261016`.

```bash
cd ~/panel.infra/gateway && git pull origin main
gcloud api-gateway api-configs create ministerio-config-v20261019 \
  --api=ministerio-api --openapi-spec=openapi.yaml --project=gestorcooperativo \
  --backend-auth-service-account=api-gateway-sa@gestorcooperativo.iam.gserviceaccount.com
gcloud api-gateway gateways update ministerio-gateway \
  --api=ministerio-api --api-config=ministerio-config-v20261019 \
  --location=us-central1 --project=gestorcooperativo
```

(Si ya existe una config con esa fecha, usar el sufijo de letra: `v20261019b`.)

## 4. Cloud Scheduler semanal

Mismo patrón que `resumen-territorial-refresh` (OIDC con la SA de svc-vivienda; esa SA ya tiene
`run.invoker` y `serviceAccountTokenCreator` sobre sí misma).

```bash
SVC_URL=https://svc-vivienda-iwni7vc2qq-rj.a.run.app
gcloud scheduler jobs create http mi-lugar-valuacion-idecor \
  --location=southamerica-east1 \
  --schedule="0 6 * * 1" --time-zone="America/Argentina/Cordoba" \
  --uri="${SVC_URL}/internal/mi-lugar/valuacion-idecor/actualizar" \
  --http-method=POST \
  --attempt-deadline=600s \
  --oidc-service-account-email="svc-vivienda@gestorcooperativo.iam.gserviceaccount.com" \
  --oidc-token-audience="${SVC_URL}" \
  --project=gestorcooperativo

# Primera carga, sin esperar al lunes:
gcloud scheduler jobs run mi-lugar-valuacion-idecor --location=southamerica-east1 --project=gestorcooperativo
```

La respuesta (en los logs de svc-vivienda) trae `{"proyectos": N, "por_estado": {...},
"con_error_en_esta_corrida": M}`.

## 5. Frontend

```bash
cd frontend && npm run build && firebase deploy --only hosting
```

## 6. Verificación (spec §8)

1. En la pestaña Expropiación, Villa María y Estación Juárez Celman muestran "= coincide".
2. Audit log: ningún `UPDATE` de `valor_fiscal` hecho por `cloud-scheduler`.
3. Botón "Recalcular" en el modal de edición responde y refresca la sugerencia.
4. Excel trae las columnas "Valor Fiscal IDECOR ($)" y "Valor referencia de mercado ($)".
5. Verificación visual del área.

## Rollback

- Apagar la consulta sin redeploy de código:
  `gcloud run services update svc-vivienda --update-env-vars=VALUACION_IDECOR_ENABLED=false ...`
  (las columnas quedan con el último valor guardado).
- Pausar el job: `gcloud scheduler jobs pause mi-lugar-valuacion-idecor --location=southamerica-east1`.
- La migración 0043 tiene downgrade (borra las dos tablas nuevas, sin tocar `valor_fiscal`).
