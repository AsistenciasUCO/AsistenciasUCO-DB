param(
    [Parameter(Mandatory = $true)] [string]$ContainerName,
    [Parameter(Mandatory = $true)] [string]$AdminPassword
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($AdminPassword) -or $AdminPassword -ceq 'CHANGE_ME') {
    throw 'SQL admin password is required and cannot be the CHANGE_ME placeholder.'
}

$fixture = Join-Path $PSScriptRoot 'fixtures/lb004d_ci_fixture_cleanup.sql'
$containerFixture = '/tmp/lb004d_ci_fixture_cleanup.sql'
try {
    docker cp $fixture "${ContainerName}:$containerFixture" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not copy the LB-004D cleanup script into the SQL container.' }

    $output = @(docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd `
        -S localhost -d gestionasistenciadb -U sa -P $AdminPassword -C -b -h -1 -W `
        -i $containerFixture 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "LB-004D fixture cleanup failed: $($output -join '; ')"
    }
    if (($output -join [Environment]::NewLine) -notmatch 'TEST_FIXTURE_CLEANED\|LB004D') {
        throw 'LB-004D fixture cleanup did not produce evidence.'
    }
    Write-Host 'TEST_PASS:LB004D_FIXTURE_CLEANED'
}
finally {
    docker exec -u 0 $ContainerName rm -f $containerFixture | Out-Null
}
