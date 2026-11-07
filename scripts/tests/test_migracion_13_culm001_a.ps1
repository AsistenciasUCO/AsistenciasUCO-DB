#Requires -Version 5.1
<#
.SYNOPSIS
  CULM-001 paquete A, compuerta manual del PLAN (N7): T-10, T-11 y T-13 de la migracion 13
  (13_culm001_a_retiro_solicitudes_up/down.sql) y A2-T-16 de la migracion 14 (14_culm001_a_correcciones_fase1_*).

.DESCRIPTION
  NO forma parte de infra.ps1 db-test: se ejecuta a mano en GREEN y AUDIT, y su salida se adjunta a VALIDATION.md.
  Corre sobre una BASE CLONADA (RESTORE del backup COPY_ONLY tomado antes de A con otro nombre), nunca sobre
  gestionasistenciadb. Los scripts de migracion se aplican sustituyendo USE [gestionasistenciadb] por el clon.

  T-10  up idempotente -> depuracion y reintento simulados -> down tolerante -> down otra vez -> up de nuevo.
  T-11  outbox: las notificaciones no terminales de SOLICITUD_INGRESO_* quedan FALLIDA_DEFINITIVA con
        TIPO_NOTIFICACION_RETIRADO y archivadas con su estado previo; la ENTREGADA y la de RETIRO_ESTUDIANTE_GRUPO no
        cambian; el despachador (usp_reservar_notificaciones_salientes) no toma ninguna de los 3 tipos.
  T-13  OBJECT_DEFINITION de los SP de la migracion = lote CREATE del archivo de schema/ (hash SHA-256 sin GO).
  A2-T-16 (si existe la migracion 14) up -> up -> down -> up; despues del down uv_usuario_perfil y uv_decano se
        consultan sin error, el RBAC DECANO y DOCENTE da estadoResultado = 1 y Decano.estado no existe; despues del
        segundo up, un decano desactivado vuelve a recibir SEC_001.
#>
param(
    [string]$ContainerName = 'sql_server_asistencias',
    [string]$Password = $(if ($env:SQL_CONTAINER_PASSWORD) { $env:SQL_CONTAINER_PASSWORD } else { $env:MSSQL_SA_PASSWORD }),
    [string]$BackupPath = '/var/opt/mssql/backup/gestionasistenciadb_antes_A_20261107.bak',
    [string]$CloneName = 'gestionasistenciadb_culm001a_mig',
    [switch]$KeepClone
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not $Password) {
    $envFile = Join-Path $Root '.env'
    if (Test-Path $envFile) {
        Get-Content $envFile | ForEach-Object {
            $line = $_.Trim()
            if ($line -and -not $line.StartsWith('#') -and $line.Contains('=')) {
                $parts = $line.Split('=', 2)
                [Environment]::SetEnvironmentVariable($parts[0].Trim(), $parts[1].Trim())
            }
        }
        $Password = if ($env:SQL_CONTAINER_PASSWORD) { $env:SQL_CONTAINER_PASSWORD } else { $env:MSSQL_SA_PASSWORD }
    }
}
if (-not $Password) { throw 'SQL password is required: pass -Password or set SQL_CONTAINER_PASSWORD/MSSQL_SA_PASSWORD.' }
if ($CloneName -eq 'gestionasistenciadb') { throw 'BLOCKED: la prueba de migracion nunca corre sobre gestionasistenciadb.' }

function Invoke-SqlText {
    param([string]$Sql, [string]$Database = $CloneName, [switch]$AllowFail)
    $localFile = [System.IO.Path]::GetTempFileName()
    Set-Content -Path $localFile -Value ("SET QUOTED_IDENTIFIER ON;`nSET ANSI_NULLS ON;`n" + $Sql) -Encoding utf8
    $remoteFile = "/tmp/culm001a_mig_$([guid]::NewGuid().ToString('N')).sql"
    docker cp $localFile "${ContainerName}:${remoteFile}" | Out-Null
    Remove-Item -Path $localFile -Force -ErrorAction SilentlyContinue
    docker exec -u 0 $ContainerName chmod a+r $remoteFile | Out-Null
    $out = @(docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -d $Database -U sa -P $Password -C -b -h -1 -W -s '|' -w 65535 -i $remoteFile 2>&1 | ForEach-Object { "$_" })
    $code = $LASTEXITCODE
    docker exec -u 0 $ContainerName rm -f $remoteFile | Out-Null
    if ($code -ne 0 -and -not $AllowFail) { throw "SQL fallo (exit $code): $($out -join ' | ')" }
    return $out
}

