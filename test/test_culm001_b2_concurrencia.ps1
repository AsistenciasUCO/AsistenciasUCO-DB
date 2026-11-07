param (
    [string]$ContainerName = 'sqlserver',
    [string]$Password = $env:MSSQL_SA_PASSWORD,
    [int]$Grupos = 5,
    [int]$EstudiantesPorGrupo = 40
)

# CULM-001 B.2 (CONTRACT §2.8.3 NB-4, §2.16.2 B2-CON-01): 5 grupos x 40 estudiantes registrando por token a la vez.
#   * 200 conexiones sqlcmd independientes lanzadas en paralelo dentro del contenedor (una por estudiante) que esperan una
#     misma hora de inicio (WAITFOR TIME) y ejecutan usp_registrar_asistencia_por_token con el hash del token de su toma.
#   * Esperado: 200 detalles AN exactos (uno por estudiante y toma), 0 duplicados, 0 errores 1205 (deadlock), 0 timeouts;
#     una segunda ronda completa: 0 detalles nuevos (AQR_008). Se registran la duracion total y p50/p95/maximo por grupo.
#   * Fixture propio CULMB2C_ confirmado (las conexiones deben verlo) y limpieza al final.
# Se ejecuta solo bajo demanda: test_summary.ps1 -Concurrencia (infra.ps1 db-test -Concurrencia).
# Salida: TEST_PASS:CULM001_B2_CON_01_5X40 o TEST FAILED: ...

$ErrorActionPreference = 'Stop'
if (-not $Password) { throw 'SQL password is required for test_culm001_b2_concurrencia.ps1.' }

$tag = [guid]::NewGuid().ToString('N').Substring(0, 10)
$fixtureTag = "CULMB2C_$tag"
$remoteDir = "/tmp/culm001_b2c_$tag"
$localDir = Join-Path ([System.IO.Path]::GetTempPath()) "culm001_b2c_$tag"
New-Item -ItemType Directory -Force -Path $localDir | Out-Null
$null = & docker exec -u 0 $ContainerName mkdir -p $remoteDir 2>&1
$failures = @()

function Invoke-ContainerSql {
    param ([string]$Name, [string]$Sql)
    $local = Join-Path $localDir "$Name.sql"
    Set-Content -Path $local -Value $Sql -Encoding utf8
    $remote = "$remoteDir/$Name.sql"
    $null = & docker cp $local "${ContainerName}:$remote" 2>&1
    $null = & docker exec -u 0 $ContainerName chmod a+r $remote 2>&1
    $out = @(& docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -d gestionasistenciadb -U sa -P $Password -C -I -b -h -1 -W -s '|' -w 65535 -t 600 -i $remote 2>&1 | ForEach-Object { "$_".Trim() })
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Lines = $out }
}

function Get-Percentile {
    param ([double[]]$Values, [double]$P)
    $sorted = @($Values | Sort-Object)
    if ($sorted.Count -eq 0) { return 0 }
    $rank = [math]::Ceiling($P / 100.0 * $sorted.Count) - 1
    if ($rank -lt 0) { $rank = 0 }
    return $sorted[[int]$rank]
}

