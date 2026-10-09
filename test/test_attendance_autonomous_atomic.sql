USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- TD-056: asistencia autonoma atomica (Asistencia + DetalleAsistencia).
-- Fallo forzado DESPUES de insertar la cabecera y ANTES de completar el detalle. El fallo es un CHECK
-- sobre DetalleAsistencia.fechaHoraInicio (error 547): no condena la transaccion externa (un THROW en trigger si).
-- Residuos esperados: Asistencia = 0 y DetalleAsistencia = 0 para la sesion de prueba.
PRINT 'TEST START: test_attendance_autonomous_atomic';

DECLARE @group UNIQUEIDENTIFIER, @student UNIQUEIDENTIFIER, @enrollment UNIQUEIDENTIFIER;
SELECT TOP 1 @group = eg.idGrupo, @student = eg.idEstudiante, @enrollment = eg.id
FROM dbo.uv_estudiante_grupo eg JOIN dbo.uv_grupo g ON g.id = eg.idGrupo
WHERE eg.codigoEstadoEstudiante = 'A' AND g.grupoEstaHablitado = 1
ORDER BY eg.id;
DECLARE @studentUser UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_estudiante_identidad WHERE id = @student);
IF @group IS NULL OR @student IS NULL OR @studentUser IS NULL
    THROW 52820, 'TEST FAILED: AUTONOMOUS_ATOMIC fixture missing.', 1;

-- Sesion con instante fijo: el detalle hereda fechaHoraInicio de la sesion, asi que el CHECK la identifica.
DECLARE @session UNIQUEIDENTIFIER = NEWID();
DECLARE @inicioSesion DATETIME2 = '2031-03-10T08:00:00';
DECLARE @finSesion DATETIME2 = '2031-03-10T09:00:00';
DECLARE @codigoSesion NVARCHAR(50) = LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8);
DECLARE @number INT = 1 + (SELECT ISNULL(MAX(numero), 0) FROM dbo.Sesion WHERE grupo = @group);
DECLARE @falla NVARCHAR(MAX) = N'ALTER TABLE dbo.DetalleAsistencia WITH NOCHECK ADD CONSTRAINT ck_qa_asistencia_detalle_falla CHECK (fechaHoraInicio <> ''2031-03-10T08:00:00'')';
DECLARE @corr UNIQUEIDENTIFIER;

-- ---------------------------------------------------------------------------------------------
-- A. Con transaccion externa: savepoint sp_asistencia_autonomo; residuos 0 y transaccion externa viva.
-- ---------------------------------------------------------------------------------------------
BEGIN TRANSACTION;
BEGIN TRY
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
    VALUES (@session, N'QA Autonoma Atomica', @number, @codigoSesion, 1, @group, @inicioSesion, @finSesion);

    EXEC sys.sp_executesql @falla;

    DECLARE @asistBefore INT = (SELECT COUNT(*) FROM dbo.Asistencia WHERE sesion = @session);
    DECLARE @detBefore INT = (SELECT COUNT(*) FROM dbo.DetalleAsistencia d INNER JOIN dbo.Asistencia a ON a.id = d.asistencia WHERE a.sesion = @session);
    SET @corr = NEWID();

    -- Llamada directa: el SP hace ROLLBACK TO SAVEPOINT, por eso no puede ir dentro de INSERT ... EXEC.
    EXEC dbo.usp_registrar_asistencia_estudiante_autonomo
        @idEstudiante = @student, @idSesion = @session, @codigoVerificacion = @codigoSesion,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @studentUser;

    IF @@TRANCOUNT <> 1 THROW 52821, 'TEST FAILED: AUTONOMOUS_ATOMIC_SAVEPOINT changed the external transaction count.', 1;
    IF XACT_STATE() <> 1 THROW 52822, 'TEST FAILED: AUTONOMOUS_ATOMIC_SAVEPOINT external transaction not usable.', 1;
    IF (SELECT COUNT(*) FROM dbo.Asistencia WHERE sesion = @session) <> @asistBefore
        THROW 52823, 'TEST FAILED: AUTONOMOUS_ATOMIC_SAVEPOINT left Asistencia residual.', 1;
    IF (SELECT COUNT(*) FROM dbo.DetalleAsistencia d INNER JOIN dbo.Asistencia a ON a.id = d.asistencia WHERE a.sesion = @session) <> @detBefore
        THROW 52824, 'TEST FAILED: AUTONOMOUS_ATOMIC_SAVEPOINT left DetalleAsistencia residual.', 1;
    PRINT 'TEST_PASS:AUTONOMOUS_ATOMIC_SAVEPOINT';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'ck_qa_asistencia_detalle_falla')
        ALTER TABLE dbo.DetalleAsistencia DROP CONSTRAINT ck_qa_asistencia_detalle_falla;
    THROW;