function Invoke-Migration {
    param([string]$RelativePath)
    $text = Get-Content -Raw -Encoding UTF8 -Path (Join-Path $Root $RelativePath)
    $text = $text.Replace('USE [gestionasistenciadb]', "USE [$CloneName]")
    $out = Invoke-SqlText -Sql $text
    foreach ($l in $out) { if ($l -match '^CULM001_A') { Write-Host "    $l" } }
    return $out
}

function Get-Value {
    param([string]$Sql, [string]$Key)
    $out = Invoke-SqlText -Sql ("SET NOCOUNT ON;`n" + $Sql)
    $hit = @($out | Where-Object { $_ -match "^$([regex]::Escape($Key))=" })
    if ($hit.Count -ne 1) { throw "No se obtuvo $Key : $($out -join ' | ')" }
    return $hit[0].Substring($Key.Length + 1).Trim()
}

function Assert-True { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw "TEST FAILED: $Message" } }

function Get-SchemaBatchHash {
    param([string]$RelativePath)
    $text = (Get-Content -Raw -Encoding UTF8 -Path (Join-Path $Root $RelativePath)).Replace("`r", '')
    $batches = [regex]::Split($text, '(?m)^GO[ \t]*$')
    $batch = @($batches | Where-Object { $_ -match 'CREATE\s+OR\s+ALTER\s+(PROCEDURE|VIEW|FUNCTION)' })
    if ($batch.Count -ne 1) { throw "Lote CREATE no unico en $RelativePath" }
    # sys.sql_modules guarda CREATE OR ALTER como CREATE (con otros espacios): se compara sin espacios en blanco y sin el
    # primer OR ALTER; cualquier otro cambio de texto se detecta.
    $sinBlancos = $batch[0] -replace '[ \t\r\n]', ''
    $norm = ([regex]'CREATEORALTER').Replace($sinBlancos, 'CREATE', 1)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    return ([BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::Unicode.GetBytes($norm)))).Replace('-', '')
}

function Test-SchemaParity {
    param([hashtable]$Objects, [string]$Label)
    foreach ($name in $Objects.Keys) {
        $expected = Get-SchemaBatchHash -RelativePath $Objects[$name]
        $actual = Get-Value -Key 'HASH' -Sql @"
DECLARE @d NVARCHAR(MAX) = REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID(N'dbo.$name')), CHAR(13), N''), CHAR(10), N''), CHAR(9), N''), N' ', N'');
SELECT CONCAT('HASH=', CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', @d), 2));
"@
        Assert-True ($actual -eq $expected) "$Label $name difiere de su archivo de schema/ (T-13)."
    }
}

$tipos = "('SOLICITUD_INGRESO_REGISTRADA','SOLICITUD_INGRESO_RESUELTA','SOLICITUD_INGRESO_RETIRADA')"
$archivos = "('zz_archivo_SolicitudIngresoGrupo','zz_archivo_NotificacionSolicitudIngreso','zz_archivo_PlantillaSolicitudIngreso','zz_archivo_PlantillaMarcadorSolicitudIngreso')"
$spsSolicitud = "('usp_registrar_solicitud_ingreso_grupo','usp_resolver_solicitud_ingreso_grupo','usp_retirar_solicitud_ingreso_grupo','usp_consultar_solicitudes_ingreso_grupo_docente','usp_consultar_solicitudes_ingreso_estudiante','usp_consultar_destinatarios_solicitud_ingreso_grupo')"
$paridad13 = @{
    'usp_consultar_oferta_grupos_estudiante'        = 'schema/stored-procedures/usp_consultar_oferta_grupos_estudiante.sql'
    'usp_internal_reactivar_matricula_retirada'     = 'schema/stored-procedures/usp_internal_reactivar_matricula_retirada.sql'
    'usp_registrar_estudiante_en_grupo_interno'     = 'schema/stored-procedures/usp_registrar_estudiante_en_grupo_interno.sql'
    'usp_registrar_estudiante_en_grupo'             = 'schema/stored-procedures/usp_registrar_estudiante_en_grupo.sql'
}

