# Deploy de svc-privada (servicio nuevo) — runbook Cloud Shell

Ejecutar en **Cloud Shell del proyecto `gestorcooperativo`**, en orden.
`deploy_simple.md` NO aplica (es para redeploy de un servicio existente).

Convenciones:
- Instancia Cloud SQL: `gestorcooperativo:southamerica-east1:ministerio-postgres`
- Ajustá las rutas de los clones si difieren (`~/gestorcooperativo/backend` = repo `panel.backend`,
  `~/gestorcooperativo/infra` = repo `gestor.infra`/`panel.infra`).

```bash
gcloud config set project gestorcooperativo
CONN="gestorcooperativo:southamerica-east1:ministerio-postgres"
SA="svc-privada@gestorcooperativo.iam.gserviceaccount.com"
VIVIENDA_URL="https://svc-vivienda-iwni7vc2qq-rj.a.run.app"
```

---

## Fase A — Provisionar BD + SA + secreto (one-time)

```bash
# A.1 — base de datos
gcloud sql databases create db_privada --instance=ministerio-postgres --charset=UTF8

# A.2 — usuario con password URL-safe (hex, sin +/= para no romper la connection string)
PRIV_PW=$(openssl rand -hex 24)
gcloud sql users create user_privada --instance=ministerio-postgres --password="$PRIV_PW"

# A.3 — secreto con la connection string (formato socket, lo lee Cloud Run)
printf '%s' "postgresql+asyncpg://user_privada:${PRIV_PW}@/db_privada?host=/cloudsql/${CONN}" \
  | gcloud secrets create svc-privada-db-url --data-file=- --replication-policy=automatic

# A.4 — service account de runtime + permisos
gcloud iam service-accounts create svc-privada --display-name="svc-privada runtime"
gcloud projects add-iam-policy-binding gestorcooperativo \
  --member="serviceAccount:${SA}" --role="roles/cloudsql.client"
gcloud secrets add-iam-policy-binding svc-privada-db-url \
  --member="serviceAccount:${SA}" --role="roles/secretmanager.secretAccessor"

# A.5 — guardá el DATABASE_URL en formato TCP para migraciones y ETL
export DATABASE_URL="postgresql+asyncpg://user_privada:${PRIV_PW}@127.0.0.1:5432/db_privada"
echo "$DATABASE_URL"   # anotalo por si abrís otra terminal
```

> Si perdés `$PRIV_PW`: `gcloud secrets versions access latest --secret=svc-privada-db-url`
> y cambiás `@/db_privada?host=...` por `@127.0.0.1:5432/db_privada`.

---

## Fase B — Migración Alembic

```bash
# B.1 — proxy
~/cloud-sql-proxy "$CONN" --port 5432 > /tmp/proxy_privada.log 2>&1 &
sleep 4 && cat /tmp/proxy_privada.log   # "Listening on 127.0.0.1:5432"

# B.2 — código + deps EN UN VENV (Cloud Shell trae un entorno global enorme de
#        tooling de IA de Google; instalar ahí downgradea pydantic/httpx/google-auth
#        y rompe esas CLIs. El venv lo aísla.)
cd ~/gestorcooperativo/backend/svc-privada
git pull origin main
python3 -m venv .venv
source .venv/bin/activate           # <- reactivar con esto si abrís otra terminal
pip install -e ".[dev,etl]"

# B.3 — aplicar (DATABASE_URL ya exportado en A.5, con el venv activo)
python -m alembic upgrade head
python -m alembic current      # debe mostrar: 0001 (head)
```

---

## Fase C — ETL BigQuery → PostgreSQL

```bash
cd ~/gestorcooperativo/backend/svc-privada
source .venv/bin/activate            # el venv de la Fase B
export BQ_PROJECT=essential-haiku-482815-u4

# C.1 — dry-run (no escribe): validar el reporte de conteos
python scripts/migrar_desde_bigquery.py --dry-run
#   esperado: gestiones 2123 / borradas 136 / eventos 166 / eventos_huerfanos 0
#             localidades_info 426 / departamentos_info 25 / fecha_finalizacion_backfill 110

# C.2 — carga real
python scripts/migrar_desde_bigquery.py --truncate
#   verificación: gestiones_total 2123 / activas 1987 / finalizadas 110
#                 finalizadas_sin_fecha 0  <- RE-9 corregido
#                 eventos 166 / localidades_info 426 / departamentos_info 25 / geo 551
```

