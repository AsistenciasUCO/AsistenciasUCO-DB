USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU176B: registro PUBLICO de una persona sin cuenta y su matricula con el token o PIN de una ventana ACTIVA. No tiene
-- parametro de ejecutor: la credencial es el token/PIN (excepcion declarada en CONTRACT §2.1 y A2); solo se concede
-- EXECUTE al rol de runtime. Crea Usuario ACTIVO (correoConfirmado = 0), Estudiante y la matricula, de forma atomica.
-- Correo institucional obligatorio (VCE_001). Documento o correo ya registrados: MQR_005. Token invalido: MQR_001.
-- Resultset: tupla canonica + idEstudiante, idUsuario, idGrupo (extension documentada, CONTRACT §2.5).
CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_estudiante_por_token_publico]
(
    @idCorrelacion         UNIQUEIDENTIFIER,
    @tokenHash             VARBINARY(32)    = NULL,
    @pin                   NCHAR(6)         = NULL,
    @idTipoIdentificacion  UNIQUEIDENTIFIER = NULL,
    @numeroIdentificacion  INT              = NULL,
    @primerNombre          NVARCHAR(50)     = NULL,
    @segundoNombre         NVARCHAR(50)     = NULL,
    @primerApellido        NVARCHAR(50)     = NULL,
    @segundoApellido       NVARCHAR(50)     = NULL,
    @correo                NVARCHAR(100)    = NULL,
    @password              NVARCHAR(500)    = NULL
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

    EXEC dbo.usp_internal_matricular_por_token
        @idCorrelacion = @idCorrelacionDefecto, @tokenHash = @tokenHash, @pin = @pin,
        @idUsuarioAutenticado = NULL,
        @idTipoIdentificacion = @idTipoIdentificacion, @numeroIdentificacion = @numeroIdentificacion,
        @primerNombre = @primerNombre, @segundoNombre = @segundoNombre,
        @primerApellido = @primerApellido, @segundoApellido = @segundoApellido,
        @correo = @correo, @password = @password,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT,
        @idEstudianteResultado = @idEstudianteResultado OUTPUT,
        @idUsuarioResultado = @idUsuarioResultado OUTPUT,
        @idGrupoResultado = @idGrupoResultado OUTPUT;

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
