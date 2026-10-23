USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- HU091 (T-091-01..12, T-DOC-02): usp_vincular_docente_programa.
-- Fixtures propios dentro de una transaccion que se revierte (sin depender de GUIDs del seed).

PRINT 'TEST START: test_usp_vincular_docente_programa';

DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @idFacultad UNIQUEIDENTIFIER = (SELECT TOP 1 idFacultad FROM dbo.uv_programa);
DECLARE @idTipoProg UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoPrograma);
DECLARE @idDecano UNIQUEIDENTIFIER = (SELECT TOP 1 decano FROM dbo.Facultad WHERE id = @idFacultad);
IF @tipoCC IS NULL OR @idFacultad IS NULL OR @idTipoProg IS NULL OR @idDecano IS NULL
    THROW 52000, 'TEST FAILED: faltan fixtures base (tipo CC, facultad, tipo de programa).', 1;

BEGIN TRANSACTION;
BEGIN TRY
    -- ------------------------------------------------------------------
    -- Fixtures: dos programas (P1, P2) de la misma facultad con coordinadores propios,
    -- un programa P3 en otra institucion, catalogo de vinculacion y docentes base.
    -- ------------------------------------------------------------------
    DECLARE @uC1 UNIQUEIDENTIFIER = NEWID(), @uC2 UNIQUEIDENTIFIER = NEWID(), @uC3 UNIQUEIDENTIFIER = NEWID();
    DECLARE @uD1 UNIQUEIDENTIFIER = NEWID(), @uD3 UNIQUEIDENTIFIER = NEWID(), @uSinRol UNIQUEIDENTIFIER = NEWID();
    DECLARE @cC1 UNIQUEIDENTIFIER = NEWID(), @cC2 UNIQUEIDENTIFIER = NEWID(), @cC3 UNIQUEIDENTIFIER = NEWID();
    DECLARE @dD1 UNIQUEIDENTIFIER = NEWID(), @dD3 UNIQUEIDENTIFIER = NEWID();
    DECLARE @p1 UNIQUEIDENTIFIER = NEWID(), @p2 UNIQUEIDENTIFIER = NEWID(), @p3 UNIQUEIDENTIFIER = NEWID();

    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES
      (@uC1,    @tipoCC, 920000001, N'Coord', N'Uno',  N'Carlos', N'Qa', N'qa.coord1.hu091@test.local',  1, 1, N'HashBackend_Fixture1'),
      (@uC2,    @tipoCC, 920000002, N'Coord', N'Dos',  N'Diana',  N'Qa', N'qa.coord2.hu091@test.local',  1, 1, N'HashBackend_Fixture2'),
      (@uC3,    @tipoCC, 920000003, N'Coord', N'Tres', N'Tomas',  N'Qa', N'qa.coord3.hu091@test.local',  1, 1, N'HashBackend_Fixture3'),
      (@uD1,    @tipoCC, 920000011, N'Docente', N'Uno', N'Daniel', N'Qa', N'qa.docente1.hu091@test.local', 1, 1, N'HashBackend_Fixture4'),
      (@uD3,    @tipoCC, 920000013, N'Docente', N'Tres', N'Dora',  N'Qa', N'qa.docente3.hu091@test.local', 1, 1, N'HashBackend_Fixture5'),
      (@uSinRol,@tipoCC, 920000019, N'Sin', N'Rol',    N'Sara',   N'Qa', N'qa.sinrol.hu091@test.local',   1, 1, N'HashBackend_Fixture6');
    INSERT INTO dbo.Coordinador (id, usuario) VALUES (@cC1, @uC1), (@cC2, @uC2), (@cC3, @uC3);
    INSERT INTO dbo.Docente (id, usuario) VALUES (@dD1, @uD1), (@dD3, @uD3);

    DECLARE @inst2 UNIQUEIDENTIFIER = NEWID(), @fac2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Institucion (id, nombre, estado) VALUES (@inst2, N'Institucion QA HU091', 1);
    INSERT INTO dbo.Facultad (id, nombre, institucion, decano, estado) VALUES (@fac2, N'Facultad QA HU091', @inst2, @idDecano, 1);
    INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado)
    VALUES (@p1, @idFacultad, @idTipoProg, N'Programa QA P1', @cC1, 1),
           (@p2, @idFacultad, @idTipoProg, N'Programa QA P2', @cC2, 1),
           (@p3, @fac2,       @idTipoProg, N'Programa QA P3', @cC3, 1);

    DECLARE @tvCat UNIQUEIDENTIFIER = (SELECT id FROM dbo.TipoVinculacion WHERE codigo = 'CAT');
    DECLARE @tvPla UNIQUEIDENTIFIER = (SELECT id FROM dbo.TipoVinculacion WHERE codigo = 'PLA');
    IF @tvCat IS NULL OR @tvPla IS NULL THROW 52001, 'TEST FAILED: catalogo TipoVinculacion (CAT/PLA) no existe.', 1;
    DECLARE @tvInactivo UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.TipoVinculacion (id, codigo, nombre, estado) VALUES (@tvInactivo, N'ZZZ', N'Inactivo QA', 0);

    -- D1 ya vinculado a P2 (otro programa, misma institucion); D3 vinculado a P3 (otra institucion).
    INSERT INTO dbo.DocentePrograma (id, docente, programa, tipoVinculacion, estado, fechaVinculacionUtc)
    VALUES (NEWID(), @dD1, @p2, @tvCat, 1, SYSUTCDATETIME()),
           (NEWID(), @dD3, @p3, @tvCat, 1, SYSUTCDATETIME());

    CREATE TABLE #r (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
    DECLARE @msg NVARCHAR(4000);
    DECLARE @corr UNIQUEIDENTIFIER = NEWID();
    DECLARE @tiposId UNIQUEIDENTIFIER = @tipoCC;

    -- ================= T-091-01: modo nuevo, camino feliz =================
    DECLARE @correoNuevo NVARCHAR(100) = N'qa.nuevo.hu091@test.local';
    INSERT INTO #r EXEC dbo.usp_vincular_docente_programa
        @idTipoIdentificacion = @tipoCC, @numeroIdentificacion = 920000101,
        @primerNombre = N'Nora', @segundoNombre = N'Qa', @primerApellido = N'Nueva', @segundoApellido = N'Docente',
        @correo = @correoNuevo, @password = N'HashBackend_NuevoDocente01',
        @idTipoVinculacion = @tvCat, @idPrograma = @p1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1)
        THROW 52010, 'T-091-01 FAILED: alta nueva no retorno exito.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo = @correoNuevo AND estado = 1 AND password = N'HashBackend_NuevoDocente01')
        THROW 52011, 'T-091-01 FAILED: no se creo el usuario activo con el hash recibido.', 1;
    DECLARE @uNuevo UNIQUEIDENTIFIER = (SELECT id FROM dbo.Usuario WHERE correo = @correoNuevo);
    DECLARE @dNuevo UNIQUEIDENTIFIER = (SELECT id FROM dbo.Docente WHERE usuario = @uNuevo);
    IF @dNuevo IS NULL THROW 52012, 'T-091-01 FAILED: no se creo el rol Docente.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.DocentePrograma WHERE docente = @dNuevo AND programa = @p1 AND tipoVinculacion = @tvCat AND estado = 1)
        THROW 52013, 'T-091-01 FAILED: no se creo la vinculacion activa.', 1;
    PRINT 'TEST_PASS:T-091-01';

    -- ================= T-091-02: docente existente de otro programa =================
    DECLARE @usuariosAntes INT = (SELECT COUNT(*) FROM dbo.Usuario);
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_vincular_docente_programa
        @idDocente = @dD1, @idTipoVinculacion = @tvPla, @idPrograma = @p1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) THROW 52020, 'T-091-02 FAILED: vinculo de docente existente no retorno exito.', 1;
    IF (SELECT COUNT(*) FROM dbo.DocentePrograma WHERE docente = @dD1) <> 2 THROW 52021, 'T-091-02 FAILED: debio quedar exactamente un vinculo nuevo.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.DocentePrograma WHERE docente = @dD1 AND programa = @p1 AND tipoVinculacion = @tvPla AND estado = 1)
        THROW 52022, 'T-091-02 FAILED: vinculo con tipo PLA no encontrado.', 1;
    IF (SELECT COUNT(*) FROM dbo.Usuario) <> @usuariosAntes THROW 52023, 'T-091-02 FAILED: no debio crear usuarios.', 1;
    PRINT 'TEST_PASS:T-091-02';

    -- ================= T-091-03: usuario existente que aun no es docente =================
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_vincular_docente_programa
        @idUsuario = @uSinRol, @idTipoVinculacion = @tvCat, @idPrograma = @p1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) THROW 52030, 'T-091-03 FAILED: modo @idUsuario no retorno exito.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Docente d INNER JOIN dbo.DocentePrograma dp ON dp.docente = d.id WHERE d.usuario = @uSinRol AND dp.programa = @p1)
        THROW 52031, 'T-091-03 FAILED: no se creo Docente + vinculo.', 1;
    PRINT 'TEST_PASS:T-091-03';

    -- ================= T-091-04: vinculo duplicado -> DOC_006 =================
    DECLARE @dpAntes INT = (SELECT COUNT(*) FROM dbo.DocentePrograma);
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_vincular_docente_programa
        @idDocente = @dD1, @idTipoVinculacion = @tvCat, @idPrograma = @p1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'DOC_006';
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) THROW 52040, 'T-091-04 FAILED: duplicado no retorno DOC_006.', 1;
    IF (SELECT COUNT(*) FROM dbo.DocentePrograma) <> @dpAntes THROW 52041, 'T-091-04 FAILED: duplicado modifico datos.', 1;
    PRINT 'TEST_PASS:T-091-04';

    -- ================= T-091-05: persona existente en modo nuevo -> DOC_003 =================
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'DOC_003';
    SET @usuariosAntes = (SELECT COUNT(*) FROM dbo.Usuario);
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_vincular_docente_programa   -- documento repetido
        @idTipoIdentificacion = @tipoCC, @numeroIdentificacion = 920000019,
        @primerNombre = N'Otra', @segundoNombre = N'Qa', @primerApellido = N'Persona', @segundoApellido = N'Qa',
        @correo = N'qa.otro.correo.hu091@test.local', @password = N'HashBackend_Otro01',
        @idTipoVinculacion = @tvCat, @idPrograma = @p1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) THROW 52050, 'T-091-05 FAILED: documento existente no retorno DOC_003.', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_vincular_docente_programa   -- correo repetido
        @idTipoIdentificacion = @tipoCC, @numeroIdentificacion = 920000102,
        @primerNombre = N'Otra', @segundoNombre = N'Qa', @primerApellido = N'Persona', @segundoApellido = N'Qa',
        @correo = N'qa.sinrol.hu091@test.local', @password = N'HashBackend_Otro02',
        @idTipoVinculacion = @tvCat, @idPrograma = @p1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) THROW 52051, 'T-091-05 FAILED: correo existente no retorno DOC_003.', 1;
    IF (SELECT COUNT(*) FROM dbo.Usuario) <> @usuariosAntes THROW 52052, 'T-091-05 FAILED: creo usuarios parciales.', 1;
    PRINT 'TEST_PASS:T-091-05';

    -- ================= T-091-06: modo invalido -> DOC_005 =================
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'DOC_005';
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_vincular_docente_programa    -- ningun modo
        @idTipoVinculacion = @tvCat, @idPrograma = @p1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) THROW 52060, 'T-091-06 FAILED: sin modo no retorno DOC_005.', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_vincular_docente_programa    -- ambos modos
        @idDocente = @dD3, @idUsuario = @uSinRol, @idTipoVinculacion = @tvCat, @idPrograma = @p1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) THROW 52061, 'T-091-06 FAILED: dos modos no retorno DOC_005.', 1;
    PRINT 'TEST_PASS:T-091-06';

    -- ================= T-091-07: tipo de vinculacion invalido -> DOC_004 =================
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'DOC_004';
    SET @usuariosAntes = (SELECT COUNT(*) FROM dbo.Usuario);
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_vincular_docente_programa    -- inexistente
        @idTipoIdentificacion = @tipoCC, @numeroIdentificacion = 920000103,
        @primerNombre = N'Ines', @segundoNombre = N'Qa', @primerApellido = N'Tipo', @segundoApellido = N'Malo',
        @correo = N'qa.tipo.inexistente.hu091@test.local', @password = N'HashBackend_Tipo01',
        @idTipoVinculacion = '15151515-1515-1515-1515-151515151515', @idPrograma = @p1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) THROW 52070, 'T-091-07 FAILED: tipo inexistente no retorno DOC_004.', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_vincular_docente_programa    -- inactivo
        @idDocente = @dD3, @idTipoVinculacion = @tvInactivo, @idPrograma = @p1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) THROW 52071, 'T-091-07 FAILED: tipo inactivo no retorno DOC_004.', 1;
    IF (SELECT COUNT(*) FROM dbo.Usuario) <> @usuariosAntes THROW 52072, 'T-091-07 FAILED: creo usuario parcial.', 1;
    PRINT 'TEST_PASS:T-091-07';

    -- ================= T-091-08: programa ajeno -> SEC_002 =================
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SEC_002';
    SET @dpAntes = (SELECT COUNT(*) FROM dbo.DocentePrograma);
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_vincular_docente_programa    -- C1 intenta vincular en P2 (de C2)
        @idDocente = @dD3, @idTipoVinculacion = @tvCat, @idPrograma = @p2, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) THROW 52080, 'T-091-08 FAILED: programa ajeno no retorno SEC_002.', 1;
    IF (SELECT COUNT(*) FROM dbo.DocentePrograma) <> @dpAntes THROW 52081, 'T-091-08 FAILED: programa ajeno modifico datos.', 1;
    PRINT 'TEST_PASS:T-091-08';

    -- ================= T-091-09: RBAC =================
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SEC_001';
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_vincular_docente_programa    -- ejecutor DOCENTE
        @idDocente = @dD3, @idTipoVinculacion = @tvCat, @idPrograma = @p1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) THROW 52090, 'T-091-09 FAILED: ejecutor DOCENTE no retorno SEC_001.', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_vincular_docente_programa    -- ejecutor NULL
        @idDocente = @dD3, @idTipoVinculacion = @tvCat, @idPrograma = @p1, @idCorrelacion = @corr, @idUsuarioEjecutor = NULL;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0) THROW 52091, 'T-091-09 FAILED: ejecutor NULL debio fallar.', 1;
    PRINT 'TEST_PASS:T-091-09';

    -- ================= T-091-10: docente de otra institucion =================
    SET @dpAntes = (SELECT COUNT(*) FROM dbo.DocentePrograma);
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_vincular_docente_programa
        @idDocente = @dD3, @idTipoVinculacion = @tvCat, @idPrograma = @p1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0) THROW 52100, 'T-091-10 FAILED: docente de otra institucion debio rechazarse.', 1;
    IF (SELECT COUNT(*) FROM dbo.DocentePrograma) <> @dpAntes THROW 52101, 'T-091-10 FAILED: vinculo de otra institucion se creo.', 1;
    PRINT 'TEST_PASS:T-091-10';

    -- ================= T-DOC-02: usp_sincronizar_docente_interno responde DOC_002 =================
    DECLARE @mu NVARCHAR(4000), @mt NVARCHAR(4000), @ok BIT;
    EXEC dbo.usp_sincronizar_docente_interno @idUsuario = @uD1, @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'DOC_002';
    IF @ok <> 0 OR @mu IS NULL OR @msg IS NULL OR @mu <> @msg THROW 52120, 'T-DOC-02 FAILED: usuario ya docente debio retornar DOC_002 (no VAL_006).', 1;
    PRINT 'TEST_PASS:T-DOC-02';

    DROP TABLE #r;
    ROLLBACK TRANSACTION;
    PRINT 'TEST_PASS:TEST_USP_VINCULAR_DOCENTE_PROGRAMA';
