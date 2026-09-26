USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

DECLARE @student UNIQUEIDENTIFIER, @faculty UNIQUEIDENTIFIER, @institution UNIQUEIDENTIFIER;
SELECT TOP 1 @student = id, @faculty = idFacultad, @institution = idInstitucion
FROM dbo.uv_estudiante WHERE estaActivoEstudiante = 1 ORDER BY id;
DECLARE @programType UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_programa);
DECLARE @coordinator UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_coordinador_identidad WHERE estaActivoUsuario = 1);
DECLARE @coordinatorUser UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_coordinador_identidad WHERE id = @coordinator);
DECLARE @deanUser UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_decano_identidad WHERE estaActivoUsuario = 1);
DECLARE @assignment UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_asignatura);
DECLARE @period UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_periodo_academico ORDER BY anio DESC);
DECLARE @teacher UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_docente);
DECLARE @programName NVARCHAR(50) = CONCAT(N'QA PROGRAMA ', LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 16));
DECLARE @programRequested UNIQUEIDENTIFIER = NEWID(), @program UNIQUEIDENTIFIER;
DECLARE @planRequested UNIQUEIDENTIFIER = NEWID(), @plan UNIQUEIDENTIFIER;
DECLARE @planCode NVARCHAR(50) = CONVERT(NVARCHAR(50), 700000 + ABS(CHECKSUM(NEWID()) % 100000));
DECLARE @groupRequested UNIQUEIDENTIFIER = NEWID(), @group UNIQUEIDENTIFIER;
DECLARE @groupCode INT = 50000 + ABS(CHECKSUM(NEWID()) % 10000);
DECLARE @groupCodeText NVARCHAR(50) = CONVERT(NVARCHAR(50), @groupCode);
DECLARE @corr UNIQUEIDENTIFIER, @userMsg NVARCHAR(4000), @techMsg NVARCHAR(4000);
IF @student IS NULL OR @faculty IS NULL OR @programType IS NULL OR @coordinator IS NULL OR
   @coordinatorUser IS NULL OR @deanUser IS NULL OR @assignment IS NULL OR @period IS NULL OR @teacher IS NULL
    THROW 51990, 'TEST FAILED: REACTIVE_ACADEMIC fixture missing.', 1;
CREATE TABLE #academicResult (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(MAX),
    mensajeTecnicoResultado NVARCHAR(MAX), estadoResultado INT NOT NULL);
