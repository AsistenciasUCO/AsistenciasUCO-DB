param ([string]$ContainerName, [string]$Password, [switch]$ParserSelfTestOnly)

$ErrorActionPreference = 'Stop'

function Test-CanonicalResultBlock {
    param (
        [string]$OutputText,
        [string]$ResultId,
        [string]$ExpectedState,
        [string]$ExpectedErrorCode
    )

    $escapedId = [regex]::Escape($ResultId)
    $beginMarkers = [regex]::Matches($OutputText, "(?m)^TEST_RESULT_BEGIN:$escapedId\r?$")
    $endMarkers = [regex]::Matches($OutputText, "(?m)^TEST_RESULT_END:$escapedId\r?$")
    $userMarkers = [regex]::Matches($OutputText, "(?m)^TEST_EXPECTED_USER:$escapedId\|([^\r\n]*)\r?$")
    # The CI log's merged SQLCMD capture showed this one known prefix on a PRINT line.
    # Accept only the observed literal "o." before this official marker; keep every other
    # marker anchored and exact, and reject duplicate clean/prefixed copies below.
    $techMarkers = [regex]::Matches($OutputText, "(?m)^(?:o\.)?TEST_EXPECTED_TECH:$escapedId\|([^\r\n]*)\r?$")
    $techRegexMarkers = [regex]::Matches($OutputText, "(?m)^TEST_EXPECTED_TECH_REGEX:$escapedId\|([^\r\n]*)\r?$")
    $stateMarkers = [regex]::Matches($OutputText, "(?m)^TEST_STATE_PASS:$escapedId\r?$")

    if ($beginMarkers.Count -ne 1 -or $endMarkers.Count -ne 1 -or $beginMarkers[0].Index -ge $endMarkers[0].Index) {
        return [pscustomobject]@{ Success = $false; Failure = 'missing, duplicated, or out-of-order result boundary' }
    }
    if ($userMarkers.Count -ne 1 -or ($techMarkers.Count + $techRegexMarkers.Count) -ne 1 -or $stateMarkers.Count -ne 1) {
        return [pscustomobject]@{ Success = $false; Failure = 'missing or duplicated catalog expectation/state assertion' }
    }

    $bodyStart = $beginMarkers[0].Index + $beginMarkers[0].Length
    $body = $OutputText.Substring($bodyStart, $endMarkers[0].Index - $bodyStart)
    $rows = [regex]::Matches($body, '(?im)^([0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12})\|([^|\r\n]*)\|(.*)\|\s*([01])\s*$')
    if ($rows.Count -ne 1) {
        return [pscustomobject]@{ Success = $false; Failure = "expected one canonical row; found $($rows.Count)" }
    }
    if ($body -match 'SECRET_MARKER') {
        return [pscustomobject]@{ Success = $false; Failure = 'leaked the password marker in the canonical result' }
    }

    $row = $rows[0]
    $expectedUser = $userMarkers[0].Groups[1].Value.Trim()
    if ($row.Groups[4].Value -ne $ExpectedState -or $row.Groups[2].Value.Trim() -cne $expectedUser) {
        return [pscustomobject]@{ Success = $false; Failure = "actual result differs from state=$ExpectedState/catalog user message" }
    }

    $expectedTech = if ($techMarkers.Count -eq 1) { $techMarkers[0].Groups[1].Value.Trim() } else { $null }
    $expectedTechRegex = if ($techRegexMarkers.Count -eq 1) { $techRegexMarkers[0].Groups[1].Value.Trim() } else { $null }
    $actualTech = $row.Groups[3].Value.Trim()
    if ($expectedTechRegex) {
        if ($actualTech -notmatch $expectedTechRegex) {
            return [pscustomobject]@{ Success = $false; Failure = 'actual technical message does not match its expected pattern' }
        }
    }
    elseif ($actualTech -cne $expectedTech) {
        return [pscustomobject]@{ Success = $false; Failure = 'actual technical message differs from the catalog expectation' }
    }

    if ($ExpectedErrorCode) {
        if ($expectedTech -cnotmatch ('^DBCODE=' + [regex]::Escape($ExpectedErrorCode) + '\|') -or
            $actualTech -cnotmatch ('^DBCODE=' + [regex]::Escape($ExpectedErrorCode) + '\|')) {
            return [pscustomobject]@{ Success = $false; Failure = "expected technical catalog code $ExpectedErrorCode" }
        }
        $correlation = [regex]::Match($expectedTech, '(?:^|\s)Correlacion:\s*([0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})\s*$')
        if (-not $correlation.Success -or $row.Groups[1].Value -ine $correlation.Groups[1].Value) {
            return [pscustomobject]@{ Success = $false; Failure = 'result correlation does not match the expected technical marker' }
        }
    }

    return [pscustomobject]@{ Success = $true; Failure = $null }
}

function Invoke-ResultParserSelfTests {
    $id = 'SES01_AUTO_CLOSED'
    $correlation = 'f7f690e0-68cc-45bc-a50e-622056bf23a1'
    $otherCorrelation = '03f3a4c8-1c6e-4bb4-86b9-f968acbda92d'
    $technical = "DBCODE=SES_008|La sesión está cerrada. Correlacion: $correlation"
    $row = "$correlation|La sesión ya finalizó.|$technical|0"
    $base = @(
        "TEST_EXPECTED_USER:$id|La sesión ya finalizó."
        "TEST_EXPECTED_TECH:$id|$technical"
        "TEST_RESULT_BEGIN:$id"
        $row
        "TEST_RESULT_END:$id"
        "TEST_STATE_PASS:$id"
    ) -join "`n"

    $cases = @(
        @{ Name = 'CLEAN'; Text = $base; Expected = $true; Code = 'SES_008' },
        @{ Name = 'CLEAN_CRLF'; Text = $base.Replace("`n", "`r`n"); Expected = $true; Code = 'SES_008' },
        @{ Name = 'OBSERVED_PREFIX'; Text = $base.Replace("TEST_EXPECTED_TECH:$id|", "o.TEST_EXPECTED_TECH:$id|"); Expected = $true; Code = 'SES_008' },
        @{ Name = 'STATE_ONLY_FORGERY'; Text = "TEST_STATE_PASS:$id"; Expected = $false; Code = 'SES_008' },
        @{ Name = 'DUPLICATE_ROW'; Text = $base.Replace("$row`nTEST_RESULT_END", "$row`n$row`nTEST_RESULT_END"); Expected = $false; Code = 'SES_008' },
        @{ Name = 'INCOMPLETE_BLOCK'; Text = $base.Replace("TEST_RESULT_END:$id`n", ''); Expected = $false; Code = 'SES_008' },
        @{ Name = 'WRONG_CATALOG_MESSAGE'; Text = $base.Replace("TEST_EXPECTED_USER:$id|La sesión ya finalizó.", "TEST_EXPECTED_USER:$id|Mensaje de catálogo incorrecto."); Expected = $false; Code = 'SES_008' },
        @{ Name = 'WRONG_ERROR_CODE'; Text = $base; Expected = $false; Code = 'SES_007' },
        @{ Name = 'CORRELATION_MISMATCH'; Text = $base.Replace("$correlation|La sesión ya finalizó.", "$otherCorrelation|La sesión ya finalizó."); Expected = $false; Code = 'SES_008' },
        @{ Name = 'DUPLICATE_TECH_MARKER'; Text = "$base`nTEST_EXPECTED_TECH:$id|$technical"; Expected = $false; Code = 'SES_008' }
    )

    foreach ($case in $cases) {
        $parsed = Test-CanonicalResultBlock -OutputText $case.Text -ResultId $id -ExpectedState '0' -ExpectedErrorCode $case.Code
        if ($parsed.Success -ne $case.Expected) {
            throw "Result parser self-test $($case.Name) failed: $($parsed.Failure)"
        }
        Write-Host "TEST_PARSER_PASS:$($case.Name)"
    }
}

