param ([string]$ContainerName, [string]$Password)

$ErrorActionPreference = 'Stop'
$envFile = Join-Path $PSScriptRoot '.env'
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith('#') -and $line.Contains('=')) {
            $parts = $line.Split('=', 2)
            [Environment]::SetEnvironmentVariable($parts[0].Trim(), $parts[1].Trim())
        }
    }
}
if (-not $ContainerName) {
    $ContainerName = if ($env:SQL_CONTAINER_NAME) { $env:SQL_CONTAINER_NAME } else { "sqlserver" }
}
if (-not $Password) {
    $Password = if ($env:SQL_CONTAINER_PASSWORD) { $env:SQL_CONTAINER_PASSWORD } elseif ($env:MSSQL_SA_PASSWORD) { $env:MSSQL_SA_PASSWORD } else { "Rionegro2233+" }
}



# Independientemente del camino de deteccion del contenedor, las validaciones SQL reales
# (DB_NAME/servidor/edicion) de mas abajo siguen siendo obligatorias antes de continuar.
$precheck = docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -d gestionasistenciadb -U sa -P $Password -C -b -h -1 -W -Q "SET NOCOUNT ON; SELECT CONCAT(DB_NAME(), '|', @@SERVERNAME, '|', CONVERT(varchar(80), SERVERPROPERTY('Edition')));" 2>&1
if ($LASTEXITCODE -ne 0 -or ($precheck -join '').Trim() -notmatch '^gestionasistenciadb\|[^|]+\|Developer Edition') {
    throw 'BLOCKED - unsafe database target: DB_NAME/server/Developer Edition precheck failed.'
}

docker exec -u 0 $ContainerName rm -rf /tmp/test | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not clear the temporary SQL test directory.' }
docker cp (Join-Path $PSScriptRoot 'test_suite.sql') "$($ContainerName):/tmp/test_suite.sql" | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not copy test_suite.sql.' }
docker cp (Join-Path $PSScriptRoot 'test') "$($ContainerName):/tmp/test" | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not copy test/.' }
docker exec -u 0 $ContainerName chmod -R a+rX /tmp/test /tmp/test_suite.sql | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not make SQL tests readable.' }

$output = docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -d gestionasistenciadb -U sa -P $Password -C -b -h -1 -s '|' -w 65535 -y 1024 -Y 1024 -i /tmp/test_suite.sql 2>&1
$sqlExitCode = $LASTEXITCODE
$outputStr = ($output | ForEach-Object { "$_" }) -join [Environment]::NewLine
foreach ($line in ($outputStr -split '\r?\n')) {
    if ($line -match '^[0-9a-fA-F-]{36}\|') {
        Write-Host ((@($line -split '\|', 4) | ForEach-Object { $_.Trim() }) -join '|')
    }
    else { Write-Host $line }
}

# ROLLBACK inside INSERT ... EXEC is prohibited by SQL Server. SQLCMD owns
# the result set and compares the actual row with catalog and state checks.
$resultIds = @('STUDENT_DUPLICATE', 'STUDENT_GROUP_NOT_FOUND', 'STUDENT_GROUP_DISABLED', 'STUDENT_CAPACITY_EXCEEDED', 'TEACHER_GROUP_NOT_FOUND', 'MASS_CLOSE_SUCCESS')
$resultFailures = @()
$clientPassed = @()
foreach ($id in $resultIds) {
    $escaped = [regex]::Escape($id)
    $block = [regex]::Match($outputStr, "(?ms)^TEST_RESULT_BEGIN:$escaped\r?\n(.*?)^TEST_RESULT_END:$escaped\s*$")
    $user = [regex]::Match($outputStr, "(?m)^TEST_EXPECTED_USER:$escaped\|(.*)$")
    $tech = [regex]::Match($outputStr, "(?m)^TEST_EXPECTED_TECH:$escaped\|(.*)$")
    $statePassed = $outputStr -match "(?m)^TEST_STATE_PASS:$escaped\s*$"
    if (-not $block.Success -or -not $user.Success -or -not $tech.Success -or -not $statePassed) {
        $resultFailures += "$id missing result, catalog expectation, or state assertion"
        continue
    }
    $rows = @([regex]::Matches($block.Groups[1].Value, '(?m)^([0-9a-fA-F-]{36})\|([^|]*)\|([^|]*)\|\s*([01])\s*$'))
    if ($rows.Count -ne 1) {
        $resultFailures += "$id expected one canonical row; found $($rows.Count)"
        continue
    }
    $row = $rows[0]
    $expectedState = if ($id -eq 'MASS_CLOSE_SUCCESS') { '1' } else { '0' }
    if ($row.Groups[4].Value -ne $expectedState -or
        $row.Groups[2].Value.Trim() -cne $user.Groups[1].Value.Trim() -or
        $row.Groups[3].Value.Trim() -cne $tech.Groups[1].Value.Trim()) {
        $resultFailures += "$id actual result differs from state=$expectedState/catalog message"
        continue
    }
    $clientPassed += $id
    Write-Host "TEST_PASS:$id"
}

