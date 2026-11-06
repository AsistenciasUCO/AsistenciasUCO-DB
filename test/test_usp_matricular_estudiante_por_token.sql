USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_usp_matricular_estudiante_por_token (HU176B)';
PRINT 'Contrato: CONTRACT.md §2.5 (modo publico y autenticado, atomico)';
PRINT '==================================================';

BEGIN TRANSACTION;
BEGIN TRY
    -- =========================================================================
    -- 0. Existencia de los objetos del contrato
    -- =========================================================================
    IF OBJECT_ID(N'dbo.TokenMatriculaGrupo', N'U') IS NULL
        THROW 56400, 'TEST FAILED HU176B-M00: tabla dbo.TokenMatriculaGrupo no existe.', 1;
    IF OBJECT_ID(N'dbo.usp_abrir_ventana_matricula_grupo', N'P') IS NULL
        THROW 56401, 'TEST FAILED HU176B-M00: SP usp_abrir_ventana_matricula_grupo no existe.', 1;
    IF OBJECT_ID(N'dbo.usp_matricular_estudiante_por_token', N'P') IS NULL
        THROW 56402, 'TEST FAILED HU176B-M00: SP usp_matricular_estudiante_por_token no existe.', 1;
    IF OBJECT_ID(N'dbo.usp_registrar_estudiante_por_token_publico', N'P') IS NULL
        THROW 56405, 'TEST FAILED HU176B-M00: SP usp_registrar_estudiante_por_token_publico no existe (CONTRACT A2).', 1;
    IF OBJECT_ID(N'dbo.usp_internal_resolver_token_matricula', N'P') IS NULL
        THROW 56403, 'TEST FAILED HU176B-M00: SP usp_internal_resolver_token_matricula no existe.', 1;
    IF dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_MATRICULA') = N''
        THROW 56404, 'TEST FAILED HU176B-M01: parametro MATRICULA_QR/ESTADO_MATRICULA ausente.', 1;

    -- =========================================================================
    -- Fixtures
    -- =========================================================================
    CREATE TABLE #r (
        idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(MAX) NULL,
        mensajeTecnicoResultado NVARCHAR(MAX) NULL, estadoResultado BIT NOT NULL,
        idVentana UNIQUEIDENTIFIER NULL, fechaExpiracionUtc DATETIME2(0) NULL
    );
    CREATE TABLE #m (
        idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(MAX) NULL,
        mensajeTecnicoResultado NVARCHAR(MAX) NULL, estadoResultado BIT NOT NULL,
        idEstudiante UNIQUEIDENTIFIER NULL, idUsuario UNIQUEIDENTIFIER NULL, idGrupo UNIQUEIDENTIFIER NULL
    );

    DECLARE @estadoActiva  NVARCHAR(10) = dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_ACTIVA');
    DECLARE @estadoCerrada NVARCHAR(10) = dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_CERRADA');
    DECLARE @codigoMatricula NVARCHAR(10) = dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_MATRICULA');
    DECLARE @dominio NVARCHAR(255) = dbo.ufn_obtener_parametro('REGISTRO', 'DOMINIO_CORREO_ESTUDIANTE');
    DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = 'CC');

    DECLARE @grupo UNIQUEIDENTIFIER, @docenteTitular UNIQUEIDENTIFIER, @userTitular UNIQUEIDENTIFIER;
    SELECT TOP 1 @grupo = g.id, @docenteTitular = g.docente
    FROM dbo.Grupo g INNER JOIN dbo.uv_grupo vg ON vg.id = g.id
    WHERE vg.grupoEstaHablitado = 1 AND vg.cuposDisponibles > 5
    ORDER BY vg.cuposDisponibles DESC;
    SELECT @userTitular = usuario FROM dbo.Docente WHERE id = @docenteTitular;
    IF @grupo IS NULL OR @userTitular IS NULL OR @tipoCC IS NULL OR @dominio IS NULL OR @dominio = N''
        THROW 56410, 'TEST FAILED HU176B: fixture de grupo/docente/tipo de documento/dominio faltante (semilla).', 1;

    UPDATE dbo.TokenMatriculaGrupo SET estado = @estadoCerrada WHERE grupo = @grupo AND estado = @estadoActiva;

    DECLARE @corr UNIQUEIDENTIFIER = NEWID();
    DECLARE @tok NVARCHAR(100) = CONCAT(N'tok-', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''));
    DECLARE @hash VARBINARY(32) = HASHBYTES('SHA2_256', @tok);
    DECLARE @pin NCHAR(6) = RIGHT(CONCAT('000000', CAST(ABS(CHECKSUM(NEWID())) % 1000000 AS VARCHAR(6))), 6);
    DECLARE @idV UNIQUEIDENTIFIER, @msgU NVARCHAR(4000), @msgT NVARCHAR(4000);

    INSERT INTO #r
    EXEC dbo.usp_abrir_ventana_matricula_grupo @idGrupo = @grupo, @tokenHash = @hash, @pin = @pin,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @userTitular;
    SELECT @idV = idVentana FROM #r WHERE estadoResultado = 1;
    IF @idV IS NULL
        THROW 56411, 'TEST FAILED HU176B: no se pudo abrir la ventana de prueba (depende de usp_abrir_ventana_matricula_grupo).', 1;

    DECLARE @numero INT = 1100000000 + ABS(CHECKSUM(NEWID()) % 400000000);
    DECLARE @sufijo NVARCHAR(40) = REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', '');
    DECLARE @correo NVARCHAR(255) = CONCAT(N'hu176b.', @sufijo, @dominio);
    DECLARE @pass NVARCHAR(500) = N'HashBackend_Hu176b_1234567890';
    DECLARE @correoOtro NVARCHAR(255) = CONCAT(N'hu176b.otro.', @sufijo, @dominio);
    DECLARE @correoTol  NVARCHAR(255) = CONCAT(N'hu176b.tol.', @sufijo, @dominio);
    DECLARE @correoFuera NVARCHAR(255) = CONCAT(N'hu176b.fuera.', @sufijo, @dominio);
    DECLARE @correoAtom NVARCHAR(255) = CONCAT(N'hu176b.atom.', @sufijo, @dominio);
    DECLARE @correoCupo NVARCHAR(255) = CONCAT(N'hu176b.cupo.', @sufijo, @dominio);
    DECLARE @num50 INT = @numero + 50, @num60 INT = @numero + 60, @num70 INT = @numero + 70;

    -- =========================================================================
    -- T-10: registro publico (cuenta nueva) con token vigente
    -- =========================================================================
    PRINT '-> T-10: registro publico crea usuario, estudiante y matricula';
    DECLARE @usrAntes INT = (SELECT COUNT(*) FROM dbo.Usuario);
    DECLARE @egAntes INT = (SELECT COUNT(*) FROM dbo.EstudianteGrupo WHERE grupo = @grupo);

    DELETE FROM #m;
    INSERT INTO #m
    EXEC dbo.usp_registrar_estudiante_por_token_publico
        @tokenHash = @hash, @pin = NULL,
        @idTipoIdentificacion = @tipoCC, @numeroIdentificacion = @numero,
        @primerNombre = N'Hu', @segundoNombre = N'Ciento', @primerApellido = N'Setenta', @segundoApellido = N'Seis',
        @correo = @correo, @password = @pass, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #m WHERE estadoResultado = 1 AND idCorrelacion = @corr
                                  AND idEstudiante IS NOT NULL AND idUsuario IS NOT NULL AND idGrupo = @grupo) <> 1
        THROW 56420, 'TEST FAILED T-10: debio matricular con estadoResultado = 1 y devolver idEstudiante, idUsuario e idGrupo.', 1;

    DECLARE @idUsuarioNuevo UNIQUEIDENTIFIER = (SELECT idUsuario FROM #m);
    DECLARE @idEstudianteNuevo UNIQUEIDENTIFIER = (SELECT idEstudiante FROM #m);
    IF (SELECT COUNT(*) FROM dbo.Usuario WHERE id = @idUsuarioNuevo AND correo = LOWER(@correo) AND estado = 1 AND correoConfirmado = 0
                                           AND numeroIdentificacion = @numero) <> 1
        THROW 56421, 'TEST FAILED T-10: el usuario debe quedar ACTIVO con correoConfirmado = 0.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Estudiante WHERE id = @idEstudianteNuevo AND usuario = @idUsuarioNuevo)
        THROW 56422, 'TEST FAILED T-10: falta el Estudiante.', 1;
    IF NOT EXISTS (
        SELECT 1 FROM dbo.EstudianteGrupo eg
        INNER JOIN dbo.uv_estado_estudiante_grupo es ON es.id = eg.estado
        WHERE eg.estudiante = @idEstudianteNuevo AND eg.grupo = @grupo AND es.codigo = @codigoMatricula)
        THROW 56423, 'TEST FAILED T-10: la matricula debe quedar en el estado del parametro MATRICULA_QR/ESTADO_MATRICULA.', 1;
    IF (SELECT COUNT(*) FROM dbo.Usuario) <> @usrAntes + 1 OR (SELECT COUNT(*) FROM dbo.EstudianteGrupo WHERE grupo = @grupo) <> @egAntes + 1
        THROW 56424, 'TEST FAILED T-10: debe crearse exactamente 1 usuario y 1 matricula.', 1;
    IF (SELECT totalMatriculas FROM dbo.TokenMatriculaGrupo WHERE id = @idV) <> 1
        THROW 56425, 'TEST FAILED T-10: totalMatriculas debe incrementarse en 1.', 1;
    PRINT 'TEST_PASS:T-10';

    -- =========================================================================
    -- T-12: ya matriculado (MQR_004), sin cambios
    -- =========================================================================
    PRINT '-> T-12: repetir la matricula devuelve MQR_004';
    -- Modo autenticado con el estudiante recien creado
    DELETE FROM #m;
    INSERT INTO #m
    EXEC dbo.usp_matricular_estudiante_por_token
        @tokenHash = NULL, @pin = @pin, @idUsuarioEjecutor = @idUsuarioNuevo, @idCorrelacion = @corr;
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'MQR_004',
        @mensajeUsuarioResultado = @msgU OUTPUT, @mensajeTecnicoResultado = @msgT OUTPUT;
    IF (SELECT COUNT(*) FROM #m WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msgU) <> 1
        THROW 56430, 'TEST FAILED T-12: el estudiante ya matriculado debe recibir estadoResultado = 0 con MQR_004.', 1;
    IF (SELECT COUNT(*) FROM dbo.EstudianteGrupo WHERE grupo = @grupo) <> @egAntes + 1
       OR (SELECT totalMatriculas FROM dbo.TokenMatriculaGrupo WHERE id = @idV) <> 1
        THROW 56431, 'TEST FAILED T-12: el rechazo no debe escribir ni incrementar totalMatriculas.', 1;
    PRINT 'TEST_PASS:T-12';

    -- =========================================================================
    -- T-11: documento o correo ya existentes en modo publico (MQR_005)
    -- =========================================================================
    PRINT '-> T-11: persona ya registrada en modo publico -> MQR_005';
    DECLARE @numeroOtro INT = @numero + 5;
    DECLARE @usrAntes2 INT = (SELECT COUNT(*) FROM dbo.Usuario);
    DELETE FROM #m;
    INSERT INTO #m
    EXEC dbo.usp_registrar_estudiante_por_token_publico
        @tokenHash = @hash, @pin = NULL,
        @idTipoIdentificacion = @tipoCC, @numeroIdentificacion = @numeroOtro,
        @primerNombre = N'Otra', @segundoNombre = N'Persona', @primerApellido = N'Mismo', @segundoApellido = N'Correo',
        @correo = @correo, @password = @pass, @idCorrelacion = @corr;
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'MQR_005',
        @mensajeUsuarioResultado = @msgU OUTPUT, @mensajeTecnicoResultado = @msgT OUTPUT;
    IF (SELECT COUNT(*) FROM #m WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msgU) <> 1
        THROW 56440, 'TEST FAILED T-11: un correo ya registrado debe recibir MQR_005.', 1;

    -- Mismo documento con otro correo
    DELETE FROM #m;
    INSERT INTO #m
    EXEC dbo.usp_registrar_estudiante_por_token_publico
        @tokenHash = @hash, @pin = NULL,
        @idTipoIdentificacion = @tipoCC, @numeroIdentificacion = @numero,
        @primerNombre = N'Otra', @segundoNombre = N'Persona', @primerApellido = N'Mismo', @segundoApellido = N'Documento',
        @correo = @correoOtro, @password = @pass, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #m WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msgU) <> 1
        THROW 56441, 'TEST FAILED T-11: un documento ya registrado debe recibir MQR_005.', 1;
    IF (SELECT COUNT(*) FROM dbo.Usuario) <> @usrAntes2
        THROW 56442, 'TEST FAILED T-11: el rechazo no debe crear usuarios.', 1;
    PRINT 'TEST_PASS:T-11';

    -- =========================================================================
    -- IDENT-001: el alta publica exige correo institucional (VCE_001), sin escrituras
    PRINT '-> T-11b: correo no institucional en el alta publica -> VCE_001';
    DECLARE @correoAjeno NVARCHAR(255) = CONCAT(N'hu176b.ajeno.', @sufijo, N'@gmail.com');
    DECLARE @num80 INT = @numero + 80;
    DECLARE @usrAntes2b INT = (SELECT COUNT(*) FROM dbo.Usuario);
    DELETE FROM #m;
    INSERT INTO #m
    EXEC dbo.usp_registrar_estudiante_por_token_publico
        @tokenHash = @hash, @pin = NULL,
        @idTipoIdentificacion = @tipoCC, @numeroIdentificacion = @num80,
        @primerNombre = N'Correo', @segundoNombre = N'Aje', @primerApellido = N'No', @segundoApellido = N'Institucional',
        @correo = @correoAjeno, @password = @pass, @idCorrelacion = @corr;
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'VCE_001', @p_param1 = @dominio,
        @mensajeUsuarioResultado = @msgU OUTPUT, @mensajeTecnicoResultado = @msgT OUTPUT;
    IF (SELECT COUNT(*) FROM #m WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msgU) <> 1
        THROW 56443, 'TEST FAILED T-11b: un correo no institucional debe recibir VCE_001.', 1;
    IF (SELECT COUNT(*) FROM dbo.Usuario) <> @usrAntes2b
        THROW 56444, 'TEST FAILED T-11b: el rechazo no debe crear usuarios.', 1;
    PRINT 'TEST_PASS:T-11b';

    -- A2: el modo autenticado exige ejecutor
    PRINT '-> T-17b: el modo autenticado sin ejecutor se rechaza (GEN_002)';
    DELETE FROM #m;
    INSERT INTO #m
    EXEC dbo.usp_matricular_estudiante_por_token @tokenHash = @hash, @pin = NULL, @idUsuarioEjecutor = NULL, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #m WHERE estadoResultado = 0) <> 1
        THROW 56451, 'TEST FAILED T-17b: sin ejecutor el modo autenticado debe rechazarse.', 1;
    PRINT 'TEST_PASS:T-17b';

    -- T-17 / R7: un usuario de otro rol (docente) no puede matricularse en modo autenticado
    -- =========================================================================
    PRINT '-> T-17: el modo autenticado exige el rol ESTUDIANTE';
    DELETE FROM #m;
    INSERT INTO #m
    EXEC dbo.usp_matricular_estudiante_por_token
        @tokenHash = @hash, @pin = NULL, @idUsuarioEjecutor = @userTitular, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #m WHERE estadoResultado = 0) <> 1
        THROW 56450, 'TEST FAILED T-17: un docente no puede matricularse por el modo autenticado.', 1;
    PRINT 'TEST_PASS:T-17';

    -- =========================================================================
    -- T-16: modo autenticado con un estudiante existente (sin crear usuario)
    -- =========================================================================
    PRINT '-> T-16: modo autenticado matricula sin crear usuarios';
    DECLARE @numeroAut INT = @numero + 20;
    DECLARE @correoAut NVARCHAR(255) = CONCAT(N'hu176b.aut.', @sufijo, @dominio);
    DECLARE @estU BIT, @estMsgU NVARCHAR(4000), @estMsgT NVARCHAR(4000);
    EXEC dbo.usp_sincronizar_usuario_interno
        @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = @numeroAut,
        @primerApellido = N'Aut', @segundoApellido = N'Ent', @primerNombre = N'Est', @segundoNombre = N'Aut',
        @correo = @correoAut, @password = @pass, @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @estMsgU OUTPUT, @mensajeTecnicoResultado = @estMsgT OUTPUT, @estadoResultado = @estU OUTPUT;
    DECLARE @idUsuarioAut UNIQUEIDENTIFIER = (SELECT id FROM dbo.Usuario WHERE correo = LOWER(@correoAut));
    EXEC dbo.usp_sincronizar_estudiante_interno
        @idUsuario = @idUsuarioAut, @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @estMsgU OUTPUT, @mensajeTecnicoResultado = @estMsgT OUTPUT, @estadoResultado = @estU OUTPUT;
    IF @idUsuarioAut IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.Estudiante WHERE usuario = @idUsuarioAut)
        THROW 56460, 'TEST FAILED T-16: no se pudo preparar el estudiante existente (fixture).', 1;

    DECLARE @usrAntes3 INT = (SELECT COUNT(*) FROM dbo.Usuario);
    DELETE FROM #m;
    INSERT INTO #m
    EXEC dbo.usp_matricular_estudiante_por_token
        @tokenHash = NULL, @pin = @pin, @idUsuarioEjecutor = @idUsuarioAut, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #m WHERE estadoResultado = 1 AND idUsuario = @idUsuarioAut AND idGrupo = @grupo) <> 1
        THROW 56461, 'TEST FAILED T-16: el estudiante autenticado debio matricularse con el PIN.', 1;
    IF (SELECT COUNT(*) FROM dbo.Usuario) <> @usrAntes3
        THROW 56462, 'TEST FAILED T-16: el modo autenticado no debe crear usuarios.', 1;
    IF (SELECT totalMatriculas FROM dbo.TokenMatriculaGrupo WHERE id = @idV) <> 2
        THROW 56463, 'TEST FAILED T-16: totalMatriculas debe ser 2.', 1;
    PRINT 'TEST_PASS:T-16';

    -- =========================================================================
    -- D2: el token anterior (dentro de la tolerancia) tambien matricula
    -- =========================================================================
    PRINT '-> T-37b: el token anterior matricula dentro de la tolerancia';
    DECLARE @tokR NVARCHAR(100) = CONCAT(N'tok-', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''));
    DECLARE @hashR VARBINARY(32) = HASHBYTES('SHA2_256', @tokR);
    DECLARE @pinR NCHAR(6) = RIGHT(CONCAT('000000', CAST((CAST(@pin AS INT) + 11) % 1000000 AS VARCHAR(6))), 6);
    DECLARE @rotacion INT = dbo.ufn_obtener_parametro_int(NULL, 'MATRICULA_QR', 'ROTACION_SEGUNDOS');
    IF OBJECT_ID(N'dbo.usp_rotar_token_matricula_automatico', N'P') IS NULL
        THROW 56470, 'TEST FAILED T-37b: SP usp_rotar_token_matricula_automatico no existe.', 1;
    UPDATE dbo.TokenMatriculaGrupo SET fechaRotacionUtc = DATEADD(SECOND, -(@rotacion + 5), SYSUTCDATETIME()) WHERE id = @idV;
    CREATE TABLE #rot (
        idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(MAX) NULL, mensajeTecnicoResultado NVARCHAR(MAX) NULL,
        estadoResultado BIT NOT NULL, idVentana UNIQUEIDENTIFIER NULL, idDocenteEmisor UNIQUEIDENTIFIER NULL,
        fechaRotacionUtc DATETIME2(0) NULL, fechaExpiracionUtc DATETIME2(0) NULL
    );
    INSERT INTO #rot EXEC dbo.usp_rotar_token_matricula_automatico
        @idGrupo = @grupo, @tokenHash = @hashR, @pin = @pinR, @idCorrelacion = @corr;

    DECLARE @numeroTol INT = @numero + 40;
    DELETE FROM #m;
    INSERT INTO #m
    EXEC dbo.usp_registrar_estudiante_por_token_publico
        @tokenHash = @hash, @pin = NULL,
        @idTipoIdentificacion = @tipoCC, @numeroIdentificacion = @numeroTol,
        @primerNombre = N'Tol', @segundoNombre = N'Er', @primerApellido = N'An', @segundoApellido = N'Cia',
        @correo = @correoTol, @password = @pass, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #m WHERE estadoResultado = 1) <> 1
        THROW 56471, 'TEST FAILED T-37b: el token anterior dentro de la tolerancia debio matricular.', 1;
    PRINT 'TEST_PASS:T-37b';

    -- Un token expirado no matricula
    PRINT '-> T-06b: un token fuera de la tolerancia no matricula';
    UPDATE dbo.TokenMatriculaGrupo
       SET fechaRotacionUtc = DATEADD(SECOND, -(dbo.ufn_obtener_parametro_int(NULL, 'MATRICULA_QR', 'TOLERANCIA_SEGUNDOS') + 5), SYSUTCDATETIME())
     WHERE id = @idV;
    DECLARE @usrAntes4 INT = (SELECT COUNT(*) FROM dbo.Usuario);
    DELETE FROM #m;
    INSERT INTO #m
    EXEC dbo.usp_registrar_estudiante_por_token_publico
        @tokenHash = @hash, @pin = NULL,
        @idTipoIdentificacion = @tipoCC, @numeroIdentificacion = @num50,
        @primerNombre = N'Fuera', @segundoNombre = N'De', @primerApellido = N'Tole', @segundoApellido = N'Rancia',
        @correo = @correoFuera, @password = @pass, @idCorrelacion = @corr;
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'MQR_001',
        @mensajeUsuarioResultado = @msgU OUTPUT, @mensajeTecnicoResultado = @msgT OUTPUT;
    IF (SELECT COUNT(*) FROM #m WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msgU) <> 1
        THROW 56472, 'TEST FAILED T-06b: un token fuera de la tolerancia debe recibir MQR_001.', 1;
    IF (SELECT COUNT(*) FROM dbo.Usuario) <> @usrAntes4
        THROW 56473, 'TEST FAILED T-06b: el rechazo no debe crear usuarios.', 1;
    PRINT 'TEST_PASS:T-06b';

    -- =========================================================================
    -- T-14: atomicidad. Falla forzada DESPUES de crear el usuario -> rollback total
    -- =========================================================================
    PRINT '-> T-14: falla despues de crear el usuario revierte todo';
    UPDATE dbo.TokenMatriculaGrupo SET fechaRotacionUtc = SYSUTCDATETIME() WHERE id = @idV;
    -- el token vigente ahora es @hashR
    DECLARE @totalAntes INT = (SELECT totalMatriculas FROM dbo.TokenMatriculaGrupo WHERE id = @idV);
    DECLARE @usrAntes5 INT = (SELECT COUNT(*) FROM dbo.Usuario);
    DECLARE @estAntes5 INT = (SELECT COUNT(*) FROM dbo.Estudiante);
    DECLARE @egAntes5 INT = (SELECT COUNT(*) FROM dbo.EstudianteGrupo);
    DECLARE @valorEstadoOriginal NVARCHAR(MAX) = (SELECT valor FROM dbo.CatalogoParametro WHERE grupo = 'MATRICULA_QR' AND clave = 'ESTADO_MATRICULA');
    UPDATE dbo.CatalogoParametro SET valor = N'ZZ' WHERE grupo = 'MATRICULA_QR' AND clave = 'ESTADO_MATRICULA';   -- estado inexistente

    DELETE FROM #m;
    INSERT INTO #m
    EXEC dbo.usp_registrar_estudiante_por_token_publico
        @tokenHash = @hashR, @pin = NULL,
        @idTipoIdentificacion = @tipoCC, @numeroIdentificacion = @num60,
        @primerNombre = N'Falla', @segundoNombre = N'For', @primerApellido = N'Zada', @segundoApellido = N'Atomica',
        @correo = @correoAtom, @password = @pass, @idCorrelacion = @corr;

    UPDATE dbo.CatalogoParametro SET valor = @valorEstadoOriginal WHERE grupo = 'MATRICULA_QR' AND clave = 'ESTADO_MATRICULA';

    IF (SELECT COUNT(*) FROM #m WHERE estadoResultado = 0) <> 1
        THROW 56480, 'TEST FAILED T-14: con un estado de matricula invalido debe responder estadoResultado = 0.', 1;
    IF (SELECT COUNT(*) FROM dbo.Usuario) <> @usrAntes5
       OR (SELECT COUNT(*) FROM dbo.Estudiante) <> @estAntes5
       OR (SELECT COUNT(*) FROM dbo.EstudianteGrupo) <> @egAntes5
       OR (SELECT totalMatriculas FROM dbo.TokenMatriculaGrupo WHERE id = @idV) <> @totalAntes
        THROW 56481, 'TEST FAILED T-14: la falla debe revertir usuario, estudiante, matricula y contador.', 1;
    IF @@TRANCOUNT < 1
        THROW 56482, 'TEST FAILED T-14: el SP no debe cerrar la transaccion del llamador.', 1;
    PRINT 'TEST_PASS:T-14';

    -- =========================================================================
    -- T-13 / T-04: sin cupo -> rechazo sin escrituras
    -- =========================================================================
    PRINT '-> T-13: grupo sin cupo';
    DECLARE @cantidadOriginal INT = (SELECT cantidadEstudiantes FROM dbo.Grupo WHERE id = @grupo);
    UPDATE dbo.Grupo SET cantidadEstudiantes = (SELECT estudiantesActivos FROM dbo.uv_grupo WHERE id = @grupo) WHERE id = @grupo;
    DECLARE @usrAntes6 INT = (SELECT COUNT(*) FROM dbo.Usuario);
    DECLARE @egAntes6 INT = (SELECT COUNT(*) FROM dbo.EstudianteGrupo WHERE grupo = @grupo);

    DELETE FROM #m;
    INSERT INTO #m
    EXEC dbo.usp_registrar_estudiante_por_token_publico
        @tokenHash = @hashR, @pin = NULL,
        @idTipoIdentificacion = @tipoCC, @numeroIdentificacion = @num70,
        @primerNombre = N'Sin', @segundoNombre = N'Cu', @primerApellido = N'Po', @segundoApellido = N'Lleno',
        @correo = @correoCupo, @password = @pass, @idCorrelacion = @corr;
    UPDATE dbo.Grupo SET cantidadEstudiantes = @cantidadOriginal WHERE id = @grupo;

    IF (SELECT COUNT(*) FROM #m WHERE estadoResultado = 0) <> 1
        THROW 56490, 'TEST FAILED T-13: un grupo sin cupo debe rechazar la matricula.', 1;
    IF (SELECT COUNT(*) FROM dbo.Usuario) <> @usrAntes6 OR (SELECT COUNT(*) FROM dbo.EstudianteGrupo WHERE grupo = @grupo) <> @egAntes6
        THROW 56491, 'TEST FAILED T-13: el rechazo por cupo no debe dejar usuarios ni matriculas.', 1;
    PRINT 'TEST_PASS:T-13';

    -- =========================================================================
    -- Validacion de forma: exactamente uno de token o PIN
    -- =========================================================================
    PRINT '-> T-30b: ninguno o ambos (token y PIN) se rechazan con MQR_007';
    DELETE FROM #m;
    INSERT INTO #m
    EXEC dbo.usp_matricular_estudiante_por_token
        @tokenHash = NULL, @pin = NULL, @idUsuarioEjecutor = @idUsuarioAut, @idCorrelacion = @corr;
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'MQR_007',
        @mensajeUsuarioResultado = @msgU OUTPUT, @mensajeTecnicoResultado = @msgT OUTPUT;
    IF (SELECT COUNT(*) FROM #m WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msgU) <> 1
        THROW 56495, 'TEST FAILED T-30b: sin token ni PIN debe recibir MQR_007.', 1;
    DELETE FROM #m;
    INSERT INTO #m
    EXEC dbo.usp_matricular_estudiante_por_token
        @tokenHash = @hashR, @pin = @pinR, @idUsuarioEjecutor = @idUsuarioAut, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #m WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msgU) <> 1
        THROW 56496, 'TEST FAILED T-30b: token y PIN a la vez debe recibir MQR_007.', 1;
    PRINT 'TEST_PASS:T-30b';

    DROP TABLE #rot;
    DROP TABLE #m;
    DROP TABLE #r;
    ROLLBACK TRANSACTION;
    PRINT '-> Rollback transaccional ejecutado. Cero residuos.';
END TRY
BEGIN CATCH
    IF USER_NAME() <> 'dbo' REVERT;
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT CONCAT('ERROR EN TEST: ', ERROR_MESSAGE());
    THROW;
END CATCH;

IF @@TRANCOUNT <> 0
    THROW 56499, 'TEST FAILED HU176B-G01: test_usp_matricular_estudiante_por_token dejo transacciones abiertas.', 1;

PRINT 'TEST_PASS:HU176B-MAT-G01';
PRINT '==================================================';
PRINT 'TEST PASS: test_usp_matricular_estudiante_por_token (OK)';
PRINT '==================================================';
PRINT 'TEST_PASS:TEST_USP_MATRICULAR_ESTUDIANTE_POR_TOKEN';
GO
