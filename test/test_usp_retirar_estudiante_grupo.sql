USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ============================================================================
-- HU051: el DOCENTE TITULAR retira a un estudiante de su grupo (R-01..R-09 del TEST_PLAN).
-- Reglas de John (2026-10-27): la matricula pasa al estado existente "inactivo" (I); se puede retirar aunque tenga
-- asistencias (se conservan); el motivo es obligatorio y queda en la auditoria; se bloquea si el periodo del grupo
-- ya termino (fecha local segun TIEMPO.ZONA_HORARIA_SQLSERVER). El cupo se libera solo (capacidad - activos).
-- Fixtures dentro de UNA transaccion con ROLLBACK final; el THROW de la consulta de destinatarios corre fuera.
-- ============================================================================
IF OBJECT_ID('tempdb..#hu51_expect') IS NOT NULL DROP PROCEDURE #hu51_expect;
GO
CREATE PROCEDURE #hu51_expect @label VARCHAR(100), @ok BIT
AS
BEGIN
    IF @ok IS NULL OR @ok <> 1
    BEGIN
        DECLARE @mensaje NVARCHAR(400) = CONCAT('TEST FAILED: HU051_', @label);
        THROW 52350, @mensaje, 1;
    END
END;
GO

PRINT 'TEST START: test_usp_retirar_estudiante_grupo';

DECLARE @group UNIQUEIDENTIFIER, @teacher UNIQUEIDENTIFIER, @periodo UNIQUEIDENTIFIER;
DECLARE @studentA UNIQUEIDENTIFIER, @studentB UNIQUEIDENTIFIER, @egA UNIQUEIDENTIFIER, @egB UNIQUEIDENTIFIER;
DECLARE @userA UNIQUEIDENTIFIER, @userT UNIQUEIDENTIFIER, @userOtroDocente UNIQUEIDENTIFIER, @userCoordPrograma UNIQUEIDENTIFIER;
DECLARE @estadoActivo UNIQUEIDENTIFIER, @estadoInactivo UNIQUEIDENTIFIER;

SELECT TOP 1 @group = g.id, @teacher = g.docente, @periodo = g.periodoAcademico
FROM dbo.Grupo g
WHERE (SELECT COUNT(*) FROM dbo.uv_estudiante_grupo x WHERE x.idGrupo = g.id AND x.codigoEstadoEstudiante = 'A') >= 2
ORDER BY g.id;

SELECT @studentA = z.idEstudiante, @egA = z.id FROM (
    SELECT idEstudiante, id, ROW_NUMBER() OVER (ORDER BY idEstudiante) rn
    FROM dbo.uv_estudiante_grupo WHERE idGrupo = @group AND codigoEstadoEstudiante = 'A') z WHERE z.rn = 1;
SELECT @studentB = z.idEstudiante, @egB = z.id FROM (
    SELECT idEstudiante, id, ROW_NUMBER() OVER (ORDER BY idEstudiante) rn
    FROM dbo.uv_estudiante_grupo WHERE idGrupo = @group AND codigoEstadoEstudiante = 'A') z WHERE z.rn = 2;

SELECT @userA = usuario FROM dbo.Estudiante WHERE id = @studentA;
SELECT @userT = usuario FROM dbo.Docente WHERE id = @teacher;
SELECT TOP 1 @userOtroDocente = usuario FROM dbo.Docente WHERE id <> @teacher AND usuario <> @userT ORDER BY id;
SELECT @userCoordPrograma = c.usuario
FROM dbo.Grupo g
INNER JOIN dbo.Asignatura a ON a.id = g.asignatura
INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = a.semestrePlanEstudio
INNER JOIN dbo.PlanEstudio pe ON pe.id = spe.planEstudio
INNER JOIN dbo.Programa pr ON pr.id = pe.programa
INNER JOIN dbo.Coordinador c ON c.id = pr.coordinador
WHERE g.id = @group;
SELECT @estadoActivo = id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'A';
SELECT @estadoInactivo = id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'I';

