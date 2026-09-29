USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT 'TEST START: test_group_capacity_decoupling';

-- LB-002.1C-A: la validacion de "grupo valido" (usp_validar_grupo_exista_por_id_interno) esta desacoplada de la
-- validacion de "cupo para matricular" (usp_validar_cupo_disponible_grupo_interno).
--   Grupo existente, habilitado y LLENO -> crear/programar sesion: PERMITIDO.
--   Grupo existente, habilitado y LLENO -> matricular un estudiante: RECHAZADO con ERR_CUPO_SUPERADO.
-- El rechazo de la matricula por el SP publico (sin Usuario/Estudiante parciales) lo cubre STUDENT_CAPACITY_EXCEEDED
-- en test_usp_registrar_estudiante_en_grupo_usuario_no_existente.sql.
DECLARE @baseGroup UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_grupo WHERE grupoEstaHablitado = 1 AND cuposDisponibles > 0 ORDER BY cuposDisponibles DESC);
DECLARE @assignment UNIQUEIDENTIFIER = (SELECT idAsignatura FROM dbo.uv_grupo WHERE id = @baseGroup);
DECLARE @period UNIQUEIDENTIFIER = (SELECT idPeriodoAcademico FROM dbo.uv_grupo WHERE id = @baseGroup);
DECLARE @teacher UNIQUEIDENTIFIER = (SELECT idDocente FROM dbo.uv_grupo WHERE id = @baseGroup);
DECLARE @teacherUser UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_docente_identidad WHERE id = @teacher);
DECLARE @existingStudent UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Estudiante);
DECLARE @activeState UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_estado_estudiante_grupo WHERE codigo = 'A');
DECLARE @fullGroup UNIQUEIDENTIFIER = NEWID();
DECLARE @corr UNIQUEIDENTIFIER = NEWID();
DECLARE @userMsg NVARCHAR(4000), @techMsg NVARCHAR(4000), @state BIT;
DECLARE @expectedUser NVARCHAR(4000), @expectedTech NVARCHAR(4000);

IF @baseGroup IS NULL OR @teacher IS NULL OR @teacherUser IS NULL OR @existingStudent IS NULL OR @activeState IS NULL
    THROW 52000, 'TEST FAILED: CAPACITY_DECOUPLING fixture missing.', 1;

BEGIN TRANSACTION;
BEGIN TRY
    INSERT dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes,
        cantidadEstudiantesFinalizaron, cantidadEstudiantesCancelaronVoluntadPropia,
        cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@fullGroup, @assignment, @period, 400000 + ABS(CHECKSUM(NEWID()) % 100000),
        N'Grupo QA Lleno Desacople', 1, 0, 0, 0, @teacher);
    INSERT dbo.EstudianteGrupo (id, estado, estudiante, grupo)
    VALUES (NEWID(), @activeState, @existingStudent, @fullGroup);

    IF NOT EXISTS (SELECT 1 FROM dbo.uv_grupo WHERE id = @fullGroup AND grupoEstaHablitado = 1 AND cuposDisponibles <= 0)
        THROW 52001, 'TEST FAILED: CAPACITY_DECOUPLING fixture is not an enabled, full group.', 1;

    -- 1) Validador de grupo: un grupo lleno pero habilitado ES valido (base de crear/generar sesiones y registrar docente).
    EXEC dbo.usp_validar_grupo_exista_por_id_interno
        @idGrupo = @fullGroup, @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT,
        @estadoResultado = @state OUTPUT;
    IF @state <> 1
        THROW 52002, 'TEST FAILED: usp_validar_grupo_exista_por_id_interno rechazo un grupo lleno (cupo no es responsabilidad de la validacion de grupo).', 1;
    PRINT 'TEST_PASS:CAPACITY_GROUP_VALIDATOR_ALLOWS_FULL_GROUP';

    -- 2) Validador de cupo: el mismo grupo lleno se rechaza con ERR_CUPO_SUPERADO (canal DBCODE estable).
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'ERR_CUPO_SUPERADO', @p_param1 = @fullGroup,
        @mensajeUsuarioResultado = @expectedUser OUTPUT, @mensajeTecnicoResultado = @expectedTech OUTPUT;
    EXEC dbo.usp_validar_cupo_disponible_grupo_interno
        @idGrupo = @fullGroup, @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT,
        @estadoResultado = @state OUTPUT;
    IF @state <> 0
        THROW 52003, 'TEST FAILED: usp_validar_cupo_disponible_grupo_interno acepto un grupo lleno.', 1;
    IF @techMsg NOT LIKE 'DBCODE=ERR_CUPO_SUPERADO|%'
        THROW 52004, 'TEST FAILED: cupo lleno no expuso DBCODE=ERR_CUPO_SUPERADO.', 1;
    IF @userMsg <> @expectedUser OR @techMsg <> CONCAT(@expectedTech, ' Correlacion: ', @corr)
        THROW 52005, 'TEST FAILED: cupo lleno no retorno el mensaje canonico del catalogo.', 1;
    PRINT 'TEST_PASS:CAPACITY_VALIDATOR_REJECTS_FULL_GROUP';

    -- 3) Comando publico Golden Path: crear sesion en el grupo lleno es PERMITIDO.
    CREATE TABLE #sessionOnFullGroup (
        idCorrelacion UNIQUEIDENTIFIER NULL,
        mensajeUsuarioResultado NVARCHAR(4000) NULL,
        mensajeTecnicoResultado NVARCHAR(4000) NULL,
        estadoResultado BIT NOT NULL
    );
    DECLARE @sessionCorr UNIQUEIDENTIFIER = NEWID();
    DECLARE @sessionStart DATETIME2 = DATEADD(HOUR, 1, SYSUTCDATETIME());
    DECLARE @sessionEnd DATETIME2 = DATEADD(HOUR, 2, SYSUTCDATETIME());
    INSERT INTO #sessionOnFullGroup
    EXEC dbo.usp_crear_sesion
        @idGrupo = @fullGroup, @nombre = N'Sesion QA Grupo Lleno',
        @fechaHoraInicio = @sessionStart, @fechaHoraFin = @sessionEnd,
        @idCorrelacion = @sessionCorr, @idUsuarioEjecutor = @teacherUser;
    IF (SELECT COUNT(*) FROM #sessionOnFullGroup WHERE estadoResultado = 1 AND idCorrelacion = @sessionCorr) <> 1
        THROW 52006, 'TEST FAILED: usp_crear_sesion no permitio programar una sesion en un grupo lleno.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Sesion WHERE grupo = @fullGroup AND nombre = N'Sesion QA Grupo Lleno')
        THROW 52007, 'TEST FAILED: la sesion del grupo lleno no fue persistida.', 1;
    IF (SELECT COUNT(*) FROM dbo.EstudianteGrupo WHERE grupo = @fullGroup) <> 1
        THROW 52008, 'TEST FAILED: crear sesion en grupo lleno altero la matricula del grupo.', 1;
    DROP TABLE #sessionOnFullGroup;
    PRINT 'TEST_PASS:SESSION_CREATE_ALLOWED_ON_FULL_GROUP';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
ROLLBACK TRANSACTION;
IF @@TRANCOUNT <> 0 THROW 52009, 'TEST FAILED: test_group_capacity_decoupling left an open transaction.', 1;
PRINT 'TEST END: test_group_capacity_decoupling';
GO
