param (
    [string]$ContainerName = 'sqlserver',
    [string]$Password = $env:MSSQL_SA_PASSWORD
)

$ErrorActionPreference = 'Stop'

if (-not $Password) { throw 'SQL password is required for the SES-02 concurrency test.' }

$tag = [guid]::NewGuid().ToString('N')
$remotePrefix = "/tmp/preload_concurrency_$tag"
$setupPath = Join-Path ([System.IO.Path]::GetTempPath()) "preload_concurrency_setup_$tag.sql"
$workerPath = Join-Path ([System.IO.Path]::GetTempPath()) "preload_concurrency_worker_$tag.sql"
$validationPath = Join-Path ([System.IO.Path]::GetTempPath()) "preload_concurrency_validation_$tag.sql"
$cleanupPath = Join-Path ([System.IO.Path]::GetTempPath()) "preload_concurrency_cleanup_$tag.sql"
$remoteFiles = @("${remotePrefix}_setup.sql", "${remotePrefix}_worker.sql", "${remotePrefix}_validation.sql", "${remotePrefix}_cleanup.sql")
$groupId = $null
$periodId = $null
$actorId = $null
$failure = $null
$job1 = $null
$job2 = $null

function Invoke-ContainerSqlFile {
    param ([string]$LocalPath, [string]$RemotePath)

    $copyOutput = @(& docker cp $LocalPath "${ContainerName}:$RemotePath" 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "could not copy SQL fixture: $($copyOutput -join '; ')" }
    $null = & docker exec -u 0 $ContainerName chmod a+r $RemotePath 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'could not set SQL fixture read permissions.' }
    $output = @(& docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -d gestionasistenciadb -U sa -P $Password -C -b -h -1 -W -s '|' -t 60 -i $RemotePath 2>&1)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) { throw "sqlcmd failed with exit code ${exitCode}: $($output -join '; ')" }
    return $output
}

function Get-OutputRecord {
    param ([string[]]$Lines, [string]$Pattern, [string]$Description)
    $records = @($Lines | ForEach-Object { "$($_)".Trim() } | Where-Object { $_ -match $Pattern })
    if ($records.Count -ne 1) { throw "expected one $Description record; found $($records.Count)." }
    return $records[0]
}

try {
    $setupSql = @'
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @idAsignatura UNIQUEIDENTIFIER, @idPrograma UNIQUEIDENTIFIER, @idInstitucion UNIQUEIDENTIFIER;
DECLARE @idCoordinador UNIQUEIDENTIFIER, @idDocente UNIQUEIDENTIFIER, @idDia UNIQUEIDENTIFIER;
DECLARE @idPeriodo UNIQUEIDENTIFIER = NEWID(), @idGrupo UNIQUEIDENTIFIER = NEWID();
DECLARE @codigoPeriodo INT = 1000000 + ABS(CHECKSUM(NEWID()) % 8000000);
DECLARE @codigoGrupo INT = 1000000 + ABS(CHECKSUM(NEWID()) % 8000000);

SELECT TOP (1)
    @idAsignatura = a.id,
    @idPrograma = pe.idPrograma,
    @idInstitucion = pr.idInstitucion,
    @idCoordinador = ci.idUsuario,
    @idDocente = dp.idDocente
FROM dbo.uv_asignatura a
INNER JOIN dbo.uv_semestre_plan_estudio spe ON a.idSemestrePlanEstudio = spe.id
INNER JOIN dbo.uv_plan_estudio pe ON spe.idPlanEstudio = pe.id
INNER JOIN dbo.uv_programa pr ON pe.idPrograma = pr.id
INNER JOIN dbo.uv_coordinador_identidad ci ON ci.id = pr.idCoordinador
INNER JOIN dbo.uv_docente_programa dp ON dp.idPrograma = pr.id AND dp.estaActivoDocentePrograma = 1
WHERE pr.estaActivoPrograma = 1
  AND ci.estaActivoUsuario = 1
  AND ci.estaActivoRolCoordinador = 1
  AND a.estaActivaAsignatura = 1
ORDER BY a.id, dp.idDocente;
SELECT TOP (1) @idDia = id FROM dbo.uv_dia WHERE codigo = 'LU';
IF @idAsignatura IS NULL OR @idPrograma IS NULL OR @idInstitucion IS NULL OR @idCoordinador IS NULL OR @idDocente IS NULL OR @idDia IS NULL
    THROW 53480, 'SES02_CONCURRENCY_FIXTURE_MISSING: missing active program, coordinator, teacher, subject or day.', 1;

BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@idPeriodo, @idInstitucion, N'QA SES02 concurrency period', @codigoPeriodo, '2098-01-06', '2098-03-02', 2098);
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes,
        cantidadEstudiantesFinalizaron, cantidadEstudiantesCancelaronVoluntadPropia,
        cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@idGrupo, @idAsignatura, @idPeriodo, @codigoGrupo, N'QA SES02 concurrency group', 30, 0, 0, 0, @idDocente);
    INSERT INTO dbo.Horario (id, grupo, dia, horaInicio, horaFin)
    VALUES (NEWID(), @idGrupo, @idDia, '08:00', '09:00');
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

