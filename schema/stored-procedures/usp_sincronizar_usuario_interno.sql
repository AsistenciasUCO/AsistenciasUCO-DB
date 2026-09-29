USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_sincronizar_usuario_interno]
    (
    @idTipoIdIdentificacion UNIQUEIDENTIFIER,
    @numeroIdentificacion   INT,
    @primerApellido         NVARCHAR(255),
    @segundoApellido        NVARCHAR(255),
    @primerNombre           NVARCHAR(255),
    @segundoNombre          NVARCHAR(255),
    @correo                 NVARCHAR(255),
    @password               NVARCHAR(500),
    @idCorrelacion          UNIQUEIDENTIFIER,
    @estaActivo             BIT = 1,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado        BIT OUTPUT
)
AS
-- 1. Estandarización e inicialización de variables utilizando funciones de catálogo (Sin ISNULL)
DECLARE @idCorrelacionDefecto            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
DECLARE @idTipoIdIdentificacionDefecto   UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idTipoIdIdentificacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
DECLARE @estaActivoDefecto               BIT = dbo.ufn_obtener_parametro_int(@estaActivo, 'GENERAL', 'ENTERO_UNO');

    DECLARE @numeroIdentificacionDefecto     INT = dbo.ufn_obtener_parametro_int(@numeroIdentificacion, 'GENERAL', 'ENTERO_CERO');
    DECLARE @primerApellidoDefecto           NVARCHAR(255) = UPPER(TRIM(dbo.ufn_obtener_parametro_texto(@primerApellido, 'GENERAL', 'CADENA_VACIA')));
    DECLARE @segundoApellidoDefecto          NVARCHAR(255) = UPPER(TRIM(dbo.ufn_obtener_parametro_texto(@segundoApellido, 'GENERAL', 'CADENA_VACIA')));
    DECLARE @primerNombreDefecto             NVARCHAR(255) = UPPER(TRIM(dbo.ufn_obtener_parametro_texto(@primerNombre, 'GENERAL', 'CADENA_VACIA')));
    DECLARE @segundoNombreDefecto            NVARCHAR(255) = UPPER(TRIM(dbo.ufn_obtener_parametro_texto(@segundoNombre, 'GENERAL', 'CADENA_VACIA')));
    DECLARE @correoDefecto                   NVARCHAR(255) = LOWER(TRIM(dbo.ufn_obtener_parametro_texto(@correo, 'GENERAL', 'CADENA_VACIA')));
    DECLARE @passwordDefecto                 NVARCHAR(500) = TRIM(dbo.ufn_obtener_parametro_texto(@password, 'GENERAL', 'CADENA_VACIA'));

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

        -- PASO 2: Validaciones de reglas de negocio en sub-procedimientos
        IF @estadoResultado = 1 
        BEGIN
        EXEC dbo.usp_validar_tipo_identificacion_exista_por_id_interno
                @idTipoId = @idTipoIdIdentificacionDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
    END

        IF @estadoResultado = 1 
        BEGIN
        EXEC dbo.usp_validar_unicidad_usuario_interno 
                @idTipoIdIdentificacion = @idTipoIdIdentificacionDefecto,
                @numeroIdentificacion = @numeroIdentificacionDefecto,
                @correo = @correoDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
    END

        -- PASO 3: Validación de formatos y restricciones utilizando funciones UFN y mensajes del catálogo
        
        -- A. Validar Tipo de Identificación (GUID por defecto)
        IF @estadoResultado = 1 AND @idTipoIdIdentificacionDefecto = TRY_CAST(dbo.ufn_obtener_parametro('GENERAL', 'GUID_DEFECTO_CORRELACION') AS UNIQUEIDENTIFIER)
        BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

        -- B. Validar Número de Identificación
        IF @estadoResultado = 1 AND dbo.ufn_validar_numero(@numeroIdentificacionDefecto) = 0
        BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

        -- C. Validar Textos Obligatorios (Nombre y Apellido)
        IF @estadoResultado = 1 AND (dbo.ufn_validar_texto(@primerNombreDefecto) = 0 OR dbo.ufn_validar_texto(@primerApellidoDefecto) = 0)
        BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_003',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

        -- D. Validar Textos Opcionales (Segundo Nombre y Apellido)
        IF @estadoResultado = 1 AND @segundoNombreDefecto <> '' AND dbo.ufn_validar_texto(@segundoNombreDefecto) = 0
        BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_004',
                @p_param1 = 'segundo nombre',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

        IF @estadoResultado = 1 AND @segundoApellidoDefecto <> '' AND dbo.ufn_validar_texto(@segundoApellidoDefecto) = 0
        BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_004',
                @p_param1 = 'segundo apellido',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

        -- E. Validar Correo Electrónico
        IF @estadoResultado = 1 AND dbo.ufn_validar_correo(@correoDefecto) = 0
        BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_005',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

        -- F. Validar presencia de Password/Hash
        IF @estadoResultado = 1 AND (@passwordDefecto IS NULL OR TRIM(@passwordDefecto) = '')
        BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_007',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

        -- PASO 4: Registro final del usuario en dbo.Usuario
        IF @estadoResultado = 1 
        BEGIN
        INSERT INTO dbo.Usuario
            (
            id, tipoIdIdentificacion, numeroIdentificacion,
            primerApellido, segundoApellido, primerNombre, segundoNombre,
            correo, correoConfirmado, estado, password
            )
        VALUES
            (
                NEWID(), @idTipoIdIdentificacionDefecto, @numeroIdentificacionDefecto,
                @primerApellidoDefecto, @segundoApellidoDefecto,
                @primerNombreDefecto, @segundoNombreDefecto,
                @correoDefecto, 0, @estaActivoDefecto, @passwordDefecto
            );

        EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'Usuario',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 1;
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
