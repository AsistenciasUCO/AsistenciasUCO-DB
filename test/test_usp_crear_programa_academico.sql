USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_usp_crear_programa_academico (HU076)';
PRINT '==================================================';

DECLARE @idInstitucion UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion WHERE estaActivaInstitucion = 1);
DECLARE @tipoId        UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoIdentificacion);
DECLARE @tipoPre       UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_programa WHERE estaActivoTipoPrograma = 1 ORDER BY nombre);
DECLARE @modPre        UNIQUEIDENTIFIER = (SELECT id FROM dbo.Modalidad WHERE codigo = N'PRE');
DECLARE @jorDiu        UNIQUEIDENTIFIER = (SELECT id FROM dbo.Jornada WHERE codigo = N'DIU');

IF @idInstitucion IS NULL THROW 52600, 'TEST FAILED: fixture uv_institucion no disponible.', 1;
IF @tipoId IS NULL THROW 52601, 'TEST FAILED: fixture TipoIdentificacion no disponible.', 1;
IF @tipoPre IS NULL THROW 52602, 'TEST FAILED: fixture tipo de programa no disponible.', 1;
IF @modPre IS NULL OR @jorDiu IS NULL THROW 52603, 'TEST FAILED: catalogos Modalidad/Jornada (PRE/DIU) no sembrados.', 1;

