USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- HU062/HU089/HU063 (T-062-01..03, T-063-01, T-089-01): usp_consultar_docentes_programa.
PRINT 'TEST START: test_usp_consultar_docentes_programa';

DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @idFacultad UNIQUEIDENTIFIER = (SELECT TOP 1 idFacultad FROM dbo.uv_programa);
DECLARE @idTipoProg UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoPrograma);
IF @tipoCC IS NULL OR @idFacultad IS NULL OR @idTipoProg IS NULL
    THROW 52200, 'TEST FAILED: faltan fixtures base.', 1;

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @uC1 UNIQUEIDENTIFIER = NEWID(), @uC2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @cC1 UNIQUEIDENTIFIER = NEWID(), @cC2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @p1 UNIQUEIDENTIFIER = NEWID(), @p2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @corr UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uC1, @tipoCC, 930000001, N'Coord', N'Uno', N'Carlos', N'Qa', N'qa.c1.hu062@test.local', 1, 1, N'HashBackend_F1'),
           (@uC2, @tipoCC, 930000002, N'Coord', N'Dos', N'Diana',  N'Qa', N'qa.c2.hu062@test.local', 1, 1, N'HashBackend_F2');
    INSERT INTO dbo.Coordinador (id, usuario) VALUES (@cC1, @uC1), (@cC2, @uC2);
    INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado)
    VALUES (@p1, @idFacultad, @idTipoProg, N'Programa QA 062-1', @cC1, 1), (@p2, @idFacultad, @idTipoProg, N'Programa QA 062-2', @cC2, 1);

    DECLARE @tvCat UNIQUEIDENTIFIER = (SELECT id FROM dbo.TipoVinculacion WHERE codigo = 'CAT');
    DECLARE @tvPla UNIQUEIDENTIFIER = (SELECT id FROM dbo.TipoVinculacion WHERE codigo = 'PLA');
    IF @tvCat IS NULL OR @tvPla IS NULL THROW 52201, 'TEST FAILED: catalogo TipoVinculacion no existe.', 1;

    -- 12 docentes vinculados a P1 (documentos 930001001..012); el 7 con vinculo inactivo; del 1 al 4 son PLA.
    DECLARE @i INT = 1, @u UNIQUEIDENTIFIER, @d UNIQUEIDENTIFIER;
    WHILE @i <= 12
    BEGIN
        SET @u = NEWID(); SET @d = NEWID();
        INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
        VALUES (@u, @tipoCC, 930001000 + @i, N'Rostagno', CONCAT(N'N', RIGHT(CONCAT('0', @i), 2)), N'Maria', N'Qa', CONCAT(N'qa.doc', @i, N'.hu062@test.local'), 1, 1, N'HashBackend_F3');
        INSERT INTO dbo.Docente (id, usuario) VALUES (@d, @u);
        INSERT INTO dbo.DocentePrograma (id, docente, programa, tipoVinculacion, estado, fechaVinculacionUtc)
        VALUES (NEWID(), @d, @p1, IIF(@i <= 4, @tvPla, @tvCat), IIF(@i = 7, 0, 1), SYSUTCDATETIME());
        SET @i += 1;
    END
    -- Un docente solo de P2 (C1 no debe verlo).
    DECLARE @uP2 UNIQUEIDENTIFIER = NEWID(), @dP2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uP2, @tipoCC, 930002001, N'Zuluaga', N'Qa', N'Pedro', N'Qa', N'qa.p2.hu062@test.local', 1, 1, N'HashBackend_F4');
    INSERT INTO dbo.Docente (id, usuario) VALUES (@dP2, @uP2);
    INSERT INTO dbo.DocentePrograma (id, docente, programa, tipoVinculacion, estado, fechaVinculacionUtc) VALUES (NEWID(), @dP2, @p2, @tvCat, 1, SYSUTCDATETIME());

    CREATE TABLE #q (
        idDocentePrograma UNIQUEIDENTIFIER, idDocente UNIQUEIDENTIFIER, idUsuario UNIQUEIDENTIFIER,
        idTipoIdentificacion UNIQUEIDENTIFIER, codigoTipoIdentificacion NVARCHAR(10), numeroIdentificacion INT,
        primerNombre NVARCHAR(50), segundoNombre NVARCHAR(50), primerApellido NVARCHAR(50), segundoApellido NVARCHAR(50),
        nombreCompleto NVARCHAR(250), correo NVARCHAR(100),
        idPrograma UNIQUEIDENTIFIER, nombrePrograma NVARCHAR(50), idFacultad UNIQUEIDENTIFIER, nombreFacultad NVARCHAR(50), idInstitucion UNIQUEIDENTIFIER,
        idTipoVinculacion UNIQUEIDENTIFIER, codigoTipoVinculacion NVARCHAR(3), nombreTipoVinculacion NVARCHAR(50),
        fechaVinculacionUtc DATETIME2(0), estaActivoVinculacion BIT, estaActivoUsuario BIT, estaActivoDocentePrograma BIT,
        totalGruposPrograma INT, totalRegistros INT);

    -- T-062-01: paginacion (12 vinculos, pagina 2 de tamano 5) y orden por nombre
    INSERT INTO #q EXEC dbo.usp_consultar_docentes_programa
        @idUsuarioEjecutor = @uC1, @idCorrelacion = @corr, @idPrograma = @p1, @numeroPagina = 2, @tamanoPagina = 5;
    IF (SELECT COUNT(*) FROM #q) <> 5 THROW 52210, 'T-062-01 FAILED: la pagina 2 debio traer 5 filas.', 1;
    IF EXISTS (SELECT 1 FROM #q WHERE totalRegistros <> 12) THROW 52211, 'T-062-01 FAILED: totalRegistros debio ser 12.', 1;
    IF EXISTS (SELECT 1 FROM #q WHERE idPrograma <> @p1) THROW 52212, 'T-062-01 FAILED: fila de otro programa.', 1;
    IF EXISTS (SELECT 1 FROM #q WHERE idDocente = @dP2) THROW 52213, 'T-062-03 FAILED: C1 ve a un docente solo de P2.', 1;
    PRINT 'TEST_PASS:T-062-01';

    -- T-062-02: docente sin grupos aparece con totalGruposPrograma = 0
    TRUNCATE TABLE #q;
    INSERT INTO #q EXEC dbo.usp_consultar_docentes_programa
        @idUsuarioEjecutor = @uC1, @idCorrelacion = @corr, @idPrograma = @p1, @numeroPagina = 1, @tamanoPagina = 50;
    IF (SELECT COUNT(*) FROM #q) <> 12 THROW 52220, 'T-062-02 FAILED: debio listar 12 docentes sin grupos.', 1;
    IF EXISTS (SELECT 1 FROM #q WHERE totalGruposPrograma <> 0) THROW 52221, 'T-062-02 FAILED: totalGruposPrograma debio ser 0.', 1;
    PRINT 'TEST_PASS:T-062-02';

    -- T-063-01: busqueda por prefijo de cedula y por nombre
    TRUNCATE TABLE #q;
    INSERT INTO #q EXEC dbo.usp_consultar_docentes_programa
        @idUsuarioEjecutor = @uC1, @idCorrelacion = @corr, @idPrograma = @p1, @numeroPagina = 1, @tamanoPagina = 50, @busqueda = N'93000100';
    IF (SELECT COUNT(*) FROM #q) <> 9 THROW 52230, 'T-063-01 FAILED: prefijo 93000100 debio coincidir con 9 documentos (1..9).', 1;
    TRUNCATE TABLE #q;
    INSERT INTO #q EXEC dbo.usp_consultar_docentes_programa
        @idUsuarioEjecutor = @uC1, @idCorrelacion = @corr, @idPrograma = @p1, @numeroPagina = 1, @tamanoPagina = 50, @busqueda = N'rosta';
    IF (SELECT COUNT(*) FROM #q) <> 12 THROW 52231, 'T-063-01 FAILED: busqueda por nombre "rosta" debio traer 12.', 1;
    TRUNCATE TABLE #q;
    INSERT INTO #q EXEC dbo.usp_consultar_docentes_programa
        @idUsuarioEjecutor = @uC1, @idCorrelacion = @corr, @idPrograma = @p1, @numeroPagina = 1, @tamanoPagina = 50, @busqueda = N'zzz-no-existe';
    IF EXISTS (SELECT 1 FROM #q) THROW 52232, 'T-063-01 FAILED: busqueda sin coincidencias debio ser vacia.', 1;
    PRINT 'TEST_PASS:T-063-01';

    -- T-089-01: filtros combinados
    TRUNCATE TABLE #q;
    INSERT INTO #q EXEC dbo.usp_consultar_docentes_programa
        @idUsuarioEjecutor = @uC1, @idCorrelacion = @corr, @idPrograma = @p1, @numeroPagina = 1, @tamanoPagina = 50, @estaActivo = 0;
    IF (SELECT COUNT(*) FROM #q) <> 1 THROW 52240, 'T-089-01 FAILED: estaActivo=0 debio traer solo el vinculo inactivo.', 1;
    TRUNCATE TABLE #q;
    INSERT INTO #q EXEC dbo.usp_consultar_docentes_programa
        @idUsuarioEjecutor = @uC1, @idCorrelacion = @corr, @idPrograma = @p1, @numeroPagina = 1, @tamanoPagina = 50, @estaActivo = 1, @idTipoVinculacion = @tvPla;
    IF (SELECT COUNT(*) FROM #q) <> 4 OR EXISTS (SELECT 1 FROM #q WHERE codigoTipoVinculacion <> 'PLA')
        THROW 52241, 'T-089-01 FAILED: filtro activo+PLA debio traer 4.', 1;
    PRINT 'TEST_PASS:T-089-01';

    -- T-062-03: ambito fail-closed. C1 consultando P2 -> error de titularidad; un docente -> error de RBAC.
    DECLARE @fallo BIT = 0;
    TRUNCATE TABLE #q;
    BEGIN TRY
        INSERT INTO #q EXEC dbo.usp_consultar_docentes_programa
            @idUsuarioEjecutor = @uC1, @idCorrelacion = @corr, @idPrograma = @p2, @numeroPagina = 1, @tamanoPagina = 10;
    END TRY
    BEGIN CATCH
        SET @fallo = 1;
    END CATCH
    IF @fallo = 0 OR EXISTS (SELECT 1 FROM #q) THROW 52250, 'T-062-03 FAILED: C1 no debe consultar P2 (SEC_002).', 1;
    SET @fallo = 0;
    BEGIN TRY
        INSERT INTO #q EXEC dbo.usp_consultar_docentes_programa
            @idUsuarioEjecutor = @uP2, @idCorrelacion = @corr, @idPrograma = @p1, @numeroPagina = 1, @tamanoPagina = 10;
    END TRY
    BEGIN CATCH
        SET @fallo = 1;
    END CATCH
    IF @fallo = 0 OR EXISTS (SELECT 1 FROM #q) THROW 52251, 'T-062-03 FAILED: un docente no debe consultar el directorio (SEC_001).', 1;
    PRINT 'TEST_PASS:T-062-03';

    -- Paginacion normalizada (como usp_consultar_grupos_paginado): pagina < 1 => 1; tamano > 100 => 100. No falla.
    TRUNCATE TABLE #q;
    INSERT INTO #q EXEC dbo.usp_consultar_docentes_programa
        @idUsuarioEjecutor = @uC1, @idCorrelacion = @corr, @idPrograma = @p1, @numeroPagina = 0, @tamanoPagina = 500;
    IF (SELECT COUNT(*) FROM #q) <> 12 THROW 52260, 'TEST FAILED: paginacion fuera de rango debio normalizarse (pagina 1, tamano 100).', 1;
    PRINT 'TEST_PASS:PAGINACION_NORMALIZADA';

    DROP TABLE #q;
    ROLLBACK TRANSACTION;
    PRINT 'TEST_PASS:TEST_USP_CONSULTAR_DOCENTES_PROGRAMA';
END TRY
BEGIN CATCH
    DECLARE @err NVARCHAR(4000) = ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    IF OBJECT_ID('tempdb..#q') IS NOT NULL DROP TABLE #q;
    THROW 52999, @err, 1;
END CATCH
GO
