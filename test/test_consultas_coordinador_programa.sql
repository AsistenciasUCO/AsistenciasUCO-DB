USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- HU064/HU060/HU061 (T-064-01, T-060-01, T-061-01): el coordinador consulta grupos, sesiones (registros de
-- asistencia) y el detalle de asistencia por sesion SOLO de su programa. Los SP de lectura usan las vistas
-- uv_auth_* filtradas por el usuario ejecutor (SESSION_CONTEXT); un coordinador de otro programa no ve nada.
PRINT 'TEST START: test_consultas_coordinador_programa';

DECLARE @idGrupo UNIQUEIDENTIFIER, @idPrograma UNIQUEIDENTIFIER, @uCoordTitular UNIQUEIDENTIFIER, @idSesion UNIQUEIDENTIFIER;
SELECT TOP 1 @idGrupo = gp.idGrupo, @idPrograma = gp.idPrograma
FROM dbo.uv_grupo_programa gp
INNER JOIN dbo.uv_programa pr ON pr.id = gp.idPrograma AND pr.idCoordinador IS NOT NULL
WHERE EXISTS (SELECT 1 FROM dbo.uv_sesion s WHERE s.idGrupo = gp.idGrupo)
ORDER BY CASE WHEN EXISTS (SELECT 1 FROM dbo.uv_sesion s INNER JOIN dbo.uv_asistencia a ON a.idSesion = s.id WHERE s.idGrupo = gp.idGrupo) THEN 0 ELSE 1 END;
SELECT @uCoordTitular = ci.idUsuario FROM dbo.uv_programa pr INNER JOIN dbo.uv_coordinador_identidad ci ON ci.id = pr.idCoordinador WHERE pr.id = @idPrograma;
-- Se prefiere una sesion con asistencia registrada; si el seed no tiene, se usa cualquier sesion del grupo.
SELECT TOP 1 @idSesion = s.id FROM dbo.uv_sesion s WHERE s.idGrupo = @idGrupo
ORDER BY CASE WHEN EXISTS (SELECT 1 FROM dbo.uv_asistencia a WHERE a.idSesion = s.id) THEN 0 ELSE 1 END;
DECLARE @sesionTieneAsistencia BIT = IIF(EXISTS (SELECT 1 FROM dbo.uv_asistencia a WHERE a.idSesion = @idSesion), 1, 0);
DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @idFacultad UNIQUEIDENTIFIER = (SELECT TOP 1 idFacultad FROM dbo.uv_programa);
DECLARE @idTipoProg UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoPrograma);
IF @idGrupo IS NULL OR @uCoordTitular IS NULL OR @idSesion IS NULL OR @tipoCC IS NULL
    THROW 52900, 'TEST FAILED: faltan fixtures del seed (grupo con sesion, coordinador del programa).', 1;

CREATE TABLE #grupos (
    id UNIQUEIDENTIFIER, codigo INT, nombre NVARCHAR(100), idAsignatura UNIQUEIDENTIFIER, nombreAsignatura NVARCHAR(100),
    idDocente UNIQUEIDENTIFIER, capacidadMaximaPermitida INT, estudiantesActivos INT, cuposDisponibles INT,
    grupoEstaHablitado BIT, fechaInicioPeriodoAcademico DATETIME2, fechaFinPeriodoAcademico DATETIME2, totalRegistros INT);
CREATE TABLE #sesiones (
    id UNIQUEIDENTIFIER, idGrupo UNIQUEIDENTIFIER, codigoGrupo INT, nombreGrupo NVARCHAR(100), nombre NVARCHAR(100),
    numero INT, codigo NVARCHAR(50), numeroSemana INT, fechaHoraInicio DATETIME2, fechaHoraFin DATETIME2, totalRegistros INT);
CREATE TABLE #asistencias (
    idDetalleAsistencia UNIQUEIDENTIFIER, codigoDetalleAsistencia INT, idAsistencia UNIQUEIDENTIFIER, idSesion UNIQUEIDENTIFIER,
    nombreSesion NVARCHAR(100), codigoSesion NVARCHAR(50), numeroSemana INT, idEstudianteGrupo UNIQUEIDENTIFIER,
    idEstudiante UNIQUEIDENTIFIER, idUsuario UNIQUEIDENTIFIER, numeroIdentificacion NVARCHAR(50), primerApellido NVARCHAR(50),
    segundoApellido NVARCHAR(50), primerNombre NVARCHAR(50), segundoNombre NVARCHAR(50), nombreCompleto NVARCHAR(250),
    asistio BIT, idRazonCausa UNIQUEIDENTIFIER, codigoRazonCausa VARCHAR(10), nombreRazonCausa NVARCHAR(100),
    fechaHoraInicio DATETIME2, fechaHoraFin DATETIME2, totalRegistros INT);

