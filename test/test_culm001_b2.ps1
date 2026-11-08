param (
    [string]$ContainerName = 'sqlserver',
    [string]$Password = $env:MSSQL_SA_PASSWORD
)

# CULM-001 B.2 (CONTRACT §2.14, §2.16.2): casos que no caben en un archivo T-SQL de la suite porque requieren sqlcmd con
# variables y :r de migrations/ y schema/ (B2-MIG-01..05, test/test_culm001_b2_migraciones.sql), una conexion que termina
# con THROW 50011 (B2-MIG-03 sin confirmacion) o dos conexiones concurrentes (B2-TOM-08 docente + job, B2-TOM-10 dos
# pasadas del job). Cada caso deja la BD como estaba (transaccion revertida o fixture CULMB2_ propio con limpieza).
# Salida: TEST_PASS:<ID> por caso aprobado y TEST FAILED: <ID> <motivo> por caso fallido.

$ErrorActionPreference = 'Stop'
if (-not $Password) { throw 'SQL password is required for test_culm001_b2.ps1.' }

$tag = [guid]::NewGuid().ToString('N').Substring(0, 12)
$remoteDir = "/tmp/culm001_b2_$tag"
$localDir = Join-Path ([System.IO.Path]::GetTempPath()) "culm001_b2_$tag"
New-Item -ItemType Directory -Force -Path $localDir | Out-Null
$null = & docker exec -u 0 $ContainerName mkdir -p $remoteDir 2>&1
$failures = @()
$dbRoot = Split-Path -Parent $PSScriptRoot

function Invoke-ContainerSql {
    param ([string]$Name, [string]$Sql, [switch]$AbortOnError, [string[]]$Variables = @())
    $local = Join-Path $localDir "$Name.sql"
    Set-Content -Path $local -Value $Sql -Encoding utf8
    $remote = "$remoteDir/$Name.sql"
    $copy = @(& docker cp $local "${ContainerName}:$remote" 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "could not copy ${Name}: $($copy -join '; ')" }
    $null = & docker exec -u 0 $ContainerName chmod a+r $remote 2>&1
    $sqlArgs = @('exec', $ContainerName, '/opt/mssql-tools18/bin/sqlcmd', '-S', 'localhost', '-d', 'gestionasistenciadb', '-U', 'sa', '-P', $Password,
              '-C', '-I', '-h', '-1', '-W', '-s', '|', '-w', '65535', '-t', '600', '-i', $remote)
    foreach ($v in $Variables) { $sqlArgs += @('-v', $v) }
    if ($AbortOnError) { $sqlArgs += '-b' }
    $output = @(& docker @sqlArgs 2>&1 | ForEach-Object { "$_".Trim() })
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Lines = $output }
}

# Copia de migrations/, schema/ y del archivo de migraciones de prueba
$null = & docker exec -u 0 $ContainerName mkdir -p "$remoteDir/migrations" "$remoteDir/schema" 2>&1
foreach ($pair in @(@('migrations', 'migrations'), @('schema', 'schema'))) {
    $copy = @(& docker cp (Join-Path $dbRoot "$($pair[0])/.") "${ContainerName}:$remoteDir/$($pair[1])" 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "could not copy $($pair[0]): $($copy -join '; ')" }
}
$copy = @(& docker cp (Join-Path $PSScriptRoot 'test_culm001_b2_migraciones.sql') "${ContainerName}:$remoteDir/test_culm001_b2_migraciones.sql" 2>&1)
if ($LASTEXITCODE -ne 0) { throw "could not copy test_culm001_b2_migraciones.sql: $($copy -join '; ')" }
$null = & docker exec -u 0 $ContainerName chmod -R a+rX $remoteDir 2>&1

