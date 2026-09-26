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
$resultIds = @('STUDENT_DUPLICATE', 'STUDENT_GROUP_NOT_FOUND', 'STUDENT_GROUP_DISABLED', 'STUDENT_CAPACITY_EXCEEDED', 'TEACHER_GROUP_NOT_FOUND', 'MASS_CLOSE_SUCCESS',
    'ATTENDANCE_BULK_STUDENT_NOT_IN_GROUP', 'ATTENDANCE_BULK_ATOMIC')
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
    $rows = @([regex]::Matches($block.Groups[1].Value, '(?m)^([0-9a-fA-F-]{36})\|([^|]*)\|(.*)\|\s*([01])\s*$'))
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

$concurrencySession = $null
try {
    $setupSql = @"
SET NOCOUNT ON;
DECLARE @group UNIQUEIDENTIFIER, @student UNIQUEIDENTIFIER, @owner UNIQUEIDENTIFIER;
SELECT TOP 1 @group = eg.idGrupo, @student = eg.idEstudiante, @owner = di.idUsuario
FROM dbo.uv_estudiante_grupo eg
JOIN dbo.uv_grupo g ON g.id = eg.idGrupo
JOIN dbo.uv_docente_identidad di ON di.id = g.idDocente
WHERE eg.codigoEstadoEstudiante = 'A'
  AND g.grupoEstaHablitado = 1
  AND di.estaActivoUsuario = 1
ORDER BY eg.id;
IF @group IS NULL OR @student IS NULL OR @owner IS NULL
BEGIN
    RAISERROR('ATTENDANCE_CONCURRENT_UPSERT fixture missing.', 16, 1);
    RETURN;
END;
DECLARE @session UNIQUEIDENTIFIER = NEWID();
DECLARE @number INT = 1 + (SELECT ISNULL(MAX(numero), 0) FROM dbo.Sesion WHERE grupo = @group);
INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
VALUES (@session, N'QA Concurrent Upsert', @number, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group, DATEADD(HOUR, 30, SYSUTCDATETIME()), DATEADD(HOUR, 31, SYSUTCDATETIME()));
SELECT CONCAT(CONVERT(VARCHAR(36), @session), '|', CONVERT(VARCHAR(36), @student), '|', CONVERT(VARCHAR(36), @owner));
"@
    $setup = @(docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -d gestionasistenciadb -U sa -P $Password -C -b -h -1 -W -Q $setupSql 2>&1 |
        ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '^[0-9a-fA-F-]{36}\|' })
    if ($LASTEXITCODE -ne 0 -or $setup.Count -ne 1) { throw "setup failed: $($setup -join '; ')" }
    $parts = $setup[0].Split('|')
    $concurrencySession = $parts[0]
    $concurrencyStudent = $parts[1]
    $concurrencyOwner = $parts[2]
    # Escrito a archivo y ejecutado con -i (no -Q): un -Q con comillas dobles embebidas (el JSON)
    # se corrompe al pasar por el marshalling de argumentos nativos de Windows/PowerShell.
    $workerSql = "SET NOCOUNT ON; DECLARE @corr UNIQUEIDENTIFIER = NEWID(); EXEC dbo.usp_registrar_asistencias_sesion @idSesion = '$concurrencySession', @asistenciaJSON = N'[{""idEstudiante"":""$concurrencyStudent"",""estado"":""AN""}]', @idCorrelacion = @corr, @idUsuarioEjecutor = '$concurrencyOwner';"
    $workerSqlLocalPath = Join-Path ([System.IO.Path]::GetTempPath()) "attendance_concurrent_worker_$([guid]::NewGuid().ToString('N')).sql"
    $workerSqlContainerPath = "/tmp/attendance_concurrent_worker.sql"
    Set-Content -Path $workerSqlLocalPath -Value $workerSql -Encoding utf8 -NoNewline
    docker cp $workerSqlLocalPath "${ContainerName}:$workerSqlContainerPath" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "could not copy worker sql into container." }
    docker exec -u 0 $ContainerName chmod a+r $workerSqlContainerPath | Out-Null
    Remove-Item -Path $workerSqlLocalPath -Force -ErrorAction SilentlyContinue

    $jobScript = {
        param($cn, $pw, $containerPath)
        $output = @(& docker exec $cn /opt/mssql-tools18/bin/sqlcmd -S localhost -d gestionasistenciadb -U sa -P $pw -C -b -h -1 -W -i $containerPath 2>&1)
        $exitCode = $LASTEXITCODE
        $output
        if ($exitCode -ne 0) { throw "sqlcmd failed with exit code ${exitCode}: $($output -join '; ')" }
    }
    $job1 = Start-Job -ScriptBlock $jobScript -ArgumentList $ContainerName, $Password, $workerSqlContainerPath
    $job2 = Start-Job -ScriptBlock $jobScript -ArgumentList $ContainerName, $Password, $workerSqlContainerPath
    $jobOutput = @(Receive-Job -Job $job1, $job2 -Wait -AutoRemoveJob 2>&1)
    if ($jobOutput | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }) { throw "worker failed: $($jobOutput -join '; ')" }
    $validateSql = @"
