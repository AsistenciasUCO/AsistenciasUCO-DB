USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_usp_consultar_programas_academicos (HU108)';
PRINT '==================================================';

DECLARE @idInstitucion UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion WHERE estaActivaInstitucion = 1);
DECLARE @tipoId        UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoIdentificacion);
DECLARE @tipoPre       UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_programa WHERE estaActivoTipoPrograma = 1 ORDER BY nombre);
DECLARE @tipoPos       UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_programa WHERE estaActivoTipoPrograma = 1 AND id <> @tipoPre ORDER BY nombre);
DECLARE @modPre        UNIQUEIDENTIFIER = (SELECT id FROM dbo.Modalidad WHERE codigo = N'PRE');
DECLARE @modVir        UNIQUEIDENTIFIER = (SELECT id FROM dbo.Modalidad WHERE codigo = N'VIR');
DECLARE @jorDiu        UNIQUEIDENTIFIER = (SELECT id FROM dbo.Jornada WHERE codigo = N'DIU');
DECLARE @jorNoc        UNIQUEIDENTIFIER = (SELECT id FROM dbo.Jornada WHERE codigo = N'NOC');

IF @idInstitucion IS NULL THROW 52600, 'TEST FAILED: fixture uv_institucion no disponible.', 1;
IF @tipoId IS NULL OR @tipoPre IS NULL OR @tipoPos IS NULL THROW 52601, 'TEST FAILED: fixtures de tipo de identificacion/programa no disponibles.', 1;
IF @modPre IS NULL OR @modVir IS NULL OR @jorDiu IS NULL OR @jorNoc IS NULL THROW 52603, 'TEST FAILED: catalogos Modalidad/Jornada no sembrados.', 1;

