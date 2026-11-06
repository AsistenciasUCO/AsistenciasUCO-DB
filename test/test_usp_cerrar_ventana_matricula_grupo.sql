USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_usp_cerrar_ventana_matricula_grupo (HU176B)';
PRINT 'Contrato: CONTRACT.md §2.3 (cierre idempotente, RBAC DOCENTE + titularidad)';
PRINT '==================================================';

BEGIN TRANSACTION;
BEGIN TRY
    IF OBJECT_ID(N'dbo.TokenMatriculaGrupo', N'U') IS NULL
        THROW 56100, 'TEST FAILED HU176B-C00: tabla dbo.TokenMatriculaGrupo no existe.', 1;
    IF OBJECT_ID(N'dbo.usp_abrir_ventana_matricula_grupo', N'P') IS NULL
        THROW 56101, 'TEST FAILED HU176B-C00: SP usp_abrir_ventana_matricula_grupo no existe.', 1;
    IF OBJECT_ID(N'dbo.usp_cerrar_ventana_matricula_grupo', N'P') IS NULL
        THROW 56102, 'TEST FAILED HU176B-C00: SP usp_cerrar_ventana_matricula_grupo no existe.', 1;
    IF OBJECT_ID(N'dbo.usp_validar_token_matricula_publico', N'P') IS NULL
        THROW 56103, 'TEST FAILED HU176B-C00: SP usp_validar_token_matricula_publico no existe.', 1;

    CREATE TABLE #r (
        idCorrelacion UNIQUEIDENTIFIER NULL,
        mensajeUsuarioResultado NVARCHAR(MAX) NULL,
        mensajeTecnicoResultado NVARCHAR(MAX) NULL,
        estadoResultado BIT NOT NULL,
        idVentana UNIQUEIDENTIFIER NULL,
        fechaExpiracionUtc DATETIME2(0) NULL
    );
    CREATE TABLE #c (
        idCorrelacion UNIQUEIDENTIFIER NULL,
        mensajeUsuarioResultado NVARCHAR(MAX) NULL,
        mensajeTecnicoResultado NVARCHAR(MAX) NULL,
        estadoResultado BIT NOT NULL
    );
    CREATE TABLE #val (
        idGrupo UNIQUEIDENTIFIER NULL, nombreAsignatura NVARCHAR(200) NULL, nombreGrupo NVARCHAR(200) NULL,
        nombreDocente NVARCHAR(300) NULL, fechaExpiracionUtc DATETIME2(0) NULL, cupoDisponible INT NULL
    );

    DECLARE @estadoActiva  NVARCHAR(10) = dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_ACTIVA');
    DECLARE @estadoCerrada NVARCHAR(10) = dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_CERRADA');
    IF @estadoActiva = N'' OR @estadoCerrada = N''
        THROW 56104, 'TEST FAILED HU176B-M01: parametros MATRICULA_QR/ESTADO_ACTIVA|ESTADO_CERRADA ausentes.', 1;

    DECLARE @grupo UNIQUEIDENTIFIER, @docenteTitular UNIQUEIDENTIFIER, @userTitular UNIQUEIDENTIFIER, @userOtro UNIQUEIDENTIFIER;
    SELECT TOP 1 @grupo = g.id, @docenteTitular = g.docente
    FROM dbo.Grupo g INNER JOIN dbo.uv_grupo vg ON vg.id = g.id
    WHERE vg.grupoEstaHablitado = 1 AND vg.cuposDisponibles > 5
    ORDER BY vg.cuposDisponibles DESC;
    SELECT @userTitular = usuario FROM dbo.Docente WHERE id = @docenteTitular;
    SELECT TOP 1 @userOtro = usuario FROM dbo.Docente WHERE id <> @docenteTitular AND usuario <> @userTitular ORDER BY id;
    IF @grupo IS NULL OR @userTitular IS NULL OR @userOtro IS NULL
        THROW 56110, 'TEST FAILED HU176B: fixture de grupo/docentes faltante (semilla).', 1;

    UPDATE dbo.TokenMatriculaGrupo SET estado = @estadoCerrada WHERE grupo = @grupo AND estado = @estadoActiva;

    DECLARE @corr UNIQUEIDENTIFIER = NEWID();
    DECLARE @tok NVARCHAR(100) = CONCAT(N'tok-', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''));
    DECLARE @hash VARBINARY(32) = HASHBYTES('SHA2_256', @tok);
    DECLARE @pin NCHAR(6) = RIGHT(CONCAT('000000', CAST(ABS(CHECKSUM(NEWID())) % 1000000 AS VARCHAR(6))), 6);
    DECLARE @idV UNIQUEIDENTIFIER, @capturado NVARCHAR(4000);

    INSERT INTO #r
    EXEC dbo.usp_abrir_ventana_matricula_grupo @idGrupo = @grupo, @tokenHash = @hash, @pin = @pin,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @userTitular;
    SELECT @idV = idVentana FROM #r WHERE estadoResultado = 1;
    IF @idV IS NULL
        THROW 56111, 'TEST FAILED HU176B: no se pudo abrir la ventana de prueba (depende de usp_abrir_ventana_matricula_grupo).', 1;

    -- T-05a: un docente no titular no puede cerrar
    PRINT '-> T-05a: un docente no titular no puede cerrar';
    DELETE FROM #c;
    INSERT INTO #c EXEC dbo.usp_cerrar_ventana_matricula_grupo @idGrupo = @grupo, @idCorrelacion = @corr, @idUsuarioEjecutor = @userOtro;
    IF (SELECT COUNT(*) FROM #c WHERE estadoResultado = 0) <> 1
        THROW 56120, 'TEST FAILED T-05a: un docente no titular debio recibir estadoResultado = 0.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.TokenMatriculaGrupo WHERE id = @idV AND estado = @estadoActiva)
        THROW 56121, 'TEST FAILED T-05a: el rechazo no debe cerrar la ventana.', 1;
    PRINT 'TEST_PASS:T-05a';

    -- T-05b: el titular cierra
    PRINT '-> T-05b: el titular cierra la ventana activa';
    DELETE FROM #c;
    INSERT INTO #c EXEC dbo.usp_cerrar_ventana_matricula_grupo @idGrupo = @grupo, @idCorrelacion = @corr, @idUsuarioEjecutor = @userTitular;
    IF (SELECT COUNT(*) FROM #c WHERE estadoResultado = 1) <> 1
        THROW 56122, 'TEST FAILED T-05b: el titular debio cerrar con estadoResultado = 1.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.TokenMatriculaGrupo WHERE id = @idV AND estado = @estadoCerrada AND fechaCierreUtc IS NOT NULL)
        THROW 56123, 'TEST FAILED T-05b: la ventana debe quedar CERRADA con fechaCierreUtc.', 1;
    PRINT 'TEST_PASS:T-05b';

    -- T-02 (efecto): un token de una ventana cerrada se rechaza con el mensaje generico
    PRINT '-> T-05c: el token de una ventana cerrada se rechaza (MQR_001)';
    SET @capturado = N'';
    BEGIN TRY
        INSERT INTO #val EXEC dbo.usp_validar_token_matricula_publico @tokenHash = @hash, @pin = NULL, @idCorrelacion = @corr;
    END TRY
    BEGIN CATCH
        SET @capturado = ERROR_MESSAGE();
    END CATCH
    IF @capturado NOT LIKE N'%DBCODE=MQR_001%'
        THROW 56124, 'TEST FAILED T-05c: el token cerrado debe recibir MQR_001.', 1;
    SET @capturado = N'';
    BEGIN TRY
        INSERT INTO #val EXEC dbo.usp_validar_token_matricula_publico @tokenHash = NULL, @pin = @pin, @idCorrelacion = @corr;
    END TRY
    BEGIN CATCH
        SET @capturado = ERROR_MESSAGE();
    END CATCH
    IF @capturado NOT LIKE N'%DBCODE=MQR_001%'
        THROW 56125, 'TEST FAILED T-05c: el PIN cerrado debe recibir MQR_001.', 1;
    PRINT 'TEST_PASS:T-05c';

    -- T-05d: idempotente (sin ventana activa)
    PRINT '-> T-05d: cerrar sin ventana activa es exito sin cambios';
    DECLARE @filas INT = (SELECT COUNT(*) FROM dbo.TokenMatriculaGrupo);
    DECLARE @fechaCierre DATETIME2(0) = (SELECT fechaCierreUtc FROM dbo.TokenMatriculaGrupo WHERE id = @idV);
    DELETE FROM #c;
    INSERT INTO #c EXEC dbo.usp_cerrar_ventana_matricula_grupo @idGrupo = @grupo, @idCorrelacion = @corr, @idUsuarioEjecutor = @userTitular;
    IF (SELECT COUNT(*) FROM #c WHERE estadoResultado = 1) <> 1
        THROW 56126, 'TEST FAILED T-05d: cerrar sin ventana activa debe responder exito.', 1;
    IF @filas <> (SELECT COUNT(*) FROM dbo.TokenMatriculaGrupo)
       OR @fechaCierre <> (SELECT fechaCierreUtc FROM dbo.TokenMatriculaGrupo WHERE id = @idV)
        THROW 56127, 'TEST FAILED T-05d: el cierre repetido no debe cambiar nada.', 1;
    PRINT 'TEST_PASS:T-05d';

    -- Sin ejecutor se rechaza
    DELETE FROM #c;
    INSERT INTO #c EXEC dbo.usp_cerrar_ventana_matricula_grupo @idGrupo = @grupo, @idCorrelacion = @corr, @idUsuarioEjecutor = NULL;
    IF (SELECT COUNT(*) FROM #c WHERE estadoResultado = 0) <> 1
        THROW 56128, 'TEST FAILED T-05e: sin idUsuarioEjecutor debe rechazarse (GEN_002).', 1;
    PRINT 'TEST_PASS:T-05e';

    DROP TABLE #val;
    DROP TABLE #c;
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
    THROW 56199, 'TEST FAILED HU176B-G01: test_usp_cerrar_ventana_matricula_grupo dejo transacciones abiertas.', 1;

PRINT 'TEST_PASS:HU176B-CER-G01';
PRINT '==================================================';
PRINT 'TEST PASS: test_usp_cerrar_ventana_matricula_grupo (OK)';
PRINT '==================================================';
PRINT 'TEST_PASS:TEST_USP_CERRAR_VENTANA_MATRICULA_GRUPO';
GO