# ---------------------------------------------------------------------------------------------------------------
# B2-MIG-01..05: test_culm001_b2_migraciones.sql dentro de una transaccion revertida
# ---------------------------------------------------------------------------------------------------------------
try {
    $sqlArgs = @('exec', $ContainerName, '/opt/mssql-tools18/bin/sqlcmd', '-S', 'localhost', '-d', 'gestionasistenciadb', '-U', 'sa', '-P', $Password,
              '-C', '-I', '-h', '-1', '-W', '-s', '|', '-w', '65535', '-t', '600', '-v', "MIGDIR=$remoteDir/migrations", '-v', "SCHEMADIR=$remoteDir/schema",
              '-i', "$remoteDir/test_culm001_b2_migraciones.sql")
    $lines = @(& docker @sqlArgs 2>&1 | ForEach-Object { "$_".Trim() })
    $exit = $LASTEXITCODE
    $text = $lines -join "`n"
    $marks = @{
        'CULM001_B2_MIG_03_DOWN_RESTAURA'       = @('MIG_SNAPSHOT_OK', 'MIG_DOWN1_OK', 'MIG_DOWN2_OK')
        'CULM001_B2_MIG_01_UP_CON_DATOS'        = @('MIG_UP1_OK')
        'CULM001_B2_MIG_02_UP_IDEMPOTENTE'      = @('MIG_UP2_OK')
        'CULM001_B2_MIG_05_DOBLE_DESPLIEGUE'    = @('MIG_DEPLOY1_OK', 'MIG_DEPLOY2_OK', 'MIG_DEPLOY_VACIA_OK')
        'CULM001_B2_MIG_04_UP_DOWN_UP_15_16'    = @('MIG_15_16_DOWN_OK', 'MIG_15_16_UP_OK', 'MIG_RESTORED_OK')
    }
    foreach ($id in @('CULM001_B2_MIG_03_DOWN_RESTAURA', 'CULM001_B2_MIG_01_UP_CON_DATOS', 'CULM001_B2_MIG_02_UP_IDEMPOTENTE',
                      'CULM001_B2_MIG_05_DOBLE_DESPLIEGUE', 'CULM001_B2_MIG_04_UP_DOWN_UP_15_16')) {
        $missing = @($marks[$id] | Where-Object { $text -notmatch "(?m)^$_$" })
        if ($missing.Count -eq 0 -and ($exit -eq 0 -or $id -ne 'CULM001_B2_MIG_04_UP_DOWN_UP_15_16')) { Write-Output "TEST_PASS:$id" }
        else { $failures += "$id missing $($missing -join ',') (exit $exit): $(($lines | Where-Object { $_ -match 'Msg |MIG_|TEST' }) -join ' / ')" }
    }
}
catch { $failures += "CULM001_B2_MIG_RUNNER $($_.Exception.Message)" }
finally {
    try {
        $state = Invoke-ContainerSql -Name 'mig16_state' -Sql "SET NOCOUNT ON; SELECT CONCAT('MIGSTATE|', IIF(OBJECT_ID(N'dbo.TomaAsistencia', N'U') IS NULL, 0, 1), '|', COLUMNPROPERTY(OBJECT_ID(N'dbo.DetalleAsistencia'), 'toma', 'AllowsNull'), '|', IIF(OBJECT_ID(N'dbo.usp_abrir_toma_asistencia', N'P') IS NULL, 0, 1));" -AbortOnError
        if (@($state.Lines | Where-Object { $_ -eq 'MIGSTATE|1|0|1' }).Count -ne 1) { $failures += "CULM001_B2_MIG left the database without B.2 objects: $($state.Lines -join ';')" }
    }
    catch { $failures += 'CULM001_B2_MIG state check failed' }
}

# ---------------------------------------------------------------------------------------------------------------
# B2-MIG-03 con 2 tomas: sin confirmacion THROW 50011 (la conexion se cierra y revierte); con confirmacion queda la SJC
# y zz_archivo_DetalleAsistencia_culm001_b2 contiene el detalle descartado
# ---------------------------------------------------------------------------------------------------------------
$twoTomasSetup = @"
SET NOCOUNT ON;
SET XACT_ABORT OFF;
DECLARE @a UNIQUEIDENTIFIER, @s UNIQUEIDENTIFIER, @t1 UNIQUEIDENTIFIER, @t2 UNIQUEIDENTIFIER = NEWID(), @d UNIQUEIDENTIFIER;
SELECT TOP 1 @a = da.asistencia, @s = t.sesion, @t1 = t.id, @d = da.id
FROM dbo.DetalleAsistencia da INNER JOIN dbo.TomaAsistencia t ON t.id = da.toma
WHERE t.numero = 1 AND NOT EXISTS (SELECT 1 FROM dbo.TomaAsistencia t2 WHERE t2.sesion = t.sesion AND t2.numero > 1)
ORDER BY da.id;
IF @a IS NULL
BEGIN
    DECLARE @eg UNIQUEIDENTIFIER;
    SELECT TOP 1 @s = s.id, @eg = eg.id
    FROM dbo.Sesion s
    INNER JOIN dbo.EstudianteGrupo eg ON eg.grupo = s.grupo
    WHERE NOT EXISTS (SELECT 1 FROM dbo.TomaAsistencia t WHERE t.sesion = s.id AND t.numero > 1)
    ORDER BY s.id;

    IF @s IS NOT NULL AND @eg IS NOT NULL
    BEGIN
        SELECT TOP 1 @t1 = t.id FROM dbo.TomaAsistencia t WHERE t.sesion = @s AND t.numero = 1;
        IF @t1 IS NULL
        BEGIN
            SET @t1 = NEWID();
            INSERT INTO dbo.TomaAsistencia (id, sesion, numero, modo, estado, esImplicita, docenteApertura, fechaAperturaUtc, fechaCierreUtc, idCorrelacionApertura)
            VALUES (@t1, @s, 1, (SELECT TOP 1 id FROM dbo.ModoTomaAsistencia WHERE usaCodigoQr = 0), (SELECT TOP 1 id FROM dbo.EstadoTomaAsistencia WHERE estaAbierta = 0), 1, NULL, SYSUTCDATETIME(), SYSUTCDATETIME(), NEWID());
        END
        SELECT TOP 1 @a = a.id FROM dbo.Asistencia a WHERE a.sesion = @s AND a.estudianteGrupo = @eg;
        IF @a IS NULL
        BEGIN
            SET @a = NEWID();
            INSERT INTO dbo.Asistencia (id, sesion, estudianteGrupo) VALUES (@a, @s, @eg);
        END
        SET @d = NEWID();
        INSERT INTO dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin, toma, registradoPorEstudiante, fechaRegistroUtc)
        VALUES (@d, NEXT VALUE FOR dbo.seq_detalle_asistencia_codigo, @a, 1, (SELECT TOP 1 id FROM dbo.RazonCausa WHERE codigo = N'AN'), SYSUTCDATETIME(), DATEADD(HOUR, 1, SYSUTCDATETIME()), @t1, 0, SYSUTCDATETIME());
    END
