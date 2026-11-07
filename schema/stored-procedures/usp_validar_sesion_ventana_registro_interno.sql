USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SES-01: ventana de registro ordinario de asistencia (cierre estricto, sin tolerancia).
--   * Solo se registra cuando fechaHoraInicio <= SYSUTCDATETIME() < fechaHoraFin. El reloj autoritativo es el
--     del motor (UTC); nunca el del cliente ni el del backend.
--   * Solo una procedencia confirmada (UTC_V2, UTC_GENERADOR, UTC_OWNER) prueba que los DATETIME2 son instantes
--     UTC. NULL (INDETERMINADA) no permite escribir: no se supone zona horaria alguna.
--   * Lee la fila de dbo.Sesion con UPDLOCK + HOLDLOCK: invocado dentro de la transaccion del llamador, el
--     bloqueo se mantiene hasta su COMMIT/ROLLBACK, de modo que el horario no cambia entre esta validacion y la
--     escritura, y los lotes concurrentes de la misma sesion se serializan y evaluan el reloj despues de
--     obtener el bloqueo (una solicitud iniciada antes del cierre que llega despues del cierre se rechaza).
--   * Codigos: SES_007 (sesion no iniciada), SES_008 (sesion cerrada), SES_009 (horario indeterminado).
--   * No escribe. El llamador decide la reversion y el resultset canonico.
-- CULM-001 B.1 (CONTRACT §2.7.1):
--   * @toleranciaMinutos / @margenMinutos (opcionales): ventana [inicio - tolerancia, fin + margen). NULL o negativos = 0,
--     es decir, la regla estricta de SES-01; los llamadores de 5 parametros (lote congelado, autonomo) no cambian.
--     Los valores los lee el LLAMADOR (ASISTENCIA/TOLERANCIA_MINUTOS y ASISTENCIA/MARGEN_RETARDO_MINUTOS).
--   * PASO 2.5 (todos los llamadores): una sesion con dbo.SesionCancelacion se rechaza con SES_010. Se lee despues del
--     UPDLOCK + HOLDLOCK sobre dbo.Sesion, el mismo bloqueo que toma usp_cancelar_sesion: registro y cancelacion se
--     serializan.
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_sesion_ventana_registro_interno]
(
    @idSesion                UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT,
    @toleranciaMinutos       INT = NULL,
    @margenMinutos           INT = NULL
)
AS
    -- 1. Estandarización e inicialización de variables utilizando funciones de catálogo (Sin ISNULL)
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @existe              BIT = 0;
    DECLARE @fechaHoraInicio     DATETIME2;
    DECLARE @fechaHoraFin        DATETIME2;
    DECLARE @procedenciaTemporal NVARCHAR(24);
    DECLARE @instanteActualUtc   DATETIME2;
    DECLARE @toleranciaAplicada  INT = IIF(@toleranciaMinutos IS NULL OR @toleranciaMinutos < 0, 0, @toleranciaMinutos);
    DECLARE @margenAplicado      INT = IIF(@margenMinutos IS NULL OR @margenMinutos < 0, 0, @margenMinutos);
    DECLARE @aperturaUtc         DATETIME2;
    DECLARE @cierreUtc           DATETIME2;
    DECLARE @detalleVentana      NVARCHAR(200) = IIF(@toleranciaMinutos IS NULL AND @margenMinutos IS NULL,
                                                     dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
                                                     CONCAT(' Tolerancia: ', @toleranciaAplicada, ' min; margen: ', @margenAplicado, ' min.'));

    -- Inicialización de respuesta desde parámetros del catálogo
    SELECT
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

        -- PASO 1: Validación del identificador de correlación obligatorio
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Lectura bloqueada del horario y su procedencia (misma fila, una sola sentencia)
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1
                @existe = 1,
                @fechaHoraInicio = s.fechaHoraInicio,
                @fechaHoraFin = s.fechaHoraFin,
                @procedenciaTemporal = s.procedenciaTemporal
            FROM dbo.Sesion s WITH (UPDLOCK, HOLDLOCK)
            WHERE s.id = @idSesionDefecto;

            IF @existe = 0
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_001',
                    @p_param1 = @idSesionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 2.5 (CULM-001 B.1): sesion cancelada => SES_010 (lectura despues del bloqueo de la fila de dbo.Sesion)
        IF @estadoResultado = 1
           AND EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc WHERE sc.sesion = @idSesionDefecto)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SES_010',
                @p_param1 = @idSesionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: Procedencia temporal confirmada (NULL o desconocida = INDETERMINADA)
        IF @estadoResultado = 1
           AND (@procedenciaTemporal IS NULL OR @procedenciaTemporal NOT IN (N'UTC_V2', N'UTC_GENERADOR', N'UTC_OWNER'))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SES_009',
                @p_param1 = @idSesionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 4: Ventana [inicio - tolerancia, fin + margen) contra el reloj UTC del motor, leído después de obtener
        --         el bloqueo. Sin tolerancia ni margen es la ventana estricta [inicio, fin) de SES-01.
        IF @estadoResultado = 1
        BEGIN
            SET @instanteActualUtc = SYSUTCDATETIME();
            SET @aperturaUtc = DATEADD(MINUTE, -@toleranciaAplicada, @fechaHoraInicio);
            SET @cierreUtc = DATEADD(MINUTE, @margenAplicado, @fechaHoraFin);

            IF @instanteActualUtc < @aperturaUtc
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_007',
                    @p_param1 = @idSesionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, @detalleVentana, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE IF @instanteActualUtc >= @cierreUtc
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_008',
                    @p_param1 = @idSesionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, @detalleVentana, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