IF @group IS NULL OR @studentA IS NULL OR @studentB IS NULL OR @userA IS NULL OR @userT IS NULL OR @userOtroDocente IS NULL
   OR @userCoordPrograma IS NULL OR @estadoActivo IS NULL OR @estadoInactivo IS NULL OR @periodo IS NULL
    THROW 52351, 'TEST FAILED: HU051 fixture missing (seed data).', 1;

DECLARE @corr UNIQUEIDENTIFIER = NEWID(), @ok BIT, @msg NVARCHAR(4000), @cuposAntes INT, @cuposDespues INT;
DECLARE @s1 UNIQUEIDENTIFIER = NEWID(), @a1 UNIQUEIDENTIFIER = NEWID();
DECLARE @n1 INT = 1 + (SELECT ISNULL(MAX(numero), 0) FROM dbo.Sesion WHERE grupo = @group);
DECLARE @c1 NVARCHAR(50) = LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8);
DECLARE @zona NVARCHAR(100) = dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER');
DECLARE @hoyLocal DATE = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE @zona AS DATE);
DECLARE @motivoLargo NVARCHAR(600) = REPLICATE(N'x', 501);

CREATE TABLE #r (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
CREATE TABLE #d (rolDestinatario VARCHAR(20), idUsuario UNIQUEIDENTIFIER, nombreCompleto NVARCHAR(400), correo NVARCHAR(100),
    idGrupo UNIQUEIDENTIFIER, codigoGrupo INT, nombreGrupo NVARCHAR(50), nombreAsignatura NVARCHAR(100));

