USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- CULM-001 D.6 (CONTRACT v2 §7.3, D6-01..D6-06): usp_consultar_auditoria_eventos_paginado gana al final
-- @idCorrelacionEvento y @soloAdministracion. @soloAsistencia conserva su defecto 1; la combinacion 1/1 se rechaza (AUD_002);
-- con mas de una Institucion activa la consulta falla con AUD_001 y sin filas ([SUPUESTO-D-16]). Todo en una transaccion revertida.
PRINT 'TEST START: test_culm001_d6_auditoria (CULM-001 D.6, HU172)';

IF NOT EXISTS (SELECT 1 FROM sys.parameters WHERE object_id = OBJECT_ID(N'dbo.usp_consultar_auditoria_eventos_paginado') AND name = N'@idCorrelacionEvento')
   OR NOT EXISTS (SELECT 1 FROM sys.parameters WHERE object_id = OBJECT_ID(N'dbo.usp_consultar_auditoria_eventos_paginado') AND name = N'@soloAdministracion')
    THROW 57600, 'TEST FAILED CULM001_D6_00: usp_consultar_auditoria_eventos_paginado no tiene @idCorrelacionEvento y @soloAdministracion.', 1;
IF dbo.ufn_obtener_parametro('AUDITORIA', 'PREFIJO_RUTA_ADMINISTRACION') <> N'/api/v1/admin/'
    THROW 57601, 'TEST FAILED CULM001_D6_00: falta AUDITORIA/PREFIJO_RUTA_ADMINISTRACION = /api/v1/admin/.', 1;
IF EXISTS (SELECT 1 FROM (VALUES ('AUD_001'), ('AUD_002')) c(codigo)
           WHERE NOT EXISTS (SELECT 1 FROM dbo.uv_mensaje_usuario u WHERE u.codigo = c.codigo)
              OR NOT EXISTS (SELECT 1 FROM dbo.uv_mensaje_tecnico t WHERE t.codigo = c.codigo))
    THROW 57602, 'TEST FAILED CULM001_D6_00: faltan los mensajes AUD_001 y AUD_002 (usuario y tecnico).', 1;
PRINT 'TEST_PASS:CULM001_D6_00_OBJETOS_Y_SEMILLAS';
GO

DECLARE @admin UNIQUEIDENTIFIER = (SELECT TOP 1 a.usuario FROM dbo.Administrador a JOIN dbo.uv_usuario u ON u.id = a.usuario WHERE u.estaActivoUsuario = 1 ORDER BY a.id);
DECLARE @coord UNIQUEIDENTIFIER = (SELECT TOP 1 ci.idUsuario FROM dbo.uv_coordinador_identidad ci WHERE ci.estaActivoUsuario = 1 AND ci.estaActivoRolCoordinador = 1 ORDER BY ci.id);
IF @admin IS NULL OR @coord IS NULL THROW 57610, 'TEST FAILED CULM001_D6: faltan fixtures del seed (administrador y coordinador).', 1;

CREATE TABLE #d6 (id UNIQUEIDENTIFIER, occurredAt DATETIMEOFFSET(7), actorId NVARCHAR(240), actorType VARCHAR(20), nombreActor NVARCHAR(400), action VARCHAR(120),
    resourceType VARCHAR(120), resourceId NVARCHAR(240), result VARCHAR(20), correlationId UNIQUEIDENTIFIER, httpMethod VARCHAR(16), path NVARCHAR(240),
    httpStatus SMALLINT, clientIp VARCHAR(45), errorCode VARCHAR(120), metadata NVARCHAR(MAX), esAccionAsistencia BIT, totalRegistros INT);
DECLARE @corr UNIQUEIDENTIFIER = NEWID(), @corrA UNIQUEIDENTIFIER = NEWID(), @corrB UNIQUEIDENTIFIER = NEWID();
DECLARE @desde DATETIMEOFFSET(7) = DATEADD(DAY, -1, SYSDATETIMEOFFSET()), @hasta DATETIMEOFFSET(7) = DATEADD(DAY, 1, SYSDATETIMEOFFSET());
DECLARE @err NVARCHAR(4000);

