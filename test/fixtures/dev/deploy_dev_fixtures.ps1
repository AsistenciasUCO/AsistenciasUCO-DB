param (
    [string]$ContainerName,
    [string]$Password,
    [string]$Scenarios = '300,1000,5000',
    [switch]$CleanupOnly,
    [switch]$ValidateOnly
)

# MAINT-003K - carga reproducible de fixtures sinteticos de desarrollo (paginacion 300/1000/5000).
# Orden: limpieza (solo prefijo DE0000) -> carga -> validacion. NO forma parte de deploy_schema.ps1 ni de ningun despliegue.
# Uso:  .\test\fixtures\dev\deploy_dev_fixtures.ps1 -ContainerName sql_server_asistencias -Password <sa>
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$envFile = Join-Path $repoRoot '.env'
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith('#') -and $line.Contains('=')) {
            $parts = $line.Split('=', 2)
            [Environment]::SetEnvironmentVariable($parts[0].Trim(), $parts[1].Trim())
        }
    }
}
if (-not $ContainerName) { $ContainerName = if ($env:SQL_CONTAINER_NAME) { $env:SQL_CONTAINER_NAME } else { 'sqlserver' } }
if (-not $Password) { $Password = if ($env:SQL_CONTAINER_PASSWORD) { $env:SQL_CONTAINER_PASSWORD } elseif ($env:MSSQL_SA_PASSWORD) { $env:MSSQL_SA_PASSWORD } else { $null } }
if (-not $Password) { throw 'SQL password is required (.env, SQL_CONTAINER_PASSWORD/MSSQL_SA_PASSWORD or -Password).' }
if ($Password -ceq 'CHANGE_ME') { throw "SQL password is still the 'CHANGE_ME' placeholder." }
if ($Scenarios -notmatch '^(300|1000|5000)(,(300|1000|5000))*$') { throw "Scenarios must be a comma list of 300,1000,5000." }

# Salvaguarda: solo Developer Edition y la base esperada (los scripts SQL repiten la comprobacion).
$precheck = docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -d gestionasistenciadb -U sa -P $Password -C -b -h -1 -W -Q "SET NOCOUNT ON; SELECT CONCAT(DB_NAME(), '|', CAST(SERVERPROPERTY('Edition') AS NVARCHAR(100)));"
if ($LASTEXITCODE -ne 0 -or ($precheck -join '').Trim() -notmatch '^gestionasistenciadb\|Developer Edition') {
    throw 'BLOCKED - unsafe database target: DB_NAME/Developer Edition precheck failed.'
}

docker exec -u 0 $ContainerName rm -rf /tmp/devfixtures | Out-Null
docker exec -u 0 $ContainerName mkdir -p /tmp/devfixtures | Out-Null
foreach ($f in 'dev_pagination_cleanup.sql', 'dev_pagination_fixture.sql', 'dev_pagination_validate.sql') {
    docker cp (Join-Path $PSScriptRoot $f) "${ContainerName}:/tmp/devfixtures/$f" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Could not copy $f." }
}
docker exec -u 0 $ContainerName chmod -R a+rX /tmp/devfixtures | Out-Null

function Invoke-DevSql([string]$File) {
    $out = docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -d gestionasistenciadb -U sa -P $Password -C -b -I -v "Scenarios=$Scenarios" -i "/tmp/devfixtures/$File"
    $out | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { throw "SQL file failed: $File" }
}

try {
    if (-not $ValidateOnly) {
        Invoke-DevSql 'dev_pagination_cleanup.sql'
        if (-not $CleanupOnly) { Invoke-DevSql 'dev_pagination_fixture.sql' }
    }
    if (-not $CleanupOnly) { Invoke-DevSql 'dev_pagination_validate.sql' }
}
finally {
    docker exec -u 0 $ContainerName rm -rf /tmp/devfixtures | Out-Null
}