Invoke-ResultParserSelfTests
if ($ParserSelfTestOnly) { exit 0 }

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
    $Password = if ($env:SQL_CONTAINER_PASSWORD) { $env:SQL_CONTAINER_PASSWORD } elseif ($env:MSSQL_SA_PASSWORD) { $env:MSSQL_SA_PASSWORD } else { $null }
}
if (-not $Password) {
    throw "SQL password is required. Create a local '.env' file from '.env.template', set SQL_CONTAINER_PASSWORD/MSSQL_SA_PASSWORD, or pass -Password."
}
if ($Password -ceq 'CHANGE_ME') {
    throw "SQL password is still the 'CHANGE_ME' placeholder. Set a real local value in '.env' (ignored by Git)."
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
$resultIds = @('STUDENT_DUPLICATE', 'STUDENT_GROUP_NOT_FOUND', 'STUDENT_GROUP_DISABLED', 'STUDENT_CAPACITY_EXCEEDED', 'MASS_CLOSE_SUCCESS',
    'ATTENDANCE_BULK_STUDENT_NOT_IN_GROUP', 'ATTENDANCE_BULK_ATOMIC',
    # CC-003G-01: rechazos y fallos forzados de los proveedores publicos (el SP ejecuta ROLLBACK internamente)
    'USER_SYNC_PUBLIC_DUPLICATE_DOCUMENT', 'USER_SYNC_PUBLIC_DUPLICATE_EMAIL', 'USER_SYNC_PUBLIC_CONFLICTING_PROFILE',
    'USER_SYNC_PUBLIC_INVALID_EMAIL', 'USER_SYNC_PUBLIC_EMPTY_PASSWORD', 'USER_SYNC_PUBLIC_UNKNOWN_ID_TYPE',
    'USER_SYNC_PUBLIC_ROLLBACK_SAVEPOINT', 'USER_SYNC_PUBLIC_ROLLBACK_OWN_TRANSACTION', 'USER_SYNC_PUBLIC_INACTIVE_REPLAY',
    'PLAN_PUBLIC_DUPLICATE_BUSINESS_KEY', 'PLAN_PUBLIC_UPDATE_TO_TAKEN_INP', 'PLAN_PUBLIC_FOREIGN_PLAN',
    'PLAN_PUBLIC_ROLLBACK_SAVEPOINT', 'PLAN_PUBLIC_ROLLBACK_OWN_TRANSACTION',
    # F1: rechazo de usp_guardar_horarios_grupo despues de escribir (rollback a savepoint y transaccion propia)
    'GROUP_SCHEDULE_TEACHER_CONFLICT_SAVEPOINT', 'GROUP_SCHEDULE_TEACHER_CONFLICT_OWN_TRANSACTION',
    # SES-01: rechazos por ventana de registro (el SP revierte su savepoint/transaccion)
    'SES01_BULK_BEFORE_START', 'SES01_BULK_EXACT_END', 'SES01_BULK_TWO_HOURS_AFTER', 'SES01_BULK_INDETERMINATE',
    'SES01_BULK_CLOSED_HISTORY_PRESERVED', 'SES01_AUTO_CLOSED', 'SES01_AUTO_BEFORE_START', 'SES01_AUTO_INDETERMINATE',
    # CULM-001 B.1 (B1-VEN-04): el lote congelado rechaza una sesion cancelada con SES_010 (revierte su savepoint)
    'CULM001_B1_VEN_04_LOTE_CONGELADO')
$resultFailures = @()
$clientPassed = @()
$ses01ExpectedErrorCodes = @{
    SES01_BULK_BEFORE_START = 'SES_007'
    SES01_BULK_EXACT_END = 'SES_008'
    SES01_BULK_TWO_HOURS_AFTER = 'SES_008'
    SES01_BULK_INDETERMINATE = 'SES_009'
    SES01_BULK_CLOSED_HISTORY_PRESERVED = 'SES_008'
    SES01_AUTO_CLOSED = 'SES_008'
    SES01_AUTO_BEFORE_START = 'SES_007'
    SES01_AUTO_INDETERMINATE = 'SES_009'
    CULM001_B1_VEN_04_LOTE_CONGELADO = 'SES_010'
}
foreach ($id in $resultIds) {
    $expectedState = if ($id -eq 'MASS_CLOSE_SUCCESS') { '1' } else { '0' }
    $expectedErrorCode = if ($ses01ExpectedErrorCodes.ContainsKey($id)) { $ses01ExpectedErrorCodes[$id] } else { $null }
    $parsedResult = Test-CanonicalResultBlock -OutputText $outputStr -ResultId $id -ExpectedState $expectedState -ExpectedErrorCode $expectedErrorCode
    if (-not $parsedResult.Success) {
        $resultFailures += "$id $($parsedResult.Failure)"
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
-- SES-01: el upsert concurrente solo puede escribir con la sesion activa y procedencia UTC confirmada.
INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
VALUES (@session, N'QA Concurrent Upsert', @number, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group, DATEADD(HOUR, -1, SYSUTCDATETIME()), DATEADD(HOUR, 1, SYSUTCDATETIME()), N'UTC_V2');
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
    $cleanupErrors = @()
    try {
        docker exec -u 0 $ContainerName rm -f /tmp/attendance_concurrent_worker.sql 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { $cleanupErrors += 'attendance worker file cleanup returned a non-zero exit code' }
    }
    catch {
        $cleanupErrors += 'attendance worker file cleanup raised an exception'
    }
    if ($concurrencySession) {
        $cleanupSql = "SET NOCOUNT ON; DELETE d FROM dbo.DetalleAsistencia d JOIN dbo.Asistencia a ON a.id = d.asistencia WHERE a.sesion = '$concurrencySession'; DELETE FROM dbo.Asistencia WHERE sesion = '$concurrencySession'; DELETE FROM dbo.Sesion WHERE id = '$concurrencySession';"
        try {
            docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -d gestionasistenciadb -U sa -P $Password -C -Q $cleanupSql | Out-Null
            if ($LASTEXITCODE -ne 0) { $cleanupErrors += 'attendance SQL cleanup returned a non-zero exit code' }
        }
        catch {
            $cleanupErrors += 'attendance SQL cleanup raised an exception'
        }
    }
    if ($cleanupErrors.Count -gt 0) {
        $resultFailures += "ATTENDANCE_CONCURRENT_UPSERT cleanup failed: $($cleanupErrors -join '; ')"
    }
}

# Secret hygiene (DB-GP-001C): scans scripts, workflows, env templates and versioned config.
# Findings are reported as file:line:type only; the secret value is never printed.
# UTC-D06-POST-FREEZE: dos conexiones crean sesiones v2 en paralelo sobre el mismo grupo. El correlativo
# (UPDLOCK, HOLDLOCK) no se duplica y TODAS las filas quedan UTC_V2 (horas y marca en el mismo INSERT).
$d06Group = $null
$d06Tag = "D06C-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
try {
    $d06SetupSql = @"
SET NOCOUNT ON;
SELECT TOP 1 CONCAT(CONVERT(VARCHAR(36), g.id), '|', CONVERT(VARCHAR(36), di.idUsuario))
FROM dbo.uv_grupo g JOIN dbo.uv_docente_identidad di ON di.id = g.idDocente
WHERE g.grupoEstaHablitado = 1 AND di.estaActivoUsuario = 1
ORDER BY g.cuposDisponibles DESC;
"@
    $d06Setup = @(docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -d gestionasistenciadb -U sa -P $Password -C -b -h -1 -W -Q $d06SetupSql 2>&1 |
        ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '^[0-9a-fA-F-]{36}\|' })
    if ($LASTEXITCODE -ne 0 -or $d06Setup.Count -ne 1) { throw "setup failed: $($d06Setup -join '; ')" }
    $d06Group = $d06Setup[0].Split('|')[0]
    $d06Owner = $d06Setup[0].Split('|')[1]
    $d06WorkerSql = "SET NOCOUNT ON; DECLARE @i INT = 0; WHILE @i < 5 BEGIN DECLARE @corr UNIQUEIDENTIFIER = NEWID(); EXEC dbo.usp_crear_sesion_v2 @idGrupo = '$d06Group', @nombre = N'$d06Tag', @fechaHoraInicio = '2027-01-10T13:00:00', @fechaHoraFin = '2027-01-10T14:00:00', @idCorrelacion = @corr, @idUsuarioEjecutor = '$d06Owner'; SET @i += 1; END"
    $d06Local = Join-Path ([System.IO.Path]::GetTempPath()) "utc_d06_concurrent_worker_$([guid]::NewGuid().ToString('N')).sql"
    Set-Content -Path $d06Local -Value $d06WorkerSql -Encoding utf8 -NoNewline
    docker cp $d06Local "${ContainerName}:/tmp/utc_d06_concurrent_worker.sql" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'could not copy D06 worker sql into container.' }
    docker exec -u 0 $ContainerName chmod a+r /tmp/utc_d06_concurrent_worker.sql | Out-Null
    Remove-Item -Path $d06Local -Force -ErrorAction SilentlyContinue
    $d06Job = {
        param($cn, $pw)
        $output = @(& docker exec $cn /opt/mssql-tools18/bin/sqlcmd -S localhost -d gestionasistenciadb -U sa -P $pw -C -b -h -1 -W -i /tmp/utc_d06_concurrent_worker.sql 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "sqlcmd failed: $($output -join '; ')" }
    }
    $d06Jobs = @(
        (Start-Job -ScriptBlock $d06Job -ArgumentList $ContainerName, $Password),
        (Start-Job -ScriptBlock $d06Job -ArgumentList $ContainerName, $Password)
    )
    $d06Out = @(Receive-Job -Job $d06Jobs -Wait -AutoRemoveJob 2>&1)
    if ($d06Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }) { throw "worker failed: $($d06Out -join '; ')" }
    $d06ValidateSql = "SET NOCOUNT ON; SELECT CONCAT(COUNT(1), '|', COUNT(DISTINCT numero), '|', COUNT(DISTINCT codigo), '|', SUM(CASE WHEN procedenciaTemporal = N'UTC_V2' THEN 1 ELSE 0 END)) FROM dbo.Sesion WHERE grupo = '$d06Group' AND nombre = N'$d06Tag';"
    $d06Counts = @(docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -d gestionasistenciadb -U sa -P $Password -C -b -h -1 -W -Q $d06ValidateSql 2>&1 |
        ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '^\d+\|\d+\|\d+\|\d+$' })
    if ($LASTEXITCODE -ne 0 -or $d06Counts.Count -ne 1 -or $d06Counts[0] -ne '10|10|10|10') { throw "unexpected counts: $($d06Counts -join '; ')" }
    $clientPassed += 'UTC_D06_CONCURRENT_V2_CREATE'
    Write-Host 'TEST_PASS:UTC_D06_CONCURRENT_V2_CREATE'
}
catch {
    $resultFailures += "UTC_D06_CONCURRENT_V2_CREATE $($_.Exception.Message)"
}
finally {
    $cleanupErrors = @()
    try {
        docker exec -u 0 $ContainerName rm -f /tmp/utc_d06_concurrent_worker.sql 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { $cleanupErrors += 'D06 worker file cleanup returned a non-zero exit code' }
    }
    catch {
        $cleanupErrors += 'D06 worker file cleanup raised an exception'
    }
    if ($d06Group) {
        try {
            docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -d gestionasistenciadb -U sa -P $Password -C -Q "SET NOCOUNT ON; DELETE FROM dbo.Sesion WHERE grupo = '$d06Group' AND nombre = N'$d06Tag';" | Out-Null
            if ($LASTEXITCODE -ne 0) { $cleanupErrors += 'D06 SQL cleanup returned a non-zero exit code' }
        }
        catch {
            $cleanupErrors += 'D06 SQL cleanup raised an exception'
        }
    }
    if ($cleanupErrors.Count -gt 0) {
        $resultFailures += "UTC_D06_CONCURRENT_V2_CREATE cleanup failed: $($cleanupErrors -join '; ')"
    }
}

