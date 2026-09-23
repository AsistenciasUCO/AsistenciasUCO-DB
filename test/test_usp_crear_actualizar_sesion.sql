USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT 'TEST START: test_usp_crear_actualizar_sesion';

DECLARE @idGrupoValido UNIQUEIDENTIFIER;
DECLARE @idPeriodoValido UNIQUEIDENTIFIER;
DECLARE @idDocenteTitular UNIQUEIDENTIFIER;
DECLARE @idUsuarioDocenteTitular UNIQUEIDENTIFIER;

SELECT TOP 1
    @idGrupoValido = id,
    @idPeriodoValido = idPeriodoAcademico,
    @idDocenteTitular = idDocente
FROM dbo.uv_grupo
WHERE grupoEstaHablitado = 1
ORDER BY cuposDisponibles DESC;
SELECT TOP 1 @idUsuarioDocenteTitular = idUsuario
FROM dbo.uv_docente_identidad
WHERE id = @idDocenteTitular;

IF @idGrupoValido IS NULL THROW 51300, 'TEST FAILED: no existe fixture uv_grupo habilitado.', 1;
IF @idDocenteTitular IS NULL THROW 51301, 'TEST FAILED: grupo fixture no expone docente titular.', 1;
IF @idUsuarioDocenteTitular IS NULL THROW 51316, 'TEST FAILED: grupo fixture no expone usuario docente titular.', 1;

