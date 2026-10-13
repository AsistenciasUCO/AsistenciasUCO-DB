USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Contrato v1 (DB-GP-001C): firma y resultset de 4 columnas sin cambios.
-- UTC-D06-POST-FREEZE: la logica vive en usp_crear_sesion_interno. v1 no transmite zona horaria,
-- por eso la sesion creada por esta via queda con procedenciaTemporal = NULL (INDETERMINADA),
-- escrita en el mismo INSERT que las horas.
CREATE OR ALTER PROCEDURE [dbo].[usp_crear_sesion]
(
    @idGrupo            UNIQUEIDENTIFIER,
    @nombre             NVARCHAR(50),
    @fechaHoraInicio    DATETIME2,
    @fechaHoraFin       DATETIME2,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto    UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;

    EXEC dbo.usp_crear_sesion_interno
        @idGrupo = @idGrupo,
        @nombre = @nombre,
        @fechaHoraInicio = @fechaHoraInicio,
        @fechaHoraFin = @fechaHoraFin,
        @idCorrelacion = @idCorrelacion,
        @idUsuarioEjecutor = @idUsuarioEjecutor,
        @procedenciaTemporal = NULL,
        @idCorrelacionResultado = @idCorrelacionDefecto OUTPUT,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    -- BLOQUE FINAL: Retorno unificado de resultados
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
