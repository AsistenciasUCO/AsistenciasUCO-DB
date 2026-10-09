USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =====================================================================================
-- PUBLIC (consumido por el backend). Orquestador de usp_sincronizar_usuario_interno.
-- TD-043 (USER_SYNC_PROVIDER): restaura el provider publico que el backend invoca.
-- Contrato canonico: 1 fila, 4 columnas (idCorrelacion, mensajeUsuarioResultado,
-- mensajeTecnicoResultado, estadoResultado). Sin parametros OUTPUT hacia el backend.
-- Validaciones (correlacion, tipo de identificacion, unicidad, formato, correo, password)
-- las ejecuta el interno; este SP solo traduce su salida a la fila canonica.
-- Transaccion: una sola escritura (INSERT Usuario) dentro del interno; sin transaccion propia.
-- =====================================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_sincronizar_usuario]
(
    @idTipoIdIdentificacion UNIQUEIDENTIFIER,
    @numeroIdentificacion   INT,
    @primerApellido         NVARCHAR(255),
    @segundoApellido        NVARCHAR(255),
    @primerNombre           NVARCHAR(255),
    @segundoNombre          NVARCHAR(255),
    @correo                 NVARCHAR(255),
    @password               NVARCHAR(500),
    @idCorrelacion          UNIQUEIDENTIFIER
)
AS

DECLARE @idCorrelacionDefecto    UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
DECLARE @mensajeUsuarioResultado NVARCHAR(4000)   = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
DECLARE @mensajeTecnicoResultado NVARCHAR(4000)   = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
DECLARE @estadoResultado         BIT              = 1;

BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        EXEC dbo.usp_sincronizar_usuario_interno
            @idTipoIdIdentificacion  = @idTipoIdIdentificacion,
            @numeroIdentificacion    = @numeroIdentificacion,
            @primerApellido          = @primerApellido,
            @segundoApellido         = @segundoApellido,
            @primerNombre            = @primerNombre,
            @segundoNombre           = @segundoNombre,
            @correo                  = @correo,
            @password                = @password,
            @idCorrelacion           = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado         = @estadoResultado OUTPUT;
    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- BLOQUE FINAL: contrato canonico (4 columnas)
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