BEGIN TRANSACTION;
BEGIN TRY
    CREATE TABLE #sesionResultado (
        idCorrelacion UNIQUEIDENTIFIER,
        mensajeUsuarioResultado NVARCHAR(4000),
        mensajeTecnicoResultado NVARCHAR(4000),
        estadoResultado BIT
    );
    DECLARE @corrCrear UNIQUEIDENTIFIER = NEWID();
    DECLARE @corrIntrusa UNIQUEIDENTIFIER = NEWID();
    DECLARE @corrActualizar UNIQUEIDENTIFIER = NEWID();
    DECLARE @corrRenombrar UNIQUEIDENTIFIER = NEWID();
    DECLARE @inicioSesion DATETIME2 = DATEADD(HOUR, 1, SYSUTCDATETIME());
    DECLARE @finSesion DATETIME2 = DATEADD(HOUR, 2, SYSUTCDATETIME());

    UPDATE dbo.PeriodoAcademico
    SET fechaInicio = DATEADD(MONTH, -1, GETDATE()), fechaFin = DATEADD(MONTH, 3, GETDATE())
    WHERE id = @idPeriodoValido;

    INSERT INTO #sesionResultado
    EXEC dbo.usp_crear_sesion
        @idGrupo = @idGrupoValido,
        @nombre = N'Sesion Suite QA',
        @fechaHoraInicio = @inicioSesion,
        @fechaHoraFin = @finSesion,
        @idCorrelacion = @corrCrear,
        @idUsuarioEjecutor = @idUsuarioDocenteTitular;

    IF NOT EXISTS (SELECT 1 FROM #sesionResultado WHERE estadoResultado = 1)
        THROW 51302, 'TEST FAILED: usp_crear_sesion no retorno SUCCESS.', 1;

    DECLARE @idSesionCreada UNIQUEIDENTIFIER = (
        SELECT TOP 1 id FROM dbo.uv_sesion WHERE idGrupo = @idGrupoValido AND nombre = N'Sesion Suite QA' ORDER BY numero DESC
    );

    IF @idSesionCreada IS NULL THROW 51303, 'TEST FAILED: no se encontro sesion creada por uv_sesion.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Sesion WHERE id = @idSesionCreada AND nombre = N'Sesion Suite QA')
        THROW 51304, 'TEST FAILED: dbo.Sesion no persistio nombre.', 1;

    DECLARE @otroDocente UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_docente WHERE id <> @idDocenteTitular);
    DECLARE @otroUsuarioDocente UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_docente WHERE id = @otroDocente);
    IF @otroDocente IS NULL
    BEGIN
        DECLARE @tipoId UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
        DECLARE @usuarioOtroDocente UNIQUEIDENTIFIER = '23232323-2323-2323-2323-232323232323';
        SET @otroDocente = '24242424-2424-2424-2424-242424242424';
        SET @otroUsuarioDocente = @usuarioOtroDocente;
        IF @tipoId IS NULL THROW 51306, 'TEST FAILED: no existe tipo identificacion CC para docente temporal.', 1;

        INSERT INTO dbo.Usuario (
            id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido,
            primerNombre, segundoNombre, correo, correoConfirmado, estado, password
        )
        VALUES (
            @usuarioOtroDocente, @tipoId, 913000001, N'Docente', N'Intruso',
            N'Sesion', N'QA', N'sesion.otrodocente.qa@test.local', 1, 1, N'HashBackend_QaSesion1234567890'
        );

        INSERT INTO dbo.Docente (id, usuario)
        VALUES (@otroDocente, @usuarioOtroDocente);
    END

    DECLARE @conteoAntes INT = (SELECT COUNT(1) FROM dbo.Sesion WHERE grupo = @idGrupoValido);
    TRUNCATE TABLE #sesionResultado;

    INSERT INTO #sesionResultado
    EXEC dbo.usp_crear_sesion
        @idGrupo = @idGrupoValido,
        @nombre = N'Sesion Intrusa',
        @fechaHoraInicio = @inicioSesion,
        @fechaHoraFin = @finSesion,
        @idCorrelacion = @corrIntrusa,
        @idUsuarioEjecutor = @otroUsuarioDocente;

    IF NOT EXISTS (SELECT 1 FROM #sesionResultado WHERE estadoResultado = 0)
        THROW 51307, 'TEST FAILED: docente no titular no fue rechazado.', 1;

    IF @conteoAntes <> (SELECT COUNT(1) FROM dbo.Sesion WHERE grupo = @idGrupoValido)
        THROW 51308, 'TEST FAILED: docente no titular inserto una sesion.', 1;

    TRUNCATE TABLE #sesionResultado;
    INSERT INTO #sesionResultado
    EXEC dbo.usp_actualizar_sesion
        @idSesion = @idSesionCreada,
        @nombre = N'Sesion Renombrada',
        @fechaHoraInicio = @inicioSesion,
        @fechaHoraFin = @finSesion,
        @idCorrelacion = @corrRenombrar,
        @idUsuarioEjecutor = @idUsuarioDocenteTitular;

    IF NOT EXISTS (SELECT 1 FROM #sesionResultado WHERE estadoResultado = 1)
        THROW 51309, 'TEST FAILED: usp_actualizar_sesion no retorno SUCCESS.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Sesion WHERE id = @idSesionCreada AND nombre = N'Sesion Renombrada')
        THROW 51311, 'TEST FAILED: actualizar sesion no conservo nombre.', 1;

    TRUNCATE TABLE #sesionResultado;
    INSERT INTO #sesionResultado
    EXEC dbo.usp_crear_sesion
        @idGrupo = @idGrupoValido,
        @nombre = N'Sesion Sin Inicio',
        @fechaHoraInicio = NULL,
        @fechaHoraFin = @finSesion,
        @idCorrelacion = @corrActualizar,
        @idUsuarioEjecutor = @idUsuarioDocenteTitular;

    IF NOT EXISTS (SELECT 1 FROM #sesionResultado WHERE estadoResultado = 0)
        OR EXISTS (SELECT 1 FROM dbo.Sesion WHERE nombre = N'Sesion Sin Inicio')
        THROW 51315, 'TEST FAILED: SESSION_REQUIRED_START no rechazo fechaHoraInicio NULL.', 1;

    TRUNCATE TABLE #sesionResultado;
    DECLARE @corrSinFin UNIQUEIDENTIFIER = NEWID();
    INSERT INTO #sesionResultado
    EXEC dbo.usp_crear_sesion
        @idGrupo = @idGrupoValido,
        @nombre = N'Sesion Sin Fin',
        @fechaHoraInicio = @inicioSesion,
        @fechaHoraFin = NULL,
        @idCorrelacion = @corrSinFin,
        @idUsuarioEjecutor = @idUsuarioDocenteTitular;
    IF NOT EXISTS (SELECT 1 FROM #sesionResultado WHERE estadoResultado = 0)
        OR EXISTS (SELECT 1 FROM dbo.Sesion WHERE nombre = N'Sesion Sin Fin')
        THROW 51317, 'TEST FAILED: SESSION_REQUIRED_END no rechazo fechaHoraFin NULL.', 1;

    TRUNCATE TABLE #sesionResultado;
    DECLARE @corrFinInvalido UNIQUEIDENTIFIER = NEWID();
    INSERT INTO #sesionResultado
    EXEC dbo.usp_crear_sesion
        @idGrupo = @idGrupoValido,
        @nombre = N'Sesion Fin Invalido',
        @fechaHoraInicio = @finSesion,
        @fechaHoraFin = @inicioSesion,
        @idCorrelacion = @corrFinInvalido,
        @idUsuarioEjecutor = @idUsuarioDocenteTitular;
    IF NOT EXISTS (SELECT 1 FROM #sesionResultado WHERE estadoResultado = 0)
        OR EXISTS (SELECT 1 FROM dbo.Sesion WHERE nombre = N'Sesion Fin Invalido')
        THROW 51318, 'TEST FAILED: SESSION_END_AFTER_START no rechazo fechaHoraFin <= fechaHoraInicio.', 1;

    TRUNCATE TABLE #sesionResultado;
    DECLARE @corrSinExecutor UNIQUEIDENTIFIER = NEWID();
    INSERT INTO #sesionResultado
    EXEC dbo.usp_crear_sesion
        @idGrupo = @idGrupoValido,
        @nombre = N'Sesion Sin Executor',
        @fechaHoraInicio = @inicioSesion,
        @fechaHoraFin = @finSesion,
        @idCorrelacion = @corrSinExecutor,
        @idUsuarioEjecutor = NULL;
    IF NOT EXISTS (SELECT 1 FROM #sesionResultado WHERE estadoResultado = 0)
        OR EXISTS (SELECT 1 FROM dbo.Sesion WHERE nombre = N'Sesion Sin Executor')
        THROW 51319, 'TEST FAILED: SESSION_EXECUTOR_REQUIRED no rechazo idUsuarioEjecutor NULL.', 1;

    TRUNCATE TABLE #sesionResultado;
    DECLARE @missingSesion UNIQUEIDENTIFIER = '11111111-1111-1111-1111-111111111111';
    DECLARE @sesUserMsg NVARCHAR(4000), @sesTechMsg NVARCHAR(4000);
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SES_001', @p_param1 = @missingSesion,
        @mensajeUsuarioResultado = @sesUserMsg OUTPUT, @mensajeTecnicoResultado = @sesTechMsg OUTPUT;
    DECLARE @corrMissingSesion UNIQUEIDENTIFIER = NEWID();
    INSERT INTO #sesionResultado
    EXEC dbo.usp_actualizar_sesion
        @idSesion = @missingSesion,
        @nombre = N'Sesion Fantasma',
        @fechaHoraInicio = @inicioSesion,
        @fechaHoraFin = @finSesion,
        @idCorrelacion = @corrMissingSesion,
        @idUsuarioEjecutor = @idUsuarioDocenteTitular;
    IF NOT EXISTS (SELECT 1 FROM #sesionResultado WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @sesUserMsg)
        THROW 51320, 'TEST FAILED: SESSION_NOT_FOUND_CODE no rechazo sesion inexistente.', 1;

    -- Fixture aislada para validar correlativo/codigo de sesion (MAX(numero), no COUNT; codigo sin truncar >99)
    DECLARE @idGrupoSecuencia UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes,
        cantidadEstudiantesFinalizaron, cantidadEstudiantesCancelaronVoluntadPropia,
        cantidadEstudiantesCancelaronAutomaticamente, docente)
    SELECT @idGrupoSecuencia, asignatura, periodoAcademico, 500000 + ABS(CHECKSUM(NEWID()) % 100000),
        N'Grupo QA Secuencia Sesion', cantidadEstudiantes, 0, 0, 0, docente
    FROM dbo.Grupo WHERE id = @idGrupoValido;

    INSERT INTO dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
    VALUES
        (NEWID(), N'Fixture Secuencia 1', 1, N'SES-01', 1, @idGrupoSecuencia, DATEADD(HOUR, 40, SYSUTCDATETIME()), DATEADD(HOUR, 41, SYSUTCDATETIME())),
        (NEWID(), N'Fixture Secuencia 3', 3, N'SES-03', 3, @idGrupoSecuencia, DATEADD(HOUR, 42, SYSUTCDATETIME()), DATEADD(HOUR, 43, SYSUTCDATETIME()));

    TRUNCATE TABLE #sesionResultado;
    DECLARE @corrSecuencia UNIQUEIDENTIFIER = NEWID();
    DECLARE @inicioSecuencia DATETIME2 = DATEADD(HOUR, 44, SYSUTCDATETIME());
    DECLARE @finSecuencia DATETIME2 = DATEADD(HOUR, 45, SYSUTCDATETIME());
    INSERT INTO #sesionResultado
    EXEC dbo.usp_crear_sesion
        @idGrupo = @idGrupoSecuencia,
        @nombre = N'Sesion Secuencia MAX',
        @fechaHoraInicio = @inicioSecuencia,
        @fechaHoraFin = @finSecuencia,
        @idCorrelacion = @corrSecuencia,
        @idUsuarioEjecutor = @idUsuarioDocenteTitular;

    IF NOT EXISTS (SELECT 1 FROM #sesionResultado WHERE estadoResultado = 1)
        THROW 52101, 'TEST FAILED: SESSION_SEQUENCE_USES_MAX_NOT_COUNT no retorno SUCCESS.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Sesion WHERE grupo = @idGrupoSecuencia AND nombre = N'Sesion Secuencia MAX' AND numero = 4 AND codigo = N'SES-04')
        THROW 52102, 'TEST FAILED: SESSION_SEQUENCE_USES_MAX_NOT_COUNT numero/codigo incorrecto (esperado 4/SES-04).', 1;

    INSERT INTO dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
    VALUES (NEWID(), N'Fixture Secuencia 99', 99, N'SES-99', 99, @idGrupoSecuencia, DATEADD(HOUR, 46, SYSUTCDATETIME()), DATEADD(HOUR, 47, SYSUTCDATETIME()));

    TRUNCATE TABLE #sesionResultado;
    DECLARE @corrSobre99 UNIQUEIDENTIFIER = NEWID();
    DECLARE @inicioSobre99 DATETIME2 = DATEADD(HOUR, 48, SYSUTCDATETIME());
    DECLARE @finSobre99 DATETIME2 = DATEADD(HOUR, 49, SYSUTCDATETIME());
    INSERT INTO #sesionResultado
    EXEC dbo.usp_crear_sesion
        @idGrupo = @idGrupoSecuencia,
        @nombre = N'Sesion Codigo Sobre 99',
        @fechaHoraInicio = @inicioSobre99,
        @fechaHoraFin = @finSobre99,
        @idCorrelacion = @corrSobre99,
        @idUsuarioEjecutor = @idUsuarioDocenteTitular;

    IF NOT EXISTS (SELECT 1 FROM #sesionResultado WHERE estadoResultado = 1)
        THROW 52103, 'TEST FAILED: SESSION_CODE_OVER_99 no retorno SUCCESS.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Sesion WHERE grupo = @idGrupoSecuencia AND nombre = N'Sesion Codigo Sobre 99' AND numero = 100 AND codigo = N'SES-100')
        THROW 52104, 'TEST FAILED: SESSION_CODE_OVER_99 codigo truncado o incorrecto (esperado SES-100).', 1;

    IF EXISTS (
        SELECT grupo, numero FROM dbo.Sesion
        WHERE grupo = @idGrupoSecuencia
        GROUP BY grupo, numero HAVING COUNT(1) > 1
    )
        THROW 52105, 'TEST FAILED: SESSION_CREATE_NO_DUPLICATE_NUMBER_CODE numero duplicado.', 1;

    IF EXISTS (
        SELECT grupo, codigo FROM dbo.Sesion
        WHERE grupo = @idGrupoSecuencia
        GROUP BY grupo, codigo HAVING COUNT(1) > 1
    )
        THROW 52106, 'TEST FAILED: SESSION_CREATE_NO_DUPLICATE_NUMBER_CODE codigo duplicado.', 1;

    DROP TABLE #sesionResultado;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH
ROLLBACK TRANSACTION;

IF EXISTS (SELECT 1 FROM dbo.Sesion WHERE nombre IN (N'Sesion Suite QA', N'Sesion Intrusa', N'Sesion Renombrada'))
    THROW 51312, 'TEST FAILED: sesion dejo datos permanentes.', 1;

IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo = N'sesion.otrodocente.qa@test.local')
    THROW 51313, 'TEST FAILED: sesion dejo docente temporal permanente.', 1;

IF @@TRANCOUNT <> 0 THROW 51314, 'TEST FAILED: sesion dejo transacciones abiertas.', 1;
PRINT 'TEST PASS: sesion create/update/uv_sesion.';
PRINT 'TEST_PASS:SESSION_CREATE';
PRINT 'TEST_PASS:SESSION_UPDATE';
PRINT 'TEST_PASS:SESSION_NON_OWNER';
PRINT 'TEST_PASS:SESSION_REQUIRED_START';
PRINT 'TEST_PASS:SESSION_REQUIRED_END';
PRINT 'TEST_PASS:SESSION_END_AFTER_START';
PRINT 'TEST_PASS:SESSION_EXECUTOR_REQUIRED';
PRINT 'TEST_PASS:SESSION_NOT_FOUND_CODE';
PRINT 'TEST_PASS:SESSION_SEQUENCE_USES_MAX_NOT_COUNT';
PRINT 'TEST_PASS:SESSION_CODE_OVER_99';
PRINT 'TEST_PASS:SESSION_CREATE_NO_DUPLICATE_NUMBER_CODE';
PRINT 'TEST END: test_usp_crear_actualizar_sesion';
GO
