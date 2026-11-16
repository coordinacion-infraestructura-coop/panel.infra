# Deploy — Exportación de pagos de Vivienda a la planilla de Gobierno Abierto

Spec: `docs/files/spec-export-gobierno-abierto-vivienda.md` · ADR-034 · migración `0047`.

No hay cambios de gateway ni de frontend.

## 0. Precondición: planilla compartida como Editor

El dueño de la planilla (`infraestructura.coop@gmail.com`) la comparte con:

**`svc-vivienda@gestorcooperativo.iam.gserviceaccount.com`** → rol **Editor**, sin notificar.

Planilla: `https://docs.google.com/spreadsheets/d/1aRmMDPySFH62TVjO4t4cPUVmvuMO2E5dcQVm_dYYQtE`.
La pestaña tiene que llamarse exactamente **Vivienda** (si cambia, ajustar
`GOBABIERTO_SHEET_TAB`). Recomendado: proteger la pestaña (Datos → Proteger hojas y rangos) para
que solo la editen esa cuenta y el dueño.

## 1. Migración (Cloud Shell, desde `svc-vivienda/`)

```bash
~/cloud-sql-proxy gestorcooperativo:southamerica-east1:ministerio-postgres --port 5432 > /tmp/proxy.log 2>&1 &
sleep 4 && cat /tmp/proxy.log
cd ~/gestorcooperativo/backend/svc-vivienda && git pull origin main
export DATABASE_URL="postgresql+asyncpg://user_vivienda:PASS@127.0.0.1:5432/db_vivienda"
python -m alembic upgrade head   # 0046 -> 0047 (crea viv_gobabierto_sync_log)
python -m alembic current        # debe decir 0047
```

## 2. Deploy de svc-vivienda

El merge a `main` dispara `deploy-svc-vivienda`. `services/cloudbuild.yaml` ya trae
`_GOBABIERTO_EXPORT_ENABLED=true` y `_GOBABIERTO_SHEET_ID`. Verificar:

```bash
gcloud run services describe svc-vivienda --region=southamerica-east1 --project=gestorcooperativo \
  --format="value(spec.template.spec.containers[0].env)" | tr ';' '\n' | grep GOBABIERTO
```

## 3. Primera corrida manual

```bash
SVC_URL=https://svc-vivienda-iwni7vc2qq-rj.a.run.app
curl -s -X POST -d "" -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  "${SVC_URL}/internal/gobierno-abierto/vivienda/sync?triggered_by=manual"
# -> {"filas": N}. 502 = no pudo escribir (¿planilla compartida como Editor?). 503 = flag apagado.
```

Revisar la pestaña Vivienda y el log:

```sql
SELECT started_at, origen, ok, filas, error FROM viv_gobabierto_sync_log ORDER BY started_at DESC LIMIT 5;
```

## 4. Cloud Scheduler cada hora

Mismo patrón que `mi-lugar-valuacion-idecor` (OIDC con la SA de svc-vivienda, que ya tiene
`run.invoker` y `serviceAccountTokenCreator` sobre sí misma).

```bash
SVC_URL=https://svc-vivienda-iwni7vc2qq-rj.a.run.app
gcloud scheduler jobs create http sync-gobabierto-vivienda \
  --location=southamerica-east1 \
  --schedule="5 * * * *" --time-zone="America/Argentina/Cordoba" \
  --uri="${SVC_URL}/internal/gobierno-abierto/vivienda/sync" \
  --http-method=POST \
  --attempt-deadline=300s \
  --oidc-service-account-email="svc-vivienda@gestorcooperativo.iam.gserviceaccount.com" \
  --oidc-token-audience="${SVC_URL}" \
  --project=gestorcooperativo
gcloud scheduler jobs run sync-gobabierto-vivienda --location=southamerica-east1 --project=gestorcooperativo
```

Si una corrida horaria falla, llega una notificación a los Admin del portal.

## Rollback

`gcloud run services update svc-vivienda --region=southamerica-east1 --update-env-vars=GOBABIERTO_EXPORT_ENABLED=false`
(y `gcloud scheduler jobs pause sync-gobabierto-vivienda`). La planilla queda con el último
contenido escrito.
