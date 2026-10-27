USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
-- El indice unico filtrado de ArchivoSoporte exige QUOTED_IDENTIFIER ON para todo DML directo (sqlcmd lo deja OFF).
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ============================================================================
-- HU010/HU011 (consulta del estudiante): pruebas de usp_consultar_solicitudes_revision_estudiante (E-01..E-08 del
-- TEST_PLAN). Fixtures dentro de UNA transaccion con ROLLBACK final; los THROW de parametros nulos corren FUERA de
-- la transaccion (el SP usa XACT_ABORT ON). El estado de soporte distinto se simula cambiando, dentro de la
-- transaccion, el parametro ARCHIVO.ESTADO_ADJUNTO (CK_ArchivoSoporte_EstadoVinculo impide otro estado vinculado).
-- ============================================================================
IF OBJECT_ID('tempdb..#hu10_expect') IS NOT NULL DROP PROCEDURE #hu10_expect;
GO
CREATE PROCEDURE #hu10_expect @label VARCHAR(100), @ok BIT
AS
BEGIN
    IF @ok IS NULL OR @ok <> 1
    BEGIN
        DECLARE @mensaje NVARCHAR(400) = CONCAT('TEST FAILED: HU010_HU011_', @label);
        THROW 52330, @mensaje, 1;
    END
END;
GO

PRINT 'TEST START: test_consultas_reclamos_estudiante';

DECLARE @group UNIQUEIDENTIFIER, @teacher UNIQUEIDENTIFIER;
DECLARE @studentA UNIQUEIDENTIFIER, @studentB UNIQUEIDENTIFIER, @egA UNIQUEIDENTIFIER, @egB UNIQUEIDENTIFIER;
DECLARE @userA UNIQUEIDENTIFIER, @userB UNIQUEIDENTIFIER, @userT UNIQUEIDENTIFIER, @userCoord UNIQUEIDENTIFIER;
DECLARE @estadoP UNIQUEIDENTIFIER, @estadoA UNIQUEIDENTIFIER;

SELECT TOP 1 @group = g.id, @teacher = g.docente
FROM dbo.Grupo g
WHERE (SELECT COUNT(*) FROM dbo.uv_estudiante_grupo x WHERE x.idGrupo = g.id AND x.codigoEstadoEstudiante = 'A') >= 2
ORDER BY (SELECT COUNT(*) FROM dbo.uv_estudiante_grupo x WHERE x.idGrupo = g.id) ASC, g.id;

SELECT @studentA = z.idEstudiante, @egA = z.id FROM (
    SELECT idEstudiante, id, ROW_NUMBER() OVER (ORDER BY idEstudiante) rn
    FROM dbo.uv_estudiante_grupo WHERE idGrupo = @group AND codigoEstadoEstudiante = 'A') z WHERE z.rn = 1;
SELECT @studentB = z.idEstudiante, @egB = z.id FROM (
    SELECT idEstudiante, id, ROW_NUMBER() OVER (ORDER BY idEstudiante) rn
    FROM dbo.uv_estudiante_grupo WHERE idGrupo = @group AND codigoEstadoEstudiante = 'A') z WHERE z.rn = 2;

SELECT @userA = usuario FROM dbo.Estudiante WHERE id = @studentA;
SELECT @userB = usuario FROM dbo.Estudiante WHERE id = @studentB;
SELECT @userT = usuario FROM dbo.Docente WHERE id = @teacher;
SELECT TOP 1 @userCoord = usuario FROM dbo.Coordinador ORDER BY id;
SELECT @estadoP = id FROM dbo.Estado WHERE codigo = 'P';
SELECT @estadoA = id FROM dbo.Estado WHERE codigo = 'A';

IF @group IS NULL OR @studentA IS NULL OR @studentB IS NULL OR @egA IS NULL OR @egB IS NULL OR @userA IS NULL
   OR @userB IS NULL OR @userT IS NULL OR @userCoord IS NULL OR @estadoP IS NULL OR @estadoA IS NULL
    THROW 52331, 'TEST FAILED: HU010_HU011 fixture missing (seed data).', 1;

