param (
    [string]$Server,          # host,puerto del SQL Server (por defecto SQL_SERVER o localhost,1433)
    [string]$Password         # por defecto SQL_CONTAINER_PASSWORD / MSSQL_SA_PASSWORD (nunca se imprime)
)
# LB-004D (DB-11 / DB-12): concurrencia real con DOS conexiones sobre usp_radicar_solicitud_revision_asistencia_v2
# y usp_registrar_archivo_soporte. A diferencia de test_lb004d_support_binding.sql (una transaccion con rollback), la
# concurrencia exige datos confirmados: el script crea fixtures con marcador unico, aserta y SIEMPRE los elimina en
# `finally` (solo filas con esos ids/marcador). No toca datos preexistentes. No crea otra base de datos.
$ErrorActionPreference = 'Stop'
$envFile = Join-Path (Split-Path $PSScriptRoot -Parent) '.env'
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith('#') -and $line.Contains('=')) {
            $p = $line.Split('=', 2); [Environment]::SetEnvironmentVariable($p[0].Trim(), $p[1].Trim())
        }
    }
}
if (-not $Server) { $Server = if ($env:SQL_SERVER) { $env:SQL_SERVER } else { 'localhost,1433' } }
if (-not $Password) { $Password = if ($env:SQL_CONTAINER_PASSWORD) { $env:SQL_CONTAINER_PASSWORD } else { $env:MSSQL_SA_PASSWORD } }
if (-not $Password -or $Password -ceq 'CHANGE_ME') { throw 'BLOCKED - SQL password is required (SQL_CONTAINER_PASSWORD/MSSQL_SA_PASSWORD).' }
$cs = "Server=$Server;Database=gestionasistenciadb;User Id=sa;Password=$Password;Encrypt=True;TrustServerCertificate=True;Application Name=lb004d-concurrency"

function Invoke-Sql([string]$sql, [hashtable]$params = @{}) {
    $c = New-Object System.Data.SqlClient.SqlConnection $cs
    $c.Open()
    try {
        $cmd = $c.CreateCommand(); $cmd.CommandText = $sql; $cmd.CommandTimeout = 60
        foreach ($k in $params.Keys) { [void]$cmd.Parameters.AddWithValue($k, $params[$k]) }
        $dt = New-Object System.Data.DataTable
        (New-Object System.Data.SqlClient.SqlDataAdapter $cmd).Fill($dt) | Out-Null
        return , $dt
    } finally { $c.Close() }
}

$precheck = (Invoke-Sql "SELECT CONCAT(DB_NAME(), '|', CONVERT(varchar(80), SERVERPROPERTY('Edition')))").Rows[0][0]
if ($precheck -notmatch '^gestionasistenciadb\|Developer Edition') { throw 'BLOCKED - unsafe database target.' }

$marker = "LB004D-CONC-$([guid]::NewGuid().ToString('N'))"
$fileAttach = [guid]::NewGuid(); $fileRegister = [guid]::NewGuid()
$sha = ([System.BitConverter]::ToString((New-Object System.Security.Cryptography.SHA256Managed).ComputeHash([Text.Encoding]::UTF8.GetBytes($marker))) -replace '-', '').ToLower()
$failures = @()
$asistenciasAntes = @()

