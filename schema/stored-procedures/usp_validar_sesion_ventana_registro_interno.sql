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
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_sesion_ventana_registro_interno]
(
    @idSesion                UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
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

        -- PASO 4: Ventana [inicio, fin) contra el reloj UTC del motor, leído después de obtener el bloqueo
        IF @estadoResultado = 1
        BEGIN
            SET @instanteActualUtc = SYSUTCDATETIME();

            IF @instanteActualUtc < @fechaHoraInicio
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_007',
                    @p_param1 = @idSesionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE IF @instanteActualUtc >= @fechaHoraFin
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_008',
                    @p_param1 = @idSesionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
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