END
IF @a IS NULL THROW 57760, 'MIG_COLAPSO_SIN_DATOS', 1;
UPDATE dbo.DetalleAsistencia SET razonCausa = (SELECT id FROM dbo.RazonCausa WHERE codigo = N'AN'), asistio = 1 WHERE id = @d;
INSERT INTO dbo.TomaAsistencia (id, sesion, numero, modo, estado, esImplicita, docenteApertura, fechaAperturaUtc, fechaCierreUtc, idCorrelacionApertura)
SELECT @t2, @s, 2, (SELECT id FROM dbo.ModoTomaAsistencia WHERE usaCodigoQr = 0), (SELECT id FROM dbo.EstadoTomaAsistencia WHERE estaAbierta = 0), 0, NULL,
       CAST(SYSUTCDATETIME() AS DATETIME2(0)), CAST(SYSUTCDATETIME() AS DATETIME2(0)), NEWID();
INSERT INTO dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin, toma, registradoPorEstudiante, fechaRegistroUtc)
SELECT NEWID(), NEXT VALUE FOR dbo.seq_detalle_asistencia_codigo, @a, 0, (SELECT id FROM dbo.RazonCausa WHERE codigo = N'SJC'), fechaHoraInicio, fechaHoraFin, @t2, 0, SYSUTCDATETIME()
FROM dbo.DetalleAsistencia WHERE id = @d;
IF OBJECT_ID(N'tempdb..#b2col') IS NOT NULL DROP TABLE #b2col;
SELECT asistencia = @a, detalleAn = @d INTO #b2col;
PRINT 'COLAPSO_SETUP_OK';
"@
try {
    $sql = @"
:on error exit
BEGIN TRANSACTION;
GO
$twoTomasSetup
GO
:setvar CONFIRMAR_COLAPSO 0
:r $remoteDir/migrations/16_culm001_b2_tomas_asistencia_qr_down.sql
GO
PRINT 'COLAPSO_NO_DEBIO_LLEGAR';
GO
"@
    $res = Invoke-ContainerSql -Name 'mig16_colapso_sin' -Sql $sql
    $text = $res.Lines -join "`n"
    if ($text -notmatch 'COLAPSO_SETUP_OK' -or $text -notmatch 'Msg 50011' -or $text -match 'COLAPSO_NO_DEBIO_LLEGAR' -or $res.ExitCode -eq 0) {
        throw "expected THROW 50011 and an aborted script (exit $($res.ExitCode)): $text"
    }
    $check = Invoke-ContainerSql -Name 'mig16_colapso_sin_check' -Sql "SET NOCOUNT ON; SELECT CONCAT('COLSIN|', IIF(OBJECT_ID(N'dbo.TomaAsistencia', N'U') IS NULL, 0, 1), '|', (SELECT COUNT(*) FROM dbo.TomaAsistencia WHERE numero > 1 AND idCorrelacionCierre IS NULL AND docenteApertura IS NULL AND esImplicita = 0), '|', IIF(OBJECT_ID(N'dbo.zz_archivo_DetalleAsistencia_culm001_b2', N'U') IS NULL, 0, 1));" -AbortOnError
    if (@($check.Lines | Where-Object { $_ -eq 'COLSIN|1|0|0' }).Count -ne 1) { throw "state after aborted down: $($check.Lines -join ';')" }
    Write-Output 'TEST_PASS:CULM001_B2_MIG_03_COLAPSO_SIN_CONFIRMACION'
}
catch { $failures += "CULM001_B2_MIG_03_COLAPSO_SIN_CONFIRMACION $($_.Exception.Message)" }

