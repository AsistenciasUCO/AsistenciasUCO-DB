USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_usp_validar_token_matricula_publico (HU176B)';
PRINT 'Contrato: CONTRACT.md §2.4 (consulta publica sin ejecutor, anti-enumeracion)';
PRINT '==================================================';

BEGIN TRANSACTION;
BEGIN TRY
    IF OBJECT_ID(N'dbo.TokenMatriculaGrupo', N'U') IS NULL
        THROW 56200, 'TEST FAILED HU176B-V00: tabla dbo.TokenMatriculaGrupo no existe.', 1;
    IF OBJECT_ID(N'dbo.usp_abrir_ventana_matricula_grupo', N'P') IS NULL
        THROW 56201, 'TEST FAILED HU176B-V00: SP usp_abrir_ventana_matricula_grupo no existe.', 1;
    IF OBJECT_ID(N'dbo.usp_validar_token_matricula_publico', N'P') IS NULL
        THROW 56202, 'TEST FAILED HU176B-V00: SP usp_validar_token_matricula_publico no existe.', 1;
    IF OBJECT_ID(N'dbo.usp_internal_resolver_token_matricula', N'P') IS NULL
        THROW 56203, 'TEST FAILED HU176B-V00: SP usp_internal_resolver_token_matricula no existe.', 1;
    IF (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('MQR_001','MQR_002','MQR_003','MQR_004','MQR_005','MQR_006','MQR_007') AND estaActivo = 1) <> 7
       OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('MQR_001','MQR_002','MQR_003','MQR_004','MQR_005','MQR_006','MQR_007') AND estaActivo = 1) <> 7
        THROW 56204, 'TEST FAILED HU176B-M01: faltan mensajes MQR_001..MQR_007 (usuario/tecnico).', 1;

    CREATE TABLE #r (
        idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(MAX) NULL,
        mensajeTecnicoResultado NVARCHAR(MAX) NULL, estadoResultado BIT NOT NULL,
        idVentana UNIQUEIDENTIFIER NULL, fechaExpiracionUtc DATETIME2(0) NULL
    );
    CREATE TABLE #val (
        idGrupo UNIQUEIDENTIFIER NULL, nombreAsignatura NVARCHAR(200) NULL, nombreGrupo NVARCHAR(200) NULL,
        nombreDocente NVARCHAR(300) NULL, fechaExpiracionUtc DATETIME2(0) NULL, cupoDisponible INT NULL
    );

    DECLARE @estadoActiva  NVARCHAR(10) = dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_ACTIVA');
    DECLARE @estadoCerrada NVARCHAR(10) = dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_CERRADA');
    DECLARE @estadoExpirada NVARCHAR(10) = dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_EXPIRADA');

    DECLARE @grupo UNIQUEIDENTIFIER, @docenteTitular UNIQUEIDENTIFIER, @userTitular UNIQUEIDENTIFIER;
    SELECT TOP 1 @grupo = g.id, @docenteTitular = g.docente
    FROM dbo.Grupo g INNER JOIN dbo.uv_grupo vg ON vg.id = g.id
    WHERE vg.grupoEstaHablitado = 1 AND vg.cuposDisponibles > 5
    ORDER BY vg.cuposDisponibles DESC;
    SELECT @userTitular = usuario FROM dbo.Docente WHERE id = @docenteTitular;
    IF @grupo IS NULL OR @userTitular IS NULL
        THROW 56210, 'TEST FAILED HU176B: fixture de grupo/docente faltante (semilla).', 1;
    UPDATE dbo.TokenMatriculaGrupo SET estado = @estadoCerrada WHERE grupo = @grupo AND estado = @estadoActiva;

    DECLARE @corr UNIQUEIDENTIFIER = NEWID();
    DECLARE @tok NVARCHAR(100) = CONCAT(N'tok-', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''));
    DECLARE @hash VARBINARY(32) = HASHBYTES('SHA2_256', @tok);
    DECLARE @pin NCHAR(6) = RIGHT(CONCAT('000000', CAST(ABS(CHECKSUM(NEWID())) % 1000000 AS VARCHAR(6))), 6);
    DECLARE @idV UNIQUEIDENTIFIER, @capturado NVARCHAR(4000), @msgU NVARCHAR(4000), @msgT NVARCHAR(4000);

    INSERT INTO #r
    EXEC dbo.usp_abrir_ventana_matricula_grupo @idGrupo = @grupo, @tokenHash = @hash, @pin = @pin,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @userTitular;
    SELECT @idV = idVentana FROM #r WHERE estadoResultado = 1;
    IF @idV IS NULL
        THROW 56211, 'TEST FAILED HU176B: no se pudo abrir la ventana de prueba (depende de usp_abrir_ventana_matricula_grupo).', 1;

    -- =========================================================================
    -- V-01: token valido -> datos minimos del curso (sin PII de estudiantes)
    -- =========================================================================
    PRINT '-> V-01: token y PIN vigentes devuelven los datos minimos del curso';
    DELETE FROM #val;
    INSERT INTO #val EXEC dbo.usp_validar_token_matricula_publico @tokenHash = @hash, @pin = NULL, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #val WHERE idGrupo = @grupo AND nombreAsignatura IS NOT NULL AND nombreGrupo IS NOT NULL
                                    AND nombreDocente IS NOT NULL AND cupoDisponible >= 0) <> 1
        THROW 56220, 'TEST FAILED V-01: el token vigente debe devolver exactamente una fila con los datos del curso.', 1;
    IF NOT EXISTS (SELECT 1 FROM #val v INNER JOIN dbo.TokenMatriculaGrupo t ON t.id = @idV WHERE v.fechaExpiracionUtc = t.fechaExpiracionUtc)
        THROW 56221, 'TEST FAILED V-01: fechaExpiracionUtc debe ser el fin de la ventana.', 1;
    DELETE FROM #val;
    INSERT INTO #val EXEC dbo.usp_validar_token_matricula_publico @tokenHash = NULL, @pin = @pin, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #val WHERE idGrupo = @grupo) <> 1
        THROW 56222, 'TEST FAILED V-01: el PIN vigente debe validar.', 1;
    PRINT 'TEST_PASS:V-01';

    -- =========================================================================
    -- V-02: exactamente uno de token o PIN (MQR_007)
    -- =========================================================================
    PRINT '-> V-02: ninguno o ambos -> MQR_007';
    SET @capturado = N'';
    BEGIN TRY
        INSERT INTO #val EXEC dbo.usp_validar_token_matricula_publico @tokenHash = NULL, @pin = NULL, @idCorrelacion = @corr;
    END TRY
    BEGIN CATCH SET @capturado = ERROR_MESSAGE(); END CATCH
    IF @capturado NOT LIKE N'%DBCODE=MQR_007%'
        THROW 56230, 'TEST FAILED V-02: sin token ni PIN debe recibir MQR_007.', 1;
    SET @capturado = N'';
    BEGIN TRY
        INSERT INTO #val EXEC dbo.usp_validar_token_matricula_publico @tokenHash = @hash, @pin = @pin, @idCorrelacion = @corr;
    END TRY
    BEGIN CATCH SET @capturado = ERROR_MESSAGE(); END CATCH
    IF @capturado NOT LIKE N'%DBCODE=MQR_007%'
        THROW 56231, 'TEST FAILED V-02: token y PIN a la vez debe recibir MQR_007.', 1;
    PRINT 'TEST_PASS:V-02';

    -- =========================================================================
    -- T-07: anti-enumeracion (inexistente, cerrado, expirado -> mismo error)
    -- =========================================================================
    PRINT '-> T-07: inexistente / expirado / cerrado devuelven el mismo error';
    DECLARE @errInexistente NVARCHAR(4000) = N'', @errExpirado NVARCHAR(4000) = N'', @errCerrado NVARCHAR(4000) = N'';
    DECLARE @hashFalso VARBINARY(32) = HASHBYTES('SHA2_256', CONCAT(N'no-existe-', NEWID()));

    BEGIN TRY
        INSERT INTO #val EXEC dbo.usp_validar_token_matricula_publico @tokenHash = @hashFalso, @pin = NULL, @idCorrelacion = @corr;
    END TRY
    BEGIN CATCH SET @errInexistente = ERROR_MESSAGE(); END CATCH

    -- expirado (T-06): la ventana vence y la fila pasa a EXPIRADA de forma perezosa
    UPDATE dbo.TokenMatriculaGrupo SET fechaExpiracionUtc = DATEADD(SECOND, -10, SYSUTCDATETIME()) WHERE id = @idV;
    BEGIN TRY
        INSERT INTO #val EXEC dbo.usp_validar_token_matricula_publico @tokenHash = @hash, @pin = NULL, @idCorrelacion = @corr;
    END TRY
    BEGIN CATCH SET @errExpirado = ERROR_MESSAGE(); END CATCH
    IF NOT EXISTS (SELECT 1 FROM dbo.TokenMatriculaGrupo WHERE id = @idV AND estado = @estadoExpirada)
        THROW 56240, 'TEST FAILED T-06: validar una ventana vencida debe marcarla EXPIRADA (expiracion perezosa, persistida).', 1;

    -- cerrado
    UPDATE dbo.TokenMatriculaGrupo SET estado = @estadoCerrada, fechaCierreUtc = SYSUTCDATETIME() WHERE id = @idV;
    BEGIN TRY
        INSERT INTO #val EXEC dbo.usp_validar_token_matricula_publico @tokenHash = @hash, @pin = NULL, @idCorrelacion = @corr;
    END TRY
    BEGIN CATCH SET @errCerrado = ERROR_MESSAGE(); END CATCH

    IF @errInexistente NOT LIKE N'%DBCODE=MQR_001%' OR @errExpirado NOT LIKE N'%DBCODE=MQR_001%' OR @errCerrado NOT LIKE N'%DBCODE=MQR_001%'
        THROW 56241, 'TEST FAILED T-07: los tres casos deben fallar con MQR_001.', 1;
    IF @errInexistente <> @errExpirado OR @errExpirado <> @errCerrado
        THROW 56242, 'TEST FAILED T-07: el mensaje de error debe ser identico en los tres casos (anti-enumeracion).', 1;

    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'MQR_001',
        @mensajeUsuarioResultado = @msgU OUTPUT, @mensajeTecnicoResultado = @msgT OUTPUT;
    -- El THROW lleva el mensaje TECNICO del catalogo (DBCODE=MQR_001|detalle), no el de usuario.
    IF @errInexistente NOT LIKE CONCAT(N'%', @msgT, N'%')
        THROW 56243, 'TEST FAILED T-07: el error debe llevar el mensaje tecnico de catalogo MQR_001.', 1;
    PRINT 'TEST_PASS:T-07';
    PRINT 'TEST_PASS:T-06';

    -- =========================================================================
    -- V-03: la consulta no escribe nada salvo la expiracion perezosa
    -- =========================================================================
    PRINT '-> V-03: validar un token vigente no modifica datos';
    UPDATE dbo.TokenMatriculaGrupo SET estado = @estadoActiva, fechaCierreUtc = NULL,
        fechaExpiracionUtc = DATEADD(MINUTE, 30, SYSUTCDATETIME()) WHERE id = @idV;
    DECLARE @antes NVARCHAR(MAX) = (SELECT CONCAT(estado, '|', totalMatriculas, '|', fechaRotacionUtc, '|', fechaExpiracionUtc)
                                    FROM dbo.TokenMatriculaGrupo WHERE id = @idV);
    DELETE FROM #val;
    INSERT INTO #val EXEC dbo.usp_validar_token_matricula_publico @tokenHash = @hash, @pin = NULL, @idCorrelacion = @corr;
    IF @antes <> (SELECT CONCAT(estado, '|', totalMatriculas, '|', fechaRotacionUtc, '|', fechaExpiracionUtc)
                  FROM dbo.TokenMatriculaGrupo WHERE id = @idV)
        THROW 56250, 'TEST FAILED V-03: validar no debe modificar la ventana.', 1;
    PRINT 'TEST_PASS:V-03';

    -- =========================================================================
    -- V-04: permisos del rol de runtime (sin DML directo sobre la tabla)
    -- =========================================================================
    PRINT '-> V-04: permisos del rol de runtime';
    IF (SELECT COUNT(*) FROM sys.database_permissions p
        INNER JOIN sys.database_principals r ON r.principal_id = p.grantee_principal_id AND r.name = N'rol_asistencias_runtime'
        WHERE p.permission_name = 'EXECUTE' AND p.state_desc = 'GRANT'
          AND p.major_id IN (OBJECT_ID(N'dbo.usp_abrir_ventana_matricula_grupo'), OBJECT_ID(N'dbo.usp_cerrar_ventana_matricula_grupo'),
                             OBJECT_ID(N'dbo.usp_rotar_token_matricula_grupo'), OBJECT_ID(N'dbo.usp_rotar_token_matricula_automatico'),
                             OBJECT_ID(N'dbo.usp_consultar_ventanas_matricula_por_rotar'),
                             OBJECT_ID(N'dbo.usp_validar_token_matricula_publico'), OBJECT_ID(N'dbo.usp_matricular_estudiante_por_token'),
                             OBJECT_ID(N'dbo.usp_registrar_estudiante_por_token_publico'))) <> 8
        THROW 56260, 'TEST FAILED V-04: el rol runtime debe tener EXECUTE sobre los 8 SP publicos de HU176B.', 1;
    IF EXISTS (SELECT 1 FROM sys.database_permissions p
        INNER JOIN sys.database_principals r ON r.principal_id = p.grantee_principal_id AND r.name = N'rol_asistencias_runtime'
        WHERE p.permission_name = 'EXECUTE' AND p.state_desc = 'GRANT'
          AND p.major_id IN (OBJECT_ID(N'dbo.usp_internal_resolver_token_matricula'), OBJECT_ID(N'dbo.usp_internal_rotar_token_matricula'),
                             OBJECT_ID(N'dbo.usp_internal_matricular_por_token')))
        THROW 56262, 'TEST FAILED V-04: el rol runtime no debe ejecutar los usp_internal_* de HU176B.', 1;
    IF EXISTS (SELECT 1 FROM sys.database_permissions p
        INNER JOIN sys.database_principals r ON r.principal_id = p.grantee_principal_id AND r.name = N'rol_asistencias_runtime'
        WHERE p.major_id = OBJECT_ID(N'dbo.TokenMatriculaGrupo') AND p.permission_name IN ('SELECT','INSERT','UPDATE','DELETE') AND p.state_desc = 'GRANT')
        THROW 56261, 'TEST FAILED V-04: el rol runtime no debe tener DML directo sobre dbo.TokenMatriculaGrupo.', 1;
    PRINT 'TEST_PASS:V-04';

    DROP TABLE #val;
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
    THROW 56299, 'TEST FAILED HU176B-G01: test_usp_validar_token_matricula_publico dejo transacciones abiertas.', 1;

PRINT 'TEST_PASS:HU176B-VAL-G01';
PRINT '==================================================';
PRINT 'TEST PASS: test_usp_validar_token_matricula_publico (OK)';
PRINT '==================================================';
PRINT 'TEST_PASS:TEST_USP_VALIDAR_TOKEN_MATRICULA_PUBLICO';
GO