> Si Cloud Shell no tiene credenciales para BigQuery del proyecto viejo:
> `gcloud auth application-default login` (con la cuenta que ve `essential-haiku-482815-u4`).

Cortá el proxy cuando termines: `kill %1` (o `jobs` para ver el número).

---

## Fase D — Cloud Run (primer deploy: flags explícitos)

```bash
cd ~/gestorcooperativo/backend/svc-privada
git pull origin main

gcloud run deploy svc-privada \
  --source . \
  --region=southamerica-east1 \
  --no-allow-unauthenticated \
  --service-account="$SA" \
  --set-secrets=DATABASE_URL=svc-privada-db-url:latest \
  --set-env-vars="GCP_PROJECT_ID=gestorcooperativo,SERVICE_NAME=svc-privada,ENVIRONMENT=production,SVC_VIVIENDA_INTERNAL_URL=${VIVIENDA_URL}" \
  --add-cloudsql-instances="$CONN" \
  --memory=512Mi --cpu=1 --min-instances=0 --max-instances=10 --concurrency=80

# URL del servicio nuevo (la vas a necesitar para el gateway)
PRIVADA_URL=$(gcloud run services describe svc-privada --region=southamerica-east1 --format='value(status.url)')
echo "$PRIVADA_URL"

# health (403 sin token es normal)
curl -s -H "Authorization: Bearer $(gcloud auth print-identity-token)" "$PRIVADA_URL/health"
#   esperado: {"status":"ok","service":"svc-privada","version":"0.1.0"}
```

---

## Fase E — IAM (run.invoker)

```bash
# E.1 — svc-privada puede llamar al endpoint interno de svc-vivienda (auth, ADR-015)
gcloud run services add-iam-policy-binding svc-vivienda --region=southamerica-east1 \
  --member="serviceAccount:${SA}" --role="roles/run.invoker"

# E.2 — el API Gateway puede llamar a svc-privada
gcloud run services add-iam-policy-binding svc-privada --region=southamerica-east1 \
  --member="serviceAccount:api-gateway-sa@gestorcooperativo.iam.gserviceaccount.com" \
  --role="roles/run.invoker"
```

Smoke del endpoint interno (desde otra terminal de Cloud Shell, con tu usuario que
NO tiene invoker — debería dar 403; el 200 sólo lo obtiene la SA de svc-privada):
```bash
curl -s -o /dev/null -w "%{http_code}\n" "$VIVIENDA_URL/internal/portal/usuarios/test@x.com"
#   403 = OK (protegido por IAM). Que svc-privada lo consuma bien se valida en el smoke del portal.
```

---

## Fase F — Gateway (cutover)

Editar `infra/gateway/openapi.yaml` siguiendo **`infra/gateway/CUTOVER-svc-privada.md`**:
repuntar `address`/`jwt_audience` de `/api/v1/privada/**` a `$PRIVADA_URL`, borrar los 4 paths
`/api/v1/privada/usuarios/**`, y agregar `PATCH /gestiones/{gestion_id}`,
`/gestiones/rollup-territorial`, `/departamentos-info` y los 4 `/informe/cooperativas/*`.

```bash
# ...editar openapi.yaml (local o en Cloud Shell), commitear y pushear a gestor.infra...

cd ~/gestorcooperativo/infra/gateway
git pull origin main
grep -c 'operationId: cors' openapi.yaml   # debería subir (~ +7 paths nuevos)

FECHA=$(date +%Y%m%d)
gcloud api-gateway api-configs create ministerio-config-v${FECHA} \
  --api=ministerio-api --openapi-spec=openapi.yaml \
  --backend-auth-service-account=api-gateway-sa@gestorcooperativo.iam.gserviceaccount.com

gcloud api-gateway gateways update ministerio-gateway \
  --api=ministerio-api --api-config=ministerio-config-v${FECHA} --location=us-central1

# esperar ~5 min, luego smoke por el gateway
GW="https://ministerio-gateway-3j5k00ma.uc.gateway.dev"
TOKEN="<ID token Firebase de un usuario con secretaría privada>"
curl -s "$GW/api/v1/privada/gestiones?limit=1"                    -H "Authorization: Bearer $TOKEN"
curl -s "$GW/api/v1/privada/me"                                   -H "Authorization: Bearer $TOKEN"
curl -s "$GW/api/v1/privada/informe/cooperativas/resumen"         -H "Authorization: Bearer $TOKEN"
curl -s "$GW/api/v1/privada/gestiones/rollup-territorial"         -H "Authorization: Bearer $TOKEN"
```

