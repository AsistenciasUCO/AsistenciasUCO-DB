param (
    [string]$ContainerName = 'sql_server_asistencias',
    [string]$Password = $env:MSSQL_SA_PASSWORD
)

# T-091-13 (R7): dos vinculos simultaneos del mismo par (docente, programa) => uno OK y el otro DOC_006.
# Crea fixtures confirmados (commit) con prefijo QA-CONC, ejecuta dos sesiones en paralelo y limpia al final.
$ErrorActionPreference = 'Stop'
if (-not $Password) { throw 'Password requerido (-Password o MSSQL_SA_PASSWORD).' }

function Invoke-Sql([string]$query) {
    $out = docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P $Password -C -d gestionasistenciadb -b -h -1 -W -Q $query 2>&1
    if ($LASTEXITCODE -ne 0) { throw "sqlcmd fallo: $out" }
    return ($out | Out-String).Trim()
}

$setup = @"
SET NOCOUNT ON;
DECLARE @tipo UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @fac UNIQUEIDENTIFIER = (SELECT TOP 1 idFacultad FROM dbo.uv_programa);
DECLARE @tp UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoPrograma);
DECLARE @uC UNIQUEIDENTIFIER = NEWID(), @cC UNIQUEIDENTIFIER = NEWID(), @uD UNIQUEIDENTIFIER = NEWID(), @dD UNIQUEIDENTIFIER = NEWID(), @p UNIQUEIDENTIFIER = NEWID();
INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password) VALUES
 (@uC, @tipo, 960000001, N'Conc', N'Qa', N'Coord', N'Qa', N'qa.conc.coord@test.local', 1, 1, N'HashBackend_C1'),
 (@uD, @tipo, 960000002, N'Conc', N'Qa', N'Docente', N'Qa', N'qa.conc.doc@test.local', 1, 1, N'HashBackend_C2');
INSERT INTO dbo.Coordinador (id, usuario) VALUES (@cC, @uC);
INSERT INTO dbo.Docente (id, usuario) VALUES (@dD, @uD);
INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado) VALUES (@p, @fac, @tp, N'QA-CONC Programa', @cC, 1);
SELECT CONCAT(@uC, '|', @dD, '|', @p);
"@
$ids = (Invoke-Sql $setup).Split('|')
$uC, $dD, $p = $ids[0], $ids[1], $ids[2]

try {
    $call = "DECLARE @tv UNIQUEIDENTIFIER = (SELECT id FROM dbo.TipoVinculacion WHERE codigo='CAT'); DECLARE @c UNIQUEIDENTIFIER = NEWID(); EXEC dbo.usp_vincular_docente_programa @idDocente='$dD', @idTipoVinculacion=@tv, @idPrograma='$p', @idCorrelacion=@c, @idUsuarioEjecutor='$uC';"
    $jobs = 1..2 | ForEach-Object {
        Start-Job -ArgumentList $ContainerName, $Password, $call -ScriptBlock {
            param($c, $pw, $q)
            docker exec $c /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P $pw -C -d gestionasistenciadb -h -1 -W -s '|' -Q $q 2>&1 | Out-String
        }
    }
    $results = $jobs | Wait-Job | Receive-Job
    $jobs | Remove-Job
    $exitos = @($results | Where-Object { $_ -match '(?m)\|\s*1\s*$' }).Count
    $total = (Invoke-Sql "SET NOCOUNT ON; SELECT COUNT(*) FROM dbo.DocentePrograma WHERE docente='$dD' AND programa='$p'")
    if ($total -ne '1') { throw "T-091-13 FAILED: se esperaba 1 vinculo, hay $total." }
    if ($exitos -ne 1) { throw "T-091-13 FAILED: se esperaba exactamente 1 exito, hubo $exitos. Salida: $results" }
    Write-Host 'TEST_PASS:T-091-13' -ForegroundColor Green
}
finally {
    Invoke-Sql "SET NOCOUNT ON; DELETE FROM dbo.DocentePrograma WHERE docente='$dD'; DELETE FROM dbo.Programa WHERE id='$p'; DELETE FROM dbo.Docente WHERE id='$dD'; DELETE FROM dbo.Coordinador WHERE usuario='$uC'; DELETE FROM dbo.Usuario WHERE correo IN (N'qa.conc.coord@test.local', N'qa.conc.doc@test.local');" | Out-Null
}
