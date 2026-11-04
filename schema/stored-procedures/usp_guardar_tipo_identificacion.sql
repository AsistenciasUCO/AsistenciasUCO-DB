USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_guardar_tipo_identificacion (HU153 administracion del catalogo de tipos de documento)
--
-- Solo ADMINISTRADOR (SEC_001). Decision de John (2026-11-04): crear y editar el nombre; sin estado (no se inactiva) y
-- sin DDL.
--   * Alta (@idTipoIdentificacion NULL): codigo obligatorio de 1 a 5 letras A-Z (se guarda en mayusculas: CC, TI, PEP)
--     y unico (GEN_003); nombre de 3 a 50 caracteres y unico sin distinguir mayusculas (GEN_003).
--   * Edicion (con id): el tipo debe existir (GEN_001); solo cambia el nombre (mismas reglas). El codigo es inmutable
--     porque forma parte de la identificacion de los usuarios; si llega, se ignora.
-- Salida canonica: (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado).
-- La escritura y su transaccion viven en usp_guardar_tipo_identificacion_interno.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_guardar_tipo_identificacion]
(
    @idTipoIdentificacion  UNIQUEIDENTIFIER = NULL,
    @codigo                NVARCHAR(20)     = NULL,
    @nombre                NVARCHAR(100)    = NULL,
    @idCorrelacion         UNIQUEIDENTIFIER = NULL,
    @idUsuarioEjecutor     UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGuidVacio              UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idTipoDefecto            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idTipoIdentificacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @esAlta                   BIT;
    DECLARE @idTipoEscritura          UNIQUEIDENTIFIER;
    DECLARE @codigoDef                NVARCHAR(20)     = UPPER(TRIM(@codigo));
    DECLARE @nombreDef                NVARCHAR(100)    = TRIM(@nombre);
    DECLARE @parametroInvalido        NVARCHAR(100);
    DECLARE @mensajeUsuarioResultado  NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado  NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado          BIT = 1;
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        SET @esAlta = IIF(@idTipoDefecto IS NULL OR @idTipoDefecto = @idGuidVacio, 1, 0);
        SET @idTipoEscritura = IIF(@esAlta = 1, NULL, @idTipoDefecto);

        -- PASO 1: Correlacion, ejecutor (GEN_002) y perfil ADMINISTRADOR (SEC_001)
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND (@idUsuarioEjecutorDefecto IS NULL OR @idUsuarioEjecutorDefecto = @idGuidVacio)
        BEGIN
            SET @parametroInvalido = N'idUsuarioEjecutor';
        END

        IF @estadoResultado = 1 AND @parametroInvalido IS NULL
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'ADMINISTRADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2: Formato del codigo (solo en el alta) y del nombre (GEN_002)
        IF @estadoResultado = 1 AND @parametroInvalido IS NULL AND @esAlta = 1
           AND (@codigoDef IS NULL OR LEN(@codigoDef) < 1 OR LEN(@codigoDef) > 5 OR @codigoDef LIKE '%[^A-Z]%')
        BEGIN
            SET @parametroInvalido = N'código del tipo de documento (1 a 5 letras)';
        END

        IF @estadoResultado = 1 AND @parametroInvalido IS NULL AND (@nombreDef IS NULL OR LEN(@nombreDef) < 3 OR LEN(@nombreDef) > 50)
        BEGIN
            SET @parametroInvalido = N'nombre del tipo de documento (3 a 50 caracteres)';
        END

        IF @estadoResultado = 1 AND @parametroInvalido IS NOT NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = @parametroInvalido,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: El tipo existe en la edicion (GEN_001)
        IF @estadoResultado = 1 AND @esAlta = 0
           AND NOT EXISTS (SELECT 1 FROM dbo.uv_tipo_identificacion t WHERE t.id = @idTipoDefecto)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_001',
                @p_param1 = N'tipo de documento',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 4: Unicidad del codigo (alta) y del nombre (excluyendo el propio) (GEN_003)
        IF @estadoResultado = 1
           AND ((@esAlta = 1 AND EXISTS (SELECT 1 FROM dbo.uv_tipo_identificacion t WHERE UPPER(t.TipoIdentificacion) = @codigoDef))
                OR EXISTS (SELECT 1 FROM dbo.uv_tipo_identificacion t
                           WHERE LOWER(t.nombre) = LOWER(@nombreDef) AND (@esAlta = 1 OR t.id <> @idTipoDefecto)))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_003',
                @p_param1 = N'tipo de documento',
                @p_param2 = N'código o nombre',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 5: Escritura (usp_guardar_tipo_identificacion_interno)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_guardar_tipo_identificacion_interno
                @idTipoIdentificacion = @idTipoEscritura,
                @codigo = @codigoDef,
                @nombre = @nombreDef,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
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

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
