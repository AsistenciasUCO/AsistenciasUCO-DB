USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ============================================================================
-- INT-HU-01 (decision de John 2026-10-28, opcion a) reescrita por CULM-001 A (E-14, DEC-009): un estudiante retirado
-- del grupo por el docente (HU051, matricula 'I') vuelve a ser matriculado A MANO por el docente titular (HU050,
-- usp_registrar_estudiante_en_grupo): se REACTIVA la misma matricula (I -> A) en lugar de fallar con 409 por duplicado.
-- El cupo se respeta (HU055, lista de espera, se descarta: ahora se rechaza con ERR_CUPO_SUPERADO) y una matricula
-- ACTIVA sigue impidiendo la nueva matricula (ERR_MATRICULA_DUPLICADA). Fixtures dentro de UNA transaccion con
-- ROLLBACK final; T-12a: @@TRANCOUNT = 1 antes del ROLLBACK y 0 al final.
-- ============================================================================
PRINT 'TEST START: test_int_hu01_reactivar_matricula_retirada';

DECLARE @group UNIQUEIDENTIFIER, @teacher UNIQUEIDENTIFIER, @periodo UNIQUEIDENTIFIER, @userT UNIQUEIDENTIFIER, @tipoCC UNIQUEIDENTIFIER;
SELECT TOP 1 @group = g.id, @teacher = g.docente, @periodo = g.periodoAcademico FROM dbo.Grupo g ORDER BY g.id;
SELECT @userT = usuario FROM dbo.Docente WHERE id = @teacher;
SELECT TOP 1 @tipoCC = id FROM dbo.TipoIdentificacion ORDER BY id;
IF @group IS NULL OR @userT IS NULL OR @tipoCC IS NULL
    THROW 54200, 'TEST FAILED: INT_HU01 fixture missing (seed data).', 1;

DECLARE @corr UNIQUEIDENTIFIER = NEWID(), @msgU NVARCHAR(4000), @msgT NVARCHAR(4000);
DECLARE @zona NVARCHAR(100) = dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER');
DECLARE @hoyLocal DATE = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE @zona AS DATE);
DECLARE @u1 UNIQUEIDENTIFIER = NEWID(), @e1 UNIQUEIDENTIFIER = NEWID();
DECLARE @egOriginal UNIQUEIDENTIFIER, @filasAntes INT;

CREATE TABLE #r (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);

