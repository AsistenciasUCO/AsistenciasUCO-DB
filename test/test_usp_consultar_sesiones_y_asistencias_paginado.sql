USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT 'TEST START: test_usp_consultar_sesiones_y_asistencias_paginado';

DECLARE @idUsuarioEjecutor UNIQUEIDENTIFIER;
SELECT TOP 1 @idUsuarioEjecutor = id FROM dbo.uv_usuario WHERE estaActivoUsuario = 1;

IF @idUsuarioEjecutor IS NULL
    THROW 51330, 'TEST FAILED: no existe usuario activo para fixture.', 1;

DECLARE @idGrupoExistente UNIQUEIDENTIFIER;
SELECT TOP 1 @idGrupoExistente = idGrupo FROM dbo.uv_sesion;

IF @idGrupoExistente IS NULL
    SELECT TOP 1 @idGrupoExistente = id FROM dbo.uv_grupo;

DECLARE @idSesionExistente UNIQUEIDENTIFIER;
SELECT TOP 1 @idSesionExistente = id FROM dbo.uv_sesion;

DECLARE @idCorrelacion UNIQUEIDENTIFIER = NEWID();

IF OBJECT_ID('tempdb..#resultadoSesiones') IS NOT NULL DROP TABLE #resultadoSesiones;
CREATE TABLE #resultadoSesiones (
    id UNIQUEIDENTIFIER,
    idGrupo UNIQUEIDENTIFIER,
    codigoGrupo INT,
    nombreGrupo NVARCHAR(100),
    nombre NVARCHAR(100),
    numero INT,
    codigo NVARCHAR(50),
    numeroSemana INT,
    fechaHoraInicio DATETIME2,
    fechaHoraFin DATETIME2,
    totalRegistros INT
);

BEGIN TRANSACTION;
BEGIN TRY
    -- ============================================================================
    -- PRUEBA 1: Consulta de sesiones del grupo (Happy Path)
    -- ============================================================================
    IF @idGrupoExistente IS NOT NULL
    BEGIN
        INSERT INTO #resultadoSesiones
        EXEC dbo.usp_consultar_sesiones_grupo_paginado
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @idCorrelacion = @idCorrelacion,
            @idGrupo = @idGrupoExistente,
            @numeroPagina = 1,
            @tamanoPagina = 10;

        PRINT 'TEST_PASS:USP_CONSULTAR_SESIONES_GRUPO_PAGINADO_SUCCESS';
    END;

    -- ============================================================================
    -- PRUEBA 2: Consulta de asistencias por sesión
    -- ============================================================================
    IF @idSesionExistente IS NOT NULL
    BEGIN
        IF OBJECT_ID('tempdb..#resultadoAsistencias') IS NOT NULL DROP TABLE #resultadoAsistencias;
        CREATE TABLE #resultadoAsistencias (
            idDetalleAsistencia UNIQUEIDENTIFIER,
            codigoDetalleAsistencia INT,
            idAsistencia UNIQUEIDENTIFIER,
            idSesion UNIQUEIDENTIFIER,
            nombreSesion NVARCHAR(100),
            codigoSesion NVARCHAR(50),
            numeroSemana INT,
            idEstudianteGrupo UNIQUEIDENTIFIER,
            idEstudiante UNIQUEIDENTIFIER,
            idUsuario UNIQUEIDENTIFIER,
            numeroIdentificacion NVARCHAR(50),
            primerApellido NVARCHAR(50),
            segundoApellido NVARCHAR(50),
            primerNombre NVARCHAR(50),
            segundoNombre NVARCHAR(50),
            nombreCompleto NVARCHAR(250),
            asistio BIT,
            idRazonCausa UNIQUEIDENTIFIER,
            codigoRazonCausa VARCHAR(10),
            nombreRazonCausa NVARCHAR(100),
            fechaHoraInicio DATETIME2,
            fechaHoraFin DATETIME2,
            totalRegistros INT
        );

        INSERT INTO #resultadoAsistencias
        EXEC dbo.usp_consultar_asistencias_sesion_paginado
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @idCorrelacion = @idCorrelacion,
            @idSesion = @idSesionExistente,
            @numeroPagina = 1,
            @tamanoPagina = 10;

        PRINT 'TEST_PASS:USP_CONSULTAR_ASISTENCIAS_SESION_PAGINADO_SUCCESS';
        DROP TABLE #resultadoAsistencias;
    END;

    DROP TABLE #resultadoSesiones;
END TRY
BEGIN CATCH
    IF OBJECT_ID('tempdb..#resultadoSesiones') IS NOT NULL DROP TABLE #resultadoSesiones;
    IF OBJECT_ID('tempdb..#resultadoAsistencias') IS NOT NULL DROP TABLE #resultadoAsistencias;
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

ROLLBACK TRANSACTION;

-- ============================================================================
-- PRUEBA 3: Validación defensiva - idGrupo NULL
-- ============================================================================
DECLARE @errorCapturado BIT = 0;
BEGIN TRY
    EXEC dbo.usp_consultar_sesiones_grupo_paginado
        @idUsuarioEjecutor = @idUsuarioEjecutor,
        @idCorrelacion = '11111111-1111-1111-1111-111111111111',
        @idGrupo = NULL;
END TRY
BEGIN CATCH
    SET @errorCapturado = 1;
END CATCH;

IF @errorCapturado = 0
    THROW 51331, 'TEST FAILED: idGrupo NULL debio fallar.', 1;

PRINT 'TEST_PASS:USP_CONSULTAR_SESIONES_GRUPO_PAGINADO_INVALID_GROUP';

PRINT 'TEST END: test_usp_consultar_sesiones_y_asistencias_paginado';
GO