SET NOCOUNT ON;
DECLARE @headers INT = (
    SELECT COUNT(1)
    FROM dbo.Asistencia a
    JOIN dbo.EstudianteGrupo eg ON eg.id = a.estudianteGrupo
    WHERE a.sesion = '$concurrencySession' AND eg.estudiante = '$concurrencyStudent'
);
DECLARE @details INT = (
    SELECT COUNT(1)
    FROM dbo.DetalleAsistencia d
    JOIN dbo.Asistencia a ON a.id = d.asistencia
    JOIN dbo.EstudianteGrupo eg ON eg.id = a.estudianteGrupo
    WHERE a.sesion = '$concurrencySession' AND eg.estudiante = '$concurrencyStudent'
);
SELECT CONCAT(@headers, '|', @details);
"@
    $counts = @(docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -d gestionasistenciadb -U sa -P $Password -C -b -h -1 -W -Q $validateSql 2>&1 |
        ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '^\d+\|\d+$' })
    if ($LASTEXITCODE -ne 0 -or $counts.Count -ne 1 -or $counts[0] -ne '1|1') { throw "unexpected counts: $($counts -join '; ')" }
    $clientPassed += 'ATTENDANCE_CONCURRENT_UPSERT'
    Write-Host 'TEST_PASS:ATTENDANCE_CONCURRENT_UPSERT'
}
catch {
    $resultFailures += "ATTENDANCE_CONCURRENT_UPSERT $($_.Exception.Message)"
}
finally {
    try { docker exec -u 0 $ContainerName rm -f /tmp/attendance_concurrent_worker.sql 2>$null | Out-Null } catch {}
    if ($concurrencySession) {
        $cleanupSql = "SET NOCOUNT ON; DELETE d FROM dbo.DetalleAsistencia d JOIN dbo.Asistencia a ON a.id = d.asistencia WHERE a.sesion = '$concurrencySession'; DELETE FROM dbo.Asistencia WHERE sesion = '$concurrencySession'; DELETE FROM dbo.Sesion WHERE id = '$concurrencySession';"
        docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -d gestionasistenciadb -U sa -P $Password -C -Q $cleanupSql | Out-Null
    }
}

$secretScanFiles = @(
    (Join-Path $PSScriptRoot 'deploy_schema.ps1'),
    (Join-Path $PSScriptRoot 'test_summary.ps1')
)
$workflowDir = Join-Path $PSScriptRoot '.github/workflows'
if (Test-Path $workflowDir) {
    $secretScanFiles += @(Get-ChildItem $workflowDir -File -Recurse | ForEach-Object { $_.FullName })
}
$hardcodedPasswordHits = @()
foreach ($scanFile in $secretScanFiles) {
    if (-not (Test-Path $scanFile)) { continue }
    $lineNo = 0
    foreach ($line in Get-Content $scanFile) {
        $lineNo++
        if ($line -match '(?i)(MSSQL_SA_PASSWORD|SQL_CONTAINER_PASSWORD|Password)\s*[:=]\s*[''"][^$][^''"]+[''"]') {
            $hardcodedPasswordHits += "${scanFile}:$lineNo"
        }
    }
}
if ($hardcodedPasswordHits.Count -eq 0) {
    $clientPassed += 'NO_HARDCODED_DB_PASSWORD'
    Write-Host 'TEST_PASS:NO_HARDCODED_DB_PASSWORD'
}
else {
    $resultFailures += "NO_HARDCODED_DB_PASSWORD hits=$($hardcodedPasswordHits -join ',')"
}