BEGIN TRANSACTION;
BEGIN TRY
    -- Periodo vigente y cupos holgados.
    UPDATE dbo.PeriodoAcademico SET fechaFin = DATEADD(DAY, 30, @hoyLocal) WHERE id = @periodo;
    UPDATE dbo.Grupo SET cantidadEstudiantes = (SELECT COUNT(*) FROM dbo.uv_estudiante_grupo
        WHERE idGrupo = @group AND codigoEstadoEstudiante = 'A') + 2 WHERE id = @group;

    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@u1, @tipoCC, 970009001, N'Uno', N'Qa', N'Est', N'Int', N'qa.inthu01.1@test.local', 1, 1, N'HashBackend_R1');
    INSERT INTO dbo.Estudiante (id, usuario) VALUES (@e1, @u1);

    -- E1 matriculado a mano por el docente titular y luego retirado (HU051: A -> I).
    INSERT INTO #r EXEC dbo.usp_registrar_estudiante_en_grupo @idGrupo = @group, @numeroIdentificacion = 970009001,
        @primerNombre = N'Est', @segundoNombre = N'Int', @primerApellido = N'Uno', @segundoApellido = N'Qa',
        @correo = N'qa.inthu01.1@test.local', @password = N'HashBackend_R1', @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    SELECT @egOriginal = id FROM dbo.EstudianteGrupo WHERE grupo = @group AND estudiante = @e1;
    INSERT INTO #r EXEC dbo.usp_retirar_estudiante_grupo @idGrupo = @group, @idEstudiante = @e1, @motivo = N'Retiro QA', @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    IF @egOriginal IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo WHERE idGrupo = @group AND idEstudiante = @e1 AND codigoEstadoEstudiante = 'I')
        THROW 54201, 'TEST FAILED: INT_HU01 precondicion (matricula retirada I).', 1;

    -- RM-01 (T-03): la matricula manual de un retirado REACTIVA la misma matricula (A), sin duplicar filas, con GEN_004.
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_registrar_estudiante_en_grupo @idGrupo = @group, @numeroIdentificacion = 970009001,
        @primerNombre = N'Est', @segundoNombre = N'Int', @primerApellido = N'Uno', @segundoApellido = N'Qa',
        @correo = N'qa.inthu01.1@test.local', @password = N'HashBackend_R1', @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'Estudiante en Grupo',
        @mensajeUsuarioResultado = @msgU OUTPUT, @mensajeTecnicoResultado = @msgT OUTPUT;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND mensajeUsuarioResultado = @msgU)
        THROW 54202, 'TEST FAILED: RM-01 matricular a un retirado debe responder GEN_004 (exito), no 409.', 1;
    IF (SELECT COUNT(*) FROM dbo.EstudianteGrupo WHERE grupo = @group AND estudiante = @e1) <> 1
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo WHERE id = @egOriginal AND codigoEstadoEstudiante = 'A')
        THROW 54203, 'TEST FAILED: RM-01 se esperaba la MISMA matricula reactivada (A).', 1;
    IF @@TRANCOUNT <> 1 THROW 54206, 'TEST FAILED: RM-01 altero el nivel de transaccion del llamador (T-12a).', 1;
    PRINT 'TEST_PASS:INT_HU01_RM01_REACTIVA_MATRICULA';

    -- RM-03 (T-06): con matricula ACTIVA, la nueva matricula manual se rechaza (ERR_MATRICULA_DUPLICADA, sin cambios).
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_registrar_estudiante_en_grupo @idGrupo = @group, @numeroIdentificacion = 970009001,
        @primerNombre = N'Est', @segundoNombre = N'Int', @primerApellido = N'Uno', @segundoApellido = N'Qa',
        @correo = N'qa.inthu01.1@test.local', @password = N'HashBackend_R1', @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'ERR_MATRICULA_DUPLICADA', @p_param1 = @e1, @p_param2 = @group,
        @mensajeUsuarioResultado = @msgU OUTPUT, @mensajeTecnicoResultado = @msgT OUTPUT;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msgU)
       OR (SELECT COUNT(*) FROM dbo.EstudianteGrupo WHERE grupo = @group AND estudiante = @e1) <> 1
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo WHERE id = @egOriginal AND codigoEstadoEstudiante = 'A')
        THROW 54205, 'TEST FAILED: RM-03 matricula activa duplicada debe seguir rechazandose (ERR_MATRICULA_DUPLICADA).', 1;
    IF @@TRANCOUNT <> 1 THROW 54207, 'TEST FAILED: RM-03 altero el nivel de transaccion del llamador (T-12a).', 1;
    PRINT 'TEST_PASS:INT_HU01_RM03_ACTIVA_SIGUE_BLOQUEADA';

    -- RM-02 (T-05): el cupo se respeta. E1 vuelve a quedar retirado y el grupo queda lleno: la reactivacion se rechaza
    -- con ERR_CUPO_SUPERADO, E1 sigue en I y no hay filas nuevas.
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_retirar_estudiante_grupo @idGrupo = @group, @idEstudiante = @e1, @motivo = N'Retiro QA 2', @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    UPDATE dbo.Grupo SET cantidadEstudiantes = (SELECT COUNT(*) FROM dbo.uv_estudiante_grupo
        WHERE idGrupo = @group AND codigoEstadoEstudiante = 'A') WHERE id = @group;
    SET @filasAntes = (SELECT COUNT(*) FROM dbo.EstudianteGrupo);
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_registrar_estudiante_en_grupo @idGrupo = @group, @numeroIdentificacion = 970009001,
        @primerNombre = N'Est', @segundoNombre = N'Int', @primerApellido = N'Uno', @segundoApellido = N'Qa',
        @correo = N'qa.inthu01.1@test.local', @password = N'HashBackend_R1', @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    SELECT @msgU = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'ERR_CUPO_SUPERADO';
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msgU)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo WHERE id = @egOriginal AND codigoEstadoEstudiante = 'I')
       OR (SELECT COUNT(*) FROM dbo.EstudianteGrupo) <> @filasAntes
        THROW 54204, 'TEST FAILED: RM-02 sin cupo la reactivacion debe rechazarse (ERR_CUPO_SUPERADO) sin cambios.', 1;
    PRINT 'TEST_PASS:INT_HU01_RM02_CUPO_RESPETADO';

    IF @@TRANCOUNT <> 1 THROW 54298, 'TEST FAILED: el objeto altero el nivel de transaccion del llamador.', 1;
    ROLLBACK TRANSACTION;
    PRINT '-> Rollback transaccional ejecutado. Cero residuos.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT CONCAT('ERROR EN TEST: ', ERROR_MESSAGE());
    THROW;
END CATCH;

IF @@TRANCOUNT <> 0
    THROW 54299, 'TEST FAILED: test_int_hu01_reactivar_matricula_retirada dejo transacciones abiertas.', 1;
DROP TABLE IF EXISTS #r;
PRINT 'TEST END: test_int_hu01_reactivar_matricula_retirada';
GO
