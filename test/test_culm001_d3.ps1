param (
    [string]$ContainerName = 'sqlserver',
    [string]$Password = $env:MSSQL_SA_PASSWORD
)

# CULM-001 D.3 y D.6 (CONTRACT v2 §4.2 D3-09 y D3-16, §7.3): casos que no caben en un archivo T-SQL de la suite.
#   * CULM001_D3_09_CONCURRENCIA: dos conexiones editan el mismo parametro con la misma fechaModificacionEsperada; la primera
#     confirma (PRM_001) y la segunda, que esperaba el bloqueo, recibe PRM_008. Deja el parametro como estaba.
#   * CULM001_D3_16_MIG_UP_DOWN_UP: migracion 22 up -> down -> up dentro de una transaccion que se revierte; el down exporta
#     CambioParametro a zz_archivo_CambioParametro_culm001_d3 y el up siguiente restaura el historial.
#   * CULM001_D6_MIG_01_UP_DOWN_UP: migracion 25 up -> down -> up (firma de usp_consultar_auditoria_eventos_paginado, AUD_001,
#     AUD_002 y AUDITORIA/PREFIJO_RUTA_ADMINISTRACION) en una transaccion que se revierte.
# Salida: TEST_PASS:<ID> por caso aprobado y TEST FAILED: <ID> <motivo> por caso fallido.

$ErrorActionPreference = 'Stop'
if (-not $Password) { throw 'SQL password is required for test_culm001_d3.ps1.' }

$tag = [guid]::NewGuid().ToString('N').Substring(0, 12)
$remoteDir = "/tmp/culm001_d3_$tag"
$localDir = Join-Path ([System.IO.Path]::GetTempPath()) "culm001_d3_$tag"
New-Item -ItemType Directory -Force -Path $localDir | Out-Null
$null = & docker exec -u 0 $ContainerName mkdir -p $remoteDir 2>&1
$failures = @()

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

