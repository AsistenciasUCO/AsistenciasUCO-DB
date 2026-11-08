USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_cambios_parametro_paginado (CULM-001 D.3, HU168; CONTRACT v2 §4.2, parte diferible)
--
-- Historial de cambios de un parametro (CambioParametro) del mas reciente al mas antiguo: valor anterior y nuevo, motivo,
-- ejecutor, correlacion y fecha UTC. El parametro debe existir (PRM_002). Solo perfil ADMINISTRADOR; [SUPUESTO-D-16]: con
-- mas de una Institucion activa falla con PRM_012. Resultset READ_QUERY_RESULTSET (filas + totalRegistros); las fallas de
-- validacion se propagan con THROW. Sin XACT_ABORT; restaura el SESSION_CONTEXT.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_cambios_parametro_paginado]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idParametro        UNIQUEIDENTIFIER,
    @numeroPagina       INT,
    @tamanoPagina       INT
)
AS
    DECLARE @idUsuario               UNIQUEIDENTIFIER;
    DECLARE @offset                  INT;
    DECLARE @idCorrelacionDefecto    UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @contextoPrevio          SQL_VARIANT = SESSION_CONTEXT(N'idUsuarioEjecutor');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        EXEC dbo.usp_validar_consulta_paginada_interno
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @idCorrelacion = @idCorrelacion,
            @codigoPerfilRequerido = 'ADMINISTRADOR',
            @numeroPagina = @numeroPagina,
            @tamanoPagina = @tamanoPagina,
            @idUsuarioValidado = @idUsuario OUTPUT,
            @offset = @offset OUTPUT,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND (SELECT COUNT(1) FROM dbo.uv_institucion WHERE estaActivaInstitucion = 1) <> 1
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'PRM_012',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', CAST(@idCorrelacionDefecto AS NVARCHAR(50)));
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND (@idParametro IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.uv_parametro WHERE id = @idParametro))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'PRM_002',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', CAST(@idCorrelacionDefecto AS NVARCHAR(50)));
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END;

        SELECT
            c.id,
            c.idParametro,
            c.grupo,
            c.clave,
            c.valorAnterior,
            c.valorNuevo,
            c.motivo,
            c.idUsuarioEjecutor,
            c.nombreEjecutor,
            c.idCorrelacion,
            c.fechaCambioUtc,
            totalRegistros = COUNT(*) OVER()
        FROM dbo.uv_cambio_parametro c
        WHERE c.idParametro = @idParametro
        ORDER BY c.fechaCambioUtc DESC, c.id ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamanoPagina ROWS ONLY;

        EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = @contextoPrevio, @read_only = 0;
    END TRY
    BEGIN CATCH
        EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = @contextoPrevio, @read_only = 0;
        THROW;
    END CATCH;
END;
GO
