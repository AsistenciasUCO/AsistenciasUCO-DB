USE [gestionasistenciadb];
GO

-- CC-003G-01: contrato del proveedor publico dbo.usp_registrar_o_actualizar_plan_estudio.
-- Los escenarios cuya ruta ejecuta ROLLBACK dentro del SP no pueden capturarse con INSERT ... EXEC
-- (error 3915): se emiten entre marcadores TEST_RESULT_BEGIN/END y los verifica test_summary.ps1.
SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT 'TEST START: test_usp_registrar_o_actualizar_plan_estudio';

IF OBJECT_ID('dbo.usp_registrar_o_actualizar_plan_estudio', 'P') IS NULL
    THROW 53200, 'TEST FAILED: PLAN_PUBLIC_METADATA procedimiento publico ausente.', 1;

DECLARE @firmaEsperada NVARCHAR(MAX) = N'@idPlanEstudio:uniqueidentifier:0,@idPrograma:uniqueidentifier:0,@inp:int:0,'
    + N'@idCorrelacion:uniqueidentifier:0,@idUsuarioEjecutor:uniqueidentifier:0';
DECLARE @firmaReal NVARCHAR(MAX) = (
    SELECT STRING_AGG(CONCAT(p.name, ':', TYPE_NAME(p.user_type_id), ':', CONVERT(INT, p.is_output)), ',')
           WITHIN GROUP (ORDER BY p.parameter_id)
    FROM sys.parameters p WHERE p.object_id = OBJECT_ID('dbo.usp_registrar_o_actualizar_plan_estudio'));
IF @firmaReal IS NULL OR @firmaReal <> @firmaEsperada
    THROW 53201, 'TEST FAILED: PLAN_PUBLIC_METADATA la firma no coincide con el contrato (backend + idUsuarioEjecutor).', 1;

IF (SELECT COUNT(*) FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID('dbo.usp_registrar_o_actualizar_plan_estudio'), NULL)
    WHERE error_number IS NULL) <> 4
   OR EXISTS (
        SELECT 1 FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID('dbo.usp_registrar_o_actualizar_plan_estudio'), NULL)
        WHERE (column_ordinal = 1 AND (name <> 'idCorrelacion' OR system_type_name <> 'uniqueidentifier'))
           OR (column_ordinal = 2 AND (name <> 'mensajeUsuarioResultado' OR system_type_name NOT LIKE 'nvarchar%'))
           OR (column_ordinal = 3 AND (name <> 'mensajeTecnicoResultado' OR system_type_name NOT LIKE 'nvarchar%'))
           OR (column_ordinal = 4 AND (name <> 'estadoResultado' OR system_type_name <> 'bit')))
    THROW 53202, 'TEST FAILED: PLAN_PUBLIC_METADATA el resultset no es el canonico de 4 columnas.', 1;

-- El ejecutor es fail-closed: el parametro admite NULL solo para que el SP lo rechace de forma canonica.
IF (SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.usp_registrar_o_actualizar_plan_estudio'))) NOT LIKE '%@idUsuarioEjecutor IS NULL%'
    THROW 53203, 'TEST FAILED: PLAN_PUBLIC_METADATA el SP no rechaza explicitamente un ejecutor ausente.', 1;
PRINT 'TEST_PASS:PLAN_PUBLIC_METADATA';
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

DECLARE @prog1 UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_programa ORDER BY id);
DECLARE @coord1 UNIQUEIDENTIFIER = (
    SELECT TOP 1 ci.idUsuario FROM dbo.uv_programa p JOIN dbo.uv_coordinador_identidad ci ON ci.id = p.idCoordinador
    WHERE p.id = @prog1 AND ci.estaActivoUsuario = 1);
DECLARE @estudiante UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_estudiante_identidad WHERE estaActivoUsuario = 1);
DECLARE @decano UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_decano_identidad WHERE estaActivoUsuario = 1);
DECLARE @tipo UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
IF @prog1 IS NULL OR @coord1 IS NULL OR @estudiante IS NULL OR @decano IS NULL OR @tipo IS NULL
    THROW 53204, 'TEST FAILED: fixtures de programa/coordinador/estudiante/decano ausentes.', 1;

