USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- HU096/HU097/HU098 (T-096-01..03, T-097-01..02, T-098-01): gestion de periodos academicos. El periodo es unico
-- para toda la institucion: solo lo gestiona el ADMINISTRADOR de esa institucion; DECANO y COORDINADOR lo consultan.
-- usp_crear_periodo_academico, usp_actualizar_periodo_academico, usp_eliminar_periodo_academico.
PRINT 'TEST START: test_usp_periodo_academico_gestion';

DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @idTipoProg UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoPrograma);
DECLARE @periodoConGrupos UNIQUEIDENTIFIER, @idInstitucion UNIQUEIDENTIFIER;
SELECT TOP 1 @periodoConGrupos = pa.id, @idInstitucion = pa.institucion
FROM dbo.PeriodoAcademico pa
INNER JOIN dbo.Institucion i ON i.id = pa.institucion AND i.estado = 1
WHERE EXISTS (SELECT 1 FROM dbo.Grupo g WHERE g.periodoAcademico = pa.id);
DECLARE @idFacultad UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Facultad WHERE institucion = @idInstitucion AND estado = 1);
IF @tipoCC IS NULL OR @idTipoProg IS NULL OR @periodoConGrupos IS NULL OR @idFacultad IS NULL
    THROW 52800, 'TEST FAILED: faltan fixtures base (periodo con grupos en institucion activa, facultad).', 1;

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @uAdm UNIQUEIDENTIFIER = NEWID(), @uAdmInactiva UNIQUEIDENTIFIER = NEWID(), @uC1 UNIQUEIDENTIFIER = NEWID(),
            @uDec UNIQUEIDENTIFIER = NEWID(), @uDoc UNIQUEIDENTIFIER = NEWID();
    DECLARE @cC1 UNIQUEIDENTIFIER = NEWID(), @dDec UNIQUEIDENTIFIER = NEWID(), @dDoc UNIQUEIDENTIFIER = NEWID();
    DECLARE @p1 UNIQUEIDENTIFIER = NEWID(), @fDec UNIQUEIDENTIFIER = NEWID(), @instInactiva UNIQUEIDENTIFIER = NEWID();
    DECLARE @per1 UNIQUEIDENTIFIER = NEWID(), @per2 UNIQUEIDENTIFIER = NEWID(), @per3 UNIQUEIDENTIFIER = NEWID(), @corr UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uAdm,         @tipoCC, 970000960, N'Admin', N'Uno', N'Adela', N'Qa', N'qa.adm.hu096@test.local', 1, 1, N'HashBackend_Q0'),
           (@uAdmInactiva, @tipoCC, 970000965, N'Admin', N'Dos', N'Abel',  N'Qa', N'qa.adm2.hu096@test.local', 1, 1, N'HashBackend_Q5'),
           (@uC1,          @tipoCC, 970000961, N'Coord', N'Uno', N'Camila', N'Qa', N'qa.c1.hu096@test.local', 1, 1, N'HashBackend_Q1'),
           (@uDec,         @tipoCC, 970000963, N'Decano', N'Uno', N'Dora', N'Qa', N'qa.dec.hu096@test.local', 1, 1, N'HashBackend_Q3'),
           (@uDoc,         @tipoCC, 970000964, N'Docente', N'Uno', N'Dario', N'Qa', N'qa.doc.hu096@test.local', 1, 1, N'HashBackend_Q4');
    INSERT INTO dbo.Institucion (id, nombre, estado) VALUES (@instInactiva, N'Institucion QA inactiva HU096', 0);
    INSERT INTO dbo.Administrador (id, usuario, institucion) VALUES (NEWID(), @uAdm, @idInstitucion), (NEWID(), @uAdmInactiva, @instInactiva);
    INSERT INTO dbo.Coordinador (id, usuario) VALUES (@cC1, @uC1);
    INSERT INTO dbo.Decano (id, usuario) VALUES (@dDec, @uDec);
    INSERT INTO dbo.Docente (id, usuario) VALUES (@dDoc, @uDoc);
    INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado)
    VALUES (@p1, @idFacultad, @idTipoProg, N'Programa QA 096', @cC1, 1);
    INSERT INTO dbo.Facultad (id, nombre, institucion, decano, estado) VALUES (@fDec, N'Facultad QA HU096', @idInstitucion, @dDec, 1);

    CREATE TABLE #r (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
    DECLARE @msg NVARCHAR(4000);

    -- T-096-01: el administrador crea un periodo en su institucion; codigo y anio derivados de fechaInicio
    INSERT INTO #r EXEC dbo.usp_crear_periodo_academico
        @idPeriodo = @per1, @nombre = N' QA-2090-1 ', @fechaInicio = '2090-02-01', @fechaFin = '2090-06-30', @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdm;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) THROW 52810, 'T-096-01 FAILED: el administrador no pudo crear el periodo.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.PeriodoAcademico WHERE id = @per1 AND institucion = @idInstitucion AND nombre = N'QA-2090-1' AND codigo = 20901 AND anio = 2090)
        THROW 52811, 'T-096-01 FAILED: periodo creado con datos inesperados.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_periodo_academico WHERE id = @per1) THROW 52812, 'T-096-01 FAILED: el periodo no es visible en uv_periodo_academico.', 1;
    PRINT 'TEST_PASS:T-096-01';

    -- T-096-02: segundo semestre => codigo terminado en 2
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_crear_periodo_academico
        @idPeriodo = @per2, @nombre = N'QA-2090-2', @fechaInicio = '2090-08-01', @fechaFin = '2090-12-15', @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdm;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) THROW 52820, 'T-096-02 FAILED: el administrador no pudo crear el segundo periodo.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.PeriodoAcademico WHERE id = @per2 AND codigo = 20902 AND anio = 2090) THROW 52821, 'T-096-02 FAILED: codigo del segundo semestre inesperado.', 1;
    PRINT 'TEST_PASS:T-096-02';

    -- T-096-03: rechazos (id nulo, duplicado, fechas, COORDINADOR, DECANO, DOCENTE, admin de institucion inactiva, ejecutor nulo)
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_crear_periodo_academico
        @idPeriodo = NULL, @nombre = N'QA-2091-1', @fechaInicio = '2091-02-01', @fechaFin = '2091-06-30', @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdm;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0) THROW 52830, 'T-096-03 FAILED: id de periodo nulo debio rechazarse.', 1;
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'PER_003';
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_crear_periodo_academico
        @idPeriodo = @per3, @nombre = N'qa-2090-1', @fechaInicio = '2091-02-01', @fechaFin = '2091-06-30', @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdm;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) THROW 52831, 'T-096-03 FAILED: nombre duplicado debio retornar PER_003.', 1;
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'PER_002';
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_crear_periodo_academico
        @idPeriodo = @per3, @nombre = N'QA-2091-1', @fechaInicio = '2091-06-30', @fechaFin = '2091-02-01', @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdm;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) THROW 52832, 'T-096-03 FAILED: fechas invertidas debio retornar PER_002.', 1;
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SEC_001';
    DECLARE @sinPermiso TABLE (idUsuario UNIQUEIDENTIFIER);
    INSERT INTO @sinPermiso VALUES (@uC1), (@uDec), (@uDoc);
    DECLARE @uSinPermiso UNIQUEIDENTIFIER;
    DECLARE sinPermiso CURSOR LOCAL FAST_FORWARD FOR SELECT idUsuario FROM @sinPermiso;
    OPEN sinPermiso;
    FETCH NEXT FROM sinPermiso INTO @uSinPermiso;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        TRUNCATE TABLE #r;
        INSERT INTO #r EXEC dbo.usp_crear_periodo_academico
            @idPeriodo = @per3, @nombre = N'QA-2091-1', @fechaInicio = '2091-02-01', @fechaFin = '2091-06-30', @idCorrelacion = @corr, @idUsuarioEjecutor = @uSinPermiso;
        IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg)
            THROW 52833, 'T-096-03 FAILED: COORDINADOR, DECANO y DOCENTE no deben crear periodos (SEC_001).', 1;
        FETCH NEXT FROM sinPermiso INTO @uSinPermiso;
    END
    CLOSE sinPermiso;
    DEALLOCATE sinPermiso;
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'PER_005';
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_crear_periodo_academico
        @idPeriodo = @per3, @nombre = N'QA-2091-1', @fechaInicio = '2091-02-01', @fechaFin = '2091-06-30', @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmInactiva;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) THROW 52835, 'T-096-03 FAILED: admin de institucion inactiva debio retornar PER_005.', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_crear_periodo_academico
        @idPeriodo = @per3, @nombre = N'QA-2091-1', @fechaInicio = '2091-02-01', @fechaFin = '2091-06-30', @idCorrelacion = @corr, @idUsuarioEjecutor = NULL;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0) THROW 52836, 'T-096-03 FAILED: ejecutor nulo debio rechazarse.', 1;
    IF EXISTS (SELECT 1 FROM dbo.PeriodoAcademico WHERE id = @per3) THROW 52837, 'T-096-03 FAILED: un rechazo creo el periodo.', 1;
    PRINT 'TEST_PASS:T-096-03';

    -- T-097-01: el administrador modifica; codigo y anio se recalculan; conservar el nombre esta permitido
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_actualizar_periodo_academico
        @idPeriodo = @per1, @nombre = N'QA-2092-2', @fechaInicio = '2092-07-15', @fechaFin = '2092-11-30', @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdm;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) THROW 52840, 'T-097-01 FAILED: el administrador no pudo modificar.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.PeriodoAcademico WHERE id = @per1 AND nombre = N'QA-2092-2' AND codigo = 20922 AND anio = 2092 AND fechaInicio = '2092-07-15')
        THROW 52841, 'T-097-01 FAILED: datos modificados inesperados.', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_actualizar_periodo_academico
        @idPeriodo = @per1, @nombre = N'QA-2092-2', @fechaInicio = '2092-07-15', @fechaFin = '2092-12-10', @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdm;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) THROW 52842, 'T-097-01 FAILED: conservar el mismo nombre debe permitirse.', 1;
    PRINT 'TEST_PASS:T-097-01';

    -- T-097-02: rechazos al modificar
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'PER_001';
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_actualizar_periodo_academico
        @idPeriodo = @per3, @nombre = N'QA-X', @fechaInicio = '2093-01-01', @fechaFin = '2093-05-01', @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdm;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) THROW 52850, 'T-097-02 FAILED: periodo inexistente debio retornar PER_001.', 1;
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'PER_003';
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_actualizar_periodo_academico
        @idPeriodo = @per1, @nombre = N'qa-2090-2', @fechaInicio = '2093-01-01', @fechaFin = '2093-05-01', @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdm;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) THROW 52851, 'T-097-02 FAILED: nombre de otro periodo debio retornar PER_003.', 1;
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'PER_002';
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_actualizar_periodo_academico
        @idPeriodo = @per1, @nombre = N'QA-2092-2', @fechaInicio = '2093-05-01', @fechaFin = '2093-05-01', @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdm;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) THROW 52852, 'T-097-02 FAILED: fechas iguales debio retornar PER_002.', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_actualizar_periodo_academico
        @idPeriodo = @per1, @nombre = N'QA-COORD', @fechaInicio = '2093-01-01', @fechaFin = '2093-05-01', @idCorrelacion = @corr, @idUsuarioEjecutor = @uC1;
    IF EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) THROW 52853, 'T-097-02 FAILED: el COORDINADOR no debe modificar periodos.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.PeriodoAcademico WHERE id = @per1 AND nombre = N'QA-2092-2') THROW 52854, 'T-097-02 FAILED: un rechazo modifico el periodo.', 1;
    PRINT 'TEST_PASS:T-097-02';

    -- T-098-01: eliminar solo sin grupos; inexistente PER_001; DECANO rechazado
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'PER_004';
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_eliminar_periodo_academico @idPeriodo = @periodoConGrupos, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdm;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) THROW 52860, 'T-098-01 FAILED: periodo con grupos debio retornar PER_004.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.PeriodoAcademico WHERE id = @periodoConGrupos) THROW 52861, 'T-098-01 FAILED: se elimino un periodo con grupos.', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_eliminar_periodo_academico @idPeriodo = @per2, @idCorrelacion = @corr, @idUsuarioEjecutor = @uDec;
    IF EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) THROW 52862, 'T-098-01 FAILED: el DECANO no debe eliminar periodos.', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_eliminar_periodo_academico @idPeriodo = @per2, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdm;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) THROW 52863, 'T-098-01 FAILED: el administrador no pudo eliminar un periodo sin grupos.', 1;
    IF EXISTS (SELECT 1 FROM dbo.PeriodoAcademico WHERE id = @per2) THROW 52864, 'T-098-01 FAILED: el periodo sigue existiendo.', 1;
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'PER_001';
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_eliminar_periodo_academico @idPeriodo = @per2, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdm;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg) THROW 52865, 'T-098-01 FAILED: eliminar dos veces debio retornar PER_001.', 1;
    PRINT 'TEST_PASS:T-098-01';

    DROP TABLE #r;
    ROLLBACK TRANSACTION;
    PRINT 'TEST_PASS:TEST_USP_PERIODO_ACADEMICO_GESTION';
END TRY
BEGIN CATCH
    DECLARE @err NVARCHAR(4000) = ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    IF OBJECT_ID('tempdb..#r') IS NOT NULL DROP TABLE #r;
    THROW 52999, @err, 1;
END CATCH
GO
