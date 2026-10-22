USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_usp_cambiar_estado_programa_academico (HU078)';
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

    PRINT '-> T-078-01 desactivar sin grupos';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_programa_academico @idPrograma = @p1, @estaActivo = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idCorrelacion = @c)
        THROW 52810, 'TEST FAILED: T-078-01 desactivar sin grupos (esperaba exito).', 1;
    TRUNCATE TABLE #r;

    IF NOT EXISTS (SELECT 1 FROM dbo.uv_programa WHERE id = @p1 AND estaActivoPrograma = 0)
        THROW 52811, 'TEST FAILED T-078-01: el estado no se persistio.', 1;
    PRINT 'TEST_PASS:HU078_DEACTIVATE_OK';
    -- T-078-06 / D12: el coordinador sigue vinculado, inactivo y no disponible
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_coordinador WHERE id = @c1 AND idPrograma = @p1 AND estaActivoCoordinador = 0)
        THROW 52812, 'TEST FAILED T-078-06: el coordinador debe quedar vinculado con estaActivoCoordinador=0.', 1;

    PRINT '-> T-078-03 idempotencia (desactivar otra vez)';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_programa_academico @idPrograma = @p1, @estaActivo = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idCorrelacion = @c)
        THROW 52813, 'TEST FAILED: T-078-03 idempotencia (desactivar otra vez) (esperaba exito).', 1;
    TRUNCATE TABLE #r;

    PRINT '-> reactivar';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_programa_academico @idPrograma = @p1, @estaActivo = 1, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idCorrelacion = @c)
        THROW 52814, 'TEST FAILED: reactivar (esperaba exito).', 1;
    TRUNCATE TABLE #r;

    IF NOT EXISTS (SELECT 1 FROM dbo.uv_programa WHERE id = @p1 AND estaActivoPrograma = 1)
        THROW 52815, 'TEST FAILED: la reactivacion no se persistio.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_coordinador WHERE id = @c1 AND idPrograma = @p1 AND estaActivoCoordinador = 1)
        THROW 52816, 'TEST FAILED T-078-06: al reactivar el programa el coordinador debe volver a estar activo.', 1;
    PRINT 'TEST_PASS:HU078_ACTIVATE_OK';

    -- Fixture de un grupo habilitado (periodo vigente) y otro de un periodo vencido para P1
    DECLARE @plan UNIQUEIDENTIFIER = NEWID(), @spe UNIQUEIDENTIFIER = NEWID(), @asig UNIQUEIDENTIFIER = NEWID();
    DECLARE @per UNIQUEIDENTIFIER = NEWID(), @perVencido UNIQUEIDENTIFIER = NEWID();
    DECLARE @g UNIQUEIDENTIFIER = NEWID(), @gVencido UNIQUEIDENTIFIER = NEWID();
    DECLARE @sem UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Semestre);
    DECLARE @docente UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Docente);
    DECLARE @area UNIQUEIDENTIFIER = (SELECT TOP 1 area FROM dbo.Asignatura);
    DECLARE @comp UNIQUEIDENTIFIER = (SELECT TOP 1 componente FROM dbo.Asignatura);
    IF @sem IS NULL OR @docente IS NULL OR @area IS NULL OR @comp IS NULL THROW 52817, 'TEST FAILED: fixtures de semestre/docente/area/componente no disponibles.', 1;
    DECLARE @hoy DATE = CAST(SYSUTCDATETIME() AS DATE);
    INSERT INTO dbo.PlanEstudio (id, programa, inp, estado) VALUES (@plan, @p1, 900000 + ABS(CHECKSUM(NEWID()) % 99999), 1);
    INSERT INTO dbo.SemestrePlanEstudio (id, planEstudio, semestre) VALUES (@spe, @plan, @sem);
    INSERT INTO dbo.Asignatura (id, codigo, nombre, credito, area, componente, semestrePlanEstudio, estado) VALUES (@asig, CONCAT(N'QA', @sufijo), N'Asignatura QA', 3, @area, @comp, @spe, 1);
    INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio) VALUES (@perVencido, @idInstitucion, N'QA vencido', 910001, DATEADD(DAY, -400, @hoy), DATEADD(DAY, -300, @hoy), YEAR(@hoy) - 1);
    INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio) VALUES (@per, @idInstitucion, N'QA vigente', 910002, DATEADD(DAY, -30, @hoy), DATEADD(DAY, 60, @hoy), YEAR(@hoy));
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron, cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@gVencido, @asig, @perVencido, 910001, N'QA G vencido', 30, 0, 0, 0, @docente);

    PRINT '-> T-078 grupo de un periodo vencido no bloquea la desactivacion';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_programa_academico @idPrograma = @p1, @estaActivo = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idCorrelacion = @c)
        THROW 52818, 'TEST FAILED: T-078 grupo de un periodo vencido no bloquea la desactivacion (esperaba exito).', 1;
    TRUNCATE TABLE #r;

    PRINT '-> reactivar tras el caso anterior';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_programa_academico @idPrograma = @p1, @estaActivo = 1, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idCorrelacion = @c)
        THROW 52819, 'TEST FAILED: reactivar tras el caso anterior (esperaba exito).', 1;
    TRUNCATE TABLE #r;

    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron, cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@g, @asig, @per, 910002, N'QA G vigente', 30, 0, 0, 0, @docente);

    PRINT '-> T-078-02 desactivar con grupos activos en el periodo vigente';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_programa_academico @idPrograma = @p1, @estaActivo = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=PROG_007|%')
        THROW 52820, 'TEST FAILED: T-078-02 desactivar con grupos activos en el periodo vigente (esperaba PROG_007).', 1;
    TRUNCATE TABLE #r;

    IF NOT EXISTS (SELECT 1 FROM dbo.uv_programa WHERE id = @p1 AND estaActivoPrograma = 1)
        THROW 52821, 'TEST FAILED T-078-02: el estado cambio pese al rechazo.', 1;
    DELETE FROM dbo.Grupo WHERE id IN (@g, @gVencido);

    -- T-078-04: reactivar con la facultad inactiva
    UPDATE dbo.Programa SET estado = 0 WHERE id = @p1;
    UPDATE dbo.Facultad SET estado = 0 WHERE id = @f1;

    PRINT '-> T-078-04 reactivar con la facultad inactiva';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_programa_academico @idPrograma = @p1, @estaActivo = 1, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=PROG_008|%')
        THROW 52822, 'TEST FAILED: T-078-04 reactivar con la facultad inactiva (esperaba PROG_008).', 1;
    TRUNCATE TABLE #r;

    UPDATE dbo.Facultad SET estado = 1 WHERE id = @f1;

    PRINT '-> programa de otra facultad';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_programa_academico @idPrograma = @p2, @estaActivo = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=PROG_001|%')
        THROW 52823, 'TEST FAILED: programa de otra facultad (esperaba PROG_001).', 1;
    TRUNCATE TABLE #r;

    PRINT '-> programa inexistente';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_programa_academico @idPrograma = @inexistente, @estaActivo = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=PROG_001|%')
        THROW 52824, 'TEST FAILED: programa inexistente (esperaba PROG_001).', 1;
    TRUNCATE TABLE #r;

    PRINT '-> estado destino NULL';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_programa_academico @idPrograma = @p1, @estaActivo = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=GEN_002|%')
        THROW 52825, 'TEST FAILED: estado destino NULL (esperaba GEN_002).', 1;
    TRUNCATE TABLE #r;

    PRINT '-> RBAC sin perfil DECANO';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_programa_academico @idPrograma = @p1, @estaActivo = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @uPlano;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=SEC_001|%')
        THROW 52826, 'TEST FAILED: RBAC sin perfil DECANO (esperaba SEC_001).', 1;
    TRUNCATE TABLE #r;

    PRINT '-> ejecutor NULL';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_programa_academico @idPrograma = @p1, @estaActivo = 0, @idCorrelacion = @c, @idUsuarioEjecutor = NULL;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=GEN_002|%')
        THROW 52827, 'TEST FAILED: ejecutor NULL (esperaba GEN_002).', 1;
    TRUNCATE TABLE #r;

    PRINT '-> correlacion nula';
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_programa_academico @idPrograma = @p1, @estaActivo = 1, @idCorrelacion = NULL, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=CORR_001|%')
        THROW 52828, 'TEST FAILED: no rechazo correlacion NULL.', 1;
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
    THROW 52699, 'TEST FAILED: test_usp_cambiar_estado_programa_academico dejo transacciones abiertas.', 1;

PRINT '==================================================';
PRINT 'TEST PASS: test_usp_cambiar_estado_programa_academico (HU078 OK)';
PRINT '==================================================';
GO