END CATCH;
ROLLBACK TRANSACTION;
IF @@TRANCOUNT <> 0 THROW 52825, 'TEST FAILED: AUTONOMOUS_ATOMIC_SAVEPOINT left transaction open.', 1;

-- ---------------------------------------------------------------------------------------------
-- B. Sin transaccion externa: transaccion propia; ROLLBACK propio; residuos 0.
-- ---------------------------------------------------------------------------------------------
-- La sesion y el CHECK viven fuera de la transaccion de prueba: se limpian explicitamente al final.
INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
VALUES (@session, N'QA Autonoma Atomica Owner', @number + 1, @codigoSesion, 1, @group, @inicioSesion, @finSesion);
EXEC sys.sp_executesql @falla;
BEGIN TRY
    DECLARE @asistBeforeOwner INT = (SELECT COUNT(*) FROM dbo.Asistencia WHERE sesion = @session);
    DECLARE @detBeforeOwner INT = (SELECT COUNT(*) FROM dbo.DetalleAsistencia d INNER JOIN dbo.Asistencia a ON a.id = d.asistencia WHERE a.sesion = @session);
    SET @corr = NEWID();
    EXEC dbo.usp_registrar_asistencia_estudiante_autonomo
        @idEstudiante = @student, @idSesion = @session, @codigoVerificacion = @codigoSesion,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @studentUser;
    IF @@TRANCOUNT <> 0 THROW 52826, 'TEST FAILED: AUTONOMOUS_ATOMIC_OWNER left an open transaction.', 1;
    IF (SELECT COUNT(*) FROM dbo.Asistencia WHERE sesion = @session) <> @asistBeforeOwner
        THROW 52827, 'TEST FAILED: AUTONOMOUS_ATOMIC_OWNER left Asistencia residual.', 1;
    IF (SELECT COUNT(*) FROM dbo.DetalleAsistencia d INNER JOIN dbo.Asistencia a ON a.id = d.asistencia WHERE a.sesion = @session) <> @detBeforeOwner
        THROW 52828, 'TEST FAILED: AUTONOMOUS_ATOMIC_OWNER left DetalleAsistencia residual.', 1;
    PRINT 'TEST_PASS:AUTONOMOUS_ATOMIC_OWNER';
END TRY
BEGIN CATCH
    IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'ck_qa_asistencia_detalle_falla')
        ALTER TABLE dbo.DetalleAsistencia DROP CONSTRAINT ck_qa_asistencia_detalle_falla;
    DELETE FROM dbo.Sesion WHERE id = @session;
    THROW;
END CATCH;
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'ck_qa_asistencia_detalle_falla')
    ALTER TABLE dbo.DetalleAsistencia DROP CONSTRAINT ck_qa_asistencia_detalle_falla;
DELETE FROM dbo.Sesion WHERE id = @session;

IF EXISTS (SELECT 1 FROM dbo.Sesion WHERE id = @session) THROW 52829, 'TEST FAILED: AUTONOMOUS_ATOMIC leaked fixture session.', 1;
IF @@TRANCOUNT <> 0 THROW 52830, 'TEST FAILED: test_attendance_autonomous_atomic left transactions open.', 1;
PRINT 'TEST END: test_attendance_autonomous_atomic';
GO
