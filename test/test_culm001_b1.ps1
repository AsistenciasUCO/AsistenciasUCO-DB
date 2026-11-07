param (
    [string]$ContainerName = 'sqlserver',
    [string]$Password = $env:MSSQL_SA_PASSWORD
)

# CULM-001 B.1 (CONTRACT §2.14, §2.16.1): casos que no caben en un archivo T-SQL de la suite porque requieren
# dos conexiones (B1-FES-05), leer la tupla de usp_generar_sesiones_grupo_v2 (usa INSERT ... EXEC, asi que no se
# puede anidar en otro INSERT ... EXEC: B1-FES-07, B1-FES-08a, B1-FES-08b, B1-FES-08b2) o ejecutar la migracion 15
# up -> down -> up dentro de una transaccion que se revierte (B1-MIG-01). Cada caso deja la BD como estaba.
# Salida: TEST_PASS:<ID> por caso aprobado y TEST FAILED: <ID> <motivo> por caso fallido.

$ErrorActionPreference = 'Stop'
if (-not $Password) { throw 'SQL password is required for test_culm001_b1.ps1.' }

$tag = [guid]::NewGuid().ToString('N').Substring(0, 12)
$remoteDir = "/tmp/culm001_b1_$tag"
$localDir = Join-Path ([System.IO.Path]::GetTempPath()) "culm001_b1_$tag"
New-Item -ItemType Directory -Force -Path $localDir | Out-Null
$null = & docker exec -u 0 $ContainerName mkdir -p $remoteDir 2>&1
$failures = @()
$guidRow = '^(?<corr>[0-9A-Fa-f]{8}-(?:[0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12})\|(?<user>[^|]*)\|(?<tech>.*)\|(?<estado>[01])'

function Invoke-ContainerSql {
    param ([string]$Name, [string]$Sql, [switch]$AbortOnError)
    $local = Join-Path $localDir "$Name.sql"
    Set-Content -Path $local -Value $Sql -Encoding utf8
    $remote = "$remoteDir/$Name.sql"
    $copy = @(& docker cp $local "${ContainerName}:$remote" 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "could not copy ${Name}: $($copy -join '; ')" }
    $null = & docker exec -u 0 $ContainerName chmod a+r $remote 2>&1
    $sqlArgs = @('exec', $ContainerName, '/opt/mssql-tools18/bin/sqlcmd', '-S', 'localhost', '-d', 'gestionasistenciadb', '-U', 'sa', '-P', $Password,
              '-C', '-I', '-h', '-1', '-W', '-s', '|', '-w', '65535', '-t', '300', '-i', $remote)
    if ($AbortOnError) { $sqlArgs += '-b' }
    $output = @(& docker @sqlArgs 2>&1 | ForEach-Object { "$_".Trim() })
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Lines = $output }
}

function Get-Rows {
    param ([string[]]$Lines, [string]$Pattern = $guidRow)
    return @($Lines | Where-Object { $_ -match $Pattern })
}

function Get-TupleRows {
    param ([string]$Text, [string]$Begin, [string]$End)
    $segment = [regex]::Match($Text, "(?s)$Begin(.*?)$End").Groups[1].Value
    return ,@($segment -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -match $guidRow })
}

function Split-Tuple {
    param ([string]$Line)
    # La tupla canonica lleva '|' dentro del mensaje tecnico (DBCODE=XXX|...): las columnas de datos se leen desde el final.
    $m = [regex]::Match($Line, '^(?<corr>[0-9A-Fa-f-]{36})\|(?<user>[^|]*)\|(?<rest>.*)$')
    if (-not $m.Success) { return $null }
    return [pscustomobject]@{ Corr = $m.Groups['corr'].Value; User = $m.Groups['user'].Value; Rest = $m.Groups['rest'].Value }
}

$fixtureSql = @'
DECLARE @institution UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion ORDER BY id);
DECLARE @assignment UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_asignatura ORDER BY id);
DECLARE @teacher UNIQUEIDENTIFIER, @teacherUser UNIQUEIDENTIFIER, @otherUser UNIQUEIDENTIFIER;
SELECT TOP 1 @teacher = di.id, @teacherUser = di.idUsuario FROM dbo.uv_docente_identidad di WHERE di.estaActivoUsuario = 1 ORDER BY di.id;
SELECT TOP 1 @otherUser = di.idUsuario FROM dbo.uv_docente_identidad di WHERE di.estaActivoUsuario = 1 AND di.id <> @teacher ORDER BY di.id;
DECLARE @firstDay DATE = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER') AS DATE);
IF @institution IS NULL OR @assignment IS NULL OR @teacher IS NULL OR @teacherUser IS NULL OR @otherUser IS NULL
    THROW 57500, 'CULM001_B1_FIXTURE_MISSING', 1;
'@