END TRY
BEGIN CATCH
    DECLARE @err NVARCHAR(4000) = ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    IF OBJECT_ID('tempdb..#r') IS NOT NULL DROP TABLE #r;
    THROW 52999, @err, 1;
END CATCH
GO

-- ================= T-091-12 (transaccion externa): con XACT_ABORT ON el fallo aborta la transaccion del llamador =================
-- Patron de ownership (docs/arquitectura/transaccion-procedimiento.md): si la transaccion externa queda doomed
-- (XACT_STATE() = -1) el SP no es propietario, no la toca y PROPAGA el error. El llamador hace el rollback total.
DECLARE @corrE UNIQUEIDENTIFIER = NEWID();
DECLARE @uCoordE UNIQUEIDENTIFIER, @pCoordE UNIQUEIDENTIFIER, @tipoCCE UNIQUEIDENTIFIER, @tvE UNIQUEIDENTIFIER;
SELECT TOP 1 @uCoordE = ci.idUsuario, @pCoordE = p.id
FROM dbo.uv_programa p INNER JOIN dbo.uv_coordinador_identidad ci ON ci.id = p.idCoordinador
WHERE p.estaActivoPrograma = 1;
SET @tipoCCE = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
SET @tvE = (SELECT TOP 1 id FROM dbo.TipoVinculacion WHERE estado = 1);
IF @uCoordE IS NULL OR @tvE IS NULL THROW 52140, 'TEST FAILED: faltan fixtures del seed (coordinador con programa / tipo de vinculacion).', 1;
IF @@TRANCOUNT <> 0 THROW 52141, 'TEST FAILED: precondicion @@TRANCOUNT = 0.', 1;