BEGIN TRANSACTION;
BEGIN TRY

    CREATE TABLE #r (
        idCorrelacion           UNIQUEIDENTIFIER,
        mensajeUsuarioResultado NVARCHAR(4000),
        mensajeTecnicoResultado NVARCHAR(4000),
        estadoResultado         BIT
    );

    CREATE TABLE #u (n INT IDENTITY(1,1), id UNIQUEIDENTIFIER);
    DECLARE @i INT = 1;
    WHILE @i <= 8
    BEGIN
        DECLARE @uid UNIQUEIDENTIFIER = NEWID();
        INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
        VALUES (@uid, @tipoId, 800000000 + ABS(CHECKSUM(NEWID()) % 99999999), N'QA', N'Programa', CONCAT(N'U', @i), N'X', CONCAT(CONVERT(NVARCHAR(36), @uid), N'@qa.test'), 1, 1, N'x');
        INSERT INTO #u (id) VALUES (@uid);
        SET @i += 1;
    END

    DECLARE @dec1 UNIQUEIDENTIFIER = NEWID(), @dec2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Decano (id, usuario) SELECT @dec1, id FROM #u WHERE n = 1;
    INSERT INTO dbo.Decano (id, usuario) SELECT @dec2, id FROM #u WHERE n = 2;
    DECLARE @uDec1 UNIQUEIDENTIFIER = (SELECT id FROM #u WHERE n = 1);
    DECLARE @uDec2 UNIQUEIDENTIFIER = (SELECT id FROM #u WHERE n = 2);
    DECLARE @uPlano UNIQUEIDENTIFIER = (SELECT id FROM #u WHERE n = 8);

    DECLARE @sufijo NVARCHAR(8) = SUBSTRING(CONVERT(NVARCHAR(36), NEWID()), 1, 8);
    DECLARE @f1 UNIQUEIDENTIFIER = NEWID(), @f2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Facultad (id, nombre, institucion, decano, estado) VALUES (@f1, CONCAT(N'QA Prog Uno ', @sufijo), @idInstitucion, @dec1, 1);
    INSERT INTO dbo.Facultad (id, nombre, institucion, decano, estado) VALUES (@f2, CONCAT(N'QA Prog Dos ', @sufijo), @idInstitucion, @dec2, 1);

    DECLARE @c1 UNIQUEIDENTIFIER = NEWID(), @c2 UNIQUEIDENTIFIER = NEWID(), @c3 UNIQUEIDENTIFIER = NEWID(), @c4 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Coordinador (id, usuario) SELECT @c1, id FROM #u WHERE n = 3;
    INSERT INTO dbo.Coordinador (id, usuario) SELECT @c2, id FROM #u WHERE n = 4;
    INSERT INTO dbo.Coordinador (id, usuario) SELECT @c3, id FROM #u WHERE n = 5;
    INSERT INTO dbo.Coordinador (id, usuario) SELECT @c4, id FROM #u WHERE n = 6;

    DECLARE @c UNIQUEIDENTIFIER, @inexistente UNIQUEIDENTIFIER = NEWID();
    DECLARE @p1 UNIQUEIDENTIFIER = NEWID(), @p2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @n1 NVARCHAR(50) = CONCAT(N'Sistemas QA ', @sufijo), @n2 NVARCHAR(50) = CONCAT(N'Industrial QA ', @sufijo);
    -- P1 (F1, coordinador c1) y P2 (F2, coordinador c2) como fixture directo
    INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado, modalidad, jornada) VALUES (@p1, @f1, @tipoPre, @n1, @c1, 1, @modPre, @jorDiu);
    INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado, modalidad, jornada) VALUES (@p2, @f2, @tipoPre, @n2, @c2, 1, NULL, NULL);

    CREATE TABLE #q (
        id UNIQUEIDENTIFIER, nombrePrograma NVARCHAR(50), idFacultad UNIQUEIDENTIFIER, nombreFacultad NVARCHAR(50),
        idCoordinador UNIQUEIDENTIFIER, nombreCoordinador NVARCHAR(200), estaActivoPrograma BIT,
        idTipoPrograma UNIQUEIDENTIFIER, nombreTipoPrograma NVARCHAR(50),
        idModalidad UNIQUEIDENTIFIER, nombreModalidad NVARCHAR(50), idJornada UNIQUEIDENTIFIER, nombreJornada NVARCHAR(50),
        totalRegistros INT
    );
    -- 10 programas adicionales en F1 (12 en total con P1 y uno mas), coordinadores nuevos
    DECLARE @k INT = 1;
    WHILE @k <= 11
    BEGIN
        DECLARE @uk UNIQUEIDENTIFIER = NEWID(), @ck UNIQUEIDENTIFIER = NEWID();
        INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
        VALUES (@uk, @tipoId, 700000000 + ABS(CHECKSUM(NEWID()) % 99999999), N'QA', N'Prog', CONCAT(N'K', @k), N'X', CONCAT(CONVERT(NVARCHAR(36), @uk), N'@qa.test'), 1, 1, N'x');
        INSERT INTO dbo.Coordinador (id, usuario) VALUES (@ck, @uk);
        INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado)
        VALUES (NEWID(), @f1, IIF(@k % 2 = 0, @tipoPre, @tipoPos), CONCAT(N'Prog ', RIGHT(CONCAT(N'0', @k), 2), N' ', @sufijo), @ck, IIF(@k % 3 = 0, 0, 1));
        SET @k += 1;
    END
    -- F1 tiene ahora P1 + 11 = 12 programas; F2 tiene P2

    PRINT '-> T-108-01: paginacion pagina 2 tamano 5';
    SET @c = NEWID();
    INSERT INTO #q EXEC dbo.usp_consultar_programas_academicos @idUsuarioEjecutor = @uDec1, @idCorrelacion = @c, @numeroPagina = 2, @tamanoPagina = 5;
    IF (SELECT COUNT(*) FROM #q) <> 5 OR NOT EXISTS (SELECT 1 FROM #q WHERE totalRegistros = 12)
        THROW 52910, 'TEST FAILED T-108-01: pagina 2/5 no devolvio 5 filas con totalRegistros=12.', 1;
    IF EXISTS (SELECT 1 FROM #q WHERE idFacultad <> @f1)
        THROW 52911, 'TEST FAILED T-108-02: aparecieron programas de otra facultad.', 1;
    DECLARE @orden INT = (SELECT COUNT(*) FROM #q);
    TRUNCATE TABLE #q;
    INSERT INTO #q EXEC dbo.usp_consultar_programas_academicos @idUsuarioEjecutor = @uDec1, @idCorrelacion = @c, @numeroPagina = 3, @tamanoPagina = 5;
    IF (SELECT COUNT(*) FROM #q) <> 2
        THROW 52912, 'TEST FAILED T-108-01: la pagina 3 debia tener 2 filas.', 1;
    TRUNCATE TABLE #q;
    PRINT 'TEST_PASS:HU108_PAGINATION_OK';

    PRINT '-> T-108-02: ambito fail-closed';
    INSERT INTO #q EXEC dbo.usp_consultar_programas_academicos @idUsuarioEjecutor = @uDec2, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 50;
    IF (SELECT COUNT(*) FROM #q) <> 1 OR NOT EXISTS (SELECT 1 FROM #q WHERE id = @p2)
        THROW 52913, 'TEST FAILED T-108-02: el decano 2 debia ver solo P2.', 1;
    TRUNCATE TABLE #q;
    INSERT INTO #q EXEC dbo.usp_consultar_programas_academicos @idUsuarioEjecutor = @uPlano, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 50;
    IF EXISTS (SELECT 1 FROM #q)
        THROW 52914, 'TEST FAILED T-108-02: un usuario sin ambito vio programas.', 1;
    TRUNCATE TABLE #q;

    PRINT '-> T-108-03: filtros combinados';
    INSERT INTO #q EXEC dbo.usp_consultar_programas_academicos @idUsuarioEjecutor = @uDec1, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 50, @nombre = N'Prog 0';
    IF NOT EXISTS (SELECT 1 FROM #q) OR EXISTS (SELECT 1 FROM #q WHERE nombrePrograma NOT LIKE N'%Prog 0%')
        THROW 52915, 'TEST FAILED T-108-03: filtro por nombre.', 1;
    TRUNCATE TABLE #q;
    INSERT INTO #q EXEC dbo.usp_consultar_programas_academicos @idUsuarioEjecutor = @uDec1, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 50, @estaActivo = 0;
    IF NOT EXISTS (SELECT 1 FROM #q) OR EXISTS (SELECT 1 FROM #q WHERE estaActivoPrograma <> 0)
        THROW 52916, 'TEST FAILED T-108-03 / T-078-05: filtro por estado inactivo.', 1;
    TRUNCATE TABLE #q;
    INSERT INTO #q EXEC dbo.usp_consultar_programas_academicos @idUsuarioEjecutor = @uDec1, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 50, @estaActivo = 1, @idTipoPrograma = @tipoPos;
    IF NOT EXISTS (SELECT 1 FROM #q) OR EXISTS (SELECT 1 FROM #q WHERE estaActivoPrograma <> 1 OR idTipoPrograma <> @tipoPos)
        THROW 52917, 'TEST FAILED T-108-03: filtros combinados estado + tipo.', 1;
    TRUNCATE TABLE #q;
    INSERT INTO #q EXEC dbo.usp_consultar_programas_academicos @idUsuarioEjecutor = @uDec1, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 50, @nombre = @n1;
    IF NOT EXISTS (SELECT 1 FROM #q WHERE id = @p1 AND nombreModalidad IS NOT NULL AND nombreJornada IS NOT NULL AND nombreTipoPrograma IS NOT NULL AND nombreCoordinador IS NOT NULL)
        THROW 52918, 'TEST FAILED: P1 no expone nombres de modalidad, jornada, tipo y coordinador.', 1;
    TRUNCATE TABLE #q;
    PRINT 'TEST_PASS:HU108_FILTERS_OK';

    PRINT '-> T-108-04: paginacion invalida';
    DECLARE @invalida INT = 0, @tmpPag INT;
    DECLARE @casos TABLE (pg INT, tm INT);
    INSERT INTO @casos VALUES (0, 10), (-1, 10), (1, 0), (1, 100000), (NULL, 10), (1, NULL);
    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT pg, tm FROM @casos;
    DECLARE @pg INT, @tm INT;
    OPEN cur; FETCH NEXT FROM cur INTO @pg, @tm;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            INSERT INTO #q EXEC dbo.usp_consultar_programas_academicos @idUsuarioEjecutor = @uDec1, @idCorrelacion = @c, @numeroPagina = @pg, @tamanoPagina = @tm;
        END TRY
        BEGIN CATCH
            IF ERROR_MESSAGE() LIKE N'%DBCODE=PAG_001|%' SET @invalida += 1;
        END CATCH
        FETCH NEXT FROM cur INTO @pg, @tm;
    END
    CLOSE cur; DEALLOCATE cur;
    IF @invalida <> 6
        THROW 52919, 'TEST FAILED T-108-04: no todos los casos de paginacion invalida lanzaron PAG_001.', 1;
    IF @@TRANCOUNT <> 1 THROW 52920, 'TEST FAILED T-108-04: el error de paginacion altero la transaccion del llamador.', 1;

    PRINT '-> T-108-05: el contexto de sesion previo se restaura (exito y error)';
    EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = @uPlano, @read_only = 0;
    INSERT INTO #q EXEC dbo.usp_consultar_programas_academicos @idUsuarioEjecutor = @uDec1, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 5;
    IF CONVERT(NVARCHAR(36), SESSION_CONTEXT(N'idUsuarioEjecutor')) <> CONVERT(NVARCHAR(36), @uPlano)
        THROW 52921, 'TEST FAILED T-108-05: el contexto previo no se restauro tras una consulta exitosa.', 1;
    BEGIN TRY
        INSERT INTO #q EXEC dbo.usp_consultar_programas_academicos @idUsuarioEjecutor = @uDec1, @idCorrelacion = @c, @numeroPagina = 0, @tamanoPagina = 5;
    END TRY
    BEGIN CATCH
    END CATCH
    IF CONVERT(NVARCHAR(36), SESSION_CONTEXT(N'idUsuarioEjecutor')) <> CONVERT(NVARCHAR(36), @uPlano)
        THROW 52922, 'TEST FAILED T-108-05: el contexto previo no se restauro tras un error.', 1;
    EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = NULL, @read_only = 0;
    PRINT 'TEST_PASS:HU108_CONTEXT_RESTORED';
    DROP TABLE #q;

    IF @@TRANCOUNT <> 1 THROW 52639, 'TEST FAILED: el SP altero el nivel de transaccion del llamador.', 1;

    DROP TABLE #r;
    DROP TABLE #u;
    ROLLBACK TRANSACTION;
    PRINT '-> Rollback transaccional ejecutado. Cero residuos.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT CONCAT('ERROR EN TEST: ', ERROR_MESSAGE());
    THROW;
END CATCH;

IF @@TRANCOUNT <> 0
    THROW 52699, 'TEST FAILED: test_usp_consultar_programas_academicos dejo transacciones abiertas.', 1;

PRINT '==================================================';
PRINT 'TEST PASS: test_usp_consultar_programas_academicos (HU108 OK)';
PRINT '==================================================';
GO