try {
    # ------------------------------------------------------------------ clon desde el backup COPY_ONLY
    Write-Host "-> Restaurando $BackupPath como [$CloneName]"
    $files = Invoke-SqlText -Database 'master' -Sql "SET NOCOUNT ON; RESTORE FILELISTONLY FROM DISK = N'$BackupPath';"
    $rows = @($files | Where-Object { $_ -match '\|' } | ForEach-Object { $c = $_.Split('|'); [pscustomobject]@{ Logical = $c[0].Trim(); Type = $c[2].Trim() } })
    $dataName = ($rows | Where-Object { $_.Type -eq 'D' } | Select-Object -First 1).Logical
    $logName = ($rows | Where-Object { $_.Type -eq 'L' } | Select-Object -First 1).Logical
    if (-not $dataName -or -not $logName) { throw "RESTORE FILELISTONLY sin archivos de datos/log: $($files -join ' | ')" }
    Invoke-SqlText -Database 'master' -Sql @"
IF DB_ID(N'$CloneName') IS NOT NULL BEGIN ALTER DATABASE [$CloneName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$CloneName]; END;
RESTORE DATABASE [$CloneName] FROM DISK = N'$BackupPath'
WITH MOVE N'$dataName' TO N'/var/opt/mssql/data/$CloneName.mdf', MOVE N'$logName' TO N'/var/opt/mssql/data/${CloneName}_log.ldf', REPLACE, RECOVERY;
"@ | Out-Null

    # ------------------------------------------------------------------ siembra previa (T-10 y T-11)
    Write-Host '-> Siembra previa al up: 2 solicitudes, plantilla v2 de administrador y 5 notificaciones'
    Invoke-SqlText -Sql @"
SET NOCOUNT ON;
DECLARE @est1 UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Estudiante ORDER BY id);
DECLARE @est2 UNIQUEIDENTIFIER = (SELECT id FROM (SELECT id, ROW_NUMBER() OVER (ORDER BY id) rn FROM dbo.Estudiante) z WHERE z.rn = 2);
DECLARE @grp UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Grupo ORDER BY id);
DECLARE @doc UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Docente ORDER BY id);
DECLARE @admin UNIQUEIDENTIFIER = (SELECT TOP 1 usuario FROM dbo.Administrador ORDER BY id);
DELETE FROM dbo.SolicitudIngresoGrupo WHERE estudiante IN (@est1, @est2) AND grupo = @grp;
INSERT INTO dbo.SolicitudIngresoGrupo (id, estudiante, grupo, estado, fechaSolicitudUtc)
VALUES ('C1A00000-0000-4000-8000-000000000001', @est1, @grp, (SELECT id FROM dbo.Estado WHERE codigo = 'P'), SYSUTCDATETIME());
INSERT INTO dbo.SolicitudIngresoGrupo (id, estudiante, grupo, estado, fechaSolicitudUtc, fechaResolucionUtc, docenteResolutor)
VALUES ('C1A00000-0000-4000-8000-000000000002', @est2, @grp, (SELECT id FROM dbo.Estado WHERE codigo = 'A'), DATEADD(DAY, -2, SYSUTCDATETIME()), SYSUTCDATETIME(), @doc);
UPDATE dbo.PlantillaNotificacion SET activa = 0 WHERE tipo = 'SOLICITUD_INGRESO_REGISTRADA' AND idioma = 'es' AND version = 1;
INSERT INTO dbo.PlantillaNotificacion (id, tipo, idioma, version, asunto, cuerpo, activa, creadoPor, creadoEn)
VALUES ('C1A00000-0000-4000-8000-0000000000B2', 'SOLICITUD_INGRESO_REGISTRADA', 'es', 2, N'Solicitud v2 {grupo}', N'{estudiante} pidio ingreso a {grupo} (v2).', 1, @admin, SYSUTCDATETIME());
DECLARE @pend UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoNotificacion WHERE codigo = 'PENDIENTE');
DECLARE @reint UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoNotificacion WHERE codigo = 'FALLIDA_REINTENTABLE');
DECLARE @entr UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoNotificacion WHERE codigo = 'ENTREGADA');
DECLARE @res UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoNotificacion WHERE codigo = 'RESERVADA');
DECLARE @ahora DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
INSERT INTO dbo.NotificacionSaliente (id, tipo, destinatarios, idEstado, creadoEn, proximoIntentoEn, reservadoHasta, reservadoPor, entregadoEn, codigoError, detalleError)
VALUES ('C1A00000-0000-4000-8000-0000000000N1', 'SOLICITUD_INGRESO_REGISTRADA', N'["qa1@uco.edu.co"]', @pend, @ahora, @ahora, NULL, NULL, NULL, NULL, NULL),
       ('C1A00000-0000-4000-8000-0000000000N2', 'SOLICITUD_INGRESO_RESUELTA', N'["qa2@uco.edu.co"]', @reint, @ahora, DATEADD(HOUR, 1, @ahora), NULL, NULL, NULL, 'SMTP_TEMPORAL', N'QA reintentable'),
       ('C1A00000-0000-4000-8000-0000000000N3', 'SOLICITUD_INGRESO_RETIRADA', N'["qa3@uco.edu.co"]', @entr, @ahora, NULL, NULL, NULL, @ahora, NULL, NULL),
       ('C1A00000-0000-4000-8000-0000000000N4', 'SOLICITUD_INGRESO_REGISTRADA', N'["qa4@uco.edu.co"]', @res, @ahora, @ahora, DATEADD(HOUR, -1, @ahora), N'qa-despachador', NULL, NULL, NULL),
       ('C1A00000-0000-4000-8000-0000000000N5', 'RETIRO_ESTUDIANTE_GRUPO', N'["qa5@uco.edu.co"]', @pend, @ahora, @ahora, NULL, NULL, NULL, NULL, NULL);