$setupSql = @"
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @idAsig UNIQUEIDENTIFIER = (SELECT TOP 1 a.id FROM dbo.uv_asignatura a WHERE a.estaActivaAsignatura = 1 ORDER BY a.id);
DECLARE @idInst UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion ORDER BY id);
DECLARE @estadoA UNIQUEIDENTIFIER = (SELECT id FROM dbo.uv_estado_estudiante_grupo WHERE codigo = 'A');
DECLARE @modoQr UNIQUEIDENTIFIER = (SELECT id FROM dbo.ModoTomaAsistencia WHERE usaCodigoQr = 1);
DECLARE @abierta UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoTomaAsistencia WHERE estaAbierta = 1);
DECLARE @uD UNIQUEIDENTIFIER = NEWID(), @d UNIQUEIDENTIFIER = NEWID(), @per UNIQUEIDENTIFIER = NEWID();
DECLARE @hoy DATE = CAST(SYSUTCDATETIME() AS DATE);
DECLARE @g TABLE (n INT, id UNIQUEIDENTIFIER, s UNIQUEIDENTIFIER, t UNIQUEIDENTIFIER);
INSERT INTO @g SELECT v.n, NEWID(), NEWID(), NEWID() FROM (SELECT TOP ($Grupos) n = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) FROM sys.all_objects) v;
DECLARE @e TABLE (g INT, n INT, u UNIQUEIDENTIFIER, e UNIQUEIDENTIFIER);
INSERT INTO @e SELECT g.n, v.n, NEWID(), NEWID() FROM @g g CROSS JOIN (SELECT TOP ($EstudiantesPorGrupo) n = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) FROM sys.all_objects) v;
BEGIN TRANSACTION;
INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
VALUES (@uD, @tipoCC, 960000000 + ABS(CHECKSUM(NEWID()) % 999999), N'Carga', N'CulmB', N'Doc', N'B2', N'$fixtureTag.d@test.local', 1, 1, N'HashBackend_CULMB2');
INSERT INTO dbo.Docente (id, usuario) VALUES (@d, @uD);
INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
SELECT u, @tipoCC, 961000000 + g * 100000 + n * 100 + ABS(CHECKSUM(NEWID()) % 99), CONCAT(N'Carga', g, N'-', n), N'CulmB', N'Est', N'B2',
       CONCAT(N'$fixtureTag.g', g, N'e', n, N'@test.local'), 1, 1, N'HashBackend_CULMB2' FROM @e;
INSERT INTO dbo.Estudiante (id, usuario) SELECT e, u FROM @e;
INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
VALUES (@per, @idInst, N'$fixtureTag', 3600000 + ABS(CHECKSUM(NEWID()) % 300000), DATEADD(DAY, -30, @hoy), DATEADD(DAY, 30, @hoy), YEAR(@hoy));
INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
    cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
SELECT id, @idAsig, @per, 950000 + n * 1000 + ABS(CHECKSUM(NEWID()) % 999), CONCAT(N'$fixtureTag G', n), $EstudiantesPorGrupo + 10, 0, 0, 0, @d FROM @g;
INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo) SELECT NEWID(), @estadoA, e.e, g.id FROM @e e INNER JOIN @g g ON g.n = e.g;
INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
SELECT s, CONCAT(N'$fixtureTag S', n), 1, CONCAT(N'CB2X', n), 1, id, DATEADD(MINUTE, -30, SYSUTCDATETIME()), DATEADD(MINUTE, 90, SYSUTCDATETIME()), N'UTC_V2' FROM @g;
INSERT INTO dbo.TomaAsistencia (id, sesion, numero, modo, estado, esImplicita, docenteApertura, fechaAperturaUtc, fechaCierreUtc, idCorrelacionApertura)
SELECT t, s, 1, @modoQr, @abierta, 0, @d, DATEADD(MINUTE, -25, SYSUTCDATETIME()), NULL, NEWID() FROM @g;
INSERT INTO dbo.TokenAsistenciaToma (id, toma, docenteEmisor, tokenHash, pin, fechaEmisionUtc, fechaRotacionUtc, fechaExpiracionUtc, idCorrelacionEmision)
SELECT NEWID(), t, @d, HASHBYTES('SHA2_256', CONCAT(N'$fixtureTag-token-', n)), RIGHT(CONCAT(N'00000', 800000 + ABS(CHECKSUM(NEWID()) % 99000) + n), 6),
       SYSUTCDATETIME(), SYSUTCDATETIME(), DATEADD(MINUTE, 120, SYSUTCDATETIME()), NEWID() FROM @g;
COMMIT TRANSACTION;
SELECT CONCAT('W|', e.g, '|', CONVERT(VARCHAR(66), HASHBYTES('SHA2_256', CONCAT(N'$fixtureTag-token-', e.g)), 1), '|', CONVERT(VARCHAR(36), e.u))
FROM @e e ORDER BY e.g, e.n;
SELECT CONCAT('START|', CONVERT(VARCHAR(8), DATEADD(SECOND, 12, GETDATE()), 108));
"@