DECLARE @sufijo NVARCHAR(32) = REPLACE(CONVERT(NVARCHAR(36), NEWID()), '-', '');
DECLARE @corr UNIQUEIDENTIFIER, @expU NVARCHAR(4000), @expT NVARCHAR(4000), @ok BIT;
DECLARE @inp1 INT = 4000 + ABS(CHECKSUM(NEWID()) % 4000);
DECLARE @inp2 INT = @inp1 + 5000;
DECLARE @inp3 INT = @inp2 + 1, @inp4 INT = @inp2 + 2, @inp5 INT = @inp2 + 11;
DECLARE @planRnd UNIQUEIDENTIFIER = NEWID(), @progRnd UNIQUEIDENTIFIER = NEWID();
DECLARE @plan1 UNIQUEIDENTIFIER = NEWID(), @planB UNIQUEIDENTIFIER = NEWID(), @planDup UNIQUEIDENTIFIER = NEWID();
DECLARE @conteo1 INT, @tranAntes INT, @firmaPlanAntes INT;
DECLARE @sys001 NVARCHAR(4000) = (SELECT contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SYS_001');

CREATE TABLE #r (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);

BEGIN TRANSACTION;
BEGIN TRY
    SET @tranAntes = @@TRANCOUNT;

    -- ===== Fixtures (se revierten): segundo programa con coordinador distinto, y coordinador inactivo =====
    DECLARE @user2 UNIQUEIDENTIFIER = NEWID(), @coordRole2 UNIQUEIDENTIFIER = NEWID(), @prog2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @userInactivo UNIQUEIDENTIFIER = NEWID(), @coordRoleInactivo UNIQUEIDENTIFIER = NEWID();
    INSERT dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@user2, @tipo, 1500000001, N'COORD', N'DOS', N'QA', N'PLAN', CONCAT(N'qa.cc003g01.coord2.', @sufijo, N'@test.local'), 0, 1, N'HashBackend_CC003G01_FIXTURE'),
           (@userInactivo, @tipo, 1500000002, N'COORD', N'INACTIVO', N'QA', N'PLAN', CONCAT(N'qa.cc003g01.coordx.', @sufijo, N'@test.local'), 0, 0, N'HashBackend_CC003G01_FIXTURE');
    INSERT dbo.Coordinador (id, usuario) VALUES (@coordRole2, @user2), (@coordRoleInactivo, @userInactivo);
    INSERT dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado)
    SELECT @prog2, facultad, tipoDePrograma, N'QA CC003G01 Programa 2', @coordRole2, 1 FROM dbo.Programa WHERE id = @prog1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_programa p JOIN dbo.uv_coordinador_identidad ci ON ci.id = p.idCoordinador
        WHERE p.id = @prog2 AND ci.idUsuario = @user2)
        THROW 53205, 'TEST FAILED: fixture del segundo programa/coordinador invalido.', 1;
    SET @conteo1 = (SELECT COUNT(*) FROM dbo.PlanEstudio WHERE programa = @prog1);

    -- ===== ALTA =====
    SET @corr = NEWID();
    INSERT #r EXEC dbo.usp_registrar_o_actualizar_plan_estudio
        @idPlanEstudio = @plan1, @idPrograma = @prog1, @inp = @inp1, @idCorrelacion = @corr, @idUsuarioEjecutor = @coord1;
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'Plan de estudio',
        @mensajeUsuarioResultado = @expU OUTPUT, @mensajeTecnicoResultado = @expT OUTPUT;
    IF (SELECT COUNT(*) FROM #r) <> 1 OR NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idCorrelacion = @corr
        AND mensajeUsuarioResultado = @expU AND mensajeTecnicoResultado = CONCAT(@expT, ' Correlacion: ', @corr))
        THROW 53210, 'TEST FAILED: PLAN_PUBLIC_CREATE resultado canonico incorrecto.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.PlanEstudio WHERE id = @plan1 AND programa = @prog1 AND inp = @inp1 AND estado = 1)
       OR (SELECT COUNT(*) FROM dbo.PlanEstudio WHERE programa = @prog1) <> @conteo1 + 1
        THROW 53211, 'TEST FAILED: PLAN_PUBLIC_CREATE no persistio exactamente el plan activo.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_plan_estudio WHERE id = @plan1 AND idPrograma = @prog1 AND inp = @inp1)
        THROW 53212, 'TEST FAILED: PLAN_PUBLIC_VIEW_CONSISTENT uv_plan_estudio no refleja el alta.', 1;
    PRINT 'TEST_PASS:PLAN_PUBLIC_CREATE';
    PRINT 'TEST_PASS:PLAN_PUBLIC_VIEW_CONSISTENT';

    -- ===== IDEMPOTENCIA: mismo id + mismo programa + mismo inp =====
    SET @firmaPlanAntes = (SELECT CHECKSUM(id, programa, inp, estado) FROM dbo.PlanEstudio WHERE id = @plan1);
    TRUNCATE TABLE #r;
    SET @corr = NEWID();
    INSERT #r EXEC dbo.usp_registrar_o_actualizar_plan_estudio
        @idPlanEstudio = @plan1, @idPrograma = @prog1, @inp = @inp1, @idCorrelacion = @corr, @idUsuarioEjecutor = @coord1;
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_005', @p_param1 = 'Plan de estudio',
        @mensajeUsuarioResultado = @expU OUTPUT, @mensajeTecnicoResultado = @expT OUTPUT;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idCorrelacion = @corr
        AND mensajeUsuarioResultado = @expU AND mensajeTecnicoResultado = CONCAT(@expT, ' Correlacion: ', @corr))
        THROW 53213, 'TEST FAILED: PLAN_PUBLIC_IDEMPOTENT el reintento no devolvio exito canonico.', 1;
    IF (SELECT COUNT(*) FROM dbo.PlanEstudio WHERE programa = @prog1) <> @conteo1 + 1
       OR @firmaPlanAntes <> (SELECT CHECKSUM(id, programa, inp, estado) FROM dbo.PlanEstudio WHERE id = @plan1)
        THROW 53214, 'TEST FAILED: PLAN_PUBLIC_IDEMPOTENT el reintento modifico o duplico el plan.', 1;
    PRINT 'TEST_PASS:PLAN_PUBLIC_IDEMPOTENT';

    -- ===== ACTUALIZACION (mismo id, otro inp) =====
    TRUNCATE TABLE #r;
    SET @corr = NEWID();
    INSERT #r EXEC dbo.usp_registrar_o_actualizar_plan_estudio
        @idPlanEstudio = @plan1, @idPrograma = @prog1, @inp = @inp2, @idCorrelacion = @corr, @idUsuarioEjecutor = @coord1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idCorrelacion = @corr AND mensajeUsuarioResultado = @expU)
        THROW 53215, 'TEST FAILED: PLAN_PUBLIC_UPDATE no devolvio exito.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.PlanEstudio WHERE id = @plan1 AND programa = @prog1 AND inp = @inp2 AND estado = 1)
       OR (SELECT COUNT(*) FROM dbo.PlanEstudio WHERE programa = @prog1) <> @conteo1 + 1
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_plan_estudio WHERE id = @plan1 AND idPrograma = @prog1 AND inp = @inp2)
       OR EXISTS (SELECT 1 FROM dbo.uv_plan_estudio WHERE id = @plan1 AND inp = @inp1)
        THROW 53216, 'TEST FAILED: PLAN_PUBLIC_UPDATE no actualizo solo inp (tabla y vista).', 1;
    PRINT 'TEST_PASS:PLAN_PUBLIC_UPDATE';

    -- ===== SEGUNDO ACTOR (rol distinto/programa distinto): coordinador 2 crea y actualiza su plan =====
    TRUNCATE TABLE #r;
    SET @corr = NEWID();
    INSERT #r EXEC dbo.usp_registrar_o_actualizar_plan_estudio
        @idPlanEstudio = @planB, @idPrograma = @prog2, @inp = @inp1, @idCorrelacion = @corr, @idUsuarioEjecutor = @user2;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.PlanEstudio WHERE id = @planB AND programa = @prog2 AND inp = @inp1)
       OR (SELECT COUNT(*) FROM dbo.PlanEstudio WHERE programa = @prog1) <> @conteo1 + 1
        THROW 53217, 'TEST FAILED: PLAN_PUBLIC_TWO_ACTORS el coordinador 2 no pudo gestionar su propio programa sin afectar al 1.', 1;
    PRINT 'TEST_PASS:PLAN_PUBLIC_TWO_ACTORS';

    -- ===== RECHAZOS PREVIOS A LA TRANSACCION (INSERT ... EXEC) =====
    DECLARE @conteoGlobal INT = (SELECT COUNT(*) FROM dbo.PlanEstudio);
    DECLARE @firmaB INT = (SELECT CHECKSUM(id, programa, inp, estado) FROM dbo.PlanEstudio WHERE id = @planB);

    -- Ejecutor ausente
    TRUNCATE TABLE #r; SET @corr = NEWID();
    INSERT #r EXEC dbo.usp_registrar_o_actualizar_plan_estudio
        @idPlanEstudio = @plan1, @idPrograma = @prog1, @inp = @inp2, @idCorrelacion = @corr, @idUsuarioEjecutor = NULL;
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
        @mensajeUsuarioResultado = @expU OUTPUT, @mensajeTecnicoResultado = @expT OUTPUT;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @corr AND mensajeUsuarioResultado = @expU
        AND mensajeTecnicoResultado = CONCAT(@expT, ' Correlacion: ', @corr))
        THROW 53220, 'TEST FAILED: PLAN_PUBLIC_EXECUTOR_REQUIRED un ejecutor ausente no fue rechazado.', 1;

    -- Ejecutor sin perfil COORDINADOR (estudiante y decano), inexistente e inactivo
    DECLARE @intentos TABLE (etiqueta NVARCHAR(30), usuario UNIQUEIDENTIFIER);
    INSERT @intentos VALUES (N'ESTUDIANTE', @estudiante), (N'DECANO', @decano), (N'INEXISTENTE', NEWID()), (N'INACTIVO', @userInactivo);
    DECLARE @etiqueta NVARCHAR(30), @usuarioIntento UNIQUEIDENTIFIER;
    DECLARE intentos CURSOR LOCAL FAST_FORWARD FOR SELECT etiqueta, usuario FROM @intentos;
    OPEN intentos; FETCH NEXT FROM intentos INTO @etiqueta, @usuarioIntento;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        TRUNCATE TABLE #r; SET @corr = NEWID();
        INSERT #r EXEC dbo.usp_registrar_o_actualizar_plan_estudio
            @idPlanEstudio = @plan1, @idPrograma = @prog1, @inp = @inp2, @idCorrelacion = @corr, @idUsuarioEjecutor = @usuarioIntento;
        EXEC dbo.usp_validar_permiso_rbac_usuario_interno @idUsuario = @usuarioIntento, @codigoPerfilRequerido = 'COORDINADOR',
            @idCorrelacion = @corr, @mensajeUsuarioResultado = @expU OUTPUT, @mensajeTecnicoResultado = @expT OUTPUT, @estadoResultado = @ok OUTPUT;
        IF @ok <> 0 OR NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @corr
            AND mensajeUsuarioResultado = @expU AND mensajeTecnicoResultado = @expT)
            THROW 53221, 'TEST FAILED: PLAN_PUBLIC_RBAC un ejecutor no autorizado no fue rechazado con el resultado canonico del validador RBAC.', 1;
        FETCH NEXT FROM intentos INTO @etiqueta, @usuarioIntento;
    END
    CLOSE intentos; DEALLOCATE intentos;

    -- Coordinador de OTRO programa pretende operar sobre el programa 1 (titularidad)
    TRUNCATE TABLE #r; SET @corr = NEWID();
    INSERT #r EXEC dbo.usp_registrar_o_actualizar_plan_estudio
        @idPlanEstudio = @planRnd, @idPrograma = @prog1, @inp = @inp3, @idCorrelacion = @corr, @idUsuarioEjecutor = @user2;
    EXEC dbo.usp_validar_titularidad_jerarquica_interno @idUsuario = @user2, @idEntidadPadre = @prog1, @tipoEntidadPadre = 'PROGRAMA',
        @idCorrelacion = @corr, @mensajeUsuarioResultado = @expU OUTPUT, @mensajeTecnicoResultado = @expT OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @expU AND mensajeTecnicoResultado = @expT)
        THROW 53222, 'TEST FAILED: PLAN_PUBLIC_FOREIGN_PROGRAM_SCOPE el coordinador de otro programa no fue rechazado por titularidad.', 1;

    -- Entradas invalidas
    TRUNCATE TABLE #r; SET @corr = NEWID();
    INSERT #r EXEC dbo.usp_registrar_o_actualizar_plan_estudio
        @idPlanEstudio = @planRnd, @idPrograma = @prog1, @inp = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @coord1;
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'inp',
        @mensajeUsuarioResultado = @expU OUTPUT, @mensajeTecnicoResultado = @expT OUTPUT;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @expU)
        THROW 53223, 'TEST FAILED: PLAN_PUBLIC_INVALID_INPUT inp NULL no fue rechazado.', 1;
    TRUNCATE TABLE #r; SET @corr = NEWID();
    INSERT #r EXEC dbo.usp_registrar_o_actualizar_plan_estudio
        @idPlanEstudio = @planRnd, @idPrograma = @prog1, @inp = 0, @idCorrelacion = @corr, @idUsuarioEjecutor = @coord1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @expU)
        THROW 53224, 'TEST FAILED: PLAN_PUBLIC_INVALID_INPUT inp 0 no fue rechazado.', 1;
    TRUNCATE TABLE #r; SET @corr = NEWID();
    INSERT #r EXEC dbo.usp_registrar_o_actualizar_plan_estudio
        @idPlanEstudio = @planRnd, @idPrograma = @prog1, @inp = -5, @idCorrelacion = @corr, @idUsuarioEjecutor = @coord1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @expU)
        THROW 53225, 'TEST FAILED: PLAN_PUBLIC_INVALID_INPUT inp negativo no fue rechazado.', 1;
    TRUNCATE TABLE #r; SET @corr = NEWID();
    INSERT #r EXEC dbo.usp_registrar_o_actualizar_plan_estudio
        @idPlanEstudio = NULL, @idPrograma = @prog1, @inp = @inp4, @idCorrelacion = @corr, @idUsuarioEjecutor = @coord1;
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idPlanEstudio',
        @mensajeUsuarioResultado = @expU OUTPUT, @mensajeTecnicoResultado = @expT OUTPUT;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @expU)
        THROW 53226, 'TEST FAILED: PLAN_PUBLIC_INVALID_INPUT idPlanEstudio ausente no fue rechazado.', 1;
    TRUNCATE TABLE #r; SET @corr = NEWID();
    INSERT #r EXEC dbo.usp_registrar_o_actualizar_plan_estudio
        @idPlanEstudio = @planRnd, @idPrograma = @progRnd, @inp = @inp4, @idCorrelacion = @corr, @idUsuarioEjecutor = @coord1;
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'PROG_001',
        @mensajeUsuarioResultado = @expU OUTPUT, @mensajeTecnicoResultado = @expT OUTPUT;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @expU AND mensajeTecnicoResultado = CONCAT(@expT, ' Correlacion: ', @corr))
        THROW 53227, 'TEST FAILED: PLAN_PUBLIC_INVALID_INPUT programa inexistente no devolvio PROG_001.', 1;
    TRUNCATE TABLE #r;
    INSERT #r EXEC dbo.usp_registrar_o_actualizar_plan_estudio
        @idPlanEstudio = @planRnd, @idPrograma = @prog1, @inp = @inp4, @idCorrelacion = NULL, @idUsuarioEjecutor = @coord1;
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'CORR_001',
        @mensajeUsuarioResultado = @expU OUTPUT, @mensajeTecnicoResultado = @expT OUTPUT;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @expU)
        THROW 53228, 'TEST FAILED: PLAN_PUBLIC_INVALID_INPUT correlacion ausente no fue rechazada.', 1;
    IF @conteoGlobal <> (SELECT COUNT(*) FROM dbo.PlanEstudio)
       OR @firmaB <> (SELECT CHECKSUM(id, programa, inp, estado) FROM dbo.PlanEstudio WHERE id = @planB)
       OR NOT EXISTS (SELECT 1 FROM dbo.PlanEstudio WHERE id = @plan1 AND programa = @prog1 AND inp = @inp2)
        THROW 53229, 'TEST FAILED: PLAN_PUBLIC_REJECTIONS_PRE_TRANSACTION un rechazo modifico datos.', 1;
    PRINT 'TEST_PASS:PLAN_PUBLIC_EXECUTOR_REQUIRED';
    PRINT 'TEST_PASS:PLAN_PUBLIC_RBAC';
    PRINT 'TEST_PASS:PLAN_PUBLIC_FOREIGN_PROGRAM_SCOPE';
    PRINT 'TEST_PASS:PLAN_PUBLIC_INVALID_INPUT';

    -- ===== RECHAZOS POSTERIORES AL SAVEPOINT (ROLLBACK dentro del SP => marcadores) =====
    -- Duplicado de negocio: otro plan del mismo programa con ese inp
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_003', @p_param1 = 'plan de estudio', @p_param2 = 'inp',
        @mensajeUsuarioResultado = @expU OUTPUT, @mensajeTecnicoResultado = @expT OUTPUT;
    PRINT CONCAT('TEST_EXPECTED_USER:PLAN_PUBLIC_DUPLICATE_BUSINESS_KEY|', @expU);
    PRINT CONCAT('TEST_EXPECTED_TECH:PLAN_PUBLIC_DUPLICATE_BUSINESS_KEY|', @expT, ' Correlacion: ', @corr);
    PRINT 'TEST_RESULT_BEGIN:PLAN_PUBLIC_DUPLICATE_BUSINESS_KEY';
    EXEC dbo.usp_registrar_o_actualizar_plan_estudio
        @idPlanEstudio = @planDup, @idPrograma = @prog1, @inp = @inp2, @idCorrelacion = @corr, @idUsuarioEjecutor = @coord1;
    PRINT 'TEST_RESULT_END:PLAN_PUBLIC_DUPLICATE_BUSINESS_KEY';
    IF EXISTS (SELECT 1 FROM dbo.PlanEstudio WHERE id = @planDup) OR @conteoGlobal <> (SELECT COUNT(*) FROM dbo.PlanEstudio)
        THROW 53230, 'TEST FAILED: PLAN_PUBLIC_DUPLICATE_BUSINESS_KEY creo un plan duplicado.', 1;
    IF @@TRANCOUNT <> @tranAntes THROW 53231, 'TEST FAILED: PLAN_PUBLIC_DUPLICATE_BUSINESS_KEY altero la transaccion externa.', 1;
    PRINT 'TEST_STATE_PASS:PLAN_PUBLIC_DUPLICATE_BUSINESS_KEY';

    -- Actualizar a un inp ya usado por otro plan del mismo programa (crear primero otro plan en prog1)
    DECLARE @planOtro UNIQUEIDENTIFIER = NEWID(), @inpOtro INT = @inp2 + 7;
    CREATE TABLE #r2 (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
    INSERT #r2 EXEC dbo.usp_registrar_o_actualizar_plan_estudio
        @idPlanEstudio = @planOtro, @idPrograma = @prog1, @inp = @inpOtro, @idCorrelacion = @corr, @idUsuarioEjecutor = @coord1;
    IF NOT EXISTS (SELECT 1 FROM #r2 WHERE estadoResultado = 1) THROW 53232, 'TEST FAILED: fixture del segundo plan del programa 1.', 1;
    DROP TABLE #r2;
    SET @conteoGlobal = (SELECT COUNT(*) FROM dbo.PlanEstudio);
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_003', @p_param1 = 'plan de estudio', @p_param2 = 'inp',
        @mensajeUsuarioResultado = @expU OUTPUT, @mensajeTecnicoResultado = @expT OUTPUT;
    PRINT CONCAT('TEST_EXPECTED_USER:PLAN_PUBLIC_UPDATE_TO_TAKEN_INP|', @expU);
    PRINT CONCAT('TEST_EXPECTED_TECH:PLAN_PUBLIC_UPDATE_TO_TAKEN_INP|', @expT, ' Correlacion: ', @corr);
    PRINT 'TEST_RESULT_BEGIN:PLAN_PUBLIC_UPDATE_TO_TAKEN_INP';
    EXEC dbo.usp_registrar_o_actualizar_plan_estudio
        @idPlanEstudio = @plan1, @idPrograma = @prog1, @inp = @inpOtro, @idCorrelacion = @corr, @idUsuarioEjecutor = @coord1;
    PRINT 'TEST_RESULT_END:PLAN_PUBLIC_UPDATE_TO_TAKEN_INP';
    IF NOT EXISTS (SELECT 1 FROM dbo.PlanEstudio WHERE id = @plan1 AND inp = @inp2) OR @conteoGlobal <> (SELECT COUNT(*) FROM dbo.PlanEstudio)
        THROW 53233, 'TEST FAILED: PLAN_PUBLIC_UPDATE_TO_TAKEN_INP modifico el plan.', 1;
    PRINT 'TEST_STATE_PASS:PLAN_PUBLIC_UPDATE_TO_TAKEN_INP';

    -- Plan ajeno: el coordinador 1 usa el id del plan del programa 2 declarando SU programa (titularidad valida)
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SEC_002', @p_param1 = 'Plan de estudio',
        @mensajeUsuarioResultado = @expU OUTPUT, @mensajeTecnicoResultado = @expT OUTPUT;
    PRINT CONCAT('TEST_EXPECTED_USER:PLAN_PUBLIC_FOREIGN_PLAN|', @expU);
    PRINT CONCAT('TEST_EXPECTED_TECH:PLAN_PUBLIC_FOREIGN_PLAN|', @expT, ' Correlacion: ', @corr);
    PRINT 'TEST_RESULT_BEGIN:PLAN_PUBLIC_FOREIGN_PLAN';
    EXEC dbo.usp_registrar_o_actualizar_plan_estudio
        @idPlanEstudio = @planB, @idPrograma = @prog1, @inp = @inp5, @idCorrelacion = @corr, @idUsuarioEjecutor = @coord1;
    PRINT 'TEST_RESULT_END:PLAN_PUBLIC_FOREIGN_PLAN';
    IF @firmaB <> (SELECT CHECKSUM(id, programa, inp, estado) FROM dbo.PlanEstudio WHERE id = @planB)
       OR @conteoGlobal <> (SELECT COUNT(*) FROM dbo.PlanEstudio)
        THROW 53234, 'TEST FAILED: PLAN_PUBLIC_FOREIGN_PLAN modifico un plan de otro programa.', 1;
    PRINT 'TEST_STATE_PASS:PLAN_PUBLIC_FOREIGN_PLAN';

    -- ===== ROLLBACK con transaccion externa: fallo forzado en el INSERT (constraint temporal) =====
    EXEC ('ALTER TABLE dbo.PlanEstudio WITH NOCHECK ADD CONSTRAINT CK_qa_cc003g01_plan CHECK (inp <> 98765)');
    SET @corr = NEWID();
    DECLARE @planBoom UNIQUEIDENTIFIER = NEWID();
    PRINT CONCAT('TEST_EXPECTED_USER:PLAN_PUBLIC_ROLLBACK_SAVEPOINT|', @sys001);
    PRINT 'TEST_EXPECTED_TECH_REGEX:PLAN_PUBLIC_ROLLBACK_SAVEPOINT|(?s)^.+$';
    PRINT 'TEST_RESULT_BEGIN:PLAN_PUBLIC_ROLLBACK_SAVEPOINT';
    EXEC dbo.usp_registrar_o_actualizar_plan_estudio
        @idPlanEstudio = @planBoom, @idPrograma = @prog1, @inp = 98765, @idCorrelacion = @corr, @idUsuarioEjecutor = @coord1;
    PRINT 'TEST_RESULT_END:PLAN_PUBLIC_ROLLBACK_SAVEPOINT';
    IF @@TRANCOUNT <> @tranAntes THROW 53235, 'TEST FAILED: PLAN_PUBLIC_ROLLBACK_SAVEPOINT altero la transaccion externa.', 1;
    IF EXISTS (SELECT 1 FROM dbo.PlanEstudio WHERE id = @planBoom) OR @conteoGlobal <> (SELECT COUNT(*) FROM dbo.PlanEstudio)
        THROW 53236, 'TEST FAILED: PLAN_PUBLIC_ROLLBACK_SAVEPOINT dejo un plan parcial.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.PlanEstudio WHERE id = @plan1 AND inp = @inp2)
        THROW 53237, 'TEST FAILED: PLAN_PUBLIC_ROLLBACK_SAVEPOINT revirtio trabajo previo de la transaccion externa.', 1;
    PRINT 'TEST_STATE_PASS:PLAN_PUBLIC_ROLLBACK_SAVEPOINT';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH
ROLLBACK TRANSACTION;
DROP TABLE #r;

IF EXISTS (SELECT 1 FROM dbo.PlanEstudio WHERE id IN (@plan1, @planB, @planDup))
   OR EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_qa_cc003g01_plan')
   OR EXISTS (SELECT 1 FROM dbo.Programa WHERE nombre = N'QA CC003G01 Programa 2')
   OR EXISTS (SELECT 1 FROM dbo.Usuario WHERE numeroIdentificacion IN (1500000001, 1500000002))
    THROW 53238, 'TEST FAILED: test_usp_registrar_o_actualizar_plan_estudio dejo datos o DDL permanentes.', 1;
IF @@TRANCOUNT <> 0 THROW 53239, 'TEST FAILED: test_usp_registrar_o_actualizar_plan_estudio dejo transacciones abiertas.', 1;
GO

-- ===== SIN TRANSACCION EXTERNA: el SP es propietario de su transaccion =====
SET NOCOUNT ON;
SET XACT_ABORT OFF;

DECLARE @prog1 UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_programa ORDER BY id);
DECLARE @coord1 UNIQUEIDENTIFIER = (
    SELECT TOP 1 ci.idUsuario FROM dbo.uv_programa p JOIN dbo.uv_coordinador_identidad ci ON ci.id = p.idCoordinador
    WHERE p.id = @prog1 AND ci.estaActivoUsuario = 1);
