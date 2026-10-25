USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- HU081/HU082/HU083 (T-081-01..02, T-082-01..03, T-083-01..02): estado del plan de estudios y semestres.
--   usp_cambiar_estado_plan_estudio, usp_agregar_semestre_plan_estudio, usp_quitar_semestre_plan_estudio.
PRINT 'TEST START: test_usp_plan_estudio_estado_semestres';

DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @idFacultad UNIQUEIDENTIFIER = (SELECT TOP 1 idFacultad FROM dbo.uv_programa);
DECLARE @idTipoProg UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoPrograma);
DECLARE @idArea UNIQUEIDENTIFIER, @idComponente UNIQUEIDENTIFIER;
SELECT TOP 1 @idArea = area, @idComponente = componente FROM dbo.Asignatura;
DECLARE @maxSemestres INT = (SELECT MAX(numero) FROM dbo.Semestre);
IF @tipoCC IS NULL OR @idFacultad IS NULL OR @idTipoProg IS NULL OR @idArea IS NULL OR @maxSemestres IS NULL
    THROW 52700, 'TEST FAILED: faltan fixtures base.', 1;

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @uC1 UNIQUEIDENTIFIER = NEWID(), @uC2 UNIQUEIDENTIFIER = NEWID(), @uD UNIQUEIDENTIFIER = NEWID();
    DECLARE @cC1 UNIQUEIDENTIFIER = NEWID(), @cC2 UNIQUEIDENTIFIER = NEWID(), @dD UNIQUEIDENTIFIER = NEWID();
    DECLARE @p1 UNIQUEIDENTIFIER = NEWID(), @p2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @pl1 UNIQUEIDENTIFIER = NEWID(), @pl2 UNIQUEIDENTIFIER = NEWID(), @corr UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uC1, @tipoCC, 970000081, N'Coord', N'Uno', N'Carla', N'Qa', N'qa.c1.hu081@test.local', 1, 1, N'HashBackend_P1'),
           (@uC2, @tipoCC, 970000082, N'Coord', N'Dos', N'Ciro',  N'Qa', N'qa.c2.hu081@test.local', 1, 1, N'HashBackend_P2'),
           (@uD,  @tipoCC, 970000083, N'Docente', N'Uno', N'Dana', N'Qa', N'qa.doc.hu081@test.local', 1, 1, N'HashBackend_P3');
    INSERT INTO dbo.Coordinador (id, usuario) VALUES (@cC1, @uC1), (@cC2, @uC2);
    INSERT INTO dbo.Docente (id, usuario) VALUES (@dD, @uD);
    INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado)
    VALUES (@p1, @idFacultad, @idTipoProg, N'Programa QA 081-1', @cC1, 1), (@p2, @idFacultad, @idTipoProg, N'Programa QA 081-2', @cC2, 1);
    INSERT INTO dbo.PlanEstudio (id, programa, inp, estado) VALUES (@pl1, @p1, 8101, 1), (@pl2, @p2, 8102, 1);

    CREATE TABLE #r (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
    DECLARE @msg NVARCHAR(4000), @i INT;

    -- T-081-01: inactivar, idempotencia y reactivacion del plan propio
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_plan_estudio
        @idPlanEstudio = @pl1, @estaActivo = 0, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) THROW 52710, 'T-081-01 FAILED: inactivar no retorno exito.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.PlanEstudio WHERE id = @pl1 AND estado = 0) THROW 52711, 'T-081-01 FAILED: el plan sigue activo.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_plan_estudio WHERE id = @pl1 AND estaActivoPlanEstudio = 0 AND estaActivoTextoPlanEstudio = 'NO')
        THROW 52715, 'T-081-01 FAILED: uv_plan_estudio no refleja el plan inactivo.', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_plan_estudio
        @idPlanEstudio = @pl1, @estaActivo = 0, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) THROW 52712, 'T-081-01 FAILED: inactivar dos veces debio ser exitoso (idempotente).', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_plan_estudio
        @idPlanEstudio = @pl1, @estaActivo = 1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) THROW 52713, 'T-081-01 FAILED: reactivar no retorno exito.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.PlanEstudio WHERE id = @pl1 AND estado = 1) THROW 52714, 'T-081-01 FAILED: el plan no quedo activo.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_plan_estudio WHERE id = @pl1 AND estaActivoPlanEstudio = 1)
        THROW 52716, 'T-081-01 FAILED: uv_plan_estudio no refleja el plan reactivado.', 1;
    PRINT 'TEST_PASS:T-081-01';

    -- T-081-02: ambito, RBAC, plan inexistente y parametros obligatorios
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SEC_002';
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_plan_estudio    -- C1 sobre el plan de P2
        @idPlanEstudio = @pl2, @estaActivo = 0, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) THROW 52720, 'T-081-02 FAILED: plan ajeno debio retornar SEC_002.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.PlanEstudio WHERE id = @pl2 AND estado = 1) THROW 52721, 'T-081-02 FAILED: el plan ajeno cambio.', 1;
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SEC_001';
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_plan_estudio    -- ejecutor docente
        @idPlanEstudio = @pl1, @estaActivo = 0, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) THROW 52722, 'T-081-02 FAILED: ejecutor docente debio retornar SEC_001.', 1;
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'PLA_002';
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_plan_estudio    -- plan inexistente
        @idPlanEstudio = NULL, @estaActivo = 0, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) THROW 52723, 'T-081-02 FAILED: plan inexistente debio retornar PLA_002.', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_plan_estudio    -- estado obligatorio
        @idPlanEstudio = @pl1, @estaActivo = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0) THROW 52724, 'T-081-02 FAILED: @estaActivo NULL debio rechazarse.', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_plan_estudio    -- ejecutor obligatorio
        @idPlanEstudio = @pl1, @estaActivo = 0, @idCorrelacion = @corr, @idUsuarioEjecutor = NULL;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0) THROW 52725, 'T-081-02 FAILED: ejecutor NULL debio rechazarse.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.PlanEstudio WHERE id = @pl1 AND estado = 1) THROW 52726, 'T-081-02 FAILED: un rechazo modifico el plan.', 1;
    PRINT 'TEST_PASS:T-081-02';

    -- T-082-01: altas consecutivas desde un plan sin semestres
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_agregar_semestre_plan_estudio @idPlanEstudio = @pl1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_agregar_semestre_plan_estudio @idPlanEstudio = @pl1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) THROW 52730, 'T-082-01 FAILED: agregar semestre no retorno exito.', 1;
    IF (SELECT COUNT(1) FROM dbo.uv_semestre_plan_estudio WHERE idPlanEstudio = @pl1) <> 2
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_semestre_plan_estudio WHERE idPlanEstudio = @pl1 AND numeroSemestre = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_semestre_plan_estudio WHERE idPlanEstudio = @pl1 AND numeroSemestre = 2)
        THROW 52731, 'T-082-01 FAILED: el plan debio quedar con los semestres 1 y 2.', 1;
    PRINT 'TEST_PASS:T-082-01';

    -- T-082-02: no supera el maximo del catalogo dbo.Semestre
    SET @i = 2;
    WHILE @i < @maxSemestres
    BEGIN
        TRUNCATE TABLE #r;
        INSERT INTO #r EXEC dbo.usp_agregar_semestre_plan_estudio @idPlanEstudio = @pl1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
        SET @i += 1;
    END
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'PLA_003';
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_agregar_semestre_plan_estudio @idPlanEstudio = @pl1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) THROW 52740, 'T-082-02 FAILED: superar el maximo debio retornar PLA_003.', 1;
    IF (SELECT COUNT(1) FROM dbo.SemestrePlanEstudio WHERE planEstudio = @pl1) <> @maxSemestres THROW 52741, 'T-082-02 FAILED: el plan debio quedar con el maximo de semestres.', 1;
    PRINT 'TEST_PASS:T-082-02';

    -- T-082-03: ambito y plan inexistente
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SEC_002';
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_agregar_semestre_plan_estudio @idPlanEstudio = @pl2, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) THROW 52750, 'T-082-03 FAILED: plan ajeno debio retornar SEC_002.', 1;
    IF EXISTS (SELECT 1 FROM dbo.SemestrePlanEstudio WHERE planEstudio = @pl2) THROW 52751, 'T-082-03 FAILED: se agrego un semestre al plan ajeno.', 1;
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'PLA_002';
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_agregar_semestre_plan_estudio @idPlanEstudio = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) THROW 52752, 'T-082-03 FAILED: plan inexistente debio retornar PLA_002.', 1;
    PRINT 'TEST_PASS:T-082-03';

    -- T-083-01: reglas de negocio al quitar (pertenencia, ultimo semestre, sin asignaturas)
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'PLA_005';
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_quitar_semestre_plan_estudio @idPlanEstudio = @pl1, @numeroSemestre = 1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) THROW 52760, 'T-083-01 FAILED: quitar un semestre intermedio debio retornar PLA_005.', 1;
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'PLA_004';
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_quitar_semestre_plan_estudio @idPlanEstudio = @pl2, @numeroSemestre = 1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC2;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) THROW 52761, 'T-083-01 FAILED: semestre ajeno al plan debio retornar PLA_004.', 1;
    DECLARE @spUltimo UNIQUEIDENTIFIER = (
        SELECT sp.id FROM dbo.SemestrePlanEstudio sp INNER JOIN dbo.Semestre s ON s.id = sp.semestre
        WHERE sp.planEstudio = @pl1 AND s.numero = @maxSemestres);
    INSERT INTO dbo.Asignatura (id, codigo, nombre, credito, area, componente, semestrePlanEstudio, estado)
    VALUES (NEWID(), N'QA-HU083', N'Asignatura QA 083', 3, @idArea, @idComponente, @spUltimo, 0);
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'PLA_006';
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_quitar_semestre_plan_estudio @idPlanEstudio = @pl1, @numeroSemestre = @maxSemestres, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) THROW 52762, 'T-083-01 FAILED: semestre con asignaturas (aunque inactivas) debio retornar PLA_006.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.SemestrePlanEstudio WHERE id = @spUltimo) THROW 52763, 'T-083-01 FAILED: se quito un semestre con asignaturas.', 1;
    DELETE FROM dbo.Asignatura WHERE semestrePlanEstudio = @spUltimo;
    PRINT 'TEST_PASS:T-083-01';

    -- T-083-02: quitar el ultimo semestre vacio, ambito y parametros obligatorios
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SEC_002';
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_quitar_semestre_plan_estudio @idPlanEstudio = @pl1, @numeroSemestre = @maxSemestres, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC2;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) THROW 52770, 'T-083-02 FAILED: plan ajeno debio retornar SEC_002.', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_quitar_semestre_plan_estudio @idPlanEstudio = @pl1, @numeroSemestre = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0) THROW 52771, 'T-083-02 FAILED: @numeroSemestre NULL debio rechazarse.', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_quitar_semestre_plan_estudio @idPlanEstudio = @pl1, @numeroSemestre = @maxSemestres, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) THROW 52772, 'T-083-02 FAILED: quitar el ultimo semestre vacio no retorno exito.', 1;
    IF EXISTS (SELECT 1 FROM dbo.SemestrePlanEstudio WHERE id = @spUltimo) THROW 52773, 'T-083-02 FAILED: el ultimo semestre no se quito.', 1;
    IF (SELECT COUNT(1) FROM dbo.SemestrePlanEstudio WHERE planEstudio = @pl1) <> @maxSemestres - 1 THROW 52774, 'T-083-02 FAILED: se quitaron mas semestres de los esperados.', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_agregar_semestre_plan_estudio @idPlanEstudio = @pl1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_semestre_plan_estudio WHERE idPlanEstudio = @pl1 AND numeroSemestre = @maxSemestres)
        THROW 52775, 'T-083-02 FAILED: tras quitar, agregar debio reponer el ultimo semestre.', 1;
    PRINT 'TEST_PASS:T-083-02';

    DROP TABLE #r;
    ROLLBACK TRANSACTION;
    PRINT 'TEST_PASS:TEST_USP_PLAN_ESTUDIO_ESTADO_SEMESTRES';
END TRY
BEGIN CATCH
    DECLARE @err NVARCHAR(4000) = ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    IF OBJECT_ID('tempdb..#r') IS NOT NULL DROP TABLE #r;
    THROW 52999, @err, 1;
END CATCH
GO
