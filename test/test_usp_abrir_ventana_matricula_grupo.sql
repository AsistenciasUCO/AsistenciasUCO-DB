USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_usp_abrir_ventana_matricula_grupo (HU176B)';
PRINT 'Contrato: GestioAsistenciaBackend/docs/work-items/HU176B-matricula-qr-autonoma/CONTRACT.md (§2.2, §2.3, §2.6, A1)';
PRINT '==================================================';

BEGIN TRANSACTION;
BEGIN TRY
    -- =========================================================================
    -- 0. Existencia de los objetos del contrato (falla en RED si faltan)
    -- =========================================================================
    IF OBJECT_ID(N'dbo.TokenMatriculaGrupo', N'U') IS NULL
        THROW 56000, 'TEST FAILED HU176B-T00: tabla dbo.TokenMatriculaGrupo no existe.', 1;
    IF OBJECT_ID(N'dbo.uv_token_matricula_grupo', N'V') IS NULL
        THROW 56001, 'TEST FAILED HU176B-T00: vista dbo.uv_token_matricula_grupo no existe.', 1;
    IF OBJECT_ID(N'dbo.usp_abrir_ventana_matricula_grupo', N'P') IS NULL
        THROW 56002, 'TEST FAILED HU176B-T00: SP usp_abrir_ventana_matricula_grupo no existe.', 1;

    -- Parametros sembrados (CONTRACT §2.6 / A1): administrables desde la DB
    IF ISNULL(dbo.ufn_obtener_parametro_int(NULL, 'MATRICULA_QR', 'DURACION_MAXIMA_MINUTOS'), 0) <= 0
        THROW 56003, 'TEST FAILED HU176B-M01: parametro MATRICULA_QR/DURACION_MAXIMA_MINUTOS ausente o invalido.', 1;
    IF ISNULL(dbo.ufn_obtener_parametro_int(NULL, 'MATRICULA_QR', 'ROTACION_SEGUNDOS'), 0) <= 0
        THROW 56004, 'TEST FAILED HU176B-M01: parametro MATRICULA_QR/ROTACION_SEGUNDOS ausente o invalido.', 1;
    IF dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_ACTIVA') = N''
       OR dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_CERRADA') = N''
        THROW 56005, 'TEST FAILED HU176B-M01: parametros MATRICULA_QR/ESTADO_ACTIVA|ESTADO_CERRADA ausentes.', 1;

    -- =========================================================================
    -- Fixtures
    -- =========================================================================
    CREATE TABLE #r (
        idCorrelacion UNIQUEIDENTIFIER NULL,
        mensajeUsuarioResultado NVARCHAR(MAX) NULL,
        mensajeTecnicoResultado NVARCHAR(MAX) NULL,
        estadoResultado BIT NOT NULL,
        idVentana UNIQUEIDENTIFIER NULL,
        fechaExpiracionUtc DATETIME2(0) NULL
    );

    DECLARE @estadoActiva  NVARCHAR(10) = dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_ACTIVA');
    DECLARE @estadoCerrada NVARCHAR(10) = dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_CERRADA');
    DECLARE @duracion INT = dbo.ufn_obtener_parametro_int(NULL, 'MATRICULA_QR', 'DURACION_MAXIMA_MINUTOS');

    DECLARE @grupo UNIQUEIDENTIFIER, @docenteTitular UNIQUEIDENTIFIER, @userTitular UNIQUEIDENTIFIER;
    DECLARE @userOtroDocente UNIQUEIDENTIFIER, @userCoordPrograma UNIQUEIDENTIFIER;

    SELECT TOP 1 @grupo = g.id, @docenteTitular = g.docente
    FROM dbo.Grupo g
    INNER JOIN dbo.uv_grupo vg ON vg.id = g.id
    WHERE vg.grupoEstaHablitado = 1 AND vg.cuposDisponibles > 5
    ORDER BY vg.cuposDisponibles DESC;

    SELECT @userTitular = usuario FROM dbo.Docente WHERE id = @docenteTitular;
    SELECT TOP 1 @userOtroDocente = usuario FROM dbo.Docente WHERE id <> @docenteTitular AND usuario <> @userTitular ORDER BY id;
    SELECT @userCoordPrograma = c.usuario
    FROM dbo.Grupo g
    INNER JOIN dbo.Asignatura a ON a.id = g.asignatura
    INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = a.semestrePlanEstudio
    INNER JOIN dbo.PlanEstudio pe ON pe.id = spe.planEstudio
    INNER JOIN dbo.Programa pr ON pr.id = pe.programa
    INNER JOIN dbo.Coordinador c ON c.id = pr.coordinador
    WHERE g.id = @grupo;

    IF @grupo IS NULL OR @userTitular IS NULL OR @userOtroDocente IS NULL OR @userCoordPrograma IS NULL
        THROW 56010, 'TEST FAILED HU176B: fixture de grupo/docentes/coordinador faltante (semilla).', 1;

    DECLARE @token1 NVARCHAR(100) = CONCAT(N'tok-', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''));
    DECLARE @token2 NVARCHAR(100) = CONCAT(N'tok-', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''));
    DECLARE @hash1 VARBINARY(32) = HASHBYTES('SHA2_256', @token1);
    DECLARE @hash2 VARBINARY(32) = HASHBYTES('SHA2_256', @token2);
    DECLARE @pin1 NCHAR(6) = RIGHT(CONCAT('000000', CAST(ABS(CHECKSUM(NEWID())) % 1000000 AS VARCHAR(6))), 6);
    DECLARE @pin2 NCHAR(6) = RIGHT(CONCAT('000000', CAST((ABS(CHECKSUM(NEWID())) % 999999) + 1 AS VARCHAR(6))), 6);
    IF @pin2 = @pin1 SET @pin2 = RIGHT(CONCAT('000000', CAST((CAST(@pin1 AS INT) + 1) % 1000000 AS VARCHAR(6))), 6);
    DECLARE @corr UNIQUEIDENTIFIER = NEWID();
    DECLARE @msgU NVARCHAR(4000), @msgT NVARCHAR(4000);
    DECLARE @antes DATETIME2(0), @despues DATETIME2(0);
    DECLARE @id1 UNIQUEIDENTIFIER;

    -- Sin ventanas previas del grupo de prueba
    UPDATE dbo.TokenMatriculaGrupo SET estado = @estadoCerrada WHERE grupo = @grupo AND estado = @estadoActiva;

    -- =========================================================================
    -- T-01 / CA-01: el docente titular abre la ventana
    -- =========================================================================
    PRINT '-> T-01: apertura por el docente titular';
    SET @antes = SYSUTCDATETIME();
    DELETE FROM #r;
    INSERT INTO #r
    EXEC dbo.usp_abrir_ventana_matricula_grupo
        @idGrupo = @grupo, @tokenHash = @hash1, @pin = @pin1,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @userTitular;
    SET @despues = SYSUTCDATETIME();

    IF (SELECT COUNT(*) FROM #r WHERE estadoResultado = 1 AND idCorrelacion = @corr AND idVentana IS NOT NULL) <> 1
        THROW 56020, 'TEST FAILED T-01: el docente titular debio abrir la ventana con estadoResultado = 1 e idVentana.', 1;
    SELECT @id1 = idVentana FROM #r;

    IF NOT EXISTS (
        SELECT 1 FROM dbo.TokenMatriculaGrupo
        WHERE id = @id1 AND grupo = @grupo AND docenteEmisor = @docenteTitular
          AND estado = @estadoActiva AND tokenHash = @hash1 AND pin = @pin1
          AND tokenHashAnterior IS NULL AND pinAnterior IS NULL
          AND totalMatriculas = 0
          AND fechaCierreUtc IS NULL
          AND fechaRotacionUtc BETWEEN DATEADD(SECOND, -2, @antes) AND DATEADD(SECOND, 2, @despues)
          AND fechaEmisionUtc  BETWEEN DATEADD(SECOND, -2, @antes) AND DATEADD(SECOND, 2, @despues)
    )
        THROW 56021, 'TEST FAILED T-01: la fila de la ventana no refleja el contrato (estado, hash, pin, docente, fechas, sin anterior).', 1;

    -- Fin de ventana = emision + DURACION_MAXIMA_MINUTOS (parametro de la DB, A1)
    IF NOT EXISTS (
        SELECT 1 FROM dbo.TokenMatriculaGrupo
        WHERE id = @id1
          AND fechaExpiracionUtc = DATEADD(MINUTE, @duracion, fechaEmisionUtc)
    )
        THROW 56022, 'TEST FAILED T-01: fechaExpiracionUtc debe ser emision + DURACION_MAXIMA_MINUTOS.', 1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE fechaExpiracionUtc = (SELECT fechaExpiracionUtc FROM dbo.TokenMatriculaGrupo WHERE id = @id1))
        THROW 56023, 'TEST FAILED T-01: el resultset debe devolver la fechaExpiracionUtc de la ventana.', 1;
    PRINT 'TEST_PASS:T-01';

    -- =========================================================================
    -- T-08: el token solo se guarda hasheado
    -- =========================================================================
    PRINT '-> T-08: el token en claro no se persiste';
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.TokenMatriculaGrupo') AND LOWER(name) IN (N'token', N'tokenenclaro'))
        THROW 56030, 'TEST FAILED T-08: la tabla no debe tener una columna con el token en claro.', 1;
    IF (SELECT COUNT(*) FROM dbo.TokenMatriculaGrupo WHERE id = @id1 AND DATALENGTH(tokenHash) = 32) <> 1
        THROW 56031, 'TEST FAILED T-08: tokenHash debe ser un SHA-256 de 32 bytes.', 1;
    IF EXISTS (SELECT 1 FROM dbo.uv_token_matricula_grupo WHERE id = @id1)
       AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.uv_token_matricula_grupo') AND name IN (N'tokenHash', N'tokenHashAnterior'))
        THROW 56032, 'TEST FAILED T-08: la vista no debe exponer tokenHash ni tokenHashAnterior.', 1;
    PRINT 'TEST_PASS:T-08';

    -- =========================================================================
    -- T-02: una sola ventana activa por grupo
    -- =========================================================================
    PRINT '-> T-02: abrir otra ventana revoca la anterior';
    DECLARE @id2 UNIQUEIDENTIFIER;
    DELETE FROM #r;
    INSERT INTO #r
    EXEC dbo.usp_abrir_ventana_matricula_grupo
        @idGrupo = @grupo, @tokenHash = @hash2, @pin = @pin2,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @userTitular;
    IF (SELECT COUNT(*) FROM #r WHERE estadoResultado = 1) <> 1
        THROW 56040, 'TEST FAILED T-02: la segunda apertura debio ser exitosa.', 1;
    SELECT @id2 = idVentana FROM #r;

    IF (SELECT COUNT(*) FROM dbo.TokenMatriculaGrupo WHERE grupo = @grupo AND estado = @estadoActiva) <> 1
        THROW 56041, 'TEST FAILED T-02: debe quedar exactamente una ventana ACTIVA por grupo.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.TokenMatriculaGrupo WHERE id = @id1 AND estado = @estadoCerrada AND fechaCierreUtc IS NOT NULL)
        THROW 56042, 'TEST FAILED T-02: la primera ventana debio quedar CERRADA con fechaCierreUtc.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.TokenMatriculaGrupo WHERE id = @id2 AND estado = @estadoActiva AND tokenHash = @hash2)
        THROW 56043, 'TEST FAILED T-02: la segunda ventana debe estar ACTIVA con el hash nuevo.', 1;
    PRINT 'TEST_PASS:T-02';

    -- =========================================================================
    -- T-03: solo el docente titular (RBAC + titularidad)
    -- =========================================================================
    PRINT '-> T-03: docente no titular y coordinador no pueden abrir';
    DECLARE @token3 NVARCHAR(100) = CONCAT(N'tok-', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''));
    DECLARE @hash3 VARBINARY(32) = HASHBYTES('SHA2_256', @token3);
    DECLARE @pin3 NCHAR(6) = RIGHT(CONCAT('000000', CAST((CAST(@pin2 AS INT) + 7) % 1000000 AS VARCHAR(6))), 6);
    DECLARE @filasAntes INT = (SELECT COUNT(*) FROM dbo.TokenMatriculaGrupo);

    DELETE FROM #r;
    INSERT INTO #r
    EXEC dbo.usp_abrir_ventana_matricula_grupo
        @idGrupo = @grupo, @tokenHash = @hash3, @pin = @pin3,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @userOtroDocente;
    IF (SELECT COUNT(*) FROM #r WHERE estadoResultado = 0 AND idVentana IS NULL) <> 1
        THROW 56050, 'TEST FAILED T-03: un docente no titular debio recibir estadoResultado = 0.', 1;

    DELETE FROM #r;
    INSERT INTO #r
    EXEC dbo.usp_abrir_ventana_matricula_grupo
        @idGrupo = @grupo, @tokenHash = @hash3, @pin = @pin3,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @userCoordPrograma;
    IF (SELECT COUNT(*) FROM #r WHERE estadoResultado = 0 AND idVentana IS NULL) <> 1
        THROW 56051, 'TEST FAILED T-03: el coordinador no puede abrir ventanas de matricula (RBAC DOCENTE).', 1;

    IF @filasAntes <> (SELECT COUNT(*) FROM dbo.TokenMatriculaGrupo)
       OR NOT EXISTS (SELECT 1 FROM dbo.TokenMatriculaGrupo WHERE id = @id2 AND estado = @estadoActiva)
        THROW 56052, 'TEST FAILED T-03: los rechazos no deben escribir ni cerrar la ventana existente.', 1;
    PRINT 'TEST_PASS:T-03';

    -- Sin ejecutor: se rechaza (la apertura siempre requiere un docente)
    PRINT '-> T-03b: sin ejecutor se rechaza';
    DELETE FROM #r;
    INSERT INTO #r
    EXEC dbo.usp_abrir_ventana_matricula_grupo
        @idGrupo = @grupo, @tokenHash = @hash3, @pin = @pin3,
        @idCorrelacion = @corr, @idUsuarioEjecutor = NULL;
    IF (SELECT COUNT(*) FROM #r WHERE estadoResultado = 0) <> 1
        THROW 56053, 'TEST FAILED T-03b: sin idUsuarioEjecutor debio rechazarse (GEN_002).', 1;
    PRINT 'TEST_PASS:T-03b';

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
    THROW 56199, 'TEST FAILED HU176B-G01: test_usp_abrir_ventana_matricula_grupo dejo transacciones abiertas.', 1;

PRINT 'TEST_PASS:HU176B-G01';
PRINT '==================================================';
PRINT 'TEST PASS: test_usp_abrir_ventana_matricula_grupo (OK)';
PRINT '==================================================';
PRINT 'TEST_PASS:TEST_USP_ABRIR_VENTANA_MATRICULA_GRUPO';
GO
