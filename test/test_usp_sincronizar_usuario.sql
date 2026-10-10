USE [gestionasistenciadb];
GO

-- CC-003G-01: contrato del proveedor publico dbo.usp_sincronizar_usuario.
-- Los escenarios cuya ruta ejecuta ROLLBACK dentro del SP (rechazos posteriores al savepoint y fallos
-- forzados) no pueden capturarse con INSERT ... EXEC (error 3915): se emiten entre marcadores
-- TEST_RESULT_BEGIN/END y los verifica test_summary.ps1 (mismo mecanismo que STUDENT_DUPLICATE).
SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT 'TEST START: test_usp_sincronizar_usuario';

IF OBJECT_ID('dbo.usp_sincronizar_usuario', 'P') IS NULL
    THROW 53100, 'TEST FAILED: USER_SYNC_PUBLIC_METADATA procedimiento publico ausente.', 1;

DECLARE @firmaEsperada NVARCHAR(MAX) = N'@idTipoIdIdentificacion:uniqueidentifier:0,@numeroIdentificacion:int:0,'
    + N'@primerApellido:nvarchar:0,@segundoApellido:nvarchar:0,@primerNombre:nvarchar:0,@segundoNombre:nvarchar:0,'
    + N'@correo:nvarchar:0,@password:nvarchar:0,@idCorrelacion:uniqueidentifier:0';
DECLARE @firmaReal NVARCHAR(MAX) = (
    SELECT STRING_AGG(CONCAT(p.name, ':', TYPE_NAME(p.user_type_id), ':', CONVERT(INT, p.is_output)), ',')
           WITHIN GROUP (ORDER BY p.parameter_id)
    FROM sys.parameters p WHERE p.object_id = OBJECT_ID('dbo.usp_sincronizar_usuario'));
IF @firmaReal IS NULL OR @firmaReal <> @firmaEsperada
    THROW 53101, 'TEST FAILED: USER_SYNC_PUBLIC_METADATA la firma no coincide con el contrato del backend.', 1;

IF (SELECT COUNT(*) FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID('dbo.usp_sincronizar_usuario'), NULL)
    WHERE error_number IS NULL) <> 4
   OR EXISTS (
        SELECT 1 FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID('dbo.usp_sincronizar_usuario'), NULL)
        WHERE (column_ordinal = 1 AND (name <> 'idCorrelacion' OR system_type_name <> 'uniqueidentifier'))
           OR (column_ordinal = 2 AND (name <> 'mensajeUsuarioResultado' OR system_type_name NOT LIKE 'nvarchar%'))
           OR (column_ordinal = 3 AND (name <> 'mensajeTecnicoResultado' OR system_type_name NOT LIKE 'nvarchar%'))
           OR (column_ordinal = 4 AND (name <> 'estadoResultado' OR system_type_name <> 'bit')))
    THROW 53102, 'TEST FAILED: USER_SYNC_PUBLIC_METADATA el resultset no es el canonico de 4 columnas.', 1;
PRINT 'TEST_PASS:USER_SYNC_PUBLIC_METADATA';
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

DECLARE @tipo UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
IF @tipo IS NULL THROW 53103, 'TEST FAILED: fixture CC ausente.', 1;

