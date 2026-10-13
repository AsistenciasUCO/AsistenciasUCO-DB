param (
    [Parameter(Mandatory = $true)][string]$ContainerName,
    [Parameter(Mandatory = $true)][string]$AdminPassword
)

# CC-003G-01: verifica con un LOGIN real de minimo privilegio (miembro SOLO de rol_asistencias_runtime, nunca sa)
# que los dos proveedores publicos son ejecutables y funcionales y que el nucleo interno, el DML directo y la
# lectura de tablas base estan denegados. El login se crea y se elimina dentro del script.
$ErrorActionPreference = 'Stop'
$database = 'gestionasistenciadb'
$login = 'cc003g01_runtime_' + ([guid]::NewGuid().ToString('N').Substring(0, 16))
$loginPassword = 'T!9a' + [guid]::NewGuid().ToString('N') + 'Zz'
$tag = ([guid]::NewGuid().ToString('N').Substring(0, 12))

function Invoke-Sql {
    param([string]$User, [string]$Password, [string]$Query)
    $out = docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd `
        -S localhost -d $database -U $User -P $Password -C -b -h -1 -W -s '|' -Q $Query 2>&1
    return @{ ExitCode = $LASTEXITCODE; Output = (($out | ForEach-Object { "$_" }) -join "`n") }
}

function Invoke-SqlFile {
    param([string]$User, [string]$Password, [string]$Sql)
    $local = Join-Path ([System.IO.Path]::GetTempPath()) "cc003g01_runtime_$([guid]::NewGuid().ToString('N')).sql"
    Set-Content -Path $local -Value $Sql -Encoding utf8
    $remote = "/tmp/cc003g01_runtime_$tag.sql"
    docker cp $local "${ContainerName}:$remote" | Out-Null
    docker exec -u 0 $ContainerName chmod a+r $remote | Out-Null
    Remove-Item -Path $local -Force -ErrorAction SilentlyContinue
    $out = docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd `
        -S localhost -d $database -U $User -P $Password -C -b -h -1 -W -s '|' -w 65535 -i $remote 2>&1
    $code = $LASTEXITCODE
    docker exec -u 0 $ContainerName rm -f $remote 2>$null | Out-Null
    return @{ ExitCode = $code; Output = (($out | ForEach-Object { "$_" }) -join "`n") }
}