# CC-003G-01: carreras REALES entre dos sesiones sqlcmd sobre los proveedores publicos (dbo.Usuario y dbo.PlanEstudio
# no tienen indices unicos de negocio: la unicidad la garantiza la serializacion dentro del SP).
function Invoke-Cc003g01WorkerPair {
    param([string]$SqlA, [string]$SqlB, [string]$Label)
    $remotes = @()
    foreach ($pair in @(@('a', $SqlA), @('b', $SqlB))) {
        $local = Join-Path ([System.IO.Path]::GetTempPath()) "cc003g01_$($Label)_$($pair[0])_$([guid]::NewGuid().ToString('N')).sql"
        Set-Content -Path $local -Value $pair[1] -Encoding utf8
        $remote = "/tmp/cc003g01_$($Label)_$($pair[0]).sql"
        docker cp $local "${ContainerName}:$remote" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "could not copy CC-003G-01 worker $($pair[0])." }
        docker exec -u 0 $ContainerName chmod a+r $remote | Out-Null
        Remove-Item -Path $local -Force -ErrorAction SilentlyContinue
        $remotes += $remote
    }
    $job = {
        param($cn, $pw, $file)
        $output = @(& docker exec $cn /opt/mssql-tools18/bin/sqlcmd -S localhost -d gestionasistenciadb -U sa -P $pw -C -b -h -1 -W -s '|' -w 65535 -i $file 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "sqlcmd failed: $($output -join '; ')" }
        $output
    }
    $jobs = @((Start-Job -ScriptBlock $job -ArgumentList $ContainerName, $Password, $remotes[0]),
              (Start-Job -ScriptBlock $job -ArgumentList $ContainerName, $Password, $remotes[1]))
    $out = @(Receive-Job -Job $jobs -Wait -AutoRemoveJob 2>&1)
    foreach ($r in $remotes) { docker exec -u 0 $ContainerName rm -f $r 2>$null | Out-Null }
    if ($out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }) { throw "worker failed: $($out -join '; ')" }
    return @($out | ForEach-Object { "$_" })
}
function Get-Cc003g01States { param([string[]]$Lines)
    return @($Lines | Where-Object { $_ -match '^[0-9A-Fa-f-]{36}\|.*\|\s*[01]\s*$' } | ForEach-Object { ($_ -replace '^.*\|\s*([01])\s*$', '$1') })
}
$ccTag = "cc3g$([guid]::NewGuid().ToString('N').Substring(0, 10))"
$ccCount = 5
try {
    $ccFx = @(docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -d gestionasistenciadb -U sa -P $Password -C -b -h -1 -W -Q @"
SET NOCOUNT ON;
SELECT TOP 1 CONCAT(CONVERT(VARCHAR(36), (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC')), '|',
       CONVERT(VARCHAR(36), p.id), '|', CONVERT(VARCHAR(36), ci.idUsuario))
FROM dbo.uv_programa p JOIN dbo.uv_coordinador_identidad ci ON ci.id = p.idCoordinador
WHERE ci.estaActivoUsuario = 1 ORDER BY p.id;
"@ 2>&1 | ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '^[0-9A-Fa-f-]{36}\|[0-9A-Fa-f-]{36}\|[0-9A-Fa-f-]{36}$' })
    if ($LASTEXITCODE -ne 0 -or $ccFx.Count -ne 1) { throw "CC-003G-01 concurrency fixtures missing: $($ccFx -join '; ')" }
    $ccTipo, $ccPrograma, $ccCoord = $ccFx[0].Split('|')
    $ccBase = 1700000000 + (Get-Random -Minimum 1 -Maximum 90000000)

    # (1) Usuario: mismas solicitudes exactas desde dos sesiones => una fila por identidad y todo exito (alta o reintento)
    $userCalls = { param($offset) (1..$ccCount | ForEach-Object {
        "EXEC dbo.usp_sincronizar_usuario @idTipoIdIdentificacion = '$ccTipo', @numeroIdentificacion = $($ccBase + $_ + $offset), @primerApellido = N'Race', @segundoApellido = N'Gate', @primerNombre = N'Same', @segundoNombre = N'Request', @correo = N'$ccTag.same.$_@test.local', @password = N'HashBackend_CC003G01_SECRET_MARKER_RACE', @idCorrelacion = '$([guid]::NewGuid())';" }) -join "`n" }
    $outSame = Invoke-Cc003g01WorkerPair -SqlA ("SET NOCOUNT ON;`n" + (& $userCalls 0)) -SqlB ("SET NOCOUNT ON;`n" + (& $userCalls 0)) -Label 'usersame'
    $sameStates = Get-Cc003g01States $outSame
    $sameCounts = @(docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -d gestionasistenciadb -U sa -P $Password -C -b -h -1 -W -Q "SET NOCOUNT ON; SELECT CONCAT(COUNT(*), '|', COUNT(DISTINCT numeroIdentificacion), '|', COUNT(DISTINCT correo)) FROM dbo.Usuario WHERE correo LIKE N'$ccTag.same.%';" 2>&1 | ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '^\d+\|\d+\|\d+$' })
    if ($sameStates.Count -ne (2 * $ccCount) -or ($sameStates | Where-Object { $_ -ne '1' }) -or $sameCounts.Count -ne 1 -or $sameCounts[0] -ne "$ccCount|$ccCount|$ccCount") {
        throw "same-request race: states=$($sameStates -join ',') counts=$($sameCounts -join ';')"
    }
    $clientPassed += 'CC003G01_CONCURRENT_USER_IDENTICAL'
    Write-Host 'TEST_PASS:CC003G01_CONCURRENT_USER_IDENTICAL'

    # (2) Usuario: mismo correo con documentos distintos => exactamente un ganador por correo
    $conflictCalls = { param($offset) (1..$ccCount | ForEach-Object {
        "EXEC dbo.usp_sincronizar_usuario @idTipoIdIdentificacion = '$ccTipo', @numeroIdentificacion = $($ccBase + 100 + $_ + $offset), @primerApellido = N'Race', @segundoApellido = N'Gate', @primerNombre = N'Same', @segundoNombre = N'Email', @correo = N'$ccTag.conflict.$_@test.local', @password = N'HashBackend_CC003G01_SECRET_MARKER_RACE', @idCorrelacion = '$([guid]::NewGuid())';" }) -join "`n" }
    $outConflict = Invoke-Cc003g01WorkerPair -SqlA ("SET NOCOUNT ON;`n" + (& $conflictCalls 0)) -SqlB ("SET NOCOUNT ON;`n" + (& $conflictCalls 1000)) -Label 'userconflict'
    $conflictStates = Get-Cc003g01States $outConflict
    $conflictCounts = @(docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -d gestionasistenciadb -U sa -P $Password -C -b -h -1 -W -Q "SET NOCOUNT ON; SELECT CONCAT(COUNT(*), '|', COUNT(DISTINCT correo)) FROM dbo.Usuario WHERE correo LIKE N'$ccTag.conflict.%';" 2>&1 | ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '^\d+\|\d+$' })
    $conflictWins = @($conflictStates | Where-Object { $_ -eq '1' }).Count
    if ($conflictStates.Count -ne (2 * $ccCount) -or $conflictWins -ne $ccCount -or $conflictCounts.Count -ne 1 -or $conflictCounts[0] -ne "$ccCount|$ccCount") {
        throw "same-email race: wins=$conflictWins of $($conflictStates.Count) counts=$($conflictCounts -join ';')"
    }
    $clientPassed += 'CC003G01_CONCURRENT_USER_CONFLICT_EMAIL'
    Write-Host 'TEST_PASS:CC003G01_CONCURRENT_USER_CONFLICT_EMAIL'

    # (3) Plan: mismo (programa, inp) con ids distintos desde dos sesiones => un solo plan por inp
    $ccInpBase = 40000 + (Get-Random -Minimum 1 -Maximum 5000) * 10
    $planCalls = { (1..$ccCount | ForEach-Object {
        "EXEC dbo.usp_registrar_o_actualizar_plan_estudio @idPlanEstudio = '$([guid]::NewGuid())', @idPrograma = '$ccPrograma', @inp = $($ccInpBase + $_), @idCorrelacion = '$([guid]::NewGuid())', @idUsuarioEjecutor = '$ccCoord';" }) -join "`n" }
    $outPlan = Invoke-Cc003g01WorkerPair -SqlA ("SET NOCOUNT ON;`n" + (& $planCalls)) -SqlB ("SET NOCOUNT ON;`n" + (& $planCalls)) -Label 'plandup'
    $planStates = Get-Cc003g01States $outPlan
    $planCounts = @(docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -d gestionasistenciadb -U sa -P $Password -C -b -h -1 -W -Q "SET NOCOUNT ON; SELECT CONCAT(COUNT(*), '|', COUNT(DISTINCT inp)) FROM dbo.PlanEstudio WHERE programa = '$ccPrograma' AND inp BETWEEN $($ccInpBase + 1) AND $($ccInpBase + $ccCount);" 2>&1 | ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '^\d+\|\d+$' })
    $planWins = @($planStates | Where-Object { $_ -eq '1' }).Count
    if ($planStates.Count -ne (2 * $ccCount) -or $planWins -ne $ccCount -or $planCounts.Count -ne 1 -or $planCounts[0] -ne "$ccCount|$ccCount") {
        throw "plan business-key race: wins=$planWins of $($planStates.Count) counts=$($planCounts -join ';')"
    }
    $clientPassed += 'CC003G01_CONCURRENT_PLAN_DUPLICATE_KEY'
    Write-Host 'TEST_PASS:CC003G01_CONCURRENT_PLAN_DUPLICATE_KEY'

    # (4) Plan: mismo id + inp desde dos sesiones (reintento simultaneo) => idempotente, una fila, todo exito
    $ccPlanIds = 1..$ccCount | ForEach-Object { [guid]::NewGuid().ToString() }
    $sameIdCalls = { (1..$ccCount | ForEach-Object {
        "EXEC dbo.usp_registrar_o_actualizar_plan_estudio @idPlanEstudio = '$($ccPlanIds[$_ - 1])', @idPrograma = '$ccPrograma', @inp = $($ccInpBase + 100 + $_), @idCorrelacion = '$([guid]::NewGuid())', @idUsuarioEjecutor = '$ccCoord';" }) -join "`n" }
    $outPlanSame = Invoke-Cc003g01WorkerPair -SqlA ("SET NOCOUNT ON;`n" + (& $sameIdCalls)) -SqlB ("SET NOCOUNT ON;`n" + (& $sameIdCalls)) -Label 'planidem'
    $planSameStates = Get-Cc003g01States $outPlanSame
    $idList = ($ccPlanIds | ForEach-Object { "'$_'" }) -join ','
    $planSameCounts = @(docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -d gestionasistenciadb -U sa -P $Password -C -b -h -1 -W -Q "SET NOCOUNT ON; SELECT CONCAT(COUNT(*), '|', COUNT(DISTINCT id)) FROM dbo.PlanEstudio WHERE id IN ($idList);" 2>&1 | ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '^\d+\|\d+$' })
    if ($planSameStates.Count -ne (2 * $ccCount) -or ($planSameStates | Where-Object { $_ -ne '1' }) -or $planSameCounts.Count -ne 1 -or $planSameCounts[0] -ne "$ccCount|$ccCount") {
        throw "plan idempotent race: states=$($planSameStates -join ',') counts=$($planSameCounts -join ';')"
    }
    $clientPassed += 'CC003G01_CONCURRENT_PLAN_IDEMPOTENT'
    Write-Host 'TEST_PASS:CC003G01_CONCURRENT_PLAN_IDEMPOTENT'
}
catch {
    $resultFailures += "CC003G01_CONCURRENCY $($_.Exception.Message)"
}
finally {
    $ccCleanup = "SET NOCOUNT ON; DELETE FROM dbo.Usuario WHERE correo LIKE N'$ccTag.%'; DELETE FROM dbo.PlanEstudio WHERE programa = '$ccPrograma' AND (inp BETWEEN $($ccInpBase + 1) AND $($ccInpBase + $ccCount) OR inp BETWEEN $($ccInpBase + 101) AND $($ccInpBase + 100 + $ccCount));"
    if ($ccPrograma) { docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -d gestionasistenciadb -U sa -P $Password -C -Q $ccCleanup | Out-Null }
}

