USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- MIGRACION UP 25: CULM-001 D.6 - auditoria de las mutaciones /api/v1/admin/** (HU172; CONTRACT v2 §7.3)
-- Siembra (MERGE) AUDITORIA/PREFIJO_RUTA_ADMINISTRACION y los mensajes AUD_001 y AUD_002, y crea o altera
-- usp_consultar_auditoria_eventos_paginado con @idCorrelacionEvento y @soloAdministracion al final (sin cambios de columnas).
-- Idempotente. El texto del SP es el de schema/stored-procedures (el que despliega deploy_schema.ps1).
-- ============================================================================
PRINT 'MIGRACION 25 UP: auditoria de administracion';
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.6 (CONTRACT v2 §7.3, HU172): prefijo de las rutas de administracion que filtra
-- usp_consultar_auditoria_eventos_paginado con @soloAdministracion = 1. Idempotente y sin pisar el valor administrado
-- (WHEN MATCHED solo actualiza tipoDato y valorDefecto). El grupo AUDITORIA esta en PARAMETROS/GRUPOS_NO_EDITABLES (D.3).
MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    ('AUDITORIA', 'PREFIJO_RUTA_ADMINISTRACION', N'/api/v1/admin/', 'STRING', N'/api/v1/admin/')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET Target.tipoDato = Source.tipoDato, Target.valorDefecto = Source.valorDefecto, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.6 (CONTRACT v2 §7.3, HU172, R-4): mensajes de la consulta de auditoria. Idempotente (MERGE por codigo).
-- AUD_001: [SUPUESTO-D-16], la auditoria no tiene ambito por institucion (el prefijo AUD no existia en las semillas).
-- AUD_002: filtros excluyentes @soloAsistencia y @soloAdministracion; el backend siempre envia los dos explicitos, asi que
-- el usuario no lo ve; vive aqui por ser SSOT de mensajes (desviacion menor del contrato, que solo preveia AUD_001).
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('AUD_001', 'BUSINESS_ERROR',   'MEDIO', N'La consulta de auditoría requiere una sola institución activa.'),
    ('AUD_002', 'VALIDATION_ERROR', 'BAJO',  N'Los filtros de solo asistencia y solo administración no se pueden combinar.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

MERGE INTO [dbo].[CatalogoMensajeTecnico] AS Target
USING (VALUES
    ('AUD_001', 'BUSINESS_ERROR',   'MEDIO', N'SUPUESTO-D-16: hay {} instituciones activas; la auditoría no tiene ámbito por institución.'),
    ('AUD_002', 'VALIDATION_ERROR', 'BAJO',  N'@soloAsistencia = 1 y @soloAdministracion = 1 son excluyentes; el llamador debe enviar los dos parametros explicitos.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
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
-- CULM-001 D.6 (CONTRACT v2 §7.3): al final @idCorrelacionEvento (eventos de una correlacion) y @soloAdministracion
-- (1 = solo rutas que empiezan por AUDITORIA/PREFIJO_RUTA_ADMINISTRACION). @soloAsistencia conserva su defecto 1; T-SQL no
-- distingue un defecto de un valor pasado, asi que el backend envia SIEMPRE los dos parametros explicitos y el SP rechaza
-- (THROW, AUD_002) la combinacion @soloAsistencia = 1 AND @soloAdministracion = 1. [SUPUESTO-D-16]: con mas de una
-- Institucion activa falla con AUD_001 y sin filas (la auditoria no tiene ambito por institucion).
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
    @soloAsistencia     BIT              = 1,
    @idCorrelacionEvento UNIQUEIDENTIFIER = NULL,
    @soloAdministracion BIT              = 0
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
    DECLARE @prefijoAdministracion   NVARCHAR(240) = dbo.ufn_obtener_parametro('AUDITORIA', 'PREFIJO_RUTA_ADMINISTRACION');
    DECLARE @totalInstituciones      INT;
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

        -- PASO 1b (D.6): filtros excluyentes (AUD_002) y [SUPUESTO-D-16] una sola Institucion activa (AUD_001)
        IF @estadoResultado = 1 AND ISNULL(@soloAsistencia, 0) = 1 AND ISNULL(@soloAdministracion, 0) = 1
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'AUD_002',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', CAST(@idCorrelacionDefecto AS NVARCHAR(50)));
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            SELECT @totalInstituciones = COUNT(1) FROM dbo.uv_institucion WHERE estaActivaInstitucion = 1;
            IF @totalInstituciones <> 1
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'AUD_001',
                    @p_param1 = @totalInstituciones,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', CAST(@idCorrelacionDefecto AS NVARCHAR(50)));
                SET @estadoResultado = 0;
            END
        END

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
            AND (ISNULL(@soloAdministracion, 0) = 0 OR (@prefijoAdministracion IS NOT NULL AND LEN(@prefijoAdministracion) > 0
                                                         AND LEFT(a.path, LEN(@prefijoAdministracion)) = @prefijoAdministracion))
            AND (@idCorrelacionEvento IS NULL OR a.correlationId = @idCorrelacionEvento)
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

PRINT CONCAT('MIGRACION 25 UP OK | @@TRANCOUNT=', @@TRANCOUNT);
GO
