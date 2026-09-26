USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT 'TEST START: test_usp_resolver_solicitud_matricula';
DECLARE @idUsuarioCoordinador UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_coordinador_identidad WHERE estaActivoUsuario = 1);
IF @idUsuarioCoordinador IS NULL THROW 51603, 'TEST FAILED: SolicitudMatricula no tiene coordinador ejecutor fixture.', 1;

BEGIN TRANSACTION;
BEGIN TRY
    CREATE TABLE #resultadoSolicitudMatricula (
        idCorrelacion UNIQUEIDENTIFIER,
        mensajeUsuarioResultado NVARCHAR(4000),
        mensajeTecnicoResultado NVARCHAR(4000),
        estadoResultado BIT
    );

    INSERT INTO #resultadoSolicitudMatricula
    EXEC dbo.usp_resolver_solicitud_matricula
        @idSolicitud = '18181818-1818-1818-1818-181818181818',
        @idCoordinador = '19191919-1919-1919-1919-191919191919',
        @accion = N'APROBAR',
        @respuestaCoordinador = N'Aprobado por QA',
        @idCorrelacion = '20202020-2020-2020-2020-202020202020',
        @idUsuarioEjecutor = @idUsuarioCoordinador;

    IF NOT EXISTS (
        SELECT 1
        FROM #resultadoSolicitudMatricula
        WHERE estadoResultado = 0
          AND mensajeUsuarioResultado = (SELECT contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'ERR_SOLICITUD_MATRICULA_NO_IMPLEMENTADA')
    )
        THROW 51600, 'TEST FAILED: SolicitudMatricula no retorno ERR_SOLICITUD_MATRICULA_NO_IMPLEMENTADA con estadoResultado = 0.', 1;

    IF OBJECT_ID('dbo.SolicitudMatricula', 'U') IS NOT NULL
        THROW 51601, 'TEST FAILED: dbo.SolicitudMatricula existe aunque la capability esta declarada no implementada.', 1;

    DROP TABLE #resultadoSolicitudMatricula;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH
ROLLBACK TRANSACTION;

IF @@TRANCOUNT <> 0 THROW 51602, 'TEST FAILED: SolicitudMatricula dejo transacciones abiertas.', 1;
PRINT 'TEST PASS: SolicitudMatricula retorna ERR_SOLICITUD_MATRICULA_NO_IMPLEMENTADA y no simula SUCCESS.';
PRINT 'TEST_PASS:MATRICULA_NOT_IMPLEMENTED';
PRINT 'TEST END: test_usp_resolver_solicitud_matricula';
GO