# ---------------------------------------------------------------------------------------------------------------
# D3-09: dos ediciones concurrentes con la misma version => una PRM_001 y la otra PRM_008
# ---------------------------------------------------------------------------------------------------------------
$idMarca = 'D3090000-0000-4000-8000-000000000009'
try {
    $setup = Invoke-ContainerSql -Name 'con_setup' -AbortOnError -Sql @"
SET NOCOUNT ON;
SELECT CONCAT('PARAM|', CONVERT(VARCHAR(36), p.id), '|', p.valor, '|', CONVERT(VARCHAR(23), p.fechaModificacion, 121), '|', CONVERT(VARCHAR(36), (SELECT TOP 1 a.usuario FROM dbo.Administrador a JOIN dbo.uv_usuario u ON u.id = a.usuario WHERE u.estaActivoUsuario = 1 ORDER BY a.id)))
FROM dbo.CatalogoParametro p WHERE p.grupo = 'ASISTENCIA' AND p.clave = 'MARGEN_RETARDO_MINUTOS';
"@
    $row = @($setup.Lines | Where-Object { $_ -like 'PARAM|*' })
    if ($row.Count -ne 1) { throw "fixture missing: $($setup.Lines -join '; ')" }
    $p = $row[0].Split('|'); $idParam = $p[1]; $valorOriginal = $p[2]; $fechaOriginal = $p[3]; $admin = $p[4]
    $valorA = if ($valorOriginal -eq '31') { '32' } else { '31' }
    $valorB = if ($valorOriginal -eq '33') { '34' } else { '33' }
    function New-Worker { param($Valor, $Motivo, $Espera)
@"
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @r TABLE (idCorrelacion UNIQUEIDENTIFIER, mu NVARCHAR(4000), mt NVARCHAR(4000), estado BIT, idParametro UNIQUEIDENTIFIER, grupo VARCHAR(100), clave VARCHAR(100),
    valorAnterior NVARCHAR(4000), valorNuevo NVARCHAR(4000), fechaModificacion DATETIME);
DECLARE @c UNIQUEIDENTIFIER = NEWID();
$Espera
BEGIN TRANSACTION;
INSERT INTO @r EXEC dbo.usp_actualizar_parametro @idParametro = '$idParam', @valor = N'$Valor', @fechaModificacionEsperada = '$fechaOriginal',
    @motivo = N'$Motivo', @idCorrelacion = @c, @idUsuarioEjecutor = '$admin';
WAITFOR DELAY '00:00:03';
COMMIT TRANSACTION;
SELECT CONCAT('RES|', estado, '|', LEFT(mt, 20)) FROM @r;
"@ }
    $w1 = Join-Path $localDir 'con_w1.sql'; $w2 = Join-Path $localDir 'con_w2.sql'
    Set-Content -Path $w1 -Value (New-Worker -Valor $valorA -Motivo 'D3-09 escritor uno' -Espera '') -Encoding utf8
    Set-Content -Path $w2 -Value (New-Worker -Valor $valorB -Motivo 'D3-09 escritor dos' -Espera "WAITFOR DELAY '00:00:01';") -Encoding utf8
    foreach ($f in 'con_w1.sql', 'con_w2.sql') {
        $null = & docker cp (Join-Path $localDir $f) "${ContainerName}:$remoteDir/$f" 2>&1
        $null = & docker exec -u 0 $ContainerName chmod a+r "$remoteDir/$f" 2>&1
    }
    $job = {
        param($cn, $pw, $file)
        $out = @(& docker exec $cn /opt/mssql-tools18/bin/sqlcmd -S localhost -d gestionasistenciadb -U sa -P $pw -C -I -b -h -1 -W -s '|' -w 65535 -t 60 -i $file 2>&1 | ForEach-Object { "$_".Trim() })
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Lines = $out }
    }
    $jobs = @((Start-Job -ScriptBlock $job -ArgumentList $ContainerName, $Password, "$remoteDir/con_w1.sql"),
              (Start-Job -ScriptBlock $job -ArgumentList $ContainerName, $Password, "$remoteDir/con_w2.sql"))
    $results = @(Receive-Job -Job $jobs -Wait -AutoRemoveJob)
    $lines = @($results | ForEach-Object { $_.Lines })
    $okCount = @($lines | Where-Object { $_ -like 'RES|1|DBCODE=PRM_001*' }).Count
    $conflictCount = @($lines | Where-Object { $_ -like 'RES|0|DBCODE=PRM_008*' }).Count
    $final = Invoke-ContainerSql -Name 'con_final' -AbortOnError -Sql "SET NOCOUNT ON; SELECT CONCAT('FINAL|', valor, '|', (SELECT COUNT(*) FROM dbo.CambioParametro WHERE parametro = '$idParam' AND motivo LIKE N'D3-09 %')) FROM dbo.CatalogoParametro WHERE id = '$idParam';"
    $finalRow = @($final.Lines | Where-Object { $_ -like 'FINAL|*' })
    if ($okCount -ne 1 -or $conflictCount -ne 1) { throw "expected one PRM_001 and one PRM_008, got $($lines -join ' / ')" }
    if ($finalRow.Count -ne 1 -or $finalRow[0] -notmatch '^FINAL\|(31|32|33|34)\|1$') { throw "unexpected final state $($finalRow -join ';')" }
    Write-Host 'TEST_PASS:CULM001_D3_09_CONCURRENCIA'
}
catch { $failures += "CULM001_D3_09_CONCURRENCIA $($_.Exception.Message)" }
finally {
    try {
        $null = Invoke-ContainerSql -Name 'con_cleanup' -AbortOnError -Sql @"
SET NOCOUNT ON;
DELETE FROM dbo.CambioParametro WHERE motivo LIKE N'D3-09 %';
UPDATE dbo.CatalogoParametro SET valor = N'$valorOriginal', fechaModificacion = '$fechaOriginal' WHERE grupo = 'ASISTENCIA' AND clave = 'MARGEN_RETARDO_MINUTOS';
"@
    }
    catch { $failures += 'CULM001_D3_09_CONCURRENCIA cleanup failed' }
}

