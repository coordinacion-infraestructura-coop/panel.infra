# Comandos frecuentes — GestorCooperativo

Proyecto GCP: `gestorcooperativo` | Región: `southamerica-east1`
Instancia Cloud SQL: `gestorcooperativo:southamerica-east1:ministerio-postgres`
API Gateway: `ministerio-gateway-3j5k00ma.uc.gateway.dev`

---

## Cloud SQL Proxy

```bash
# Iniciar el proxy en background (puerto 5432)
cloud-sql-proxy gestorcooperativo:southamerica-east1:ministerio-postgres --port=5432 &

# Verificar que el proxy esté activo
jobs

# Matar el proxy si es necesario reiniciarlo
kill %1
```

---

## Variables de entorno (Cloud Shell)

```bash
# Obtener la DATABASE_URL desde Secret Manager
gcloud secrets versions access latest --secret="svc-vivienda-db-url" --project=gestorcooperativo

# Exportar DATABASE_URL en formato TCP (para usar con proxy)
# Reemplazar la parte del socket por 127.0.0.1:5432
export DATABASE_URL="postgresql+asyncpg://user_vivienda:PASS@127.0.0.1:5432/db_vivienda"

# Verificar que esté seteada
echo $DATABASE_URL
```

> **Nota:** La contraseña tiene `+` y `=`. En el export de bash **no** hace falta URL-encodear
> (os.environ.get la lee literal). Solo hay que encodear si se usa en `alembic.ini` (configparser).

---

## Migraciones Alembic (desde Cloud Shell, con proxy activo y DATABASE_URL exportada)

```bash
cd ~/gestorcooperativo/backend/svc-vivienda

# Ver estado actual de las migraciones
python -m alembic current

# Ver historial
python -m alembic history

# Aplicar todas las migraciones pendientes
python -m alembic upgrade head

# Aplicar hasta una revisión específica
python -m alembic upgrade 0003

# Revertir una migración
python -m alembic downgrade -1
```

---

## Seeds

```bash
cd ~/gestorcooperativo/backend/svc-vivienda

# Seed completo de Cordón Cuneta (estados + municipios + config)
python seed_cordon_cuneta_v2.py
```

---

## Deploy svc-vivienda (desde Cloud Shell)

```bash
cd ~/gestorcooperativo/backend/svc-vivienda

# Actualizar código
git pull

# Deploy a Cloud Run (construye la imagen con Cloud Build)
gcloud run deploy svc-vivienda \
  --source . \
  --region=southamerica-east1 \
  --project=gestorcooperativo
```

---

## Verificar endpoints

```bash
# Obtener token desde el navegador (consola JS mientras estás logueado):
# firebase.auth().currentUser?.getIdToken().then(t => console.log(t))

# Health check del servicio
curl -s https://ministerio-gateway-3j5k00ma.uc.gateway.dev/health

# Panel Cordón Cuneta
curl -s "https://ministerio-gateway-3j5k00ma.uc.gateway.dev/api/v1/vivienda/cordon-cuneta" \
  -H "Authorization: Bearer TOKEN" | python3 -m json.tool | head -30

# Listar builds recientes de Cloud Build
gcloud builds list --project=gestorcooperativo --limit=5

# Ver logs del Cloud Run
gcloud run services logs read svc-vivienda --region=southamerica-east1 --project=gestorcooperativo --limit=50
```

---

## Secretos

```bash
# Listar secretos del proyecto
gcloud secrets list --project=gestorcooperativo

# Acceder a un secreto
gcloud secrets versions access latest --secret="NOMBRE_SECRETO" --project=gestorcooperativo

# Actualizar un secreto
echo -n "nuevo_valor" | gcloud secrets versions add NOMBRE_SECRETO --data-file=- --project=gestorcooperativo
```

---

## Flujo completo para un cambio de backend + migración

```bash
# 1. LOCAL: commitear y pushear
git add -A && git commit -m "feat: descripción" && git push

# 2. CLOUD SHELL: actualizar, migrar, deployar
git pull
cloud-sql-proxy gestorcooperativo:southamerica-east1:ministerio-postgres --port=5432 &
export DATABASE_URL="postgresql+asyncpg://user_vivienda:PASS@127.0.0.1:5432/db_vivienda"
python -m alembic upgrade head
gcloud run deploy svc-vivienda --source . --region=southamerica-east1 --project=gestorcooperativo
```