$cleanupSql = @"
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @g TABLE (id UNIQUEIDENTIFIER);
INSERT INTO @g SELECT id FROM dbo.Grupo WHERE nombre LIKE N'$fixtureTag G%';
BEGIN TRANSACTION;
DELETE da FROM dbo.DetalleAsistencia da INNER JOIN dbo.Asistencia a ON a.id = da.asistencia INNER JOIN dbo.Sesion s ON s.id = a.sesion WHERE s.grupo IN (SELECT id FROM @g);
DELETE tk FROM dbo.TokenAsistenciaToma tk INNER JOIN dbo.TomaAsistencia t ON t.id = tk.toma INNER JOIN dbo.Sesion s ON s.id = t.sesion WHERE s.grupo IN (SELECT id FROM @g);
DELETE t FROM dbo.TomaAsistencia t INNER JOIN dbo.Sesion s ON s.id = t.sesion WHERE s.grupo IN (SELECT id FROM @g);
DELETE a FROM dbo.Asistencia a INNER JOIN dbo.Sesion s ON s.id = a.sesion WHERE s.grupo IN (SELECT id FROM @g);
DELETE FROM dbo.Sesion WHERE grupo IN (SELECT id FROM @g);
DELETE FROM dbo.EstudianteGrupo WHERE grupo IN (SELECT id FROM @g);
DELETE FROM dbo.Grupo WHERE id IN (SELECT id FROM @g);
DELETE FROM dbo.PeriodoAcademico WHERE nombre = N'$fixtureTag';
DELETE e FROM dbo.Estudiante e INNER JOIN dbo.Usuario u ON u.id = e.usuario WHERE u.correo LIKE N'$fixtureTag.%';
DELETE d FROM dbo.Docente d INNER JOIN dbo.Usuario u ON u.id = d.usuario WHERE u.correo LIKE N'$fixtureTag.%';
DELETE FROM dbo.Usuario WHERE correo LIKE N'$fixtureTag.%';
COMMIT TRANSACTION;
SELECT CONCAT('CLEANUP|', (SELECT COUNT(*) FROM dbo.Grupo WHERE nombre LIKE N'$fixtureTag G%'), '|', (SELECT COUNT(*) FROM dbo.Usuario WHERE correo LIKE N'$fixtureTag.%'));
"@

# Script de cada conexion: espera la hora comun, mide el tiempo de la llamada e imprime el codigo devuelto
$workerSql = @'
SET NOCOUNT ON;
WAITFOR TIME '$(START)';
DECLARE @t0 DATETIME2(7) = SYSUTCDATETIME();
DECLARE @r TABLE (idCorrelacion UNIQUEIDENTIFIER, mu NVARCHAR(4000), mt NVARCHAR(4000), estado BIT, idToma UNIQUEIDENTIFIER, idSesion UNIQUEIDENTIFIER,
    idGrupo UNIQUEIDENTIFIER, nombreAsignatura NVARCHAR(200), nombreGrupo NVARCHAR(300), numeroSesion INT, numeroToma SMALLINT, yaRegistrado BIT, fechaRegistroUtc DATETIME2(0));
DECLARE @c UNIQUEIDENTIFIER = NEWID();
BEGIN TRY
    EXEC dbo.usp_registrar_asistencia_por_token @tokenHash = $(H), @pin = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = '$(U)';
    PRINT CONCAT('RES|$(G)|', DATEDIFF(MICROSECOND, @t0, SYSUTCDATETIME()));
END TRY
BEGIN CATCH
    PRINT CONCAT('ERR|$(G)|', ERROR_NUMBER(), '|', ERROR_MESSAGE());
END CATCH;
'@

$runner = @'
#!/bin/bash
# $1 = manifiesto (G H U por linea), $2 = hora de inicio, $3 = directorio de salida, $4 = ronda
i=0
while read -r G H U; do
  i=$((i+1))
  /opt/mssql-tools18/bin/sqlcmd -S localhost -d gestionasistenciadb -U sa -P "$SQLPW" -C -I -h -1 -W -s '|' -w 65535 -t 30 -l 30 \
    -v START="$2" H="$H" U="$U" G="$G" -i "$3/worker.sql" < /dev/null > "$3/out_$4_$i.txt" 2>&1 &
