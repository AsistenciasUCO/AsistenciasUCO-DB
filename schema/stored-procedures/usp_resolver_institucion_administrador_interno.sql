USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_resolver_institucion_administrador_interno]
-- HU133-HU139: valida correlacion y ejecutor y resuelve la institucion del administrador (ambito).
-- Falla con THROW (DBCODE=...): CORR_001, VAL_001 (ejecutor nulo), KPI_004 (no es administrador de una institucion), KPI_002 (umbral ausente).
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_resolver_institucion_administrador_interno]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @validarUmbrales   BIT = 1,
    @idInstitucion     UNIQUEIDENTIFIER OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @msgP1 NVARCHAR(500);
    SET @idInstitucion = NULL;
    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 0 THROW 51000, @mensajeTecnicoResultado, 1;
    IF @idUsuarioEjecutor IS NULL OR @idUsuarioEjecutor = @guidVacio
    BEGIN
        SET @msgP1 = CAST(N'UsuarioEjecutor' AS NVARCHAR(500));
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001',
            @p_param1 = @msgP1,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    SELECT TOP 1 @idInstitucion = a.idInstitucion
    FROM dbo.uv_administrador a
    WHERE a.idUsuario = @idUsuarioEjecutor
    ORDER BY a.estaActivaInstitucion DESC, a.nombreInstitucion ASC, a.idInstitucion ASC;

    IF @idInstitucion IS NULL
    BEGIN
        SET @msgP1 = CAST(CONVERT(NVARCHAR(36), @idUsuarioEjecutor) AS NVARCHAR(500));
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'KPI_004',
            @p_param1 = @msgP1,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    IF @validarUmbrales = 1 AND dbo.ufn_clasificar_permanencia(0, N'A') IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'KPI_002',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END
END;
GO