# ---------------------------------------------------------------------------------------------------------------
# B1-FES-05: dos cargas concurrentes del mismo anio (2099) => sin duplicados ni error de clave; la segunda espera
# ---------------------------------------------------------------------------------------------------------------
$cleanup2099 = "SET NOCOUNT ON; SET QUOTED_IDENTIFIER ON; DELETE FROM dbo.CargaDiaFestivo WHERE anio = 2099; DELETE FROM dbo.DiaFestivo WHERE anio = 2099;"
try {
    $cr = Invoke-ContainerSql -Name 'fes05_cleanup_before' -Sql $cleanup2099 -AbortOnError; if ($cr.ExitCode -ne 0) { throw "cleanup exit $($cr.ExitCode): $($cr.Lines -join '; ')" }
    $workerSql = @'
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @admin UNIQUEIDENTIFIER = (SELECT TOP 1 a.usuario FROM dbo.Administrador a JOIN dbo.uv_usuario u ON u.id = a.usuario WHERE u.estaActivoUsuario = 1 ORDER BY a.id);
DECLARE @json NVARCHAR(MAX) = (SELECT fecha = CONVERT(CHAR(10), DATEADD(DAY, v.n * 7, CAST('2099-01-05' AS DATE)), 23), nombre = CONCAT(N'CULM1 festivo ', v.n)
                               FROM (VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11),(12),(13),(14),(15),(16),(17),(18),(19)) v(n) FOR JSON PATH);
DECLARE @corr UNIQUEIDENTIFIER = NEWID();
BEGIN TRANSACTION;
EXEC dbo.usp_cargar_dias_festivos @anio = 2099, @festivosJSON = @json, @fuente = N'CALCULO_LOCAL', @diferenciasCalculoLocal = 0,
    @idCorrelacion = @corr, @idUsuarioEjecutor = @admin;
WAITFOR DELAY '00:00:03';
COMMIT TRANSACTION;
'@
    $local = Join-Path $localDir 'fes05_worker.sql'
    Set-Content -Path $local -Value $workerSql -Encoding utf8
    $remoteWorker = "$remoteDir/fes05_worker.sql"
    $null = & docker cp $local "${ContainerName}:$remoteWorker" 2>&1
    $null = & docker exec -u 0 $ContainerName chmod a+r $remoteWorker 2>&1
    $job = {
        param($cn, $pw, $file)
        $out = @(& docker exec $cn /opt/mssql-tools18/bin/sqlcmd -S localhost -d gestionasistenciadb -U sa -P $pw -C -I -b -h -1 -W -s '|' -w 65535 -i $file 2>&1 | ForEach-Object { "$_".Trim() })
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Lines = $out }
    }
    $jobs = @((Start-Job -ScriptBlock $job -ArgumentList $ContainerName, $Password, $remoteWorker),
              (Start-Job -ScriptBlock $job -ArgumentList $ContainerName, $Password, $remoteWorker))
    $results = @(Receive-Job -Job $jobs -Wait -AutoRemoveJob)
    $rows = @()
    foreach ($r in $results) {
        if ($r.ExitCode -ne 0) { throw "worker failed: $($r.Lines -join '; ')" }
        $rows += Get-Rows -Lines $r.Lines
    }
    if ($rows.Count -ne 2) { throw "expected 2 tuples; found $($rows.Count)" }
    $inserted = @()
    foreach ($row in $rows) {
        $m = [regex]::Match($row, '\|1\|2099\|19\|(?<ins>\d+)\|(?<upd>\d+)\|0$')
        if (-not $m.Success -or $row -notmatch '\|DBCODE=FES_005\|') { throw "unexpected tuple: $row" }
        $inserted += [int]$m.Groups['ins'].Value
    }
    if (($inserted | Sort-Object) -join ',' -ne '0,19') { throw "expected one load with 19 inserted and one with 0; got $($inserted -join ',')" }
    $check = Invoke-ContainerSql -Name 'fes05_check' -Sql "SET NOCOUNT ON; SELECT CONCAT('FES05|', (SELECT COUNT(*) FROM dbo.DiaFestivo WHERE anio = 2099), '|', (SELECT COUNT(DISTINCT fecha) FROM dbo.DiaFestivo WHERE anio = 2099 AND estaActivo = 1), '|', (SELECT COUNT(*) FROM dbo.CargaDiaFestivo WHERE anio = 2099));" -AbortOnError
    $line = @($check.Lines | Where-Object { $_ -like 'FES05|*' })
    if ($line.Count -ne 1 -or $line[0] -ne 'FES05|19|19|2') { throw "unexpected final state: $($line -join ';')" }
    Write-Host 'TEST_PASS:CULM001_B1_FES_05_CARGA_CONCURRENTE'
}
catch { $failures += "CULM001_B1_FES_05_CARGA_CONCURRENTE $($_.Exception.Message)" }
finally { try { $cr = Invoke-ContainerSql -Name 'fes05_cleanup' -Sql $cleanup2099 -AbortOnError; if ($cr.ExitCode -ne 0) { throw "cleanup exit $($cr.ExitCode): $($cr.Lines -join '; ')" } } catch { $failures += 'CULM001_B1_FES_05 cleanup failed' } }