$repoProcedures = @(Get-ChildItem (Join-Path $PSScriptRoot 'schema/stored-procedures') -Filter 'usp_*.sql' |
    Where-Object { $_.BaseName -notmatch '_interno$' } | ForEach-Object { $_.BaseName })
$repoViews = @(Get-ChildItem (Join-Path $PSScriptRoot 'schema/views') -Filter 'uv_*.sql' |
    ForEach-Object { $_.BaseName })
$instanceProcedures = @(docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -d gestionasistenciadb -U sa -P $Password -C -b -h -1 -W -Q "SET NOCOUNT ON; SELECT name FROM sys.procedures WHERE schema_id=SCHEMA_ID('dbo') AND name LIKE 'usp[_]%' AND name NOT LIKE '%[_]interno' ORDER BY name;" 2>&1 |
    ForEach-Object { "$_".Trim() } | Where-Object { $_ })
$procedureQueryExit = $LASTEXITCODE
$instanceViews = @(docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -d gestionasistenciadb -U sa -P $Password -C -b -h -1 -W -Q "SET NOCOUNT ON; SELECT name FROM sys.views WHERE schema_id=SCHEMA_ID('dbo') AND name LIKE 'uv[_]%' ORDER BY name;" 2>&1 |
    ForEach-Object { "$_".Trim() } | Where-Object { $_ })
$viewQueryExit = $LASTEXITCODE
$missingProcedures = @($repoProcedures | Where-Object { $_ -notin $instanceProcedures })
$missingViews = @($repoViews | Where-Object { $_ -notin $instanceViews })
if ($procedureQueryExit -eq 0 -and $missingProcedures.Count -eq 0) {
    $clientPassed += 'PUBLIC_SP_INVENTORY'
    Write-Host 'TEST_PASS:PUBLIC_SP_INVENTORY'
}
if ($viewQueryExit -eq 0 -and $missingViews.Count -eq 0) {
    $clientPassed += 'PUBLIC_VIEW_INVENTORY'
    Write-Host 'TEST_PASS:PUBLIC_VIEW_INVENTORY'
}
Write-Host "REPO_PUBLIC_SP_COUNT=$($repoProcedures.Count)"
Write-Host "INSTANCE_PUBLIC_SP_COUNT=$($instanceProcedures.Count)"
Write-Host "REPO_PUBLIC_VIEW_COUNT=$($repoViews.Count)"
Write-Host "INSTANCE_PUBLIC_VIEW_COUNT=$($instanceViews.Count)"
Write-Host "PUBLIC_SP_MISSING=$($missingProcedures.Count)"
Write-Host "PUBLIC_VIEW_MISSING=$($missingViews.Count)"
if ($missingProcedures.Count) { Write-Host "MISSING_PROCEDURES=$($missingProcedures -join ',')" }
if ($missingViews.Count) { Write-Host "MISSING_VIEWS=$($missingViews -join ',')" }

