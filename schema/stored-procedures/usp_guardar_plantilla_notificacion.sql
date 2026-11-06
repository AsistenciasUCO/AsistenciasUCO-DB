USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_guardar_plantilla_notificacion]
-- Capacidad: Administracion de Plantillas de Notificacion (NOTIF-002B)
-- Ambito: Fachada publica para que el Administrador guarde y active una nueva version de plantilla.
-- Salida:
--   Result set 1 (canonico): (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado)
--   Result set 2 (cuando estadoResultado=1): Fila creada (id, tipo, idioma, version, asunto, cuerpo, activa, creadoEn)
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_guardar_plantilla_notificacion]
(
    @tipo              NVARCHAR(100)    = NULL,
    @idioma            CHAR(2)          = 'es',
    @asunto            NVARCHAR(400)    = NULL,
    @cuerpo            NVARCHAR(MAX)    = NULL,
    @creadoPor         UNIQUEIDENTIFIER = NULL,
    @idCorrelacion     UNIQUEIDENTIFIER = NULL,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ejecutorEfectivo         UNIQUEIDENTIFIER = COALESCE(@idUsuarioEjecutor, @creadoPor);
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@ejecutorEfectivo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio                UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idiomaDef                CHAR(2)          = COALESCE(NULLIF(LOWER(TRIM(@idioma)), ''), 'es');
    DECLARE @tipoDef                  VARCHAR(60)      = NULL;
    DECLARE @asuntoRaw                NVARCHAR(200)    = NULL;
    DECLARE @cuerpoRaw                NVARCHAR(4000)   = NULL;

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000)   = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000)   = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT              = 1;
    DECLARE @idCreado                UNIQUEIDENTIFIER = NULL;

    BEGIN TRY
        -- 1. Validar idCorrelacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- 2. Validar idUsuarioEjecutor obligatorio
        IF @estadoResultado = 1 AND (@ejecutorEfectivo IS NULL OR @idUsuarioEjecutorDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- 3. Validar perfil RBAC ADMINISTRADOR
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

        -- 4. Validar tipo (3..60 caracteres, A-Z0-9_)
        IF @estadoResultado = 1
        BEGIN
            DECLARE @tipoRaw NVARCHAR(100) = UPPER(TRIM(@tipo));
            IF @tipoRaw IS NULL OR LEN(@tipoRaw) < 3 OR LEN(@tipoRaw) > 60 OR @tipoRaw LIKE '%[^A-Z0-9_]%'
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'NTF_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Tipo de plantilla invalido. Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE
            BEGIN
                SET @tipoDef = CAST(@tipoRaw AS VARCHAR(60));
            END
        END

        -- 5. Validar asunto (1..200 caracteres no nulo ni vacio)
        IF @estadoResultado = 1
        BEGIN
            DECLARE @asuntoInput NVARCHAR(400) = TRIM(@asunto);
            IF @asuntoInput IS NULL OR LEN(@asuntoInput) = 0 OR LEN(@asuntoInput) > 200
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'NTF_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Asunto de plantilla invalido (1-200 caracteres). Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE
            BEGIN
                SET @asuntoRaw = CAST(@asuntoInput AS NVARCHAR(200));
            END
        END

        -- 6. Validar cuerpo (1..4000 caracteres no nulo ni vacio)
        IF @estadoResultado = 1
        BEGIN
            DECLARE @cuerpoInput NVARCHAR(MAX) = TRIM(@cuerpo);
            IF @cuerpoInput IS NULL OR LEN(@cuerpoInput) = 0 OR LEN(@cuerpoInput) > 4000
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'NTF_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Cuerpo de plantilla invalido (1-4000 caracteres). Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE
            BEGIN
                SET @cuerpoRaw = CAST(@cuerpoInput AS NVARCHAR(4000));
            END
        END

        -- 7. Validar que el tipo tenga al menos un marcador declarado
        IF @estadoResultado = 1 AND NOT EXISTS (SELECT 1 FROM dbo.PlantillaNotificacionMarcador WHERE tipo = @tipoDef)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'NTF_001',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' El tipo no tiene marcadores declarados. Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- 8. Validar marcadores obligatorios y tokens permitidos en asunto + cuerpo
        IF @estadoResultado = 1
        BEGIN
            DECLARE @textoCompleto NVARCHAR(MAX) = CONCAT(@asuntoRaw, N' ', @cuerpoRaw);

            -- Regla 1: Todo marcador obligatorio debe estar presente
            IF EXISTS (
                SELECT 1
                FROM dbo.PlantillaNotificacionMarcador m
                WHERE m.tipo = @tipoDef
                  AND m.obligatorio = 1
                  AND CHARINDEX(CONCAT(N'{', m.marcador, N'}'), @textoCompleto) = 0
            )
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'NTF_004',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Faltan marcadores obligatorios en el texto. Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END

            -- Regla 2: Todo token {...} debe ser un marcador declarado para el tipo (y llaves balanceadas)
            IF @estadoResultado = 1
            BEGIN
                DECLARE @posAbre INT = CHARINDEX('{', @textoCompleto);
                DECLARE @posCierra INT;
                DECLARE @proximoAbre INT;
                DECLARE @token NVARCHAR(100);
                DECLARE @tokensInvalidos BIT = 0;

                WHILE @posAbre > 0 AND @tokensInvalidos = 0
                BEGIN
                    SET @posCierra = CHARINDEX('}', @textoCompleto, @posAbre + 1);
                    IF @posCierra = 0
                    BEGIN
                        SET @tokensInvalidos = 1;
                        BREAK;
                    END

                    SET @proximoAbre = CHARINDEX('{', @textoCompleto, @posAbre + 1);
                    IF @proximoAbre > 0 AND @proximoAbre < @posCierra
                    BEGIN
                        SET @tokensInvalidos = 1;
                        BREAK;
                    END

                    SET @token = SUBSTRING(@textoCompleto, @posAbre + 1, @posCierra - @posAbre - 1);

                    IF LEN(TRIM(@token)) = 0 OR NOT EXISTS (
                        SELECT 1
                        FROM dbo.PlantillaNotificacionMarcador m
                        WHERE m.tipo = @tipoDef AND m.marcador = @token
                    )
                    BEGIN
                        SET @tokensInvalidos = 1;
                        BREAK;
                    END

                    SET @posAbre = CHARINDEX('{', @textoCompleto, @posCierra + 1);
                END

                IF @tokensInvalidos = 0
                BEGIN
                    IF (LEN(@textoCompleto) - LEN(REPLACE(@textoCompleto, '{', ''))) <> (LEN(@textoCompleto) - LEN(REPLACE(@textoCompleto, '}', '')))
                    BEGIN
                        SET @tokensInvalidos = 1;
                    END
                END

                IF @tokensInvalidos = 1
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'NTF_004',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Contiene marcadores no declarados o llaves invalidas. Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
            END
        END

        -- 9. Insercion atomica delegada
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_guardar_plantilla_notificacion_interno
                @tipo = @tipoDef,
                @idioma = @idiomaDef,
                @asunto = @asuntoRaw,
                @cuerpo = @cuerpoRaw,
                @idUsuarioEjecutor = @idUsuarioEjecutorDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @idCreado = @idCreado OUTPUT,
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
        SET @idCreado = NULL;
    END CATCH

    -- Result set 1: tupla canonica
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;

    -- Result set 2: version creada
    IF @estadoResultado = 1
    BEGIN
        SELECT
            id        = p.id,
            tipo      = p.tipo,
            idioma    = p.idioma,
            [version] = p.[version],
            asunto    = p.asunto,
            cuerpo    = p.cuerpo,
            activa    = p.activa,
            creadoEn  = p.creadoEn
        FROM dbo.PlantillaNotificacion p
        WHERE p.id = @idCreado;
    END
END;
GO
