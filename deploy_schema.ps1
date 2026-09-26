param (
    [string]$ContainerName,
    [string]$Password
)

$ErrorActionPreference = 'Stop'

# Cargar variables de entorno desde archivo .env si existe
$envFile = Join-Path $PSScriptRoot ".env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
            $parts = $line.Split("=", 2)
            [System.Environment]::SetEnvironmentVariable($parts[0].Trim(), $parts[1].Trim())
        }
    }
}

if (-not $ContainerName) {
    $ContainerName = if ($env:SQL_CONTAINER_NAME) { $env:SQL_CONTAINER_NAME } else { "sqlserver" }
}
if (-not $Password) {
    $Password = if ($env:SQL_CONTAINER_PASSWORD) { $env:SQL_CONTAINER_PASSWORD } elseif ($env:MSSQL_SA_PASSWORD) { $env:MSSQL_SA_PASSWORD } else { $null }
}
if (-not $Password) {
    throw "SQL password is required. Create a local '.env' file from '.env.template', set SQL_CONTAINER_PASSWORD/MSSQL_SA_PASSWORD, or pass -Password."
}
if ($Password -ceq 'CHANGE_ME') {
    throw "SQL password is still the 'CHANGE_ME' placeholder. Set a real local value in '.env' (ignored by Git)."
}

Write-Host "Iniciando despliegue de arquitectura por objeto (/schema)..." -ForegroundColor Cyan

$schemaDir = Join-Path $PSScriptRoot "schema"

# 0. Asegurar que la base de datos existe
Write-Host "`nAsegurando base de datos 'gestionasistenciadb'..." -ForegroundColor Yellow
docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$Password" -C -Q "IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'gestionasistenciadb') CREATE DATABASE gestionasistenciadb;"
if ($LASTEXITCODE -ne 0) { throw "Could not create/verify database gestionasistenciadb." }

# 0.1 Copiar la carpeta schema al contenedor para evitar problemas de codificación de tubería (BOM/stdin)
Write-Host "Copiando esquema al contenedor..." -ForegroundColor Gray
docker exec $ContainerName mkdir -p /tmp/schema
if ($LASTEXITCODE -ne 0) { throw "Could not create /tmp/schema in SQL container." }
docker cp "$schemaDir" "${ContainerName}:/tmp/"
if ($LASTEXITCODE -ne 0) { throw "Could not copy schema into SQL container." }

# Función auxiliar para ejecutar archivos SQL desde el contenedor
function Execute-Sql-File {
    param (
        [string]$LocalFilePath
    )
    # Calcular ruta relativa dentro del contenedor
    $relativePath = $LocalFilePath.Substring($schemaDir.Length).Replace('\', '/')
    $containerPath = "/tmp/schema$relativePath"
    
    docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$Password" -C -b -i $containerPath
    if ($LASTEXITCODE -ne 0) { throw "SQL file failed: $LocalFilePath" }
}

# 1. Aplicar Tablas
Write-Host "`nAplicando Tablas..." -ForegroundColor Yellow
Get-ChildItem -Path "$schemaDir\tables" -Filter "*.sql" -Recurse | Sort-Object Name | ForEach-Object {
    Execute-Sql-File -LocalFilePath $_.FullName
}

# 2. Aplicar Funciones
Write-Host "`nAplicando Funciones..." -ForegroundColor Yellow
Get-ChildItem -Path "$schemaDir\functions" -Filter "*.sql" -Recurse | Sort-Object Name | ForEach-Object {
    Execute-Sql-File -LocalFilePath $_.FullName
}

# 3. Aplicar Vistas (Optimizadas dinámicamente)
Write-Host "`nAplicando Vistas (Resolviendo dependencias dinamicamente)..." -ForegroundColor Yellow
$views = Get-ChildItem -Path "$schemaDir\views" -Filter "*.sql" -Recurse
$pendingViews = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
foreach ($v in $views) { $pendingViews.Add($v) }

$maxPasses = 15
$pass = 1
$progressMade = $true

while ($pendingViews.Count -gt 0 -and $progressMade -and $pass -le $maxPasses) {
    $progressMade = $false
    $failedThisPass = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    foreach ($viewFile in $pendingViews) {
        $relativePath = $viewFile.FullName.Substring($schemaDir.Length).Replace('\', '/')
        $containerPath = "/tmp/schema$relativePath"
        $sqlResult = docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$Password" -C -b -i $containerPath 2>&1
        if ($LASTEXITCODE -ne 0 -or $sqlResult -match "Msg \d+, Level \d+") {
            $failedThisPass.Add($viewFile)
        }
        else {
            $progressMade = $true
        }
    }
    $pendingViews = $failedThisPass
    $pass++
}

if ($pendingViews.Count -gt 0) {
    Write-Host "`n[ERROR] No se pudieron aplicar las siguientes vistas debido a errores reales o dependencias circulares:" -ForegroundColor Red
    foreach ($viewFile in $pendingViews) {
        Write-Host "  - $($viewFile.Name)" -ForegroundColor Red
        Execute-Sql-File -LocalFilePath $viewFile.FullName
    }
}
else {
    Write-Host "Todas las vistas aplicadas correctamente!" -ForegroundColor Green
}

# 4. Aplicar Procedimientos Almacenados (soporta internos, externos, etc.)
Write-Host "`nAplicando Procedimientos Almacenados..." -ForegroundColor Yellow
Get-ChildItem -Path "$schemaDir\stored-procedures" -Filter "*.sql" -Recurse | Sort-Object Name | ForEach-Object {
    Write-Host "Ejecutando: $($_.Name)" -ForegroundColor Gray
    Execute-Sql-File -LocalFilePath $_.FullName
}

# 5. Aplicar Datos Semilla / Maestros (Seed)
if (Test-Path "$schemaDir\seed") {
    Write-Host "`nAplicando Datos Semilla / Maestros..." -ForegroundColor Yellow
    Get-ChildItem -Path "$schemaDir\seed" -Filter "*.sql" -Recurse | Sort-Object Name | ForEach-Object {
        Write-Host "Ejecutando Semilla: $($_.Name)" -ForegroundColor Gray
        Execute-Sql-File -LocalFilePath $_.FullName
    }
}

Write-Host "`n========================================================" -ForegroundColor Green
Write-Host "Despliegue del esquema por objeto completado con exito!" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
