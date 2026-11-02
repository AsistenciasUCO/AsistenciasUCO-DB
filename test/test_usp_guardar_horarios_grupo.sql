USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- F1 (2026-10-30): usp_guardar_horarios_grupo. El coordinador del programa reemplaza el horario semanal del grupo.
-- Reglas: formato (HOR_004), franjas del grupo sin traslape (HOR_003, contiguas permitidas), cruce del docente con
-- otro grupo del periodo (HOR_002), ambito (SEC_001/SEC_002). Un rechazo no deja escrituras parciales.
PRINT 'TEST START: test_usp_guardar_horarios_grupo';

DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @idAsig UNIQUEIDENTIFIER, @idProg UNIQUEIDENTIFIER, @uCoord UNIQUEIDENTIFIER;
SELECT TOP 1 @idAsig = a.id, @idProg = pe.idPrograma
FROM dbo.uv_asignatura a
INNER JOIN dbo.uv_semestre_plan_estudio spe ON a.idSemestrePlanEstudio = spe.id
INNER JOIN dbo.uv_plan_estudio pe ON spe.idPlanEstudio = pe.id
INNER JOIN dbo.uv_programa pr ON pe.idPrograma = pr.id AND pr.idCoordinador IS NOT NULL;
SELECT @uCoord = ci.idUsuario FROM dbo.uv_programa pr INNER JOIN dbo.uv_coordinador_identidad ci ON ci.id = pr.idCoordinador WHERE pr.id = @idProg;
DECLARE @idPeriodo UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_periodo_academico ORDER BY anio DESC);
DECLARE @idFacultad UNIQUEIDENTIFIER = (SELECT TOP 1 idFacultad FROM dbo.uv_programa WHERE id = @idProg);
DECLARE @idTipoProg UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoPrograma);
DECLARE @tvCat UNIQUEIDENTIFIER = (SELECT id FROM dbo.TipoVinculacion WHERE codigo = 'CAT');
IF @tipoCC IS NULL OR @idAsig IS NULL OR @uCoord IS NULL OR @idPeriodo IS NULL OR @idFacultad IS NULL OR @idTipoProg IS NULL OR @tvCat IS NULL
    THROW 53200, 'TEST FAILED: faltan fixtures del seed (asignatura, coordinador, periodo, facultad o vinculacion).', 1;

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @uD1 UNIQUEIDENTIFIER = NEWID(), @uD2 UNIQUEIDENTIFIER = NEWID(), @d1 UNIQUEIDENTIFIER = NEWID(), @d2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @uC2 UNIQUEIDENTIFIER = NEWID(), @c2 UNIQUEIDENTIFIER = NEWID(), @p2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uD1, @tipoCC, 972000001, N'Horario', N'Uno', N'Hector', N'Qa', N'qa.horario.d1@test.local', 1, 1, N'HashBackend_H1'),
           (@uD2, @tipoCC, 972000002, N'Horario', N'Dos', N'Helena', N'Qa', N'qa.horario.d2@test.local', 1, 1, N'HashBackend_H2'),
           (@uC2, @tipoCC, 972000003, N'Horario', N'Coord', N'Hugo', N'Qa', N'qa.horario.c2@test.local', 1, 1, N'HashBackend_H3');
    INSERT INTO dbo.Docente (id, usuario) VALUES (@d1, @uD1), (@d2, @uD2);
    INSERT INTO dbo.Coordinador (id, usuario) VALUES (@c2, @uC2);
    INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado)
    VALUES (@p2, @idFacultad, @idTipoProg, N'Programa QA horario ajeno', @c2, 1);
    INSERT INTO dbo.DocentePrograma (id, docente, programa, tipoVinculacion, estado, fechaVinculacionUtc)
    VALUES (NEWID(), @d1, @idProg, @tvCat, 1, SYSUTCDATETIME()), (NEWID(), @d2, @idProg, @tvCat, 1, SYSUTCDATETIME());

    CREATE TABLE #r (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
    DECLARE @corr UNIQUEIDENTIFIER = NEWID();
    DECLARE @userMsg NVARCHAR(4000), @techMsg NVARCHAR(4000);
    DECLARE @base INT = 60000 + ABS(CHECKSUM(NEWID()) % 9000);
    DECLARE @gA UNIQUEIDENTIFIER = NEWID(), @gB UNIQUEIDENTIFIER = NEWID();
    DECLARE @codA INT = @base, @codB INT = @base + 1, @codC INT = @base + 2;

    -- Grupo A (docente 1) y grupo B (docente 2), sin horario
    INSERT INTO #r EXEC dbo.usp_crear_grupo @idGrupo = @gA, @idAsignatura = @idAsig, @idPeriodoAcademico = @idPeriodo, @codigo = @codA,
        @nombre = N'Grupo QA Horario A', @idDocente = @d1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    INSERT INTO #r EXEC dbo.usp_crear_grupo @idGrupo = @gB, @idAsignatura = @idAsig, @idPeriodoAcademico = @idPeriodo, @codigo = @codB,
        @nombre = N'Grupo QA Horario B', @idDocente = @d2, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF (SELECT COUNT(*) FROM #r WHERE estadoResultado = 1) <> 2 THROW 53201, 'TEST FAILED: los grupos de prueba debieron crearse.', 1;

    -- 1. Exito: dos franjas en dias distintos
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_guardar_horarios_grupo @idGrupo = @gA,
        @horariosJSON = N'[{"codigoDia":"LU","horaInicio":"08:00","horaFin":"10:00"},{"codigoDia":"MI","horaInicio":"08:00","horaFin":"10:00"}]',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) OR (SELECT COUNT(*) FROM dbo.uv_horario WHERE idGrupo = @gA) <> 2
        THROW 53210, 'GROUP_SCHEDULE_SAVE_SUCCESS FAILED: debio guardar 2 franjas.', 1;
    PRINT 'TEST_PASS:GROUP_SCHEDULE_SAVE_SUCCESS';

    -- 2. Reemplazo: el horario nuevo sustituye todas las franjas anteriores
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_guardar_horarios_grupo @idGrupo = @gA,
        @horariosJSON = N'[{"codigoDia":"MA","horaInicio":"10:00","horaFin":"12:00"}]',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1)
       OR (SELECT COUNT(*) FROM dbo.uv_horario WHERE idGrupo = @gA) <> 1
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_horario WHERE idGrupo = @gA AND nombreDia = N'Martes' AND horaInicio = '10:00')
        THROW 53220, 'GROUP_SCHEDULE_REPLACE FAILED: debio quedar solo la franja nueva.', 1;
    PRINT 'TEST_PASS:GROUP_SCHEDULE_REPLACE';

    -- 3. Franjas del mismo grupo que se traslapan: HOR_003 y el horario anterior no cambia
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'HOR_003', @p_param1 = N'Lunes 08:00-10:00', @p_param2 = N'Lunes 09:00-11:00',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_guardar_horarios_grupo @idGrupo = @gA,
        @horariosJSON = N'[{"codigoDia":"LU","horaInicio":"08:00","horaFin":"10:00"},{"codigoDia":"LU","horaInicio":"09:00","horaFin":"11:00"}]',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @userMsg
                   AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr))
        THROW 53230, 'GROUP_SCHEDULE_OVERLAP_REJECTED FAILED: debio retornar HOR_003 con las dos franjas.', 1;
    IF (SELECT COUNT(*) FROM dbo.uv_horario WHERE idGrupo = @gA) <> 1 THROW 53231, 'GROUP_SCHEDULE_OVERLAP_REJECTED FAILED: cambio el horario.', 1;
    PRINT 'TEST_PASS:GROUP_SCHEDULE_OVERLAP_REJECTED';

    -- 4. Franjas contiguas el mismo dia: permitidas
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_guardar_horarios_grupo @idGrupo = @gA,
        @horariosJSON = N'[{"codigoDia":"LU","horaInicio":"08:00","horaFin":"10:00"},{"codigoDia":"lu","horaInicio":"10:00","horaFin":"12:00"}]',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) OR (SELECT COUNT(*) FROM dbo.uv_horario WHERE idGrupo = @gA) <> 2
        THROW 53240, 'GROUP_SCHEDULE_ADJACENT_ALLOWED FAILED: las franjas contiguas debieron guardarse.', 1;
    PRINT 'TEST_PASS:GROUP_SCHEDULE_ADJACENT_ALLOWED';

    -- 5. Formato invalido: HOR_004 con el motivo y sin cambios
    DECLARE @casos TABLE (n INT, json NVARCHAR(MAX), motivo NVARCHAR(200));
    INSERT INTO @casos VALUES
        (1, N'[]', N'debe enviar al menos una franja'),
        (2, N'{"codigoDia":"LU"}', N'debe enviar al menos una franja'),
        (3, N'[{"codigoDia":"XX","horaInicio":"08:00","horaFin":"10:00"}]', N'el dia "XX" no existe'),
        (4, N'[{"codigoDia":"LU","horaInicio":"10:00","horaFin":"08:00"}]', N'en Lunes la hora de fin debe ser mayor que la de inicio'),
        (5, N'[{"codigoDia":"LU","horaInicio":"8h","horaFin":"10:00"}]', N'las horas deben tener formato HH:mm'),
        (6, N'[{"codigoDia":"LU","horaInicio":"08:00","horaFin":"10:00","salon":"101"}]', N'cada franja lleva solo codigoDia, horaInicio y horaFin');
    DECLARE @n INT = 1, @json NVARCHAR(MAX), @motivo NVARCHAR(200);
    WHILE @n <= 6
    BEGIN
        SELECT @json = json, @motivo = motivo FROM @casos WHERE n = @n;
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'HOR_004', @p_param1 = @motivo,
            @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
        TRUNCATE TABLE #r;
        INSERT INTO #r EXEC dbo.usp_guardar_horarios_grupo @idGrupo = @gA, @horariosJSON = @json,
            @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
        IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @userMsg)
        BEGIN
            DECLARE @falla NVARCHAR(400) = CONCAT('GROUP_SCHEDULE_INVALID FAILED: caso ', @n, ' debio retornar HOR_004 (', @motivo, ').');
            THROW 53250, @falla, 1;
        END
        SET @n += 1;
    END
    IF (SELECT COUNT(*) FROM dbo.uv_horario WHERE idGrupo = @gA) <> 2 THROW 53251, 'GROUP_SCHEDULE_INVALID FAILED: cambio el horario.', 1;
    PRINT 'TEST_PASS:GROUP_SCHEDULE_INVALID';

    -- 6. Cruce del docente dentro de una transaccion externa: el docente 2 ya tiene el martes 08-10 en el grupo C.
    --    HOR_002, rollback al savepoint (sin franjas parciales) y la transaccion externa se conserva.
    --    ROLLBACK no se permite dentro de INSERT ... EXEC: SQLCMD toma el resultado (TEST_RESULT_*, test_summary.ps1).
    DECLARE @gC UNIQUEIDENTIFIER = NEWID();
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_crear_grupo @idGrupo = @gC, @idAsignatura = @idAsig, @idPeriodoAcademico = @idPeriodo, @codigo = @codC,
        @nombre = N'Grupo QA Horario C', @idDocente = @d2, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_guardar_horarios_grupo @idGrupo = @gC,
        @horariosJSON = N'[{"codigoDia":"MA","horaInicio":"08:00","horaFin":"10:00"}]', @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) THROW 53260, 'GROUP_SCHEDULE_TEACHER_CONFLICT_SAVEPOINT FAILED: fixture del grupo C.', 1;
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'HOR_002', @p_param1 = N'Grupo QA Horario C', @p_param2 = N'Martes 08:00-10:00',
        @p_param3 = @gB, @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    DECLARE @tranAntes INT = @@TRANCOUNT;
    PRINT CONCAT('TEST_EXPECTED_USER:GROUP_SCHEDULE_TEACHER_CONFLICT_SAVEPOINT|', @userMsg);
    PRINT CONCAT('TEST_EXPECTED_TECH:GROUP_SCHEDULE_TEACHER_CONFLICT_SAVEPOINT|', @techMsg, ' Correlacion: ', @corr);
    PRINT 'TEST_RESULT_BEGIN:GROUP_SCHEDULE_TEACHER_CONFLICT_SAVEPOINT';
    EXEC dbo.usp_guardar_horarios_grupo @idGrupo = @gB,
        @horariosJSON = N'[{"codigoDia":"VI","horaInicio":"14:00","horaFin":"16:00"},{"codigoDia":"MA","horaInicio":"09:00","horaFin":"11:00"}]',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    PRINT 'TEST_RESULT_END:GROUP_SCHEDULE_TEACHER_CONFLICT_SAVEPOINT';
    IF @@TRANCOUNT <> @tranAntes THROW 53261, 'GROUP_SCHEDULE_TEACHER_CONFLICT_SAVEPOINT FAILED: altero la transaccion externa.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Horario WHERE grupo = @gB) THROW 53262, 'GROUP_SCHEDULE_TEACHER_CONFLICT_SAVEPOINT FAILED: quedaron franjas parciales.', 1;
    IF (SELECT COUNT(*) FROM dbo.Horario WHERE grupo = @gA) <> 2 OR NOT EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @gC)
        THROW 53263, 'GROUP_SCHEDULE_TEACHER_CONFLICT_SAVEPOINT FAILED: revirtio trabajo previo de la transaccion externa.', 1;
    PRINT 'TEST_STATE_PASS:GROUP_SCHEDULE_TEACHER_CONFLICT_SAVEPOINT';

    -- 8. Ambito: coordinador de otro programa (SEC_002) y ejecutor docente (SEC_001); sin cambios
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_guardar_horarios_grupo @idGrupo = @gA,
        @horariosJSON = N'[{"codigoDia":"JU","horaInicio":"08:00","horaFin":"10:00"}]', @idCorrelacion = @corr, @idUsuarioEjecutor = @uC2;
    SELECT @userMsg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SEC_002';
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @userMsg)
        THROW 53280, 'GROUP_SCHEDULE_SCOPE FAILED: coordinador de otro programa debio retornar SEC_002.', 1;
    -- F3: el docente titular solo define el horario inicial (HOR_005 si ya existe); un docente ajeno al grupo recibe SEC_002
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_guardar_horarios_grupo @idGrupo = @gA,
        @horariosJSON = N'[{"codigoDia":"JU","horaInicio":"08:00","horaFin":"10:00"}]', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    SELECT @userMsg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'HOR_005';
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @userMsg)
        THROW 53281, 'GROUP_SCHEDULE_SCOPE FAILED: docente titular con horario ya definido debio retornar HOR_005.', 1;
    IF EXISTS (SELECT 1 FROM dbo.uv_horario WHERE idGrupo = @gA AND nombreDia = N'Jueves') THROW 53282, 'GROUP_SCHEDULE_SCOPE FAILED: cambio el horario.', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_guardar_horarios_grupo @idGrupo = @gA,
        @horariosJSON = N'[{"codigoDia":"JU","horaInicio":"08:00","horaFin":"10:00"}]', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD2;
    SELECT @userMsg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SEC_002';
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @userMsg)
        THROW 53283, 'GROUP_SCHEDULE_SCOPE FAILED: docente que no es titular debio retornar SEC_002.', 1;
    PRINT 'TEST_PASS:GROUP_SCHEDULE_SCOPE';

    -- 9. F3: el docente crea grupos a su propio nombre (SEC_002 si asigna a otro docente) y define su horario inicial
    DECLARE @gD UNIQUEIDENTIFIER = NEWID(), @gE UNIQUEIDENTIFIER = NEWID(), @codD INT = @base + 3, @codE INT = @base + 4;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_crear_grupo @idGrupo = @gE, @idAsignatura = @idAsig, @idPeriodoAcademico = @idPeriodo, @codigo = @codE,
        @nombre = N'Grupo QA Horario E', @idDocente = @d2, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    SELECT @userMsg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SEC_002';
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @userMsg) OR EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @gE)
        THROW 53284, 'TEACHER_CREATES_GROUP FAILED: docente creando un grupo para otro docente debio retornar SEC_002 sin crearlo.', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_crear_grupo @idGrupo = @gD, @idAsignatura = @idAsig, @idPeriodoAcademico = @idPeriodo, @codigo = @codD,
        @nombre = N'Grupo QA Horario D', @idDocente = @d1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) OR NOT EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @gD AND docente = @d1)
        THROW 53285, 'TEACHER_CREATES_GROUP FAILED: docente debio crear un grupo a su nombre.', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_guardar_horarios_grupo @idGrupo = @gD,
        @horariosJSON = N'[{"codigoDia":"VI","horaInicio":"14:00","horaFin":"16:00"}]', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) OR (SELECT COUNT(*) FROM dbo.uv_horario WHERE idGrupo = @gD) <> 1
        THROW 53286, 'TEACHER_CREATES_GROUP FAILED: docente titular debio definir el horario inicial.', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_guardar_horarios_grupo @idGrupo = @gD,
        @horariosJSON = N'[{"codigoDia":"VI","horaInicio":"15:00","horaFin":"17:00"}]', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    SELECT @userMsg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'HOR_005';
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @userMsg)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_horario WHERE idGrupo = @gD AND horaInicio = '14:00')
        THROW 53287, 'TEACHER_CREATES_GROUP FAILED: segundo guardado del docente debio retornar HOR_005 sin cambios.', 1;
    -- F3: un docente sin vinculo activo con el programa de la asignatura no puede abrir el grupo (SEC_002, sin crearlo)
    DECLARE @uD3 UNIQUEIDENTIFIER = NEWID(), @d3 UNIQUEIDENTIFIER = NEWID(), @gF UNIQUEIDENTIFIER = NEWID(), @codF INT = @base + 5;
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uD3, @tipoCC, 972000004, N'Horario', N'SinVinculo', N'Hilario', N'Qa', N'qa.horario.d3@test.local', 1, 1, N'HashBackend_H4');
    INSERT INTO dbo.Docente (id, usuario) VALUES (@d3, @uD3);
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_crear_grupo @idGrupo = @gF, @idAsignatura = @idAsig, @idPeriodoAcademico = @idPeriodo, @codigo = @codF,
        @nombre = N'Grupo QA Horario F', @idDocente = @d3, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD3;
    SELECT @userMsg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SEC_002';
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @userMsg) OR EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @gF)
        THROW 53288, 'TEACHER_CREATES_GROUP FAILED: docente sin vinculo con el programa debio retornar SEC_002 sin crear el grupo.', 1;
    PRINT 'TEST_PASS:TEACHER_CREATES_GROUP';

    DROP TABLE #r;
    ROLLBACK TRANSACTION;
    IF EXISTS (SELECT 1 FROM dbo.Grupo WHERE id IN (@gA, @gB, @gC, @gD, @gE)) THROW 53290, 'TEST FAILED: quedaron grupos de prueba.', 1;
    IF @@TRANCOUNT <> 0 THROW 53291, 'TEST FAILED: transaccion abierta.', 1;
    PRINT 'TEST END: test_usp_guardar_horarios_grupo (transaccion externa)';
