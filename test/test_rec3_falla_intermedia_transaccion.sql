USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ============================================================================
-- REC3 (auditoria BD 2026-10-28): falla a mitad de la transaccion en los SP que abren su propia transaccion.
-- El SP debe ser DUENO de la transaccion (sin transaccion del llamador), asi que las fixtures se confirman y se
-- limpian al final en todos los caminos. La falla se provoca con un CHECK temporal (WITH NOCHECK) sobre la
-- tabla de la SEGUNDA escritura, limitado a las filas de la prueba; el CHECK se elimina siempre.
-- Se verifica: la PRIMERA escritura quedo revertida, la segunda no persistio y @@TRANCOUNT = 0. El SP se invoca con EXEC
-- directo (no INSERT-EXEC): SQL Server no permite ROLLBACK dentro de un INSERT-EXEC; el resultset SYS_001 queda en la salida.
-- ============================================================================
PRINT 'TEST START: test_rec3_falla_intermedia_transaccion';

-- Limpieza defensiva de una ejecucion anterior interrumpida.
IF OBJECT_ID('dbo.CK_REC3_TMP_SOLICITUD', 'C') IS NOT NULL ALTER TABLE dbo.SolicitudRevisionAsistencia DROP CONSTRAINT CK_REC3_TMP_SOLICITUD;
IF OBJECT_ID('dbo.CK_REC3_TMP_DETALLE', 'C') IS NOT NULL ALTER TABLE dbo.DetalleAsistencia DROP CONSTRAINT CK_REC3_TMP_DETALLE;
IF OBJECT_ID('dbo.CK_REC3_TMP_GRUPO', 'C') IS NOT NULL ALTER TABLE dbo.Grupo DROP CONSTRAINT CK_REC3_TMP_GRUPO;
IF OBJECT_ID('dbo.CK_REC3_TMP_SESION', 'C') IS NOT NULL ALTER TABLE dbo.Sesion DROP CONSTRAINT CK_REC3_TMP_SESION;
GO

-- ---------------------------------------------------------------------------
-- TX-01: usp_radicar_solicitud_revision_asistencia. 1a escritura: Asistencia; 2a: SolicitudRevisionAsistencia (falla).
-- ---------------------------------------------------------------------------
DECLARE @group UNIQUEIDENTIFIER, @student UNIQUEIDENTIFIER, @enrollment UNIQUEIDENTIFIER;
SELECT TOP 1 @group = eg.idGrupo, @student = eg.idEstudiante, @enrollment = eg.id
FROM dbo.uv_estudiante_grupo eg JOIN dbo.uv_grupo g ON g.id = eg.idGrupo
WHERE eg.codigoEstadoEstudiante = 'A' AND g.grupoEstaHablitado = 1
ORDER BY eg.id;
DECLARE @studentUser UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_estudiante_identidad WHERE id = @student);
DECLARE @session UNIQUEIDENTIFIER = NEWID(), @corr UNIQUEIDENTIFIER = NEWID(), @fallo NVARCHAR(4000) = NULL;
DECLARE @number INT = 1 + (SELECT MAX(numero) FROM dbo.Sesion WHERE grupo = @group);
IF @number IS NULL SET @number = 1;
IF @group IS NULL OR @studentUser IS NULL THROW 54300, 'TEST FAILED: TX-01 fixture missing.', 1;

INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
VALUES (@session, N'QA REC3 TX01', @number, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group,
        DATEADD(HOUR, -3, SYSUTCDATETIME()), DATEADD(HOUR, -2, SYSUTCDATETIME()));
-- Precondicion: sin la restriccion la misma llamada es exitosa (dentro de una transaccion que se revierte), asi la
-- falla posterior ocurre en la escritura y no en una validacion previa.
CREATE TABLE #preTX01 (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
BEGIN TRANSACTION;
INSERT INTO #preTX01 EXEC dbo.usp_radicar_solicitud_revision_asistencia @idEstudiante = @student, @idSesion = @session,
        @categoria = N'ASISTENCIA', @justificacion = N'REC3_FALLA_INTERMEDIA', @soporteNombre = NULL, @soporteUrl = NULL,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @studentUser;