EXEC (N'CREATE TRIGGER dbo.trg_qa_hu091_falla3 ON dbo.DocentePrograma AFTER INSERT AS THROW 52997, ''QA fallo forzado'', 1;');
DECLARE @propagado BIT = 0;
BEGIN TRANSACTION;
BEGIN TRY
    EXEC dbo.usp_vincular_docente_programa
        @idTipoIdentificacion = @tipoCCE, @numeroIdentificacion = 920000106,
        @primerNombre = N'Externa', @segundoNombre = N'Qa', @primerApellido = N'Transaccion', @segundoApellido = N'Qa',
        @correo = N'qa.externa.hu091@test.local', @password = N'HashBackend_Externa01',
        @idTipoVinculacion = @tvE, @idPrograma = @pCoordE, @idCorrelacion = @corrE, @idUsuarioEjecutor = @uCoordE;
END TRY
BEGIN CATCH
    SET @propagado = 1;
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;   -- el llamador (propietario) deshace todo
DROP TRIGGER IF EXISTS dbo.trg_qa_hu091_falla3;
IF @propagado = 0 THROW 52142, 'T-091-12 FAILED: el error con transaccion externa doomed debio propagarse al propietario.', 1;
IF @@TRANCOUNT <> 0 THROW 52143, 'T-091-12 FAILED: quedo una transaccion abierta.', 1;
IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo = N'qa.externa.hu091@test.local')
    THROW 52144, 'T-091-11 FAILED: el rollback del propietario no elimino el usuario creado.', 1;
