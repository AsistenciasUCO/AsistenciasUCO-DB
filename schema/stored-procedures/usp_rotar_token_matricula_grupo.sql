USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU176B (D2 rotativo): regeneracion MANUAL del codigo de matricula por el docente titular. Ejecutor obligatorio
-- (NULL -> GEN_002). RBAC DOCENTE + titularidad (SEC_002). Rota siempre (no espera ROTACION_SEGUNDOS).
-- La rotacion automatica del servidor es usp_rotar_token_matricula_automatico (CONTRACT A2).
-- Resultset: tupla canonica + idVentana, idDocenteEmisor, fechaRotacionUtc, fechaExpiracionUtc.
CREATE OR ALTER PROCEDURE [dbo].[usp_rotar_token_matricula_grupo]
(
    @idGrupo           UNIQUEIDENTIFIER,
    @tokenHash         VARBINARY(32),
    @pin               NCHAR(6),
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @idVentana          UNIQUEIDENTIFIER = NULL;
    DECLARE @idDocenteEmisor    UNIQUEIDENTIFIER = NULL;
    DECLARE @fechaRotacionUtc   DATETIME2(0)     = NULL;
    DECLARE @fechaExpiracionUtc DATETIME2(0)     = NULL;
BEGIN
    SET NOCOUNT ON;

    IF @idUsuarioEjecutor IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END
    ELSE
    BEGIN
        EXEC dbo.usp_internal_rotar_token_matricula
            @idCorrelacion = @idCorrelacionDefecto, @idGrupo = @idGrupo, @tokenHash = @tokenHash, @pin = @pin,
            @forzar = 1, @idUsuarioManual = @idUsuarioEjecutor,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT,
            @idVentana = @idVentana OUTPUT, @idDocenteEmisor = @idDocenteEmisor OUTPUT,
            @fechaRotacionUtc = @fechaRotacionUtc OUTPUT, @fechaExpiracionUtc = @fechaExpiracionUtc OUTPUT;
    END

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado,
        idVentana               = @idVentana,
        idDocenteEmisor         = @idDocenteEmisor,
        fechaRotacionUtc        = @fechaRotacionUtc,
        fechaExpiracionUtc      = @fechaExpiracionUtc;
END;
GO
