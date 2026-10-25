USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_validar_programa_en_facultad_interno]
-- HU144 (CA-05): GEN_001 «Programa» si el programa no existe o pertenece a otra facultad (no se revela cual de los dos).
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_programa_en_facultad_interno]
(
    @idFacultad UNIQUEIDENTIFIER,
    @idPrograma UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @msgP1 NVARCHAR(500);

    IF @idPrograma IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.uv_programa p WHERE p.id = @idPrograma AND p.idFacultad = @idFacultad)
    BEGIN
        SET @msgP1 = CAST(N'Programa' AS NVARCHAR(500));
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_001',
            @p_param1 = @msgP1,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END
END;
GO