IF NOT EXISTS (SELECT 1 FROM #preTX01 WHERE estadoResultado = 1) SET @fallo = 'TX01 precondicion: la llamada sin falla inyectada no fue exitosa.';
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
DROP TABLE #preTX01;
ALTER TABLE dbo.SolicitudRevisionAsistencia WITH NOCHECK
    ADD CONSTRAINT CK_REC3_TMP_SOLICITUD CHECK (justificacionSolicitud <> N'REC3_FALLA_INTERMEDIA');
BEGIN TRY
    IF @fallo IS NOT NULL THROW 54390, @fallo, 1;
    EXEC dbo.usp_radicar_solicitud_revision_asistencia @idEstudiante = @student, @idSesion = @session,
        @categoria = N'ASISTENCIA', @justificacion = N'REC3_FALLA_INTERMEDIA', @soporteNombre = NULL, @soporteUrl = NULL,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @studentUser;
    IF @@TRANCOUNT <> 0 SET @fallo = 'TX-01 dejo una transaccion abierta.';
    ELSE IF EXISTS (SELECT 1 FROM dbo.Asistencia WHERE estudianteGrupo = @enrollment AND sesion = @session)
        SET @fallo = 'TX-01 la Asistencia insertada antes de la falla NO se revirtio.';
    ELSE IF EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia WHERE justificacionSolicitud = N'REC3_FALLA_INTERMEDIA')
        SET @fallo = 'TX-01 quedo una solicitud escrita.';
END TRY
BEGIN CATCH
    SET @fallo = CONCAT('TX-01 error no controlado: ', ERROR_MESSAGE());
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
ALTER TABLE dbo.SolicitudRevisionAsistencia DROP CONSTRAINT CK_REC3_TMP_SOLICITUD;
DELETE FROM dbo.SolicitudRevisionAsistencia WHERE asistencia IN (SELECT id FROM dbo.Asistencia WHERE sesion = @session);
-- CULM-001 B.2 ([SUPUESTO-B-20]): tomas, tokens y cancelacion de la sesion antes de borrarla
DECLARE @culmb2Limpieza1 NVARCHAR(MAX) = (SELECT idSesion = @session FOR JSON PATH);
EXEC #culm001_b2_limpiar_sesiones @sesionesJSON = @culmb2Limpieza1;
DELETE FROM dbo.Asistencia WHERE sesion = @session;
DELETE FROM dbo.Sesion WHERE id = @session;
IF @fallo IS NOT NULL THROW 54301, @fallo, 1;
PRINT 'TEST_PASS:REC3_TX01_RADICAR_REVIERTE_TODO';
GO

-- ---------------------------------------------------------------------------
-- TX-02: usp_resolver_solicitud_revision_asistencia. 1a escritura: SolicitudRevisionAsistencia (estado/respuesta);
-- 2a: DetalleAsistencia.razonCausa = EX con asistio = 0 (SES-04; falla).
-- ---------------------------------------------------------------------------
DECLARE @group UNIQUEIDENTIFIER, @enrollment UNIQUEIDENTIFIER, @teacher UNIQUEIDENTIFIER;
SELECT TOP 1 @group = eg.idGrupo, @enrollment = eg.id, @teacher = g.idDocente
FROM dbo.uv_estudiante_grupo eg JOIN dbo.uv_grupo g ON g.id = eg.idGrupo
WHERE eg.codigoEstadoEstudiante = 'A' AND g.grupoEstaHablitado = 1
ORDER BY eg.id;
DECLARE @teacherUser UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_docente_identidad WHERE id = @teacher);
DECLARE @reason UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.RazonCausa WHERE codigo IN ('SJC', 'F'));
DECLARE @pending UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Estado WHERE codigo = 'P');
DECLARE @session UNIQUEIDENTIFIER = NEWID(), @attendance UNIQUEIDENTIFIER = NEWID(), @detail UNIQUEIDENTIFIER = NEWID();
DECLARE @request UNIQUEIDENTIFIER = NEWID(), @corr UNIQUEIDENTIFIER = NEWID(), @fallo NVARCHAR(4000) = NULL, @sql NVARCHAR(MAX);
DECLARE @number INT = 1 + (SELECT MAX(numero) FROM dbo.Sesion WHERE grupo = @group);
IF @number IS NULL SET @number = 1;
DECLARE @detailCode INT = 1 + (SELECT MAX(codigo) FROM dbo.DetalleAsistencia);
IF @detailCode IS NULL SET @detailCode = 1;
IF @group IS NULL OR @teacherUser IS NULL OR @reason IS NULL OR @pending IS NULL THROW 54310, 'TEST FAILED: TX-02 fixture missing.', 1;

INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
VALUES (@session, N'QA REC3 TX02', @number, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group,
        DATEADD(HOUR, -3, SYSUTCDATETIME()), DATEADD(HOUR, -2, SYSUTCDATETIME()));
INSERT dbo.Asistencia (id, estudianteGrupo, sesion) VALUES (@attendance, @enrollment, @session);
-- CULM-001 B.2 ([SUPUESTO-B-20]): la columna obligatoria DetalleAsistencia.toma exige la toma 1 de la sesion (helper culm001_b2_toma_fixture.sql).
DECLARE @culmb2Toma UNIQUEIDENTIFIER;
EXEC #culm001_b2_crear_toma @idSesion = @session, @idToma = @culmb2Toma OUTPUT;
INSERT dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin, toma)
VALUES (@detail, @detailCode, @attendance, 0, @reason, DATEADD(HOUR, -3, SYSUTCDATETIME()), DATEADD(HOUR, -2, SYSUTCDATETIME()), @culmb2Toma);
INSERT dbo.SolicitudRevisionAsistencia (id, nombre, asistencia, fecha, estado, justificacionSolicitud, justificacionRespuesta)
VALUES (@request, N'REC-QAREC3', @attendance, CAST(SYSUTCDATETIME() AS DATE), @pending, N'QA REC3 TX02', N'');
-- Precondicion: sin la restriccion la misma llamada es exitosa (dentro de una transaccion que se revierte), asi la
-- falla posterior ocurre en la escritura y no en una validacion previa.
CREATE TABLE #preTX02 (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
BEGIN TRANSACTION;
INSERT INTO #preTX02 EXEC dbo.usp_resolver_solicitud_revision_asistencia @idSolicitud = @request, @idDocente = @teacher,
        @accion = N'APROBADA', @respuestaDocente = N'REC3 no debe persistir', @idCorrelacion = @corr, @idUsuarioEjecutor = @teacherUser;