BEGIN TRANSACTION;
BEGIN TRY
    -- El periodo del grupo sigue abierto (el seed puede tener periodos vencidos).
    UPDATE dbo.PeriodoAcademico SET fechaFin = DATEADD(DAY, 30, @hoyLocal) WHERE id = @periodo;
    -- A tiene una asistencia registrada: la regla 2 permite retirarlo y la asistencia se conserva.
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
    VALUES (@s1, N'QA HU051 S1', @n1, @c1, 1, @group, '2026-10-19T15:00:00', '2026-10-19T16:00:00');
    INSERT dbo.Asistencia (id, estudianteGrupo, sesion) VALUES (@a1, @egA, @s1);

    -- -------------------------------------------------------- R-03 otro docente, coordinador o estudiante: RET_001 sin cambios
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'RET_001';
    INSERT INTO #r EXEC dbo.usp_retirar_estudiante_grupo
        @idGrupo = @group, @idEstudiante = @studentA, @motivo = N'No titular', @idCorrelacion = @corr, @idUsuarioEjecutor = @userOtroDocente;
    INSERT INTO #r EXEC dbo.usp_retirar_estudiante_grupo
        @idGrupo = @group, @idEstudiante = @studentA, @motivo = N'Coordinador', @idCorrelacion = @corr, @idUsuarioEjecutor = @userCoordPrograma;
    INSERT INTO #r EXEC dbo.usp_retirar_estudiante_grupo
        @idGrupo = @group, @idEstudiante = @studentA, @motivo = N'Estudiante', @idCorrelacion = @corr, @idUsuarioEjecutor = @userA;
    SET @ok = IIF((SELECT COUNT(*) FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) = 3
        AND (SELECT estado FROM dbo.EstudianteGrupo WHERE id = @egA) = @estadoActivo, 1, 0);
    EXEC #hu51_expect 'R03_ONLY_TITULAR_TEACHER', @ok;
    PRINT 'TEST_PASS:R-03';

    -- -------------------------------------------------------- R-06 grupo inexistente: RET_001
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_retirar_estudiante_grupo
        @idGrupo = '00000000-0000-0000-0000-0000000000AB', @idEstudiante = @studentA, @motivo = N'X', @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg), 1, 0);
    EXEC #hu51_expect 'R06_UNKNOWN_GROUP', @ok;
    PRINT 'TEST_PASS:R-06';

    -- -------------------------------------------------------- R-04 motivo obligatorio (vacio, espacios, nulo, > 500): RET_004
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'RET_004';
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_retirar_estudiante_grupo
        @idGrupo = @group, @idEstudiante = @studentA, @motivo = N'', @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    INSERT INTO #r EXEC dbo.usp_retirar_estudiante_grupo
        @idGrupo = @group, @idEstudiante = @studentA, @motivo = N'   ', @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    INSERT INTO #r EXEC dbo.usp_retirar_estudiante_grupo
        @idGrupo = @group, @idEstudiante = @studentA, @motivo = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    INSERT INTO #r EXEC dbo.usp_retirar_estudiante_grupo
        @idGrupo = @group, @idEstudiante = @studentA, @motivo = @motivoLargo, @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    SET @ok = IIF((SELECT COUNT(*) FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) = 4
        AND (SELECT estado FROM dbo.EstudianteGrupo WHERE id = @egA) = @estadoActivo, 1, 0);
    EXEC #hu51_expect 'R04_REASON_REQUIRED', @ok;
    PRINT 'TEST_PASS:R-04';

    -- -------------------------------------------------------- R-05 periodo terminado (ayer en hora local): RET_003
    UPDATE dbo.PeriodoAcademico SET fechaFin = DATEADD(DAY, -1, @hoyLocal) WHERE id = @periodo;
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'RET_003';
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_retirar_estudiante_grupo
        @idGrupo = @group, @idEstudiante = @studentA, @motivo = N'Periodo cerrado', @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg)
        AND (SELECT estado FROM dbo.EstudianteGrupo WHERE id = @egA) = @estadoActivo, 1, 0);
    EXEC #hu51_expect 'R05_PERIOD_FINISHED', @ok;
    -- El ultimo dia del periodo todavia se puede retirar (se reabre para el resto de casos).
    UPDATE dbo.PeriodoAcademico SET fechaFin = @hoyLocal WHERE id = @periodo;
    PRINT 'TEST_PASS:R-05';

    -- -------------------------------------------------------- R-01 el titular retira a A: inactivo, cupo liberado, asistencia y auditoria
    SELECT @cuposAntes = cuposDisponibles FROM dbo.uv_grupo WHERE id = @group;
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'RET_005';
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_retirar_estudiante_grupo
        @idGrupo = @group, @idEstudiante = @studentA, @motivo = N'  Inasistencia reiterada QA  ', @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    SELECT @cuposDespues = cuposDisponibles FROM dbo.uv_grupo WHERE id = @group;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND mensajeUsuarioResultado = @msg AND idCorrelacion = @corr)
        AND (SELECT estado FROM dbo.EstudianteGrupo WHERE id = @egA) = @estadoInactivo
        AND (SELECT estado FROM dbo.EstudianteGrupo WHERE id = @egB) = @estadoActivo
        AND @cuposDespues = @cuposAntes + 1
        AND EXISTS (SELECT 1 FROM dbo.Asistencia WHERE id = @a1 AND estudianteGrupo = @egA), 1, 0);
    EXEC #hu51_expect 'R01_RETIRED_INACTIVE_SEAT_FREED_HISTORY_KEPT', @ok;
    SET @ok = IIF(EXISTS (SELECT 1 FROM dbo.AuditoriaEvento
        WHERE action = 'RETIRO_ESTUDIANTE_GRUPO' AND resourceType = 'EstudianteGrupo' AND resourceId = CAST(@egA AS NVARCHAR(120))
          AND result = 'SUCCESS' AND correlationId = @corr AND actorType = 'USER' AND actorId = CAST(@userT AS NVARCHAR(120))
          AND ISJSON(metadata) = 1 AND JSON_VALUE(metadata, '$.motivo') = N'Inasistencia reiterada QA'
          AND JSON_VALUE(metadata, '$.idGrupo') = CAST(@group AS NVARCHAR(36))
          AND JSON_VALUE(metadata, '$.idEstudiante') = CAST(@studentA AS NVARCHAR(36))), 1, 0);
    EXEC #hu51_expect 'R01_AUDIT_WITH_TRIMMED_REASON', @ok;
    PRINT 'TEST_PASS:R-01';

    -- -------------------------------------------------------- R-02 retirar de nuevo (sin matricula activa): RET_002
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'RET_002';
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_retirar_estudiante_grupo
        @idGrupo = @group, @idEstudiante = @studentA, @motivo = N'Otra vez', @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg), 1, 0);
    EXEC #hu51_expect 'R02_NO_ACTIVE_ENROLMENT', @ok;
    PRINT 'TEST_PASS:R-02';

    -- -------------------------------------------------------- R-07 ejecutor nulo: GEN_002
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'GEN_002';
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_retirar_estudiante_grupo
        @idGrupo = @group, @idEstudiante = @studentB, @motivo = N'Sin ejecutor', @idCorrelacion = @corr, @idUsuarioEjecutor = NULL;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0)
        AND (SELECT estado FROM dbo.EstudianteGrupo WHERE id = @egB) = @estadoActivo, 1, 0);
    EXEC #hu51_expect 'R07_NULL_EXECUTOR', @ok;
    PRINT 'TEST_PASS:R-07';

    -- -------------------------------------------------------- R-08 destinatarios del aviso: estudiante, docente titular y coordinador del programa
    INSERT INTO #d EXEC dbo.usp_consultar_destinatarios_retiro_estudiante_grupo
        @idGrupo = @group, @idEstudiante = @studentA, @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    SET @ok = IIF((SELECT COUNT(*) FROM #d) = 3
        AND EXISTS (SELECT 1 FROM #d WHERE rolDestinatario = 'ESTUDIANTE' AND idUsuario = @userA AND correo <> N'' AND nombreCompleto <> N'')
        AND EXISTS (SELECT 1 FROM #d WHERE rolDestinatario = 'DOCENTE' AND idUsuario = @userT)
        AND EXISTS (SELECT 1 FROM #d WHERE rolDestinatario = 'COORDINADOR' AND idUsuario = @userCoordPrograma)
        AND NOT EXISTS (SELECT 1 FROM #d WHERE idGrupo <> @group OR nombreAsignatura IS NULL), 1, 0);
    EXEC #hu51_expect 'R08_RECIPIENTS', @ok;
    -- Otro docente no obtiene destinatarios (ambito del titular).
    TRUNCATE TABLE #d;
    INSERT INTO #d EXEC dbo.usp_consultar_destinatarios_retiro_estudiante_grupo
        @idGrupo = @group, @idEstudiante = @studentA, @idCorrelacion = @corr, @idUsuarioEjecutor = @userOtroDocente;
    SET @ok = IIF((SELECT COUNT(*) FROM #d) = 0, 1, 0);
    EXEC #hu51_expect 'R08_RECIPIENTS_SCOPED', @ok;
    PRINT 'TEST_PASS:R-08';

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

-- ------------------------------------------------------------ R-09 consulta de destinatarios con ejecutor nulo: THROW VAL_001
DECLARE @lanzo BIT = 0;
BEGIN TRY
    EXEC dbo.usp_consultar_destinatarios_retiro_estudiante_grupo
        @idGrupo = @group, @idEstudiante = @studentA, @idCorrelacion = @corr, @idUsuarioEjecutor = NULL;
END TRY
BEGIN CATCH
    SET @lanzo = 1;
END CATCH;
EXEC #hu51_expect 'R09_RECIPIENTS_NULL_EXECUTOR_THROWS', @lanzo;
PRINT 'TEST_PASS:R-09';

DROP TABLE #r;
DROP TABLE #d;
PRINT 'TEST_PASS:TEST_USP_RETIRAR_ESTUDIANTE_GRUPO';
GO
