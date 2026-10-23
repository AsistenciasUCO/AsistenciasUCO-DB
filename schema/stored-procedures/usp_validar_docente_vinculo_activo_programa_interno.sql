USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU093 (D12): un docente cuyo vinculo con el programa de la asignatura fue INACTIVADO no puede ser titular de grupos
-- nuevos ni asignarse a un grupo existente (DOC_009). Un docente sin ningun vinculo no se bloquea, para no romper
-- flujos de asignacion previos a la adscripcion; los grupos ya asignados se conservan (esta regla solo se aplica
-- cuando se designa un titular).
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_docente_vinculo_activo_programa_interno]
(
    @idDocente               UNIQUEIDENTIFIER,
    @idAsignatura            UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idPrograma UNIQUEIDENTIFIER;

    SELECT
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;

BEGIN
    SET NOCOUNT ON;

    SELECT TOP 1 @idPrograma = pe.idPrograma
    FROM dbo.uv_asignatura a
    INNER JOIN dbo.uv_semestre_plan_estudio spe ON a.idSemestrePlanEstudio = spe.id
    INNER JOIN dbo.uv_plan_estudio pe ON spe.idPlanEstudio = pe.id
    WHERE a.id = @idAsignatura;

    IF @idPrograma IS NOT NULL
       AND EXISTS (SELECT 1 FROM dbo.DocentePrograma WHERE docente = @idDocente AND programa = @idPrograma AND estado = 0)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'DOC_009',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END
END;
GO