try {
    $sql = @"
:on error exit
SET XACT_ABORT OFF;
GO
BEGIN TRANSACTION;
GO
$twoTomasSetup
GO
:setvar CONFIRMAR_COLAPSO 1
:r $remoteDir/migrations/16_culm001_b2_tomas_asistencia_qr_down.sql
GO
DECLARE @a UNIQUEIDENTIFIER = (SELECT asistencia FROM #b2col), @d UNIQUEIDENTIFIER = (SELECT detalleAn FROM #b2col);
IF (SELECT COUNT(*) FROM dbo.DetalleAsistencia WHERE asistencia = @a) <> 1
   OR NOT EXISTS (SELECT 1 FROM dbo.DetalleAsistencia da INNER JOIN dbo.RazonCausa rc ON rc.id = da.razonCausa WHERE da.asistencia = @a AND rc.codigo = N'SJC' AND da.asistio = 0)
   OR NOT EXISTS (SELECT 1 FROM dbo.zz_archivo_DetalleAsistencia_culm001_b2 WHERE id = @d)
   OR COL_LENGTH(N'dbo.DetalleAsistencia', N'toma') IS NOT NULL
   OR EXISTS (SELECT 1 FROM sys.foreign_keys WHERE referenced_object_id = OBJECT_ID(N'dbo.zz_archivo_DetalleAsistencia_culm001_b2') OR parent_object_id = OBJECT_ID(N'dbo.zz_archivo_DetalleAsistencia_culm001_b2'))
    THROW 57761, 'MIG_COLAPSO_CONFIRMADO_FAILED', 1;
PRINT 'COLAPSO_CONFIRMADO_OK';
GO
ROLLBACK TRANSACTION;
GO
IF @@TRANCOUNT <> 0 OR OBJECT_ID(N'dbo.TomaAsistencia', N'U') IS NULL OR OBJECT_ID(N'dbo.zz_archivo_DetalleAsistencia_culm001_b2', N'U') IS NOT NULL
    THROW 57762, 'MIG_COLAPSO_ROLLBACK_FAILED', 1;
PRINT 'COLAPSO_RESTAURADO_OK';
GO
"@
    $res = Invoke-ContainerSql -Name 'mig16_colapso_con' -Sql $sql
    $text = $res.Lines -join "`n"
    if ($text -notmatch 'COLAPSO_CONFIRMADO_OK' -or $text -notmatch 'COLAPSO_RESTAURADO_OK' -or $res.ExitCode -ne 0) { throw "exit $($res.ExitCode): $text" }
    Write-Output 'TEST_PASS:CULM001_B2_MIG_03_COLAPSO_CONFIRMADO'
}
catch { $failures += "CULM001_B2_MIG_03_COLAPSO_CONFIRMADO $($_.Exception.Message)" }

# ---------------------------------------------------------------------------------------------------------------
# B2-SEG-02: maint_003g_attendance_fixture.sql y dev_pagination_cleanup.sql + dev_pagination_fixture.sql dos veces seguidas
# sin errores de FK (las limpiezas borran tokens, tomas y cancelaciones antes de la sesion), dentro de una transaccion
# revertida
# ---------------------------------------------------------------------------------------------------------------
try {
    foreach ($f in @('fixtures/maint_003g_attendance_fixture.sql', 'fixtures/dev/dev_pagination_fixture.sql', 'fixtures/dev/dev_pagination_cleanup.sql')) {
        $copy = @(& docker cp (Join-Path $PSScriptRoot $f) "${ContainerName}:$remoteDir/$(Split-Path -Leaf $f)" 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "could not copy ${f}: $($copy -join '; ')" }
    }
    $null = & docker exec -u 0 $ContainerName chmod -R a+rX $remoteDir 2>&1
    $sql = @"
:on error exit
:setvar Scenarios 300
SET NOCOUNT ON;
GO
BEGIN TRANSACTION;
GO
:r $remoteDir/maint_003g_attendance_fixture.sql
GO
:r $remoteDir/maint_003g_attendance_fixture.sql
GO
IF NOT EXISTS (SELECT 1 FROM dbo.TomaAsistencia t INNER JOIN dbo.Sesion s ON s.id = t.sesion WHERE s.nombre = N'IT-MAINT003G-ATTENDANCE')
    THROW 57770, 'SEG02_MAINT_SIN_TOMA: el lote congelado del fixture debe crear la toma implicita.', 1;
PRINT 'SEG02_MAINT_OK';
GO
:r $remoteDir/dev_pagination_cleanup.sql
GO
:r $remoteDir/dev_pagination_fixture.sql
GO
DROP TABLE IF EXISTS #esc, #nom, #ape, #est;
GO
:r $remoteDir/dev_pagination_cleanup.sql
GO
:r $remoteDir/dev_pagination_fixture.sql
GO
-- el fixture de paginacion deja tablas temporales de sesion: se retiran para repetirlo en la misma conexion
DROP TABLE IF EXISTS #esc, #nom, #ape, #est;
GO
IF NOT EXISTS (SELECT 1 FROM dbo.TomaAsistencia WHERE LEFT(CONVERT(CHAR(36), id), 8) = 'DE00000A')
    THROW 57771, 'SEG02_DEV_SIN_TOMA: el fixture de paginacion debe crear la toma 1 de sus sesiones.', 1;
GO
:r $remoteDir/dev_pagination_cleanup.sql
GO
IF EXISTS (SELECT 1 FROM dbo.TomaAsistencia WHERE LEFT(CONVERT(CHAR(36), sesion), 6) = 'DE0000')
    THROW 57772, 'SEG02_DEV_LIMPIEZA: la limpieza de paginacion debe borrar las tomas del fixture.', 1;
PRINT 'SEG02_DEV_OK';
GO
ROLLBACK TRANSACTION;
GO
IF @@TRANCOUNT <> 0 THROW 57773, 'SEG02_TRANCOUNT', 1;
PRINT 'SEG02_RESTORED_OK';
GO
"@
    $res = Invoke-ContainerSql -Name 'seg02' -Sql $sql
    $text = $res.Lines -join "`n"
    foreach ($m in @('SEG02_MAINT_OK', 'SEG02_DEV_OK', 'SEG02_RESTORED_OK')) { if ($text -notmatch $m) { throw "missing $m (exit $($res.ExitCode)): $(($res.Lines | Where-Object { $_ -match 'Msg |SEG02|Level' }) -join ' / ')" } }
    if ($res.ExitCode -ne 0) { throw "exit $($res.ExitCode)" }
    Write-Output 'TEST_PASS:CULM001_B2_SEG_02_FIXTURES_REPETIBLES'
}
catch { $failures += "CULM001_B2_SEG_02_FIXTURES_REPETIBLES $($_.Exception.Message)" }

# ---------------------------------------------------------------------------------------------------------------
# Fixture confirmado (CULMB2_) para los casos concurrentes: grupo con 3 estudiantes activos y tomas QR abiertas en
# sesiones cuya ventana con margen ya vencio (el job puede cerrarlas)
# ---------------------------------------------------------------------------------------------------------------
$fixtureTag = "CULMB2_$tag"
$setupSql = @"
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @idAsig UNIQUEIDENTIFIER = (SELECT TOP 1 a.id FROM dbo.uv_asignatura a WHERE a.estaActivaAsignatura = 1 ORDER BY a.id);
DECLARE @idInst UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion ORDER BY id);
DECLARE @estadoA UNIQUEIDENTIFIER = (SELECT id FROM dbo.uv_estado_estudiante_grupo WHERE codigo = 'A');
DECLARE @modoQr UNIQUEIDENTIFIER = (SELECT id FROM dbo.ModoTomaAsistencia WHERE usaCodigoQr = 1);
DECLARE @abierta UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoTomaAsistencia WHERE estaAbierta = 1);
DECLARE @uD UNIQUEIDENTIFIER = NEWID(), @d UNIQUEIDENTIFIER = NEWID(), @per UNIQUEIDENTIFIER = NEWID(), @g UNIQUEIDENTIFIER = NEWID();
DECLARE @hoy DATE = CAST(SYSUTCDATETIME() AS DATE);
BEGIN TRANSACTION;
INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
VALUES (@uD, @tipoCC, 979000000 + ABS(CHECKSUM(NEWID()) % 999999), N'Concurrente', N'CulmB', N'Doc', N'B2', N'$fixtureTag.d@test.local', 1, 1, N'HashBackend_CULMB2');
INSERT INTO dbo.Docente (id, usuario) VALUES (@d, @uD);
DECLARE @e TABLE (n INT, u UNIQUEIDENTIFIER, e UNIQUEIDENTIFIER);
INSERT INTO @e SELECT v.n, NEWID(), NEWID() FROM (VALUES (1), (2), (3)) v(n);
INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
SELECT u, @tipoCC, 979100000 + n * 10000 + ABS(CHECKSUM(NEWID()) % 9999), CONCAT(N'Conc', n), N'CulmB', N'Est', N'B2', CONCAT(N'$fixtureTag.e', n, N'@test.local'), 1, 1, N'HashBackend_CULMB2' FROM @e;
INSERT INTO dbo.Estudiante (id, usuario) SELECT e, u FROM @e;
INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
VALUES (@per, @idInst, N'$fixtureTag', 3500000 + ABS(CHECKSUM(NEWID()) % 400000), DATEADD(DAY, -30, @hoy), DATEADD(DAY, 30, @hoy), YEAR(@hoy));
INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
    cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
