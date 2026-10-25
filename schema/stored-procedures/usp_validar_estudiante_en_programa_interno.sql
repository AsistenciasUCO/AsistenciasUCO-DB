USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_validar_estudiante_en_programa_interno]
-- HU067/HU069 (CA-06): el estudiante debe tener matricula en un grupo del programa. GEN_001 'Estudiante' tanto si no existe
-- como si es de otro programa (no se revela su existencia).
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_estudiante_en_programa_interno]
(
    @idEstudiante UNIQUEIDENTIFIER,
    @idPrograma   UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @msgP1 NVARCHAR(500);

    IF @idEstudiante IS NULL
    BEGIN
        SET @msgP1 = CAST(N'Estudiante' AS NVARCHAR(500));
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001',
            @p_param1 = @msgP1,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    IF NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo eg INNER JOIN dbo.uv_grupo_programa gp ON gp.idGrupo = eg.idGrupo WHERE eg.idEstudiante = @idEstudiante AND gp.idPrograma = @idPrograma)
    BEGIN
        SET @msgP1 = CAST(N'Estudiante' AS NVARCHAR(500));
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_001',
            @p_param1 = @msgP1,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

END;
GO