DECLARE @s1 UNIQUEIDENTIFIER = NEWID(), @s2 UNIQUEIDENTIFIER = NEWID();
DECLARE @n1 INT = 1 + (SELECT ISNULL(MAX(numero), 0) FROM dbo.Sesion WHERE grupo = @group);
DECLARE @c1 NVARCHAR(50) = LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8);
DECLARE @c2 NVARCHAR(50) = LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8);
DECLARE @inicio DATETIME2(7) = '2026-10-19T15:30:45.1234567';
DECLARE @a1 UNIQUEIDENTIFIER = NEWID(), @a2 UNIQUEIDENTIFIER = NEWID(), @b1 UNIQUEIDENTIFIER = NEWID();
DECLARE @reqA1 UNIQUEIDENTIFIER = NEWID(), @reqA2 UNIQUEIDENTIFIER = NEWID(), @reqB1 UNIQUEIDENTIFIER = NEWID();
DECLARE @file UNIQUEIDENTIFIER = NEWID();
DECLARE @sha CHAR(64) = LOWER(CONVERT(CHAR(64), HASHBYTES('SHA2_256', 'hu010-estudiante'), 2));
DECLARE @corr UNIQUEIDENTIFIER = NEWID(), @corrAdj UNIQUEIDENTIFIER = NEWID();
DECLARE @hoy DATE = CAST(SYSUTCDATETIME() AS DATE);
DECLARE @ok BIT, @cols NVARCHAR(MAX), @colsR2 NVARCHAR(MAX);

CREATE TABLE #r (idSolicitudRevisionAsistencia UNIQUEIDENTIFIER, nombreSolicitud NVARCHAR(50), fechaSolicitud DATE,
    codigoEstado NVARCHAR(5), nombreEstado NVARCHAR(100), justificacionSolicitud NVARCHAR(MAX), justificacionRespuesta NVARCHAR(MAX),
    idEstudiante UNIQUEIDENTIFIER, nombreEstudiante NVARCHAR(400), idSesion UNIQUEIDENTIFIER, numeroSesion INT,
    fechaHoraInicioSesion DATETIME2(7), procedenciaTemporalSesion NVARCHAR(24), idGrupo UNIQUEIDENTIFIER, codigoGrupo INT,
    nombreGrupo NVARCHAR(100), idAsignatura UNIQUEIDENTIFIER, codigoAsignatura NVARCHAR(100), nombreAsignatura NVARCHAR(100),
    idArchivoSoporte UNIQUEIDENTIFIER, nombreSoporte NVARCHAR(250), tipoContenidoSoporte VARCHAR(50),
    tamanioSoporteBytes BIGINT, fechaRegistroSoporteUtc DATETIME2(7), totalRegistros INT);