VALUES (@g, @idAsig, @per, 949000 + ABS(CHECKSUM(NEWID()) % 50999), N'$fixtureTag', 30, 0, 0, 0, @d);
INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo) SELECT NEWID(), @estadoA, e, @g FROM @e;
INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
SELECT NEWID(), CONCAT(N'$fixtureTag S', v.n), v.n, CONCAT(N'CB2C', v.n), 1, @g, DATEADD(MINUTE, -300 - v.n, SYSUTCDATETIME()), DATEADD(MINUTE, -180 - v.n, SYSUTCDATETIME()), N'UTC_V2'
FROM (VALUES (1), (2), (3), (4)) v(n);
INSERT INTO dbo.TomaAsistencia (id, sesion, numero, modo, estado, esImplicita, docenteApertura, fechaAperturaUtc, fechaCierreUtc, idCorrelacionApertura)
SELECT NEWID(), s.id, 1, @modoQr, @abierta, 0, @d, DATEADD(MINUTE, -290, SYSUTCDATETIME()), NULL, NEWID() FROM dbo.Sesion s WHERE s.grupo = @g;
COMMIT TRANSACTION;
SELECT CONCAT('FIXTURE|', CONVERT(VARCHAR(36), @g), '|', CONVERT(VARCHAR(36), @uD));
SELECT CONCAT('TOMA|', s.numero, '|', CONVERT(VARCHAR(36), t.id)) FROM dbo.Sesion s INNER JOIN dbo.TomaAsistencia t ON t.sesion = s.id WHERE s.grupo = @g ORDER BY s.numero;
"@
$cleanupSql = @"
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @g TABLE (id UNIQUEIDENTIFIER);
INSERT INTO @g SELECT id FROM dbo.Grupo WHERE nombre = N'$fixtureTag';
BEGIN TRANSACTION;
DELETE da FROM dbo.DetalleAsistencia da INNER JOIN dbo.Asistencia a ON a.id = da.asistencia INNER JOIN dbo.Sesion s ON s.id = a.sesion WHERE s.grupo IN (SELECT id FROM @g);
DELETE tk FROM dbo.TokenAsistenciaToma tk INNER JOIN dbo.TomaAsistencia t ON t.id = tk.toma INNER JOIN dbo.Sesion s ON s.id = t.sesion WHERE s.grupo IN (SELECT id FROM @g);
DELETE t FROM dbo.TomaAsistencia t INNER JOIN dbo.Sesion s ON s.id = t.sesion WHERE s.grupo IN (SELECT id FROM @g);
DELETE sc FROM dbo.SesionCancelacion sc INNER JOIN dbo.Sesion s ON s.id = sc.sesion WHERE s.grupo IN (SELECT id FROM @g);
DELETE a FROM dbo.Asistencia a INNER JOIN dbo.Sesion s ON s.id = a.sesion WHERE s.grupo IN (SELECT id FROM @g);
DELETE FROM dbo.Sesion WHERE grupo IN (SELECT id FROM @g);
DELETE FROM dbo.EstudianteGrupo WHERE grupo IN (SELECT id FROM @g);
DELETE FROM dbo.Grupo WHERE id IN (SELECT id FROM @g);
DELETE FROM dbo.PeriodoAcademico WHERE nombre = N'$fixtureTag';
DELETE e FROM dbo.Estudiante e INNER JOIN dbo.Usuario u ON u.id = e.usuario WHERE u.correo LIKE N'$fixtureTag.%';
DELETE d FROM dbo.Docente d INNER JOIN dbo.Usuario u ON u.id = d.usuario WHERE u.correo LIKE N'$fixtureTag.%';
DELETE FROM dbo.Usuario WHERE correo LIKE N'$fixtureTag.%';
COMMIT TRANSACTION;
SELECT CONCAT('CLEANUP|', (SELECT COUNT(*) FROM dbo.Grupo WHERE nombre = N'$fixtureTag'), '|', (SELECT COUNT(*) FROM dbo.Usuario WHERE correo LIKE N'$fixtureTag.%'));
"@