"@.Replace('0000000000N1', '000000000a01').Replace('0000000000N2', '000000000a02').Replace('0000000000N3', '000000000a03').Replace('0000000000N4', '000000000a04').Replace('0000000000N5', '000000000a05') | Out-Null
    $n1 = 'C1A00000-0000-4000-8000-000000000a01'; $n2 = 'C1A00000-0000-4000-8000-000000000a02'; $n3 = 'C1A00000-0000-4000-8000-000000000a03'
    $n4 = 'C1A00000-0000-4000-8000-000000000a04'; $n5 = 'C1A00000-0000-4000-8000-000000000a05'

    # ------------------------------------------------------------------ up
    Write-Host '-> up (13)'
    Invoke-Migration 'migrations/13_culm001_a_retiro_solicitudes_up.sql' | Out-Null
    $estado = Get-Value -Key 'UP1' -Sql @"
SELECT CONCAT('UP1=',
  (SELECT COUNT(*) FROM sys.tables WHERE name IN $archivos), '|',
  IIF(OBJECT_ID(N'dbo.SolicitudIngresoGrupo', N'U') IS NULL, 0, 1), '|',
  (SELECT COUNT(*) FROM sys.procedures WHERE name IN $spsSolicitud), '|',
  (SELECT COUNT(*) FROM dbo.zz_archivo_SolicitudIngresoGrupo WHERE id IN ('C1A00000-0000-4000-8000-000000000001','C1A00000-0000-4000-8000-000000000002')), '|',
  (SELECT COUNT(*) FROM dbo.zz_archivo_PlantillaSolicitudIngreso WHERE tipo = 'SOLICITUD_INGRESO_REGISTRADA'), '|',
  (SELECT COUNT(*) FROM dbo.zz_archivo_PlantillaSolicitudIngreso WHERE id = 'C1A00000-0000-4000-8000-0000000000B2' AND creadoPor IS NOT NULL AND activa = 1), '|',
  (SELECT COUNT(*) FROM dbo.zz_archivo_PlantillaMarcadorSolicitudIngreso), '|',
  (SELECT COUNT(*) FROM dbo.PlantillaNotificacion WHERE tipo IN $tipos), '|',
  (SELECT COUNT(*) FROM dbo.Estado WHERE codigo = 'E'), '|',
  (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo LIKE 'SIG[_]%'));
