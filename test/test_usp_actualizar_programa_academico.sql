USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_usp_actualizar_programa_academico (HU077)';
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

    DECLARE @nm NVARCHAR(50);
    DECLARE @c UNIQUEIDENTIFIER, @inexistente UNIQUEIDENTIFIER = NEWID();
    DECLARE @p1 UNIQUEIDENTIFIER = NEWID(), @p2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @n1 NVARCHAR(50) = CONCAT(N'Sistemas QA ', @sufijo), @n2 NVARCHAR(50) = CONCAT(N'Industrial QA ', @sufijo);
    -- P1 (F1, coordinador c1) y P2 (F2, coordinador c2) como fixture directo
    INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado, modalidad, jornada) VALUES (@p1, @f1, @tipoPre, @n1, @c1, 1, @modPre, @jorDiu);
    INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado, modalidad, jornada) VALUES (@p2, @f2, @tipoPre, @n2, @c2, 1, NULL, NULL);

    PRINT '-> T-077-01 editar nombre, tipo, modalidad y jornada';
    SET @c = NEWID();
    SET @nm = CONCAT(N'Sistemas Editado ', @sufijo);
    INSERT INTO #r EXEC dbo.usp_actualizar_programa_academico @idPrograma = @p1, @nombre = @nm, @idTipoPrograma = @tipoPos, @idCoordinador = @c1, @idModalidad = @modVir, @idJornada = @jorNoc, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idCorrelacion = @c)
        THROW 52710, 'TEST FAILED: T-077-01 editar nombre, tipo, modalidad y jornada (esperaba exito).', 1;
    TRUNCATE TABLE #r;

    IF NOT EXISTS (SELECT 1 FROM dbo.uv_programa WHERE id = @p1 AND nombrePrograma = CONCAT(N'Sistemas Editado ', @sufijo) AND idTipoPrograma = @tipoPos AND idModalidad = @modVir AND idJornada = @jorNoc AND idCoordinador = @c1)
        THROW 52711, 'TEST FAILED T-077-01: la vista no refleja los valores nuevos.', 1;
    PRINT 'TEST_PASS:HU077_UPDATE_OK';

    PRINT '-> T-077-05 la unicidad excluye al propio programa';
    SET @c = NEWID();
    SET @nm = CONCAT(N'Sistemas Editado ', @sufijo);
    INSERT INTO #r EXEC dbo.usp_actualizar_programa_academico @idPrograma = @p1, @nombre = @nm, @idTipoPrograma = @tipoPos, @idCoordinador = @c1, @idModalidad = @modVir, @idJornada = @jorNoc, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idCorrelacion = @c)
        THROW 52712, 'TEST FAILED: T-077-05 la unicidad excluye al propio programa (esperaba exito).', 1;
    TRUNCATE TABLE #r;

    PRINT '-> modalidad y jornada NULL dejan el programa sin valor';
    SET @c = NEWID();
    SET @nm = CONCAT(N'Sistemas Editado ', @sufijo);
    INSERT INTO #r EXEC dbo.usp_actualizar_programa_academico @idPrograma = @p1, @nombre = @nm, @idTipoPrograma = @tipoPre, @idCoordinador = @c1, @idModalidad = NULL, @idJornada = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idCorrelacion = @c)
        THROW 52713, 'TEST FAILED: modalidad y jornada NULL dejan el programa sin valor (esperaba exito).', 1;
    TRUNCATE TABLE #r;

    IF NOT EXISTS (SELECT 1 FROM dbo.uv_programa WHERE id = @p1 AND idModalidad IS NULL AND idJornada IS NULL)
        THROW 52714, 'TEST FAILED: NULL no limpio modalidad/jornada.', 1;

    PRINT '-> T-077-02 reasignar coordinador a uno disponible';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_actualizar_programa_academico @idPrograma = @p1, @nombre = @n1, @idTipoPrograma = @tipoPre, @idCoordinador = @c3, @idModalidad = @modPre, @idJornada = @jorDiu, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idCorrelacion = @c)
        THROW 52715, 'TEST FAILED: T-077-02 reasignar coordinador a uno disponible (esperaba exito).', 1;
    TRUNCATE TABLE #r;

    IF NOT EXISTS (SELECT 1 FROM dbo.uv_coordinador WHERE id = @c3 AND idPrograma = @p1)
        THROW 52716, 'TEST FAILED T-077-02: c3 no quedo vinculado a P1.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_coordinador WHERE id = @c1 AND idPrograma IS NULL)
        THROW 52717, 'TEST FAILED T-077-02: c1 no volvio a quedar disponible.', 1;
    PRINT 'TEST_PASS:HU077_REASSIGN_OK';

    PRINT '-> reasignar a un coordinador con programa';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_actualizar_programa_academico @idPrograma = @p1, @nombre = @n1, @idTipoPrograma = @tipoPre, @idCoordinador = @c2, @idModalidad = @modPre, @idJornada = @jorDiu, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=PROG_005|%')
        THROW 52718, 'TEST FAILED: reasignar a un coordinador con programa (esperaba PROG_005).', 1;
    TRUNCATE TABLE #r;

    PRINT '-> T-077-04 modalidad invalida';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_actualizar_programa_academico @idPrograma = @p1, @nombre = @n1, @idTipoPrograma = @tipoPre, @idCoordinador = @c1, @idModalidad = @inexistente, @idJornada = @jorDiu, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=PROG_006|%')
        THROW 52719, 'TEST FAILED: T-077-04 modalidad invalida (esperaba PROG_006).', 1;
    TRUNCATE TABLE #r;

    PRINT '-> jornada invalida';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_actualizar_programa_academico @idPrograma = @p1, @nombre = @n1, @idTipoPrograma = @tipoPre, @idCoordinador = @c1, @idModalidad = @modPre, @idJornada = @inexistente, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=PROG_006|%')
        THROW 52720, 'TEST FAILED: jornada invalida (esperaba PROG_006).', 1;
    TRUNCATE TABLE #r;

    PRINT '-> tipo invalido';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_actualizar_programa_academico @idPrograma = @p1, @nombre = @n1, @idTipoPrograma = @inexistente, @idCoordinador = @c1, @idModalidad = @modPre, @idJornada = @jorDiu, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=PROG_004|%')
        THROW 52721, 'TEST FAILED: tipo invalido (esperaba PROG_004).', 1;
    TRUNCATE TABLE #r;

    DECLARE @p3 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado) VALUES (@p3, @f1, @tipoPre, @n1, @c4, 1);
    PRINT '-> nombre duplicado en la facultad';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_actualizar_programa_academico @idPrograma = @p1, @nombre = @n1, @idTipoPrograma = @tipoPre, @idCoordinador = @c3, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=PROG_003|%')
        THROW 52722, 'TEST FAILED: nombre duplicado en la facultad (esperaba PROG_003).', 1;
    TRUNCATE TABLE #r;

    PRINT '-> T-077-06 programa de otra facultad';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_actualizar_programa_academico @idPrograma = @p2, @nombre = @n1, @idTipoPrograma = @tipoPre, @idCoordinador = @c1, @idModalidad = @modPre, @idJornada = @jorDiu, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=PROG_001|%')
        THROW 52723, 'TEST FAILED: T-077-06 programa de otra facultad (esperaba PROG_001).', 1;
    TRUNCATE TABLE #r;

    IF NOT EXISTS (SELECT 1 FROM dbo.Programa WHERE id = @p2 AND nombre = @n2 AND coordinador = @c2)
        THROW 52724, 'TEST FAILED T-077-06: se modifico el programa de otra facultad.', 1;

    PRINT '-> programa inexistente';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_actualizar_programa_academico @idPrograma = @inexistente, @nombre = @n1, @idTipoPrograma = @tipoPre, @idCoordinador = @c1, @idModalidad = @modPre, @idJornada = @jorDiu, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=PROG_001|%')
        THROW 52725, 'TEST FAILED: programa inexistente (esperaba PROG_001).', 1;
    TRUNCATE TABLE #r;

    PRINT '-> RBAC sin perfil DECANO';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_actualizar_programa_academico @idPrograma = @p1, @nombre = @n1, @idTipoPrograma = @tipoPre, @idCoordinador = @c1, @idModalidad = @modPre, @idJornada = @jorDiu, @idCorrelacion = @c, @idUsuarioEjecutor = @uPlano;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=SEC_001|%')
        THROW 52726, 'TEST FAILED: RBAC sin perfil DECANO (esperaba SEC_001).', 1;
    TRUNCATE TABLE #r;

    PRINT '-> ejecutor NULL';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_actualizar_programa_academico @idPrograma = @p1, @nombre = @n1, @idTipoPrograma = @tipoPre, @idCoordinador = @c1, @idModalidad = @modPre, @idJornada = @jorDiu, @idCorrelacion = @c, @idUsuarioEjecutor = NULL;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=GEN_002|%')
        THROW 52727, 'TEST FAILED: ejecutor NULL (esperaba GEN_002).', 1;
    TRUNCATE TABLE #r;

    PRINT '-> nombre vacio';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_actualizar_programa_academico @idPrograma = @p1, @nombre = N'   ', @idTipoPrograma = @tipoPre, @idCoordinador = @c1, @idModalidad = @modPre, @idJornada = @jorDiu, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=GEN_002|%')
        THROW 52728, 'TEST FAILED: nombre vacio (esperaba GEN_002).', 1;
    TRUNCATE TABLE #r;

    PRINT '-> correlacion nula';
    INSERT INTO #r EXEC dbo.usp_actualizar_programa_academico @idPrograma = @p1, @nombre = @n1, @idTipoPrograma = @tipoPre, @idCoordinador = @c3, @idCorrelacion = NULL, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=CORR_001|%')
        THROW 52729, 'TEST FAILED: no rechazo correlacion NULL.', 1;
    TRUNCATE TABLE #r;

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
    THROW 52699, 'TEST FAILED: test_usp_actualizar_programa_academico dejo transacciones abiertas.', 1;

PRINT '==================================================';
PRINT 'TEST PASS: test_usp_actualizar_programa_academico (HU077 OK)';
PRINT '==================================================';
GO