function Start-SqlWorker {
    param ([string]$Name, [string]$Sql)
    $local = Join-Path $localDir "$Name.sql"
    Set-Content -Path $local -Value $Sql -Encoding utf8
    $remote = "$remoteDir/$Name.sql"
    $null = & docker cp $local "${ContainerName}:$remote" 2>&1
    $null = & docker exec -u 0 $ContainerName chmod a+r $remote 2>&1
    $job = {
        param($cn, $pw, $file)
        $out = @(& docker exec $cn /opt/mssql-tools18/bin/sqlcmd -S localhost -d gestionasistenciadb -U sa -P $pw -C -I -b -h -1 -W -s '|' -w 65535 -i $file 2>&1 | ForEach-Object { "$_".Trim() })
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Lines = $out }
    }
    return Start-Job -ScriptBlock $job -ArgumentList $ContainerName, $Password, $remote
}

try {
    $res = Invoke-ContainerSql -Name 'conc_setup' -Sql $setupSql -AbortOnError
    $fx = @($res.Lines | Where-Object { $_ -like 'FIXTURE|*' })
    $tomas = @($res.Lines | Where-Object { $_ -like 'TOMA|*' } | ForEach-Object { $_.Split('|')[2] })
    if ($fx.Count -ne 1 -or $tomas.Count -ne 4) { throw "setup failed: $($res.Lines -join '; ')" }
    $teacherUser = $fx[0].Split('|')[2]

    # B2-TOM-10: dos pasadas concurrentes del job no cierran la misma toma dos veces
    $jobSql = "SET NOCOUNT ON; DECLARE @c UNIQUEIDENTIFIER = NEWID(); EXEC dbo.usp_cerrar_tomas_vencidas @idCorrelacion = @c;"
    $jobs = @((Start-SqlWorker -Name 'tom10_a' -Sql $jobSql), (Start-SqlWorker -Name 'tom10_b' -Sql $jobSql))
    $results = @(Receive-Job -Job $jobs -Wait -AutoRemoveJob)
    foreach ($r in $results) { if ($r.ExitCode -ne 0) { throw "worker failed: $($r.Lines -join '; ')" } }
    $closed = @($results | ForEach-Object { $_.Lines } | Where-Object { $_ -match '^[0-9A-Fa-f-]{36}\|' } | ForEach-Object { $_.Split('|')[0].ToLowerInvariant() })
    $mine = @($tomas[0..3] | ForEach-Object { $_.ToLowerInvariant() })
    $closedMine = @($closed | Where-Object { $_ -in $mine })
    if ($closedMine.Count -ne 4 -or @($closedMine | Select-Object -Unique).Count -ne 4) { throw "expected each of the 4 tomas closed exactly once; got $($closedMine -join ',')" }
    $check = Invoke-ContainerSql -Name 'tom10_check' -Sql @"
SET NOCOUNT ON;
SELECT CONCAT('TOM10|', (SELECT COUNT(*) FROM dbo.TomaAsistencia t INNER JOIN dbo.Sesion s ON s.id = t.sesion INNER JOIN dbo.Grupo g ON g.id = s.grupo WHERE g.nombre = N'$fixtureTag' AND t.fechaCierreUtc IS NULL),
    '|', (SELECT COUNT(*) FROM dbo.DetalleAsistencia da INNER JOIN dbo.TomaAsistencia t ON t.id = da.toma WHERE t.id IN ('$($tomas[0])', '$($tomas[1])', '$($tomas[2])', '$($tomas[3])')),
    '|', (SELECT COUNT(*) FROM (SELECT da.asistencia, da.toma FROM dbo.DetalleAsistencia da GROUP BY da.asistencia, da.toma HAVING COUNT(*) > 1) x));
"@ -AbortOnError
    if (@($check.Lines | Where-Object { $_ -eq 'TOM10|0|12|0' }).Count -ne 1) { throw "unexpected final state: $($check.Lines -join ';')" }
    Write-Output 'TEST_PASS:CULM001_B2_TOM_10_CIERRE_AUTOMATICO_CONCURRENTE'
}
catch { $failures += "CULM001_B2_TOM_10_CIERRE_AUTOMATICO_CONCURRENTE $($_.Exception.Message)" }