"@
    Assert-True ($estado -eq '4|0|0|2|2|1|6|0|0|0') "T-10 estado despues del up: $estado (archivos|tabla|sp|solicitudes|versiones REGISTRADA|v2 admin|marcadores|plantillas vivas|E|SIG)."

    # T-11: outbox
    $outbox = Get-Value -Key 'OUTBOX' -Sql @"
SELECT CONCAT('OUTBOX=',
  (SELECT COUNT(*) FROM dbo.NotificacionSaliente n JOIN dbo.EstadoNotificacion e ON e.id = n.idEstado
     WHERE n.id IN ('$n1','$n2','$n4') AND e.codigo = 'FALLIDA_DEFINITIVA' AND n.codigoError = 'TIPO_NOTIFICACION_RETIRADO'
       AND n.reservadoHasta IS NULL AND n.proximoIntentoEn IS NULL), '|',
  (SELECT COUNT(*) FROM dbo.zz_archivo_NotificacionSolicitudIngreso a WHERE (a.idNotificacion = '$n1' AND a.codigoEstadoAnterior = 'PENDIENTE')
     OR (a.idNotificacion = '$n2' AND a.codigoEstadoAnterior = 'FALLIDA_REINTENTABLE' AND a.codigoErrorAnterior = 'SMTP_TEMPORAL')
     OR (a.idNotificacion = '$n4' AND a.codigoEstadoAnterior = 'RESERVADA')), '|',
  (SELECT COUNT(*) FROM dbo.NotificacionSaliente n JOIN dbo.EstadoNotificacion e ON e.id = n.idEstado WHERE n.id = '$n3' AND e.codigo = 'ENTREGADA' AND n.codigoError IS NULL), '|',
  (SELECT COUNT(*) FROM dbo.NotificacionSaliente n JOIN dbo.EstadoNotificacion e ON e.id = n.idEstado WHERE n.id = '$n5' AND e.codigo = 'PENDIENTE'), '|',
  (SELECT COUNT(*) FROM dbo.zz_archivo_NotificacionSolicitudIngreso WHERE idNotificacion IN ('$n3','$n5')));
"@
    Assert-True ($outbox -eq '3|3|1|1|0') "T-11 outbox despues del up: $outbox."
    $reservadas = Get-Value -Key 'RES3' -Sql @"
DECLARE @cRes UNIQUEIDENTIFIER = NEWID();
BEGIN TRANSACTION;
EXEC dbo.usp_reservar_notificaciones_salientes @lote = 500, @leaseSegundos = 60, @instancia = N'qa-culm001a', @idCorrelacion = @cRes;
SELECT CONCAT('RES3=', (SELECT COUNT(*) FROM dbo.NotificacionSaliente n JOIN dbo.EstadoNotificacion e ON e.id = n.idEstado
    WHERE n.tipo IN $tipos AND e.codigo = 'RESERVADA' AND n.reservadoPor = N'qa-culm001a'),
    '|', (SELECT COUNT(*) FROM dbo.NotificacionSaliente n JOIN dbo.EstadoNotificacion e ON e.id = n.idEstado
    WHERE n.id = '$n5' AND e.codigo = 'RESERVADA'));