DECLARE @secret NVARCHAR(500) = N'HashBackend_CC003G01_SECRET_MARKER_0123456789';
DECLARE @secretReplay NVARCHAR(500) = N'HashBackend_CC003G01_SECRET_MARKER_REPLAY';
DECLARE @sufijo NVARCHAR(32) = REPLACE(CONVERT(NVARCHAR(36), NEWID()), '-', '');
DECLARE @correo NVARCHAR(100) = CONCAT(N'qa.cc003g01.', @sufijo, N'@test.local');
DECLARE @correoOtro NVARCHAR(100) = CONCAT(N'qa.cc003g01.otro.', @sufijo, N'@test.local');
DECLARE @numero INT = 1300000000 + ABS(CHECKSUM(NEWID()) % 100000000);
DECLARE @numeroOtro INT = @numero + 1;
DECLARE @corr UNIQUEIDENTIFIER, @expU NVARCHAR(4000), @expT NVARCHAR(4000), @userId UNIQUEIDENTIFIER;
DECLARE @conteoAntes INT, @firmaAntes INT, @tranAntes INT;
DECLARE @correoSucio NVARCHAR(100) = CONCAT(N'  ', UPPER(@correo), N' ');
DECLARE @nombreLargo NVARCHAR(255) = REPLICATE(N'A', 51);
DECLARE @correoLargo NVARCHAR(255) = CONCAT(REPLICATE(N'x', 96), N'@a.co');
DECLARE @sys001 NVARCHAR(4000) = (SELECT contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SYS_001');

IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE numeroIdentificacion IN (@numero, @numeroOtro) OR correo IN (@correo, @correoOtro))
    THROW 53104, 'TEST FAILED: fixture de identificacion no es unico.', 1;

CREATE TABLE #r (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);