BEGIN TRANSACTION;
BEGIN TRY
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
    VALUES (@s1, N'QA HU010 S1', @n1, @c1, 1, @group, @inicio, DATEADD(HOUR, 1, @inicio)),
           (@s2, N'QA HU010 S2', @n1 + 1, @c2, 2, @group, DATEADD(DAY, 7, @inicio), DATEADD(HOUR, 1, DATEADD(DAY, 7, @inicio)));
    INSERT dbo.Asistencia (id, estudianteGrupo, sesion) VALUES (@a1, @egA, @s1), (@a2, @egA, @s2), (@b1, @egB, @s1);
    -- A tiene dos solicitudes (A1 de hoy pendiente con soporte; A2 de ayer aprobada con respuesta); B tiene una.
    INSERT dbo.SolicitudRevisionAsistencia (id, nombre, asistencia, fecha, estado, justificacionSolicitud, justificacionRespuesta)
    VALUES (@reqA1, N'QA-HU010-A1', @a1, @hoy, @estadoP, N'Cita medica QA', N''),
           (@reqA2, N'QA-HU010-A2', @a2, DATEADD(DAY, -1, @hoy), @estadoA, N'Calamidad QA', N'Aprobada por el docente'),
           (@reqB1, N'QA-HU010-B1', @b1, @hoy, @estadoP, N'Solicitud de B', N'');
    INSERT dbo.ArchivoSoporte (id, usuarioPropietario, solicitudRevisionAsistencia, nombreOriginal, tipoContenido, tamanioBytes,
        checksumSha256, estado, fechaRegistroUtc, fechaAdjuncionUtc, fechaCambioEstadoUtc, idCorrelacionRegistro, idCorrelacionAdjuncion)
    VALUES (@file, @userA, @reqA1, N'incapacidad-hu010.pdf', 'application/pdf', 2048, @sha, 'ATTACHED',
        SYSUTCDATETIME(), SYSUTCDATETIME(), SYSUTCDATETIME(), @corr, @corrAdj);

    -- -------------------------------------------------------- E-01 el estudiante A ve solo sus solicitudes, con soporte
    INSERT INTO #r EXEC dbo.usp_consultar_solicitudes_revision_estudiante
        @idUsuarioEjecutor = @userA, @idCorrelacion = @corr, @codigoEstado = NULL, @numeroPagina = 1, @tamanoPagina = 10;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r WHERE idSolicitudRevisionAsistencia = @reqA1 AND codigoEstado = N'P'
        AND idEstudiante = @studentA AND idSesion = @s1 AND idGrupo = @group AND idArchivoSoporte = @file
        AND nombreSoporte = N'incapacidad-hu010.pdf' AND tamanioSoporteBytes = 2048 AND fechaRegistroSoporteUtc IS NOT NULL
        AND justificacionSolicitud = N'Cita medica QA' AND totalRegistros = 2)
        AND EXISTS (SELECT 1 FROM #r WHERE idSolicitudRevisionAsistencia = @reqA2 AND codigoEstado = N'A'
            AND justificacionRespuesta = N'Aprobada por el docente' AND idArchivoSoporte IS NULL)
        AND NOT EXISTS (SELECT 1 FROM #r WHERE idSolicitudRevisionAsistencia = @reqB1)
        AND NOT EXISTS (SELECT 1 FROM #r WHERE idEstudiante <> @studentA), 1, 0);
    EXEC #hu10_expect 'E01_OWN_REQUESTS_WITH_SUPPORT', @ok;
    PRINT 'TEST_PASS:E-01';

    -- -------------------------------------------------------- E-02 orden por fecha descendente
    SET @ok = IIF((SELECT TOP 1 idSolicitudRevisionAsistencia FROM #r ORDER BY fechaSolicitud DESC) = @reqA1
        AND (SELECT COUNT(*) FROM #r) = 2, 1, 0);
    EXEC #hu10_expect 'E02_ORDER_BY_DATE_DESC', @ok;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_consultar_solicitudes_revision_estudiante
        @idUsuarioEjecutor = @userA, @idCorrelacion = @corr, @codigoEstado = NULL, @numeroPagina = 1, @tamanoPagina = 1;
    SET @ok = IIF((SELECT COUNT(*) FROM #r) = 1 AND EXISTS (SELECT 1 FROM #r WHERE idSolicitudRevisionAsistencia = @reqA1
        AND totalRegistros = 2), 1, 0);
    EXEC #hu10_expect 'E02_FIRST_PAGE_IS_NEWEST', @ok;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_consultar_solicitudes_revision_estudiante
        @idUsuarioEjecutor = @userA, @idCorrelacion = @corr, @codigoEstado = NULL, @numeroPagina = 2, @tamanoPagina = 1;
    SET @ok = IIF((SELECT COUNT(*) FROM #r) = 1 AND EXISTS (SELECT 1 FROM #r WHERE idSolicitudRevisionAsistencia = @reqA2), 1, 0);
    EXEC #hu10_expect 'E02_SECOND_PAGE', @ok;
    PRINT 'TEST_PASS:E-02';

    -- -------------------------------------------------------- E-03 filtro por estado
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_consultar_solicitudes_revision_estudiante
        @idUsuarioEjecutor = @userA, @idCorrelacion = @corr, @codigoEstado = N'A', @numeroPagina = 1, @tamanoPagina = 10;
    SET @ok = IIF((SELECT COUNT(*) FROM #r) = 1 AND EXISTS (SELECT 1 FROM #r WHERE idSolicitudRevisionAsistencia = @reqA2
        AND totalRegistros = 1), 1, 0);
    EXEC #hu10_expect 'E03_STATE_FILTER', @ok;
    PRINT 'TEST_PASS:E-03';

    -- -------------------------------------------------------- E-04 el estudiante B ve solo la suya
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_consultar_solicitudes_revision_estudiante
        @idUsuarioEjecutor = @userB, @idCorrelacion = @corr, @codigoEstado = NULL, @numeroPagina = 1, @tamanoPagina = 100;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r WHERE idSolicitudRevisionAsistencia = @reqB1)
        AND NOT EXISTS (SELECT 1 FROM #r WHERE idSolicitudRevisionAsistencia IN (@reqA1, @reqA2)), 1, 0);
    EXEC #hu10_expect 'E04_OTHER_STUDENT_ISOLATED', @ok;
    PRINT 'TEST_PASS:E-04';

    -- -------------------------------------------------------- E-05 docente y coordinador no ven solicitudes como estudiante
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_consultar_solicitudes_revision_estudiante
        @idUsuarioEjecutor = @userT, @idCorrelacion = @corr, @codigoEstado = NULL, @numeroPagina = 1, @tamanoPagina = 100;
    INSERT INTO #r EXEC dbo.usp_consultar_solicitudes_revision_estudiante
        @idUsuarioEjecutor = @userCoord, @idCorrelacion = @corr, @codigoEstado = NULL, @numeroPagina = 1, @tamanoPagina = 100;
    SET @ok = IIF(NOT EXISTS (SELECT 1 FROM #r WHERE idSolicitudRevisionAsistencia IN (@reqA1, @reqA2, @reqB1)), 1, 0);
    EXEC #hu10_expect 'E05_NON_OWNER_ROLES_ZERO_ROWS', @ok;
    PRINT 'TEST_PASS:E-05';

    -- -------------------------------------------------------- E-06 paginacion fuera de rango se acota (como R2)
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_consultar_solicitudes_revision_estudiante
        @idUsuarioEjecutor = @userA, @idCorrelacion = @corr, @codigoEstado = NULL, @numeroPagina = 0, @tamanoPagina = 0;
    SET @ok = IIF((SELECT COUNT(*) FROM #r) = 2, 1, 0);
    EXEC #hu10_expect 'E06_PAGING_CLAMPED', @ok;
    PRINT 'TEST_PASS:E-06';

    -- -------------------------------------------------------- E-07 soporte que no esta en estado adjunto no se expone
    UPDATE dbo.CatalogoParametro SET valor = N'QA_OTRO_ESTADO' WHERE grupo = 'ARCHIVO' AND clave = 'ESTADO_ADJUNTO';
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_consultar_solicitudes_revision_estudiante
        @idUsuarioEjecutor = @userA, @idCorrelacion = @corr, @codigoEstado = N'P', @numeroPagina = 1, @tamanoPagina = 10;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r WHERE idSolicitudRevisionAsistencia = @reqA1 AND idArchivoSoporte IS NULL), 1, 0);
    EXEC #hu10_expect 'E07_SUPPORT_ONLY_WHEN_ATTACHED', @ok;
    PRINT 'TEST_PASS:E-07';

    -- -------------------------------------------------------- E-08a mismas columnas y orden que R2 (docente)
    SELECT @cols = STRING_AGG(CAST(name AS NVARCHAR(MAX)), N',') WITHIN GROUP (ORDER BY column_ordinal)
    FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID('dbo.usp_consultar_solicitudes_revision_estudiante'), NULL);
    SELECT @colsR2 = STRING_AGG(CAST(name AS NVARCHAR(MAX)), N',') WITHIN GROUP (ORDER BY column_ordinal)
    FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID('dbo.usp_consultar_solicitudes_revision_docente'), NULL);
    SET @ok = IIF(@cols IS NOT NULL AND @cols = @colsR2, 1, 0);
    EXEC #hu10_expect 'E08_SAME_COLUMNS_AS_R2', @ok;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DROP TABLE IF EXISTS #r;
    THROW;
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
DROP TABLE IF EXISTS #r;

-- ------------------------------------------------------------ E-08b ejecutor nulo => THROW con VAL_001 (fuera de tx)
DECLARE @rechazado BIT = 0, @corrX UNIQUEIDENTIFIER = NEWID();
BEGIN TRY
    EXEC dbo.usp_consultar_solicitudes_revision_estudiante
        @idUsuarioEjecutor = NULL, @idCorrelacion = @corrX, @codigoEstado = NULL, @numeroPagina = 1, @tamanoPagina = 10;
END TRY
BEGIN CATCH
    IF ERROR_MESSAGE() LIKE '%DBCODE=VAL_001|%' SET @rechazado = 1;
END CATCH;
EXEC #hu10_expect 'E08_NULL_EXECUTOR_REJECTED', @rechazado;
PRINT 'TEST_PASS:E-08';
PRINT 'TEST_PASS:TEST_CONSULTAS_RECLAMOS_ESTUDIANTE';
GO