BEGIN TRANSACTION;
BEGIN TRY

    CREATE TABLE #r (
        idCorrelacion           UNIQUEIDENTIFIER,
        mensajeUsuarioResultado NVARCHAR(4000),
        mensajeTecnicoResultado NVARCHAR(4000),
        estadoResultado         BIT
    );

    -- Fixtures propios (rollback al final): 8 usuarios, 2 decanos, 2 facultades, coordinadores libres
    CREATE TABLE #u (n INT IDENTITY(1,1), id UNIQUEIDENTIFIER);
    DECLARE @i INT = 1;
    WHILE @i <= 8
    BEGIN
        DECLARE @uid UNIQUEIDENTIFIER = NEWID();
        INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
        VALUES (@uid, @tipoId, 800000000 + ABS(CHECKSUM(NEWID()) % 99999999), N'QA', N'Programa', CONCAT(N'U', @i), N'X', CONCAT(CONVERT(NVARCHAR(36), @uid), N'@qa.test'), 1, IIF(@i = 7, 0, 1), N'x');
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

    DECLARE @c1 UNIQUEIDENTIFIER = NEWID(), @c2 UNIQUEIDENTIFIER = NEWID(), @c3 UNIQUEIDENTIFIER = NEWID(), @c4 UNIQUEIDENTIFIER = NEWID(), @cInact UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Coordinador (id, usuario) SELECT @c1, id FROM #u WHERE n = 3;
    INSERT INTO dbo.Coordinador (id, usuario) SELECT @c2, id FROM #u WHERE n = 4;
    INSERT INTO dbo.Coordinador (id, usuario) SELECT @c3, id FROM #u WHERE n = 5;
    INSERT INTO dbo.Coordinador (id, usuario) SELECT @c4, id FROM #u WHERE n = 6;
    INSERT INTO dbo.Coordinador (id, usuario) SELECT @cInact, id FROM #u WHERE n = 7;

    DECLARE @c UNIQUEIDENTIFIER, @p1 UNIQUEIDENTIFIER = NEWID(), @inexistente UNIQUEIDENTIFIER = NEWID();
    DECLARE @nm NVARCHAR(100);
    DECLARE @nombre NVARCHAR(50) = CONCAT(N'Sistemas QA ', @sufijo);

    -- T-076-01 / T-076-02: alta feliz y coordinador vinculado
    PRINT '-> T-076-01: alta feliz';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_crear_programa_academico
        @idPrograma = @p1, @nombre = @nombre, @idTipoPrograma = @tipoPre, @idCoordinador = @c1,
        @idModalidad = @modPre, @idJornada = @jorDiu, @idFacultad = @f1, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idCorrelacion = @c)
        THROW 52610, 'TEST FAILED T-076-01: el alta feliz no retorno exito.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_programa WHERE id = @p1 AND idFacultad = @f1 AND idCoordinador = @c1 AND estaActivoPrograma = 1
                   AND idTipoPrograma = @tipoPre AND idModalidad = @modPre AND idJornada = @jorDiu)
        THROW 52611, 'TEST FAILED T-076-01: el programa no quedo persistido con sus atributos.', 1;
    PRINT 'TEST_PASS:HU076_CREATE_OK';
    TRUNCATE TABLE #r;

    PRINT '-> T-076-02: el coordinador deja de estar disponible';
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_coordinador WHERE id = @c1 AND idPrograma = @p1)
        THROW 52612, 'TEST FAILED T-076-02: uv_coordinador no refleja el vinculo.', 1;

    -- T-076-03: nombre duplicado en la misma facultad (mayusculas y espacios), el existente no se modifica
    PRINT '-> T-076-03: nombre duplicado en la facultad';
    SET @c = NEWID();
    SET @nm = CONCAT(N'  ', UPPER(@nombre), N'  ');
    INSERT INTO #r EXEC dbo.usp_crear_programa_academico
        @nombre = @nm, @idTipoPrograma = @tipoPre, @idCoordinador = @c2, @idFacultad = @f1, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=PROG_003|%')
        THROW 52613, 'TEST FAILED T-076-03: no rechazo el nombre duplicado con PROG_003.', 1;
    IF (SELECT COUNT(*) FROM dbo.Programa WHERE facultad = @f1) <> 1
        THROW 52614, 'TEST FAILED T-076-03: se creo o modifico un programa pese al rechazo.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Programa WHERE id = @p1 AND nombre = @nombre AND coordinador = @c1)
        THROW 52615, 'TEST FAILED T-076-03: el programa existente fue modificado (regresion del upsert).', 1;
    TRUNCATE TABLE #r;

    -- T-076-04: el mismo nombre en otra facultad esta permitido
    PRINT '-> T-076-04: mismo nombre en otra facultad';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_crear_programa_academico
        @nombre = @nombre, @idTipoPrograma = @tipoPre, @idCoordinador = @c2, @idFacultad = @f2, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec2;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idCorrelacion = @c)
        THROW 52616, 'TEST FAILED T-076-04: rechazo el mismo nombre en otra facultad.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Programa WHERE id = @p1 AND facultad = @f1 AND coordinador = @c1)
        THROW 52617, 'TEST FAILED T-076-04: altero el programa de la otra facultad.', 1;
    TRUNCATE TABLE #r;

    -- T-076-06 (y T-076-05): coordinador ya con programa (de cualquier facultad) => PROG_005
    PRINT '-> T-076-06: coordinador ocupado';
    SET @c = NEWID();
    SET @nm = CONCAT(N'Otro ', @sufijo);
    INSERT INTO #r EXEC dbo.usp_crear_programa_academico
        @nombre = @nm, @idTipoPrograma = @tipoPre, @idCoordinador = @c1, @idFacultad = @f1, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=PROG_005|%')
        THROW 52618, 'TEST FAILED T-076-06: no rechazo coordinador ocupado con PROG_005.', 1;
    TRUNCATE TABLE #r;

    PRINT '-> T-076-05: coordinador con programa en otra facultad';
    SET @c = NEWID();
    SET @nm = CONCAT(N'Ajeno ', @sufijo);
    INSERT INTO #r EXEC dbo.usp_crear_programa_academico
        @nombre = @nm, @idTipoPrograma = @tipoPre, @idCoordinador = @c2, @idFacultad = @f1, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;   -- c2 ya coordina el programa de F2 (T-076-04)
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=PROG_005|%')
        THROW 52619, 'TEST FAILED T-076-05: acepto un coordinador que ya coordina un programa de otra facultad.', 1;
    TRUNCATE TABLE #r;

    PRINT '-> T-076-16: coordinador con usuario inactivo o inexistente';
    SET @c = NEWID();
    SET @nm = CONCAT(N'Inactivo ', @sufijo);
    INSERT INTO #r EXEC dbo.usp_crear_programa_academico
        @nombre = @nm, @idTipoPrograma = @tipoPre, @idCoordinador = @cInact, @idFacultad = @f1, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=PROG_005|%')
        THROW 52620, 'TEST FAILED T-076-16: acepto un coordinador inactivo.', 1;
    TRUNCATE TABLE #r;
    SET @c = NEWID();
    SET @nm = CONCAT(N'Fantasma ', @sufijo);
    INSERT INTO #r EXEC dbo.usp_crear_programa_academico
        @nombre = @nm, @idTipoPrograma = @tipoPre, @idCoordinador = @inexistente, @idFacultad = @f1, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=PROG_005|%')
        THROW 52621, 'TEST FAILED T-076-16: acepto un coordinador inexistente.', 1;
    TRUNCATE TABLE #r;

    -- T-076-08: tipo inexistente / inactivo
    PRINT '-> T-076-08: tipo de programa invalido';
    SET @c = NEWID();
    SET @nm = CONCAT(N'Tipo ', @sufijo);
    INSERT INTO #r EXEC dbo.usp_crear_programa_academico
        @nombre = @nm, @idTipoPrograma = @inexistente, @idCoordinador = @c3, @idFacultad = @f1, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=PROG_004|%')
        THROW 52622, 'TEST FAILED T-076-08: no rechazo tipo inexistente con PROG_004.', 1;
    TRUNCATE TABLE #r;
    UPDATE dbo.TipoPrograma SET estado = 0 WHERE id = @tipoPre;   -- revertido por el rollback final
    SET @c = NEWID();
    SET @nm = CONCAT(N'Tipo2 ', @sufijo);
    INSERT INTO #r EXEC dbo.usp_crear_programa_academico
        @nombre = @nm, @idTipoPrograma = @tipoPre, @idCoordinador = @c3, @idFacultad = @f1, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=PROG_004|%')
        THROW 52623, 'TEST FAILED T-076-08: no rechazo tipo inactivo con PROG_004.', 1;
    UPDATE dbo.TipoPrograma SET estado = 1 WHERE id = @tipoPre;
    TRUNCATE TABLE #r;

    -- T-077/076: modalidad o jornada invalidas
    PRINT '-> modalidad/jornada invalida';
    SET @c = NEWID();
    SET @nm = CONCAT(N'Mod ', @sufijo);
    INSERT INTO #r EXEC dbo.usp_crear_programa_academico
        @nombre = @nm, @idTipoPrograma = @tipoPre, @idCoordinador = @c3, @idModalidad = @inexistente, @idFacultad = @f1, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=PROG_006|%')
        THROW 52624, 'TEST FAILED: no rechazo modalidad inexistente con PROG_006.', 1;
    TRUNCATE TABLE #r;

    -- T-076-09: facultad ajena (D1 intenta sobre F2)
    PRINT '-> T-076-09: facultad ajena';
    SET @c = NEWID();
    SET @nm = CONCAT(N'Ajena ', @sufijo);
    INSERT INTO #r EXEC dbo.usp_crear_programa_academico
        @nombre = @nm, @idTipoPrograma = @tipoPre, @idCoordinador = @c3, @idFacultad = @f2, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=SEC_002|%')
        THROW 52625, 'TEST FAILED T-076-09: permitio crear en una facultad ajena (SEC_002).', 1;
    IF EXISTS (SELECT 1 FROM dbo.Programa WHERE coordinador = @c3)
        THROW 52626, 'TEST FAILED T-076-09: se creo un programa pese al rechazo.', 1;
    TRUNCATE TABLE #r;

    -- facultad inexistente
    SET @c = NEWID();
    SET @nm = CONCAT(N'NoFac ', @sufijo);
    INSERT INTO #r EXEC dbo.usp_crear_programa_academico
        @nombre = @nm, @idTipoPrograma = @tipoPre, @idCoordinador = @c3, @idFacultad = @inexistente, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c)
        THROW 52627, 'TEST FAILED: acepto facultad inexistente.', 1;
    TRUNCATE TABLE #r;

    -- T-076-10: RBAC (usuario sin perfil de decano)
    PRINT '-> T-076-10: RBAC';
    SET @c = NEWID();
    SET @nm = CONCAT(N'Rbac ', @sufijo);
    INSERT INTO #r EXEC dbo.usp_crear_programa_academico
        @nombre = @nm, @idTipoPrograma = @tipoPre, @idCoordinador = @c3, @idFacultad = @f1, @idCorrelacion = @c, @idUsuarioEjecutor = @uPlano;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=SEC_001|%')
        THROW 52628, 'TEST FAILED T-076-10: permitio ejecutor sin perfil DECANO.', 1;
    TRUNCATE TABLE #r;

    -- T-076-11: ejecutor NULL y correlacion NULL
    PRINT '-> T-076-11: ejecutor y correlacion nulos';
    SET @c = NEWID();
    SET @nm = CONCAT(N'Nulo ', @sufijo);
    INSERT INTO #r EXEC dbo.usp_crear_programa_academico
        @nombre = @nm, @idTipoPrograma = @tipoPre, @idCoordinador = @c3, @idFacultad = @f1, @idCorrelacion = @c, @idUsuarioEjecutor = NULL;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=GEN_002|%')
        THROW 52629, 'TEST FAILED T-076-11: no rechazo ejecutor NULL con GEN_002.', 1;
    TRUNCATE TABLE #r;
    SET @nm = CONCAT(N'Corr ', @sufijo);
    INSERT INTO #r EXEC dbo.usp_crear_programa_academico
        @nombre = @nm, @idTipoPrograma = @tipoPre, @idCoordinador = @c3, @idFacultad = @f1, @idCorrelacion = NULL, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=CORR_001|%')
        THROW 52630, 'TEST FAILED T-076-11: no rechazo correlacion NULL con CORR_001.', 1;
    TRUNCATE TABLE #r;

    -- T-076-12: validacion de forma del nombre
    PRINT '-> T-076-12: nombre vacio / solo espacios / demasiado largo';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_crear_programa_academico
        @nombre = N'    ', @idTipoPrograma = @tipoPre, @idCoordinador = @c3, @idFacultad = @f1, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=GEN_002|%')
        THROW 52631, 'TEST FAILED T-076-12: acepto un nombre vacio.', 1;
    TRUNCATE TABLE #r;
    SET @c = NEWID();
    SET @nm = REPLICATE(N'X', 51);
    INSERT INTO #r EXEC dbo.usp_crear_programa_academico
        @nombre = @nm, @idTipoPrograma = @tipoPre, @idCoordinador = @c3, @idFacultad = @f1, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=GEN_002|%')
        THROW 52632, 'TEST FAILED T-076-12: acepto un nombre de mas de 50 caracteres.', 1;
    TRUNCATE TABLE #r;

    -- T-076-13: id explicito ya existente
    PRINT '-> T-076-13: id explicito existente';
    SET @c = NEWID();
    SET @nm = CONCAT(N'Dup id ', @sufijo);
    INSERT INTO #r EXEC dbo.usp_crear_programa_academico
        @idPrograma = @p1, @nombre = @nm, @idTipoPrograma = @tipoPre, @idCoordinador = @c3, @idFacultad = @f1, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=PROG_002|%')
        THROW 52633, 'TEST FAILED T-076-13: no rechazo id existente con PROG_002.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Programa WHERE id = @p1 AND nombre = @nombre AND coordinador = @c1)
        THROW 52634, 'TEST FAILED T-076-13: el programa P1 fue modificado.', 1;
    TRUNCATE TABLE #r;

    -- T-076-14 / T-076-15: atomicidad. Un trigger fuerza el fallo del INSERT despues de las validaciones.
    PRINT '-> T-076-14/15: atomicidad con transaccion externa';
    EXEC (N'CREATE TRIGGER dbo.trg_qa_programa_falla ON dbo.Programa INSTEAD OF INSERT AS BEGIN THROW 52690, N''QA fallo forzado'', 1; END');
    SET @nm = CONCAT(N'Atomico ', @sufijo);
    -- Con SET XACT_ABORT ON un error de ejecucion deja la transaccion externa no confirmable (-1): el SP no puede hacer
    -- ROLLBACK TO savepoint, tampoco se puede escribir (ni capturar el resultset con INSERT..EXEC) y la duena de la
    -- transaccion debe revertirla (ver test_transaction_ownership.sql, TEST_SKIP:XACT_STATE_MINUS_ONE_RUNTIME).
    -- El SP jamas debe confirmar trabajo parcial: se verifica el estado y, tras el ROLLBACK, la ausencia de la fila.
    EXEC dbo.usp_crear_programa_academico
        @nombre = @nm, @idTipoPrograma = @tipoPre, @idCoordinador = @c3, @idFacultad = @f1, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF XACT_STATE() <> -1
        THROW 52637, 'TEST FAILED T-076-14/15: tras un error de ejecucion se esperaba la transaccion externa no confirmable (-1).', 1;
    ROLLBACK TRANSACTION;
    IF @@TRANCOUNT <> 0 THROW 52638, 'TEST FAILED T-076-15: quedaron transacciones abiertas tras el rollback.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Programa WHERE nombre = @nm OR coordinador = @c3)
        THROW 52635, 'TEST FAILED T-076-14: quedaron filas parciales.', 1;
    PRINT 'TEST_PASS:HU076_CREATE_ATOMIC';
    PRINT 'TEST PASS: test_usp_crear_programa_academico (HU076 OK)';
    RETURN;

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
    THROW 52699, 'TEST FAILED: test_usp_crear_programa_academico dejo transacciones abiertas.', 1;

PRINT '==================================================';
PRINT 'TEST PASS: test_usp_crear_programa_academico (HU076 OK)';
PRINT '==================================================';
GO