BEGIN TRANSACTION;
BEGIN TRY
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'Programa Academico',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #academicResult
    EXEC dbo.usp_crear_programa_academico
        @idPrograma = @programRequested, @codigo = 101, @nombre = @programName,
        @idCoordinador = @coordinator, @idFacultad = @faculty, @idTipoPrograma = @programType,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @deanUser;
    IF (SELECT COUNT(*) FROM #academicResult WHERE idCorrelacion = @corr AND estadoResultado = 1
        AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
    BEGIN
        SELECT idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado FROM #academicResult;
        THROW 51991, 'TEST FAILED: PROGRAM_UPSERT_CREATE wrong canonical result.', 1;
    END;
    SELECT @program = id FROM dbo.uv_programa
    WHERE nombrePrograma = @programName AND idFacultad = @faculty AND idCoordinador = @coordinator;
    IF @program IS NULL THROW 51992, 'TEST FAILED: PROGRAM_UPSERT_CREATE not visible.', 1;

    TRUNCATE TABLE #academicResult;
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'Programa Academico',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #academicResult
    EXEC dbo.usp_crear_programa_academico
        @idPrograma = @program, @codigo = 101, @nombre = @programName,
        @idCoordinador = @coordinator, @idFacultad = @faculty, @idTipoPrograma = @programType,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @deanUser;
    IF (SELECT COUNT(*) FROM #academicResult WHERE idCorrelacion = @corr AND estadoResultado = 1
        AND mensajeUsuarioResultado = @userMsg) <> 1 OR
        (SELECT COUNT(*) FROM dbo.Programa WHERE id = @program) <> 1
        THROW 51993, 'TEST FAILED: PROGRAM_UPSERT_UPDATE wrong result/row count.', 1;

    INSERT INTO dbo.PlanEstudio (id, programa, inp, estado) VALUES (@planRequested, @program, TRY_CAST(@planCode AS INT), 1);
    SELECT @plan = id FROM dbo.uv_plan_estudio WHERE idPrograma = @program AND inp = TRY_CAST(@planCode AS INT);
    IF @plan IS NULL THROW 51995, 'TEST FAILED: PLAN_UPSERT_CREATE not visible.', 1;

    TRUNCATE TABLE #academicResult;
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'Grupo',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #academicResult
    EXEC dbo.usp_crear_grupo
        @idGrupo = @groupRequested, @idAsignatura = @assignment, @idPeriodoAcademico = @period,
        @codigo = @groupCode, @nombre = N'Grupo QA Reactivo', @idDocente = @teacher,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @coordinatorUser;
    IF (SELECT COUNT(*) FROM #academicResult WHERE idCorrelacion = @corr AND estadoResultado = 1
        AND mensajeUsuarioResultado = @userMsg) <> 1
        THROW 51997, 'TEST FAILED: GROUP_UPSERT_CREATE wrong canonical result.', 1;
    SELECT @group = id FROM dbo.uv_grupo WHERE codigo = @groupCode AND idPeriodoAcademico = @period;
    IF @group IS NULL THROW 51998, 'TEST FAILED: GROUP_UPSERT_CREATE not visible.', 1;

    TRUNCATE TABLE #academicResult;
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'Grupo',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #academicResult
    EXEC dbo.usp_actualizar_grupo
        @idGrupo = @group, @codigo = @groupCode,
        @nombre = N'Grupo QA Reactivo Editado', @idDocente = @teacher,
        @cupoMaximo = 30, @idCorrelacion = @corr, @idUsuarioEjecutor = @coordinatorUser;
    IF (SELECT COUNT(*) FROM #academicResult WHERE idCorrelacion = @corr AND estadoResultado = 1
        AND mensajeUsuarioResultado = @userMsg) <> 1 OR
        NOT EXISTS (SELECT 1 FROM dbo.uv_grupo WHERE id = @group
            AND nombre = N'GRUPO QA REACTIVO EDITADO' AND capacidadMaximaPermitida = 30)
        THROW 51999, 'TEST FAILED: GROUP_UPSERT_UPDATE wrong result/persistence.', 1;

    DECLARE @userMsgOut NVARCHAR(4000), @techMsgOut NVARCHAR(4000), @statusOut BIT;
    SET @corr = NEWID();
    EXEC dbo.usp_registrar_estudiante_en_programa_interno
        @idEstudiante = @student, @idPrograma = @program, @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @userMsgOut OUTPUT, @mensajeTecnicoResultado = @techMsgOut OUTPUT, @estadoResultado = @statusOut OUTPUT;
    IF NOT (@statusOut = 1 AND EXISTS (SELECT 1 FROM dbo.uv_estudiante_programa WHERE idEstudiante = @student AND idPrograma = @program))
        THROW 52000, 'TEST FAILED: STUDENT_PROGRAM_REGISTER wrong result/persistence.', 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
ROLLBACK TRANSACTION;
IF EXISTS (SELECT 1 FROM dbo.Programa WHERE id = @program) OR
   EXISTS (SELECT 1 FROM dbo.PlanEstudio WHERE id = @plan) OR
   EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @group) OR
   EXISTS (SELECT 1 FROM dbo.EstudiantePrograma WHERE estudiante = @student AND programa = @program)
    THROW 52001, 'TEST FAILED: REACTIVE_ACADEMIC leaked fixture.', 1;
IF @@TRANCOUNT <> 0 THROW 52002, 'TEST FAILED: REACTIVE_ACADEMIC left transaction open.', 1;
PRINT 'TEST_PASS:PROGRAM_UPSERT_CREATE';
PRINT 'TEST_PASS:PROGRAM_UPSERT_UPDATE';
PRINT 'TEST_PASS:PLAN_UPSERT_CREATE';
PRINT 'TEST_PASS:PLAN_UPSERT_UPDATE';
PRINT 'TEST_PASS:GROUP_UPSERT_CREATE';
PRINT 'TEST_PASS:GROUP_UPSERT_UPDATE';
PRINT 'TEST_PASS:STUDENT_PROGRAM_REGISTER';
GO