BEGIN TRANSACTION;
BEGIN TRY
    SET @tranAntes = @@TRANCOUNT;

    -- ===== ALTA VALIDA (con normalizacion) =====
    SET @corr = NEWID();
    INSERT #r EXEC dbo.usp_sincronizar_usuario
        @idTipoIdIdentificacion = @tipo, @numeroIdentificacion = @numero,
        @primerApellido = N'  Perez ', @segundoApellido = N'Gomez', @primerNombre = N' Ana', @segundoNombre = N'Maria ',
        @correo = @correoSucio, @password = @secret, @idCorrelacion = @corr;
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'Usuario',
        @mensajeUsuarioResultado = @expU OUTPUT, @mensajeTecnicoResultado = @expT OUTPUT;
    IF (SELECT COUNT(*) FROM #r) <> 1
        THROW 53110, 'TEST FAILED: USER_SYNC_PUBLIC_SUCCESS no devolvio exactamente una fila.', 1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idCorrelacion = @corr
        AND mensajeUsuarioResultado = @expU AND mensajeTecnicoResultado = CONCAT(@expT, ' Correlacion: ', @corr))
        THROW 53111, 'TEST FAILED: USER_SYNC_PUBLIC_SUCCESS resultado canonico incorrecto.', 1;
    IF EXISTS (SELECT 1 FROM #r WHERE mensajeUsuarioResultado LIKE '%SECRET_MARKER%' OR mensajeTecnicoResultado LIKE '%SECRET_MARKER%')
        THROW 53112, 'TEST FAILED: USER_SYNC_PUBLIC_NO_SECRET_LEAK el exito expone el password.', 1;
    SELECT @userId = id FROM dbo.uv_usuario WHERE idTipoIdentificacion = @tipo AND numeroIdentificacion = @numero;
    IF @userId IS NULL OR (SELECT COUNT(*) FROM dbo.Usuario WHERE numeroIdentificacion = @numero) <> 1
        THROW 53113, 'TEST FAILED: USER_SYNC_PUBLIC_SUCCESS no persistio exactamente un usuario consultable por identificacion.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @userId AND correo = @correo AND primerNombre = N'ANA'
        AND segundoNombre = N'MARIA' AND primerApellido = N'PEREZ' AND segundoApellido = N'GOMEZ'
        AND estado = 1 AND correoConfirmado = 0 AND password = @secret)
        THROW 53114, 'TEST FAILED: USER_SYNC_PUBLIC_SUCCESS fila no normalizada o password no persistido.', 1;
    IF EXISTS (SELECT 1 FROM dbo.uv_usuario WHERE id = @userId AND password <> '*****')
        THROW 53115, 'TEST FAILED: USER_SYNC_PUBLIC_NO_SECRET_LEAK la vista publica expone el password.', 1;
    PRINT 'TEST_PASS:USER_SYNC_PUBLIC_SUCCESS';
    PRINT 'TEST_PASS:USER_SYNC_PUBLIC_NO_SECRET_LEAK';

    -- ===== IDEMPOTENCIA: reintento exacto no escribe y no toca el password =====
    SELECT @firmaAntes = CHECKSUM(id, correo, primerNombre, segundoNombre, primerApellido, segundoApellido, estado, password)
    FROM dbo.Usuario WHERE id = @userId;
    TRUNCATE TABLE #r;
    SET @corr = NEWID();
    INSERT #r EXEC dbo.usp_sincronizar_usuario
        @idTipoIdIdentificacion = @tipo, @numeroIdentificacion = @numero,
        @primerApellido = N'Perez', @segundoApellido = N'Gomez', @primerNombre = N'Ana', @segundoNombre = N'Maria',
        @correo = @correo, @password = @secretReplay, @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idCorrelacion = @corr
        AND mensajeUsuarioResultado = @expU AND mensajeTecnicoResultado = CONCAT(@expT, ' Correlacion: ', @corr))
        THROW 53116, 'TEST FAILED: USER_SYNC_PUBLIC_IDEMPOTENT el reintento exacto no devolvio exito canonico.', 1;
    IF (SELECT COUNT(*) FROM dbo.Usuario WHERE numeroIdentificacion = @numero OR correo = @correo) <> 1
        THROW 53117, 'TEST FAILED: USER_SYNC_PUBLIC_IDEMPOTENT el reintento creo un duplicado.', 1;
    IF @firmaAntes <> (SELECT CHECKSUM(id, correo, primerNombre, segundoNombre, primerApellido, segundoApellido, estado, password)
        FROM dbo.Usuario WHERE id = @userId)
        THROW 53118, 'TEST FAILED: USER_SYNC_PUBLIC_IDEMPOTENT el reintento modifico el usuario (password incluido).', 1;
    PRINT 'TEST_PASS:USER_SYNC_PUBLIC_IDEMPOTENT';

    -- ===== RECHAZOS PREVIOS A LA TRANSACCION (capturables con INSERT ... EXEC) =====
    TRUNCATE TABLE #r;
    INSERT #r EXEC dbo.usp_sincronizar_usuario
        @idTipoIdIdentificacion = @tipo, @numeroIdentificacion = @numeroOtro,
        @primerApellido = N'Perez', @segundoApellido = N'Gomez', @primerNombre = N'Ana', @segundoNombre = N'Maria',
        @correo = @correoOtro, @password = @secret, @idCorrelacion = NULL;
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'CORR_001',
        @mensajeUsuarioResultado = @expU OUTPUT, @mensajeTecnicoResultado = @expT OUTPUT;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @expU)
       OR EXISTS (SELECT 1 FROM dbo.Usuario WHERE numeroIdentificacion = @numeroOtro OR correo = @correoOtro)
        THROW 53120, 'TEST FAILED: USER_SYNC_PUBLIC_REJECTIONS correlacion ausente no fue rechazada sin escribir.', 1;

    TRUNCATE TABLE #r;
    SET @corr = NEWID();
    INSERT #r EXEC dbo.usp_sincronizar_usuario
        @idTipoIdIdentificacion = @tipo, @numeroIdentificacion = @numeroOtro,
        @primerApellido = N'Perez', @segundoApellido = N'Gomez', @primerNombre = @nombreLargo, @segundoNombre = N'Maria',
        @correo = @correoOtro, @password = @secret, @idCorrelacion = @corr;
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'VAL_004', @p_param1 = 'primer nombre',
        @mensajeUsuarioResultado = @expU OUTPUT, @mensajeTecnicoResultado = @expT OUTPUT;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @corr AND mensajeUsuarioResultado = @expU
        AND mensajeTecnicoResultado = CONCAT(@expT, ' Correlacion: ', @corr))
       OR EXISTS (SELECT 1 FROM dbo.Usuario WHERE numeroIdentificacion = @numeroOtro)
        THROW 53121, 'TEST FAILED: USER_SYNC_PUBLIC_REJECTIONS nombre excedido no fue rechazado sin escribir.', 1;

    TRUNCATE TABLE #r;
    SET @corr = NEWID();
    INSERT #r EXEC dbo.usp_sincronizar_usuario
        @idTipoIdIdentificacion = @tipo, @numeroIdentificacion = @numeroOtro,
        @primerApellido = N'Perez', @segundoApellido = N'Gomez', @primerNombre = N'Ana', @segundoNombre = N'Maria',
        @correo = @correoLargo, @password = @secret, @idCorrelacion = @corr;
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'VAL_005',
        @mensajeUsuarioResultado = @expU OUTPUT, @mensajeTecnicoResultado = @expT OUTPUT;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @expU)
       OR EXISTS (SELECT 1 FROM dbo.Usuario WHERE numeroIdentificacion = @numeroOtro)
        THROW 53122, 'TEST FAILED: USER_SYNC_PUBLIC_REJECTIONS correo excedido no fue rechazado sin escribir.', 1;
    PRINT 'TEST_PASS:USER_SYNC_PUBLIC_REJECTIONS_PRE_TRANSACTION';

    -- ===== RECHAZOS POSTERIORES AL SAVEPOINT (ROLLBACK dentro del SP => marcadores) =====
    -- Duplicado por documento (otro correo): el existente no cambia.
    SET @conteoAntes = (SELECT COUNT(*) FROM dbo.Usuario);
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'ERR_UNICIDAD_DOCUMENTO', @p_param1 = @numero,
        @mensajeUsuarioResultado = @expU OUTPUT, @mensajeTecnicoResultado = @expT OUTPUT;
    PRINT CONCAT('TEST_EXPECTED_USER:USER_SYNC_PUBLIC_DUPLICATE_DOCUMENT|', @expU);
    PRINT CONCAT('TEST_EXPECTED_TECH:USER_SYNC_PUBLIC_DUPLICATE_DOCUMENT|', @expT, ' Correlacion: ', @corr);
    PRINT 'TEST_RESULT_BEGIN:USER_SYNC_PUBLIC_DUPLICATE_DOCUMENT';
    EXEC dbo.usp_sincronizar_usuario
        @idTipoIdIdentificacion = @tipo, @numeroIdentificacion = @numero,
        @primerApellido = N'Perez', @segundoApellido = N'Gomez', @primerNombre = N'Ana', @segundoNombre = N'Maria',
        @correo = @correoOtro, @password = @secretReplay, @idCorrelacion = @corr;
    PRINT 'TEST_RESULT_END:USER_SYNC_PUBLIC_DUPLICATE_DOCUMENT';
    IF @conteoAntes <> (SELECT COUNT(*) FROM dbo.Usuario) OR EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo = @correoOtro)
        THROW 53130, 'TEST FAILED: USER_SYNC_PUBLIC_DUPLICATE_DOCUMENT escribio un usuario.', 1;
    IF @firmaAntes <> (SELECT CHECKSUM(id, correo, primerNombre, segundoNombre, primerApellido, segundoApellido, estado, password)
        FROM dbo.Usuario WHERE id = @userId)
        THROW 53131, 'TEST FAILED: USER_SYNC_PUBLIC_DUPLICATE_DOCUMENT modifico el usuario existente.', 1;
    IF @@TRANCOUNT <> @tranAntes THROW 53132, 'TEST FAILED: USER_SYNC_PUBLIC_DUPLICATE_DOCUMENT altero la transaccion externa.', 1;
    PRINT 'TEST_STATE_PASS:USER_SYNC_PUBLIC_DUPLICATE_DOCUMENT';

    -- Duplicado por correo (otro documento): el existente no cambia.
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'VAL_006', @p_param1 = @correo,
        @mensajeUsuarioResultado = @expU OUTPUT, @mensajeTecnicoResultado = @expT OUTPUT;
    PRINT CONCAT('TEST_EXPECTED_USER:USER_SYNC_PUBLIC_DUPLICATE_EMAIL|', @expU);
    PRINT CONCAT('TEST_EXPECTED_TECH:USER_SYNC_PUBLIC_DUPLICATE_EMAIL|', @expT, ' Correlacion: ', @corr);
    PRINT 'TEST_RESULT_BEGIN:USER_SYNC_PUBLIC_DUPLICATE_EMAIL';
    EXEC dbo.usp_sincronizar_usuario
        @idTipoIdIdentificacion = @tipo, @numeroIdentificacion = @numeroOtro,
        @primerApellido = N'Perez', @segundoApellido = N'Gomez', @primerNombre = N'Ana', @segundoNombre = N'Maria',
        @correo = @correo, @password = @secretReplay, @idCorrelacion = @corr;
    PRINT 'TEST_RESULT_END:USER_SYNC_PUBLIC_DUPLICATE_EMAIL';
    IF @conteoAntes <> (SELECT COUNT(*) FROM dbo.Usuario) OR EXISTS (SELECT 1 FROM dbo.Usuario WHERE numeroIdentificacion = @numeroOtro)
        THROW 53133, 'TEST FAILED: USER_SYNC_PUBLIC_DUPLICATE_EMAIL escribio un usuario.', 1;
    IF @@TRANCOUNT <> @tranAntes THROW 53134, 'TEST FAILED: USER_SYNC_PUBLIC_DUPLICATE_EMAIL altero la transaccion externa.', 1;
    PRINT 'TEST_STATE_PASS:USER_SYNC_PUBLIC_DUPLICATE_EMAIL';

    -- Mismo documento y correo pero nombres distintos NO es un reintento: se rechaza sin modificar.
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'ERR_UNICIDAD_DOCUMENTO', @p_param1 = @numero,
        @mensajeUsuarioResultado = @expU OUTPUT, @mensajeTecnicoResultado = @expT OUTPUT;
    PRINT CONCAT('TEST_EXPECTED_USER:USER_SYNC_PUBLIC_CONFLICTING_PROFILE|', @expU);
    PRINT CONCAT('TEST_EXPECTED_TECH:USER_SYNC_PUBLIC_CONFLICTING_PROFILE|', @expT, ' Correlacion: ', @corr);
    PRINT 'TEST_RESULT_BEGIN:USER_SYNC_PUBLIC_CONFLICTING_PROFILE';
    EXEC dbo.usp_sincronizar_usuario
        @idTipoIdIdentificacion = @tipo, @numeroIdentificacion = @numero,
        @primerApellido = N'Perez', @segundoApellido = N'Gomez', @primerNombre = N'Otro', @segundoNombre = N'Maria',
        @correo = @correo, @password = @secretReplay, @idCorrelacion = @corr;
    PRINT 'TEST_RESULT_END:USER_SYNC_PUBLIC_CONFLICTING_PROFILE';
    IF @firmaAntes <> (SELECT CHECKSUM(id, correo, primerNombre, segundoNombre, primerApellido, segundoApellido, estado, password)
        FROM dbo.Usuario WHERE id = @userId)
        THROW 53135, 'TEST FAILED: USER_SYNC_PUBLIC_CONFLICTING_PROFILE modifico el usuario existente.', 1;
    PRINT 'TEST_STATE_PASS:USER_SYNC_PUBLIC_CONFLICTING_PROFILE';

    -- Correo invalido
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'VAL_005',
        @mensajeUsuarioResultado = @expU OUTPUT, @mensajeTecnicoResultado = @expT OUTPUT;
    PRINT CONCAT('TEST_EXPECTED_USER:USER_SYNC_PUBLIC_INVALID_EMAIL|', @expU);
    PRINT CONCAT('TEST_EXPECTED_TECH:USER_SYNC_PUBLIC_INVALID_EMAIL|', @expT, ' Correlacion: ', @corr);
    PRINT 'TEST_RESULT_BEGIN:USER_SYNC_PUBLIC_INVALID_EMAIL';
    EXEC dbo.usp_sincronizar_usuario
        @idTipoIdIdentificacion = @tipo, @numeroIdentificacion = @numeroOtro,
        @primerApellido = N'Perez', @segundoApellido = N'Gomez', @primerNombre = N'Ana', @segundoNombre = N'Maria',
        @correo = N'no-es-un-correo', @password = @secret, @idCorrelacion = @corr;
    PRINT 'TEST_RESULT_END:USER_SYNC_PUBLIC_INVALID_EMAIL';
    IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE numeroIdentificacion = @numeroOtro)
        THROW 53136, 'TEST FAILED: USER_SYNC_PUBLIC_INVALID_EMAIL escribio un usuario.', 1;
    PRINT 'TEST_STATE_PASS:USER_SYNC_PUBLIC_INVALID_EMAIL';

    -- Password vacio
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'VAL_007',
        @mensajeUsuarioResultado = @expU OUTPUT, @mensajeTecnicoResultado = @expT OUTPUT;
    PRINT CONCAT('TEST_EXPECTED_USER:USER_SYNC_PUBLIC_EMPTY_PASSWORD|', @expU);
    PRINT CONCAT('TEST_EXPECTED_TECH:USER_SYNC_PUBLIC_EMPTY_PASSWORD|', @expT, ' Correlacion: ', @corr);
    PRINT 'TEST_RESULT_BEGIN:USER_SYNC_PUBLIC_EMPTY_PASSWORD';
    EXEC dbo.usp_sincronizar_usuario
        @idTipoIdIdentificacion = @tipo, @numeroIdentificacion = @numeroOtro,
        @primerApellido = N'Perez', @segundoApellido = N'Gomez', @primerNombre = N'Ana', @segundoNombre = N'Maria',
        @correo = @correoOtro, @password = N'   ', @idCorrelacion = @corr;
    PRINT 'TEST_RESULT_END:USER_SYNC_PUBLIC_EMPTY_PASSWORD';
    IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE numeroIdentificacion = @numeroOtro OR correo = @correoOtro)
        THROW 53137, 'TEST FAILED: USER_SYNC_PUBLIC_EMPTY_PASSWORD escribio un usuario.', 1;
    PRINT 'TEST_STATE_PASS:USER_SYNC_PUBLIC_EMPTY_PASSWORD';

    -- Tipo de identificacion inexistente: el mensaje esperado lo produce el propio validador interno
    SET @corr = NEWID();
    DECLARE @tipoInexistente UNIQUEIDENTIFIER = NEWID(), @okValidador BIT;
    EXEC dbo.usp_validar_tipo_identificacion_exista_por_id_interno
        @idTipoId = @tipoInexistente, @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @expU OUTPUT, @mensajeTecnicoResultado = @expT OUTPUT, @estadoResultado = @okValidador OUTPUT;
    IF @okValidador <> 0 THROW 53138, 'TEST FAILED: fixture de tipo inexistente invalido.', 1;
    PRINT CONCAT('TEST_EXPECTED_USER:USER_SYNC_PUBLIC_UNKNOWN_ID_TYPE|', @expU);
    PRINT CONCAT('TEST_EXPECTED_TECH:USER_SYNC_PUBLIC_UNKNOWN_ID_TYPE|', @expT);
    PRINT 'TEST_RESULT_BEGIN:USER_SYNC_PUBLIC_UNKNOWN_ID_TYPE';
    EXEC dbo.usp_sincronizar_usuario
        @idTipoIdIdentificacion = @tipoInexistente, @numeroIdentificacion = @numeroOtro,
        @primerApellido = N'Perez', @segundoApellido = N'Gomez', @primerNombre = N'Ana', @segundoNombre = N'Maria',
        @correo = @correoOtro, @password = @secret, @idCorrelacion = @corr;
    PRINT 'TEST_RESULT_END:USER_SYNC_PUBLIC_UNKNOWN_ID_TYPE';
    IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE numeroIdentificacion = @numeroOtro)
        THROW 53139, 'TEST FAILED: USER_SYNC_PUBLIC_UNKNOWN_ID_TYPE escribio un usuario.', 1;
    PRINT 'TEST_STATE_PASS:USER_SYNC_PUBLIC_UNKNOWN_ID_TYPE';

    -- ===== ROLLBACK DE LA OPERACION CON TRANSACCION EXTERNA (savepoint): fallo forzado en el INSERT =====
    EXEC ('ALTER TABLE dbo.Usuario WITH NOCHECK ADD CONSTRAINT CK_qa_cc003g01_usuario CHECK (correo <> N''qa.cc003g01.boom@test.local'')');
    SET @corr = NEWID();
    PRINT CONCAT('TEST_EXPECTED_USER:USER_SYNC_PUBLIC_ROLLBACK_SAVEPOINT|', @sys001);
    PRINT 'TEST_EXPECTED_TECH_REGEX:USER_SYNC_PUBLIC_ROLLBACK_SAVEPOINT|(?s)^(?!.*SECRET_MARKER).+$';
    PRINT 'TEST_RESULT_BEGIN:USER_SYNC_PUBLIC_ROLLBACK_SAVEPOINT';
    EXEC dbo.usp_sincronizar_usuario
        @idTipoIdIdentificacion = @tipo, @numeroIdentificacion = @numeroOtro,
        @primerApellido = N'Perez', @segundoApellido = N'Gomez', @primerNombre = N'Ana', @segundoNombre = N'Maria',
        @correo = N'qa.cc003g01.boom@test.local', @password = @secret, @idCorrelacion = @corr;
    PRINT 'TEST_RESULT_END:USER_SYNC_PUBLIC_ROLLBACK_SAVEPOINT';
    IF @@TRANCOUNT <> @tranAntes THROW 53140, 'TEST FAILED: USER_SYNC_PUBLIC_ROLLBACK_SAVEPOINT altero la transaccion externa.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE numeroIdentificacion = @numeroOtro OR correo = N'qa.cc003g01.boom@test.local')
        THROW 53141, 'TEST FAILED: USER_SYNC_PUBLIC_ROLLBACK_SAVEPOINT dejo un usuario parcial.', 1;
    IF @firmaAntes <> (SELECT CHECKSUM(id, correo, primerNombre, segundoNombre, primerApellido, segundoApellido, estado, password)
        FROM dbo.Usuario WHERE id = @userId)
        THROW 53142, 'TEST FAILED: USER_SYNC_PUBLIC_ROLLBACK_SAVEPOINT revirtio trabajo previo de la transaccion externa.', 1;
    PRINT 'TEST_STATE_PASS:USER_SYNC_PUBLIC_ROLLBACK_SAVEPOINT';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH
ROLLBACK TRANSACTION;
DROP TABLE #r;

IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE numeroIdentificacion IN (@numero, @numeroOtro) OR correo IN (@correo, @correoOtro))
   OR EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_qa_cc003g01_usuario')
    THROW 53143, 'TEST FAILED: test_usp_sincronizar_usuario dejo datos o DDL permanentes.', 1;
IF @@TRANCOUNT <> 0 THROW 53144, 'TEST FAILED: test_usp_sincronizar_usuario dejo transacciones abiertas.', 1;
GO

-- ===== SIN TRANSACCION EXTERNA: el SP es propietario de su transaccion =====
SET NOCOUNT ON;
SET XACT_ABORT OFF;

DECLARE @tipo UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @secret NVARCHAR(500) = N'HashBackend_CC003G01_SECRET_MARKER_OWNTX';
DECLARE @sufijo NVARCHAR(32) = REPLACE(CONVERT(NVARCHAR(36), NEWID()), '-', '');
DECLARE @correo NVARCHAR(100) = CONCAT(N'qa.cc003g01.own.', @sufijo, N'@test.local');
DECLARE @numero INT = 1400000000 + ABS(CHECKSUM(NEWID()) % 100000000);
DECLARE @numeroBoom INT = @numero + 1;
DECLARE @corr UNIQUEIDENTIFIER = NEWID();
DECLARE @sys001 NVARCHAR(4000) = (SELECT contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SYS_001');

IF @@TRANCOUNT <> 0 THROW 53150, 'TEST FAILED: precondicion sin transaccion externa.', 1;
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_qa_cc003g01_usuario_own')
    EXEC ('ALTER TABLE dbo.Usuario DROP CONSTRAINT CK_qa_cc003g01_usuario_own');

BEGIN TRY
    -- COMMIT propio
    CREATE TABLE #r (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
    INSERT #r EXEC dbo.usp_sincronizar_usuario
        @idTipoIdIdentificacion = @tipo, @numeroIdentificacion = @numero,
        @primerApellido = N'Perez', @segundoApellido = N'Gomez', @primerNombre = N'Ana', @segundoNombre = N'Maria',
        @correo = @correo, @password = @secret, @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) THROW 53151, 'TEST FAILED: USER_SYNC_PUBLIC_COMMIT_OWN_TRANSACTION no devolvio exito.', 1;
    IF @@TRANCOUNT <> 0 THROW 53152, 'TEST FAILED: USER_SYNC_PUBLIC_COMMIT_OWN_TRANSACTION dejo una transaccion abierta.', 1;
    IF (SELECT COUNT(*) FROM dbo.Usuario WHERE numeroIdentificacion = @numero AND correo = @correo) <> 1
        THROW 53153, 'TEST FAILED: USER_SYNC_PUBLIC_COMMIT_OWN_TRANSACTION no confirmo el alta.', 1;
    DROP TABLE #r;
    PRINT 'TEST_PASS:USER_SYNC_PUBLIC_COMMIT_OWN_TRANSACTION';

    -- ROLLBACK propio ante fallo forzado en el INSERT
    EXEC ('ALTER TABLE dbo.Usuario WITH NOCHECK ADD CONSTRAINT CK_qa_cc003g01_usuario_own CHECK (correo <> N''qa.cc003g01.own.boom@test.local'')');
    SET @corr = NEWID();
    PRINT CONCAT('TEST_EXPECTED_USER:USER_SYNC_PUBLIC_ROLLBACK_OWN_TRANSACTION|', @sys001);
    PRINT 'TEST_EXPECTED_TECH_REGEX:USER_SYNC_PUBLIC_ROLLBACK_OWN_TRANSACTION|(?s)^(?!.*SECRET_MARKER).+$';
    PRINT 'TEST_RESULT_BEGIN:USER_SYNC_PUBLIC_ROLLBACK_OWN_TRANSACTION';
    EXEC dbo.usp_sincronizar_usuario
        @idTipoIdIdentificacion = @tipo, @numeroIdentificacion = @numeroBoom,
        @primerApellido = N'Perez', @segundoApellido = N'Gomez', @primerNombre = N'Ana', @segundoNombre = N'Maria',
        @correo = N'qa.cc003g01.own.boom@test.local', @password = @secret, @idCorrelacion = @corr;
    PRINT 'TEST_RESULT_END:USER_SYNC_PUBLIC_ROLLBACK_OWN_TRANSACTION';
    IF @@TRANCOUNT <> 0 THROW 53154, 'TEST FAILED: USER_SYNC_PUBLIC_ROLLBACK_OWN_TRANSACTION dejo una transaccion abierta.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE numeroIdentificacion = @numeroBoom OR correo = N'qa.cc003g01.own.boom@test.local')
        THROW 53155, 'TEST FAILED: USER_SYNC_PUBLIC_ROLLBACK_OWN_TRANSACTION dejo un usuario parcial.', 1;
    PRINT 'TEST_STATE_PASS:USER_SYNC_PUBLIC_ROLLBACK_OWN_TRANSACTION';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_qa_cc003g01_usuario_own')
        ALTER TABLE dbo.Usuario DROP CONSTRAINT CK_qa_cc003g01_usuario_own;
    DELETE FROM dbo.Usuario WHERE correo IN (@correo, N'qa.cc003g01.own.boom@test.local');
    THROW;
END CATCH

IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_qa_cc003g01_usuario_own')
    ALTER TABLE dbo.Usuario DROP CONSTRAINT CK_qa_cc003g01_usuario_own;
DELETE FROM dbo.Usuario WHERE correo = @correo;
IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo IN (@correo, N'qa.cc003g01.own.boom@test.local'))
    THROW 53156, 'TEST FAILED: limpieza de test_usp_sincronizar_usuario incompleta.', 1;
IF @@TRANCOUNT <> 0 THROW 53157, 'TEST FAILED: test_usp_sincronizar_usuario dejo transacciones abiertas.', 1;
PRINT 'TEST END: test_usp_sincronizar_usuario';
GO