# ---------------------------------------------------------------------------------------------------------------
# B1-FES-07 (tupla): v2 en un periodo con festivos => sesionesCanceladasPorFestivo = 3; segunda ejecucion = 0
# ---------------------------------------------------------------------------------------------------------------
try {
    $sql = @"
SET NOCOUNT ON;
SET XACT_ABORT OFF;
$fixtureSql
DECLARE @json NVARCHAR(MAX) = N'[{"fecha":"2026-01-01","nombre":"Año Nuevo"},{"fecha":"2026-01-12","nombre":"Reyes Magos"},{"fecha":"2026-03-23","nombre":"San José"},{"fecha":"2026-04-02","nombre":"Jueves Santo"},{"fecha":"2026-04-03","nombre":"Viernes Santo"},{"fecha":"2026-05-01","nombre":"Día del Trabajo"},{"fecha":"2026-05-18","nombre":"Ascensión del Señor"},{"fecha":"2026-06-08","nombre":"Corpus Christi"},{"fecha":"2026-06-15","nombre":"Sagrado Corazón"},{"fecha":"2026-06-29","nombre":"San Pedro y San Pablo"},{"fecha":"2026-07-13","nombre":"Nuestra Señora del Rosario de Chiquinquirá"},{"fecha":"2026-07-20","nombre":"Independencia"},{"fecha":"2026-08-07","nombre":"Batalla de Boyacá"},{"fecha":"2026-08-17","nombre":"Asunción de la Virgen"},{"fecha":"2026-10-12","nombre":"Día de la Raza"},{"fecha":"2026-11-02","nombre":"Todos los Santos"},{"fecha":"2026-11-16","nombre":"Independencia de Cartagena"},{"fecha":"2026-12-08","nombre":"Inmaculada Concepción"},{"fecha":"2026-12-25","nombre":"Navidad"}]';
DECLARE @period UNIQUEIDENTIFIER = NEWID(), @group UNIQUEIDENTIFIER = NEWID(), @corr UNIQUEIDENTIFIER = NEWID();
CREATE TABLE #cf (a UNIQUEIDENTIFIER, b NVARCHAR(4000), c NVARCHAR(4000), d BIT, e INT, f INT, g INT, h INT, i INT);
BEGIN TRANSACTION;
INSERT INTO #cf EXEC dbo.usp_cargar_dias_festivos_automatico @anio = 2026, @festivosJSON = @json, @fuente = N'CALCULO_LOCAL', @diferenciasCalculoLocal = 0, @idCorrelacion = @corr;
IF NOT EXISTS (SELECT 1 FROM #cf WHERE d = 1) THROW 57501, 'FES07 festivos 2026 no cargados', 1;
INSERT dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
VALUES (@period, @institution, N'CULM1 Periodo FES07', 3800000 + ABS(CHECKSUM(NEWID()) % 99999), '2026-11-01', '2026-11-20', 2026);
INSERT dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
    cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
VALUES (@group, @assignment, @period, 943000 + ABS(CHECKSUM(NEWID()) % 56999), N'CULM1 Grupo FES07', 20, 0, 0, 0, @teacher);
INSERT dbo.Horario (id, grupo, dia, horaInicio, horaFin) SELECT NEWID(), @group, id, '08:00', '09:00' FROM dbo.uv_dia;
PRINT 'FES07_RUN1_BEGIN';
EXEC dbo.usp_generar_sesiones_grupo_v2 @idGrupo = @group, @idCorrelacion = @corr, @idUsuarioEjecutor = @teacherUser;
PRINT 'FES07_RUN1_END';
PRINT 'FES07_RUN2_BEGIN';
EXEC dbo.usp_generar_sesiones_grupo_v2 @idGrupo = @group, @idCorrelacion = @corr, @idUsuarioEjecutor = @teacherUser;
PRINT 'FES07_RUN2_END';
SELECT CONCAT('FES07|', (SELECT COUNT(*) FROM dbo.Sesion WHERE grupo = @group), '|', (SELECT COUNT(*) FROM dbo.SesionCancelacion sc JOIN dbo.Sesion s ON s.id = sc.sesion WHERE s.grupo = @group));
ROLLBACK TRANSACTION;
SELECT CONCAT('FES07_AFTER|', @@TRANCOUNT, '|', (SELECT COUNT(*) FROM dbo.Grupo WHERE id = @group));
"@
    $res = Invoke-ContainerSql -Name 'fes07' -Sql $sql
    $text = $res.Lines -join "`n"
    $run1 = Get-TupleRows -Text $text -Begin 'FES07_RUN1_BEGIN' -End 'FES07_RUN1_END'
    $run2 = Get-TupleRows -Text $text -Begin 'FES07_RUN2_BEGIN' -End 'FES07_RUN2_END'
    if ($run1.Count -ne 1 -or $run1[0] -notmatch '\|DBCODE=GEN_004\|.*\|1\|2\|0$') { throw "first run tuple: $($run1 -join ';') / $text" }
    if ($run2.Count -ne 1 -or $run2[0] -notmatch '\|DBCODE=GEN_004\|.*\|1\|0\|0$') { throw "second run tuple: $($run2 -join ';')" }
    if (@($res.Lines | Where-Object { $_ -eq 'FES07|20|2' }).Count -ne 1) { throw "expected 20 sessions and 2 cancelled: $text" }
    if (@($res.Lines | Where-Object { $_ -eq 'FES07_AFTER|0|0' }).Count -ne 1) { throw "rollback did not restore state: $text" }
    Write-Host 'TEST_PASS:CULM001_B1_FES_07_TUPLA_CONTEOS'
}
catch { $failures += "CULM001_B1_FES_07_TUPLA_CONTEOS $($_.Exception.Message)" }

# ---------------------------------------------------------------------------------------------------------------
# B1-FES-08a: falla inyectada en la fase 1 SIN transaccion externa => una tupla SYS_001, @@TRANCOUNT = 0, 0 sesiones
# ---------------------------------------------------------------------------------------------------------------
$fes08Ids = $null
try {
    $setup = @"
SET NOCOUNT ON;
SET XACT_ABORT ON;
$fixtureSql
DECLARE @period UNIQUEIDENTIFIER = NEWID(), @group UNIQUEIDENTIFIER = NEWID();
INSERT dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
VALUES (@period, @institution, N'CULM1 Periodo FES08A', 3700000 + ABS(CHECKSUM(NEWID()) % 99999), @firstDay, DATEADD(DAY, 7, @firstDay), YEAR(@firstDay));
INSERT dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
    cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
VALUES (@group, @assignment, @period, 944000 + ABS(CHECKSUM(NEWID()) % 55999), N'CULM1 Grupo FES08A', 20, 0, 0, 0, @teacher);
INSERT dbo.Horario (id, grupo, dia, horaInicio, horaFin) SELECT NEWID(), @group, id, '08:00', '09:00' FROM dbo.uv_dia;
SELECT CONCAT('FES08IDS|', CONVERT(VARCHAR(36), @period), '|', CONVERT(VARCHAR(36), @group), '|', CONVERT(VARCHAR(36), @teacherUser));
"@
    $res = Invoke-ContainerSql -Name 'fes08a_setup' -Sql $setup -AbortOnError
    $idsLine = @($res.Lines | Where-Object { $_ -like 'FES08IDS|*' })
    if ($idsLine.Count -ne 1) { throw "setup failed: $($res.Lines -join '; ')" }
    $fes08Ids = $idsLine[0].Split('|')
    $period = $fes08Ids[1]; $group = $fes08Ids[2]; $teacherUser = $fes08Ids[3]
    $run = @"
SET NOCOUNT ON;
DECLARE @u NVARCHAR(4000), @t NVARCHAR(4000), @corr UNIQUEIDENTIFIER = NEWID();
EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SYS_001', @mensajeUsuarioResultado = @u OUTPUT, @mensajeTecnicoResultado = @t OUTPUT;
PRINT CONCAT('EXPECTED_SYS001|', @u);
ALTER TABLE dbo.Sesion WITH NOCHECK ADD CONSTRAINT CK_CULM1_TMP_SESION_08A CHECK (grupo <> '$group' OR numero < 2);
PRINT 'FES08A_BEGIN';
EXEC dbo.usp_generar_sesiones_grupo_v2 @idGrupo = '$group', @idCorrelacion = @corr, @idUsuarioEjecutor = '$teacherUser';
PRINT 'FES08A_END';
SELECT CONCAT('FES08A_STATE|', @@TRANCOUNT, '|', (SELECT COUNT(*) FROM dbo.Sesion WHERE grupo = '$group'));
"@
    $res = Invoke-ContainerSql -Name 'fes08a_run' -Sql $run
    $text = $res.Lines -join "`n"
    $expectedUser = (@($res.Lines | Where-Object { $_ -like 'EXPECTED_SYS001|*' })[0]).Substring('EXPECTED_SYS001|'.Length)
    $rows = Get-TupleRows -Text $text -Begin 'FES08A_BEGIN' -End 'FES08A_END'
    if ($rows.Count -ne 1) { throw "expected one tuple; found $($rows.Count): $text" }
    $t = Split-Tuple -Line $rows[0]
    if ($t.User -cne $expectedUser -or $t.Rest -notmatch '\|0\|NULL\|NULL$') { throw "expected SYS_001 tuple with estadoResultado = 0: $($rows[0])" }
    if (@($res.Lines | Where-Object { $_ -eq 'FES08A_STATE|0|0' }).Count -ne 1) { throw "expected @@TRANCOUNT = 0 and 0 sessions: $text" }
    if ($text -match 'Msg \d+, Level') { throw "the v2 raised an error to the caller without an external transaction: $text" }
    Write-Host 'TEST_PASS:CULM001_B1_FES_08A_SIN_TRANSACCION_SYS001'
}
catch { $failures += "CULM001_B1_FES_08A_SIN_TRANSACCION_SYS001 $($_.Exception.Message)" }
finally {
    $cleanup = "SET NOCOUNT ON; IF OBJECT_ID('dbo.CK_CULM1_TMP_SESION_08A', 'C') IS NOT NULL ALTER TABLE dbo.Sesion DROP CONSTRAINT CK_CULM1_TMP_SESION_08A;"
    if ($fes08Ids) {
        $cleanup += " DELETE FROM dbo.Sesion WHERE grupo = '$($fes08Ids[2])'; DELETE FROM dbo.Horario WHERE grupo = '$($fes08Ids[2])'; DELETE FROM dbo.Grupo WHERE id = '$($fes08Ids[2])'; DELETE FROM dbo.PeriodoAcademico WHERE id = '$($fes08Ids[1])';"
    }
    try { $cr = Invoke-ContainerSql -Name 'fes08a_cleanup' -Sql $cleanup -AbortOnError; if ($cr.ExitCode -ne 0) { throw "cleanup exit $($cr.ExitCode): $($cr.Lines -join '; ')" } } catch { $failures += 'CULM001_B1_FES_08A cleanup failed' }
}

# ---------------------------------------------------------------------------------------------------------------
# B1-FES-08b2 (sin tupla): con transaccion externa el v2 hace THROW y no devuelve ninguna fila canonica
# ---------------------------------------------------------------------------------------------------------------
try {
    $sql = @"
SET NOCOUNT ON;
SET XACT_ABORT OFF;
$fixtureSql
DECLARE @period UNIQUEIDENTIFIER = NEWID(), @group UNIQUEIDENTIFIER = NEWID(), @corr UNIQUEIDENTIFIER = NEWID(), @sql NVARCHAR(MAX);
BEGIN TRANSACTION;
BEGIN TRY
    INSERT dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@period, @institution, N'CULM1 Periodo FES08B2', 3600000 + ABS(CHECKSUM(NEWID()) % 99999), @firstDay, DATEADD(DAY, 7, @firstDay), YEAR(@firstDay));
    INSERT dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
        cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@group, @assignment, @period, 945000 + ABS(CHECKSUM(NEWID()) % 54999), N'CULM1 Grupo FES08B2', 20, 0, 0, 0, @teacher);
    INSERT dbo.Horario (id, grupo, dia, horaInicio, horaFin) SELECT NEWID(), @group, id, '08:00', '09:00' FROM dbo.uv_dia;
    SET @sql = CONCAT(N'ALTER TABLE dbo.Sesion WITH NOCHECK ADD CONSTRAINT CK_CULM1_TMP_SESION_08B2 CHECK (grupo <> ''', CONVERT(NVARCHAR(36), @group), N''' OR numero < 2);');
    EXEC sys.sp_executesql @sql;
    PRINT 'FES08B2_BEGIN';
    EXEC dbo.usp_generar_sesiones_grupo_v2 @idGrupo = @group, @idCorrelacion = @corr, @idUsuarioEjecutor = @teacherUser;
    PRINT 'FES08B2_NO_THROW';
END TRY
BEGIN CATCH
    PRINT 'FES08B2_END';
    PRINT CONCAT('FES08B2_XACT|', XACT_STATE());
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
IF OBJECT_ID('dbo.CK_CULM1_TMP_SESION_08B2', 'C') IS NOT NULL ALTER TABLE dbo.Sesion DROP CONSTRAINT CK_CULM1_TMP_SESION_08B2;
SELECT CONCAT('FES08B2_STATE|', @@TRANCOUNT, '|', (SELECT COUNT(*) FROM dbo.Sesion WHERE grupo = @group), '|', (SELECT COUNT(*) FROM dbo.Grupo WHERE id = @group));
"@
    $res = Invoke-ContainerSql -Name 'fes08b2' -Sql $sql
    $text = $res.Lines -join "`n"
    if ($text -match 'FES08B2_NO_THROW') { throw "the v2 did not THROW with an external transaction: $text" }
    $rows = Get-TupleRows -Text $text -Begin 'FES08B2_BEGIN' -End 'FES08B2_END'
    if ($rows.Count -ne 0) { throw "the v2 returned a tuple with an external transaction: $($rows -join ';')" }
    if (@($res.Lines | Where-Object { $_ -eq 'FES08B2_XACT|-1' }).Count -ne 1) { throw "caller must see XACT_STATE() = -1: $text" }
    if (@($res.Lines | Where-Object { $_ -eq 'FES08B2_STATE|0|0|0' }).Count -ne 1) { throw "state after caller rollback: $text" }
    Write-Host 'TEST_PASS:CULM001_B1_FES_08B2_SIN_TUPLA'
}
catch { $failures += "CULM001_B1_FES_08B2_SIN_TUPLA $($_.Exception.Message)" }
finally {
    try { $null = Invoke-ContainerSql -Name 'fes08b2_cleanup' -Sql "IF OBJECT_ID('dbo.CK_CULM1_TMP_SESION_08B2', 'C') IS NOT NULL ALTER TABLE dbo.Sesion DROP CONSTRAINT CK_CULM1_TMP_SESION_08B2;" -AbortOnError } catch { }
}

# ---------------------------------------------------------------------------------------------------------------
# B1-FES-08b: paridad de la tupla de negocio (grupo sin horarios; docente no titular) entre v1 y v2
# ---------------------------------------------------------------------------------------------------------------
$parityIds = $null
try {
    $setup = @"
SET NOCOUNT ON;
SET XACT_ABORT ON;
$fixtureSql
DECLARE @period UNIQUEIDENTIFIER = NEWID(), @group UNIQUEIDENTIFIER = NEWID();
INSERT dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
VALUES (@period, @institution, N'CULM1 Periodo FES08B', 3500000 + ABS(CHECKSUM(NEWID()) % 99999), @firstDay, DATEADD(DAY, 7, @firstDay), YEAR(@firstDay));
INSERT dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
    cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
VALUES (@group, @assignment, @period, 946000 + ABS(CHECKSUM(NEWID()) % 53999), N'CULM1 Grupo FES08B', 20, 0, 0, 0, @teacher);
SELECT CONCAT('FES08BIDS|', CONVERT(VARCHAR(36), @period), '|', CONVERT(VARCHAR(36), @group), '|', CONVERT(VARCHAR(36), @teacherUser), '|', CONVERT(VARCHAR(36), @otherUser));
"@
    $res = Invoke-ContainerSql -Name 'fes08b_setup' -Sql $setup -AbortOnError
    $idsLine = @($res.Lines | Where-Object { $_ -like 'FES08BIDS|*' })
    if ($idsLine.Count -ne 1) { throw "setup failed: $($res.Lines -join '; ')" }
    $parityIds = $idsLine[0].Split('|')
    $group = $parityIds[2]; $teacherUser = $parityIds[3]; $otherUser = $parityIds[4]
    $run = @"
SET NOCOUNT ON;
DECLARE @c1 UNIQUEIDENTIFIER = NEWID(), @c2 UNIQUEIDENTIFIER = NEWID();
PRINT 'P_V1_SIN_HORARIO'; EXEC dbo.usp_generar_sesiones_grupo @idGrupo = '$group', @idCorrelacion = @c1, @idUsuarioEjecutor = '$teacherUser';
PRINT 'P_V2_SIN_HORARIO'; EXEC dbo.usp_generar_sesiones_grupo_v2 @idGrupo = '$group', @idCorrelacion = @c1, @idUsuarioEjecutor = '$teacherUser';
PRINT 'P_V1_NO_TITULAR'; EXEC dbo.usp_generar_sesiones_grupo @idGrupo = '$group', @idCorrelacion = @c2, @idUsuarioEjecutor = '$otherUser';
PRINT 'P_V2_NO_TITULAR'; EXEC dbo.usp_generar_sesiones_grupo_v2 @idGrupo = '$group', @idCorrelacion = @c2, @idUsuarioEjecutor = '$otherUser';
PRINT 'P_END';
"@
    $res = Invoke-ContainerSql -Name 'fes08b_run' -Sql $run
    $text = $res.Lines -join "`n"
    $casos = @(
        [pscustomobject]@{ Nombre = 'sin horario'; V1 = (Get-TupleRows -Text $text -Begin 'P_V1_SIN_HORARIO' -End 'P_V2_SIN_HORARIO'); V2 = (Get-TupleRows -Text $text -Begin 'P_V2_SIN_HORARIO' -End 'P_V1_NO_TITULAR') },
        [pscustomobject]@{ Nombre = 'no titular'; V1 = (Get-TupleRows -Text $text -Begin 'P_V1_NO_TITULAR' -End 'P_V2_NO_TITULAR'); V2 = (Get-TupleRows -Text $text -Begin 'P_V2_NO_TITULAR' -End 'P_END') }
    )
    foreach ($caso in $casos) {
        if ($caso.V1.Count -ne 1 -or $caso.V2.Count -ne 1) { throw "missing tuple ($($caso.Nombre)): $text" }
        if ($caso.V1[0] -notmatch '\|0$') { throw "v1 should reject ($($caso.Nombre)): $($caso.V1[0])" }
        if ("$($caso.V1[0])|NULL|NULL" -cne $caso.V2[0]) { throw "tuple parity ($($caso.Nombre)): v1=[$($caso.V1[0])] v2=[$($caso.V2[0])]" }
    }
    if ($casos[1].V1[0] -notmatch '\|DBCODE=SEC_002\|') { throw "non-owner should be SEC_002: $($casos[1].V1[0])" }
    Write-Host 'TEST_PASS:CULM001_B1_FES_08B_PARIDAD_TUPLA'
}
catch { $failures += "CULM001_B1_FES_08B_PARIDAD_TUPLA $($_.Exception.Message)" }
finally {
    if ($parityIds) {
        $cleanup = "SET NOCOUNT ON; DELETE FROM dbo.Sesion WHERE grupo = '$($parityIds[2])'; DELETE FROM dbo.Grupo WHERE id = '$($parityIds[2])'; DELETE FROM dbo.PeriodoAcademico WHERE id = '$($parityIds[1])';"
        try { $cr = Invoke-ContainerSql -Name 'fes08b_cleanup' -Sql $cleanup -AbortOnError; if ($cr.ExitCode -ne 0) { throw "cleanup exit $($cr.ExitCode): $($cr.Lines -join '; ')" } } catch { $failures += 'CULM001_B1_FES_08B cleanup failed' }
    }
}

# ---------------------------------------------------------------------------------------------------------------
# B1-MIG-01: migracion 15 up -> down -> up dentro de una transaccion revertida (sqlcmd -b: un error aborta y revierte)
# ---------------------------------------------------------------------------------------------------------------
try {
    $migDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'migrations'
    $up = Join-Path $migDir '15_culm001_b1_sesion_cancelada_festivos_up.sql'
    $down = Join-Path $migDir '15_culm001_b1_sesion_cancelada_festivos_down.sql'
    if (-not (Test-Path $up) -or -not (Test-Path $down)) { throw 'migration 15 up/down files are missing.' }
    foreach ($f in @($up, $down)) {
        $null = & docker cp $f "${ContainerName}:$remoteDir/$(Split-Path -Leaf $f)" 2>&1
        if ($LASTEXITCODE -ne 0) { throw "could not copy $f" }
    }
    $null = & docker exec -u 0 $ContainerName chmod -R a+r $remoteDir 2>&1
    $checkUp = @'
IF OBJECT_ID(N'dbo.SesionCancelacion', N'U') IS NULL OR OBJECT_ID(N'dbo.TipoCancelacionSesion', N'U') IS NULL
   OR OBJECT_ID(N'dbo.DiaFestivo', N'U') IS NULL OR OBJECT_ID(N'dbo.CargaDiaFestivo', N'U') IS NULL
   OR OBJECT_ID(N'dbo.uv_sesion_estado', N'V') IS NULL OR OBJECT_ID(N'dbo.uv_dia_festivo', N'V') IS NULL
   OR OBJECT_ID(N'dbo.uv_carga_dia_festivo', N'V') IS NULL OR OBJECT_ID(N'dbo.uv_tipo_cancelacion_sesion', N'V') IS NULL
   OR (SELECT COUNT(*) FROM dbo.TipoCancelacionSesion) <> 2
   OR OBJECT_ID(N'dbo.FK_SesionCancelacion_Sesion', N'F') IS NULL OR OBJECT_ID(N'dbo.FK_SesionCancelacion_DiaFestivo', N'F') IS NULL
   OR NOT EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.uv_cumplimiento_sesion_grupo') AND definition LIKE N'%SesionCancelacion%')
    THROW 57600, 'MIG_CHECK_UP_FAILED', 1;
'@
    $wrapper = @"
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT OFF;
GO
BEGIN TRANSACTION;
GO
:r $remoteDir/15_culm001_b1_sesion_cancelada_festivos_up.sql
GO
$checkUp
PRINT 'MIG_UP1_OK';
GO
:r $remoteDir/15_culm001_b1_sesion_cancelada_festivos_down.sql
GO
IF OBJECT_ID(N'dbo.SesionCancelacion', N'U') IS NOT NULL OR OBJECT_ID(N'dbo.TipoCancelacionSesion', N'U') IS NOT NULL
   OR OBJECT_ID(N'dbo.DiaFestivo', N'U') IS NOT NULL OR OBJECT_ID(N'dbo.CargaDiaFestivo', N'U') IS NOT NULL
   OR OBJECT_ID(N'dbo.uv_sesion_estado', N'V') IS NOT NULL OR OBJECT_ID(N'dbo.uv_dia_festivo', N'V') IS NOT NULL
   OR OBJECT_ID(N'dbo.uv_carga_dia_festivo', N'V') IS NOT NULL OR OBJECT_ID(N'dbo.uv_tipo_cancelacion_sesion', N'V') IS NOT NULL
   OR OBJECT_ID(N'dbo.usp_cancelar_sesion', N'P') IS NOT NULL OR OBJECT_ID(N'dbo.usp_generar_sesiones_grupo_v2', N'P') IS NOT NULL
   OR OBJECT_ID(N'dbo.usp_internal_aplicar_festivos_grupo', N'P') IS NOT NULL OR OBJECT_ID(N'dbo.usp_cargar_dias_festivos', N'P') IS NOT NULL
   OR OBJECT_ID(N'dbo.usp_consultar_dias_festivos', N'P') IS NOT NULL OR OBJECT_ID(N'dbo.usp_consultar_destinatarios_sesion_cancelada', N'P') IS NOT NULL
   OR (SELECT COUNT(*) FROM sys.parameters WHERE object_id = OBJECT_ID(N'dbo.usp_validar_sesion_ventana_registro_interno')) <> 5
   OR EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_precargar_sesiones_grupo_interno') AND definition LIKE N'%festivo%')
   OR EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.uv_cumplimiento_sesion_grupo') AND definition LIKE N'%SesionCancelacion%')
   OR EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id IN (OBJECT_ID(N'dbo.usp_consultar_sesiones_grupo_paginado'), OBJECT_ID(N'dbo.usp_consultar_sesiones_facultad_paginado')) AND definition LIKE N'%uv_sesion_estado%')
   OR OBJECT_ID(N'dbo.usp_validar_sesion_ventana_registro_interno', N'P') IS NULL OR OBJECT_ID(N'dbo.usp_precargar_sesiones_grupo_interno', N'P') IS NULL
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('SES_010', 'SES_011', 'SES_012', 'SES_013', 'SES_014', 'SES_016') OR codigo LIKE 'FES[_]%')
   OR EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo = 'FESTIVOS' OR (grupo = 'SESION' AND clave LIKE 'MOTIVO_CANCELACION%'))
   OR EXISTS (SELECT 1 FROM dbo.PlantillaNotificacion WHERE tipo = 'SESION_CANCELADA' AND creadoPor IS NULL)
   OR EXISTS (SELECT 1 FROM dbo.PlantillaNotificacionMarcador WHERE tipo = 'SESION_CANCELADA')
    THROW 57601, 'MIG_CHECK_DOWN_FAILED', 1;
-- El SES-01 restaurado sigue funcionando con la regla estricta (5 parametros)
DECLARE @u NVARCHAR(4000), @t NVARCHAR(4000), @e BIT, @s UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Sesion ORDER BY id), @c UNIQUEIDENTIFIER = NEWID();
IF @s IS NOT NULL
BEGIN
    EXEC dbo.usp_validar_sesion_ventana_registro_interno @idSesion = @s, @idCorrelacion = @c,
        @mensajeUsuarioResultado = @u OUTPUT, @mensajeTecnicoResultado = @t OUTPUT, @estadoResultado = @e OUTPUT;
    IF @t LIKE N'DBCODE=SYS[_]001|%' THROW 57602, 'MIG_CHECK_DOWN_VENTANA_BROKEN', 1;
END
PRINT 'MIG_DOWN_OK';
GO
:r $remoteDir/15_culm001_b1_sesion_cancelada_festivos_down.sql
GO
PRINT 'MIG_DOWN2_OK';
GO
:r $remoteDir/15_culm001_b1_sesion_cancelada_festivos_up.sql
GO
$checkUp
PRINT 'MIG_UP2_OK';
GO
:r $remoteDir/15_culm001_b1_sesion_cancelada_festivos_up.sql
GO
$checkUp
PRINT 'MIG_UP3_OK';
GO
ROLLBACK TRANSACTION;
GO
IF @@TRANCOUNT <> 0 THROW 57603, 'MIG_TRANCOUNT', 1;
IF OBJECT_ID(N'dbo.usp_cancelar_sesion', N'P') IS NULL OR OBJECT_ID(N'dbo.usp_generar_sesiones_grupo_v2', N'P') IS NULL
   OR (SELECT COUNT(*) FROM sys.parameters WHERE object_id = OBJECT_ID(N'dbo.usp_validar_sesion_ventana_registro_interno')) <> 8
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'SES_010')
    THROW 57604, 'MIG_ROLLBACK_DID_NOT_RESTORE', 1;
PRINT 'MIG_RESTORED_OK';
GO
"@
    $res = Invoke-ContainerSql -Name 'mig15' -Sql $wrapper -AbortOnError
    $text = $res.Lines -join "`n"
    foreach ($marker in @('MIG_UP1_OK', 'MIG_DOWN_OK', 'MIG_DOWN2_OK', 'MIG_UP2_OK', 'MIG_UP3_OK', 'MIG_RESTORED_OK')) {
        if ($text -notmatch $marker) { throw "missing $marker (exit $($res.ExitCode)): $text" }
    }
    if ($res.ExitCode -ne 0) { throw "sqlcmd exit $($res.ExitCode): $text" }
    Write-Host 'TEST_PASS:CULM001_B1_MIG_01_UP_DOWN_UP'
}
catch { $failures += "CULM001_B1_MIG_01_UP_DOWN_UP $($_.Exception.Message)" }
finally {
    # Garantia: si la migracion se interrumpio, la conexion cerrada revirtio la transaccion; se verifica el estado
    try {
        $state = Invoke-ContainerSql -Name 'mig15_state' -Sql "SET NOCOUNT ON; SELECT CONCAT('MIGSTATE|', IIF(OBJECT_ID(N'dbo.SesionCancelacion', N'U') IS NULL, 0, 1), '|', IIF(OBJECT_ID(N'dbo.usp_cancelar_sesion', N'P') IS NULL, 0, 1));" -AbortOnError
        if (@($state.Lines | Where-Object { $_ -eq 'MIGSTATE|1|1' }).Count -ne 1) { $failures += "CULM001_B1_MIG_01 left the database without B.1 objects: $($state.Lines -join ';')" }
    }
    catch { $failures += 'CULM001_B1_MIG_01 state check failed' }
}

$null = & docker exec -u 0 $ContainerName rm -rf $remoteDir 2>&1
Remove-Item -Recurse -Force -Path $localDir -ErrorAction SilentlyContinue
foreach ($f in $failures) { Write-Host "TEST FAILED: $f" }
if ($failures.Count -gt 0) { exit 1 }
exit 0
