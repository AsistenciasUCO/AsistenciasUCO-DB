USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_ficha_estudiante_programa (HU069). READ_QUERY_RESULTSET (1 fila). Solo campos que existen en la DB (sin telefono, D5).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_ficha_estudiante_programa]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idEstudiante      UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @msgP1 NVARCHAR(500);
    DECLARE @idPrograma UNIQUEIDENTIFIER;

    EXEC dbo.usp_resolver_programa_coordinador_interno @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion, @validarUmbrales = 0, @idPrograma = @idPrograma OUTPUT;
    EXEC dbo.usp_validar_estudiante_en_programa_interno @idEstudiante = @idEstudiante, @idPrograma = @idPrograma;

    SELECT
        idEstudiante = ei.id,
        tipoIdentificacion = u.TipoIdentificacion,
        numeroIdentificacion = u.numeroIdentificacion,
        primerNombre = u.primerNombre,
        segundoNombre = u.segundoNombre,
        primerApellido = u.primerApellido,
        segundoApellido = u.segundoApellido,
        nombreCompleto = u.nombreCompleto,
        correo = u.correo,
        estaActivoUsuario = u.estaActivoUsuario,
        idPrograma = p.id,
        nombrePrograma = p.nombrePrograma
    FROM dbo.uv_estudiante_identidad ei
    INNER JOIN dbo.uv_usuario u ON u.id = ei.idUsuario
    INNER JOIN dbo.uv_programa p ON p.id = @idPrograma
    WHERE ei.id = @idEstudiante;
END;
GO