**Rollback**: `gcloud api-gateway gateways update ministerio-gateway --api=ministerio-api --api-config=ministerio-config-v20260716b --location=us-central1`

---

## Fase G — Alta de usuarios en portal_usuarios

Los usuarios de Privada (`anexos/C_usuarios_roles.csv`, 17 filas — revisar los 4 gateway/test con
`Admin`) se dan de alta en `portal_usuarios` (db_vivienda). Vía `AdminUsuariosPage` del portal, o
por SQL directo contra `db_vivienda` con el proxy, o un script. Cada uno con secretaría `privada`.

---

## §E5a — Federación server-side de Privada en Resumen Territorial (ADR-016)

Código en `panel.backend` `2f48a55` + `panel.front` `6791757`. Reemplaza el merge client-side
(`privadaGestiones.ts`) por líneas de Privada en el snapshot server-side de `resumen_territorial`.

```bash
gcloud config set project gestorcooperativo
VIV_SA="svc-vivienda@gestorcooperativo.iam.gserviceaccount.com"
PRIVADA_URL="https://svc-privada-iwni7vc2qq-rj.a.run.app"

# 1. la SA de svc-vivienda puede invocar svc-privada (para el endpoint interno)
gcloud run services add-iam-policy-binding svc-privada --region=southamerica-east1 \
  --member="serviceAccount:${VIV_SA}" --role="roles/run.invoker"

# 2. redeploy de svc-privada (trae GET /internal/privada/rollup-territorial)
#    Usar `run deploy --source .` desde el dir del servicio: reconstruye la imagen y
#    CONSERVA la config (SA, secretos, Cloud SQL, env). `gcloud builds submit --config`
#    a mano deja ${SHORT_SHA} vacío -> "invalid image name ...:".
cd ~/gestorcooperativo/backend && git pull origin main
cd svc-privada
gcloud run deploy svc-privada --source . --region=southamerica-east1
#    check: 403 = endpoint interno existe (lo bloquea IAM); 404 = no se desplegó
curl -s -o /dev/null -w "%{http_code}\n" "${PRIVADA_URL}/internal/privada/rollup-territorial"

# 3. redeploy de svc-vivienda con la federación server-side encendida
#    --update-env-vars MERGEA (no borra GOOGLE_SHEET_CC_ID, etc.)
cd ~/gestorcooperativo/backend/svc-vivienda
gcloud run deploy svc-vivienda --source . --region=southamerica-east1 \
  --update-env-vars=PRIVADA_FETCH_ENABLED=true,SVC_PRIVADA_INTERNAL_URL=${PRIVADA_URL}

# 4. frontend: rebuild + deploy (el merge client-side de Privada ya está OFF por
#    default desde el commit ba70889 — NO hay que tocar .env). Hard-refresh después.
cd ~/gestorcooperativo/frontend && git pull origin main
npm run build && firebase deploy --only hosting

# 5. recomputar el snapshot y verificar
GW="https://ministerio-gateway-3j5k00ma.uc.gateway.dev"
curl -s -X POST "$GW/api/v1/resumen-territorial/actualizar" -H "Authorization: Bearer $TOKEN"
curl -s "$GW/api/v1/resumen-territorial" -H "Authorization: Bearer $TOKEN" | python3 -m json.tool | grep -A3 generado_para_areas
#   debe incluir "privada"; las líneas privada NO deben aparecer duplicadas
```

**Rollback**: redeploy svc-vivienda con `--update-env-vars=PRIVADA_FETCH_ENABLED=false` **y**
rebuild del frontend con `VITE_PRIVADA_CLIENT_FEDERATION=true` en `.env.production` → vuelve al
merge client-side.

