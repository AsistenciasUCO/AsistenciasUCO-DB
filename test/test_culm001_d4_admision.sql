USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ============================================================================
-- CULM-001 D.4 (CONTRACT §5.2, HU156): admision de estudiantes por el administrador. D4-01 .. D4-11 (D4-12, up->down->up de
-- la migracion 23, esta en test_culm001_d4.ps1). Los casos D4-01..D4-08, D4-10 y D4-11 corren en UNA transaccion con ROLLBACK
-- final; D4-09 (fallo despues de crear el Usuario) corre fuera de transaccion para que el SP sea dueno de la suya.
-- ============================================================================
IF OBJECT_ID('tempdb..#d4_expect') IS NOT NULL DROP PROCEDURE #d4_expect;
GO
CREATE PROCEDURE #d4_expect @label VARCHAR(100), @ok BIT
AS
BEGIN
    IF @ok IS NULL OR @ok <> 1
    BEGIN
        DECLARE @mensaje NVARCHAR(400) = CONCAT('TEST FAILED: CULM001_D4_', @label);
        THROW 52400, @mensaje, 1;
    END
END;
GO

DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @idPrograma UNIQUEIDENTIFIER, @uCoord UNIQUEIDENTIFIER, @idInstitucion UNIQUEIDENTIFIER;
SELECT TOP 1 @idPrograma = p.id, @uCoord = ci.idUsuario, @idInstitucion = p.idInstitucion
FROM dbo.uv_programa p
INNER JOIN dbo.uv_coordinador_identidad ci ON ci.id = p.idCoordinador
WHERE ci.estaActivoUsuario = 1 AND p.estaActivoPrograma = 1
ORDER BY p.id;
DECLARE @uAdmin UNIQUEIDENTIFIER = (SELECT TOP 1 a.idUsuario FROM dbo.uv_administrador a WHERE a.idInstitucion = @idInstitucion ORDER BY a.id);
DECLARE @idDecano UNIQUEIDENTIFIER, @uDecano UNIQUEIDENTIFIER;
SELECT TOP 1 @idDecano = d.id, @uDecano = d.idUsuario FROM dbo.uv_facultad f INNER JOIN dbo.uv_decano d ON d.id = f.idDecano WHERE f.idInstitucion = @idInstitucion;
IF @tipoCC IS NULL OR @idPrograma IS NULL OR @uCoord IS NULL OR @uAdmin IS NULL OR @idDecano IS NULL
    THROW 52401, 'TEST FAILED: CULM001_D4 faltan fixtures del seed (tipo de documento, programa con coordinador, administrador, decano).', 1;

DECLARE @dominio NVARCHAR(255) = dbo.ufn_obtener_parametro('REGISTRO', 'DOMINIO_CORREO_ESTUDIANTE');
DECLARE @hash NVARCHAR(500) = N'HashBackend_QaAdmision1234567890';
DECLARE @mu NVARCHAR(4000), @mt NVARCHAR(4000), @ok BIT, @corr UNIQUEIDENTIFIER, @n INT;
DECLARE @correo1 NVARCHAR(255) = CONCAT(N'qa.d4.uno', @dominio), @correo2 NVARCHAR(255) = CONCAT(N'qa.d4.dos', @dominio);
DECLARE @uAdmin2 UNIQUEIDENTIFIER, @inst2 UNIQUEIDENTIFIER = NEWID();
DECLARE @uExistente UNIQUEIDENTIFIER;
DECLARE @idEst1 UNIQUEIDENTIFIER, @uEst1 UNIQUEIDENTIFIER;
DECLARE @msgEsperado NVARCHAR(4000), @progInexistente UNIQUEIDENTIFIER = NEWID(), @docDecano INT;

CREATE TABLE #a (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000),
                 estadoResultado BIT, idUsuario UNIQUEIDENTIFIER, idEstudiante UNIQUEIDENTIFIER, esUsuarioNuevo BIT, esEstudianteNuevo BIT);
CREATE TABLE #c (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000),
                 estadoResultado BIT, idUsuario UNIQUEIDENTIFIER, correo NVARCHAR(100), numeroIdentificacion INT);
CREATE TABLE #p (id UNIQUEIDENTIFIER, nombre NVARCHAR(300), idFacultad UNIQUEIDENTIFIER, nombreFacultad NVARCHAR(300), totalRegistros INT);

