param(
    [Parameter(Mandatory = $true)] [string]$ContainerName,
    [Parameter(Mandatory = $true)] [string]$AdminPassword
)

$ErrorActionPreference = 'Stop'
$database = 'gestionasistenciadb'
$fixture = Join-Path $PSScriptRoot 'fixtures/maint_003g_attendance_fixture.sql'

docker cp $fixture "$($ContainerName):/tmp/maint_003g_attendance_fixture.sql" | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not copy the MAINT-003G fixture into the isolated container.' }

$output = docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd `
    -S localhost -d $database -U sa -P $AdminPassword -C -b -h -1 -W `
    -i /tmp/maint_003g_attendance_fixture.sql 2>&1
if ($LASTEXITCODE -ne 0) { throw 'MAINT-003G Java integration fixture failed.' }

if (($output | Out-String) -notmatch 'TEST_FIXTURE_READY\|session=[0-9A-Fa-f-]{36}\|rows=2') {
    throw 'MAINT-003G fixture did not produce its readiness evidence.'
}

Write-Host 'TEST_PASS:MAINT_003G_JAVA_ATTENDANCE_FIXTURE'
