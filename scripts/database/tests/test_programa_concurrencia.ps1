#Requires -Version 5.1
<#
.SYNOPSIS
  T-076-07 (HU076): dos altas simultaneas de programa con el MISMO coordinador libre.
  Exactamente una debe tener exito y la otra debe devolver PROG_005, con @@TRANCOUNT = 0 en ambas.

.DESCRIPTION
  La sesion A abre una transaccion externa, ejecuta el alta y espera 4 s antes de confirmar.
  La sesion B arranca 1 s despues e intenta el alta con el mismo coordinador: debe quedar bloqueada
  por el UPDLOCK/HOLDLOCK del SP hasta el commit de A y luego recibir PROG_005. Se mide el tiempo de B
  para demostrar que las dos sesiones SE SOLAPARON (no se ejecutaron en serie).
  Crea fixtures confirmados (decano, facultad, coordinador) y los elimina al final.
#>
param(
    [string]$ContainerName = 'sql_server_asistencias',
    [string]$Password = 'TuPasswordSeguro123',
    [string]$Database = 'gestionasistenciadb'
)
$ErrorActionPreference = 'Stop'

function Invoke-Sql([string]$Query) {
    $out = $Query | docker exec -i $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P $Password -C -d $Database -y 0 -b -h -1 2>&1
    if ($LASTEXITCODE -ne 0) { throw "sqlcmd fallo: $out" }
    return ($out | Out-String).Trim()
}

$sufijo = ([guid]::NewGuid().ToString('N')).Substring(0, 8)
$setup = @"
SET NOCOUNT ON;
DECLARE @inst UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion WHERE estaActivaInstitucion = 1);
DECLARE @tid UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoIdentificacion);
DECLARE @tipo UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_programa WHERE estaActivoTipoPrograma = 1);
DECLARE @ud UNIQUEIDENTIFIER = NEWID(), @uc UNIQUEIDENTIFIER = NEWID(), @d UNIQUEIDENTIFIER = NEWID(), @co UNIQUEIDENTIFIER = NEWID(), @f UNIQUEIDENTIFIER = NEWID();
INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
VALUES (@ud, @tid, 600000000 + ABS(CHECKSUM(NEWID()) % 9999999), N'QA', N'Conc', N'Dec', N'X', CONCAT(CONVERT(NVARCHAR(36), @ud), N'@qa.test'), 1, 1, N'x'),
       (@uc, @tid, 610000000 + ABS(CHECKSUM(NEWID()) % 9999999), N'QA', N'Conc', N'Coo', N'X', CONCAT(CONVERT(NVARCHAR(36), @uc), N'@qa.test'), 1, 1, N'x');
INSERT INTO dbo.Decano (id, usuario) VALUES (@d, @ud);
INSERT INTO dbo.Facultad (id, nombre, institucion, decano, estado) VALUES (@f, N'QA Conc $sufijo', @inst, @d, 1);
INSERT INTO dbo.Coordinador (id, usuario) VALUES (@co, @uc);
SELECT CONCAT(@ud, '|', @f, '|', @co, '|', @tipo, '|', @d, '|', @uc);
"@
$fx = (Invoke-Sql $setup).Split('|')
$uDec, $fac, $coord, $tipo, $dec, $uCoord = $fx
Write-Host "Fixtures: facultad=$fac coordinador=$coord"

function New-Call([string]$nombre, [string]$espera) {
@"
SET NOCOUNT ON;
DECLARE @t0 DATETIME2 = SYSUTCDATETIME();
CREATE TABLE #r (idCorrelacion UNIQUEIDENTIFIER, mu NVARCHAR(4000), mt NVARCHAR(4000), ok BIT);
BEGIN TRANSACTION;
INSERT INTO #r EXEC dbo.usp_crear_programa_academico @nombre = N'$nombre', @idTipoPrograma = '$tipo', @idCoordinador = '$coord',
    @idFacultad = '$fac', @idCorrelacion = NEWID(), @idUsuarioEjecutor = '$uDec';
$espera
COMMIT TRANSACTION;
SELECT CONCAT((SELECT ok FROM #r), '|', LEFT((SELECT mt FROM #r), 40), '|', DATEDIFF(MILLISECOND, @t0, SYSUTCDATETIME()), '|', @@TRANCOUNT);
"@
}

try {
    $jobA = Start-Job -ScriptBlock {
        param($c, $p, $d, $q)
        $q | docker exec -i $c /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P $p -C -d $d -y 0 -b -h -1 2>&1 | Out-String
    } -ArgumentList $ContainerName, $Password, $Database, (New-Call "QA Conc A $sufijo" "WAITFOR DELAY '00:00:04';")
    Start-Sleep -Seconds 1
    $jobB = Start-Job -ScriptBlock {
        param($c, $p, $d, $q)
        $q | docker exec -i $c /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P $p -C -d $d -y 0 -b -h -1 2>&1 | Out-String
    } -ArgumentList $ContainerName, $Password, $Database, (New-Call "QA Conc B $sufijo" "")
    $resA = (Receive-Job $jobA -Wait).Trim()
    $resB = (Receive-Job $jobB -Wait).Trim()
    Write-Host "A: $resA"
    Write-Host "B: $resB"

    $a = $resA.Split('|'); $b = $resB.Split('|')
    $exitos = @($a[0], $b[0]) | Where-Object { $_ -eq '1' }
    if ($exitos.Count -ne 1) { throw "TEST FAILED T-076-07: se esperaba exactamente 1 exito, hubo $($exitos.Count)." }
    $perdedor = if ($a[0] -eq '0') { $resA } else { $resB }
    if ($perdedor -notmatch 'PROG_005') { throw "TEST FAILED T-076-07: la sesion perdedora no devolvio PROG_005: $perdedor" }
    if ([int]$b[2] -lt 2500) { throw "TEST FAILED T-076-07: B tardo $($b[2]) ms; no se solapo con A (se ejecutaron en serie)." }
    if ($a[3] -ne '0' -or $b[3] -ne '0') { throw 'TEST FAILED T-076-07: @@TRANCOUNT <> 0 al terminar.' }
    $n = Invoke-Sql "SET NOCOUNT ON; SELECT COUNT(*) FROM dbo.Programa WHERE coordinador = '$coord';"
    if ($n -ne '1') { throw "TEST FAILED T-076-07: el coordinador quedo con $n programas." }
    Write-Host 'TEST_PASS:HU076_CONCURRENCY'
}
finally {
    Invoke-Sql @"
SET NOCOUNT ON;
DELETE FROM dbo.Programa WHERE facultad = '$fac';
DELETE FROM dbo.Coordinador WHERE id = '$coord';
DELETE FROM dbo.Facultad WHERE id = '$fac';
DELETE FROM dbo.Decano WHERE id = '$dec';
DELETE FROM dbo.Usuario WHERE id IN ('$uDec', '$uCoord');
"@ | Out-Null
    Write-Host 'Fixtures eliminados.'
}
