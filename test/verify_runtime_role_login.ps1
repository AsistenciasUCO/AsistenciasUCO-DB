param (
    [Parameter(Mandatory = $true)][string]$ContainerName,
    [Parameter(Mandatory = $true)][string]$AdminPassword
)

$ErrorActionPreference = 'Stop'
$database = 'gestionasistenciadb'
$login = 'utc_d06_runtime_' + ([guid]::NewGuid().ToString('N').Substring(0, 16))
$loginPassword = 'T!9a' + [guid]::NewGuid().ToString('N') + 'Zz'

function Invoke-SqlCmdInContainer {
    param([string]$User, [string]$Password, [string]$Query)
    $result = docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd `
        -S localhost -d $database -U $User -P $Password -C -b -h -1 -W -Q $Query 2>&1
    return $result
}

try {
    $escapedLogin = $login.Replace(']', ']]')
    Invoke-SqlCmdInContainer -User 'sa' -Password $AdminPassword -Query @"
CREATE LOGIN [$escapedLogin] WITH PASSWORD = '$loginPassword', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;
CREATE USER [$escapedLogin] FOR LOGIN [$escapedLogin];
ALTER ROLE [rol_asistencias_runtime] ADD MEMBER [$escapedLogin];
"@ | Out-Null

    $requiredProcedures = @(
        'usp_actualizar_asignatura', 'usp_actualizar_grupo', 'usp_actualizar_sesion', 'usp_actualizar_sesion_v2',
        'usp_cerrar_sesion', 'usp_crear_asignatura', 'usp_crear_coordinador', 'usp_crear_decano',
        'usp_crear_grupo', 'usp_crear_sesion', 'usp_crear_sesion_v2', 'usp_ejecutar_cierre_masivo_periodo',
        'usp_generar_sesiones_grupo', 'usp_radicar_solicitud_revision_asistencia',
        'usp_registrar_asistencia_estudiante_autonomo', 'usp_registrar_asistencias_sesion',
        'usp_registrar_estudiante_en_grupo', 'usp_resolver_solicitud_revision_asistencia',
        'usp_toggle_estado_asignatura'
    )
    $permissionRows = $requiredProcedures | ForEach-Object {
        "SELECT '$_' AS procedure_name, HAS_PERMS_BY_NAME('dbo.$_', 'OBJECT', 'EXECUTE') AS can_execute"
    }
    $permissionOutput = Invoke-SqlCmdInContainer -User $login -Password $loginPassword -Query (($permissionRows -join ' UNION ALL ') + ';')
    $missing = @($permissionOutput | Where-Object { $_ -match '\|0$' })
    if ($missing.Count -gt 0) {
        throw 'Runtime login lacks an explicit EXECUTE grant for one or more required procedures.'
    }

    Invoke-SqlCmdInContainer -User 'sa' -Password $AdminPassword -Query "IF EXISTS (SELECT 1 FROM sys.database_permissions WHERE grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') AND class_desc = 'SCHEMA' AND permission_name = 'EXECUTE' AND state_desc LIKE 'GRANT%') THROW 52121, 'Schema-wide EXECUTE grant remains.', 1;" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Runtime role still has a schema-wide EXECUTE grant.'
    }

    $directDml = Invoke-SqlCmdInContainer -User $login -Password $loginPassword -Query 'UPDATE dbo.Sesion SET nombre = nombre WHERE 1 = 0;'
    if ($LASTEXITCODE -eq 0) {
        throw 'Runtime login unexpectedly has direct UPDATE permission on dbo.Sesion.'
    }

    $internalExecute = Invoke-SqlCmdInContainer -User $login -Password $loginPassword -Query 'EXEC dbo.usp_crear_sesion_interno;'
    if ($LASTEXITCODE -eq 0) {
        throw 'Runtime login unexpectedly executes dbo.usp_crear_sesion_interno.'
    }

    Write-Host 'TEST_PASS:UTC_D06_RUNTIME_LOGIN_OBJECT_GRANTS'
    Write-Host 'TEST_PASS:UTC_D06_RUNTIME_LOGIN_DIRECT_DML_DENIED'
    Write-Host 'TEST_PASS:UTC_D06_RUNTIME_LOGIN_INTERNAL_EXEC_DENIED'
} finally {
    try {
        Invoke-SqlCmdInContainer -User 'sa' -Password $AdminPassword -Query "IF DATABASE_PRINCIPAL_ID(N'$login') IS NOT NULL DROP USER [$login];" | Out-Null
        docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P $AdminPassword -C -b -Q "IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$login') DROP LOGIN [$login];" | Out-Null
    } catch {
        Write-Error 'Runtime-login cleanup failed; inspect the isolated test container before reuse.'
        throw
    }
}
