USE [gestionasistenciadb];
GO

SET NOCOUNT ON;

PRINT 'TEST START: test_usp_validar_sesion_operacion_interno';

DECLARE @idUsuarioDocente UNIQUEIDENTIFIER;
SELECT TOP 1 @idUsuarioDocente = idUsuario
FROM dbo.uv_docente_identidad
WHERE estaActivoUsuario = 1
ORDER BY id;

IF @idUsuarioDocente IS NULL
    THROW 51340, 'TEST FAILED: no existe docente activo para probar la validacion comun.', 1;

DECLARE @mensajeUsuarioResultado NVARCHAR(4000);
DECLARE @mensajeTecnicoResultado NVARCHAR(4000);
DECLARE @estadoResultado BIT;
DECLARE @idCorrelacion UNIQUEIDENTIFIER = NEWID();
DECLARE @fechaHoraInicio DATETIME2 = DATEADD(HOUR, 1, SYSUTCDATETIME());
DECLARE @fechaHoraFin DATETIME2 = DATEADD(HOUR, 2, SYSUTCDATETIME());

EXEC dbo.usp_validar_sesion_operacion_interno
    @idCorrelacion = @idCorrelacion,
    @idUsuarioEjecutor = @idUsuarioDocente,
    @procedenciaTemporal = NULL,
    @fechaHoraInicio = @fechaHoraInicio,
    @fechaHoraFin = @fechaHoraFin,
    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
    @estadoResultado = @estadoResultado OUTPUT;

IF @estadoResultado <> 1
    THROW 51341, 'TEST FAILED: la validacion comun rechazo un docente activo y una procedencia v1.', 1;
PRINT 'TEST_PASS:SESSION_COMMON_VALIDATION_HAPPY_PATH';

SET @mensajeUsuarioResultado = NULL;
SET @mensajeTecnicoResultado = NULL;
SET @estadoResultado = 1;
SET @idCorrelacion = NEWID();

EXEC dbo.usp_validar_sesion_operacion_interno
    @idCorrelacion = @idCorrelacion,
    @idUsuarioEjecutor = @idUsuarioDocente,
    @procedenciaTemporal = N'UTC_OWNER',
    @fechaHoraInicio = @fechaHoraInicio,
    @fechaHoraFin = @fechaHoraFin,
    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
    @estadoResultado = @estadoResultado OUTPUT;

IF @estadoResultado <> 0
    THROW 51342, 'TEST FAILED: la validacion comun acepto una procedencia reservada.', 1;
PRINT 'TEST_PASS:SESSION_COMMON_VALIDATION_RESERVED_PROVENANCE';

SET @mensajeUsuarioResultado = NULL;
SET @mensajeTecnicoResultado = NULL;
SET @estadoResultado = 1;
SET @idCorrelacion = NEWID();

EXEC dbo.usp_validar_sesion_operacion_interno
    @idCorrelacion = @idCorrelacion,
    @idUsuarioEjecutor = NULL,
    @procedenciaTemporal = NULL,
    @fechaHoraInicio = @fechaHoraInicio,
    @fechaHoraFin = @fechaHoraFin,
    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
    @estadoResultado = @estadoResultado OUTPUT;

IF @estadoResultado <> 0
    THROW 51343, 'TEST FAILED: la validacion comun acepto un ejecutor NULL.', 1;
PRINT 'TEST_PASS:SESSION_COMMON_VALIDATION_EXECUTOR_REQUIRED';

SET @mensajeUsuarioResultado = NULL;
SET @mensajeTecnicoResultado = NULL;
SET @estadoResultado = 1;
SET @idCorrelacion = NEWID();

EXEC dbo.usp_validar_sesion_operacion_interno
    @idCorrelacion = @idCorrelacion,
    @idUsuarioEjecutor = @idUsuarioDocente,
    @procedenciaTemporal = NULL,
    @fechaHoraInicio = NULL,
    @fechaHoraFin = @fechaHoraFin,
    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
    @estadoResultado = @estadoResultado OUTPUT;

IF @estadoResultado <> 0
    THROW 51345, 'TEST FAILED: la validacion comun acepto una fecha inicial NULL.', 1;
PRINT 'TEST_PASS:SESSION_COMMON_VALIDATION_START_REQUIRED';

SET @mensajeUsuarioResultado = NULL;
SET @mensajeTecnicoResultado = NULL;
SET @estadoResultado = 1;
SET @idCorrelacion = NEWID();

EXEC dbo.usp_validar_sesion_operacion_interno
    @idCorrelacion = @idCorrelacion,
    @idUsuarioEjecutor = @idUsuarioDocente,
    @procedenciaTemporal = NULL,
    @fechaHoraInicio = @fechaHoraFin,
    @fechaHoraFin = @fechaHoraInicio,
    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
    @estadoResultado = @estadoResultado OUTPUT;

IF @estadoResultado <> 0
    THROW 51346, 'TEST FAILED: la validacion comun acepto una ventana temporal invertida.', 1;
PRINT 'TEST_PASS:SESSION_COMMON_VALIDATION_DATE_ORDER';

IF @@TRANCOUNT <> 0
    THROW 51344, 'TEST FAILED: la validacion comun dejo transacciones abiertas.', 1;

PRINT 'TEST PASS: session common validation.';
GO
