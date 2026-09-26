USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_crear_programa_academico]
(
    @idPrograma              UNIQUEIDENTIFIER,
    @codigo                  INT,
    @nombre                  NVARCHAR(100),
    @idCoordinador           UNIQUEIDENTIFIER,
    @idFacultad              UNIQUEIDENTIFIER,
    @idTipoPrograma          UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL
)
AS
    -- 1. Estandarización e inicialización de variables utilizando funciones de catálogo (Sin ISNULL)
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idProgramaDefecto        UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idPrograma, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idCoordinadorDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCoordinador, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idFacultadDefecto        UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idFacultad, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idTipoProgramaDefecto    UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idTipoPrograma, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @nombreDef                NVARCHAR(100)    = TRIM(@nombre);

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

        -- PASO 1: Validación del identificador de correlación obligatorio
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 1.5: Validación de perfil RBAC y titularidad jerárquica sobre la Facultad
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'DECANO',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

            IF @estadoResultado = 1 AND @idFacultadDefecto IS NOT NULL
            BEGIN
                EXEC dbo.usp_validar_titularidad_jerarquica_interno
                    @idUsuario = @idUsuarioEjecutorDefecto,
                    @idEntidadPadre = @idFacultadDefecto,
                    @tipoEntidadPadre = 'FACULTAD',
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
            END
        END

        -- PASO 2: Inserción o actualización en dbo.Programa
        IF @estadoResultado = 1
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.uv_programa WHERE id = @idProgramaDefecto OR LOWER(nombrePrograma) = LOWER(@nombreDef))
            BEGIN
                UPDATE dbo.Programa
                SET nombre = @nombreDef,
                    coordinador = @idCoordinadorDefecto,
                    facultad = @idFacultadDefecto,
                    tipoDePrograma = @idTipoProgramaDefecto,
                    estado = 1
                WHERE id = @idProgramaDefecto OR LOWER(nombre) = LOWER(@nombreDef);
            END
            ELSE
            BEGIN
                INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado)
                VALUES (@idProgramaDefecto, @idFacultadDefecto, @idTipoProgramaDefecto, @nombreDef, @idCoordinadorDefecto, 1);
            END

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'Programa Academico',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
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

    -- BLOQUE FINAL: Retorno unificado de resultados
    SELECT 
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
