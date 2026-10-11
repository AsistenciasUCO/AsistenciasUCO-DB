USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Validacion compartida por los nucleos de creacion y actualizacion de sesion.
-- Mantiene en un unico punto las reglas de procedencia, correlacion y seguridad;
-- no abre ni modifica transacciones y deja la gestion transaccional al llamador.
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_sesion_operacion_interno]
(
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @procedenciaTemporal     NVARCHAR(24),
    @fechaHoraInicio         DATETIME2,
    @fechaHoraFin            DATETIME2,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

BEGIN
    SET NOCOUNT ON;

    SELECT
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado         = 1;

    BEGIN TRY
        -- PASO 0: Solo NULL (v1) o UTC_V2 (v2) son procedencias admitidas.
        IF @procedenciaTemporal IS NOT NULL AND @procedenciaTemporal <> N'UTC_V2'
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'procedenciaTemporal',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 1: Validacion de correlacion.
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 1.5: El ejecutor es obligatorio y nunca puede saltar seguridad.
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 1.6: Validacion de perfil RBAC del ejecutor.
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'DOCENTE',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2: Las fechas de sesion son obligatorias y deben estar ordenadas.
        IF @estadoResultado = 1 AND @fechaHoraInicio IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'fechaHoraInicio',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND @fechaHoraFin IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'fechaHoraFin',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND @fechaHoraFin <= @fechaHoraInicio
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SES_004',
                @p_param1 = 'fechaHoraFin',
                @p_param2 = 'fechaHoraInicio',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
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