BEGIN TRANSACTION;
BEGIN TRY
    -- Coordinador de OTRO programa (sin grupos)
    DECLARE @uOtro UNIQUEIDENTIFIER = NEWID(), @cOtro UNIQUEIDENTIFIER = NEWID(), @pOtro UNIQUEIDENTIFIER = NEWID(), @corr UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uOtro, @tipoCC, 970000641, N'Coord', N'Otro', N'Olga', N'Qa', N'qa.c.hu064@test.local', 1, 1, N'HashBackend_R1');
    INSERT INTO dbo.Coordinador (id, usuario) VALUES (@cOtro, @uOtro);
    INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado)
    VALUES (@pOtro, @idFacultad, @idTipoProg, N'Programa QA 064', @cOtro, 1);

    -- T-064-01: el coordinador titular ve el grupo de su programa; el de otro programa no lo ve
    INSERT INTO #grupos EXEC dbo.usp_consultar_grupos_paginado
        @idUsuarioEjecutor = @uCoordTitular, @idCorrelacion = @corr, @numeroPagina = 1, @tamanoPagina = 100;
    IF NOT EXISTS (SELECT 1 FROM #grupos WHERE id = @idGrupo) THROW 52910, 'T-064-01 FAILED: el coordinador titular no ve el grupo de su programa.', 1;
    IF EXISTS (SELECT 1 FROM #grupos g WHERE NOT EXISTS (SELECT 1 FROM dbo.uv_grupo_programa gp WHERE gp.idGrupo = g.id AND gp.idPrograma = @idPrograma))
        THROW 52911, 'T-064-01 FAILED: el coordinador ve grupos de otros programas.', 1;
    TRUNCATE TABLE #grupos;
    INSERT INTO #grupos EXEC dbo.usp_consultar_grupos_paginado
        @idUsuarioEjecutor = @uOtro, @idCorrelacion = @corr, @numeroPagina = 1, @tamanoPagina = 100;
    IF EXISTS (SELECT 1 FROM #grupos) THROW 52912, 'T-064-01 FAILED: un coordinador sin grupos ve grupos ajenos.', 1;
    PRINT 'TEST_PASS:T-064-01';

    -- T-060-01: sesiones (registros de asistencia) del grupo, solo para el titular
    INSERT INTO #sesiones EXEC dbo.usp_consultar_sesiones_grupo_paginado
        @idUsuarioEjecutor = @uCoordTitular, @idCorrelacion = @corr, @idGrupo = @idGrupo, @numeroPagina = 1, @tamanoPagina = 100;
    IF NOT EXISTS (SELECT 1 FROM #sesiones WHERE id = @idSesion) THROW 52920, 'T-060-01 FAILED: el titular no ve las sesiones del grupo.', 1;
    TRUNCATE TABLE #sesiones;
    INSERT INTO #sesiones EXEC dbo.usp_consultar_sesiones_grupo_paginado
        @idUsuarioEjecutor = @uOtro, @idCorrelacion = @corr, @idGrupo = @idGrupo, @numeroPagina = 1, @tamanoPagina = 100;
    IF EXISTS (SELECT 1 FROM #sesiones) THROW 52921, 'T-060-01 FAILED: un coordinador ajeno ve sesiones del grupo.', 1;
    PRINT 'TEST_PASS:T-060-01';

    -- T-061-01: detalle de asistencia de la sesion, solo para el titular
    INSERT INTO #asistencias EXEC dbo.usp_consultar_asistencias_sesion_paginado
        @idUsuarioEjecutor = @uCoordTitular, @idCorrelacion = @corr, @idSesion = @idSesion, @numeroPagina = 1, @tamanoPagina = 100;
    IF @sesionTieneAsistencia = 1 AND NOT EXISTS (SELECT 1 FROM #asistencias WHERE idSesion = @idSesion)
        THROW 52930, 'T-061-01 FAILED: el titular no ve el detalle de asistencia.', 1;
    TRUNCATE TABLE #asistencias;
    INSERT INTO #asistencias EXEC dbo.usp_consultar_asistencias_sesion_paginado
        @idUsuarioEjecutor = @uOtro, @idCorrelacion = @corr, @idSesion = @idSesion, @numeroPagina = 1, @tamanoPagina = 100;
    IF EXISTS (SELECT 1 FROM #asistencias) THROW 52931, 'T-061-01 FAILED: un coordinador ajeno ve el detalle de asistencia.', 1;
    PRINT 'TEST_PASS:T-061-01';

    ROLLBACK TRANSACTION;
    DROP TABLE #grupos; DROP TABLE #sesiones; DROP TABLE #asistencias;
    PRINT 'TEST_PASS:TEST_CONSULTAS_COORDINADOR_PROGRAMA';
END TRY
BEGIN CATCH
    DECLARE @err NVARCHAR(4000) = ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    IF OBJECT_ID('tempdb..#grupos') IS NOT NULL DROP TABLE #grupos;
    IF OBJECT_ID('tempdb..#sesiones') IS NOT NULL DROP TABLE #sesiones;
    IF OBJECT_ID('tempdb..#asistencias') IS NOT NULL DROP TABLE #asistencias;
    THROW 52999, @err, 1;
END CATCH
GO