# ---------------------------------------------------------------------------------------------------------------
# D3-16 y D6-MIG: migraciones 22 y 25 up -> down -> up dentro de una transaccion revertida (sqlcmd -b)
# ---------------------------------------------------------------------------------------------------------------
$migDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'migrations'
$names = @('22_culm001_d3_parametros_editables_up.sql', '22_culm001_d3_parametros_editables_down.sql', '25_culm001_d6_auditoria_admin_up.sql', '25_culm001_d6_auditoria_admin_down.sql')
foreach ($n in $names) {
    $f = Join-Path $migDir $n
    if (-not (Test-Path $f)) { $failures += "MIGRATION_FILE_MISSING $n"; continue }
    $null = & docker cp $f "${ContainerName}:$remoteDir/$n" 2>&1
}
$null = & docker exec -u 0 $ContainerName chmod -R a+r $remoteDir 2>&1

$checkUp22 = @'
IF OBJECT_ID(N'dbo.CatalogoParametroEdicion', N'U') IS NULL OR OBJECT_ID(N'dbo.CambioParametro', N'U') IS NULL
   OR OBJECT_ID(N'dbo.uv_parametro_edicion', N'V') IS NULL OR OBJECT_ID(N'dbo.uv_cambio_parametro', N'V') IS NULL
   OR OBJECT_ID(N'dbo.ufn_validar_valor_parametro', N'FN') IS NULL
   OR OBJECT_ID(N'dbo.usp_actualizar_parametro', N'P') IS NULL OR OBJECT_ID(N'dbo.usp_consultar_parametros_paginado', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_consultar_cambios_parametro_paginado', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FK_CambioParametro_CatalogoParametro', N'F') IS NULL OR OBJECT_ID(N'dbo.FK_CatalogoParametroEdicion_CatalogoParametro', N'F') IS NULL
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'PRM_001')
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo = 'PARAMETROS' AND clave = 'GRUPOS_NO_EDITABLES')
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoParametroEdicion WHERE esEditable = 1)
    THROW 57700, 'MIG_CHECK_UP22_FAILED', 1;
'@
$checkDown22 = @'
IF OBJECT_ID(N'dbo.CatalogoParametroEdicion', N'U') IS NOT NULL OR OBJECT_ID(N'dbo.CambioParametro', N'U') IS NOT NULL
   OR OBJECT_ID(N'dbo.uv_parametro_edicion', N'V') IS NOT NULL OR OBJECT_ID(N'dbo.uv_cambio_parametro', N'V') IS NOT NULL
   OR OBJECT_ID(N'dbo.ufn_validar_valor_parametro', N'FN') IS NOT NULL
   OR OBJECT_ID(N'dbo.usp_actualizar_parametro', N'P') IS NOT NULL OR OBJECT_ID(N'dbo.usp_consultar_parametros_paginado', N'P') IS NOT NULL
   OR OBJECT_ID(N'dbo.usp_consultar_cambios_parametro_paginado', N'P') IS NOT NULL
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo LIKE 'PRM[_]%')
   OR EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo = 'PARAMETROS')
   OR OBJECT_ID(N'dbo.zz_archivo_CambioParametro_culm001_d3', N'U') IS NULL
   OR (SELECT COUNT(*) FROM dbo.zz_archivo_CambioParametro_culm001_d3 WHERE id = 'D3160000-0000-4000-8000-000000000016') <> 1
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo = 'ASISTENCIA' AND clave = 'TOLERANCIA_MINUTOS')
    THROW 57701, 'MIG_CHECK_DOWN22_FAILED', 1;
