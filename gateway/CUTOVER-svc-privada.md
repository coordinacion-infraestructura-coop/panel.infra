# Gateway — cambios de `openapi.yaml` para el cutover de svc-privada (Fase 6)

Se aplica **todo junto** al crear la config nueva `ministerio-config-v{YYYYMMDD}` durante la
ventana de cutover (spec `spec-migracion-svc-privada.md` §6, §9). No se toca `openapi.yaml`
antes: hasta el cutover el gateway sigue apuntando al Cloud Run viejo.

Prerequisito: `svc-privada` desplegado en Cloud Run y su URL conocida →
`SVC_PRIVADA_URL` (algo como `https://svc-privada-xxxxxxxxxx-rj.a.run.app`).

---

## 1. Repuntar TODOS los backends `/api/v1/privada/**`

Reemplazo global dentro de la sección privada (paths desde `/api/v1/privada/me` hasta el final
de `/api/v1/privada/localidades-info`):

```
"https://infraestructura-gestioninterna-354063050046.southamerica-east1.run.app"
```
→
```
"<SVC_PRIVADA_URL>"
```

Aplica a **`address:` y `jwt_audience:`** de cada `get/post/put/delete/patch/options`.
(`sed -i 's#https://infraestructura-gestioninterna-354063050046\.southamerica-east1\.run\.app#<SVC_PRIVADA_URL>#g'` sobre el rango de la sección privada — verificar que NO toca otras secciones.)

## 2. ELIMINAR paths (ADR-015 — la gestión de usuarios pasa al portal)

Borrar estos 4 bloques completos (path + todos sus verbos + `options`):

- `/api/v1/privada/usuarios`
- `/api/v1/privada/usuarios/{email}`
- `/api/v1/privada/usuarios/{email}/modulos`
- `/api/v1/privada/usuarios/{email}/modulos/{modulo}`

`/api/v1/privada/catalogos/modulos` no está como path propio (lo cubre `/catalogos/{catalogo}`);
no hay nada que borrar ahí, pero `svc-privada` responde 404 a `catalogos/modulos` (correcto).

## 3. AGREGAR paths nuevos

`/api/v1/privada/me` se mantiene (alias). Agregar (misma estructura que el resto de la sección,
`path_translation: APPEND_PATH_TO_ADDRESS`, `<SVC_PRIVADA_URL>` en `address`+`jwt_audience`,
`options` con `security: []`):

### 3.1 `PATCH` en `/api/v1/privada/gestiones/{gestion_id}`
Ya existe el path con `get` + `delete` + `options`. **Agregar sólo el verbo `patch`**:

```yaml
    patch:
      operationId: editarGestion
      summary: Editar campos de una gestión (sin cambio de estado)
      tags: [privada]
      x-google-backend:
        address: "<SVC_PRIVADA_URL>"
        path_translation: APPEND_PATH_TO_ADDRESS
        jwt_audience: "<SVC_PRIVADA_URL>"
      responses:
        "200":
          description: Gestión actualizada
```

### 3.2 `/api/v1/privada/gestiones/rollup-territorial`
```yaml
  /api/v1/privada/gestiones/rollup-territorial:
    get:
      operationId: rollupTerritorialPrivada
      summary: Rollup global por departamento y localidad
      tags: [privada]
      x-google-backend:
        address: "<SVC_PRIVADA_URL>"
        path_translation: APPEND_PATH_TO_ADDRESS
        jwt_audience: "<SVC_PRIVADA_URL>"
      responses:
        "200":
          description: Rollup territorial
    options:
      operationId: corsPrivadaRollupTerritorial
      summary: CORS preflight
      security: []
      x-google-backend:
        address: "<SVC_PRIVADA_URL>"
        path_translation: APPEND_PATH_TO_ADDRESS
        jwt_audience: "<SVC_PRIVADA_URL>"
      responses:
        "200":
          description: OK
```
> Debe declararse **antes** de `/api/v1/privada/gestiones/{gestion_id}` en el archivo para que
> ESPv2 no lo capture como `{gestion_id}` (mismo criterio que `resumen-territorial`).

### 3.3 `/api/v1/privada/departamentos-info`
```yaml
  /api/v1/privada/departamentos-info:
    get:
      operationId: getDepartamentoInfo
      summary: Ficha de información de un departamento (read-only)
      tags: [privada]
      parameters:
        - in: query
          name: departamento
          required: true
          type: string
      x-google-backend:
        address: "<SVC_PRIVADA_URL>"
        path_translation: APPEND_PATH_TO_ADDRESS
        jwt_audience: "<SVC_PRIVADA_URL>"
      responses:
        "200":
          description: Ficha del departamento
    options:
      operationId: corsPrivadaDepartamentoInfo
      summary: CORS preflight
      security: []
      x-google-backend:
        address: "<SVC_PRIVADA_URL>"
        path_translation: APPEND_PATH_TO_ADDRESS
        jwt_audience: "<SVC_PRIVADA_URL>"
      responses:
        "200":
          description: OK
```