SELECT CONCAT(CONVERT(VARCHAR(36), @idGrupo), '|', CONVERT(VARCHAR(36), @idPeriodo), '|', CONVERT(VARCHAR(36), @idCoordinador));
'@
    Set-Content -Path $setupPath -Value $setupSql -Encoding utf8
    $setupOutput = @(Invoke-ContainerSqlFile -LocalPath $setupPath -RemotePath "${remotePrefix}_setup.sql")
    $fixture = Get-OutputRecord -Lines $setupOutput -Pattern '^([0-9a-fA-F-]{36})\|([0-9a-fA-F-]{36})\|([0-9a-fA-F-]{36})$' -Description 'fixture'
    $fixtureParts = $fixture.Split('|')
    $groupId = $fixtureParts[0]
    $periodId = $fixtureParts[1]
    $actorId = $fixtureParts[2]

    $workerSql = @"
SET NOCOUNT ON;
WAITFOR DELAY '00:00:02';
DECLARE @result TABLE (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
DECLARE @corr UNIQUEIDENTIFIER = NEWID();
INSERT INTO @result EXEC dbo.usp_precargar_sesiones_grupo
    @idGrupo = '$groupId', @idCorrelacion = @corr, @idUsuarioEjecutor = '$actorId';
IF (SELECT COUNT(*) FROM @result) <> 1 OR EXISTS (SELECT 1 FROM @result WHERE estadoResultado <> 1)
    THROW 53481, 'PRELOAD_CONCURRENT_IDEMPOTENT FAILED: concurrent preload returned a failure.', 1;
"@
    Set-Content -Path $workerPath -Value $workerSql -Encoding utf8
    $workerRemotePath = "${remotePrefix}_worker.sql"
    $copyOutput = @(& docker cp $workerPath "${ContainerName}:$workerRemotePath" 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "could not copy SQL worker fixture: $($copyOutput -join '; ')" }
    $null = & docker exec -u 0 $ContainerName chmod a+r $workerRemotePath 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'could not set SQL worker fixture read permissions.' }
    $validationSql = @"
SET NOCOUNT ON;
DECLARE @zonaHoraria SYSNAME = (SELECT TOP (1) valor FROM dbo.uv_parametro WHERE grupo = 'TIEMPO' AND clave = 'ZONA_HORARIA_SQLSERVER' AND estaActivo = 1);
IF @zonaHoraria IS NULL THROW 53482, 'PRELOAD_CONCURRENT_IDEMPOTENT FAILED: institutional timezone missing.', 1;
IF EXISTS (
    SELECT fechaHoraInicio, fechaHoraFin FROM dbo.uv_sesion_v2 WHERE idGrupo = '$groupId'
    GROUP BY fechaHoraInicio, fechaHoraFin HAVING COUNT(*) > 1
) THROW 53483, 'PRELOAD_CONCURRENT_IDEMPOTENT FAILED: duplicate time slots exist.', 1;
IF EXISTS (
    SELECT 1 FROM dbo.uv_sesion_v2
    WHERE idGrupo = '$groupId'
      AND (procedenciaTemporal <> N'UTC_GENERADOR'
           OR CAST(fechaHoraInicio AT TIME ZONE 'UTC' AT TIME ZONE @zonaHoraria AS DATE) NOT BETWEEN '2098-01-06' AND '2098-03-02'
           OR DATEDIFF(DAY, '19000101', CAST(fechaHoraInicio AT TIME ZONE 'UTC' AT TIME ZONE @zonaHoraria AS DATE)) % 7 <> 0)
) THROW 53484, 'PRELOAD_CONCURRENT_IDEMPOTENT FAILED: generated date or provenance is invalid.', 1;
SELECT CONCAT(COUNT(*), '|', COUNT(DISTINCT numero), '|', COUNT(DISTINCT codigo), '|', MIN(numero), '|', MAX(numero),
    '|', SUM(CASE WHEN procedenciaTemporal = N'UTC_GENERADOR' THEN 1 ELSE 0 END))