$criticalIds = @(
    'SCHEMA_COLUMNS', 'PUBLIC_SIGNATURES', 'PUBLIC_VIEWS_REFRESH', 'BROKEN_DEPENDENCIES_ZERO',
    'PUBLIC_SP_INVENTORY', 'PUBLIC_VIEW_INVENTORY',
    'USER_SYNC_SUCCESS', 'USER_SYNC_INVALID', 'DEAN_SUCCESS',
    'SESSION_CLOSE_SUCCESS', 'SESSION_CLOSE_NON_OWNER',
    'REVIEW_FILE_INVALID', 'REVIEW_FILE_SUCCESS', 'REVIEW_RESOLVE_NON_OWNER', 'REVIEW_RESOLVE_SUCCESS',
    'SUBJECT_CREATE', 'SUBJECT_UPDATE', 'SUBJECT_TOGGLE',
    'SUBJECT_UPSERT_CREATE', 'SUBJECT_UPSERT_UPDATE', 'CATALOG_INSERT', 'CATALOG_GET',
    'PROGRAM_UPSERT_CREATE', 'PROGRAM_UPSERT_UPDATE',
    'PLAN_UPSERT_CREATE', 'PLAN_UPSERT_UPDATE',
    'GROUP_UPSERT_CREATE', 'GROUP_UPSERT_UPDATE', 'STUDENT_PROGRAM_REGISTER',
    'MASS_CLOSE_SUCCESS',
    'STUDENT_SUCCESS', 'STUDENT_DUPLICATE', 'STUDENT_GROUP_NOT_FOUND', 'STUDENT_GROUP_DISABLED', 'STUDENT_CAPACITY_EXCEEDED',
    'TEACHER_SUCCESS', 'TEACHER_GROUP_NOT_FOUND',
    'OWNERSHIP_STUDENT', 'OWNERSHIP_TEACHER', 'OWNERSHIP_DEAN', 'OWNERSHIP_COORDINATOR',
    'GROUP_CREATE', 'GROUP_UPDATE', 'GROUP_CAPACITY_REJECT',
    'SESSION_CREATE', 'SESSION_UPDATE', 'SESSION_NON_OWNER',
    'SESSION_GENERATION_SUCCESS', 'SESSION_GENERATION_IDEMPOTENT', 'SESSION_GENERATION_INVALID',
    'ATTENDANCE_BULK_SUCCESS', 'ATTENDANCE_BULK_INVALID',
    'ATTENDANCE_AUTO_SUCCESS', 'ATTENDANCE_AUTO_INVALID',
    'ATTENDANCE_SINGLE_SUCCESS', 'ATTENDANCE_SINGLE_INVALID',
    'COORDINATOR_SUCCESS', 'COORDINATOR_PROGRAM_MISSING', 'COORDINATOR_FACULTY_MISSING', 'COORDINATOR_SCOPE_MISMATCH',
    'MATRICULA_NOT_IMPLEMENTED', 'SUITE_TRANCOUNT_ZERO',
    'USP_CONSULTAR_GRUPOS_PAGINADO_SUCCESS', 'USP_CONSULTAR_GRUPOS_PAGINADO_FILTER_AND_PAGINATION',
    'USP_CONSULTAR_GRUPOS_PAGINADO_INVALID_USER', 'USP_CONSULTAR_GRUPOS_PAGINADO_CONTEXT_CLEANUP'
)
$sqlPasses = @([regex]::Matches($outputStr, '(?m)^TEST_PASS:([A-Z0-9_]+)\s*$') | ForEach-Object { $_.Groups[1].Value })
$passed = @($sqlPasses) + @($clientPassed)
$missing = @($criticalIds | Where-Object { $_ -notin $passed })
$duplicates = @($passed | Group-Object | Where-Object { $_.Count -ne 1 } | ForEach-Object { $_.Name })
$skipped = @([regex]::Matches($outputStr, '(?m)^TEST_SKIP:([A-Z0-9_]+)\s*$') | ForEach-Object { $_.Groups[1].Value })
$allowed = @($skipped | Where-Object { $_ -eq 'XACT_STATE_MINUS_ONE_RUNTIME' })
$unauthorized = @($skipped | Where-Object { $_ -ne 'XACT_STATE_MINUS_ONE_RUNTIME' })
$sqlErrors = @([regex]::Matches($outputStr, 'Msg \d+, Level \d+'))
$explicitFailures = @([regex]::Matches($outputStr, 'TEST FAILED:'))
$failed = $resultFailures.Count + $explicitFailures.Count + $duplicates.Count
if ($sqlExitCode -ne 0 -and $explicitFailures.Count -eq 0) { $failed++ }

Write-Host "TOTAL_EXPECTED=$($criticalIds.Count)"
Write-Host "TOTAL_EXECUTED=$($passed.Count + $skipped.Count + $failed)"
Write-Host "PASSED=$($passed.Count)"
Write-Host "FAILED=$failed"
Write-Host "SKIPPED=$($skipped.Count)"
Write-Host "ALLOWED_SKIPPED=$($allowed.Count)"
Write-Host "CRITICAL_MISSING=$($missing.Count)"
Write-Host "SQLCMD_EXIT_CODE=$sqlExitCode"
Write-Host "SQL_ERROR_COUNT=$($sqlErrors.Count)"
if ($resultFailures.Count) { Write-Host "RESULT_FAILURES=$($resultFailures -join '; ')" }
if ($missing.Count) { Write-Host "MISSING_IDS=$($missing -join ',')" }
if ($unauthorized.Count) { Write-Host "UNAUTHORIZED_SKIPS=$($unauthorized -join ',')" }
if ($duplicates.Count) { Write-Host "DUPLICATE_PASS_IDS=$($duplicates -join ',')" }
if ($missing.Count -or $unauthorized.Count) { Write-Host 'DB GATE INCOMPLETE' }
if ($failed -or $sqlErrors.Count -or $missing.Count -or $unauthorized.Count) { exit 1 }
Write-Host 'DB GATE PASS'
exit 0
