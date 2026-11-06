USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_validar_consulta_paginada_interno (HU112/HU128/HU143/HU157, 2026-11-02)
--
-- Validacion compartida de las consultas paginadas de solo lectura (skill procedimientos-internos-condiciones,
-- REC4 #2: la secuencia repetida ejecutor, RBAC y parametros se extrae a un usp_validar_*_interno con el triplete):
--   * idCorrelacion presente (usp_validar_id_correlacion_esta_presente_interno);
--   * ejecutor obligatorio (VAL_001);
--   * perfil del ejecutor dentro de @codigoPerfilRequerido (SEC_001, usp_validar_permiso_rbac_usuario_interno);
--   * pagina >= 1 y tamano entre 1 y PAGINACION.TAMANO_MAXIMO (PAG_001).
-- Si todo es valido fija el SESSION_CONTEXT del ejecutor para las vistas uv_auth_* (el caller captura el previo y lo
-- restaura) y devuelve el ejecutor normalizado y el desplazamiento de la pagina. El caller hace THROW con el mensaje
-- tecnico cuando @estadoResultado = 0. Solo lectura: no abre transaccion ni usa XACT_ABORT.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_consulta_paginada_interno]
(
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @codigoPerfilRequerido   NVARCHAR(50),
    @numeroPagina            INT,
    @tamanoPagina            INT,
    @idUsuarioValidado       UNIQUEIDENTIFIER OUTPUT,
    @offset                  INT OUTPUT,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGuidVacio          UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @tamanoMaximo         INT = TRY_CAST(dbo.ufn_obtener_parametro('PAGINACION', 'TAMANO_MAXIMO') AS INT);

    SELECT
        @idUsuarioValidado = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION'),
        @offset = NULL,
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: idCorrelacion presente
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Ejecutor obligatorio (VAL_001)
        IF @estadoResultado = 1 AND (@idUsuarioValidado IS NULL OR @idUsuarioValidado = @idGuidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', CAST(@idCorrelacionDefecto AS NVARCHAR(50)));
            SET @estadoResultado = 0;
        END

        -- PASO 3: Perfil del ejecutor (SEC_001)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioValidado,
                @codigoPerfilRequerido = @codigoPerfilRequerido,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: Pagina y tamano validos (PAG_001)
        IF @estadoResultado = 1
           AND (@numeroPagina IS NULL OR @numeroPagina < 1 OR @tamanoPagina IS NULL OR @tamanoPagina < 1
                OR @tamanoMaximo IS NULL OR @tamanoPagina > @tamanoMaximo)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'PAG_001',
                @p_param1 = @numeroPagina,
                @p_param2 = @tamanoPagina,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', CAST(@idCorrelacionDefecto AS NVARCHAR(50)));
            SET @estadoResultado = 0;
        END

        -- PASO 5: Desplazamiento y contexto del ejecutor para las vistas uv_auth_*
        IF @estadoResultado = 1
        BEGIN
            SET @offset = (@numeroPagina - 1) * @tamanoPagina;
            EXEC dbo.usp_establecer_contexto_usuario_ejecutor
                @p_idUsuario = @idUsuarioValidado;
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