PRINT 'TEST_PASS:T-091-12_EXTERNAL';
GO

-- ================= T-091-11 (transaccion propia): sin transaccion externa @@TRANCOUNT=0 tras el fallo =================
DECLARE @corr UNIQUEIDENTIFIER = NEWID();
DECLARE @uCoord UNIQUEIDENTIFIER, @pCoord UNIQUEIDENTIFIER, @tipoCC2 UNIQUEIDENTIFIER, @tv UNIQUEIDENTIFIER;
SELECT TOP 1 @uCoord = ci.idUsuario, @pCoord = p.id
FROM dbo.uv_programa p INNER JOIN dbo.uv_coordinador_identidad ci ON ci.id = p.idCoordinador
WHERE p.estaActivoPrograma = 1;
SET @tipoCC2 = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
SET @tv = (SELECT TOP 1 id FROM dbo.TipoVinculacion WHERE estado = 1);
IF @uCoord IS NULL OR @tv IS NULL THROW 52130, 'TEST FAILED: faltan fixtures del seed (coordinador con programa / tipo de vinculacion).', 1;
IF @@TRANCOUNT <> 0 THROW 52131, 'TEST FAILED: precondicion @@TRANCOUNT = 0.', 1;

EXEC (N'CREATE TRIGGER dbo.trg_qa_hu091_falla2 ON dbo.DocentePrograma AFTER INSERT AS THROW 52998, ''QA fallo forzado'', 1;');
BEGIN TRY
    EXEC dbo.usp_vincular_docente_programa
        @idTipoIdentificacion = @tipoCC2, @numeroIdentificacion = 920000105,
        @primerNombre = N'Propia', @segundoNombre = N'Qa', @primerApellido = N'Transaccion', @segundoApellido = N'Qa',
        @correo = N'qa.propia.hu091@test.local', @password = N'HashBackend_Propia01',
        @idTipoVinculacion = @tv, @idPrograma = @pCoord, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
END TRY
BEGIN CATCH
    PRINT 'INFO: fallo forzado propagado.';
END CATCH
DROP TRIGGER IF EXISTS dbo.trg_qa_hu091_falla2;
IF @@TRANCOUNT <> 0
BEGIN
    ROLLBACK TRANSACTION;
    THROW 52132, 'T-091-11 FAILED: el SP dejo una transaccion abierta (@@TRANCOUNT <> 0).', 1;
END
IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo = N'qa.propia.hu091@test.local')
    THROW 52133, 'T-091-11 FAILED: transaccion propia no hizo rollback del usuario.', 1;
PRINT 'TEST_PASS:T-091-11_OWNED';
GO
