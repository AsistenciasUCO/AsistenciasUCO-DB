USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU121/HU122 (habilitador compartido con IAM-001): actualiza nombres, apellidos y correo de un usuario existente.
-- El tipo y el numero de documento NO se editan (el documento es el username del proveedor de identidad).
-- El correo debe ser unico excluyendo al propio usuario (VAL_006, leido con UPDLOCK/HOLDLOCK).
-- Sin transaccion propia (corre dentro de la fachada publica).
CREATE OR ALTER PROCEDURE [dbo].[usp_actualizar_datos_usuario_interno]
(
    @idUsuario               UNIQUEIDENTIFIER,
    @primerNombre            NVARCHAR(50),
    @segundoNombre           NVARCHAR(50),
    @primerApellido          NVARCHAR(50),
    @segundoApellido         NVARCHAR(50),
    @correo                  NVARCHAR(100),
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @primerNombreDefecto    NVARCHAR(50)  = TRIM(dbo.ufn_obtener_parametro_texto(@primerNombre, 'GENERAL', 'CADENA_VACIA'));
    DECLARE @segundoNombreDefecto   NVARCHAR(50)  = TRIM(dbo.ufn_obtener_parametro_texto(@segundoNombre, 'GENERAL', 'CADENA_VACIA'));
    DECLARE @primerApellidoDefecto  NVARCHAR(50)  = TRIM(dbo.ufn_obtener_parametro_texto(@primerApellido, 'GENERAL', 'CADENA_VACIA'));
    DECLARE @segundoApellidoDefecto NVARCHAR(50)  = TRIM(dbo.ufn_obtener_parametro_texto(@segundoApellido, 'GENERAL', 'CADENA_VACIA'));
    DECLARE @correoDefecto          NVARCHAR(100) = LOWER(TRIM(dbo.ufn_obtener_parametro_texto(@correo, 'GENERAL', 'CADENA_VACIA')));
BEGIN
    SET NOCOUNT ON;

    SELECT
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;

    BEGIN TRY
        -- Existencia del usuario
        IF @idUsuario IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.uv_usuario WHERE id = @idUsuario)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_001',
                @p_param1 = 'Usuario',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacion);
            SET @estadoResultado = 0;
        END

        -- Textos obligatorios
        IF @estadoResultado = 1 AND (dbo.ufn_validar_texto(@primerNombreDefecto) = 0 OR dbo.ufn_validar_texto(@primerApellidoDefecto) = 0)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_003',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacion);
            SET @estadoResultado = 0;
        END

        -- Textos opcionales
        IF @estadoResultado = 1 AND @segundoNombreDefecto <> '' AND dbo.ufn_validar_texto(@segundoNombreDefecto) = 0
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_004',
                @p_param1 = 'segundo nombre',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacion);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND @segundoApellidoDefecto <> '' AND dbo.ufn_validar_texto(@segundoApellidoDefecto) = 0
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_004',
                @p_param1 = 'segundo apellido',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacion);
            SET @estadoResultado = 0;
        END

        -- Formato del correo
        IF @estadoResultado = 1 AND dbo.ufn_validar_correo(@correoDefecto) = 0
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_005',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacion);
            SET @estadoResultado = 0;
        END

        -- Unicidad del correo excluyendo al propio usuario
        IF @estadoResultado = 1 AND EXISTS (
            SELECT 1 FROM dbo.Usuario WITH (UPDLOCK, HOLDLOCK)
            WHERE LOWER(correo) = @correoDefecto AND id <> @idUsuario)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_006',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacion);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            UPDATE dbo.Usuario
            SET primerNombre = @primerNombreDefecto,
                segundoNombre = @segundoNombreDefecto,
                primerApellido = @primerApellidoDefecto,
                segundoApellido = @segundoApellidoDefecto,
                correo = @correoDefecto
            WHERE id = @idUsuario;
        END
    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacion);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