END TRY
BEGIN CATCH
    DECLARE @err NVARCHAR(4000) = ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    IF OBJECT_ID('tempdb..#r') IS NOT NULL DROP TABLE #r;
    THROW 53299, @err, 1;
END CATCH
GO

-- ===== SIN TRANSACCION EXTERNA: el SP es propietario de su transaccion =====
SET NOCOUNT ON;
SET XACT_ABORT OFF;

DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @idAsig UNIQUEIDENTIFIER, @idProg UNIQUEIDENTIFIER, @uCoord UNIQUEIDENTIFIER;
SELECT TOP 1 @idAsig = a.id, @idProg = pe.idPrograma
FROM dbo.uv_asignatura a
INNER JOIN dbo.uv_semestre_plan_estudio spe ON a.idSemestrePlanEstudio = spe.id
INNER JOIN dbo.uv_plan_estudio pe ON spe.idPlanEstudio = pe.id
INNER JOIN dbo.uv_programa pr ON pe.idPrograma = pr.id AND pr.idCoordinador IS NOT NULL;
SELECT @uCoord = ci.idUsuario FROM dbo.uv_programa pr INNER JOIN dbo.uv_coordinador_identidad ci ON ci.id = pr.idCoordinador WHERE pr.id = @idProg;
DECLARE @idPeriodo UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_periodo_academico ORDER BY anio DESC);
DECLARE @tvCat UNIQUEIDENTIFIER = (SELECT id FROM dbo.TipoVinculacion WHERE codigo = 'CAT');
DECLARE @uD UNIQUEIDENTIFIER = NEWID(), @d UNIQUEIDENTIFIER = NEWID(), @gX UNIQUEIDENTIFIER = NEWID(), @gY UNIQUEIDENTIFIER = NEWID();
DECLARE @corr UNIQUEIDENTIFIER = NEWID(), @userMsg NVARCHAR(4000), @techMsg NVARCHAR(4000);
DECLARE @base INT = 69100 + ABS(CHECKSUM(NEWID()) % 800);
DECLARE @codY INT = @base + 1;
CREATE TABLE #r (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);