ROLLBACK TRANSACTION;
"@
    Assert-True ($reservadas -eq '0|1') "T-11 el despachador no debe tomar notificaciones de los 3 tipos (y si la de RETIRO): $reservadas."
    Write-Host 'TEST_PASS:CULM001A_T11_OUTBOX_CANCELADO'

    Test-SchemaParity -Objects $paridad13 -Label 'migracion 13'
    Write-Host 'TEST_PASS:CULM001A_T13_SCHEMA_PARIDAD'

    # up otra vez: sin error y mismos conteos
    $conteoSql = @"
SELECT CONCAT('CNT=', (SELECT COUNT(*) FROM dbo.zz_archivo_SolicitudIngresoGrupo), '|', (SELECT COUNT(*) FROM dbo.zz_archivo_NotificacionSolicitudIngreso), '|',
  (SELECT COUNT(*) FROM dbo.zz_archivo_PlantillaSolicitudIngreso), '|', (SELECT COUNT(*) FROM dbo.zz_archivo_PlantillaMarcadorSolicitudIngreso), '|',
  (SELECT COUNT(*) FROM dbo.NotificacionSaliente WHERE codigoError = 'TIPO_NOTIFICACION_RETIRADO'));
"@
    $antes = Get-Value -Key 'CNT' -Sql $conteoSql
    Write-Host '-> up (13) otra vez'
    Invoke-Migration 'migrations/13_culm001_a_retiro_solicitudes_up.sql' | Out-Null
    $despues = Get-Value -Key 'CNT' -Sql $conteoSql
    Assert-True ($antes -eq $despues) "T-10 el segundo up debe ser idempotente: antes=$antes despues=$despues."

    # despues del up: depuracion (n1) y reintento del administrador (n2)
    Invoke-SqlText -Sql @"
DELETE FROM dbo.NotificacionSaliente WHERE id = '$n1';
UPDATE dbo.NotificacionSaliente SET idEstado = (SELECT id FROM dbo.EstadoNotificacion WHERE codigo = 'PENDIENTE'),
    codigoError = NULL, detalleError = NULL, proximoIntentoEn = SYSDATETIMEOFFSET() WHERE id = '$n2';
"@ | Out-Null

    # ------------------------------------------------------------------ down
    Write-Host '-> down (13)'
    $downOut = Invoke-Migration 'migrations/13_culm001_a_retiro_solicitudes_down.sql'
    Assert-True ((@($downOut | Where-Object { $_ -match 'depuradas=1 reintentadas=1' })).Count -eq 1) 'T-10 el down debe informar la depurada y la reintentada como resueltas.'
    $down = Get-Value -Key 'DOWN' -Sql @"
SELECT CONCAT('DOWN=',
  IIF(OBJECT_ID(N'dbo.SolicitudIngresoGrupo', N'U') IS NULL, 0, 1), '|',
  (SELECT COUNT(*) FROM sys.procedures p JOIN sys.database_permissions dp ON dp.major_id = p.object_id
     WHERE p.name IN $spsSolicitud AND dp.permission_name = 'EXECUTE' AND dp.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime')), '|',
  (SELECT COUNT(*) FROM dbo.Estado WHERE codigo = 'E' AND id = 'C5D1E2F3-4A5B-4C6D-8E7F-901A2B3C4D5E'), '|',
  (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo LIKE 'SIG[_]%'), '|',
  (SELECT COUNT(*) FROM dbo.CatalogoMensajeTecnico WHERE codigo LIKE 'SIG[_]%'), '|',
  (SELECT COUNT(*) FROM dbo.PlantillaNotificacion WHERE tipo = 'SOLICITUD_INGRESO_REGISTRADA' AND ((version = 1 AND activa = 0 AND creadoPor IS NULL)
     OR (id = 'C1A00000-0000-4000-8000-0000000000B2' AND version = 2 AND activa = 1 AND creadoPor IS NOT NULL))), '|',
  (SELECT COUNT(*) FROM dbo.PlantillaNotificacionMarcador WHERE tipo IN $tipos), '|',
  (SELECT COUNT(*) FROM dbo.SolicitudIngresoGrupo WHERE id IN ('C1A00000-0000-4000-8000-000000000001','C1A00000-0000-4000-8000-000000000002')), '|',
  (SELECT COUNT(*) FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID('dbo.usp_consultar_oferta_grupos_estudiante'), 0)), '|',
  (SELECT COUNT(*) FROM dbo.NotificacionSaliente n JOIN dbo.EstadoNotificacion e ON e.id = n.idEstado WHERE n.id = '$n4' AND e.codigo = 'PENDIENTE'
     AND n.proximoIntentoEn IS NOT NULL AND n.reservadoHasta IS NULL), '|',
  (SELECT COUNT(*) FROM dbo.NotificacionSaliente n JOIN dbo.EstadoNotificacion e ON e.id = n.idEstado WHERE n.id = '$n2' AND e.codigo = 'PENDIENTE' AND n.codigoError IS NULL), '|',
  (SELECT COUNT(*) FROM dbo.NotificacionSaliente WHERE id = '$n1'), '|',
  (SELECT COUNT(*) FROM sys.tables WHERE name IN $archivos), '|',
  IIF(OBJECT_ID(N'dbo.usp_internal_reactivar_matricula_retirada', N'P') IS NULL, 0, 1));
