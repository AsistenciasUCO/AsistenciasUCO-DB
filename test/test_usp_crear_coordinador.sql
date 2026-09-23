USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT 'TEST START: test_usp_crear_coordinador';

DECLARE @tipoId UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @idProgramaValido UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_programa);
DECLARE @idFacultadCorrecta UNIQUEIDENTIFIER = (SELECT TOP 1 idFacultad FROM dbo.uv_programa WHERE id = @idProgramaValido);
DECLARE @idInstitucion UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion);
DECLARE @idDecano UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_decano);
DECLARE @idUsuarioDecano UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_decano_identidad WHERE id = @idDecano);

IF @tipoId IS NULL THROW 51400, 'TEST FAILED: no existe fixture uv_tipo_identificacion CC.', 1;
IF @idProgramaValido IS NULL THROW 51401, 'TEST FAILED: no existe fixture uv_programa.', 1;
IF @idFacultadCorrecta IS NULL THROW 51402, 'TEST FAILED: programa fixture no expone facultad.', 1;
IF @idInstitucion IS NULL THROW 51403, 'TEST FAILED: no existe fixture uv_institucion.', 1;
IF @idDecano IS NULL THROW 51404, 'TEST FAILED: no existe fixture uv_decano.', 1;
IF @idUsuarioDecano IS NULL THROW 51415, 'TEST FAILED: no existe fixture usuario decano.', 1;

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @idFacultadIncorrecta UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Facultad (id, nombre, institucion, decano, estado)
    VALUES (@idFacultadIncorrecta, N'Facultad QA Inconsistente', @idInstitucion, @idDecano, 1);

    CREATE TABLE #coordinadorResultado (
        idCorrelacion UNIQUEIDENTIFIER,
        mensajeUsuarioResultado NVARCHAR(4000),
        mensajeTecnicoResultado NVARCHAR(4000),
        estadoResultado BIT
    );
    DECLARE @corrMismatch UNIQUEIDENTIFIER = NEWID();
    DECLARE @corrProgramaMissing UNIQUEIDENTIFIER = NEWID();
    DECLARE @corrFacultadMissing UNIQUEIDENTIFIER = NEWID();
    DECLARE @corrSuccess UNIQUEIDENTIFIER = NEWID();
    DECLARE @idCoordinadorSuccess UNIQUEIDENTIFIER = NEWID();

    DECLARE @correo1 NVARCHAR(100) = N'coord.mismatch.qa@test.local';
    INSERT INTO #coordinadorResultado
    EXEC dbo.usp_crear_coordinador
        @idCoordinador = NULL,
        @numeroIdentificacion = 914000001,
        @primerNombre = N'Coord',
        @segundoNombre = N'Mismatch',
        @primerApellido = N'QA',
        @segundoApellido = N'Test',
        @correo = @correo1,
        @idPrograma = @idProgramaValido,
        @idFacultad = @idFacultadIncorrecta,
        @password = N'HashBackend_QaCoord1234567890',
        @idCorrelacion = @corrMismatch,
        @idUsuarioEjecutor = @idUsuarioDecano;

    IF NOT EXISTS (SELECT 1 FROM #coordinadorResultado WHERE estadoResultado = 0 AND mensajeUsuarioResultado = (SELECT contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'ERR_PROGRAMA_FACULTAD_INCONSISTENTE'))
        THROW 51405, 'TEST FAILED: mismatch Programa/Facultad no retorno ERR_PROGRAMA_FACULTAD_INCONSISTENTE.', 1;

    IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo = @correo1)
        THROW 51406, 'TEST FAILED: mismatch Programa/Facultad creo Usuario parcial.', 1;

    TRUNCATE TABLE #coordinadorResultado;
    DECLARE @correo2 NVARCHAR(100) = N'coord.programa-missing.qa@test.local';
    INSERT INTO #coordinadorResultado
    EXEC dbo.usp_crear_coordinador
        @idCoordinador = NULL,
        @numeroIdentificacion = 914000002,
        @primerNombre = N'Coord',
        @segundoNombre = N'NoPrograma',
        @primerApellido = N'QA',
        @segundoApellido = N'Test',
        @correo = @correo2,
        @idPrograma = '15151515-1515-1515-1515-151515151515',
        @idFacultad = @idFacultadCorrecta,
        @password = N'HashBackend_QaCoord1234567890',
        @idCorrelacion = @corrProgramaMissing,
        @idUsuarioEjecutor = @idUsuarioDecano;

    IF NOT EXISTS (SELECT 1 FROM #coordinadorResultado WHERE estadoResultado = 0 AND mensajeUsuarioResultado = (SELECT contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'PROG_001'))
        THROW 51407, 'TEST FAILED: Programa inexistente no retorno PROG_001.', 1;

    IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo = @correo2)
        THROW 51408, 'TEST FAILED: Programa inexistente creo Usuario parcial.', 1;

    TRUNCATE TABLE #coordinadorResultado;
    DECLARE @correo3 NVARCHAR(100) = N'coord.facultad-missing.qa@test.local';
    INSERT INTO #coordinadorResultado
    EXEC dbo.usp_crear_coordinador
        @idCoordinador = NULL,
        @numeroIdentificacion = 914000003,
        @primerNombre = N'Coord',
        @segundoNombre = N'NoFacultad',
        @primerApellido = N'QA',
        @segundoApellido = N'Test',
        @correo = @correo3,
        @idPrograma = @idProgramaValido,
        @idFacultad = '16161616-1616-1616-1616-161616161616',
        @password = N'HashBackend_QaCoord1234567890',
        @idCorrelacion = @corrFacultadMissing,
        @idUsuarioEjecutor = @idUsuarioDecano;

    IF NOT EXISTS (SELECT 1 FROM #coordinadorResultado WHERE estadoResultado = 0 AND mensajeUsuarioResultado = (SELECT dbo.ufn_reemplazar_plantilla_mensaje(contenido, N'Facultad', NULL, NULL) FROM dbo.uv_mensaje_usuario WHERE codigo = 'GEN_001'))
        THROW 51409, 'TEST FAILED: Facultad inexistente no retorno el codigo existente GEN_001.', 1;

    IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo = @correo3)
        THROW 51410, 'TEST FAILED: Facultad inexistente creo Usuario parcial.', 1;

    TRUNCATE TABLE #coordinadorResultado;
    DECLARE @correo4 NVARCHAR(100) = N'coord.success.qa@test.local';
    INSERT INTO #coordinadorResultado
    EXEC dbo.usp_crear_coordinador
        @idCoordinador = @idCoordinadorSuccess,
        @numeroIdentificacion = 914000004,
        @primerNombre = N'Coord',
        @segundoNombre = N'Success',
        @primerApellido = N'QA',
        @segundoApellido = N'Test',
        @correo = @correo4,
        @idPrograma = @idProgramaValido,
        @idFacultad = @idFacultadCorrecta,
        @password = N'HashBackend_QaCoord1234567890',
        @idCorrelacion = @corrSuccess,
        @idUsuarioEjecutor = @idUsuarioDecano;

    IF NOT EXISTS (SELECT 1 FROM #coordinadorResultado WHERE estadoResultado = 1)
        THROW 51411, 'TEST FAILED: Programa/Facultad correctos no retorno SUCCESS.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Usuario u
        JOIN dbo.Coordinador c ON c.usuario = u.id
        JOIN dbo.Programa p ON p.coordinador = c.id
        WHERE u.correo = @correo4 AND p.id = @idProgramaValido
    )
        THROW 51412, 'TEST FAILED: coordinador SUCCESS no completo Usuario/Coordinador/Programa.', 1;

    DROP TABLE #coordinadorResultado;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH
ROLLBACK TRANSACTION;

IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo IN (@correo1, @correo2, @correo3, @correo4))
    THROW 51413, 'TEST FAILED: coordinador dejo datos permanentes.', 1;

IF @@TRANCOUNT <> 0 THROW 51414, 'TEST FAILED: coordinador dejo transacciones abiertas.', 1;
PRINT 'TEST PASS: coordinador SUCCESS/PROG_001/GEN_001/ERR_PROGRAMA_FACULTAD_INCONSISTENTE.';
PRINT 'TEST_PASS:COORDINATOR_SUCCESS';
PRINT 'TEST_PASS:COORDINATOR_PROGRAM_MISSING';
PRINT 'TEST_PASS:COORDINATOR_FACULTY_MISSING';
PRINT 'TEST_PASS:COORDINATOR_SCOPE_MISMATCH';
PRINT 'TEST END: test_usp_crear_coordinador';
GO