done < "$1"
wait
echo DONE
'@

try {
    $res = Invoke-ContainerSql -Name 'con_setup' -Sql $setupSql
    if ($res.ExitCode -ne 0) { throw "setup failed: $($res.Lines -join '; ')" }
    $workers = @($res.Lines | Where-Object { $_ -like 'W|*' })
    $expected = $Grupos * $EstudiantesPorGrupo
    if ($workers.Count -ne $expected) { throw "setup produced $($workers.Count) workers; expected $expected" }
    $manifest = Join-Path $localDir 'manifest.txt'
    Set-Content -Path $manifest -Value ($workers | ForEach-Object { $p = $_.Split('|'); "$($p[1]) $($p[2]) $($p[3])" }) -Encoding ascii
    $workerLocal = Join-Path $localDir 'worker.sql'
    Set-Content -Path $workerLocal -Value $workerSql -Encoding utf8
    $runnerLocal = Join-Path $localDir 'run.sh'
    [System.IO.File]::WriteAllText($runnerLocal, ($runner -replace "`r`n", "`n"))
    foreach ($f in @('manifest.txt', 'worker.sql', 'run.sh')) {
        $null = & docker cp (Join-Path $localDir $f) "${ContainerName}:$remoteDir/$f" 2>&1
    }
    $null = & docker exec -u 0 $ContainerName bash -c "sed -i 's/\r$//' $remoteDir/manifest.txt && chmod -R a+rwX $remoteDir" 2>&1

    $rounds = @{}
    foreach ($round in 1, 2) {
        $startRes = Invoke-ContainerSql -Name "con_start_$round" -Sql "SET NOCOUNT ON; SELECT CONCAT('START|', CONVERT(VARCHAR(8), DATEADD(SECOND, 8, GETDATE()), 108));"
        $start = (@($startRes.Lines | Where-Object { $_ -like 'START|*' })[0]).Substring(6)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $out = @(& docker exec -e "SQLPW=$Password" $ContainerName bash "$remoteDir/run.sh" "$remoteDir/manifest.txt" $start $remoteDir $round 2>&1)
        $sw.Stop()
        if (($out -join '') -notmatch 'DONE') { throw "round $round runner failed: $($out -join '; ')" }
        $lines = @(& docker exec $ContainerName bash -c "cat $remoteDir/out_${round}_*.txt" 2>&1 | ForEach-Object { "$_".Trim() })
        $rounds[$round] = [pscustomobject]@{ Lines = $lines; WallMs = $sw.ElapsedMilliseconds }
    }

    $r1 = $rounds[1].Lines; $r2 = $rounds[2].Lines
    $ok1 = @($r1 | Where-Object { $_ -match '\|DBCODE=AQR_009\|' }).Count
    $ok2 = @($r2 | Where-Object { $_ -match '\|DBCODE=AQR_008\|' }).Count
    $errs = @(($r1 + $r2) | Where-Object { $_ -like 'ERR|*' -or $_ -match 'Msg \d+' -or $_ -match '(?i)deadlock|1205|timeout expired|Login timeout' })
    $times = @($r1 | Where-Object { $_ -like 'RES|*' } | ForEach-Object { $p = $_.Split('|'); [pscustomobject]@{ G = [int]$p[1]; Ms = [double]$p[2] / 1000.0 } })
    $check = Invoke-ContainerSql -Name 'con_check' -Sql @"
SET NOCOUNT ON;
SELECT CONCAT('CHECK|',
    (SELECT COUNT(*) FROM dbo.DetalleAsistencia da INNER JOIN dbo.TomaAsistencia t ON t.id = da.toma INNER JOIN dbo.Sesion s ON s.id = t.sesion
     INNER JOIN dbo.Grupo g ON g.id = s.grupo INNER JOIN dbo.RazonCausa rc ON rc.id = da.razonCausa
     WHERE g.nombre LIKE N'$fixtureTag G%' AND rc.codigo = N'AN' AND da.asistio = 1 AND da.registradoPorEstudiante = 1), '|',
    (SELECT COUNT(*) FROM (SELECT da.asistencia, da.toma FROM dbo.DetalleAsistencia da INNER JOIN dbo.TomaAsistencia t ON t.id = da.toma INNER JOIN dbo.Sesion s ON s.id = t.sesion
     INNER JOIN dbo.Grupo g ON g.id = s.grupo WHERE g.nombre LIKE N'$fixtureTag G%' GROUP BY da.asistencia, da.toma HAVING COUNT(*) > 1) x), '|',
    (SELECT COUNT(*) FROM (SELECT a.estudianteGrupo, a.sesion FROM dbo.Asistencia a INNER JOIN dbo.Sesion s ON s.id = a.sesion
     INNER JOIN dbo.Grupo g ON g.id = s.grupo WHERE g.nombre LIKE N'$fixtureTag G%' GROUP BY a.estudianteGrupo, a.sesion HAVING COUNT(*) > 1) x), '|',
    (SELECT COUNT(*) FROM dbo.DetalleAsistencia da INNER JOIN dbo.TomaAsistencia t ON t.id = da.toma INNER JOIN dbo.Sesion s ON s.id = t.sesion
     INNER JOIN dbo.Grupo g ON g.id = s.grupo WHERE g.nombre LIKE N'$fixtureTag G%'));
"@
    $state = @($check.Lines | Where-Object { $_ -like 'CHECK|*' })
    Write-Host "CULM001_B2_CON_01 round1_ok=$ok1 round2_idempotent=$ok2 errors=$($errs.Count) wall_ms_round1=$($rounds[1].WallMs) wall_ms_round2=$($rounds[2].WallMs) state=$($state -join ';')"
    foreach ($grp in @($times | Group-Object G | Sort-Object { [int]$_.Name })) {
        $v = @($grp.Group | ForEach-Object { $_.Ms })
        Write-Host ("CULM001_B2_CON_01 grupo={0} n={1} p50_ms={2:N1} p95_ms={3:N1} max_ms={4:N1}" -f $grp.Name, $v.Count, (Get-Percentile $v 50), (Get-Percentile $v 95), (($v | Measure-Object -Maximum).Maximum))
    }
    $all = @($times | ForEach-Object { $_.Ms })
    Write-Host ("CULM001_B2_CON_01 total n={0} p50_ms={1:N1} p95_ms={2:N1} max_ms={3:N1}" -f $all.Count, (Get-Percentile $all 50), (Get-Percentile $all 95), (($all | Measure-Object -Maximum).Maximum))
    if ($errs.Count -gt 0) { throw "errors: $(($errs | Select-Object -First 5) -join ' / ')" }
    if ($ok1 -ne $expected -or $ok2 -ne $expected -or $times.Count -ne $expected) { throw "round1 AQR_009=$ok1 round2 AQR_008=$ok2 timings=$($times.Count) (expected $expected)" }
    if ($state.Count -ne 1 -or $state[0] -ne "CHECK|$expected|0|0|$expected") { throw "unexpected final state $($state -join ';')" }
    Write-Host 'TEST_PASS:CULM001_B2_CON_01_5X40'
}
catch { $failures += "CULM001_B2_CON_01_5X40 $($_.Exception.Message)" }
finally {
    try {
        $cr = Invoke-ContainerSql -Name 'con_cleanup' -Sql $cleanupSql
        if (@($cr.Lines | Where-Object { $_ -eq 'CLEANUP|0|0' }).Count -ne 1) { throw "cleanup: $($cr.Lines -join '; ')" }
    }
    catch { $failures += "CULM001_B2_CON_01 cleanup failed: $($_.Exception.Message)" }
    $null = & docker exec -u 0 $ContainerName rm -rf $remoteDir 2>&1
    Remove-Item -Recurse -Force -Path $localDir -ErrorAction SilentlyContinue
}
foreach ($f in $failures) { Write-Host "TEST FAILED: $f" }
if ($failures.Count -gt 0) { exit 1 }
exit 0