$escapedLogin = $login.Replace(']', ']]')
$userNumber = 1600000000 + (Get-Random -Minimum 1 -Maximum 90000000)
$userEmail = "qa.cc003g01.rt.$tag@test.local"
$planInp = 30000 + (Get-Random -Minimum 1 -Maximum 9000)
$planId = [guid]::NewGuid().ToString()
try {
    $setup = Invoke-Sql -User 'sa' -Password $AdminPassword -Query @"
CREATE LOGIN [$escapedLogin] WITH PASSWORD = '$loginPassword', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;
CREATE USER [$escapedLogin] FOR LOGIN [$escapedLogin];
ALTER ROLE [rol_asistencias_runtime] ADD MEMBER [$escapedLogin];
"@
    if ($setup.ExitCode -ne 0) { throw "Could not create the isolated runtime login: $($setup.Output)" }

    # Datos de apoyo leidos como administrador del contenedor aislado (no se hardcodean ids)
    $fx = Invoke-Sql -User 'sa' -Password $AdminPassword -Query @"
SET NOCOUNT ON;
SELECT CONCAT(CONVERT(VARCHAR(36), (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC')), '|',
              CONVERT(VARCHAR(36), p.id), '|', CONVERT(VARCHAR(36), ci.idUsuario))
FROM dbo.uv_programa p JOIN dbo.uv_coordinador_identidad ci ON ci.id = p.idCoordinador
WHERE ci.estaActivoUsuario = 1 ORDER BY p.id;
"@
    $fxLine = @($fx.Output -split "`n" | Where-Object { $_ -match '^[0-9A-Fa-f-]{36}\|[0-9A-Fa-f-]{36}\|[0-9A-Fa-f-]{36}$' } | Select-Object -First 1)
    if ($fx.ExitCode -ne 0 -or $fxLine.Count -ne 1) { throw 'Runtime verification fixtures (tipo/programa/coordinador) are missing.' }
    $tipoId, $programaId, $coordinadorUsuario = $fxLine[0].Split('|')

    # 1. Grants por objeto
    $perm = Invoke-Sql -User $login -Password $loginPassword -Query @"
SET NOCOUNT ON;
SELECT CONCAT('sync=', HAS_PERMS_BY_NAME('dbo.usp_sincronizar_usuario', 'OBJECT', 'EXECUTE'),
              ';plan=', HAS_PERMS_BY_NAME('dbo.usp_registrar_o_actualizar_plan_estudio', 'OBJECT', 'EXECUTE'),
              ';syncInterno=', HAS_PERMS_BY_NAME('dbo.usp_sincronizar_usuario_interno', 'OBJECT', 'EXECUTE'),
              ';validadorInterno=', HAS_PERMS_BY_NAME('dbo.usp_validar_titularidad_jerarquica_interno', 'OBJECT', 'EXECUTE'));
"@
    if ($perm.ExitCode -ne 0 -or $perm.Output -notmatch 'sync=1;plan=1;syncInterno=0;validadorInterno=0') {
        throw "Unexpected object permissions for the runtime login: $($perm.Output)"
    }
    Write-Output 'TEST_PASS:CC003G01_RUNTIME_EXECUTE_GRANTS'

    # 2. Internos, DML directo y lectura de tablas base denegados (error 229/230 con el login real)
    $denied = @(
        @{ Name = 'INTERNAL_EXEC'; Query = 'EXEC dbo.usp_sincronizar_usuario_interno;' },
        @{ Name = 'VALIDATOR_EXEC'; Query = 'EXEC dbo.usp_validar_titularidad_jerarquica_interno;' },
        @{ Name = 'USUARIO_INSERT'; Query = "INSERT dbo.Usuario (id) VALUES (NEWID());" },
        @{ Name = 'USUARIO_UPDATE'; Query = 'UPDATE dbo.Usuario SET estado = estado WHERE 1 = 0;' },
        @{ Name = 'USUARIO_DELETE'; Query = 'DELETE dbo.Usuario WHERE 1 = 0;' },
        @{ Name = 'USUARIO_SELECT'; Query = 'SELECT TOP 1 password FROM dbo.Usuario;' },
        @{ Name = 'PLAN_INSERT'; Query = 'INSERT dbo.PlanEstudio (id) VALUES (NEWID());' },
        @{ Name = 'PLAN_UPDATE'; Query = 'UPDATE dbo.PlanEstudio SET inp = inp WHERE 1 = 0;' },
        @{ Name = 'PLAN_DELETE'; Query = 'DELETE dbo.PlanEstudio WHERE 1 = 0;' }
    )
    foreach ($d in $denied) {
        $r = Invoke-Sql -User $login -Password $loginPassword -Query $d.Query
        if ($r.ExitCode -eq 0 -or $r.Output -notmatch '(permission was denied|permiso)') {
            throw "Runtime login unexpectedly allowed '$($d.Name)': $($r.Output)"
        }
    }
    Write-Output 'TEST_PASS:CC003G01_RUNTIME_INTERNAL_EXEC_DENIED'
    Write-Output 'TEST_PASS:CC003G01_RUNTIME_DIRECT_DML_DENIED'
    Write-Output 'TEST_PASS:CC003G01_RUNTIME_BASE_TABLE_READ_DENIED'

    # 3. Ejecucion efectiva por el login de minimo privilegio (cadena de propiedad dbo -> dbo, sin sysadmin)
    $sql = @"
SET NOCOUNT ON;
DECLARE @c UNIQUEIDENTIFIER = NEWID();
EXEC dbo.usp_sincronizar_usuario @idTipoIdIdentificacion = '$tipoId', @numeroIdentificacion = $userNumber,
    @primerApellido = N'Runtime', @segundoApellido = N'Least', @primerNombre = N'Privilege', @segundoNombre = N'Login',
    @correo = N'$userEmail', @password = N'HashBackend_CC003G01_RUNTIME_SECRET', @idCorrelacion = @c;
EXEC dbo.usp_sincronizar_usuario @idTipoIdIdentificacion = '$tipoId', @numeroIdentificacion = $userNumber,
    @primerApellido = N'Runtime', @segundoApellido = N'Least', @primerNombre = N'Privilege', @segundoNombre = N'Login',
    @correo = N'$userEmail', @password = N'HashBackend_CC003G01_RUNTIME_SECRET_2', @idCorrelacion = @c;
EXEC dbo.usp_sincronizar_usuario @idTipoIdIdentificacion = '$tipoId', @numeroIdentificacion = $userNumber,
    @primerApellido = N'Runtime', @segundoApellido = N'Least', @primerNombre = N'Otro', @segundoNombre = N'Login',
    @correo = N'$userEmail', @password = N'HashBackend_CC003G01_RUNTIME_SECRET_3', @idCorrelacion = @c;
EXEC dbo.usp_registrar_o_actualizar_plan_estudio @idPlanEstudio = '$planId', @idPrograma = '$programaId',
    @inp = $planInp, @idCorrelacion = @c, @idUsuarioEjecutor = '$coordinadorUsuario';
EXEC dbo.usp_registrar_o_actualizar_plan_estudio @idPlanEstudio = '$planId', @idPrograma = '$programaId',
    @inp = $planInp, @idCorrelacion = @c, @idUsuarioEjecutor = '$coordinadorUsuario';
EXEC dbo.usp_registrar_o_actualizar_plan_estudio @idPlanEstudio = '$planId', @idPrograma = '$programaId',
    @inp = $planInp, @idCorrelacion = @c, @idUsuarioEjecutor = NULL;
SELECT CONCAT('VISIBLE|', (SELECT COUNT(*) FROM dbo.uv_usuario WHERE numeroIdentificacion = $userNumber),
              '|', (SELECT COUNT(*) FROM dbo.uv_plan_estudio WHERE id = '$planId' AND inp = $planInp));
"@
    $run = Invoke-SqlFile -User $login -Password $loginPassword -Sql $sql
    if ($run.ExitCode -ne 0) { throw "Runtime login could not execute the providers: $($run.Output)" }
    $states = @([regex]::Matches($run.Output, '(?m)^[0-9A-Fa-f-]{36}\|.*\|\s*([01])\s*$') | ForEach-Object { $_.Groups[1].Value })
    if (($states -join ',') -ne '1,1,0,1,1,0') { throw "Unexpected provider states for the runtime login: $($states -join ',')" }
    if ($run.Output -notmatch '(?m)^VISIBLE\|1\|1$') { throw "Providers did not persist rows visible through uv_* views: $($run.Output)" }
    if ($run.Output -match 'RUNTIME_SECRET') { throw 'A provider echoed the password hash.' }
    Write-Output 'TEST_PASS:CC003G01_RUNTIME_PROVIDERS_FUNCTIONAL'
}
finally {
    try {
        Invoke-Sql -User 'sa' -Password $AdminPassword -Query "DELETE FROM dbo.PlanEstudio WHERE id = '$planId'; DELETE FROM dbo.Usuario WHERE correo = N'$userEmail';" | Out-Null
        Invoke-Sql -User 'sa' -Password $AdminPassword -Query "IF DATABASE_PRINCIPAL_ID(N'$login') IS NOT NULL DROP USER [$login];" | Out-Null
        docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P $AdminPassword -C -b -Q "IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$login') DROP LOGIN [$login];" | Out-Null
    }
    catch {
        Write-Error 'Runtime-login cleanup failed; inspect the isolated test container before reuse.'
        throw
    }
}
