USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_crear_facultad]
-- Historia de Usuario: HU116 (Alta institucional de nueva facultad)
-- Ámbito: Administrador Institucional (Nivel 1 de custodia jerárquica)
-- Estándar: Conforme a procedimientos-externos-condiciones, consulta-a-bd y AGENTS.md
-- Salida Canónica: (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado)
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_crear_facultad]
(
    @id                      UNIQUEIDENTIFIER = NULL,
    @nombre                  NVARCHAR(150)    = NULL,
    @idInstitucion           UNIQUEIDENTIFIER = NULL,
    @idDecano                UNIQUEIDENTIFIER = NULL,
    @idCorrelacion           UNIQUEIDENTIFIER = NULL,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL,
    -- Parámetros de compatibilidad retroactiva:
    @idFacultad              UNIQUEIDENTIFIER = NULL,
    @nombreFacultad          NVARCHAR(150)    = NULL
)
AS
    -- 1. Declaración e inicialización estricta en cabecera (AS ... BEGIN)
    -- Prohibido ISNULL / COALESCE según estándar canónico de procedimientos externos
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idInstitucionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idInstitucion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idDecanoDefecto          UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idDecano, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idFacultadDefecto        UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@id, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @nombreDef                NVARCHAR(150)    = TRIM(@nombre);

    -- Variables locales de respuesta unificada
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 0: Compatibilidad con parámetros retroactivos
        IF @nombreDef IS NULL AND @nombreFacultad IS NOT NULL
        BEGIN
            SET @nombreDef = TRIM(@nombreFacultad);
        END

        IF (@idFacultadDefecto IS NULL OR @idFacultadDefecto = TRY_CAST(dbo.ufn_obtener_parametro('GENERAL', 'GUID_DEFECTO_CORRELACION') AS UNIQUEIDENTIFIER)) AND @idFacultad IS NOT NULL
        BEGIN
            SET @idFacultadDefecto = dbo.ufn_obtener_parametro_guid(@idFacultad, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
        END

        -- PASO 1: Validación del identificador de correlación obligatorio
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 1.5: Validación de presencia del ejecutor y perfil RBAC
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
                @codigoPerfilRequerido = 'ADMINISTRADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2: Resolución de dependencias (Institución y Decano) desde Vistas Canónicas (uv_*)
        IF @estadoResultado = 1 AND (@idInstitucionDefecto IS NULL OR @idInstitucionDefecto = TRY_CAST(dbo.ufn_obtener_parametro('GENERAL', 'GUID_DEFECTO_CORRELACION') AS UNIQUEIDENTIFIER))
        BEGIN
            SELECT TOP 1 @idInstitucionDefecto = id
            FROM dbo.uv_institucion
            WHERE estaActivaInstitucion = 1
            ORDER BY id ASC;

            IF @idInstitucionDefecto IS NULL
            BEGIN
                SELECT TOP 1 @idInstitucionDefecto = id
                FROM dbo.uv_institucion
                ORDER BY id ASC;
            END
        END

        -- PASO 3: Validaciones de Negocio
        -- 3.1 Validación de Nombre Obligatorio y Longitud (3 a 50 caracteres)
        IF @estadoResultado = 1 AND (@nombreDef IS NULL OR LEN(@nombreDef) < 3 OR LEN(@nombreDef) > 50)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'Nombre de Facultad',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Longitud invalida (3-50). Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- 3.2 Validación de Unicidad de Nombre (Consumo de uv_facultad, sin SELECT a tablas físicas)
        IF @estadoResultado = 1 AND EXISTS (SELECT 1 FROM dbo.uv_facultad WHERE LOWER(nombreFacultad) = LOWER(@nombreDef))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_003',
                @p_param1 = 'Facultad',
                @p_param2 = 'nombre',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Conflicto de unicidad para nombre: ', @nombreDef, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- 3.3 Validación de Integridad Referencial: Institución (Consumo de uv_institucion)
        IF @estadoResultado = 1 AND (@idInstitucionDefecto IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.uv_institucion WHERE id = @idInstitucionDefecto))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_001',
                @p_param1 = 'Institucion',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- 3.4 Validación de Decano Obligatorio e Integridad Referencial (Sin NULLs por regla relacional de Facultad)
        IF @estadoResultado = 1 AND (@idDecanoDefecto IS NULL OR @idDecanoDefecto = TRY_CAST(dbo.ufn_obtener_parametro('GENERAL', 'GUID_DEFECTO_CORRELACION') AS UNIQUEIDENTIFIER))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'Decano',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Decano obligatorio. Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND NOT EXISTS (SELECT 1 FROM dbo.uv_decano_identidad WHERE id = @idDecanoDefecto)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_001',
                @p_param1 = 'Decano',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Decano inexistente. Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 4: Delegación al procedimiento interno de persistencia (*_interno)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_crear_facultad_interno
                @id = @idFacultadDefecto,
                @nombre = @nombreDef,
                @idInstitucion = @idInstitucionDefecto,
                @idDecano = @idDecanoDefecto,
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

    -- BLOQUE FINAL OBLIGATORIO: Retorno canónico de 4 columnas para JPA / ProcedureResultMapper
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
