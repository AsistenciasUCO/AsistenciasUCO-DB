USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- MIGRACION DOWN 25: CULM-001 D.6 - revierte la auditoria de administracion (CONTRACT v2 §7.3, §14.2). Idempotente.
--   1. Restaura el texto anterior de usp_consultar_auditoria_eventos_paginado (copiado literal de la linea base f2f1010).
--   2. Borra AUDITORIA/PREFIJO_RUTA_ADMINISTRACION solo si valor = valorDefecto y los mensajes AUD_001 y AUD_002.
-- ============================================================================
PRINT 'MIGRACION 25 DOWN: auditoria de administracion';
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_auditoria_eventos_paginado (HU172 auditoria de cambios de asistencia)
--
-- Eventos de auditoria (quien, cuando, accion, recurso y resultado) de mas reciente a mas antiguo. No hay valores
-- antes/despues: AuditoriaEvento no los guarda (decision de John, 2026-11-04: se consulta el rastro existente).
-- Filtros: rango [@desdeUtc, @hastaUtc) obligatorio (el backend lo acota a 90 dias y por defecto a los ultimos 7),
-- accion, tipo e id de recurso, usuario, resultado y @soloAsistencia (1 = solo acciones de asistencia).
--
-- Resultset: READ_QUERY_RESULTSET (filas + totalRegistros), NO el resultset canonico de 4 columnas
-- de los comandos. Las fallas de validacion se propagan con THROW (VAL_001 / SEC_001 / PAG_001 / GEN_002).
-- Ambito: solo perfil ADMINISTRADOR (la auditoria es de la plataforma; AuditoriaEvento no tiene institucion).
-- SESSION_CONTEXT: lo fija el interno de validacion; se captura el previo y SIEMPRE se restaura.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_auditoria_eventos_paginado]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @numeroPagina       INT,
    @tamanoPagina       INT,
    @desdeUtc           DATETIMEOFFSET(7),
    @hastaUtc           DATETIMEOFFSET(7),
    @accion             VARCHAR(120)     = NULL,
    @tipoRecurso        VARCHAR(120)     = NULL,
    @idRecurso          NVARCHAR(120)    = NULL,
    @idUsuarioActor     UNIQUEIDENTIFIER = NULL,
    @resultado          VARCHAR(20)      = NULL,
    @soloAsistencia     BIT              = 1
)
AS
    DECLARE @idUsuario               UNIQUEIDENTIFIER;
    DECLARE @offset                  INT;
    DECLARE @idCorrelacionDefecto    UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @accionFiltro            VARCHAR(120) = NULLIF(TRIM(@accion), '');
    DECLARE @tipoRecursoFiltro       VARCHAR(120) = NULLIF(TRIM(@tipoRecurso), '');
    DECLARE @idRecursoFiltro         NVARCHAR(120) = NULLIF(TRIM(@idRecurso), '');
    DECLARE @resultadoFiltro         VARCHAR(20) = NULLIF(TRIM(@resultado), '');
    DECLARE @idActorFiltro           NVARCHAR(120) = CONVERT(NVARCHAR(120), @idUsuarioActor);
    DECLARE @contextoPrevio          SQL_VARIANT = SESSION_CONTEXT(N'idUsuarioEjecutor');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
BEGIN
    SET NOCOUNT ON;
    -- Consulta de solo lectura: sin XACT_ABORT para no invalidar la transaccion del llamador ante un THROW de validacion.
    BEGIN TRY
        -- PASO 1: Correlacion, ejecutor, perfil ADMINISTRADOR y paginacion; fija el contexto (usp_validar_consulta_paginada_interno)
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

        -- PASO 2: Rango de fechas obligatorio (GEN_002)
        IF @estadoResultado = 1 AND (@desdeUtc IS NULL OR @hastaUtc IS NULL)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'rango de fechas',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', CAST(@idCorrelacionDefecto AS NVARCHAR(50)));
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END;

        -- PASO 3: Consulta y retorno de resultados
        SELECT
            a.id,
            a.occurredAt,
            a.actorId,
            a.actorType,
            a.nombreActor,
            a.action,
            a.resourceType,
            a.resourceId,
            a.result,
            a.correlationId,
            a.httpMethod,
            a.path,
            a.httpStatus,
            a.clientIp,
            a.errorCode,
            a.metadata,
            a.esAccionAsistencia,
            totalRegistros = COUNT(*) OVER()
        FROM dbo.uv_auditoria_evento a
        WHERE
            a.occurredAt >= @desdeUtc
            AND a.occurredAt < @hastaUtc
            AND (@soloAsistencia = 0 OR a.esAccionAsistencia = 1)
            AND (@accionFiltro IS NULL OR a.action = @accionFiltro)
            AND (@tipoRecursoFiltro IS NULL OR a.resourceType = @tipoRecursoFiltro)
            AND (@idRecursoFiltro IS NULL OR a.resourceId = @idRecursoFiltro)
            AND (@idActorFiltro IS NULL OR a.actorId = @idActorFiltro)
            AND (@resultadoFiltro IS NULL OR a.result = @resultadoFiltro)
        ORDER BY a.occurredAt DESC, a.id ASC
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

DELETE FROM dbo.CatalogoParametro WHERE grupo = 'AUDITORIA' AND clave = 'PREFIJO_RUTA_ADMINISTRACION' AND valor = valorDefecto;
GO
DELETE FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('AUD_001', 'AUD_002');
DELETE FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('AUD_001', 'AUD_002');
GO
PRINT CONCAT('MIGRACION 25 DOWN OK | @@TRANCOUNT=', @@TRANCOUNT);
GO