$activeAulaHits = @()
foreach ($path in @('schema', 'test', 'migrations')) {
    $full = Join-Path $PSScriptRoot $path
    if (Test-Path $full) {
        $activeAulaHits += @(Get-ChildItem $full -File -Recurse | Select-String -Pattern 'aula' -SimpleMatch -ErrorAction SilentlyContinue)
    }
}
if ($activeAulaHits.Count -eq 0) {
    $clientPassed += 'AULA_ACTIVE_SQL_REFERENCES_ZERO'
    Write-Host 'TEST_PASS:AULA_ACTIVE_SQL_REFERENCES_ZERO'
}
else {
    $resultFailures += "AULA_ACTIVE_SQL_REFERENCES_ZERO hits=$($activeAulaHits.Count)"
}

$merPath = Join-Path $PSScriptRoot 'docs/ModeloEntidadRelacion.md'
$normativeGhostHits = @()
if (Test-Path $merPath) {
    $normativeGhostHits = @(Select-String -Path $merPath -Pattern 'NVARCHAR aula|Grupo\.aula|Sesion\.aula' -CaseSensitive:$false)
}
if ($normativeGhostHits.Count -eq 0) {
    $clientPassed += 'NORMATIVE_MODEL_GHOST_FIELDS_ZERO'
    Write-Host 'TEST_PASS:NORMATIVE_MODEL_GHOST_FIELDS_ZERO'
}
else {
    $resultFailures += "NORMATIVE_MODEL_GHOST_FIELDS_ZERO hits=$($normativeGhostHits.Count)"
}

