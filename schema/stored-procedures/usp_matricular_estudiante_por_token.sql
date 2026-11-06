USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU176B: matricula de un estudiante YA REGISTRADO e identificado (modo AUTENTICADO) con el token o PIN de una ventana
-- ACTIVA. Ejecutor obligatorio (NULL -> GEN_002); RBAC ESTUDIANTE. Reglas de HU050, cupo, duplicado (MQR_004) y atomicidad
-- en usp_internal_matricular_por_token. El registro de una persona sin cuenta es usp_registrar_estudiante_por_token_publico
-- (CONTRACT A2).
-- Resultset: tupla canonica + idEstudiante, idUsuario, idGrupo (extension documentada, CONTRACT §2.5).
CREATE OR ALTER PROCEDURE [dbo].[usp_matricular_estudiante_por_token]
(
    @idCorrelacion     UNIQUEIDENTIFIER,
    @tokenHash         VARBINARY(32)    = NULL,
    @pin               NCHAR(6)         = NULL,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @idEstudianteResultado UNIQUEIDENTIFIER = NULL;
    DECLARE @idUsuarioResultado    UNIQUEIDENTIFIER = NULL;
    DECLARE @idGrupoResultado      UNIQUEIDENTIFIER = NULL;
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
        EXEC dbo.usp_internal_matricular_por_token
            @idCorrelacion = @idCorrelacionDefecto, @tokenHash = @tokenHash, @pin = @pin,
            @idUsuarioAutenticado = @idUsuarioEjecutor,
            @idTipoIdentificacion = NULL, @numeroIdentificacion = NULL, @primerNombre = NULL, @segundoNombre = NULL,
            @primerApellido = NULL, @segundoApellido = NULL, @correo = NULL, @password = NULL,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT,
            @idEstudianteResultado = @idEstudianteResultado OUTPUT,
            @idUsuarioResultado = @idUsuarioResultado OUTPUT,
            @idGrupoResultado = @idGrupoResultado OUTPUT;
    END

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado,
        idEstudiante            = @idEstudianteResultado,
        idUsuario               = @idUsuarioResultado,
        idGrupo                 = @idGrupoResultado;
END;
GO