### 3.4 Informe de Cooperativas — los 4 endpoints (hoy dan 404 por el gateway)
```yaml
  /api/v1/privada/informe/cooperativas/resumen:
    get:
      operationId: informeCoopResumen
      summary: Informe de Cooperativas — KPIs por tema
      tags: [privada]
      x-google-backend:
        address: "<SVC_PRIVADA_URL>"
        path_translation: APPEND_PATH_TO_ADDRESS
        jwt_audience: "<SVC_PRIVADA_URL>"
      responses:
        "200": { description: OK }
    options:
      operationId: corsPrivadaInformeCoopResumen
      summary: CORS preflight
      security: []
      x-google-backend:
        address: "<SVC_PRIVADA_URL>"
        path_translation: APPEND_PATH_TO_ADDRESS
        jwt_audience: "<SVC_PRIVADA_URL>"
      responses:
        "200": { description: OK }

  /api/v1/privada/informe/cooperativas/temporal:
    get:
      operationId: informeCoopTemporal
      summary: Informe de Cooperativas — evolución mensual
      tags: [privada]
      x-google-backend:
        address: "<SVC_PRIVADA_URL>"
        path_translation: APPEND_PATH_TO_ADDRESS
        jwt_audience: "<SVC_PRIVADA_URL>"
      responses:
        "200": { description: OK }
    options:
      operationId: corsPrivadaInformeCoopTemporal
      summary: CORS preflight
      security: []
      x-google-backend:
        address: "<SVC_PRIVADA_URL>"
        path_translation: APPEND_PATH_TO_ADDRESS
        jwt_audience: "<SVC_PRIVADA_URL>"
      responses:
        "200": { description: OK }

  /api/v1/privada/informe/cooperativas/por-departamento:
    get:
      operationId: informeCoopPorDepartamento
      summary: Informe de Cooperativas — tema x departamento
      tags: [privada]
      x-google-backend:
        address: "<SVC_PRIVADA_URL>"
        path_translation: APPEND_PATH_TO_ADDRESS
        jwt_audience: "<SVC_PRIVADA_URL>"
      responses:
        "200": { description: OK }
    options:
      operationId: corsPrivadaInformeCoopPorDepto
      summary: CORS preflight
      security: []
      x-google-backend:
        address: "<SVC_PRIVADA_URL>"
        path_translation: APPEND_PATH_TO_ADDRESS
        jwt_audience: "<SVC_PRIVADA_URL>"
      responses:
        "200": { description: OK }

  /api/v1/privada/informe/cooperativas/puntos:
    get:
      operationId: informeCoopPuntos
      summary: Informe de Cooperativas — puntos para el mapa
      tags: [privada]
      x-google-backend:
        address: "<SVC_PRIVADA_URL>"
        path_translation: APPEND_PATH_TO_ADDRESS
        jwt_audience: "<SVC_PRIVADA_URL>"
      responses:
        "200": { description: OK }
    options:
      operationId: corsPrivadaInformeCoopPuntos
      summary: CORS preflight
      security: []
      x-google-backend:
        address: "<SVC_PRIVADA_URL>"
        path_translation: APPEND_PATH_TO_ADDRESS
        jwt_audience: "<SVC_PRIVADA_URL>"
      responses:
        "200": { description: OK }
```

---

## 4. Desplegar la config nueva

```bash
cd ~/panel.infra/gateway && git pull origin main
gcloud api-gateway api-configs create ministerio-config-v{YYYYMMDD} \
  --api=ministerio-api --openapi-spec=openapi.yaml --project=gestorcooperativo \
  --backend-auth-service-account=api-gateway-sa@gestorcooperativo.iam.gserviceaccount.com
gcloud api-gateway gateways update ministerio-gateway \
  --api=ministerio-api --api-config=ministerio-config-v{YYYYMMDD} \
  --location=us-central1 --project=gestorcooperativo
```

Rollback: `gateways update ... --api-config=ministerio-config-v20260716b` (config previa vigente).

## 5. IAM

- SA del gateway (`api-gateway-sa@gestorcooperativo`) con `roles/run.invoker` sobre el Cloud Run
  de `svc-privada`.
- SA de `svc-privada` con `roles/run.invoker` sobre `svc-vivienda` (para el endpoint interno de
  auth, ADR-015).
- Quitar (si aplica) la config IAM cross-project que ADR-006 requería para el Cloud Run viejo.

## 6. Smoke post-cutover

`GET /api/v1/privada/gestiones?limit=1`, `/api/v1/privada/me`,
`/api/v1/privada/informe/cooperativas/resumen`, `/api/v1/privada/gestiones/rollup-territorial`
— todos 200 con el token de un usuario con secretaría `privada`.
