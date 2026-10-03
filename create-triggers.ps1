# Script para crear/actualizar Cloud Build triggers en GestorCooperativo
# Uso: .\infra\create-triggers.ps1

$ErrorActionPreference = "Stop"

$PROJECT = "gestorcooperativo"
$REPO_NAME = "panel.backend"
$REPO_OWNER = "coordinacion-infraestructura-coop"
$BRANCH_PATTERN = "^main$"
$CONFIG_PATH = "services/cloudbuild.yaml"

$SERVICES = @(
  "svc-vivienda",
  "svc-privada",
  "svc-gasifera",
  "svc-gralgob",
  "svc-datos-externos"
)

Write-Host "=================================================="
Write-Host "GestorCooperativo — Cloud Build Triggers Setup" -ForegroundColor Cyan
Write-Host "=================================================="
Write-Host ""
Write-Host "Proyecto: $PROJECT"
Write-Host "Repo: $REPO_OWNER/$REPO_NAME"
Write-Host "Branch: $BRANCH_PATTERN"
Write-Host "Config: $CONFIG_PATH"
Write-Host ""

# Función para crear un trigger
function CreateTrigger {
  param([string]$SERVICE)
  
  $TRIGGER_NAME = "deploy-$SERVICE"
  
  Write-Host "🔨 Creando trigger: $TRIGGER_NAME" -ForegroundColor Yellow
  
  try {
    & gcloud builds triggers create github `
      --repo-name="$REPO_NAME" `
      --repo-owner="$REPO_OWNER" `
      --branch-pattern="$BRANCH_PATTERN" `
      --build-config="$CONFIG_PATH" `
      --substitutions="_SERVICE=$SERVICE" `
      --name="$TRIGGER_NAME" `
      --project="$PROJECT" `
      --included-files="services/$SERVICE/**"
    
    Write-Host "✅ Trigger $TRIGGER_NAME creado exitosamente" -ForegroundColor Green
  }
  catch {
    Write-Host "⚠️  Trigger $TRIGGER_NAME ya existe o error de creación" -ForegroundColor Yellow
    Write-Host $_.Exception.Message -ForegroundColor Red
  }
  
  Write-Host ""
}

# Crear cada trigger
foreach ($SERVICE in $SERVICES) {
  CreateTrigger -SERVICE $SERVICE
}

Write-Host "=================================================="
Write-Host "✅ Triggers creados/actualizados" -ForegroundColor Green
Write-Host "=================================================="
Write-Host ""
Write-Host "Próximos pasos:"
Write-Host "  1. Verificar triggers:"
Write-Host "     gcloud builds triggers list --project=$PROJECT --format=`"table(name,substitutions._SERVICE)`""
Write-Host ""
Write-Host "  2. Ver logs de un build:"
Write-Host "     gcloud builds log <BUILD_ID> --project=$PROJECT"
Write-Host ""
Write-Host "  3. Ver lista de builds recientes:"
Write-Host "     gcloud builds list --project=$PROJECT --limit=10"
Write-Host ""
