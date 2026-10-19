<#
.SYNOPSIS
    Script unificado de entorno local Docker para gestionasistenciadb.
.DESCRIPTION
    Levanta SQL Server en Docker, espera su estado Healthy, despliega el esquema y corre la suite de pruebas.
.EXAMPLE
    .\run_local_env.ps1 -All
    .\run_local_env.ps1 -Up
    .\run_local_env.ps1 -Deploy
    .\run_local_env.ps1 -Test
    .\run_local_env.ps1 -Down
    .\run_local_env.ps1 -Clean
#>
param(
    [switch]$Up,
    [switch]$Down,
    [switch]$Deploy,
    [switch]$Test,
    [switch]$All,
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot

# Cargar .env si existe
$envFile = Join-Path $ScriptDir ".env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
            $parts = $line.Split("=", 2)
            [System.Environment]::SetEnvironmentVariable($parts[0].Trim(), $parts[1].Trim())
        }
    }
}

$ContainerName = if ($env:SQL_CONTAINER_NAME) { $env:SQL_CONTAINER_NAME } else { "sqlserver" }
$Password = if ($env:SQL_CONTAINER_PASSWORD) { $env:SQL_CONTAINER_PASSWORD } elseif ($env:MSSQL_SA_PASSWORD) { $env:MSSQL_SA_PASSWORD } else {
    throw "SQL password is required. Set SQL_CONTAINER_PASSWORD or MSSQL_SA_PASSWORD in the local ignored .env file."
}

function Start-SqlServerContainer {
    Write-Host "🐳 [1/4] Iniciando contenedor SQL Server ($ContainerName)..." -ForegroundColor Cyan
    docker compose -f (Join-Path $ScriptDir "docker-compose.dev.yml") up -d

    Write-Host "⏳ [2/4] Esperando a que SQL Server esté listo (Healthy)..." -ForegroundColor Yellow
    $retries = 30
    $isReady = $false

    while ($retries -gt 0) {
        $status = docker inspect --format '{{json .State.Health.Status}}' $ContainerName 2>$null
        if ($status -eq '"healthy"') {
            $isReady = $true
            break
        }
        Start-Sleep -Seconds 2
        $retries--
    }

    if (-not $isReady) {
        Write-Host "⚠️ El healthcheck no reportó 'healthy' a tiempo. Intentando conexión directa vía sqlcmd..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
    } else {
        Write-Host "✅ SQL Server está activo y saludable." -ForegroundColor Green
    }
}

function Invoke-DeploySchema {
    Write-Host "🚀 [3/4] Desplegando esquema completo en $ContainerName..." -ForegroundColor Cyan
    $deployScript = Join-Path $ScriptDir "deploy_schema.ps1"
    & $deployScript -ContainerName $ContainerName -Password $Password
}

function Invoke-Tests {
    Write-Host "🧪 [4/4] Ejecutando suite de pruebas automatizadas..." -ForegroundColor Cyan
    $testScript = Join-Path $ScriptDir "test_summary.ps1"
    & $testScript -ContainerName $ContainerName -Password $Password
}

function Stop-SqlServerContainer([bool]$RemoveVolumes) {
    Write-Host "🛑 Deteniendo contenedor SQL Server ($ContainerName)..." -ForegroundColor Yellow
    if ($RemoveVolumes) {
        docker compose -f (Join-Path $ScriptDir "docker-compose.dev.yml") down -v
        Write-Host "🧹 Contenedor y volúmenes de datos eliminados." -ForegroundColor Magenta
    } else {
        docker compose -f (Join-Path $ScriptDir "docker-compose.dev.yml") down
        Write-Host "⏹️ Contenedor detenido." -ForegroundColor Yellow
    }
}

# Lógica de ejecución
if ($Clean) {
    Stop-SqlServerContainer $true
    exit 0
}

if ($Down) {
    Stop-SqlServerContainer $false
    exit 0
}

if ($All -or (-not $Up -and -not $Down -and -not $Deploy -and -not $Test)) {
    Start-SqlServerContainer
    Invoke-DeploySchema
    Invoke-Tests
    Write-Host "`n🎉 Entorno desplegado y validado con éxito." -ForegroundColor Green
    exit 0
}

if ($Up) {
    Start-SqlServerContainer
}

if ($Deploy) {
    Invoke-DeploySchema
}

if ($Test) {
    Invoke-Tests
}