BEGIN TRY
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uD, @tipoCC, 972000009, N'Horario', N'Propio', N'Hilda', N'Qa', N'qa.horario.own@test.local', 1, 1, N'HashBackend_H9');
    INSERT INTO dbo.Docente (id, usuario) VALUES (@d, @uD);
    INSERT INTO dbo.DocentePrograma (id, docente, programa, tipoVinculacion, estado, fechaVinculacionUtc)
    VALUES (NEWID(), @d, @idProg, @tvCat, 1, SYSUTCDATETIME());
    INSERT INTO #r EXEC dbo.usp_crear_grupo @idGrupo = @gX, @idAsignatura = @idAsig, @idPeriodoAcademico = @idPeriodo, @codigo = @base,
        @nombre = N'Grupo QA Horario X', @idDocente = @d, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    INSERT INTO #r EXEC dbo.usp_crear_grupo @idGrupo = @gY, @idAsignatura = @idAsig, @idPeriodoAcademico = @idPeriodo, @codigo = @codY,
        @nombre = N'Grupo QA Horario Y', @idDocente = @d, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    INSERT INTO #r EXEC dbo.usp_guardar_horarios_grupo @idGrupo = @gX,
        @horariosJSON = N'[{"codigoDia":"LU","horaInicio":"08:00","horaFin":"10:00"}]', @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF (SELECT COUNT(*) FROM #r WHERE estadoResultado = 1) <> 3 OR @@TRANCOUNT <> 0
        THROW 53295, 'GROUP_SCHEDULE_TEACHER_CONFLICT_OWN_TRANSACTION FAILED: fixtures o commit propio.', 1;

    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'HOR_002', @p_param1 = N'Grupo QA Horario X', @p_param2 = N'Lunes 08:00-10:00',
        @p_param3 = @gY, @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    PRINT CONCAT('TEST_EXPECTED_USER:GROUP_SCHEDULE_TEACHER_CONFLICT_OWN_TRANSACTION|', @userMsg);
    PRINT CONCAT('TEST_EXPECTED_TECH:GROUP_SCHEDULE_TEACHER_CONFLICT_OWN_TRANSACTION|', @techMsg, ' Correlacion: ', @corr);
    PRINT 'TEST_RESULT_BEGIN:GROUP_SCHEDULE_TEACHER_CONFLICT_OWN_TRANSACTION';
    EXEC dbo.usp_guardar_horarios_grupo @idGrupo = @gY,
        @horariosJSON = N'[{"codigoDia":"LU","horaInicio":"09:00","horaFin":"11:00"}]', @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    PRINT 'TEST_RESULT_END:GROUP_SCHEDULE_TEACHER_CONFLICT_OWN_TRANSACTION';
    IF @@TRANCOUNT <> 0 THROW 53296, 'GROUP_SCHEDULE_TEACHER_CONFLICT_OWN_TRANSACTION FAILED: dejo una transaccion abierta.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Horario WHERE grupo = @gY) THROW 53297, 'GROUP_SCHEDULE_TEACHER_CONFLICT_OWN_TRANSACTION FAILED: quedaron franjas parciales.', 1;
    PRINT 'TEST_STATE_PASS:GROUP_SCHEDULE_TEACHER_CONFLICT_OWN_TRANSACTION';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DELETE FROM dbo.Horario WHERE grupo IN (@gX, @gY);
    DELETE FROM dbo.Grupo WHERE id IN (@gX, @gY);
    DELETE FROM dbo.DocentePrograma WHERE docente = @d;
    DELETE FROM dbo.Docente WHERE id = @d;
    DELETE FROM dbo.Usuario WHERE id = @uD;
    IF OBJECT_ID('tempdb..#r') IS NOT NULL DROP TABLE #r;
    THROW;
END CATCH

DELETE FROM dbo.Horario WHERE grupo IN (@gX, @gY);
DELETE FROM dbo.Grupo WHERE id IN (@gX, @gY);
DELETE FROM dbo.DocentePrograma WHERE docente = @d;
DELETE FROM dbo.Docente WHERE id = @d;
DELETE FROM dbo.Usuario WHERE id = @uD;
DROP TABLE #r;
IF EXISTS (SELECT 1 FROM dbo.Grupo WHERE id IN (@gX, @gY)) OR EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @uD)
    THROW 53298, 'TEST FAILED: limpieza de test_usp_guardar_horarios_grupo incompleta.', 1;
IF @@TRANCOUNT <> 0 THROW 53294, 'TEST FAILED: test_usp_guardar_horarios_grupo dejo transacciones abiertas.', 1;
PRINT 'TEST END: test_usp_guardar_horarios_grupo (sin transaccion externa)';
GO
