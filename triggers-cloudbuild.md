# Cloud Build Triggers — GestorCooperativo

## Estado Actual

Triggers necesarios para cada microservicio. Ejecutar en Cloud Shell o local con `gcloud` auth configurado.

## Crear Triggers

### 1. svc-vivienda (si no existe)

```bash
gcloud builds triggers create github \
  --repo-name=panel.backend \
  --repo-owner=coordinacion-infraestructura-coop \
  --branch-pattern="^main$" \
  --build-config=services/cloudbuild.yaml \
  --substitutions="_SERVICE=svc-vivienda" \
  --name=deploy-svc-vivienda \
  --project=gestorcooperativo \
  --included-files="services/svc-vivienda/**"
```

### 2. svc-privada

```bash
gcloud builds triggers create github \
  --repo-name=panel.backend \
  --repo-owner=coordinacion-infraestructura-coop \
  --branch-pattern="^main$" \
  --build-config=services/cloudbuild.yaml \
  --substitutions="_SERVICE=svc-privada" \
  --name=deploy-svc-privada \
  --project=gestorcooperativo \
  --included-files="services/svc-privada/**"
```

### 3. svc-gasifera

```bash
gcloud builds triggers create github \
  --repo-name=panel.backend \
  --repo-owner=coordinacion-infraestructura-coop \
  --branch-pattern="^main$" \
  --build-config=services/cloudbuild.yaml \
  --substitutions="_SERVICE=svc-gasifera" \
  --name=deploy-svc-gasifera \
  --project=gestorcooperativo \
  --included-files="services/svc-gasifera/**"
```

### 4. svc-gralgob

```bash
gcloud builds triggers create github \
  --repo-name=panel.backend \
  --repo-owner=coordinacion-infraestructura-coop \
  --branch-pattern="^main$" \
  --build-config=services/cloudbuild.yaml \
  --substitutions="_SERVICE=svc-gralgob" \
  --name=deploy-svc-gralgob \
  --project=gestorcooperativo \
  --included-files="services/svc-gralgob/**"
```

### 5. svc-datos-externos (futuro)

```bash
gcloud builds triggers create github \
  --repo-name=panel.backend \
  --repo-owner=coordinacion-infraestructura-coop \
  --branch-pattern="^main$" \
  --build-config=services/cloudbuild.yaml \
  --substitutions="_SERVICE=svc-datos-externos" \
  --name=deploy-svc-datos-externos \
  --project=gestorcooperativo \
  --included-files="services/svc-datos-externos/**"
```

## Verificar Triggers Existentes

```bash
gcloud builds triggers list --project=gestorcooperativo --format="table(name,description,filename,substitutions._SERVICE)"
```

## Eliminar un Trigger (si es necesario)

```bash
gcloud builds triggers delete NOMBRE_DEL_TRIGGER --project=gestorcooperativo
```

## Notas

- **repo-name**: debe ser exacto → `panel.backend` (es el repo de GitHub donde está `services/`)
- **repo-owner**: `coordinacion-infraestructura-coop` (la org de GitHub)
- **branch-pattern**: `^main$` (solo trigger en main, no en PRs)
- **included-files**: optimiza el trigger → solo corre si cambios en esa carpeta del servicio
- **substitutions._SERVICE**: el nombre del directorio del servicio (ej: `svc-privada`)
- **cloudbuild.yaml**: automáticamente busca `services/cloudbuild.yaml`, que es genérico y usa el substitution `_SERVICE` para saber qué compilar

## Cómo Funciona

1. Se hace `git push` a `main` en `panel.backend`
2. Cloud Build detecta cambios en `services/svc-X/**`
3. Ejecuta automáticamente `services/cloudbuild.yaml --substitutions=_SERVICE=svc-X`
4. El pipeline:
   - Build imagen Docker desde `services/svc-X/Dockerfile`
   - Push a Artifact Registry (`southamerica-east1-docker.pkg.dev/...`)
   - Deploy a Cloud Run (`gcloud run deploy svc-X ...`)
   - Aplica todas las env vars (secretos de Sheet, URLs internas, etc.)

## Estado Post-Deploy

- ✅ Imagen en Artifact Registry con tag `${SHORT_SHA}` y `latest`
- ✅ Servicio Cloud Run en `southamerica-east1` actualizado
- ✅ Env vars y secrets inyectados desde substitutions
- ✅ Cloud SQL `ministerio-postgres` conectada
- ✅ Service account `svc-X@gestorcooperativo.iam.gserviceaccount.com` con permisos IAM

**Si no ves el deploy aparecer:**
1. Verifica que el trigger tenga `included-files` correcto (evita falsos positivos)
2. Ve a Cloud Console → Cloud Build → History para ver logs detallados
3. Busca el commit SHA para asociarlo con el build que corrió
