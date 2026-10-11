USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT 'TEST START: test_maint_003k_error_priority';

DECLARE @idUsuarioDocente UNIQUEIDENTIFIER;
SELECT TOP 1 @idUsuarioDocente = idUsuario
FROM dbo.uv_docente_identidad
WHERE estaActivoUsuario = 1
ORDER BY id;

IF @idUsuarioDocente IS NULL
    THROW 53400, 'TEST FAILED: no existe docente activo para probar prioridad de errores.', 1;

DECLARE @grupoInexistente UNIQUEIDENTIFIER = 'EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE';
DECLARE @sesionInexistente UNIQUEIDENTIFIER = 'FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF';
DECLARE @fechaInicio DATETIME2 = '2026-10-11T14:00:00.0000000';
DECLARE @fechaFin DATETIME2 = '2026-10-11T13:00:00.0000000';
DECLARE @idCorrelacion UNIQUEIDENTIFIER;
DECLARE @sesionesAntes INT;
DECLARE @sesionesDespues INT;

CREATE TABLE #resultado (
    idCorrelacion UNIQUEIDENTIFIER,
    mensajeUsuarioResultado NVARCHAR(4000),
    mensajeTecnicoResultado NVARCHAR(4000),
    estadoResultado BIT
);

-- Caso A: el grupo inexistente conserva prioridad sobre la ventana temporal inválida.
SET @idCorrelacion = NEWID();
SELECT @sesionesAntes = COUNT(*) FROM dbo.uv_sesion;

INSERT INTO #resultado
EXEC dbo.usp_crear_sesion
    @idGrupo = @grupoInexistente,
    @nombre = N'MAINT-003K grupo inexistente',
    @fechaHoraInicio = @fechaInicio,
    @fechaHoraFin = @fechaFin,
    @idCorrelacion = @idCorrelacion,
    @idUsuarioEjecutor = @idUsuarioDocente;

SELECT @sesionesDespues = COUNT(*) FROM dbo.uv_sesion;
IF (SELECT COUNT(*) FROM #resultado) <> 1
    THROW 53401, 'TEST FAILED: MAINT-003K create no retorno exactamente las cuatro columnas contractuales.', 1;
IF NOT EXISTS (
    SELECT 1 FROM #resultado
    WHERE estadoResultado = 0
      AND mensajeTecnicoResultado LIKE 'DBCODE=ERR_GRUPO_NO_EXISTE|%'
)
    THROW 53402, 'TEST FAILED: MAINT-003K create no priorizo ERR_GRUPO_NO_EXISTE sobre SES_004.', 1;
IF @sesionesAntes <> @sesionesDespues
    THROW 53403, 'TEST FAILED: MAINT-003K create dejo una escritura parcial.', 1;
PRINT 'TEST_PASS:SESSION_ERROR_PRIORITY_CREATE_GROUP_BEFORE_DATES';

-- Caso B: la sesión inexistente conserva prioridad sobre la ventana temporal inválida.
TRUNCATE TABLE #resultado;
SET @idCorrelacion = NEWID();
SELECT @sesionesAntes = COUNT(*) FROM dbo.uv_sesion;

INSERT INTO #resultado
EXEC dbo.usp_actualizar_sesion
    @idSesion = @sesionInexistente,
    @nombre = N'MAINT-003K sesión inexistente',
    @fechaHoraInicio = @fechaInicio,
    @fechaHoraFin = @fechaFin,
    @idCorrelacion = @idCorrelacion,
    @idUsuarioEjecutor = @idUsuarioDocente;

SELECT @sesionesDespues = COUNT(*) FROM dbo.uv_sesion;
IF (SELECT COUNT(*) FROM #resultado) <> 1
    THROW 53404, 'TEST FAILED: MAINT-003K update no retorno exactamente las cuatro columnas contractuales.', 1;
IF NOT EXISTS (
    SELECT 1 FROM #resultado
    WHERE estadoResultado = 0
      AND mensajeTecnicoResultado LIKE 'DBCODE=SES_001|%'
)
    THROW 53405, 'TEST FAILED: MAINT-003K update no priorizo SES_001 sobre SES_004.', 1;
IF @sesionesAntes <> @sesionesDespues
    THROW 53406, 'TEST FAILED: MAINT-003K update dejo una escritura parcial.', 1;
PRINT 'TEST_PASS:SESSION_ERROR_PRIORITY_UPDATE_SESSION_BEFORE_DATES';

IF @@TRANCOUNT <> 0
    THROW 53407, 'TEST FAILED: MAINT-003K error priority dejo transacciones abiertas.', 1;

PRINT 'TEST PASS: MAINT-003K error priority.';
GO