"@
    Assert-True ($down -eq '1|6|1|15|15|2|6|2|21|1|1|0|0|0') "T-10 estado despues del down: $down."

    Write-Host '-> down (13) otra vez'
    Invoke-Migration 'migrations/13_culm001_a_retiro_solicitudes_down.sql' | Out-Null
    Write-Host '-> up (13) de nuevo'
    Invoke-Migration 'migrations/13_culm001_a_retiro_solicitudes_up.sql' | Out-Null
    $final = Get-Value -Key 'FINAL' -Sql @"
SELECT CONCAT('FINAL=', IIF(OBJECT_ID(N'dbo.SolicitudIngresoGrupo', N'U') IS NULL, 0, 1), '|', (SELECT COUNT(*) FROM sys.procedures WHERE name IN $spsSolicitud), '|',
  (SELECT COUNT(*) FROM dbo.Estado WHERE codigo = 'E'), '|', (SELECT COUNT(*) FROM dbo.Estado WHERE codigo = 'X'), '|',
  dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_RETIRADA'), dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA'), '|',
  (SELECT COUNT(*) FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID('dbo.usp_consultar_oferta_grupos_estudiante'), 0)), '|',
  (SELECT COUNT(*) FROM dbo.zz_archivo_SolicitudIngresoGrupo WHERE id IN ('C1A00000-0000-4000-8000-000000000001','C1A00000-0000-4000-8000-000000000002')));
