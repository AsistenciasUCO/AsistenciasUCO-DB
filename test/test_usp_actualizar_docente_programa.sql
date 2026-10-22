USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- HU092 (T-092-01..05): usp_actualizar_docente_programa. Edita el tipo de vinculacion (solo del vinculo) y los
-- nombres/apellidos de la persona. Correo y documento no se editan.
PRINT 'TEST START: test_usp_actualizar_docente_programa';

DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @idFacultad UNIQUEIDENTIFIER = (SELECT TOP 1 idFacultad FROM dbo.uv_programa);
DECLARE @idTipoProg UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoPrograma);
IF @tipoCC IS NULL OR @idFacultad IS NULL OR @idTipoProg IS NULL
    THROW 52500, 'TEST FAILED: faltan fixtures base.', 1;

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @uC1 UNIQUEIDENTIFIER = NEWID(), @uC2 UNIQUEIDENTIFIER = NEWID(), @uD UNIQUEIDENTIFIER = NEWID();
    DECLARE @cC1 UNIQUEIDENTIFIER = NEWID(), @cC2 UNIQUEIDENTIFIER = NEWID(), @dD UNIQUEIDENTIFIER = NEWID();
    DECLARE @p1 UNIQUEIDENTIFIER = NEWID(), @p2 UNIQUEIDENTIFIER = NEWID(), @corr UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uC1, @tipoCC, 950000001, N'Coord', N'Uno', N'Carlos', N'Qa', N'qa.c1.hu092@test.local', 1, 1, N'HashBackend_F1'),
           (@uC2, @tipoCC, 950000002, N'Coord', N'Dos', N'Diana',  N'Qa', N'qa.c2.hu092@test.local', 1, 1, N'HashBackend_F2'),
           (@uD,  @tipoCC, 950000011, N'Original', N'Apellido', N'Nombre', N'Viejo', N'qa.doc.hu092@test.local', 1, 1, N'HashBackend_F3');
    INSERT INTO dbo.Coordinador (id, usuario) VALUES (@cC1, @uC1), (@cC2, @uC2);
    INSERT INTO dbo.Docente (id, usuario) VALUES (@dD, @uD);
    INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado)
    VALUES (@p1, @idFacultad, @idTipoProg, N'Programa QA 092-1', @cC1, 1), (@p2, @idFacultad, @idTipoProg, N'Programa QA 092-2', @cC2, 1);
    DECLARE @tvCat UNIQUEIDENTIFIER = (SELECT id FROM dbo.TipoVinculacion WHERE codigo = 'CAT');
    DECLARE @tvPla UNIQUEIDENTIFIER = (SELECT id FROM dbo.TipoVinculacion WHERE codigo = 'PLA');
    DECLARE @tvInactivo UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.TipoVinculacion (id, codigo, nombre, estado) VALUES (@tvInactivo, N'ZZY', N'Inactivo QA', 0);
    -- Vinculado a P1 y a P2, ambos CAT.
    INSERT INTO dbo.DocentePrograma (id, docente, programa, tipoVinculacion, estado, fechaVinculacionUtc)
    VALUES (NEWID(), @dD, @p1, @tvCat, 1, SYSUTCDATETIME()), (NEWID(), @dD, @p2, @tvCat, 1, SYSUTCDATETIME());

    CREATE TABLE #r (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
    DECLARE @msg NVARCHAR(4000);

    -- T-092-01: editar tipo de vinculacion solo cambia ESE vinculo
    INSERT INTO #r EXEC dbo.usp_actualizar_docente_programa
        @idDocente = @dD, @idPrograma = @p1, @idTipoVinculacion = @tvPla, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) THROW 52510, 'T-092-01 FAILED: edicion de tipo no retorno exito.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.DocentePrograma WHERE docente = @dD AND programa = @p1 AND tipoVinculacion = @tvPla)
        THROW 52511, 'T-092-01 FAILED: el vinculo de P1 no cambio a PLA.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.DocentePrograma WHERE docente = @dD AND programa = @p2 AND tipoVinculacion = @tvCat)
        THROW 52512, 'T-092-01 FAILED: el vinculo de P2 no debio cambiar.', 1;
    PRINT 'TEST_PASS:T-092-01';

    -- T-092-02: editar nombres actualiza la persona; correo y documento intactos; los no enviados no cambian
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_actualizar_docente_programa
        @idDocente = @dD, @idPrograma = @p1, @primerNombre = N'Nuevo', @primerApellido = N'Cambiado', @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) THROW 52520, 'T-092-02 FAILED: edicion de nombres no retorno exito.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @uD AND primerNombre = N'Nuevo' AND primerApellido = N'Cambiado'
                   AND segundoNombre = N'Viejo' AND segundoApellido = N'Apellido'
                   AND correo = N'qa.doc.hu092@test.local' AND numeroIdentificacion = 950000011)
        THROW 52521, 'T-092-02 FAILED: nombres mal actualizados o correo/documento alterados.', 1;
    PRINT 'TEST_PASS:T-092-02';

    -- T-092-03: sin campos a actualizar -> GEN_002
    SELECT @msg = dbo.ufn_reemplazar_plantilla_mensaje(contenido, N'campo a actualizar', NULL, NULL) FROM dbo.uv_mensaje_usuario WHERE codigo = 'GEN_002';
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_actualizar_docente_programa
        @idDocente = @dD, @idPrograma = @p1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) THROW 52530, 'T-092-03 FAILED: sin campos debio retornar GEN_002.', 1;
    PRINT 'TEST_PASS:T-092-03';

    -- Nombres invalidos -> VAL_003 y sin cambios
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_actualizar_docente_programa
        @idDocente = @dD, @idPrograma = @p1, @primerNombre = N'Bad;Name', @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0) THROW 52531, 'T-092-03 FAILED: nombre invalido debio rechazarse.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @uD AND primerNombre = N'Nuevo') THROW 52532, 'T-092-03 FAILED: nombre invalido modifico datos.', 1;

    -- T-092-04: ambito. Docente sin vinculo con el programa y coordinador ajeno.
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'DOC_008';
    DECLARE @uD2 UNIQUEIDENTIFIER = NEWID(), @dD2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uD2, @tipoCC, 950000012, N'Sin', N'Vinculo', N'Docente', N'Qa', N'qa.doc2.hu092@test.local', 1, 1, N'HashBackend_F4');
    INSERT INTO dbo.Docente (id, usuario) VALUES (@dD2, @uD2);
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_actualizar_docente_programa
        @idDocente = @dD2, @idPrograma = @p1, @primerNombre = N'Otro', @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) THROW 52540, 'T-092-04 FAILED: docente sin vinculo debio retornar DOC_008.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @uD2 AND primerNombre = N'Otro') THROW 52541, 'T-092-04 FAILED: modifico un docente sin vinculo.', 1;
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SEC_002';
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_actualizar_docente_programa    -- C1 intenta editar en P2
        @idDocente = @dD, @idPrograma = @p2, @idTipoVinculacion = @tvPla, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) THROW 52542, 'T-092-04 FAILED: programa ajeno debio retornar SEC_002.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.DocentePrograma WHERE docente = @dD AND programa = @p2 AND tipoVinculacion = @tvCat)
        THROW 52543, 'T-092-04 FAILED: el vinculo de P2 cambio.', 1;
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SEC_001';
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_actualizar_docente_programa    -- ejecutor docente
        @idDocente = @dD, @idPrograma = @p1, @idTipoVinculacion = @tvPla, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) THROW 52544, 'T-092-04 FAILED: ejecutor docente debio retornar SEC_001.', 1;
    PRINT 'TEST_PASS:T-092-04';

    -- T-092-05: tipo de vinculacion invalido -> DOC_004 y sin cambios (ni siquiera los nombres enviados)
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'DOC_004';
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_actualizar_docente_programa
        @idDocente = @dD, @idPrograma = @p1, @idTipoVinculacion = @tvInactivo, @primerNombre = N'NoDebe', @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) THROW 52550, 'T-092-05 FAILED: tipo inactivo debio retornar DOC_004.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @uD AND primerNombre = N'NoDebe') THROW 52551, 'T-092-05 FAILED: aplico nombres pese al tipo invalido.', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_actualizar_docente_programa
        @idDocente = @dD, @idPrograma = @p1, @idTipoVinculacion = '15151515-1515-1515-1515-151515151515', @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) THROW 52552, 'T-092-05 FAILED: tipo inexistente debio retornar DOC_004.', 1;
    PRINT 'TEST_PASS:T-092-05';

    DROP TABLE #r;
    ROLLBACK TRANSACTION;
    PRINT 'TEST_PASS:TEST_USP_ACTUALIZAR_DOCENTE_PROGRAMA';
END TRY
BEGIN CATCH
    DECLARE @err NVARCHAR(4000) = ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    IF OBJECT_ID('tempdb..#r') IS NOT NULL DROP TABLE #r;
    THROW 52999, @err, 1;
END CATCH
GO