$criticalIds = @(
    'SCHEMA_COLUMNS', 'PUBLIC_SIGNATURES', 'GROUP_PUBLIC_SIGNATURE', 'SESSION_PUBLIC_SIGNATURE', 'NO_SESSION_GHOST_FIELDS',
    'PUBLIC_VIEWS_REFRESH', 'BROKEN_DEPENDENCIES_ZERO',
    'DEPLOY_CATALOGS_NON_DESTRUCTIVE', 'CATALOG_SEEDS_NO_DUPLICATES', 'AUDIT_SCHEMA_IMMUTABLE',
    'UTC_CATALOG_TIMESTAMPS', 'UTC_AUDIT_TIMESTAMP', 'PUBLIC_SECURITY_EXECUTOR_REQUIRED',
    'SESSION_IDDOCENTE_REMOVED', 'PUBLIC_CANONICAL_RESULTSET',
    'CATALOG_PARAMETER_CACHE_CONTRACT', 'CATALOG_MESSAGE_CACHE_CONTRACT',
    'TECHNICAL_CODE_CHANNEL', 'TECHNICAL_CODE_CHANNEL_FALLBACK',
    'SEC_001_PREFIX', 'SEC_002_PREFIX', 'ATT_PREFIX', 'SES_PREFIX', 'RC_001_PREFIX', 'GEN_002_PREFIX', 'EST_004_PREFIX',
    'NO_HARDCODED_DB_PASSWORD', 'AULA_ACTIVE_SQL_REFERENCES_ZERO', 'NORMATIVE_MODEL_GHOST_FIELDS_ZERO',
    'PUBLIC_SP_INVENTORY', 'PUBLIC_VIEW_INVENTORY',
    'USER_SYNC_SUCCESS', 'USER_SYNC_INVALID', 'DEAN_SUCCESS',
    'SESSION_CLOSE_NOT_SUPPORTED',
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
    'SESSION_CREATE', 'SESSION_UPDATE', 'SESSION_NON_OWNER', 'SESSION_REQUIRED_START',
    'SESSION_REQUIRED_END', 'SESSION_END_AFTER_START', 'SESSION_EXECUTOR_REQUIRED', 'SESSION_NOT_FOUND_CODE',
    'SESSION_GENERATION_SUCCESS', 'SESSION_GENERATION_IDEMPOTENT', 'SESSION_GENERATION_INVALID', 'UTC_SESSION_GENERATION',
    'SESSION_SEQUENCE_USES_MAX_NOT_COUNT', 'SESSION_CODE_OVER_99', 'SESSION_CREATE_NO_DUPLICATE_NUMBER_CODE',
    'VIEW_RAZON_CAUSA_CONTRACT', 'VIEW_DETALLE_ASISTENCIA_CONTRACT',
    'TITULARIDAD_GRUPO_USUARIO_ID', 'TITULARIDAD_SESION_USUARIO_ID', 'TITULARIDAD_PROGRAMA_USUARIO_ID', 'TITULARIDAD_FACULTAD_USUARIO_ID',
    'ATTENDANCE_BULK_SUCCESS', 'ATTENDANCE_BULK_SJC', 'ATTENDANCE_BULK_EX', 'ATTENDANCE_BULK_INVALID_JSON',
    'ATTENDANCE_BULK_PARTIAL_ALLOWED', 'ATTENDANCE_BULK_OMITTED_STUDENT_UNCHANGED',
    'ATTENDANCE_BULK_IDEMPOTENT_SAME_STATE', 'ATTENDANCE_BULK_UPDATE_EXISTING_STATE',
    'ATTENDANCE_NO_DUPLICATE_HEADER', 'ATTENDANCE_NO_DUPLICATE_DETAIL',
    'ATTENDANCE_STATE_AN_CONSISTENCY', 'ATTENDANCE_STATE_SJC_CONSISTENCY', 'ATTENDANCE_STATE_EX_CONSISTENCY',
    'ATTENDANCE_READ_ONLY_PERSISTED_ROWS', 'ATTENDANCE_READ_CANONICAL_CODE',
    'ATTENDANCE_CONCURRENT_UPSERT',
    'ATTENDANCE_BULK_NOT_ARRAY', 'ATTENDANCE_BULK_EMPTY', 'ATTENDANCE_BULK_DUPLICATE_STUDENT',
    'ATTENDANCE_BULK_MISSING_STATE',
    'ATTENDANCE_BULK_INVALID',
    'ATTENDANCE_BULK_INVALID_STATE', 'ATTENDANCE_BULK_EXECUTOR_REQUIRED', 'ATTENDANCE_BULK_NON_OWNER',
    'ATTENDANCE_HELPER_CLOSED_CATALOG', 'ATTENDANCE_NO_LEGACY_PUBLIC_STATE',
    'ATTENDANCE_BULK_STUDENT_NOT_IN_GROUP', 'ATTENDANCE_BULK_ATOMIC',
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
Write-Host "UNAUTHORIZED_SKIPS=$($unauthorized.Count)"
if ($passed -contains 'SUITE_TRANCOUNT_ZERO') { Write-Host '@@TRANCOUNT=0' }
if ($resultFailures.Count) { Write-Host "RESULT_FAILURES=$($resultFailures -join '; ')" }
if ($missing.Count) { Write-Host "MISSING_IDS=$($missing -join ',')" }
if ($unauthorized.Count) { Write-Host "UNAUTHORIZED_SKIP_IDS=$($unauthorized -join ',')" }
if ($duplicates.Count) { Write-Host "DUPLICATE_PASS_IDS=$($duplicates -join ',')" }
if ($missing.Count -or $unauthorized.Count) { Write-Host 'DB GATE INCOMPLETE' }
if ($failed -or $sqlErrors.Count -or $missing.Count -or $unauthorized.Count) { exit 1 }
Write-Host 'DB GATE PASS'
exit 0