IF NOT EXISTS (SELECT 1 FROM #preTX02 WHERE estadoResultado = 1) SET @fallo = 'TX02 precondicion: la llamada sin falla inyectada no fue exitosa.';
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
DROP TABLE #preTX02;
-- SES-04: la segunda escritura cambia la causal a EX; la restriccion temporal solo admite la causal original.
SET @sql = CONCAT(N'ALTER TABLE dbo.DetalleAsistencia WITH NOCHECK ADD CONSTRAINT CK_REC3_TMP_DETALLE CHECK (id <> ''',
                  CONVERT(NVARCHAR(36), @detail), N''' OR razonCausa = ''', CONVERT(NVARCHAR(36), @reason), N''');');
EXEC sys.sp_executesql @sql;
BEGIN TRY
    IF @fallo IS NOT NULL THROW 54390, @fallo, 1;
    EXEC dbo.usp_resolver_solicitud_revision_asistencia @idSolicitud = @request, @idDocente = @teacher,
        @accion = N'APROBADA', @respuestaDocente = N'REC3 no debe persistir', @idCorrelacion = @corr, @idUsuarioEjecutor = @teacherUser;
    IF @@TRANCOUNT <> 0 SET @fallo = 'TX-02 dejo una transaccion abierta.';
    ELSE IF NOT EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia WHERE id = @request AND estado = @pending AND justificacionRespuesta = N'')
        SET @fallo = 'TX-02 la actualizacion de la solicitud anterior a la falla NO se revirtio.';
    ELSE IF NOT EXISTS (SELECT 1 FROM dbo.DetalleAsistencia WHERE id = @detail AND asistio = 0 AND razonCausa = @reason)
        SET @fallo = 'TX-02 el detalle de asistencia cambio.';
END TRY
BEGIN CATCH
    SET @fallo = CONCAT('TX-02 error no controlado: ', ERROR_MESSAGE());
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
ALTER TABLE dbo.DetalleAsistencia DROP CONSTRAINT CK_REC3_TMP_DETALLE;
DELETE FROM dbo.SolicitudRevisionAsistencia WHERE id = @request;
DELETE FROM dbo.DetalleAsistencia WHERE id = @detail;
-- CULM-001 B.2 ([SUPUESTO-B-20]): tomas, tokens y cancelacion de la sesion antes de borrarla
DECLARE @culmb2Limpieza2 NVARCHAR(MAX) = (SELECT idSesion = @session FOR JSON PATH);
EXEC #culm001_b2_limpiar_sesiones @sesionesJSON = @culmb2Limpieza2;
DELETE FROM dbo.Asistencia WHERE id = @attendance;
DELETE FROM dbo.Sesion WHERE id = @session;
IF @fallo IS NOT NULL THROW 54311, @fallo, 1;
PRINT 'TEST_PASS:REC3_TX02_RESOLVER_REVIERTE_TODO';
GO

-- ---------------------------------------------------------------------------
-- TX-03: usp_ejecutar_cierre_masivo_periodo. 1a escritura: EstudianteGrupo -> F; 2a: contadores de Grupo (falla).
-- ---------------------------------------------------------------------------
DECLARE @institution UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion);
DECLARE @assignment UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_asignatura);
DECLARE @teacher UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_docente);
DECLARE @adminUser UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_administrador WHERE estaActivoUsuario = 1);
DECLARE @student UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Estudiante ORDER BY id);
DECLARE @active UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'A');
DECLARE @period UNIQUEIDENTIFIER = NEWID(), @group UNIQUEIDENTIFIER = NEWID(), @enrollment UNIQUEIDENTIFIER = NEWID();
DECLARE @periodCode INT = 700000 + ABS(CHECKSUM(NEWID()) % 100000);
DECLARE @corr UNIQUEIDENTIFIER = NEWID(), @fallo NVARCHAR(4000) = NULL, @sql NVARCHAR(MAX);
DECLARE @periodCodeText NVARCHAR(50) = CONVERT(NVARCHAR(50), @periodCode);
IF @institution IS NULL OR @assignment IS NULL OR @teacher IS NULL OR @adminUser IS NULL OR @student IS NULL OR @active IS NULL
    THROW 54320, 'TEST FAILED: TX-03 fixture missing.', 1;

INSERT dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
VALUES (@period, @institution, N'Periodo QA REC3', @periodCode,
        DATEADD(DAY, -20, CAST(GETDATE() AS DATE)), DATEADD(DAY, -1, CAST(GETDATE() AS DATE)), YEAR(GETDATE()));
INSERT dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
    cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
VALUES (@group, @assignment, @period, 400000 + ABS(CHECKSUM(NEWID()) % 100000), N'Grupo QA REC3', 30, 0, 0, 0, @teacher);
INSERT dbo.EstudianteGrupo (id, estado, estudiante, grupo) VALUES (@enrollment, @active, @student, @group);
-- Precondicion: sin la restriccion la misma llamada es exitosa (dentro de una transaccion que se revierte), asi la
-- falla posterior ocurre en la escritura y no en una validacion previa.
CREATE TABLE #preTX03 (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
BEGIN TRANSACTION;
INSERT INTO #preTX03 EXEC dbo.usp_ejecutar_cierre_masivo_periodo @codigoPeriodo = @periodCodeText, @idActor = N'QA_REC3',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @adminUser;
IF NOT EXISTS (SELECT 1 FROM #preTX03 WHERE estadoResultado = 1) SET @fallo = 'TX03 precondicion: la llamada sin falla inyectada no fue exitosa.';
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
DROP TABLE #preTX03;
SET @sql = CONCAT(N'ALTER TABLE dbo.Grupo WITH NOCHECK ADD CONSTRAINT CK_REC3_TMP_GRUPO CHECK (id <> ''',
                  CONVERT(NVARCHAR(36), @group), N''' OR cantidadEstudiantesFinalizaron = 0);');
EXEC sys.sp_executesql @sql;
BEGIN TRY
    IF @fallo IS NOT NULL THROW 54390, @fallo, 1;
    EXEC dbo.usp_ejecutar_cierre_masivo_periodo @codigoPeriodo = @periodCodeText, @idActor = N'QA_REC3',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @adminUser;
    IF @@TRANCOUNT <> 0 SET @fallo = 'TX-03 dejo una transaccion abierta.';
    ELSE IF NOT EXISTS (SELECT 1 FROM dbo.EstudianteGrupo WHERE id = @enrollment AND estado = @active)
        SET @fallo = 'TX-03 la finalizacion de la matricula anterior a la falla NO se revirtio.';
    ELSE IF EXISTS (SELECT 1 FROM dbo.AuditoriaEvento WHERE correlationId = @corr AND result = N'SUCCESS')
        SET @fallo = 'TX-03 quedo un evento de auditoria de exito.';
END TRY
BEGIN CATCH
    SET @fallo = CONCAT('TX-03 error no controlado: ', ERROR_MESSAGE());
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
ALTER TABLE dbo.Grupo DROP CONSTRAINT CK_REC3_TMP_GRUPO;
DELETE FROM dbo.EstudianteGrupo WHERE grupo = @group;
DELETE FROM dbo.Grupo WHERE id = @group;
DELETE FROM dbo.PeriodoAcademico WHERE id = @period;
IF @fallo IS NOT NULL THROW 54321, @fallo, 1;
PRINT 'TEST_PASS:REC3_TX03_CIERRE_MASIVO_REVIERTE_TODO';
GO

-- ---------------------------------------------------------------------------
-- TX-04: usp_generar_sesiones_grupo (congelado; cambio aprobado por John 2026-10-29). Inserta una Sesion por dia;
-- la 1a insercion debe revertirse cuando falla la 2a.
-- ---------------------------------------------------------------------------
DECLARE @institution UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion);
DECLARE @assignment UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_asignatura);
DECLARE @teacher UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_docente);
DECLARE @teacherUser UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_docente WHERE id = @teacher);
DECLARE @period UNIQUEIDENTIFIER = NEWID(), @group UNIQUEIDENTIFIER = NEWID(), @corr UNIQUEIDENTIFIER = NEWID();
DECLARE @fallo NVARCHAR(4000) = NULL, @sql NVARCHAR(MAX);
DECLARE @firstDay DATE = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER') AS DATE);
IF @institution IS NULL OR @assignment IS NULL OR @teacher IS NULL OR @teacherUser IS NULL
    THROW 54330, 'TEST FAILED: TX-04 fixture missing.', 1;

INSERT dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
VALUES (@period, @institution, N'Periodo QA REC3 TX04', 800000 + ABS(CHECKSUM(NEWID()) % 100000), @firstDay, DATEADD(DAY, 7, @firstDay), YEAR(@firstDay));
INSERT dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
    cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
VALUES (@group, @assignment, @period, 500000 + ABS(CHECKSUM(NEWID()) % 100000), N'Grupo QA REC3 TX04', 20, 0, 0, 0, @teacher);
INSERT dbo.Horario (id, grupo, dia, horaInicio, horaFin)
SELECT NEWID(), @group, id, '08:00', '09:00' FROM dbo.uv_dia;

-- Precondicion: sin la restriccion la generacion es exitosa (dentro de una transaccion que se revierte).
CREATE TABLE #preTX04 (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
BEGIN TRANSACTION;
INSERT INTO #preTX04 EXEC dbo.usp_generar_sesiones_grupo @idGrupo = @group, @idCorrelacion = @corr, @idUsuarioEjecutor = @teacherUser;
IF NOT EXISTS (SELECT 1 FROM #preTX04 WHERE estadoResultado = 1) OR (SELECT COUNT(*) FROM dbo.Sesion WHERE grupo = @group) < 2
    SET @fallo = 'TX04 precondicion: la generacion sin falla inyectada no fue exitosa o creo menos de 2 sesiones.';
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
DROP TABLE #preTX04;
SET @sql = CONCAT(N'ALTER TABLE dbo.Sesion WITH NOCHECK ADD CONSTRAINT CK_REC3_TMP_SESION CHECK (grupo <> ''',
                  CONVERT(NVARCHAR(36), @group), N''' OR numero < 2);');
EXEC sys.sp_executesql @sql;
BEGIN TRY
    IF @fallo IS NOT NULL THROW 54390, @fallo, 1;
    EXEC dbo.usp_generar_sesiones_grupo @idGrupo = @group, @idCorrelacion = @corr, @idUsuarioEjecutor = @teacherUser;
    IF @@TRANCOUNT <> 0 SET @fallo = 'TX-04 dejo una transaccion abierta.';
    ELSE IF EXISTS (SELECT 1 FROM dbo.Sesion WHERE grupo = @group)
        SET @fallo = 'TX-04 la primera Sesion insertada antes de la falla NO se revirtio.';
END TRY
BEGIN CATCH
    SET @fallo = CONCAT('TX-04 error no controlado: ', ERROR_MESSAGE());
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
ALTER TABLE dbo.Sesion DROP CONSTRAINT CK_REC3_TMP_SESION;
-- CULM-001 B.2 ([SUPUESTO-B-20]): tomas, tokens y cancelaciones de las sesiones del grupo antes de borrarlas
DECLARE @culmb2Limpieza4 NVARCHAR(MAX) = (SELECT idSesion = id FROM dbo.Sesion WHERE grupo = @group FOR JSON PATH);
EXEC #culm001_b2_limpiar_sesiones @sesionesJSON = @culmb2Limpieza4;
DELETE FROM dbo.Sesion WHERE grupo = @group;
DELETE FROM dbo.Horario WHERE grupo = @group;
DELETE FROM dbo.Grupo WHERE id = @group;
DELETE FROM dbo.PeriodoAcademico WHERE id = @period;
IF @fallo IS NOT NULL THROW 54331, @fallo, 1;
PRINT 'TEST_PASS:REC3_TX04_GENERAR_SESIONES_REVIERTE_TODO';
GO

IF OBJECT_ID('dbo.CK_REC3_TMP_SOLICITUD', 'C') IS NOT NULL OR OBJECT_ID('dbo.CK_REC3_TMP_DETALLE', 'C') IS NOT NULL
   OR OBJECT_ID('dbo.CK_REC3_TMP_GRUPO', 'C') IS NOT NULL OR OBJECT_ID('dbo.CK_REC3_TMP_SESION', 'C') IS NOT NULL
    THROW 54399, 'TEST FAILED: REC3 dejo restricciones temporales.', 1;
IF @@TRANCOUNT <> 0 THROW 54398, 'TEST FAILED: REC3 dejo transacciones abiertas.', 1;
PRINT 'TEST END: test_rec3_falla_intermedia_transaccion';
GO