# CC-003G-01: login real de minimo privilegio (no sa) para los dos proveedores.
try {
    $rtOutput = @(& (Join-Path $PSScriptRoot 'test/verify_runtime_role_cc003g01.ps1') -ContainerName $ContainerName -AdminPassword $Password 2>&1 | ForEach-Object { "$_" })
    foreach ($line in $rtOutput) { Write-Host $line }
    foreach ($id in @('CC003G01_RUNTIME_EXECUTE_GRANTS', 'CC003G01_RUNTIME_INTERNAL_EXEC_DENIED', 'CC003G01_RUNTIME_DIRECT_DML_DENIED',
            'CC003G01_RUNTIME_BASE_TABLE_READ_DENIED', 'CC003G01_RUNTIME_PROVIDERS_FUNCTIONAL')) {
        if ($rtOutput -contains "TEST_PASS:$id") { $clientPassed += $id }
        else { $resultFailures += "$id not reported by verify_runtime_role_cc003g01.ps1" }
    }
}
catch {
    $resultFailures += "CC003G01_RUNTIME_LOGIN $($_.Exception.Message)"
}

# F2: dos sqlcmd independientes precargan el mismo grupo y luego se valida el reintento.
try {
    $preloadConcurrencyOutput = @(& (Join-Path $PSScriptRoot 'test/test_usp_precargar_sesiones_concurrency.ps1') `
        -ContainerName $ContainerName -Password $Password 2>&1 | ForEach-Object { "$_" })
    foreach ($line in $preloadConcurrencyOutput) { Write-Host $line }
    if ($preloadConcurrencyOutput -contains 'TEST_PASS:PRELOAD_CONCURRENT_IDEMPOTENT') {
        $clientPassed += 'PRELOAD_CONCURRENT_IDEMPOTENT'
    }
    else {
        $resultFailures += 'PRELOAD_CONCURRENT_IDEMPOTENT not reported by test_usp_precargar_sesiones_concurrency.ps1'
    }
}
catch {
    $resultFailures += "PRELOAD_CONCURRENT_IDEMPOTENT $($_.Exception.Message)"
}

# CULM-001 B.1: concurrencia de cargas de festivos, tuplas de usp_generar_sesiones_grupo_v2 (no anidable en
# INSERT ... EXEC) y migracion 15 up -> down -> up revertida (test/test_culm001_b1.ps1).
$culm001B1Ids = @('CULM001_B1_FES_05_CARGA_CONCURRENTE', 'CULM001_B1_FES_07_TUPLA_CONTEOS', 'CULM001_B1_FES_08A_SIN_TRANSACCION_SYS001',
    'CULM001_B1_FES_08B2_SIN_TUPLA', 'CULM001_B1_FES_08B_PARIDAD_TUPLA', 'CULM001_B1_MIG_01_UP_DOWN_UP')
try {
    $culm001B1Output = @(& (Join-Path $PSScriptRoot 'test/test_culm001_b1.ps1') -ContainerName $ContainerName -Password $Password 2>&1 | ForEach-Object { "$_" })
    foreach ($line in $culm001B1Output) { Write-Host $line }
    foreach ($id in $culm001B1Ids) {
        if ($culm001B1Output -contains "TEST_PASS:$id") { $clientPassed += $id }
        else { $resultFailures += "$id not reported by test_culm001_b1.ps1" }
    }
}
catch {
    $resultFailures += "CULM001_B1_RUNNER $($_.Exception.Message)"
}
. (Join-Path $PSScriptRoot 'scripts/secret-hygiene.ps1')
$secretScanList = @(Get-SecretScanFiles -Root $PSScriptRoot)
$secretFindings = @(Invoke-SecretHygieneScan -Root $PSScriptRoot)
if ($secretFindings.Count -eq 0) {
    $clientPassed += 'NO_HARDCODED_DB_PASSWORD'
    Write-Host 'TEST_PASS:NO_HARDCODED_DB_PASSWORD'
}
else {
    $resultFailures += "NO_HARDCODED_DB_PASSWORD hits=$(($secretFindings | ForEach-Object { "$($_.File):$($_.Line):$($_.Type)" }) -join ',')"
}
$mustScan = @('deploy_schema.ps1', 'test_summary.ps1', '.env.template', '.env.example')
$missingScan = @($mustScan | Where-Object { $_ -notin $secretScanList }) + @(if (-not ($secretScanList | Where-Object { $_ -like '.github/workflows/*' })) { '.github/workflows/**' })
if ($missingScan.Count -eq 0) {
    $clientPassed += 'SECRET_GATE_COVERS_ENV_TEMPLATES'
    Write-Host 'TEST_PASS:SECRET_GATE_COVERS_ENV_TEMPLATES'
}
else { $resultFailures += "SECRET_GATE_COVERS_ENV_TEMPLATES not scanned: $($missingScan -join ',')" }
$selfCheck = Test-SecretGateSelfCheck
if ($selfCheck.DetectsUnsafeEnvTemplate -and $selfCheck.DetectsQuotedScriptLiteral) {
    $clientPassed += 'SECRET_GATE_DETECTS_UNSAFE_TEMPLATE'
    Write-Host 'TEST_PASS:SECRET_GATE_DETECTS_UNSAFE_TEMPLATE'
}
else { $resultFailures += 'SECRET_GATE_DETECTS_UNSAFE_TEMPLATE gate did not detect a synthetic unsafe fixture' }
if ($selfCheck.AcceptsPlaceholder) {
    $clientPassed += 'SECRET_GATE_ACCEPTS_PLACEHOLDER'
    Write-Host 'TEST_PASS:SECRET_GATE_ACCEPTS_PLACEHOLDER'
}
else { $resultFailures += 'SECRET_GATE_ACCEPTS_PLACEHOLDER gate rejected a safe placeholder fixture' }

# Golden Path freeze manifest (contract + Golden Path object sources + addendum).
$manifestOutput = @(& (Join-Path $PSScriptRoot 'scripts/freeze-manifest.ps1') -Mode Verify 2>&1 | ForEach-Object { "$_" })
if ($LASTEXITCODE -eq 0) {
    $clientPassed += 'GOLDEN_PATH_FREEZE_MANIFEST_VERIFIED'
    Write-Host 'TEST_PASS:GOLDEN_PATH_FREEZE_MANIFEST_VERIFIED'
}
else { $resultFailures += "GOLDEN_PATH_FREEZE_MANIFEST_VERIFIED $($manifestOutput -join ',')" }

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
    'HU116_FACULTY_CREATE_EXECUTOR_REQUIRED', 'HU116_FACULTY_CREATE_EXECUTOR_RBAC', 'HU116_FACULTY_CREATE_DEAN_REQUIRED', 'HU116_FACULTY_CREATE_SUCCESS',
    'SESSION_IDDOCENTE_REMOVED', 'PUBLIC_CANONICAL_RESULTSET',
    'CATALOG_PARAMETER_CACHE_CONTRACT', 'CATALOG_MESSAGE_CACHE_CONTRACT',
    'TECHNICAL_CODE_CHANNEL', 'TECHNICAL_CODE_CHANNEL_FALLBACK',
    'SEC_001_PREFIX', 'SEC_002_PREFIX', 'ATT_PREFIX', 'SES_PREFIX', 'RC_001_PREFIX', 'GEN_002_PREFIX', 'EST_004_PREFIX',
    'NO_HARDCODED_DB_PASSWORD', 'AULA_ACTIVE_SQL_REFERENCES_ZERO', 'NORMATIVE_MODEL_GHOST_FIELDS_ZERO',
    'PUBLIC_SP_INVENTORY', 'PUBLIC_VIEW_INVENTORY',
    'USER_SYNC_SUCCESS', 'USER_SYNC_INVALID', 'DEAN_SUCCESS',
    'SESSION_CLOSE_NOT_SUPPORTED',
    'REVIEW_FILE_INVALID', 'REVIEW_FILE_SUCCESS', 'REVIEW_RESOLVE_NON_OWNER', 'REVIEW_RESOLVE_SUCCESS',
    # SES-04 (test/test_ses04_reclamo_justificada.sql): reclamo aprobado => EX con asistio = 0; rechazo conserva la asistencia
    'SES04_INVALID_ACTION', 'SES04_NOT_FOUND', 'SES04_NON_OWNER', 'SES04_APPROVE_SJC_TO_EX', 'SES04_APPROVE_AUDITED',
    'SES04_APPROVE_IDEMPOTENT', 'SES04_CONTRADICTORY_REJECTED', 'SES04_REJECT_KEEPS_ATTENDANCE', 'SES04_NO_DETAIL',
    'SES04_PRESENT_NOT_JUSTIFIABLE', 'SES04_AFTER_SESSION_CLOSE',
    'SUBJECT_CREATE', 'SUBJECT_UPDATE', 'SUBJECT_TOGGLE',
    'SUBJECT_UPSERT_CREATE', 'SUBJECT_UPSERT_UPDATE', 'CATALOG_INSERT', 'CATALOG_GET',
    'PROGRAM_UPSERT_CREATE', 'PROGRAM_UPSERT_UPDATE',
    'PLAN_UPSERT_CREATE', 'PLAN_UPSERT_UPDATE',
    'GROUP_UPSERT_CREATE', 'GROUP_UPSERT_UPDATE', 'STUDENT_PROGRAM_REGISTER',
    'MASS_CLOSE_SUCCESS',
    'HU159_IDENTITY_CORRECTION_SUCCESS', 'HU159_IDENTITY_CORRECTION_REASON_REQUIRED', 'HU159_IDENTITY_CORRECTION_SCOPE',
    'HU159_IDENTITY_CORRECTION_DOCUMENT_UNIQUE', 'HU159_IDENTITY_CORRECTION_RBAC', 'HU159_DEAN_IDENTITY_CORRECTION',
    'HU121_COORDINATOR_DOCUMENT_CORRECTION', 'HU092_TEACHER_DOCUMENT_CORRECTION', 'IDENTITY_DOCUMENT_CORRECTION_PARAMETER_OFF',
    'HU136_ADMIN_TEACHERS_INSTITUTION',
    'STUDENT_SUCCESS', 'STUDENT_DUPLICATE', 'STUDENT_GROUP_NOT_FOUND', 'STUDENT_GROUP_DISABLED', 'STUDENT_CAPACITY_EXCEEDED',
    'OWNERSHIP_STUDENT', 'OWNERSHIP_DEAN', 'OWNERSHIP_COORDINATOR',
    'GROUP_CREATE', 'GROUP_UPDATE', 'GROUP_CAPACITY_REJECT',
    'TEACHER_SCHEDULE_CREATE_ALLOWED', 'TEACHER_SCHEDULE_CONFLICT_REJECTED', 'TEACHER_SCHEDULE_ADJACENT_ALLOWED',
    'TEACHER_SCHEDULE_OTHER_DAY_ALLOWED', 'TEACHER_SCHEDULE_OTHER_PERIOD_ALLOWED', 'TEACHER_SCHEDULE_SAME_TITULAR_ALLOWED',
    'GROUP_SCHEDULE_SAVE_SUCCESS', 'GROUP_SCHEDULE_REPLACE', 'GROUP_SCHEDULE_OVERLAP_REJECTED', 'GROUP_SCHEDULE_ADJACENT_ALLOWED',
    'GROUP_SCHEDULE_INVALID', 'GROUP_SCHEDULE_SCOPE', 'GROUP_SCHEDULE_TEACHER_CONFLICT_SAVEPOINT', 'GROUP_SCHEDULE_TEACHER_CONFLICT_OWN_TRANSACTION', 'TEACHER_CREATES_GROUP', 'TEACHER_OFFER_LINKED', 'TEACHER_OFFER_NO_LINK', 'TEACHER_OFFER_REJECTS_OTHER_PROFILES',
    'PRELOAD_CREATES', 'PRELOAD_IDEMPOTENT', 'PRELOAD_PRESERVES_ATTENDANCE', 'PRELOAD_PRESERVES_CLASSIFICATION', 'PRELOAD_PRESERVES_HISTORY',
    'PRELOAD_REGENERATE', 'PRELOAD_CROSS_PROGRAM_DENIED', 'PRELOAD_NO_PRIVILEGE_DENIED', 'PRELOAD_SCOPE', 'PRELOAD_REQUIRES_SCHEDULE', 'PRELOAD_NO_PAST',
    'PRELOAD_VARIABLE_8WEEK_SINGLE', 'PRELOAD_VARIABLE_12WEEK_TWO', 'PRELOAD_VARIABLE_16WEEK_SINGLE', 'PRELOAD_VARIABLE_18WEEK_TWO',
    'PRELOAD_RUNTIME_LEAST_PRIVILEGE', 'PRELOAD_CONCURRENT_IDEMPOTENT',
    'SESSION_CREATE', 'SESSION_UPDATE', 'SESSION_NON_OWNER', 'SESSION_REQUIRED_START',
    'SESSION_REQUIRED_END', 'SESSION_END_AFTER_START', 'SESSION_EXECUTOR_REQUIRED', 'SESSION_NOT_FOUND_CODE',
    'SESSION_COMMON_VALIDATION_HAPPY_PATH', 'SESSION_COMMON_VALIDATION_RESERVED_PROVENANCE',
    'SESSION_COMMON_VALIDATION_EXECUTOR_REQUIRED', 'SESSION_COMMON_VALIDATION_START_REQUIRED',
    'SESSION_COMMON_VALIDATION_DATE_ORDER',
    'SESSION_ERROR_PRIORITY_CREATE_GROUP_BEFORE_DATES', 'SESSION_ERROR_PRIORITY_UPDATE_SESSION_BEFORE_DATES',
    'SESSION_GENERATION_SUCCESS', 'SESSION_GENERATION_IDEMPOTENT', 'SESSION_GENERATION_INVALID', 'UTC_SESSION_GENERATION',
    'SESSION_SEQUENCE_USES_MAX_NOT_COUNT', 'SESSION_CODE_OVER_99', 'SESSION_CREATE_NO_DUPLICATE_NUMBER_CODE',
    'CAPACITY_GROUP_VALIDATOR_ALLOWS_FULL_GROUP', 'CAPACITY_VALIDATOR_REJECTS_FULL_GROUP', 'SESSION_CREATE_ALLOWED_ON_FULL_GROUP',
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
    # SES-01 (test/test_ses01_ventana_asistencia.sql): ventana [inicio, fin) con reloj del motor y procedencia confirmada
    'SES01_WINDOW_LOCK_HELD', 'SES01_BULK_EXACT_START', 'SES01_BULK_DURING', 'SES01_BULK_JUST_BEFORE_END',
    'SES01_BULK_BEFORE_START', 'SES01_BULK_EXACT_END', 'SES01_BULK_TWO_HOURS_AFTER', 'SES01_BULK_INDETERMINATE',
    'SES01_BULK_CLOSED_HISTORY_PRESERVED', 'SES01_AUTO_CLOSED', 'SES01_AUTO_BEFORE_START', 'SES01_AUTO_INDETERMINATE',
    'COORDINATOR_SUCCESS', 'COORDINATOR_PROGRAM_MISSING', 'COORDINATOR_FACULTY_MISSING', 'COORDINATOR_SCOPE_MISMATCH',
    'SUITE_TRANCOUNT_ZERO',
    'USP_CONSULTAR_GRUPOS_PAGINADO_SUCCESS', 'USP_CONSULTAR_GRUPOS_PAGINADO_FILTER_AND_PAGINATION',
    'USP_CONSULTAR_GRUPOS_PAGINADO_INVALID_USER', 'USP_CONSULTAR_GRUPOS_PAGINADO_CONTEXT_CLEANUP',
    'USP_CONSULTAR_GRUPOS_PAGINADO_CONTEXT_PREVIOUS_VALUE_RESTORED', 'USP_CONSULTAR_GRUPOS_PAGINADO_CONTEXT_RESTORED_ON_EXCEPTION',
    'USP_CONSULTAR_GRUPOS_PAGINADO_NO_CONTEXT_LEAK',
    'RBAC_AUTH_VIEWS_FAIL_CLOSED_DEFINITION', 'RBAC_NULL_CONTEXT_NO_ROWS', 'RBAC_UNKNOWN_CONTEXT_NO_ROWS',
    'RBAC_ADMIN_INSTITUTION_ISOLATION', 'RBAC_INACTIVE_USER_NO_BROADER_SCOPE', 'RBAC_DECANO_FACULTY_ISOLATION',
    'RBAC_COORDINADOR_PROGRAM_ISOLATION', 'RBAC_DOCENTE_GROUP_ISOLATION', 'RBAC_ESTUDIANTE_ENROLLED_GROUP_ISOLATION',
    'RBAC_RESET_CONTEXT',
    'GOLDEN_PATH_VIEW_SHAPES_FROZEN', 'GOLDEN_PATH_SP_SIGNATURES_FROZEN', 'GOLDEN_PATH_MUTATION_RESULTSET_FROZEN',
    'GOLDEN_PATH_FREEZE_MANIFEST_VERIFIED',
    'UTC_D06_READONLY_CONTRACT', 'UTC_D06_SCHEMA_COLUMN', 'UTC_D06_SEED_UTC', 'UTC_D06_V2_VIEW_SHAPE',
    'UTC_D06_V2_SIGNATURES', 'UTC_D06_V2_CREATE_MARK', 'UTC_D06_V1_CREATE_NULL', 'UTC_D06_V2_UPDATE_MARK',
    'UTC_D06_V2_SES_004_NO_WRITE', 'UTC_D06_V2_NON_OWNER', 'UTC_D06_V1_UPDATE_INVALIDATES',
    'UTC_D06_INTERNAL_REJECTS_RESERVED_MARK', 'UTC_D06_CHECK_REJECTS_UNKNOWN', 'UTC_D06_V2_VIEW_PARITY',
    'UTC_D06_RUNTIME_PERMISSIONS', 'UTC_D06_CLASSIFICATION_REJECTS', 'UTC_D06_CLASSIFICATION_BY_ID',
    'UTC_D06_DETALLE_SNAPSHOT', 'UTC_D06_GENERATOR_DST_GAP', 'UTC_D06_GENERATOR_MARK',
    'UTC_D06_DIRECT_UPDATE_REJECTED', 'UTC_D06_CONCURRENT_V2_CREATE', 'UV_ESTUDIANTE_PROGRAMA_NO_DUPLICATES',
    'SECRET_GATE_COVERS_ENV_TEMPLATES', 'SECRET_GATE_DETECTS_UNSAFE_TEMPLATE', 'SECRET_GATE_ACCEPTS_PLACEHOLDER',
    # CC-003G-01: proveedores publicos usp_sincronizar_usuario y usp_registrar_o_actualizar_plan_estudio
    'USER_SYNC_PUBLIC_METADATA', 'USER_SYNC_PUBLIC_SUCCESS', 'USER_SYNC_PUBLIC_NO_SECRET_LEAK', 'USER_SYNC_PUBLIC_IDEMPOTENT',
    'USER_SYNC_PUBLIC_REJECTIONS_PRE_TRANSACTION', 'USER_SYNC_PUBLIC_DUPLICATE_DOCUMENT', 'USER_SYNC_PUBLIC_DUPLICATE_EMAIL',
    'USER_SYNC_PUBLIC_CONFLICTING_PROFILE', 'USER_SYNC_PUBLIC_INVALID_EMAIL', 'USER_SYNC_PUBLIC_EMPTY_PASSWORD',
    'USER_SYNC_PUBLIC_UNKNOWN_ID_TYPE', 'USER_SYNC_PUBLIC_ROLLBACK_SAVEPOINT', 'USER_SYNC_PUBLIC_COMMIT_OWN_TRANSACTION',
    'USER_SYNC_PUBLIC_ROLLBACK_OWN_TRANSACTION', 'USER_SYNC_PUBLIC_INACTIVE_REPLAY',
    'PLAN_PUBLIC_METADATA', 'PLAN_PUBLIC_CREATE', 'PLAN_PUBLIC_VIEW_CONSISTENT', 'PLAN_PUBLIC_IDEMPOTENT', 'PLAN_PUBLIC_UPDATE',
    'PLAN_PUBLIC_TWO_ACTORS', 'PLAN_PUBLIC_EXECUTOR_REQUIRED', 'PLAN_PUBLIC_RBAC', 'PLAN_PUBLIC_FOREIGN_PROGRAM_SCOPE',
    'PLAN_PUBLIC_INVALID_INPUT', 'PLAN_PUBLIC_DUPLICATE_BUSINESS_KEY', 'PLAN_PUBLIC_UPDATE_TO_TAKEN_INP', 'PLAN_PUBLIC_FOREIGN_PLAN',
    'PLAN_PUBLIC_ROLLBACK_SAVEPOINT', 'PLAN_PUBLIC_COMMIT_OWN_TRANSACTION', 'PLAN_PUBLIC_ROLLBACK_OWN_TRANSACTION',
    'CC003G01_CONCURRENT_USER_IDENTICAL', 'CC003G01_CONCURRENT_USER_CONFLICT_EMAIL',
    'CC003G01_CONCURRENT_PLAN_DUPLICATE_KEY', 'CC003G01_CONCURRENT_PLAN_IDEMPOTENT',
    'CC003G01_RUNTIME_EXECUTE_GRANTS', 'CC003G01_RUNTIME_INTERNAL_EXEC_DENIED', 'CC003G01_RUNTIME_DIRECT_DML_DENIED',
    'CC003G01_RUNTIME_BASE_TABLE_READ_DENIED', 'CC003G01_RUNTIME_PROVIDERS_FUNCTIONAL',
    # LB-004D (ONE_TABLE): soporte de solicitudes de revision (test/test_lb004d_support_binding.sql)
    'LB004D_SCHEMA_SHAPE', 'LB004D_UTC_V2_DATETIME2_7', 'LB004D_W1_VALID', 'LB004D_W1_IDEMPOTENT', 'LB004D_W1_INVALID', 'LB004D_W2_WITHOUT_SUPPORT', 'LB004D_W2_ATTACH', 'LB004D_W2_IDEMPOTENT', 'LB004D_W2_FOREIGN_AND_USED_FILE', 'LB004D_W2_STUDENT_NOT_EXECUTOR', 'LB004D_W2_INVALID_CONTEXT', 'LB004D_R1_AUTHORIZATION_MATRIX', 'LB004D_R2_TEACHER_SCOPE', 'LB004D_INTEGRITY', 'LB004D_W2_ATOMIC_ROLLBACK', 'LB004D_RUNTIME_LEAST_PRIVILEGE', 'LB004D_V1_UNCHANGED',
    # CULM-001 B.1 (test/test_culm001_b1_*.sql, test/test_culm001_b1.ps1, test/test_public_objects.sql)
    'CULM001_B1_VEN_00_FIRMA', 'CULM001_B1_VEN_01_SIN_TOLERANCIA', 'CULM001_B1_VEN_02_CON_TOLERANCIA', 'CULM001_B1_VEN_03_NULL_NEGATIVO_ES_CERO',
    'CULM001_B1_VEN_04_CANCELADA_SES010', 'CULM001_B1_VEN_04_LOTE_CONGELADO', 'CULM001_B1_VEN_05_PROCEDENCIA_ANTES_QUE_TOLERANCIA',
    'CULM001_B1_VEN_LOCK_HELD', 'CULM001_B1_VEN_TRANCOUNT_ZERO',
    'CULM001_B1_CAN_00_OBJETOS_Y_SEMILLAS', 'CULM001_B1_CAN_VALIDACIONES_PREVIAS', 'CULM001_B1_CAN_01_TITULAR_CANCELA', 'CULM001_B1_CAN_02_SOLO_TITULAR',
    'CULM001_B1_CAN_03_MOTIVO_SES013', 'CULM001_B1_CAN_04_CON_ASISTENCIA_SES012', 'CULM001_B1_CAN_05_DOBLE_SES011', 'CULM001_B1_CAN_06_FUERA_DE_CUMPLIMIENTO',
    'CULM001_B1_CAN_07_DESTINATARIOS', 'CULM001_B1_CAN_07_AMBITO_SEC002', 'CULM001_B1_CAN_08_PASADA_Y_TERMINADA', 'CULM001_B1_CAN_UV_SESION_ESTADO_VENTANA',
    'CULM001_B1_INV_SESION_CANCELACION_COHERENTE', 'CULM001_B1_CAN_TRANCOUNT_ZERO',
    'CULM001_B1_FES_00_OBJETOS_Y_SEMILLAS', 'CULM001_B1_FES_01_CARGA_2026', 'CULM001_B1_FES_02_CARGA_IDEMPOTENTE', 'CULM001_B1_FES_CARGA_AUTOMATICA',
    'CULM001_B1_FES_03_RECARGA_DESACTIVA_SIN_REVERTIR', 'CULM001_B1_FES_04_ENTRADAS_INVALIDAS', 'CULM001_B1_FES_05_CARGA_CONCURRENTE',
    'CULM001_B1_FES_06_38_FECHAS_2026_2027', 'CULM001_B1_FES_07_GENERACION_IDEMPOTENTE', 'CULM001_B1_FES_07_TUPLA_CONTEOS',
    'CULM001_B1_FES_08A_SIN_TRANSACCION_SYS001', 'CULM001_B1_FES_08B_PARIDAD_TUPLA', 'CULM001_B1_FES_08B2_TRANSACCION_EXTERNA_THROW',
    'CULM001_B1_FES_08B2_SIN_TUPLA', 'CULM001_B1_FES_08C_RUTA_FELIZ_TRANSACCION_EXTERNA', 'CULM001_B1_FES_08C_LLAMADOR_REVIERTE',
    'CULM001_B1_FES_09_PRECARGA_CON_FESTIVOS', 'CULM001_B1_FES_10_APLICAR_GRUPO', 'CULM001_B1_FES_11_APLICAR_PERIODO',
    'CULM001_B1_FES_12_SESIONES_REPORTADAS', 'CULM001_B1_FES_13_FECHA_LOCAL_VS_UTC', 'CULM001_B1_FES_INV_COHERENCIA', 'CULM001_B1_FES_CONSULTA_RBAC_PAGINACION',
    'CULM001_B1_MIG_01_UP_DOWN_UP', 'CULM001_B1_SEG_01_PERMISOS'
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
