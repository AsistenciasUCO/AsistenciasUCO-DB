USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_docente_por_id
--
-- Clasificacion:
--   NON_GOLDEN_PATH_EXTENSION        Consulta individual de docente
--   READ_QUERY_RESULTSET             Retorna datos de identidad y usuario
--
-- Proposito:
--   Recuperar la información consolidada de un docente específico consumiendo
--   uv_docente_identidad y uv_usuario.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_docente_por_id]
(
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idDocente               UNIQUEIDENTIFIER
)
AS
    -- 1. Declaraciones y normalizaciones previas obligatorias (AS ... BEGIN)
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idDocenteDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idDocente, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    -- Control de diagnóstico
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- Paso 1: Validación obligatoria de identificador de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- Paso 2: Validación obligatoria de usuario ejecutor
        IF @estadoResultado = 1 AND (@idUsuarioDefecto IS NULL OR @idUsuarioDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @estadoResultado = 0;
        END

        -- Paso 3: Validación obligatoria de idDocente
        IF @estadoResultado = 1 AND (@idDocenteDefecto IS NULL OR @idDocenteDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'Docente',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- Paso 4: Consulta de docente por identificador
        SELECT
            d.id                    AS id,
            u.id                    AS idUsuario,
            u.idTipoIdentificacion  AS tipoIdentificacionId,
            u.numeroIdentificacion  AS numeroIdentificacion,
            u.primerApellido        AS primerApellido,
            u.segundoApellido       AS segundoApellido,
            u.primerNombre          AS primerNombre,
            u.segundoNombre         AS segundoNombre,
            u.nombreCompleto        AS nombreCompleto,
            u.correo                AS correo,
            u.estaActivoUsuario     AS estaActivoUsuario
        FROM dbo.uv_docente_identidad d
        INNER JOIN dbo.uv_usuario u ON d.idUsuario = u.id
        WHERE d.id = @idDocenteDefecto;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;
END;
GO