'@
$checkRestored22 = @'
IF (SELECT COUNT(*) FROM dbo.CambioParametro WHERE id = 'D3160000-0000-4000-8000-000000000016' AND motivo = N'Marca de migracion D3-16') <> 1
   OR OBJECT_ID(N'dbo.zz_archivo_CambioParametro_culm001_d3', N'U') IS NOT NULL
    THROW 57702, 'MIG_CHECK_HISTORIAL_NOT_RESTORED', 1;
'@
$wrapper22 = @"
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT OFF;
GO
BEGIN TRANSACTION;
GO
:r $remoteDir/22_culm001_d3_parametros_editables_up.sql
GO
$checkUp22
INSERT INTO dbo.CambioParametro (id, parametro, valorAnterior, valorNuevo, motivo, idUsuarioEjecutor, idCorrelacion, fechaCambioUtc)
SELECT 'D3160000-0000-4000-8000-000000000016', p.id, N'1', N'2', N'Marca de migracion D3-16',
       (SELECT TOP 1 a.usuario FROM dbo.Administrador a ORDER BY a.id), NEWID(), SYSUTCDATETIME()
FROM dbo.CatalogoParametro p WHERE p.grupo = 'ASISTENCIA' AND p.clave = 'TOLERANCIA_MINUTOS';
PRINT 'MIG22_UP1_OK';
GO
:r $remoteDir/22_culm001_d3_parametros_editables_down.sql
GO
$checkDown22
PRINT 'MIG22_DOWN_OK';
GO
:r $remoteDir/22_culm001_d3_parametros_editables_down.sql
GO
PRINT 'MIG22_DOWN2_OK';
GO
:r $remoteDir/22_culm001_d3_parametros_editables_up.sql
GO
$checkUp22
$checkRestored22
PRINT 'MIG22_UP2_OK';
GO
:r $remoteDir/22_culm001_d3_parametros_editables_up.sql
GO
$checkUp22
$checkRestored22
PRINT 'MIG22_UP3_OK';
GO
ROLLBACK TRANSACTION;
GO
IF @@TRANCOUNT <> 0 THROW 57703, 'MIG_TRANCOUNT', 1;
IF OBJECT_ID(N'dbo.usp_actualizar_parametro', N'P') IS NULL OR OBJECT_ID(N'dbo.CambioParametro', N'U') IS NULL
   OR EXISTS (SELECT 1 FROM dbo.CambioParametro WHERE id = 'D3160000-0000-4000-8000-000000000016')
    THROW 57704, 'MIG_ROLLBACK_DID_NOT_RESTORE', 1;
PRINT 'MIG22_RESTORED_OK';
GO
"@

$checkUp25 = @'
IF NOT EXISTS (SELECT 1 FROM sys.parameters WHERE object_id = OBJECT_ID(N'dbo.usp_consultar_auditoria_eventos_paginado') AND name = N'@idCorrelacionEvento')
   OR NOT EXISTS (SELECT 1 FROM sys.parameters WHERE object_id = OBJECT_ID(N'dbo.usp_consultar_auditoria_eventos_paginado') AND name = N'@soloAdministracion')
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'AUD_001') OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'AUD_002')
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeTecnico WHERE codigo = 'AUD_001') OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeTecnico WHERE codigo = 'AUD_002')
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo = 'AUDITORIA' AND clave = 'PREFIJO_RUTA_ADMINISTRACION')
    THROW 57710, 'MIG_CHECK_UP25_FAILED', 1;
'@
$checkDown25 = @'
IF EXISTS (SELECT 1 FROM sys.parameters WHERE object_id = OBJECT_ID(N'dbo.usp_consultar_auditoria_eventos_paginado') AND name IN (N'@idCorrelacionEvento', N'@soloAdministracion'))
   OR OBJECT_ID(N'dbo.usp_consultar_auditoria_eventos_paginado', N'P') IS NULL
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('AUD_001', 'AUD_002')) OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('AUD_001', 'AUD_002'))
   OR EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo = 'AUDITORIA' AND clave = 'PREFIJO_RUTA_ADMINISTRACION')
    THROW 57711, 'MIG_CHECK_DOWN25_FAILED', 1;
