USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_usp_rotar_token_matricula_grupo (HU176B, D2 rotativo)';
PRINT 'Contrato: GestioAsistenciaBackend/docs/work-items/HU176B-matricula-qr-autonoma/CONTRACT.md (§2.3b, A1)';
PRINT '==================================================';

BEGIN TRANSACTION;
BEGIN TRY
    -- =========================================================================
    -- 0. Existencia de los objetos del contrato (falla en RED si faltan)
    -- =========================================================================
    IF OBJECT_ID(N'dbo.TokenMatriculaGrupo', N'U') IS NULL
        THROW 56300, 'TEST FAILED HU176B-R00: tabla dbo.TokenMatriculaGrupo no existe.', 1;
    IF OBJECT_ID(N'dbo.usp_abrir_ventana_matricula_grupo', N'P') IS NULL
        THROW 56301, 'TEST FAILED HU176B-R00: SP usp_abrir_ventana_matricula_grupo no existe.', 1;
    IF OBJECT_ID(N'dbo.usp_rotar_token_matricula_grupo', N'P') IS NULL
        THROW 56302, 'TEST FAILED HU176B-R00: SP usp_rotar_token_matricula_grupo no existe.', 1;
    IF OBJECT_ID(N'dbo.usp_rotar_token_matricula_automatico', N'P') IS NULL
        THROW 56307, 'TEST FAILED HU176B-R00: SP usp_rotar_token_matricula_automatico no existe (CONTRACT A2).', 1;
    IF OBJECT_ID(N'dbo.usp_consultar_ventanas_matricula_por_rotar', N'P') IS NULL
        THROW 56303, 'TEST FAILED HU176B-R00: SP usp_consultar_ventanas_matricula_por_rotar no existe.', 1;
    IF OBJECT_ID(N'dbo.usp_validar_token_matricula_publico', N'P') IS NULL
        THROW 56304, 'TEST FAILED HU176B-R00: SP usp_validar_token_matricula_publico no existe.', 1;

    DECLARE @rotacion INT   = dbo.ufn_obtener_parametro_int(NULL, 'MATRICULA_QR', 'ROTACION_SEGUNDOS');
    DECLARE @tolerancia INT = dbo.ufn_obtener_parametro_int(NULL, 'MATRICULA_QR', 'TOLERANCIA_SEGUNDOS');
    IF ISNULL(@rotacion, 0) <= 0 OR ISNULL(@tolerancia, 0) <= 0
        THROW 56305, 'TEST FAILED HU176B-M01: parametros MATRICULA_QR/ROTACION_SEGUNDOS y TOLERANCIA_SEGUNDOS ausentes o invalidos.', 1;
    IF dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_ACTIVA') = N''
       OR dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_EXPIRADA') = N''
        THROW 56306, 'TEST FAILED HU176B-M01: parametros MATRICULA_QR/ESTADO_ACTIVA|ESTADO_EXPIRADA ausentes.', 1;

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
    CREATE TABLE #rot (
        idCorrelacion UNIQUEIDENTIFIER NULL,
        mensajeUsuarioResultado NVARCHAR(MAX) NULL,
        mensajeTecnicoResultado NVARCHAR(MAX) NULL,
        estadoResultado BIT NOT NULL,
        idVentana UNIQUEIDENTIFIER NULL,
        idDocenteEmisor UNIQUEIDENTIFIER NULL,
        fechaRotacionUtc DATETIME2(0) NULL,
        fechaExpiracionUtc DATETIME2(0) NULL
    );
    CREATE TABLE #val (
        idGrupo UNIQUEIDENTIFIER NULL,
        nombreAsignatura NVARCHAR(200) NULL,
        nombreGrupo NVARCHAR(200) NULL,
        nombreDocente NVARCHAR(300) NULL,
        fechaExpiracionUtc DATETIME2(0) NULL,
        cupoDisponible INT NULL
    );
    CREATE TABLE #por (idGrupo UNIQUEIDENTIFIER NULL, idDocenteEmisor UNIQUEIDENTIFIER NULL);

    DECLARE @estadoActiva  NVARCHAR(10) = dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_ACTIVA');
    DECLARE @estadoCerrada NVARCHAR(10) = dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_CERRADA');
    DECLARE @estadoExpirada NVARCHAR(10) = dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_EXPIRADA');

    DECLARE @grupo UNIQUEIDENTIFIER, @docenteTitular UNIQUEIDENTIFIER, @userTitular UNIQUEIDENTIFIER, @userOtroDocente UNIQUEIDENTIFIER;
    DECLARE @grupoB UNIQUEIDENTIFIER, @docenteB UNIQUEIDENTIFIER, @userB UNIQUEIDENTIFIER;

    SELECT TOP 1 @grupo = g.id, @docenteTitular = g.docente
    FROM dbo.Grupo g INNER JOIN dbo.uv_grupo vg ON vg.id = g.id
    WHERE vg.grupoEstaHablitado = 1 AND vg.cuposDisponibles > 5
    ORDER BY vg.cuposDisponibles DESC;
    SELECT @userTitular = usuario FROM dbo.Docente WHERE id = @docenteTitular;

    SELECT TOP 1 @grupoB = g.id, @docenteB = g.docente
    FROM dbo.Grupo g INNER JOIN dbo.uv_grupo vg ON vg.id = g.id
    WHERE vg.grupoEstaHablitado = 1 AND vg.cuposDisponibles > 0 AND g.docente <> @docenteTitular AND g.id <> @grupo
    ORDER BY vg.cuposDisponibles DESC;

    -- La semilla canonica solo tiene un docente con grupos: se crea (dentro de la transaccion de la prueba, con rollback)
    -- un segundo grupo identico al primero pero a cargo de otro docente.
    IF @grupoB IS NULL
    BEGIN
        SELECT TOP 1 @docenteB = d.id FROM dbo.Docente d WHERE d.id <> @docenteTitular ORDER BY d.id;
        IF @docenteB IS NOT NULL
        BEGIN
            SET @grupoB = NEWID();
            INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes,
                                   cantidadEstudiantesFinalizaron, cantidadEstudiantesCancelaronVoluntadPropia,
                                   cantidadEstudiantesCancelaronAutomaticamente, docente)
            SELECT @grupoB, g.asignatura, g.periodoAcademico, g.codigo + 900, N'HU176B-B', 20, 0, 0, 0, @docenteB
            FROM dbo.Grupo g WHERE g.id = @grupo;
        END
    END
    SELECT @userB = usuario FROM dbo.Docente WHERE id = @docenteB;
    SET @userOtroDocente = @userB;

    IF @grupo IS NULL OR @userTitular IS NULL OR @grupoB IS NULL OR @userB IS NULL
        THROW 56310, 'TEST FAILED HU176B: fixture de dos grupos con docentes distintos faltante (semilla).', 1;

    UPDATE dbo.TokenMatriculaGrupo SET estado = @estadoCerrada WHERE grupo IN (@grupo, @grupoB) AND estado = @estadoActiva;

    DECLARE @corr UNIQUEIDENTIFIER = NEWID();
    DECLARE @t1 NVARCHAR(100) = CONCAT(N'tok-', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''));
    DECLARE @t2 NVARCHAR(100) = CONCAT(N'tok-', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''));
    DECLARE @t3 NVARCHAR(100) = CONCAT(N'tok-', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''));
    DECLARE @t4 NVARCHAR(100) = CONCAT(N'tok-', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''));
    DECLARE @h1 VARBINARY(32) = HASHBYTES('SHA2_256', @t1), @h2 VARBINARY(32) = HASHBYTES('SHA2_256', @t2);
    DECLARE @h3 VARBINARY(32) = HASHBYTES('SHA2_256', @t3), @h4 VARBINARY(32) = HASHBYTES('SHA2_256', @t4);
    DECLARE @base INT = ABS(CHECKSUM(NEWID())) % 900000;
    DECLARE @p1 NCHAR(6) = RIGHT(CONCAT('000000', CAST(@base + 10 AS VARCHAR(7))), 6);
    DECLARE @p2 NCHAR(6) = RIGHT(CONCAT('000000', CAST(@base + 20 AS VARCHAR(7))), 6);
    DECLARE @p3 NCHAR(6) = RIGHT(CONCAT('000000', CAST(@base + 30 AS VARCHAR(7))), 6);
    DECLARE @p4 NCHAR(6) = RIGHT(CONCAT('000000', CAST(@base + 40 AS VARCHAR(7))), 6);
    DECLARE @idV UNIQUEIDENTIFIER, @capturado NVARCHAR(4000);

    -- Ventana inicial del grupo A con (h1, p1)
    INSERT INTO #r
    EXEC dbo.usp_abrir_ventana_matricula_grupo
        @idGrupo = @grupo, @tokenHash = @h1, @pin = @p1, @idCorrelacion = @corr, @idUsuarioEjecutor = @userTitular;
    SELECT @idV = idVentana FROM #r WHERE estadoResultado = 1;
    IF @idV IS NULL
        THROW 56311, 'TEST FAILED HU176B: no se pudo abrir la ventana de prueba (depende de usp_abrir_ventana_matricula_grupo).', 1;

    -- =========================================================================
    -- T-36 (previo): job sobre una ventana que aun NO debe rotar -> sin cambios
    -- =========================================================================
    PRINT '-> T-36a: el job no rota una ventana que no vencio';
    DELETE FROM #rot;
    INSERT INTO #rot
    EXEC dbo.usp_rotar_token_matricula_automatico
        @idGrupo = @grupo, @tokenHash = @h2, @pin = @p2, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #rot WHERE estadoResultado = 1) <> 1
        THROW 56320, 'TEST FAILED T-36a: el job sobre una ventana no vencida debe responder exito sin cambios.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.TokenMatriculaGrupo WHERE id = @idV AND tokenHash = @h1 AND pin = @p1 AND tokenHashAnterior IS NULL)
        THROW 56321, 'TEST FAILED T-36a: la ventana no vencida no debio cambiar.', 1;
    PRINT 'TEST_PASS:T-36a';

    -- =========================================================================
    -- T-35: rotacion cuando debeRotar = 1 (modo job)
    -- =========================================================================
    PRINT '-> T-35: el job rota la ventana vencida (vigente -> anterior)';
    UPDATE dbo.TokenMatriculaGrupo SET fechaRotacionUtc = DATEADD(SECOND, -(@rotacion + 5), SYSUTCDATETIME()) WHERE id = @idV;

    DELETE FROM #por;
    INSERT INTO #por EXEC dbo.usp_consultar_ventanas_matricula_por_rotar;
    IF NOT EXISTS (SELECT 1 FROM #por WHERE idGrupo = @grupo AND idDocenteEmisor = @docenteTitular)
        THROW 56330, 'TEST FAILED T-35: usp_consultar_ventanas_matricula_por_rotar debe listar la ventana vencida con su docente emisor.', 1;

    DELETE FROM #rot;
    INSERT INTO #rot
    EXEC dbo.usp_rotar_token_matricula_automatico
        @idGrupo = @grupo, @tokenHash = @h2, @pin = @p2, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #rot WHERE estadoResultado = 1 AND idVentana = @idV AND idDocenteEmisor = @docenteTitular) <> 1
        THROW 56331, 'TEST FAILED T-35: la rotacion debio ser exitosa y devolver idVentana e idDocenteEmisor.', 1;
    IF NOT EXISTS (
        SELECT 1 FROM dbo.TokenMatriculaGrupo
        WHERE id = @idV AND estado = @estadoActiva
          AND tokenHash = @h2 AND pin = @p2
          AND tokenHashAnterior = @h1 AND pinAnterior = @p1
          AND fechaRotacionUtc >= DATEADD(SECOND, -3, SYSUTCDATETIME())
    )
        THROW 56332, 'TEST FAILED T-35: vigente debio pasar a anterior, los nuevos regir y fechaRotacionUtc actualizarse.', 1;

    DELETE FROM #por;
    INSERT INTO #por EXEC dbo.usp_consultar_ventanas_matricula_por_rotar;
    IF EXISTS (SELECT 1 FROM #por WHERE idGrupo = @grupo)
        THROW 56333, 'TEST FAILED T-35: tras rotar, la ventana ya no debe aparecer como pendiente de rotar.', 1;
    PRINT 'TEST_PASS:T-35';

    -- =========================================================================
    -- T-36: idempotencia (un segundo job inmediato no cambia nada)
    -- =========================================================================
    PRINT '-> T-36: el segundo job inmediato es idempotente';
    DELETE FROM #rot;
    INSERT INTO #rot
    EXEC dbo.usp_rotar_token_matricula_automatico
        @idGrupo = @grupo, @tokenHash = @h3, @pin = @p3, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #rot WHERE estadoResultado = 1) <> 1
        THROW 56340, 'TEST FAILED T-36: el segundo job debe responder exito sin cambios.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.TokenMatriculaGrupo WHERE id = @idV AND tokenHash = @h2 AND tokenHashAnterior = @h1)
        THROW 56341, 'TEST FAILED T-36: el segundo job no debe mover los tokens (h2 sigue vigente, h1 anterior).', 1;
    PRINT 'TEST_PASS:T-36';

    -- =========================================================================
    -- T-37: tolerancia del token anterior
    -- =========================================================================
    PRINT '-> T-37: el token anterior vale dentro de la tolerancia y no despues';
    DELETE FROM #val;
    INSERT INTO #val EXEC dbo.usp_validar_token_matricula_publico @tokenHash = @h1, @pin = NULL, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #val WHERE idGrupo = @grupo) <> 1
        THROW 56350, 'TEST FAILED T-37: el token anterior debe validar dentro de TOLERANCIA_SEGUNDOS.', 1;

    DELETE FROM #val;
    INSERT INTO #val EXEC dbo.usp_validar_token_matricula_publico @tokenHash = NULL, @pin = @p1, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #val WHERE idGrupo = @grupo) <> 1
        THROW 56351, 'TEST FAILED T-37: el PIN anterior debe validar dentro de TOLERANCIA_SEGUNDOS.', 1;

    UPDATE dbo.TokenMatriculaGrupo SET fechaRotacionUtc = DATEADD(SECOND, -(@tolerancia + 5), SYSUTCDATETIME()) WHERE id = @idV;
    SET @capturado = N'';
    BEGIN TRY
        DELETE FROM #val;
        INSERT INTO #val EXEC dbo.usp_validar_token_matricula_publico @tokenHash = @h1, @pin = NULL, @idCorrelacion = @corr;
    END TRY
    BEGIN CATCH
        SET @capturado = ERROR_MESSAGE();
    END CATCH
    IF @capturado NOT LIKE N'%DBCODE=MQR_001%'
        THROW 56352, 'TEST FAILED T-37: fuera de la tolerancia el token anterior debe recibir MQR_001.', 1;

    -- El token vigente sigue valido
    DELETE FROM #val;
    INSERT INTO #val EXEC dbo.usp_validar_token_matricula_publico @tokenHash = @h2, @pin = NULL, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #val WHERE idGrupo = @grupo) <> 1
        THROW 56353, 'TEST FAILED T-37: el token vigente debe seguir validando.', 1;
    PRINT 'TEST_PASS:T-37';

    -- =========================================================================
    -- T-38: un token de dos rotaciones atras ya no vale
    -- =========================================================================
    PRINT '-> T-38: token de dos rotaciones atras';
    UPDATE dbo.TokenMatriculaGrupo SET fechaRotacionUtc = DATEADD(SECOND, -(@rotacion + 5), SYSUTCDATETIME()) WHERE id = @idV;
    DELETE FROM #rot;
    INSERT INTO #rot
    EXEC dbo.usp_rotar_token_matricula_automatico
        @idGrupo = @grupo, @tokenHash = @h3, @pin = @p3, @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM dbo.TokenMatriculaGrupo WHERE id = @idV AND tokenHash = @h3 AND tokenHashAnterior = @h2)
        THROW 56360, 'TEST FAILED T-38: la segunda rotacion debio dejar h3 vigente y h2 anterior.', 1;

    SET @capturado = N'';
    BEGIN TRY
        DELETE FROM #val;
        INSERT INTO #val EXEC dbo.usp_validar_token_matricula_publico @tokenHash = @h1, @pin = NULL, @idCorrelacion = @corr;
    END TRY
    BEGIN CATCH
        SET @capturado = ERROR_MESSAGE();
    END CATCH
    IF @capturado NOT LIKE N'%DBCODE=MQR_001%'
        THROW 56361, 'TEST FAILED T-38: el token de dos rotaciones atras debe recibir MQR_001 (aun dentro del tiempo).', 1;
    PRINT 'TEST_PASS:T-38';

    -- =========================================================================
    -- T-39: el PIN nuevo no puede repetir el PIN vigente ni el anterior de otra ventana activa
    -- =========================================================================
    PRINT '-> T-39: unicidad del PIN contra pines anteriores de otras ventanas';
    DECLARE @tB NVARCHAR(100) = CONCAT(N'tok-', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''));
    DECLARE @hB VARBINARY(32) = HASHBYTES('SHA2_256', @tB);
    DECLARE @filasAntes INT = (SELECT COUNT(*) FROM dbo.TokenMatriculaGrupo);
    DECLARE @pinAnteriorA NCHAR(6) = (SELECT pinAnterior FROM dbo.TokenMatriculaGrupo WHERE id = @idV);
    IF @pinAnteriorA IS NULL
        THROW 56370, 'TEST FAILED T-39: precondicion: la ventana A debe tener pinAnterior.', 1;

    DELETE FROM #r;
    INSERT INTO #r
    EXEC dbo.usp_abrir_ventana_matricula_grupo
        @idGrupo = @grupoB, @tokenHash = @hB, @pin = @pinAnteriorA, @idCorrelacion = @corr, @idUsuarioEjecutor = @userB;
    IF (SELECT COUNT(*) FROM #r WHERE estadoResultado = 0 AND idVentana IS NULL) <> 1
        THROW 56371, 'TEST FAILED T-39: abrir con un PIN que es pinAnterior de otra ventana activa debe rechazarse (MQR_006).', 1;
    IF @filasAntes <> (SELECT COUNT(*) FROM dbo.TokenMatriculaGrupo)
        THROW 56372, 'TEST FAILED T-39: el rechazo por PIN repetido no debe escribir.', 1;
    PRINT 'TEST_PASS:T-39';

    -- =========================================================================
    -- T-40: rotacion manual del docente (modo con ejecutor)
    -- =========================================================================
    PRINT '-> T-40: rotacion manual por el titular rota siempre; otro docente se rechaza';
    DELETE FROM #rot;
    INSERT INTO #rot
    EXEC dbo.usp_rotar_token_matricula_grupo
        @idGrupo = @grupo, @tokenHash = @h4, @pin = @p4, @idCorrelacion = @corr, @idUsuarioEjecutor = @userTitular;
    IF (SELECT COUNT(*) FROM #rot WHERE estadoResultado = 1 AND idVentana = @idV) <> 1
        THROW 56380, 'TEST FAILED T-40: el titular debio poder rotar manualmente aunque no hubiera vencido.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.TokenMatriculaGrupo WHERE id = @idV AND tokenHash = @h4 AND pin = @p4 AND tokenHashAnterior = @h3)
        THROW 56381, 'TEST FAILED T-40: la rotacion manual debio dejar h4 vigente y h3 anterior.', 1;

    DELETE FROM #rot;
    INSERT INTO #rot
    EXEC dbo.usp_rotar_token_matricula_grupo
        @idGrupo = @grupo, @tokenHash = @h1, @pin = @p1, @idCorrelacion = @corr, @idUsuarioEjecutor = @userOtroDocente;
    IF (SELECT COUNT(*) FROM #rot WHERE estadoResultado = 0) <> 1
        THROW 56382, 'TEST FAILED T-40: un docente no titular no puede rotar.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.TokenMatriculaGrupo WHERE id = @idV AND tokenHash = @h4)
        THROW 56383, 'TEST FAILED T-40: el rechazo no debe alterar la ventana.', 1;

    -- A2: la rotacion manual exige ejecutor
    DELETE FROM #rot;
    INSERT INTO #rot
    EXEC dbo.usp_rotar_token_matricula_grupo
        @idGrupo = @grupo, @tokenHash = @h1, @pin = @p1, @idCorrelacion = @corr, @idUsuarioEjecutor = NULL;
    IF (SELECT COUNT(*) FROM #rot WHERE estadoResultado = 0) <> 1
        THROW 56385, 'TEST FAILED T-40: la rotacion manual sin ejecutor debe rechazarse (GEN_002).', 1;

    -- Sin ventana activa: se rechaza
    UPDATE dbo.TokenMatriculaGrupo SET estado = @estadoCerrada WHERE grupo = @grupoB AND estado = @estadoActiva;
    DELETE FROM #rot;
    INSERT INTO #rot
    EXEC dbo.usp_rotar_token_matricula_grupo
        @idGrupo = @grupoB, @tokenHash = @hB, @pin = @p1, @idCorrelacion = @corr, @idUsuarioEjecutor = @userB;
    IF (SELECT COUNT(*) FROM #rot WHERE estadoResultado = 0) <> 1
        THROW 56384, 'TEST FAILED T-40: rotar un grupo sin ventana activa debe rechazarse (MQR_001).', 1;
    PRINT 'TEST_PASS:T-40';

    -- =========================================================================
    -- T-41: ventana vencida -> EXPIRADA, sin token nuevo
    -- =========================================================================
    PRINT '-> T-41: rotar una ventana vencida la marca EXPIRADA';
    UPDATE dbo.TokenMatriculaGrupo
       SET fechaExpiracionUtc = DATEADD(SECOND, -10, SYSUTCDATETIME()),
           fechaRotacionUtc   = DATEADD(SECOND, -(@rotacion + 5), SYSUTCDATETIME())
     WHERE id = @idV;
    DECLARE @hashAntes VARBINARY(32) = (SELECT tokenHash FROM dbo.TokenMatriculaGrupo WHERE id = @idV);
    DECLARE @tZ NVARCHAR(100) = CONCAT(N'tok-', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''));
    DECLARE @hZ VARBINARY(32) = HASHBYTES('SHA2_256', @tZ);

    DELETE FROM #rot;
    INSERT INTO #rot
    EXEC dbo.usp_rotar_token_matricula_automatico
        @idGrupo = @grupo, @tokenHash = @hZ, @pin = @p1, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #rot WHERE estadoResultado = 0) <> 1
        THROW 56390, 'TEST FAILED T-41: rotar una ventana vencida debe responder estadoResultado = 0 (MQR_001).', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.TokenMatriculaGrupo WHERE id = @idV AND estado = @estadoExpirada AND tokenHash = @hashAntes)
        THROW 56391, 'TEST FAILED T-41: la ventana debe quedar EXPIRADA (persistido) y sin el token nuevo.', 1;
    PRINT 'TEST_PASS:T-41';

    DROP TABLE #por;
    DROP TABLE #val;
    DROP TABLE #rot;
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
    THROW 56399, 'TEST FAILED HU176B-G01: test_usp_rotar_token_matricula_grupo dejo transacciones abiertas.', 1;

PRINT 'TEST_PASS:HU176B-ROT-G01';
PRINT '==================================================';
PRINT 'TEST PASS: test_usp_rotar_token_matricula_grupo (OK)';
PRINT '==================================================';
PRINT 'TEST_PASS:TEST_USP_ROTAR_TOKEN_MATRICULA_GRUPO';
GO