# Fixture de lectura: una sesion existente con un estudiante activo matriculado en su grupo.
$fx = (Invoke-Sql @"
SELECT TOP 1 s.id AS sesion, eg.idEstudiante AS estudiante, e.usuario AS usuario
FROM dbo.Sesion s
JOIN dbo.uv_estudiante_grupo eg ON eg.idGrupo = s.grupo AND eg.codigoEstadoEstudiante = 'A'
JOIN dbo.Estudiante e ON e.id = eg.idEstudiante
ORDER BY s.id, eg.idEstudiante
"@).Rows[0]
$sesion = [guid]$fx.sesion; $estudiante = [guid]$fx.estudiante; $usuario = [guid]$fx.usuario
$asistenciasAntes = @((Invoke-Sql "SELECT id FROM dbo.Asistencia WHERE sesion = @s" @{ '@s' = $sesion }).Rows | ForEach-Object { [string]$_.id })

$callW2 = {
    param($cs, $sesion, $estudiante, $usuario, $file, $corr, $marker, $startAt)
    $c = New-Object System.Data.SqlClient.SqlConnection $cs
    $c.Open()
    try {
        $cmd = $c.CreateCommand(); $cmd.CommandTimeout = 60
        $cmd.CommandText = 'EXEC dbo.usp_radicar_solicitud_revision_asistencia_v2 @idEstudiante=@e, @idSesion=@s, @categoria=N''ASISTENCIA'', @justificacion=@j, @idArchivoSoporte=@f, @idCorrelacion=@c, @idUsuarioEjecutor=@u'
        [void]$cmd.Parameters.AddWithValue('@e', [guid]$estudiante); [void]$cmd.Parameters.AddWithValue('@s', [guid]$sesion)
        [void]$cmd.Parameters.AddWithValue('@j', $marker); [void]$cmd.Parameters.AddWithValue('@f', [guid]$file)
        [void]$cmd.Parameters.AddWithValue('@c', [guid]$corr); [void]$cmd.Parameters.AddWithValue('@u', [guid]$usuario)
        while ([DateTime]::UtcNow -lt $startAt) { Start-Sleep -Milliseconds 5 }
        $r = $cmd.ExecuteReader(); [void]$r.Read()
        "$([int]$r['estadoResultado'])|$($r['mensajeTecnicoResultado'])"
    } finally { $c.Close() }
}
$callW1 = {
    param($cs, $usuario, $file, $corr, $sha, $startAt)
    $c = New-Object System.Data.SqlClient.SqlConnection $cs
    $c.Open()
    try {
        $cmd = $c.CreateCommand(); $cmd.CommandTimeout = 60
        $cmd.CommandText = 'EXEC dbo.usp_registrar_archivo_soporte @idArchivoSoporte=@f, @nombreOriginal=N''conc.pdf'', @tipoContenido=''application/pdf'', @tamanioBytes=10, @checksumSha256=@h, @idCorrelacion=@c, @idUsuarioEjecutor=@u'
        [void]$cmd.Parameters.AddWithValue('@f', [guid]$file); [void]$cmd.Parameters.AddWithValue('@h', $sha)
        [void]$cmd.Parameters.AddWithValue('@c', [guid]$corr); [void]$cmd.Parameters.AddWithValue('@u', [guid]$usuario)
        while ([DateTime]::UtcNow -lt $startAt) { Start-Sleep -Milliseconds 5 }
        $r = $cmd.ExecuteReader(); [void]$r.Read()
        "$([int]$r['estadoResultado'])|$($r['mensajeTecnicoResultado'])"
    } finally { $c.Close() }
}

try {
    # ---- DB-14 (concurrencia W1): dos altas simultaneas del MISMO fileId y metadata => ambas OK, una sola fila
    $startAt = [DateTime]::UtcNow.AddSeconds(4)
    $jobs = 1..2 | ForEach-Object { Start-Job -ScriptBlock $callW1 -ArgumentList $cs, $usuario, $fileRegister, ([guid]::NewGuid()), $sha, $startAt }
    $res = $jobs | Wait-Job | Receive-Job; $jobs | Remove-Job
    $okW1 = @($res | Where-Object { $_ -like '1|*' }).Count
    $rows = (Invoke-Sql "SELECT COUNT(*) FROM dbo.ArchivoSoporte WHERE id = @f" @{ '@f' = $fileRegister }).Rows[0][0]
    if ($okW1 -ne 2 -or $rows -ne 1) { $failures += "W1 concurrente: exitos=$okW1 filas=$rows (esperado 2 y 1)" }

    # ---- DB-11 (concurrencia W2): dos radicaciones con el MISMO fileId => exactamente una gana
    [void](Invoke-Sql "SELECT 1")
    $reg = Invoke-Sql "EXEC dbo.usp_registrar_archivo_soporte @idArchivoSoporte=@f, @nombreOriginal=N'conc.pdf', @tipoContenido='application/pdf', @tamanioBytes=10, @checksumSha256=@h, @idCorrelacion=@c, @idUsuarioEjecutor=@u" @{ '@f' = $fileAttach; '@h' = $sha; '@c' = [guid]::NewGuid(); '@u' = $usuario }
    if ($reg.Rows[0]['estadoResultado'] -ne $true) { throw 'No se pudo registrar el DRAFT del fixture W2.' }
    $startAt = [DateTime]::UtcNow.AddSeconds(4)
    $jobs = 1..2 | ForEach-Object { Start-Job -ScriptBlock $callW2 -ArgumentList $cs, $sesion, $estudiante, $usuario, $fileAttach, ([guid]::NewGuid()), $marker, $startAt }
    $res = $jobs | Wait-Job | Receive-Job; $jobs | Remove-Job
    $win = @($res | Where-Object { $_ -like '1|*' }).Count
    $lose = @($res | Where-Object { $_ -like '0|*ARC_001*' }).Count
    $solicitudes = (Invoke-Sql "SELECT COUNT(*) FROM dbo.SolicitudRevisionAsistencia WHERE justificacionSolicitud = @j" @{ '@j' = $marker }).Rows[0][0]
    $estado = (Invoke-Sql "SELECT estado FROM dbo.ArchivoSoporte WHERE id = @f" @{ '@f' = $fileAttach }).Rows[0][0]
    $vinculadas = (Invoke-Sql "SELECT COUNT(*) FROM dbo.ArchivoSoporte a JOIN dbo.SolicitudRevisionAsistencia s ON s.id = a.solicitudRevisionAsistencia WHERE a.id = @f AND s.justificacionSolicitud = @j" @{ '@f' = $fileAttach; '@j' = $marker }).Rows[0][0]
    if ($win -ne 1 -or $lose -ne 1 -or $solicitudes -ne 1 -or $estado -ne 'ATTACHED' -or $vinculadas -ne 1) {
        $failures += "W2 concurrente: ganadoras=$win ARC_001=$lose solicitudes=$solicitudes estado=$estado vinculadas=$vinculadas (esperado 1,1,1,ATTACHED,1)"
    }
}
finally {
    # Limpieza acotada a los ids/marcador de esta ejecucion (orden de FK: archivo -> solicitud -> asistencia creada).
    $c = New-Object System.Data.SqlClient.SqlConnection $cs; $c.Open()
    try {
        $cmd = $c.CreateCommand()
        $cmd.CommandText = @"
DELETE FROM dbo.ArchivoSoporte WHERE id IN (@a, @r);
DELETE FROM dbo.SolicitudRevisionAsistencia WHERE justificacionSolicitud = @j;
DELETE a FROM dbo.Asistencia a
WHERE a.sesion = @s AND NOT EXISTS (SELECT 1 FROM STRING_SPLIT(@antes, ',') x WHERE TRY_CAST(x.value AS UNIQUEIDENTIFIER) = a.id)
  AND NOT EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia s WHERE s.asistencia = a.id)
  AND NOT EXISTS (SELECT 1 FROM dbo.DetalleAsistencia d WHERE d.asistencia = a.id);
"@
        [void]$cmd.Parameters.AddWithValue('@a', $fileAttach); [void]$cmd.Parameters.AddWithValue('@r', $fileRegister)
        [void]$cmd.Parameters.AddWithValue('@j', $marker); [void]$cmd.Parameters.AddWithValue('@s', $sesion)
        [void]$cmd.Parameters.AddWithValue('@antes', ($asistenciasAntes -join ','))
        [void]$cmd.ExecuteNonQuery()
    } finally { $c.Close() }
}

$left = (Invoke-Sql "SELECT (SELECT COUNT(*) FROM dbo.ArchivoSoporte WHERE id IN (@a, @r)) + (SELECT COUNT(*) FROM dbo.SolicitudRevisionAsistencia WHERE justificacionSolicitud = @j)" @{ '@a' = $fileAttach; '@r' = $fileRegister; '@j' = $marker }).Rows[0][0]
if ($left -ne 0) { $failures += "Limpieza incompleta: $left filas de fixture restantes" }
if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "TEST FAILED: LB004D_CONCURRENCY $_" -ForegroundColor Red }
    exit 1
}
Write-Host 'TEST_PASS:LB004D_W1_CONCURRENT_IDEMPOTENT'
Write-Host 'TEST_PASS:LB004D_W2_CONCURRENT_SINGLE_WINNER'
Write-Host 'TEST_PASS:LB004D_CONCURRENCY_FIXTURE_CLEANED'
