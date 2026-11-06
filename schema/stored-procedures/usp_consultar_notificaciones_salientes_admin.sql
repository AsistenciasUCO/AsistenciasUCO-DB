USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_consultar_notificaciones_salientes_admin]
-- Capacidad: Monitor de Cola Outbox (TD-069)
-- Ambito: Fachada publica para que el Administrador consulte la cola outbox y su resumen.
-- Salida:
--   Result set 1 (canonico): (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado)
--   Result set 2 (cuando estadoResultado=1): Notificaciones paginadas con totalRegistros (creadoEn DESC)
--   Result set 3 (cuando estadoResultado=1): Resumen de totales por estado (codigoEstado, total)
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_notificaciones_salientes_admin]
(
    @estado            NVARCHAR(40)     = NULL,
    @codigoEstado      NVARCHAR(40)     = NULL,
    @tipo              NVARCHAR(60)     = NULL,
    @numeroPagina      INT              = 1,
    @tamanoPagina      INT              = 20,
    @idCorrelacion     UNIQUEIDENTIFIER = NULL,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio                UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoEstadoDef          NVARCHAR(40)     = COALESCE(NULLIF(TRIM(@estado), ''), NULLIF(TRIM(@codigoEstado), ''));
    DECLARE @tipoDef                  NVARCHAR(60)     = NULLIF(TRIM(@tipo), '');
    DECLARE @numPagDef                INT              = COALESCE(@numeroPagina, 1);
    DECLARE @tamPagDef                INT              = COALESCE(@tamanoPagina, 20);

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    BEGIN TRY
        -- 1. Validar idCorrelacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- 2. El usuario ejecutor es obligatorio: sin el no se consulta (nunca se omite el RBAC)
        IF @estadoResultado = 1 AND @idUsuarioEjecutorDefecto = @guidVacio
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

        -- 3. Validar parametros de paginacion (pagina >= 0, tamano entre 1 y 100)
        IF @estadoResultado = 1 AND (@numPagDef < 0 OR @tamPagDef < 1 OR @tamPagDef > 100)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'PAG_001',
                @p_param1 = @numPagDef,
                @p_param2 = @tamPagDef,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Paginacion fuera de rango (1-100). Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- 5. Mensaje de exito
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'NotificacionSaliente',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
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

    -- Result set 1: tupla canonica
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;

    -- Result sets 2 y 3: lista paginada y resumen
    IF @estadoResultado = 1
    BEGIN
        EXEC dbo.usp_consultar_notificaciones_salientes_admin_interno
            @codigoEstado = @codigoEstadoDef,
            @tipo         = @tipoDef,
            @numeroPagina = @numPagDef,
            @tamanoPagina = @tamPagDef;
    END
END;
GO
