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

# MAINT-003H: datos para que los 3 escenarios dependientes de datos se EJECUTEN (sin tocar los tests ni sus Assumptions)
$fixtureData = Join-Path $PSScriptRoot 'fixtures/maint_003h_failsafe_data_fixture.sql'
docker cp $fixtureData "$($ContainerName):/tmp/maint_003h_failsafe_data_fixture.sql" | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not copy the MAINT-003H data fixture into the isolated container.' }
$outputData = docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd `
    -S localhost -d $database -U sa -P $AdminPassword -C -b -h -1 -W `
    -i /tmp/maint_003h_failsafe_data_fixture.sql 2>&1
if ($LASTEXITCODE -ne 0) { throw "MAINT-003H data fixture failed: $($outputData | Out-String)" }
if (($outputData | Out-String) -notmatch 'TEST_FIXTURE_READY\|maint003h\|multi=1\|empty=1\|horarios=[1-9]') {
    throw 'MAINT-003H data fixture did not produce its readiness evidence.'
}
Write-Host 'TEST_PASS:MAINT_003H_JAVA_DATA_FIXTURE'