'@
$wrapper25 = @"
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT OFF;
GO
BEGIN TRANSACTION;
GO
:r $remoteDir/25_culm001_d6_auditoria_admin_up.sql
GO
$checkUp25
PRINT 'MIG25_UP1_OK';
GO
:r $remoteDir/25_culm001_d6_auditoria_admin_down.sql
GO
$checkDown25
PRINT 'MIG25_DOWN_OK';
GO
:r $remoteDir/25_culm001_d6_auditoria_admin_down.sql
GO
PRINT 'MIG25_DOWN2_OK';
GO
:r $remoteDir/25_culm001_d6_auditoria_admin_up.sql
GO
$checkUp25
PRINT 'MIG25_UP2_OK';
GO
:r $remoteDir/25_culm001_d6_auditoria_admin_up.sql
GO
$checkUp25
PRINT 'MIG25_UP3_OK';
GO
ROLLBACK TRANSACTION;
GO
IF @@TRANCOUNT <> 0 THROW 57712, 'MIG_TRANCOUNT', 1;
IF NOT EXISTS (SELECT 1 FROM sys.parameters WHERE object_id = OBJECT_ID(N'dbo.usp_consultar_auditoria_eventos_paginado') AND name = N'@soloAdministracion')
    THROW 57713, 'MIG_ROLLBACK_DID_NOT_RESTORE', 1;
PRINT 'MIG25_RESTORED_OK';
GO
"@

foreach ($case in @(
        @{ Id = 'CULM001_D3_16_MIG_UP_DOWN_UP'; Name = 'mig22'; Sql = $wrapper22; Markers = @('MIG22_UP1_OK', 'MIG22_DOWN_OK', 'MIG22_DOWN2_OK', 'MIG22_UP2_OK', 'MIG22_UP3_OK', 'MIG22_RESTORED_OK'); Probe = 'usp_actualizar_parametro' },
        @{ Id = 'CULM001_D6_MIG_01_UP_DOWN_UP'; Name = 'mig25'; Sql = $wrapper25; Markers = @('MIG25_UP1_OK', 'MIG25_DOWN_OK', 'MIG25_DOWN2_OK', 'MIG25_UP2_OK', 'MIG25_UP3_OK', 'MIG25_RESTORED_OK'); Probe = 'usp_consultar_auditoria_eventos_paginado' })) {
    try {
        $res = Invoke-ContainerSql -Name $case.Name -Sql $case.Sql -AbortOnError
        $text = $res.Lines -join "`n"
        foreach ($marker in $case.Markers) { if ($text -notmatch $marker) { throw "missing $marker (exit $($res.ExitCode)): $text" } }
        if ($res.ExitCode -ne 0) { throw "sqlcmd exit $($res.ExitCode): $text" }
        Write-Host "TEST_PASS:$($case.Id)"
    }
    catch { $failures += "$($case.Id) $($_.Exception.Message)" }
    finally {
        try {
            $state = Invoke-ContainerSql -Name "$($case.Name)_state" -AbortOnError -Sql "SET NOCOUNT ON; SELECT CONCAT('MIGSTATE|', IIF(OBJECT_ID(N'dbo.$($case.Probe)', N'P') IS NULL, 0, 1), '|', @@TRANCOUNT);"
            if (@($state.Lines | Where-Object { $_ -eq 'MIGSTATE|1|0' }).Count -ne 1) { $failures += "$($case.Id) left the database without its objects: $($state.Lines -join ';')" }
        }
        catch { $failures += "$($case.Id) state check failed" }
    }
}

$null = & docker exec -u 0 $ContainerName rm -rf $remoteDir 2>&1
Remove-Item -Recurse -Force -Path $localDir -ErrorAction SilentlyContinue
foreach ($f in $failures) { Write-Host "TEST FAILED: $f" }
if ($failures.Count -gt 0) { exit 1 }