BEGIN TRANSACTION;
BEGIN TRY
    -- 4 eventos del fixture (resourceType CULM1D6): 2 administrativos (correlaciones A y B), 1 de asistencia (A), 1 de otra ruta no administrativa (B)
    INSERT INTO dbo.AuditoriaEvento (id, occurredAt, actorId, actorType, action, resourceType, resourceId, result, correlationId, httpMethod, path, httpStatus, metadata)
    VALUES (NEWID(), SYSDATETIMEOFFSET(), CONVERT(NVARCHAR(120), @admin), 'USER', 'ACTUALIZAR_PARAMETRO', 'CULM1D6', N'P1', 'SUCCESS', @corrA, 'PUT', N'/api/v1/admin/parametros/P1', 200, N'{"clave":"TOLERANCIA_MINUTOS"}'),
           (NEWID(), SYSDATETIMEOFFSET(), CONVERT(NVARCHAR(120), @admin), 'USER', 'CREAR_FACULTAD', 'CULM1D6', N'F1', 'FAILURE', @corrB, 'POST', N'/api/v1/admin/facultades', 400, NULL),
           (NEWID(), SYSDATETIMEOFFSET(), CONVERT(NVARCHAR(120), @admin), 'USER', 'REGISTRAR_ASISTENCIA', 'CULM1D6', N'S1', 'SUCCESS', @corrA, 'POST', N'/api/v1/asistencias/lote', 200, NULL),
           (NEWID(), SYSDATETIMEOFFSET(), CONVERT(NVARCHAR(120), @admin), 'USER', 'CONSULTAR_ALGO', 'CULM1D6', N'X1', 'SUCCESS', @corrB, 'GET', N'/api/v1/docente/grupos', 200, NULL);

    -- D6-04: sin los filtros nuevos el comportamiento es el de antes (solo acciones de asistencia por defecto)
    INSERT INTO #d6 EXEC dbo.usp_consultar_auditoria_eventos_paginado @idUsuarioEjecutor = @admin, @idCorrelacion = @corr, @numeroPagina = 1, @tamanoPagina = 50,
        @desdeUtc = @desde, @hastaUtc = @hasta, @tipoRecurso = 'CULM1D6';
    IF (SELECT COUNT(*) FROM #d6) <> 1 OR NOT EXISTS (SELECT 1 FROM #d6 WHERE action = 'REGISTRAR_ASISTENCIA' AND esAccionAsistencia = 1 AND correlationId = @corrA)
        THROW 57620, 'TEST FAILED CULM001_D6_04: sin filtros nuevos y con el defecto de @soloAsistencia solo debe devolver las acciones de asistencia.', 1;
    TRUNCATE TABLE #d6;
    INSERT INTO #d6 EXEC dbo.usp_consultar_auditoria_eventos_paginado @idUsuarioEjecutor = @admin, @idCorrelacion = @corr, @numeroPagina = 1, @tamanoPagina = 50,
        @desdeUtc = @desde, @hastaUtc = @hasta, @tipoRecurso = 'CULM1D6', @soloAsistencia = 0;
    IF (SELECT COUNT(*) FROM #d6) <> 4 OR (SELECT MIN(totalRegistros) FROM #d6) <> 4
        THROW 57621, 'TEST FAILED CULM001_D6_04: @soloAsistencia = 0 sin filtros nuevos devuelve los 4 eventos del fixture.', 1;
    TRUNCATE TABLE #d6;
    PRINT 'TEST_PASS:CULM001_D6_04_SIN_FILTROS_NUEVOS';

    -- D6-01: filtro por correlacion
    INSERT INTO #d6 EXEC dbo.usp_consultar_auditoria_eventos_paginado @idUsuarioEjecutor = @admin, @idCorrelacion = @corr, @numeroPagina = 1, @tamanoPagina = 50,
        @desdeUtc = @desde, @hastaUtc = @hasta, @soloAsistencia = 0, @idCorrelacionEvento = @corrA;
    IF (SELECT COUNT(*) FROM #d6) <> 2 OR EXISTS (SELECT 1 FROM #d6 WHERE correlationId <> @corrA) OR (SELECT MIN(totalRegistros) FROM #d6) <> 2
       OR NOT EXISTS (SELECT 1 FROM #d6 WHERE action = 'ACTUALIZAR_PARAMETRO' AND path = N'/api/v1/admin/parametros/P1' AND metadata LIKE N'%TOLERANCIA_MINUTOS%')
        THROW 57622, 'TEST FAILED CULM001_D6_01: @idCorrelacionEvento debe devolver solo los eventos de esa correlacion.', 1;
    TRUNCATE TABLE #d6;
    INSERT INTO #d6 EXEC dbo.usp_consultar_auditoria_eventos_paginado @idUsuarioEjecutor = @admin, @idCorrelacion = @corr, @numeroPagina = 1, @tamanoPagina = 50,
        @desdeUtc = @desde, @hastaUtc = @hasta, @soloAsistencia = 0, @idCorrelacionEvento = @corr;
    IF EXISTS (SELECT 1 FROM #d6) THROW 57623, 'TEST FAILED CULM001_D6_01: una correlacion sin eventos devuelve 0 filas.', 1;
    TRUNCATE TABLE #d6;
    PRINT 'TEST_PASS:CULM001_D6_01_FILTRO_CORRELACION';

    -- D6-02 / D6-05: solo rutas administrativas (prefijo AUDITORIA/PREFIJO_RUTA_ADMINISTRACION), pasando los dos parametros
    INSERT INTO #d6 EXEC dbo.usp_consultar_auditoria_eventos_paginado @idUsuarioEjecutor = @admin, @idCorrelacion = @corr, @numeroPagina = 1, @tamanoPagina = 50,
        @desdeUtc = @desde, @hastaUtc = @hasta, @tipoRecurso = 'CULM1D6', @soloAsistencia = 0, @soloAdministracion = 1;
    IF (SELECT COUNT(*) FROM #d6) <> 2 OR EXISTS (SELECT 1 FROM #d6 WHERE path NOT LIKE N'/api/v1/admin/%')
        THROW 57624, 'TEST FAILED CULM001_D6_02: @soloAdministracion = 1 con @soloAsistencia = 0 debe devolver solo rutas /api/v1/admin/.', 1;
    TRUNCATE TABLE #d6;
    PRINT 'TEST_PASS:CULM001_D6_02_SOLO_ADMINISTRACION';

    -- D6-03: los dos a 1 => error (AUD_002)
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #d6 EXEC dbo.usp_consultar_auditoria_eventos_paginado @idUsuarioEjecutor = @admin, @idCorrelacion = @corr, @numeroPagina = 1, @tamanoPagina = 50,
            @desdeUtc = @desde, @hastaUtc = @hasta, @soloAsistencia = 1, @soloAdministracion = 1;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH;
    IF @@TRANCOUNT = 0 THROW 57625, 'TEST FAILED CULM001_D6_03: el THROW cerro la transaccion de la prueba.', 1;
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=AUD[_]002|%' OR EXISTS (SELECT 1 FROM #d6)
        THROW 57626, 'TEST FAILED CULM001_D6_03: @soloAsistencia = 1 y @soloAdministracion = 1 deben fallar con AUD_002 y sin filas.', 1;
    PRINT 'TEST_PASS:CULM001_D6_03_FILTROS_EXCLUYENTES';

    -- D6-05: solo @soloAdministracion = 1 con el defecto de @soloAsistencia (1) => error: el llamador debe pasar los dos
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #d6 EXEC dbo.usp_consultar_auditoria_eventos_paginado @idUsuarioEjecutor = @admin, @idCorrelacion = @corr, @numeroPagina = 1, @tamanoPagina = 50,
            @desdeUtc = @desde, @hastaUtc = @hasta, @soloAdministracion = 1;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH;
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=AUD[_]002|%'
        THROW 57627, 'TEST FAILED CULM001_D6_05: solo @soloAdministracion = 1 (con el defecto de @soloAsistencia) debe fallar: el llamador debe pasar los dos parametros.', 1;
    PRINT 'TEST_PASS:CULM001_D6_05_PARAMETROS_EXPLICITOS';

    -- RBAC: el coordinador no consulta auditoria
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #d6 EXEC dbo.usp_consultar_auditoria_eventos_paginado @idUsuarioEjecutor = @coord, @idCorrelacion = @corr, @numeroPagina = 1, @tamanoPagina = 50,
            @desdeUtc = @desde, @hastaUtc = @hasta, @soloAsistencia = 0, @soloAdministracion = 1;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH;
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=SEC[_]001|%' THROW 57628, 'TEST FAILED CULM001_D6_RBAC: el coordinador no puede consultar auditoria (SEC_001).', 1;
    PRINT 'TEST_PASS:CULM001_D6_RBAC';

    -- D6-06 (R-4): una segunda Institucion activa => AUD_001 y ninguna fila
    INSERT INTO dbo.Institucion (id, nombre, estado) VALUES (NEWID(), N'CULM1 D6 segunda', 1);
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #d6 EXEC dbo.usp_consultar_auditoria_eventos_paginado @idUsuarioEjecutor = @admin, @idCorrelacion = @corr, @numeroPagina = 1, @tamanoPagina = 50,
            @desdeUtc = @desde, @hastaUtc = @hasta, @tipoRecurso = 'CULM1D6', @soloAsistencia = 0, @soloAdministracion = 1;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH;
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=AUD[_]001|%' OR EXISTS (SELECT 1 FROM #d6)
        THROW 57629, 'TEST FAILED CULM001_D6_06: con dos instituciones activas la consulta debe fallar con AUD_001 y sin filas.', 1;
    PRINT 'TEST_PASS:CULM001_D6_06_DOS_INSTITUCIONES';

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    DECLARE @msg NVARCHAR(4000) = ERROR_MESSAGE(), @num INT = ERROR_NUMBER();
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    IF @num BETWEEN 57600 AND 57699 THROW 57699, @msg, 1;
    SET @msg = CONCAT(N'TEST FAILED CULM001_D6: error inesperado ', @num, N': ', @msg);
    THROW 57698, @msg, 1;
END CATCH;
IF @@TRANCOUNT <> 0 THROW 57697, 'TEST FAILED CULM001_D6: la prueba dejo una transaccion abierta.', 1;
PRINT 'TEST_PASS:CULM001_D6_TRANCOUNT_ZERO';
PRINT 'TEST END: test_culm001_d6_auditoria';
GO