DECLARE @planOk UNIQUEIDENTIFIER = NEWID(), @planBoom UNIQUEIDENTIFIER = NEWID();
DECLARE @inpOk INT = 20000 + ABS(CHECKSUM(NEWID()) % 5000);
DECLARE @corr UNIQUEIDENTIFIER = NEWID();
DECLARE @sys001 NVARCHAR(4000) = (SELECT contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SYS_001');
IF @@TRANCOUNT <> 0 THROW 53240, 'TEST FAILED: precondicion sin transaccion externa.', 1;
IF @prog1 IS NULL OR @coord1 IS NULL THROW 53241, 'TEST FAILED: fixtures de programa/coordinador ausentes.', 1;
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_qa_cc003g01_plan_own')
    EXEC ('ALTER TABLE dbo.PlanEstudio DROP CONSTRAINT CK_qa_cc003g01_plan_own');

BEGIN TRY
    CREATE TABLE #r (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
    INSERT #r EXEC dbo.usp_registrar_o_actualizar_plan_estudio
        @idPlanEstudio = @planOk, @idPrograma = @prog1, @inp = @inpOk, @idCorrelacion = @corr, @idUsuarioEjecutor = @coord1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) THROW 53242, 'TEST FAILED: PLAN_PUBLIC_COMMIT_OWN_TRANSACTION no devolvio exito.', 1;
    IF @@TRANCOUNT <> 0 THROW 53243, 'TEST FAILED: PLAN_PUBLIC_COMMIT_OWN_TRANSACTION dejo una transaccion abierta.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.PlanEstudio WHERE id = @planOk AND programa = @prog1 AND inp = @inpOk)
        THROW 53244, 'TEST FAILED: PLAN_PUBLIC_COMMIT_OWN_TRANSACTION no confirmo el alta.', 1;
    DROP TABLE #r;
    PRINT 'TEST_PASS:PLAN_PUBLIC_COMMIT_OWN_TRANSACTION';

    EXEC ('ALTER TABLE dbo.PlanEstudio WITH NOCHECK ADD CONSTRAINT CK_qa_cc003g01_plan_own CHECK (inp <> 98766)');
    SET @corr = NEWID();
    PRINT CONCAT('TEST_EXPECTED_USER:PLAN_PUBLIC_ROLLBACK_OWN_TRANSACTION|', @sys001);
    PRINT 'TEST_EXPECTED_TECH_REGEX:PLAN_PUBLIC_ROLLBACK_OWN_TRANSACTION|(?s)^.+$';
    PRINT 'TEST_RESULT_BEGIN:PLAN_PUBLIC_ROLLBACK_OWN_TRANSACTION';
    EXEC dbo.usp_registrar_o_actualizar_plan_estudio
        @idPlanEstudio = @planBoom, @idPrograma = @prog1, @inp = 98766, @idCorrelacion = @corr, @idUsuarioEjecutor = @coord1;
    PRINT 'TEST_RESULT_END:PLAN_PUBLIC_ROLLBACK_OWN_TRANSACTION';
    IF @@TRANCOUNT <> 0 THROW 53245, 'TEST FAILED: PLAN_PUBLIC_ROLLBACK_OWN_TRANSACTION dejo una transaccion abierta.', 1;
    IF EXISTS (SELECT 1 FROM dbo.PlanEstudio WHERE id = @planBoom)
        THROW 53246, 'TEST FAILED: PLAN_PUBLIC_ROLLBACK_OWN_TRANSACTION dejo un plan parcial.', 1;
    PRINT 'TEST_STATE_PASS:PLAN_PUBLIC_ROLLBACK_OWN_TRANSACTION';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_qa_cc003g01_plan_own')
        ALTER TABLE dbo.PlanEstudio DROP CONSTRAINT CK_qa_cc003g01_plan_own;
    DELETE FROM dbo.PlanEstudio WHERE id IN (@planOk, @planBoom);
    THROW;
END CATCH

IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_qa_cc003g01_plan_own')
    ALTER TABLE dbo.PlanEstudio DROP CONSTRAINT CK_qa_cc003g01_plan_own;
DELETE FROM dbo.PlanEstudio WHERE id IN (@planOk, @planBoom);
IF EXISTS (SELECT 1 FROM dbo.PlanEstudio WHERE id IN (@planOk, @planBoom))
    THROW 53247, 'TEST FAILED: limpieza de test_usp_registrar_o_actualizar_plan_estudio incompleta.', 1;
IF @@TRANCOUNT <> 0 THROW 53248, 'TEST FAILED: test_usp_registrar_o_actualizar_plan_estudio dejo transacciones abiertas.', 1;
PRINT 'TEST END: test_usp_registrar_o_actualizar_plan_estudio';
GO
