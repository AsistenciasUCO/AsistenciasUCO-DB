USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT 'TEST START: test_usp_consultar_catalogos_y_revisiones_paginado';

DECLARE @idUsuarioEjecutor UNIQUEIDENTIFIER;
SELECT TOP 1 @idUsuarioEjecutor = id FROM dbo.uv_usuario WHERE estaActivoUsuario = 1;

IF @idUsuarioEjecutor IS NULL
    THROW 51340, 'TEST FAILED: no existe usuario activo para fixture.', 1;

DECLARE @idCorrelacion UNIQUEIDENTIFIER = NEWID();

IF OBJECT_ID('tempdb..#resultadoAsignaturas') IS NOT NULL DROP TABLE #resultadoAsignaturas;
CREATE TABLE #resultadoAsignaturas (
    id UNIQUEIDENTIFIER,
    codigo NVARCHAR(50),
    nombre NVARCHAR(100),
    credito INT,
    idArea UNIQUEIDENTIFIER,
    nombreArea NVARCHAR(100),
    idComponente UNIQUEIDENTIFIER,
    nombreComponente NVARCHAR(100),
    inp INT,
    nombrePrograma NVARCHAR(100),
    codigoSemestre NVARCHAR(50),
    estaActivaAsignatura BIT,
    totalRegistros INT
);

IF OBJECT_ID('tempdb..#resultadoProgramas') IS NOT NULL DROP TABLE #resultadoProgramas;
CREATE TABLE #resultadoProgramas (
    id UNIQUEIDENTIFIER,
    nombrePrograma NVARCHAR(100),
    idFacultad UNIQUEIDENTIFIER,
    nombreFacultad NVARCHAR(100),
    idInstitucion UNIQUEIDENTIFIER,
    nombreInstitucion NVARCHAR(100),
    idCoordinador UNIQUEIDENTIFIER,
    nombreCoordinador NVARCHAR(250),
    estaActivoPrograma BIT,
    totalRegistros INT
);

IF OBJECT_ID('tempdb..#resultadoFacultades') IS NOT NULL DROP TABLE #resultadoFacultades;
CREATE TABLE #resultadoFacultades (
    id UNIQUEIDENTIFIER,
    nombreFacultad NVARCHAR(100),
    idInstitucion UNIQUEIDENTIFIER,
    nombreInstitucion NVARCHAR(100),
    idDecano UNIQUEIDENTIFIER,
    nombreCompletoDecano NVARCHAR(250),
    estaActivaFacultad BIT,
    totalRegistros INT
);

IF OBJECT_ID('tempdb..#resultadoRevisiones') IS NOT NULL DROP TABLE #resultadoRevisiones;
CREATE TABLE #resultadoRevisiones (
    idSolicitud UNIQUEIDENTIFIER,
    radicadoSolicitud NVARCHAR(100),
    fechaRadicacion DATE,
    idEstado UNIQUEIDENTIFIER,
    nombreEstado NVARCHAR(100),
    justificacionSolicitud VARCHAR(MAX),
    justificacionRespuesta VARCHAR(MAX),
    idAsistencia UNIQUEIDENTIFIER,
    idSesion UNIQUEIDENTIFIER,
    nombreSesion NVARCHAR(100),
    codigoSesion NVARCHAR(50),
    idGrupo UNIQUEIDENTIFIER,
    idEstudianteGrupo UNIQUEIDENTIFIER,
    idEstudiante UNIQUEIDENTIFIER,
    idUsuario UNIQUEIDENTIFIER,
    numeroIdentificacion NVARCHAR(50),
    nombreCompletoEstudiante NVARCHAR(250),
    correoEstudiante NVARCHAR(150),
    totalRegistros INT
);

BEGIN TRANSACTION;
BEGIN TRY
    -- ============================================================================
    -- PRUEBA 1: Consulta de Asignaturas
    -- ============================================================================
    INSERT INTO #resultadoAsignaturas
    EXEC dbo.usp_consultar_asignaturas_paginado
        @idUsuarioEjecutor = @idUsuarioEjecutor,
        @idCorrelacion = @idCorrelacion,
        @numeroPagina = 1,
        @tamanoPagina = 10;

    PRINT 'TEST_PASS:USP_CONSULTAR_ASIGNATURAS_PAGINADO_SUCCESS';

    -- ============================================================================
    -- PRUEBA 2: Consulta de Programas
    -- ============================================================================
    INSERT INTO #resultadoProgramas
    EXEC dbo.usp_consultar_programas_paginado
        @idUsuarioEjecutor = @idUsuarioEjecutor,
        @idCorrelacion = @idCorrelacion,
        @numeroPagina = 1,
        @tamanoPagina = 10;

    PRINT 'TEST_PASS:USP_CONSULTAR_PROGRAMAS_PAGINADO_SUCCESS';

    -- ============================================================================
    -- PRUEBA 3: Consulta de Facultades
    -- ============================================================================
    INSERT INTO #resultadoFacultades
    EXEC dbo.usp_consultar_facultades_paginado
        @idUsuarioEjecutor = @idUsuarioEjecutor,
        @idCorrelacion = @idCorrelacion,
        @numeroPagina = 1,
        @tamanoPagina = 10;

    PRINT 'TEST_PASS:USP_CONSULTAR_FACULTADES_PAGINADO_SUCCESS';

    -- ============================================================================
    -- PRUEBA 4: Consulta de Solicitudes de Revisión de Asistencia
    -- ============================================================================
    INSERT INTO #resultadoRevisiones
    EXEC dbo.usp_consultar_solicitudes_revision_asistencia_paginado
        @idUsuarioEjecutor = @idUsuarioEjecutor,
        @idCorrelacion = @idCorrelacion,
        @numeroPagina = 1,
        @tamanoPagina = 10;

    PRINT 'TEST_PASS:USP_CONSULTAR_REVISIONES_PAGINADO_SUCCESS';

    DROP TABLE #resultadoRevisiones;
    DROP TABLE #resultadoAsignaturas;
    DROP TABLE #resultadoProgramas;
    DROP TABLE #resultadoFacultades;
END TRY
BEGIN CATCH
    IF OBJECT_ID('tempdb..#resultadoAsignaturas') IS NOT NULL DROP TABLE #resultadoAsignaturas;
    IF OBJECT_ID('tempdb..#resultadoProgramas') IS NOT NULL DROP TABLE #resultadoProgramas;
    IF OBJECT_ID('tempdb..#resultadoFacultades') IS NOT NULL DROP TABLE #resultadoFacultades;
    IF OBJECT_ID('tempdb..#resultadoRevisiones') IS NOT NULL DROP TABLE #resultadoRevisiones;
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

ROLLBACK TRANSACTION;

PRINT 'TEST END: test_usp_consultar_catalogos_y_revisiones_paginado';
GO
