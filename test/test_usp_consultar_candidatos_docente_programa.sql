USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- HU091 picker (T-091-18, T-091-19): usp_consultar_candidatos_docente_programa.
PRINT 'TEST START: test_usp_consultar_candidatos_docente_programa';

DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @idFacultad UNIQUEIDENTIFIER = (SELECT TOP 1 idFacultad FROM dbo.uv_programa);
DECLARE @idTipoProg UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoPrograma);
DECLARE @idDecano UNIQUEIDENTIFIER = (SELECT TOP 1 decano FROM dbo.Facultad WHERE id = @idFacultad);
IF @tipoCC IS NULL OR @idFacultad IS NULL OR @idTipoProg IS NULL OR @idDecano IS NULL
    THROW 52300, 'TEST FAILED: faltan fixtures base.', 1;

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @corr UNIQUEIDENTIFIER = NEWID();
    DECLARE @uC1 UNIQUEIDENTIFIER = NEWID(), @uC2 UNIQUEIDENTIFIER = NEWID(), @uC3 UNIQUEIDENTIFIER = NEWID();
    DECLARE @cC1 UNIQUEIDENTIFIER = NEWID(), @cC2 UNIQUEIDENTIFIER = NEWID(), @cC3 UNIQUEIDENTIFIER = NEWID();
    DECLARE @p1 UNIQUEIDENTIFIER = NEWID(), @p2 UNIQUEIDENTIFIER = NEWID(), @p3 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uC1, @tipoCC, 940000001, N'Coord', N'Uno', N'Carlos', N'Qa', N'qa.c1.cand@test.local', 1, 1, N'HashBackend_F1'),
           (@uC2, @tipoCC, 940000002, N'Coord', N'Dos', N'Diana',  N'Qa', N'qa.c2.cand@test.local', 1, 1, N'HashBackend_F2'),
           (@uC3, @tipoCC, 940000003, N'Coord', N'Tres', N'Tomas', N'Qa', N'qa.c3.cand@test.local', 1, 1, N'HashBackend_F3');
    INSERT INTO dbo.Coordinador (id, usuario) VALUES (@cC1, @uC1), (@cC2, @uC2), (@cC3, @uC3);
    DECLARE @inst2 UNIQUEIDENTIFIER = NEWID(), @fac2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Institucion (id, nombre, estado) VALUES (@inst2, N'Institucion QA Cand', 1);
    INSERT INTO dbo.Facultad (id, nombre, institucion, decano, estado) VALUES (@fac2, N'Facultad QA Cand', @inst2, @idDecano, 1);
    INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado)
    VALUES (@p1, @idFacultad, @idTipoProg, N'Programa QA C1', @cC1, 1), (@p2, @idFacultad, @idTipoProg, N'Programa QA C2', @cC2, 1), (@p3, @fac2, @idTipoProg, N'Programa QA C3', @cC3, 1);
    DECLARE @tvCat UNIQUEIDENTIFIER = (SELECT id FROM dbo.TipoVinculacion WHERE codigo = 'CAT');
    IF @tvCat IS NULL THROW 52301, 'TEST FAILED: catalogo TipoVinculacion no existe.', 1;

    -- Docentes "Candidato": d1 solo en P1 (excluido), d2 en P2 (candidato), d3 en P3 otra institucion (excluido), d4 en P2 con usuario inactivo (excluido)
    DECLARE @u1 UNIQUEIDENTIFIER = NEWID(), @u2 UNIQUEIDENTIFIER = NEWID(), @u3 UNIQUEIDENTIFIER = NEWID(), @u4 UNIQUEIDENTIFIER = NEWID();
    DECLARE @d1 UNIQUEIDENTIFIER = NEWID(), @d2 UNIQUEIDENTIFIER = NEWID(), @d3 UNIQUEIDENTIFIER = NEWID(), @d4 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@u1, @tipoCC, 940001001, N'Candidato', N'Uno',    N'Ana', N'Qa', N'qa.k1.cand@test.local', 1, 1, N'HashBackend_F4'),
           (@u2, @tipoCC, 940001002, N'Candidato', N'Dos',    N'Ana', N'Qa', N'qa.k2.cand@test.local', 1, 1, N'HashBackend_F5'),
           (@u3, @tipoCC, 940001003, N'Candidato', N'Tres',   N'Ana', N'Qa', N'qa.k3.cand@test.local', 1, 1, N'HashBackend_F6'),
           (@u4, @tipoCC, 940001004, N'Candidato', N'Cuatro', N'Ana', N'Qa', N'qa.k4.cand@test.local', 1, 0, N'HashBackend_F7');
    INSERT INTO dbo.Docente (id, usuario) VALUES (@d1, @u1), (@d2, @u2), (@d3, @u3), (@d4, @u4);
    INSERT INTO dbo.DocentePrograma (id, docente, programa, tipoVinculacion, estado, fechaVinculacionUtc)
    VALUES (NEWID(), @d1, @p1, @tvCat, 1, SYSUTCDATETIME()), (NEWID(), @d2, @p2, @tvCat, 1, SYSUTCDATETIME()),
           (NEWID(), @d3, @p3, @tvCat, 1, SYSUTCDATETIME()), (NEWID(), @d4, @p2, @tvCat, 1, SYSUTCDATETIME());

    -- D4: el resultset solo expone datos minimos (sin correo): 5 columnas.
    CREATE TABLE #c (idDocente UNIQUEIDENTIFIER, idUsuario UNIQUEIDENTIFIER, codigoTipoIdentificacion NVARCHAR(10), numeroIdentificacion INT, nombreCompleto NVARCHAR(250));

    -- T-091-18: solo misma institucion, excluye ya vinculados a P1 y usuarios inactivos
    INSERT INTO #c EXEC dbo.usp_consultar_candidatos_docente_programa
        @idUsuarioEjecutor = @uC1, @idCorrelacion = @corr, @idPrograma = @p1, @busqueda = N'Candidato';
    IF NOT EXISTS (SELECT 1 FROM #c WHERE idDocente = @d2) THROW 52310, 'T-091-18 FAILED: el docente de P2 debio ser candidato.', 1;
    IF EXISTS (SELECT 1 FROM #c WHERE idDocente IN (@d1, @d3, @d4)) THROW 52311, 'T-091-18 FAILED: aparecieron excluidos (ya vinculado / otra institucion / usuario inactivo).', 1;
    PRINT 'TEST_PASS:T-091-18';

    -- Busqueda por cedula (prefijo)
    TRUNCATE TABLE #c;
    INSERT INTO #c EXEC dbo.usp_consultar_candidatos_docente_programa
        @idUsuarioEjecutor = @uC1, @idCorrelacion = @corr, @idPrograma = @p1, @busqueda = N'940001002';
    IF (SELECT COUNT(*) FROM #c) <> 1 THROW 52313, 'T-091-18 FAILED: busqueda por cedula debio traer 1.', 1;

    -- T-091-19: busqueda corta -> error DOC_007
    DECLARE @fallo BIT = 0;
    BEGIN TRY
        INSERT INTO #c EXEC dbo.usp_consultar_candidatos_docente_programa
            @idUsuarioEjecutor = @uC1, @idCorrelacion = @corr, @idPrograma = @p1, @busqueda = N'ab';
    END TRY
    BEGIN CATCH
        SET @fallo = 1;
    END CATCH
    IF @fallo = 0 THROW 52320, 'T-091-19 FAILED: busqueda de 2 caracteres debio fallar con DOC_007.', 1;
    PRINT 'TEST_PASS:T-091-19';

    -- Ambito: C2 no puede consultar candidatos para P1
    SET @fallo = 0;
    BEGIN TRY
        INSERT INTO #c EXEC dbo.usp_consultar_candidatos_docente_programa
            @idUsuarioEjecutor = @uC2, @idCorrelacion = @corr, @idPrograma = @p1, @busqueda = N'Candidato';
    END TRY
    BEGIN CATCH
        SET @fallo = 1;
    END CATCH
    IF @fallo = 0 THROW 52330, 'TEST FAILED: coordinador ajeno consulto candidatos de P1 (SEC_002).', 1;
    PRINT 'TEST_PASS:CANDIDATOS_AMBITO';

    -- Tope por parametro DOCENTE/MAX_CANDIDATOS_BUSQUEDA
    IF dbo.ufn_obtener_parametro('DOCENTE', 'MAX_CANDIDATOS_BUSQUEDA') IS NULL
        THROW 52340, 'TEST FAILED: falta el parametro DOCENTE/MAX_CANDIDATOS_BUSQUEDA.', 1;
    PRINT 'TEST_PASS:CANDIDATOS_TOPE_PARAMETRO';

    DROP TABLE #c;
    ROLLBACK TRANSACTION;
    PRINT 'TEST_PASS:TEST_USP_CONSULTAR_CANDIDATOS_DOCENTE_PROGRAMA';
END TRY
BEGIN CATCH
    IF OBJECT_ID('tempdb..#c') IS NOT NULL DROP TABLE #c;
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @err NVARCHAR(4000) = ERROR_MESSAGE();
    THROW 52999, @err, 1;
END CATCH
GO
