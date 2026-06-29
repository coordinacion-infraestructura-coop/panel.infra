# Plan de Ejecución — Infraestructura GCP

**Proyecto**: `gestorcooperativo`
**Región**: `southamerica-east1` (São Paulo)

Ejecutar los pasos en el orden indicado. Cada sección tiene su verificación antes de continuar.

---

## Prerequisitos

Antes de empezar, tener instalado y configurado:

```bash
# Verificar herramientas
gcloud --version          # Google Cloud SDK >= 450
firebase --version        # Firebase CLI >= 13
git --version
docker --version          # Solo necesario para build local

# Autenticarse con la cuenta de desarrollo
# Cuenta actual: infraestructura.coop@gmail.com
gcloud auth login
gcloud auth application-default login
```

Tener a mano:
- [ ] **Billing Account ID** → `gcloud billing accounts list`
- [ ] **Repositorio GitHub** creado y con el código de este proyecto

> **Nota sobre dominios**: No es necesario tener el dominio ministerial ni correos institucionales
> para comenzar. GCP provee URLs funcionales inmediatamente:
> - API Gateway: `https://GATEWAY_ID.southamerica-east1.gateway.dev`
> - Firebase Hosting: `https://gestorcooperativo.web.app`
>
> El dominio custom (`api.ministerio-coop.gob.ar`) se agrega después como paso opcional.
> Los dominios institucionales se incorporan cuando estén disponibles (gestión con seguridad informática).
> Todo el desarrollo y las pruebas funcionales se hacen con las URLs de GCP.

---

## Paso 1 — Crear el proyecto GCP

```bash
# Editar el archivo antes de ejecutar: completar BILLING_ACCOUNT
nano infra/gcp-setup.sh
# Cambiar: BILLING_ACCOUNT=""  →  BILLING_ACCOUNT="XXXXXX-XXXXXX-XXXXXX"

bash infra/gcp-setup.sh
```

**Tiempo estimado**: 3-5 minutos

**Verificación:**
```bash
gcloud projects describe gestorcooperativo
# Debe mostrar: lifecycleState: ACTIVE

gcloud services list --enabled --project=gestorcooperativo | grep -E "run|sql|gateway|pubsub"
# Debe listar los servicios habilitados

gcloud iam service-accounts list --project=gestorcooperativo
# Debe mostrar: svc-vivienda, svc-infraestructura, svc-territorial, svc-gasifera, svc-desarrollo, api-gateway-sa
```

---

## Paso 2 — Artifact Registry

```bash
# Crear el repositorio de imágenes Docker
gcloud artifacts repositories create ministerio-docker \
  --repository-format=docker \
  --location=southamerica-east1 \
  --description="Imágenes Docker del sistema ministerial" \
  --project=gestorcooperativo

# Configurar Docker para usar el registry
gcloud auth configure-docker southamerica-east1-docker.pkg.dev --quiet
```

**Verificación:**
```bash
gcloud artifacts repositories list \
  --location=southamerica-east1 \
  --project=gestorcooperativo
# Debe mostrar: ministerio-docker
```

---

## Paso 3 — Cloud SQL

```bash
bash infra/cloudsql-setup.sh
```

**Tiempo estimado**: 8-12 minutos (la instancia tarda en provisionar)

**Verificación:**
```bash
gcloud sql instances list --project=gestorcooperativo
# Estado debe ser: RUNNABLE

gcloud sql databases list \
  --instance=ministerio-postgres \
  --project=gestorcooperativo
# Debe listar: db_vivienda, db_infraestructura, db_territorial, db_gasifera, db_desarrollo

gcloud secrets list --project=gestorcooperativo
# Debe listar: svc-vivienda-db-url, svc-infraestructura-db-url, etc.
```

**Guardar el connection name** (lo necesitás en el Paso 7):
```bash
gcloud sql instances describe ministerio-postgres \
  --project=gestorcooperativo \
  --format="value(connectionName)"
# Ejemplo: gestorcooperativo:southamerica-east1:ministerio-postgres
```