BEGIN TRANSACTION;
BEGIN TRY
    -- Segundo administrador de OTRA institucion (para los casos fuera de ambito)
    INSERT dbo.Institucion (id, nombre, estado) VALUES (@inst2, N'QA D4 Institucion 2', 1);
    SET @corr = NEWID();
    EXEC dbo.usp_sincronizar_usuario_interno @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 916400090,
        @primerApellido = N'Admin', @segundoApellido = N'Dos', @primerNombre = N'Qa', @segundoNombre = N'',
        @correo = N'admin2.qa.d4@test.local', @password = @hash, @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    EXEC #d4_expect 'FIXTURE_ADMIN2', @ok;
    SELECT @uAdmin2 = id FROM dbo.Usuario WHERE correo = N'admin2.qa.d4@test.local';
    INSERT dbo.Administrador (id, usuario, institucion) VALUES (NEWID(), @uAdmin2, @inst2);

    -- Persona que ya existe como Usuario (sin perfil de estudiante) con correo NO institucional
    EXEC dbo.usp_sincronizar_usuario_interno @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 916400020,
        @primerApellido = N'Existente', @segundoApellido = N'Qa', @primerNombre = N'Pedro', @segundoNombre = N'',
        @correo = N'existente.qa.d4@test.local', @password = @hash, @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    EXEC #d4_expect 'FIXTURE_EXISTENTE', @ok;
    SELECT @uExistente = id FROM dbo.Usuario WHERE correo = N'existente.qa.d4@test.local';

    -- ---------------------------------------------------------------- D4-01 alta nueva, sin matricula en grupos
    SET @corr = NEWID();
    INSERT #a EXEC dbo.usp_admitir_estudiante @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 916400001,
        @primerNombre = N'Ana', @segundoNombre = NULL, @primerApellido = N'Admitida', @segundoApellido = NULL,
        @correo = @correo1, @password = @hash, @idPrograma = @idPrograma, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    SELECT @uEst1 = u.id, @idEst1 = e.id FROM dbo.Usuario u LEFT JOIN dbo.Estudiante e ON e.usuario = u.id WHERE u.correo = @correo1;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #a WHERE estadoResultado = 1 AND esUsuarioNuevo = 1 AND esEstudianteNuevo = 1
                          AND idUsuario = @uEst1 AND idEstudiante = @idEst1)
                  AND @idEst1 IS NOT NULL
                  AND EXISTS (SELECT 1 FROM dbo.EstudiantePrograma WHERE estudiante = @idEst1 AND programa = @idPrograma)
                  AND NOT EXISTS (SELECT 1 FROM dbo.EstudianteGrupo WHERE estudiante = @idEst1), 1, 0);
    EXEC #d4_expect 'D4_01_ALTA_NUEVA_SIN_MATRICULA', @ok;
    PRINT 'TEST_PASS:CULM001_D4_01_ALTA_NUEVA';

    -- ---------------------------------------------------------------- D4-02 persona existente (mismo documento y correo)
    TRUNCATE TABLE #a;
    SET @corr = NEWID();
    INSERT #a EXEC dbo.usp_admitir_estudiante @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 916400020,
        @primerNombre = N'Pedro', @segundoNombre = NULL, @primerApellido = N'Existente', @segundoApellido = N'Qa',
        @correo = N'existente.qa.d4@test.local', @password = NULL, @idPrograma = @idPrograma, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #a WHERE estadoResultado = 1 AND esUsuarioNuevo = 0 AND esEstudianteNuevo = 1 AND idUsuario = @uExistente)
                  AND (SELECT COUNT(*) FROM dbo.Usuario WHERE numeroIdentificacion = 916400020) = 1
                  AND (SELECT COUNT(*) FROM dbo.Estudiante WHERE usuario = @uExistente) = 1
                  AND EXISTS (SELECT 1 FROM dbo.Estudiante e INNER JOIN dbo.EstudiantePrograma ep ON ep.estudiante = e.id
                              WHERE e.usuario = @uExistente AND ep.programa = @idPrograma), 1, 0);
    EXEC #d4_expect 'D4_02_PERSONA_EXISTENTE_PERFIL_ES', @ok;
    PRINT 'TEST_PASS:CULM001_D4_02_PERSONA_EXISTENTE';

    -- ---------------------------------------------------------------- D4-03 repeticion => ADS_002 (sin duplicar)
    TRUNCATE TABLE #a;
    SET @corr = NEWID();
    INSERT #a EXEC dbo.usp_admitir_estudiante @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 916400001,
        @primerNombre = N'Ana', @segundoNombre = NULL, @primerApellido = N'Admitida', @segundoApellido = NULL,
        @correo = @correo1, @password = @hash, @idPrograma = @idPrograma, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    SELECT @msgEsperado = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'ADS_002';
    SET @ok = IIF(@msgEsperado IS NOT NULL
                  AND EXISTS (SELECT 1 FROM #a WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msgEsperado
                              AND idUsuario = @uEst1 AND idEstudiante = @idEst1 AND esUsuarioNuevo = 0 AND esEstudianteNuevo = 0)
                  AND (SELECT COUNT(*) FROM dbo.EstudiantePrograma WHERE estudiante = @idEst1 AND programa = @idPrograma) = 1, 1, 0);
    EXEC #d4_expect 'D4_03_REPETIDO_ADS_002', @ok;
    PRINT 'TEST_PASS:CULM001_D4_03_YA_ADMITIDO';

    -- ---------------------------------------------------------------- D4-04 documento y correo de personas distintas => ADS_004
    TRUNCATE TABLE #a;
    SET @corr = NEWID();
    INSERT #a EXEC dbo.usp_admitir_estudiante @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 916400001,
        @primerNombre = N'Ana', @segundoNombre = NULL, @primerApellido = N'Admitida', @segundoApellido = NULL,
        @correo = @correo2, @password = @hash, @idPrograma = @idPrograma, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    SELECT @msgEsperado = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'ADS_004';
    SET @ok = IIF(@msgEsperado IS NOT NULL AND EXISTS (SELECT 1 FROM #a WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msgEsperado)
                  AND NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo = @correo2), 1, 0);
    EXEC #d4_expect 'D4_04_DOCUMENTO_DISTINTO_ADS_004', @ok;
    TRUNCATE TABLE #a;
    SET @corr = NEWID();
    INSERT #a EXEC dbo.usp_admitir_estudiante @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 916400077,
        @primerNombre = N'Ana', @segundoNombre = NULL, @primerApellido = N'Admitida', @segundoApellido = NULL,
        @correo = @correo1, @password = @hash, @idPrograma = @idPrograma, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #a WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msgEsperado)
                  AND NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE numeroIdentificacion = 916400077), 1, 0);
    EXEC #d4_expect 'D4_04_CORREO_DISTINTO_ADS_004', @ok;
    PRINT 'TEST_PASS:CULM001_D4_04_PERSONAS_DISTINTAS';

    -- ---------------------------------------------------------------- D4-05 programa inexistente o de otra institucion => ADS_003
    TRUNCATE TABLE #a;
    SET @corr = NEWID();
    INSERT #a EXEC dbo.usp_admitir_estudiante @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 916400003,
        @primerNombre = N'Ana', @segundoNombre = NULL, @primerApellido = N'SinPrograma', @segundoApellido = NULL,
        @correo = @correo2, @password = @hash, @idPrograma = @progInexistente, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    SELECT @msgEsperado = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'ADS_003';
    SET @ok = IIF(@msgEsperado IS NOT NULL AND EXISTS (SELECT 1 FROM #a WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msgEsperado)
                  AND NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo = @correo2), 1, 0);
    EXEC #d4_expect 'D4_05_PROGRAMA_INEXISTENTE_ADS_003', @ok;
    TRUNCATE TABLE #a;
    SET @corr = NEWID();
    INSERT #a EXEC dbo.usp_admitir_estudiante @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 916400003,
        @primerNombre = N'Ana', @segundoNombre = NULL, @primerApellido = N'SinPrograma', @segundoApellido = NULL,
        @correo = @correo2, @password = @hash, @idPrograma = @idPrograma, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin2;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #a WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msgEsperado)
                  AND NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo = @correo2), 1, 0);
    EXEC #d4_expect 'D4_05_PROGRAMA_DE_OTRA_INSTITUCION_ADS_003', @ok;
    PRINT 'TEST_PASS:CULM001_D4_05_PROGRAMA_FUERA_DE_AMBITO';

    -- ---------------------------------------------------------------- D4-06 correo no institucional en alta nueva => ADS_005
    TRUNCATE TABLE #a;
    SET @corr = NEWID();
    INSERT #a EXEC dbo.usp_admitir_estudiante @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 916400004,
        @primerNombre = N'Ana', @segundoNombre = NULL, @primerApellido = N'Gmail', @segundoApellido = NULL,
        @correo = N'qa.d4.externo@gmail.com', @password = @hash, @idPrograma = @idPrograma, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #a WHERE estadoResultado = 0 AND mensajeUsuarioResultado LIKE N'El correo debe ser institucional%'
                          AND mensajeUsuarioResultado LIKE CONCAT(N'%', @dominio, N'%'))
                  AND NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE numeroIdentificacion = 916400004), 1, 0);
    EXEC #d4_expect 'D4_06_CORREO_NO_INSTITUCIONAL_ADS_005', @ok;
    PRINT 'TEST_PASS:CULM001_D4_06_CORREO_INSTITUCIONAL';

    -- ---------------------------------------------------------------- D4-07 alta nueva sin contrasena => ADS_006
    TRUNCATE TABLE #a;
    SET @corr = NEWID();
    INSERT #a EXEC dbo.usp_admitir_estudiante @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 916400005,
        @primerNombre = N'Ana', @segundoNombre = NULL, @primerApellido = N'SinClave', @segundoApellido = NULL,
        @correo = @correo2, @password = NULL, @idPrograma = @idPrograma, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    SELECT @msgEsperado = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'ADS_006';
    SET @ok = IIF(@msgEsperado IS NOT NULL AND EXISTS (SELECT 1 FROM #a WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msgEsperado)
                  AND NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo = @correo2), 1, 0);
    EXEC #d4_expect 'D4_07_SIN_CONTRASENA_ADS_006', @ok;
    TRUNCATE TABLE #a;
    SET @corr = NEWID();
    INSERT #a EXEC dbo.usp_admitir_estudiante @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 916400005,
        @primerNombre = N'Ana', @segundoNombre = NULL, @primerApellido = N'SinClave', @segundoApellido = NULL,
        @correo = @correo2, @password = N'   ', @idPrograma = @idPrograma, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #a WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msgEsperado), 1, 0);
    EXEC #d4_expect 'D4_07_CONTRASENA_EN_BLANCO_ADS_006', @ok;
    PRINT 'TEST_PASS:CULM001_D4_07_CONTRASENA_INICIAL';

    -- ---------------------------------------------------------------- D4-08 otros perfiles no admiten (RBAC)
    TRUNCATE TABLE #a;
    SET @corr = NEWID();
    INSERT #a EXEC dbo.usp_admitir_estudiante @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 916400006,
        @primerNombre = N'Ana', @segundoNombre = NULL, @primerApellido = N'Coord', @segundoApellido = NULL,
        @correo = @correo2, @password = @hash, @idPrograma = @idPrograma, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #a WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SEC_001|%')
                  AND NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo = @correo2), 1, 0);
    EXEC #d4_expect 'D4_08_COORDINADOR_NO_ADMITE', @ok;
    PRINT 'TEST_PASS:CULM001_D4_08_RBAC';

    -- ---------------------------------------------------------------- D4-10 correccion de identidad por jerarquia
    -- ADMINISTRADOR de su institucion corrige a un estudiante de un programa de su institucion
    SET @corr = NEWID();
    INSERT #c EXEC dbo.usp_corregir_identidad_usuario @tipoUsuario = 'ESTUDIANTE', @idRegistro = @idEst1, @idTipoIdIdentificacion = @tipoCC,
        @numeroIdentificacion = 916400001, @primerNombre = N'Anita', @primerApellido = N'Admitida', @motivo = N'QA D4 correccion por administrador',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #c WHERE estadoResultado = 1 AND idUsuario = @uEst1)
                  AND EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @uEst1 AND primerNombre = N'ANITA'), 1, 0);
    EXEC #d4_expect 'D4_10_ADMIN_CORRIGE_ESTUDIANTE_DE_SU_INSTITUCION', @ok;
    -- ADMINISTRADOR de otra institucion: indistinguible de inexistente (GEN_001)
    TRUNCATE TABLE #c;
    SET @corr = NEWID();
    INSERT #c EXEC dbo.usp_corregir_identidad_usuario @tipoUsuario = 'ESTUDIANTE', @idRegistro = @idEst1, @idTipoIdIdentificacion = @tipoCC,
        @numeroIdentificacion = 916400001, @primerNombre = N'Hackeado', @primerApellido = N'Admitida', @motivo = N'QA D4 fuera de ambito',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin2;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #c WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=GEN_001|%')
                  AND EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @uEst1 AND primerNombre = N'ANITA'), 1, 0);
    EXEC #d4_expect 'D4_10_ADMIN_DE_OTRA_INSTITUCION_GEN_001', @ok;
    -- COORDINADOR del programa sigue corrigiendo (regla actual)
    TRUNCATE TABLE #c;
    SET @corr = NEWID();
    INSERT #c EXEC dbo.usp_corregir_identidad_usuario @tipoUsuario = 'ESTUDIANTE', @idRegistro = @idEst1, @idTipoIdIdentificacion = @tipoCC,
        @numeroIdentificacion = 916400001, @primerNombre = N'Ana', @primerApellido = N'Admitida', @motivo = N'QA D4 correccion por coordinador',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #c WHERE estadoResultado = 1) AND EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @uEst1 AND primerNombre = N'ANA'), 1, 0);
    EXEC #d4_expect 'D4_10_COORDINADOR_SIGUE_CORRIGIENDO', @ok;
    -- DECANO corregido por ADMINISTRADOR sigue igual; un estudiante no puede ser corregido por un decano
    TRUNCATE TABLE #c;
    SET @corr = NEWID();
    SELECT @docDecano = numeroIdentificacion FROM dbo.Usuario WHERE id = @uDecano;
    INSERT #c EXEC dbo.usp_corregir_identidad_usuario @tipoUsuario = 'DECANO', @idRegistro = @idDecano, @idTipoIdIdentificacion = @tipoCC,
        @numeroIdentificacion = @docDecano, @primerNombre = N'Decano',
        @primerApellido = N'Qa', @motivo = N'QA D4 decano por administrador', @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #c WHERE estadoResultado = 1), 1, 0);
    EXEC #d4_expect 'D4_10_DECANO_POR_ADMINISTRADOR_SIGUE_IGUAL', @ok;
    TRUNCATE TABLE #c;
    SET @corr = NEWID();
    INSERT #c EXEC dbo.usp_corregir_identidad_usuario @tipoUsuario = 'ESTUDIANTE', @idRegistro = @idEst1, @idTipoIdIdentificacion = @tipoCC,
        @numeroIdentificacion = 916400001, @primerNombre = N'Ana', @primerApellido = N'Admitida', @motivo = N'QA D4 decano no corrige estudiantes',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uDecano;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #c WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SEC_001|%'), 1, 0);
    EXEC #d4_expect 'D4_10_DECANO_NO_CORRIGE_ESTUDIANTES', @ok;
    -- Los perfiles permitidos viven en parametros: el SP no lleva literales de perfil
    SET @ok = IIF(EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_corregir_identidad_usuario')
                          AND definition LIKE N'%PERFILES_CORRECCION_ESTUDIANTE%' AND definition LIKE N'%PERFILES_CORRECCION_DECANO%'
                          AND definition NOT LIKE N'%''COORDINADOR''%' AND definition NOT LIKE N'%''ADMINISTRADOR''%')
                  AND dbo.ufn_obtener_parametro('IDENTIDAD', 'PERFILES_CORRECCION_ESTUDIANTE') <> N''
                  AND dbo.ufn_obtener_parametro('IDENTIDAD', 'PERFILES_CORRECCION_DECANO') <> N'', 1, 0);
    EXEC #d4_expect 'D4_10_SIN_LITERALES_DE_PERFIL', @ok;
    PRINT 'TEST_PASS:CULM001_D4_10_CORRECCION_POR_JERARQUIA';

    -- ---------------------------------------------------------------- D4-11 programas paginados de la institucion del administrador
    SET @corr = NEWID();
    INSERT #p EXEC dbo.usp_consultar_programas_institucion_paginado @idUsuarioEjecutor = @uAdmin, @idCorrelacion = @corr,
        @numeroPagina = 1, @tamanoPagina = 100, @texto = NULL, @idFacultad = NULL;
    SET @n = (SELECT COUNT(*) FROM dbo.uv_programa WHERE idInstitucion = @idInstitucion AND estaActivoPrograma = 1);
    SET @ok = IIF(@n >= 1 AND (SELECT COUNT(*) FROM #p) = @n AND NOT EXISTS (SELECT 1 FROM #p WHERE totalRegistros <> @n)
                  AND EXISTS (SELECT 1 FROM #p WHERE id = @idPrograma)
                  AND NOT EXISTS (SELECT 1 FROM #p x LEFT JOIN dbo.uv_programa v ON v.id = x.id AND v.idInstitucion = @idInstitucion WHERE v.id IS NULL), 1, 0);
    EXEC #d4_expect 'D4_11_PROGRAMAS_DE_SU_INSTITUCION', @ok;
    TRUNCATE TABLE #p;
    SET @corr = NEWID();
    INSERT #p EXEC dbo.usp_consultar_programas_institucion_paginado @idUsuarioEjecutor = @uAdmin2, @idCorrelacion = @corr,
        @numeroPagina = 1, @tamanoPagina = 100, @texto = NULL, @idFacultad = NULL;
    SET @ok = IIF(NOT EXISTS (SELECT 1 FROM #p), 1, 0);
    EXEC #d4_expect 'D4_11_OTRA_INSTITUCION_CERO_PROGRAMAS', @ok;
    TRUNCATE TABLE #p;
    SET @corr = NEWID();
    INSERT #p EXEC dbo.usp_consultar_programas_institucion_paginado @idUsuarioEjecutor = @uAdmin, @idCorrelacion = @corr,
        @numeroPagina = 1, @tamanoPagina = 100, @texto = N'#sin-coincidencia-d4#', @idFacultad = NULL;
    SET @ok = IIF(NOT EXISTS (SELECT 1 FROM #p), 1, 0);
    EXEC #d4_expect 'D4_11_FILTRO_TEXTO', @ok;
    PRINT 'TEST_PASS:CULM001_D4_11_PROGRAMAS_PAGINADOS';

    ROLLBACK TRANSACTION;

    -- Errores de validacion de la consulta (THROW 51000): fuera de la transaccion (XACT_ABORT del SP)
    DECLARE @errNum INT = NULL;
    BEGIN TRY
        SET @corr = NEWID();
        INSERT #p EXEC dbo.usp_consultar_programas_institucion_paginado @idUsuarioEjecutor = @uCoord, @idCorrelacion = @corr,
            @numeroPagina = 1, @tamanoPagina = 100, @texto = NULL, @idFacultad = NULL;
    END TRY
    BEGIN CATCH
        SET @errNum = ERROR_NUMBER();
    END CATCH
    SET @ok = IIF(@errNum = 51000, 1, 0);
    EXEC #d4_expect 'D4_11_COORDINADOR_RECHAZADO', @ok;
    SET @errNum = NULL;
    BEGIN TRY
        SET @corr = NEWID();
        INSERT #p EXEC dbo.usp_consultar_programas_institucion_paginado @idUsuarioEjecutor = @uAdmin, @idCorrelacion = @corr,
            @numeroPagina = 1, @tamanoPagina = 0, @texto = NULL, @idFacultad = NULL;
    END TRY
    BEGIN CATCH
        SET @errNum = ERROR_NUMBER();
    END CATCH
    SET @ok = IIF(@errNum = 51000, 1, 0);
    EXEC #d4_expect 'D4_11_PAGINACION_INVALIDA', @ok;
    PRINT 'TEST_PASS:CULM001_D4_11_ERRORES_DE_VALIDACION';
END TRY
BEGIN CATCH
    DECLARE @fallo NVARCHAR(2000) = CONCAT(ERROR_MESSAGE(), N' (linea ', ERROR_LINE(), N')');
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DROP TABLE IF EXISTS #a; DROP TABLE IF EXISTS #c; DROP TABLE IF EXISTS #p;
    THROW 52402, @fallo, 1;
END CATCH
DROP TABLE IF EXISTS #a; DROP TABLE IF EXISTS #c; DROP TABLE IF EXISTS #p;
GO

-- ---------------------------------------------------------------- D4-09 fallo DESPUES de crear el Usuario => sin filas parciales
-- Un disparador INSTEAD OF temporal (solo falla para el correo de la prueba) hace fallar el vinculo con el programa cuando el
-- Usuario y el Estudiante ya se crearon. Fuera de transaccion: el SP es dueno de la suya y debe terminar con @@TRANCOUNT = 0.
DECLARE @tipoCC9 UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @prog9 UNIQUEIDENTIFIER, @inst9 UNIQUEIDENTIFIER;
SELECT TOP 1 @prog9 = p.id, @inst9 = p.idInstitucion FROM dbo.uv_programa p WHERE p.estaActivoPrograma = 1 ORDER BY p.id;
DECLARE @admin9 UNIQUEIDENTIFIER = (SELECT TOP 1 a.idUsuario FROM dbo.uv_administrador a WHERE a.idInstitucion = @inst9 ORDER BY a.id);
DECLARE @dominio9 NVARCHAR(255) = dbo.ufn_obtener_parametro('REGISTRO', 'DOMINIO_CORREO_ESTUDIANTE');
DECLARE @correo9 NVARCHAR(255) = CONCAT(N'qa.d4.fallo', @dominio9);
DECLARE @corr9 UNIQUEIDENTIFIER = NEWID(), @ok9 BIT;
IF @prog9 IS NULL OR @admin9 IS NULL OR @tipoCC9 IS NULL
    THROW 52403, 'TEST FAILED: CULM001_D4_09 faltan fixtures del seed.', 1;
IF OBJECT_ID(N'dbo.usp_admitir_estudiante', N'P') IS NULL
    THROW 52404, 'TEST FAILED: CULM001_D4_09 usp_admitir_estudiante ausente.', 1;
DECLARE @sqlTrigger NVARCHAR(MAX) = N'
CREATE TRIGGER dbo.tr_qa_d4_fallo ON dbo.EstudiantePrograma INSTEAD OF INSERT AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM inserted i INNER JOIN dbo.Estudiante e ON e.id = i.estudiante INNER JOIN dbo.Usuario u ON u.id = e.usuario
               WHERE u.correo = N''' + @correo9 + N''')
        THROW 52409, ''QA D4: fallo provocado despues de crear el Usuario'', 1;
    INSERT dbo.EstudiantePrograma (id, estudiante, programa) SELECT id, estudiante, programa FROM inserted;
END';
BEGIN TRY
    EXEC (@sqlTrigger);
    -- EXEC directo: un ROLLBACK del SP dentro de INSERT ... EXEC lo prohibe SQL Server (3915).
    EXEC dbo.usp_admitir_estudiante @idTipoIdIdentificacion = @tipoCC9, @numeroIdentificacion = 916400009,
        @primerNombre = N'Ana', @segundoNombre = NULL, @primerApellido = N'Fallo', @segundoApellido = NULL,
        @correo = @correo9, @password = N'HashBackend_QaAdmision1234567890', @idPrograma = @prog9, @idCorrelacion = @corr9, @idUsuarioEjecutor = @admin9;
    SET @ok9 = IIF(NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo = @correo9 OR numeroIdentificacion = 916400009)
                   AND NOT EXISTS (SELECT 1 FROM dbo.Estudiante e INNER JOIN dbo.Usuario u ON u.id = e.usuario WHERE u.correo = @correo9)
                   AND @@TRANCOUNT = 0, 1, 0);
END TRY
BEGIN CATCH
    SET @ok9 = 0;
END CATCH
IF OBJECT_ID(N'dbo.tr_qa_d4_fallo', N'TR') IS NOT NULL DROP TRIGGER dbo.tr_qa_d4_fallo;
-- Limpieza defensiva si el SP hubiera dejado filas parciales (la asercion de abajo falla igual)
DELETE ep FROM dbo.EstudiantePrograma ep INNER JOIN dbo.Estudiante e ON e.id = ep.estudiante INNER JOIN dbo.Usuario u ON u.id = e.usuario WHERE u.correo = @correo9;
DELETE e FROM dbo.Estudiante e INNER JOIN dbo.Usuario u ON u.id = e.usuario WHERE u.correo = @correo9;
DELETE FROM dbo.Usuario WHERE correo = @correo9;
IF @ok9 IS NULL OR @ok9 <> 1
    THROW 52405, 'TEST FAILED: CULM001_D4_09_FALLO_TRAS_CREAR_USUARIO_SIN_FILAS_PARCIALES', 1;
PRINT 'TEST_PASS:CULM001_D4_09_SIN_FILAS_PARCIALES';
GO
DROP PROCEDURE #d4_expect;
GO