FROM dbo.uv_sesion_v2 WHERE idGrupo = '$groupId';
"@
    Set-Content -Path $validationPath -Value $validationSql -Encoding utf8

    $jobScript = {
        param ($container, $password, $path)
        $workerOutput = @(& docker exec $container /opt/mssql-tools18/bin/sqlcmd -S localhost -d gestionasistenciadb -U sa -P $password -C -b -h -1 -W -t 60 -i $path 2>&1)
        $workerExitCode = $LASTEXITCODE
        $workerOutput
        if ($workerExitCode -ne 0) { throw "concurrent sqlcmd failed with exit code ${workerExitCode}: $($workerOutput -join '; ')" }
    }
    $job1 = Start-Job -ScriptBlock $jobScript -ArgumentList $ContainerName, $Password, $workerRemotePath
    $job2 = Start-Job -ScriptBlock $jobScript -ArgumentList $ContainerName, $Password, $workerRemotePath
    $jobOutput = @(Receive-Job -Job $job1, $job2 -Wait -AutoRemoveJob 2>&1)
    if ($jobOutput | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }) {
        throw "concurrent workers failed: $($jobOutput -join '; ')"
    }

    $validationRemotePath = "${remotePrefix}_validation.sql"
    $validationOutput = @(Invoke-ContainerSqlFile -LocalPath $validationPath -RemotePath $validationRemotePath)
    $firstCounts = Get-OutputRecord -Lines $validationOutput -Pattern '^8\|8\|8\|1\|8\|8$' -Description 'concurrent validation'

    # A third call verifies that a settled concurrent result remains idempotent.
    $retryOutput = @(& docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -d gestionasistenciadb -U sa -P $Password -C -b -h -1 -W -t 60 -i $workerRemotePath 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "sequential retry failed: $($retryOutput -join '; ')" }
    $retryValidation = @(Invoke-ContainerSqlFile -LocalPath $validationPath -RemotePath $validationRemotePath)
    $null = Get-OutputRecord -Lines $retryValidation -Pattern '^8\|8\|8\|1\|8\|8$' -Description 'post-retry validation'
}
catch {
    $failure = $_.Exception.Message
}
finally {
    if ($job1 -and $job1.State -eq 'Running') { Stop-Job -Job $job1 -ErrorAction SilentlyContinue }
    if ($job2 -and $job2.State -eq 'Running') { Stop-Job -Job $job2 -ErrorAction SilentlyContinue }
    if ($groupId -and $periodId) {
        $cleanupSql = @"
SET NOCOUNT ON;
-- CULM-001 B.2 ([SUPUESTO-B-20]): tokens, tomas y cancelaciones (festivos) de las sesiones del grupo antes de borrarlas
DELETE tk FROM dbo.TokenAsistenciaToma tk INNER JOIN dbo.TomaAsistencia t ON t.id = tk.toma INNER JOIN dbo.Sesion s ON s.id = t.sesion WHERE s.grupo = '$groupId';
DELETE t FROM dbo.TomaAsistencia t INNER JOIN dbo.Sesion s ON s.id = t.sesion WHERE s.grupo = '$groupId';
DELETE sc FROM dbo.SesionCancelacion sc INNER JOIN dbo.Sesion s ON s.id = sc.sesion WHERE s.grupo = '$groupId';
DELETE FROM dbo.Sesion WHERE grupo = '$groupId';
DELETE FROM dbo.Horario WHERE grupo = '$groupId';
DELETE FROM dbo.Grupo WHERE id = '$groupId';
DELETE FROM dbo.PeriodoAcademico WHERE id = '$periodId';
IF EXISTS (SELECT 1 FROM dbo.uv_grupo WHERE id = '$groupId') OR EXISTS (SELECT 1 FROM dbo.uv_periodo_academico WHERE id = '$periodId')
    THROW 53485, 'PRELOAD_CONCURRENT_IDEMPOTENT cleanup failed.', 1;
"@
        Set-Content -Path $cleanupPath -Value $cleanupSql -Encoding utf8
        try { $null = Invoke-ContainerSqlFile -LocalPath $cleanupPath -RemotePath "${remotePrefix}_cleanup.sql" }
        catch { if (-not $failure) { $failure = "cleanup failed: $($_.Exception.Message)" } }
    }
    $remoteCleanup = @(& docker exec -u 0 $ContainerName rm -f $remoteFiles 2>&1)
    if ($LASTEXITCODE -ne 0 -and -not $failure) { $failure = "temporary SQL cleanup failed: $($remoteCleanup -join '; ')" }
    Remove-Item -LiteralPath $setupPath, $workerPath, $validationPath, $cleanupPath -Force -ErrorAction SilentlyContinue
    if ($job1) { Remove-Job -Job $job1 -Force -ErrorAction SilentlyContinue }
    if ($job2) { Remove-Job -Job $job2 -Force -ErrorAction SilentlyContinue }
}

if ($failure) { throw $failure }
Write-Output 'TEST_PASS:PRELOAD_CONCURRENT_IDEMPOTENT'