try {
    if (-not $tomas -or $tomas.Count -ne 4) { throw 'fixture not available' }
    $res = Invoke-ContainerSql -Name 'tom08_setup' -Sql @"
SET NOCOUNT ON;
DECLARE @t UNIQUEIDENTIFIER = NEWID();
INSERT INTO dbo.TomaAsistencia (id, sesion, numero, modo, estado, esImplicita, docenteApertura, fechaAperturaUtc, fechaCierreUtc, idCorrelacionApertura)
SELECT @t, t.sesion, 2, t.modo, (SELECT id FROM dbo.EstadoTomaAsistencia WHERE estaAbierta = 1), 0, t.docenteApertura, t.fechaAperturaUtc, NULL, NEWID()
FROM dbo.TomaAsistencia t WHERE t.id = '$($tomas[0])';
SELECT CONCAT('TOMA08|', CONVERT(VARCHAR(36), @t));
"@ -AbortOnError
    $toma08 = @($res.Lines | Where-Object { $_ -like 'TOMA08|*' } | ForEach-Object { $_.Split('|')[1] })
    if ($toma08.Count -ne 1) { throw "toma 08 setup failed: $($res.Lines -join '; ')" }
    # B2-TOM-08: cierre concurrente docente + job sobre la toma 1 => un solo cierre efectivo, sin SJC duplicados
    $docente = @"
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @c UNIQUEIDENTIFIER = NEWID();
BEGIN TRANSACTION;
EXEC dbo.usp_cerrar_toma_asistencia @idToma = '$($toma08[0])', @marcarAusentes = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = '$teacherUser';
WAITFOR DELAY '00:00:02';
COMMIT TRANSACTION;
"@
    $jobSql = "SET NOCOUNT ON; DECLARE @c UNIQUEIDENTIFIER = NEWID(); WAITFOR DELAY '00:00:00.500'; EXEC dbo.usp_cerrar_tomas_vencidas @idCorrelacion = @c;"
    $jobs = @((Start-SqlWorker -Name 'tom08_docente' -Sql $docente), (Start-SqlWorker -Name 'tom08_job' -Sql $jobSql))
    $results = @(Receive-Job -Job $jobs -Wait -AutoRemoveJob)
    foreach ($r in $results) { if ($r.ExitCode -ne 0) { throw "worker failed: $($r.Lines -join '; ')" } }
    $check = Invoke-ContainerSql -Name 'tom08_check' -Sql @"
SET NOCOUNT ON;
SELECT CONCAT('TOM08|', (SELECT COUNT(*) FROM dbo.TomaAsistencia t INNER JOIN dbo.EstadoTomaAsistencia e ON e.id = t.estado WHERE t.id = '$($toma08[0])' AND e.estaAbierta = 0 AND t.fechaCierreUtc IS NOT NULL AND t.idCorrelacionCierre IS NOT NULL),
    '|', (SELECT COUNT(*) FROM (SELECT asistencia FROM dbo.DetalleAsistencia WHERE toma = '$($toma08[0])' GROUP BY asistencia HAVING COUNT(*) > 1) x),
    '|', (SELECT COUNT(*) FROM dbo.DetalleAsistencia WHERE toma = '$($toma08[0])'),
    '|', (SELECT totalAusentesMarcados FROM dbo.TomaAsistencia WHERE id = '$($toma08[0])'));
"@ -AbortOnError
    $line = @($check.Lines | Where-Object { $_ -like 'TOM08|*' })
    if ($line.Count -ne 1) { throw "no state: $($check.Lines -join ';')" }
    $p = $line[0].Split('|')
    # El docente cierra sin marcar (ventana vencida) o el job cierra marcando 3 SJC; nunca ambos ni duplicados
    if ($p[1] -ne '1' -or $p[2] -ne '0' -or $p[3] -ne $p[4] -or ($p[3] -ne '0' -and $p[3] -ne '3')) { throw "unexpected final state $($line[0])" }
    $docTuple = @($results | ForEach-Object { $_.Lines } | Where-Object { $_ -match '\|DBCODE=TOM_0(09|11)\|' })
    if ($docTuple.Count -ne 1) { throw "docente tuple not found: $($results | ForEach-Object { $_.Lines })" }
    Write-Output 'TEST_PASS:CULM001_B2_TOM_08_CIERRE_CONCURRENTE'
}
catch { $failures += "CULM001_B2_TOM_08_CIERRE_CONCURRENTE $($_.Exception.Message)" }
finally {
    try {
        $cr = Invoke-ContainerSql -Name 'conc_cleanup' -Sql $cleanupSql -AbortOnError
        if (@($cr.Lines | Where-Object { $_ -eq 'CLEANUP|0|0' }).Count -ne 1) { throw "cleanup: $($cr.Lines -join '; ')" }
    }
    catch { $failures += "CULM001_B2 concurrency cleanup failed: $($_.Exception.Message)" }
}

$null = & docker exec -u 0 $ContainerName rm -rf $remoteDir 2>&1
Remove-Item -Recurse -Force -Path $localDir -ErrorAction SilentlyContinue
foreach ($f in $failures) { Write-Output "TEST FAILED: $f" }
if ($failures.Count -gt 0) { exit 1 }
exit 0
