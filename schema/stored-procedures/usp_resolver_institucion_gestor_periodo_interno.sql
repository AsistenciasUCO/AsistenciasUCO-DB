USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU096/HU097/HU098: valida que el ejecutor pueda gestionar periodos academicos y resuelve la institucion sobre la
-- que actua. El periodo es unico para toda la institucion, por eso solo lo gestiona el ADMINISTRADOR de esa
-- institucion (dbo.Administrador.institucion); DECANO y COORDINADOR solo lo consultan. Sin institucion => PER_005.
CREATE OR ALTER PROCEDURE [dbo].[usp_resolver_institucion_gestor_periodo_interno]
(
    @idUsuario               UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idInstitucion           UNIQUEIDENTIFIER OUTPUT,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuario, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    SELECT
        @idInstitucion = NULL,
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        EXEC dbo.usp_validar_permiso_rbac_usuario_interno
            @idUsuario = @idUsuarioDefecto, @codigoPerfilRequerido = 'ADMINISTRADOR',
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idInstitucion = a.institucion
            FROM dbo.Administrador a
            INNER JOIN dbo.Institucion i ON i.id = a.institucion AND i.estado = 1
            WHERE a.usuario = @idUsuarioDefecto;

            IF @idInstitucion IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'PER_005',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END
    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