"@
    Assert-True ($final -eq '0|0|0|1|IA|19|2') "T-10 estado despues del up final: $final."
    Test-SchemaParity -Objects $paridad13 -Label 'migracion 13 (up final)'
    Write-Host 'TEST_PASS:CULM001A_T10_UP_DOWN_UP'

    # ------------------------------------------------------------------ A2-T-16: migracion 14
    $up14 = 'migrations/14_culm001_a_correcciones_fase1_up.sql'
    $down14 = 'migrations/14_culm001_a_correcciones_fase1_down.sql'
    if ((Test-Path (Join-Path $Root $up14)) -and (Test-Path (Join-Path $Root $down14))) {
        Write-Host '-> up (14), up (14) otra vez'
        Invoke-Migration $up14 | Out-Null
        Invoke-Migration $up14 | Out-Null
        $paridad14 = @{}
        Get-Content (Join-Path $Root $up14) -Encoding UTF8 | ForEach-Object {
            if ($_ -match '^-- PARIDAD: (\S+) (\S+)$') { $paridad14[$Matches[1]] = $Matches[2] }
        }
        if ($paridad14.Count -gt 0) { Test-SchemaParity -Objects $paridad14 -Label 'migracion 14' }
        Write-Host '-> down (14)'
        Invoke-Migration $down14 | Out-Null
        $rbac = Get-Value -Key 'RBAC' -Sql @"
DECLARE @mu NVARCHAR(4000), @mt NVARCHAR(4000), @okDec BIT, @okDoc BIT, @c UNIQUEIDENTIFIER = NEWID();
DECLARE @uDec UNIQUEIDENTIFIER = (SELECT TOP 1 d.usuario FROM dbo.Decano d JOIN dbo.Usuario u ON u.id = d.usuario WHERE u.estado = 1 ORDER BY d.id);
DECLARE @uDoc UNIQUEIDENTIFIER = (SELECT TOP 1 d.usuario FROM dbo.Docente d JOIN dbo.Usuario u ON u.id = d.usuario WHERE u.estado = 1 ORDER BY d.id);
DECLARE @p INT = (SELECT COUNT(*) FROM (SELECT TOP 1 * FROM dbo.uv_usuario_perfil) x);
DECLARE @v INT = (SELECT COUNT(*) FROM (SELECT TOP 1 * FROM dbo.uv_decano) x);
EXEC dbo.usp_validar_permiso_rbac_usuario_interno @idUsuario = @uDec, @codigoPerfilRequerido = 'DECANO', @idCorrelacion = @c,
    @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @okDec OUTPUT;
EXEC dbo.usp_validar_permiso_rbac_usuario_interno @idUsuario = @uDoc, @codigoPerfilRequerido = 'DOCENTE', @idCorrelacion = @c,
    @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @okDoc OUTPUT;
SELECT CONCAT('RBAC=', @okDec, '|', @okDoc, '|', IIF(COL_LENGTH('dbo.Decano', 'estado') IS NULL, 0, 1), '|', IIF(@p >= 0 AND @v >= 0, 1, 0));
"@
        Assert-True ($rbac -eq '1|1|0|1') "A2-T-16 despues del down de 14: $rbac (rbacDecano|rbacDocente|columnaDecano.estado|vistas)."
        Write-Host '-> up (14) de nuevo'
        Invoke-Migration $up14 | Out-Null
        $rbac2 = Get-Value -Key 'RBAC2' -Sql @"
DECLARE @mu NVARCHAR(4000), @mt NVARCHAR(4000), @ok BIT, @c UNIQUEIDENTIFIER = NEWID();
DECLARE @idDec UNIQUEIDENTIFIER, @uDec UNIQUEIDENTIFIER;
SELECT TOP 1 @idDec = d.id, @uDec = d.usuario FROM dbo.Decano d JOIN dbo.Usuario u ON u.id = d.usuario WHERE u.estado = 1 ORDER BY d.id;
BEGIN TRANSACTION;
EXEC sys.sp_executesql N'UPDATE dbo.Decano SET estado = 0 WHERE id = @id;', N'@id UNIQUEIDENTIFIER', @id = @idDec;
EXEC dbo.usp_validar_permiso_rbac_usuario_interno @idUsuario = @uDec, @codigoPerfilRequerido = 'DECANO', @idCorrelacion = @c,
    @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
ROLLBACK TRANSACTION;
SELECT CONCAT('RBAC2=', @ok, '|', IIF(@mt LIKE 'DBCODE=SEC[_]001|%', 1, 0));
"@
        Assert-True ($rbac2 -eq '0|1') "A2-T-16 despues del segundo up, el decano desactivado debe recibir SEC_001: $rbac2."
        if ($paridad14.Count -gt 0) { Test-SchemaParity -Objects $paridad14 -Label 'migracion 14 (up final)' }
        Write-Host 'TEST_PASS:CULM001A2_T16_MIGRACION_14'
    }
    else {
        Write-Host 'TEST_SKIP:CULM001A2_T16_MIGRACION_14 (migracion 14 ausente)'
    }
}
finally {
    if (-not $KeepClone) {
        Invoke-SqlText -Database 'master' -AllowFail -Sql "IF DB_ID(N'$CloneName') IS NOT NULL BEGIN ALTER DATABASE [$CloneName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$CloneName]; END;" | Out-Null
    }
}