---

## Paso 4 — Pub/Sub

```bash
bash infra/pubsub-setup.sh
```

**Tiempo estimado**: 2 minutos

**Verificación:**
```bash
gcloud pubsub topics list --project=gestorcooperativo
# Debe mostrar los 6 tópicos: ministerio-eventos-vivienda, ..., ministerio-eventos-dl

gcloud pubsub subscriptions list --project=gestorcooperativo
# Debe mostrar subscripciones bigquery-sub-* y notificaciones-sub-*
```

---

## Paso 5 — Firebase y Google Identity Platform

Este paso es manual desde la consola web.

### 5a. Crear proyecto Firebase

1. Ir a [console.firebase.google.com](https://console.firebase.google.com)
2. **Agregar proyecto** → seleccionar el proyecto GCP existente `gestorcooperativo`
3. Habilitar Google Analytics si se desea (opcional)

### 5b. Habilitar Google Identity Platform

```bash
# Habilitar Identity Platform via CLI
gcloud services enable identitytoolkit.googleapis.com --project=gestorcooperativo
```

En Cloud Console → Identity Platform:
1. Agregar proveedor: **Google**
2. Configurar dominios autorizados (sin dominio propio aún):
   - `gestorcooperativo.web.app` (Firebase Hosting)
   - `gestorcooperativo.firebaseapp.com` (Firebase Hosting alternativo)
   - `localhost` (desarrollo local)
3. Cuando el dominio ministerial esté disponible, agregar `ministerio-coop.gob.ar`

### 5c. Habilitar Firebase Hosting

```bash
# Desde el directorio frontend/ (una vez que esté inicializado)
firebase login
firebase projects:addfirebase gestorcooperativo
firebase init hosting --project=gestorcooperativo
```

**Verificación:**
```bash
firebase projects:list
# Debe mostrar gestorcooperativo
```

---

## Paso 6 — Conectar GitHub con Cloud Build

### 6a. Instalar la app de Cloud Build en GitHub

1. Ir a: Cloud Console → Cloud Build → **Triggers**
2. Conectar repositorio → GitHub → seleccionar el repositorio del proyecto
3. Autorizar la Cloud Build App en GitHub

### 6b. Crear trigger de CI/CD

```bash
gcloud builds triggers create github \
  --repo-name=GestorCooperativo \
  --repo-owner=TU_ORG_O_USUARIO \
  --branch-pattern="^main$" \
  --build-config=cloudbuild.yaml \
  --substitutions=_SERVICE=svc-vivienda \
  --name=deploy-svc-vivienda \
  --project=gestorcooperativo
```

> Repetir para cada servicio cuando esté listo para deploy.

**Verificación:**
```bash
gcloud builds triggers list --project=gestorcooperativo
```

---

## Paso 7 — Primer deploy: svc-vivienda

### 7a. Build y push manual (primera vez)

```bash
cd services/svc-vivienda

# Build
docker build \
  -t southamerica-east1-docker.pkg.dev/gestorcooperativo/ministerio-docker/svc-vivienda:latest \
  .

# Push
docker push \
  southamerica-east1-docker.pkg.dev/gestorcooperativo/ministerio-docker/svc-vivienda:latest
```

O via Cloud Build:
```bash
gcloud builds submit \
  --config=cloudbuild.yaml \
  --substitutions=_SERVICE=svc-vivienda \
  --project=gestorcooperativo
```

### 7b. Deploy a Cloud Run

```bash
CONNECTION_NAME=$(gcloud sql instances describe ministerio-postgres \
  --project=gestorcooperativo \
  --format="value(connectionName)")

gcloud run deploy svc-vivienda \
  --image=southamerica-east1-docker.pkg.dev/gestorcooperativo/ministerio-docker/svc-vivienda:latest \
  --region=southamerica-east1 \
  --no-allow-unauthenticated \
  --service-account=svc-vivienda@gestorcooperativo.iam.gserviceaccount.com \
  --set-secrets=DATABASE_URL=svc-vivienda-db-url:latest \
  --set-env-vars=GCP_PROJECT_ID=gestorcooperativo,SERVICE_NAME=svc-vivienda,ENVIRONMENT=production \
  --add-cloudsql-instances=$CONNECTION_NAME \
  --memory=512Mi \
  --cpu=1 \
  --min-instances=0 \
  --max-instances=10 \
  --concurrency=80 \
  --project=gestorcooperativo
```

### 7c. Ejecutar migraciones

```bash
# Obtener la URL del servicio
SVC_URL=$(gcloud run services describe svc-vivienda \
  --region=southamerica-east1 \
  --project=gestorcooperativo \
  --format="value(status.url)")

echo "svc-vivienda desplegado en: $SVC_URL"

# Las migraciones se ejecutan conectándose al Cloud SQL vía proxy local:
cloud-sql-proxy gestorcooperativo:southamerica-east1:ministerio-postgres &

# En otra terminal, con el DATABASE_URL apuntando a 127.0.0.1:
cd services/svc-vivienda
DATABASE_URL="postgresql+asyncpg://user_vivienda:PASSWORD@127.0.0.1:5432/db_vivienda" \
  alembic upgrade head
```

> El PASSWORD es el que generó `cloudsql-setup.sh` y quedó en Secret Manager. Para recuperarlo:
> ```bash
> gcloud secrets versions access latest --secret=svc-vivienda-db-url --project=gestorcooperativo
> ```

**Verificación:**
```bash
curl "$SVC_URL/health"
# Debe retornar: {"status":"ok","service":"svc-vivienda","version":"0.1.0"}
```

---

## Paso 8 — Desplegar API Gateway

### 8a. Actualizar openapi.yaml con la URL real del Cloud Run

```bash
# Obtener la URL del servicio
SVC_URL=$(gcloud run services describe svc-vivienda \
  --region=southamerica-east1 \
  --project=gestorcooperativo \
  --format="value(status.url)")

echo "Reemplazar en openapi.yaml: svc-vivienda-REPLACE → ${SVC_URL#https://}"
```

Editar `infra/gateway/openapi.yaml`: reemplazar todas las ocurrencias de `svc-vivienda-REPLACE-southamerica-east1.a.run.app` con la URL real.

### 8b. Dar permisos al API Gateway para invocar Cloud Run

```bash
# El service account del gateway necesita invocar svc-vivienda
gcloud run services add-iam-policy-binding svc-vivienda \
  --member="serviceAccount:api-gateway-sa@gestorcooperativo.iam.gserviceaccount.com" \
  --role="roles/run.invoker" \
  --region=southamerica-east1 \
  --project=gestorcooperativo

# También necesita invocar el svc-privada en el proyecto externo
# (ejecutar en el proyecto externo con permisos correspondientes)
gcloud run services add-iam-policy-binding infraestructura-gestioninterna \
  --member="serviceAccount:api-gateway-sa@gestorcooperativo.iam.gserviceaccount.com" \
  --role="roles/run.invoker" \
  --region=southamerica-east1 \
  --project=essential-haiku-482815-u4
```

### 8c. Deploy del gateway

```bash
bash infra/gateway/deploy-gateway.sh
```

**Tiempo estimado**: 5-10 minutos

**Verificación:**
```bash
GATEWAY_URL=$(gcloud api-gateway gateways describe ministerio-gateway \
  --location=southamerica-east1 \
  --project=gestorcooperativo \
  --format="value(defaultHostname)")

echo "Gateway en: https://$GATEWAY_URL"

# Health check (sin auth)
curl "https://$GATEWAY_URL/health"

# Test con token real (obtener con gcloud):
TOKEN=$(gcloud auth print-identity-token)
curl -H "Authorization: Bearer $TOKEN" \
  "https://$GATEWAY_URL/api/v1/vivienda/programas"
```

---

## Paso 9 — Configurar dominio custom ⏳ DIFERIDO (pendiente gestión con seguridad informática)

Este paso queda para cuando el dominio ministerial esté disponible. Hasta entonces, usar la URL
default del API Gateway: `https://GATEWAY_ID.southamerica-east1.gateway.dev`

Cuando el dominio esté listo:

```bash
# En API Gateway → Custom domains (desde Cloud Console):
# 1. Agregar dominio: api.ministerio-coop.gob.ar
# 2. Verificar propiedad
# 3. Configurar CNAME en el DNS del dominio

# En Firebase Hosting → Custom domains:
# 1. Agregar dominio: ministerio-coop.gob.ar
# 2. Verificar propiedad + configurar DNS

# En Identity Platform:
# Agregar ministerio-coop.gob.ar a los dominios autorizados

# En svc-vivienda app/main.py — actualizar CORS:
# allow_origins: agregar "https://ministerio-coop.gob.ar"
```

---

## Paso 10 — Seed de datos iniciales

Una vez que las migraciones corrieron y el servicio está desplegado:

```bash
# Seed de programas y municipios Cordón Cuneta
# (endpoint temporal solo disponible en development, o ejecutar via script)
TOKEN=$(gcloud auth print-identity-token)
GATEWAY_URL="..."   # URL del gateway

# Verificar que los programas estén cargados
curl -H "Authorization: Bearer $TOKEN" \
  "https://$GATEWAY_URL/api/v1/vivienda/programas"
# Si retorna [] → ejecutar seed manualmente conectando a la BD
```

---

## Resumen de estado

| Paso | Descripción | Tiempo | Estado |
|------|-------------|--------|--------|
| 0 | Prerequisitos (herramientas + billing account) | — | ⏳ pendiente |
| 1 | Crear proyecto GCP + APIs + service accounts | 5 min | ⏳ pendiente |
| 2 | Artifact Registry | 1 min | ⏳ pendiente |
| 3 | Cloud SQL (instancia + BDs + secrets) | 12 min | ⏳ pendiente |
| 4 | Pub/Sub (tópicos + subscripciones) | 2 min | ⏳ pendiente |
| 5 | Firebase + Google Identity Platform | 10 min manual | ⏳ pendiente |
| 6 | GitHub + Cloud Build trigger | 5 min | ⏳ pendiente |
| 7 | Deploy svc-vivienda + migraciones | 10 min | ⏳ pendiente |
| 8 | API Gateway (con URL real de Cloud Run) | 10 min | ⏳ pendiente |
| 9 | **Dominio custom** — diferido hasta gestión con seguridad informática | — | 🔜 diferido |
| 10 | Seed de datos iniciales | 5 min | ⏳ pendiente |

**Tiempo total estimado primera ejecución**: ~60 minutos (incluyendo tiempos de espera de Cloud SQL y API Gateway)

---

## Ante errores comunes

**`ERROR: (gcloud.projects.create) Resource in projects already exists`**
→ El proyecto ya existe. Continuar desde el Paso 2.

**`ERROR: Billing account not found`**
→ Completar `BILLING_ACCOUNT` en `gcp-setup.sh` con el ID correcto (`gcloud billing accounts list`).

**`ERROR: Cloud SQL instance not found` al conectar via proxy**
→ Esperar que la instancia esté en estado `RUNNABLE` (`gcloud sql instances list`).

**`403 Forbidden` en el API Gateway**
→ Verificar que el service account `api-gateway-sa` tiene `roles/run.invoker` en el Cloud Run correspondiente (Paso 8b).

**Migraciones fallan con `connection refused`**
→ Asegurarse de que el Cloud SQL Auth Proxy está corriendo en segundo plano antes de ejecutar `alembic upgrade head`.
