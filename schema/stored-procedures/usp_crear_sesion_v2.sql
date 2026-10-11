USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- UTC-D06-POST-FREEZE: creacion v2. El backend solo invoca este SP despues de normalizar un
-- RFC3339 con offset explicito (perfil UTC-D02) al instante UTC, por lo que las horas recibidas
-- son instantes UTC confirmados: se marcan UTC_V2 en el MISMO INSERT (usp_crear_sesion_interno).
-- Mismos parametros nombrados y resultset de 4 columnas que v1. Ningun parametro permite elegir
-- otra procedencia: el origen lo fija el SP invocado, no el payload del cliente.
CREATE OR ALTER PROCEDURE [dbo].[usp_crear_sesion_v2]
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
        @procedenciaTemporal = N'UTC_V2',
        @idCorrelacionResultado = @idCorrelacionDefecto OUTPUT,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