## §7 — Tablero nativo (gate del decommission de BigQuery)

`TableroPage.tsx` ya es nativo (`panel.front` `6791757`) — sale con el deploy normal del frontend.
Antes de apagar BigQuery: comparar KPIs del tablero nuevo contra el Looker `f9dc4a4e-…` para un
rango de fechas de control (criterio de `spec-privada-tablero.md §6`).

## §D+E1+E2 — Catálogos editables + Ok Gob/Min + mejoras de lista (2026-09-02)

Migración `0002` (nuevas tablas + columnas) + backfill + config de gateway nueva. `panel.backend`
hasta `1b20f70`, `panel.front` `92422d5`, `panel.infra` `bbbf57c`.

```bash
gcloud config set project gestorcooperativo
CONN="gestorcooperativo:southamerica-east1:ministerio-postgres"

# 1) redeploy svc-privada (código: catalogos_editables, sort, ok_gob/min, /localidades-info/all)
cd ~/gestorcooperativo/backend && git pull origin main && cd svc-privada
gcloud run deploy svc-privada --source . --region=southamerica-east1

# 2) migración 0002 en db_privada de prod (Cloud Shell + proxy + venv de la Fase B)
~/cloud-sql-proxy "$CONN" --port 5432 > /tmp/proxy.log 2>&1 &
sleep 4 && cat /tmp/proxy.log            # "Listening on 127.0.0.1:5432"
source .venv/bin/activate
PRIV_PW=$(gcloud secrets versions access latest --secret=svc-privada-db-url \
  | sed -E 's|.*//user_privada:([^@]+)@.*|\1|')
export DATABASE_URL="postgresql+asyncpg://user_privada:${PRIV_PW}@127.0.0.1:5432/db_privada"
python -m alembic current                # 0001
python -m alembic upgrade head           # aplica 0002
python -m alembic current                # 0002

# 3) backfill de categoria_id / acciones_implementadas (RE-1: mirar antes de aplicar)
python scripts/backfill_categorias.py --dry-run
python scripts/backfill_categorias.py --diff-informe     # comparación tema(regex) → categoría nueva
python scripts/backfill_categorias.py                    # aplica (sólo donde está NULL)
#   → compartir la salida de --diff-informe con Secretaría Privada antes de E4

# 4) config de gateway nueva (por /localidades-info/all + los 6 paths de /categorias,/programas,/areas)
cd ~/gestorcooperativo/infra/gateway && git pull origin main
python3 -c "import yaml; yaml.safe_load(open('openapi.yaml')); print('yaml ok')"
FECHA=$(date +%Y%m%d)
gcloud api-gateway api-configs create ministerio-config-v${FECHA} \
  --api=ministerio-api --openapi-spec=openapi.yaml \
  --backend-auth-service-account=api-gateway-sa@gestorcooperativo.iam.gserviceaccount.com
gcloud api-gateway gateways update ministerio-gateway \
  --api=ministerio-api --api-config=ministerio-config-v${FECHA} --location=us-central1
# esperar ~5 min

# 5) frontend
cd ~/gestorcooperativo/frontend && git pull origin main
npm run build && firebase deploy --only hosting
```

Smoke (token Admin):
```bash
GW="https://ministerio-gateway-3j5k00ma.uc.gateway.dev"
curl -s "$GW/api/v1/privada/categorias" -H "Authorization: Bearer $TOKEN"                 # 9 categorías
curl -s "$GW/api/v1/privada/localidades-info/all" -H "Authorization: Bearer $TOKEN" | head -c 300
curl -s "$GW/api/v1/privada/gestiones?sort=urgencia&sort_dir=asc&limit=3" -H "Authorization: Bearer $TOKEN"
```

**Rollback**: `gateways update ... --api-config=ministerio-config-v20260901`. La migración 0002 es
aditiva (columnas nullable + tablas nuevas) — `alembic downgrade 0001` si hiciera falta.

## Después del cutover

- T+1..T+30: monitoreo. Sistema viejo apagado pero conservado (rollback barato).
- E3 (DAG) y E4 (informe v2) → necesitan la reunión de relevamiento con Secretaría Privada.
- Decommission (`spec-migracion-svc-privada.md §10`).
