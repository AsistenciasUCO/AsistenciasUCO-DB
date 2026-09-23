USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_validar_titularidad_jerarquica_interno]
(
    @idUsuario               UNIQUEIDENTIFIER,
    @idEntidadPadre          UNIQUEIDENTIFIER,
    @tipoEntidadPadre        NVARCHAR(50),
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    -- @idUsuario es Usuario.id (identidad autenticada), NO Docente.id / Coordinador.id / Decano.id.
    -- Cada rama resuelve el ID de rol hacia Usuario.id mediante uv_docente_identidad / uv_coordinador_identidad /
    -- uv_decano_identidad. INSTITUCION compara Administrador.usuario, que ya es Usuario.id.
    -- 1. Estandarización e inicialización de variables utilizando funciones de catálogo (Sin ISNULL)
    DECLARE @idCorrelacionDefecto    UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto        UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuario, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idEntidadPadreDefecto   UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idEntidadPadre, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @tipoEntidadPadreDefecto NVARCHAR(50)     = TRIM(dbo.ufn_obtener_parametro_texto(@tipoEntidadPadre, 'GENERAL', 'CADENA_VACIA'));

    -- Inicialización de respuesta desde parámetros del catálogo
    SELECT 
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

        -- PASO 1: Validación del identificador de correlación obligatorio
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Verificación de custodia según tipo de entidad padre
        IF @estadoResultado = 1
        BEGIN
            IF @tipoEntidadPadreDefecto = 'GRUPO'
            BEGIN
                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.uv_grupo g
                    INNER JOIN dbo.uv_docente_identidad di ON di.id = g.idDocente
                    WHERE g.id = @idEntidadPadreDefecto AND di.idUsuario = @idUsuarioDefecto
                )
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'SEC_002',
                        @p_param1 = 'Titularidad Grupo',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
            END
            ELSE IF @tipoEntidadPadreDefecto = 'PROGRAMA'
            BEGIN
                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.uv_programa p
                    INNER JOIN dbo.uv_coordinador_identidad ci ON ci.id = p.idCoordinador
                    WHERE p.id = @idEntidadPadreDefecto AND ci.idUsuario = @idUsuarioDefecto
                )
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'SEC_002',
                        @p_param1 = 'Titularidad Programa',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
            END
            ELSE IF @tipoEntidadPadreDefecto = 'FACULTAD'
            BEGIN
                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.uv_facultad f
                    INNER JOIN dbo.uv_decano_identidad di ON di.id = f.idDecano
                    WHERE f.id = @idEntidadPadreDefecto AND di.idUsuario = @idUsuarioDefecto
                )
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'SEC_002',
                        @p_param1 = 'Titularidad Facultad',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
            END
            ELSE IF @tipoEntidadPadreDefecto = 'INSTITUCION'
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM dbo.Administrador 
                    WHERE institucion = @idEntidadPadreDefecto AND usuario = @idUsuarioDefecto
                )
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'SEC_002',
                        @p_param1 = 'Titularidad Institución',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
            END
            ELSE IF @tipoEntidadPadreDefecto = 'SESION'
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 
                    FROM dbo.uv_sesion s
                    INNER JOIN dbo.uv_grupo g ON s.idGrupo = g.id
                    INNER JOIN dbo.uv_docente_identidad di ON di.id = g.idDocente
                    WHERE s.id = @idEntidadPadreDefecto AND di.idUsuario = @idUsuarioDefecto
                )
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'SEC_002',
                        @p_param1 = 'Titularidad Sesión',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
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
