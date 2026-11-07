-- ============================================================================
-- MIGRACION UP 20: CULM-001 D.1 - plazo de excusas de HU026B (CONTRACT D §2.2)
-- Crea o altera, en este orden: mensajes REV_020/REV_025 (MERGE), ufn_calcular_fecha_limite_justificacion,
-- usp_internal_validar_plazo_justificacion, uv_sesion_estudiante_reclamo, usp_consultar_sesiones_materia_estudiante y
-- los SP de radicacion v1 y v2 (plazo tras la reejecucion idempotente; fecha local de radicacion), y concede EXECUTE/SELECT
-- al rol runtime. Idempotente (CREATE OR ALTER / MERGE). Sin cambios de tablas. Down: 20_..._down.sql (aborta si D.2 esta aplicada).
-- ============================================================================
PRINT 'MIGRACION 20 UP: plazo de excusas (D.1)';
GO
-- ---- schema/seed/51_culm001_d1_mensajes.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.1 (CONTRACT §2.2, HU026B): mensajes del plazo de excusas. Idempotente (MERGE por codigo).
--   REV_020  la radicacion llega despues del limite (el mensaje de usuario informa la ultima fecha local admitida)
--   REV_025  falta ASISTENCIA/DIAS_LIMITE_JUSTIFICACION o TIEMPO/ZONA_HORARIA_SQLSERVER: no se puede validar el plazo
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('REV_020', 'BUSINESS_ERROR',  'MEDIO', N'El plazo para justificar esta inasistencia venció el {}.'),
    ('REV_025', 'TECHNICAL_ERROR', 'ALTO',  N'No es posible validar el plazo de justificación en este momento.')
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
    ('REV_020', 'BUSINESS_ERROR',  'MEDIO', N'HU026B: instante {} >= límite {} (ASISTENCIA/DIAS_LIMITE_JUSTIFICACION={}).'),
    ('REV_025', 'TECHNICAL_ERROR', 'ALTO',  N'HU026B: falta ASISTENCIA/DIAS_LIMITE_JUSTIFICACION o TIEMPO/ZONA_HORARIA_SQLSERVER.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
-- ---- schema/functions/ufn_calcular_fecha_limite_justificacion.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- ufn_calcular_fecha_limite_justificacion (CULM-001 D.1, HU026B; CONTRACT §0 [SUPUESTO-D-01], §2.2)
--
-- Limite EXCLUSIVO (UTC) para radicar una excusa: la medianoche local (TIEMPO/ZONA_HORARIA_SQLSERVER) del dia
--   fecha local de fin de la sesion + N + 1,   N = ASISTENCIA/DIAS_LIMITE_JUSTIFICACION.
-- Una radicacion se admite mientras SYSUTCDATETIME() < limite. Dias calendario locales completos: una sesion que termina
-- a las 23:30 no pierde un dia. Ejemplo (N = 5, Bogota): fin el miercoles 2026-11-04 a las 08:00 => limite 2026-11-10 00:00
-- local, es decir se puede justificar hasta el lunes 2026-11-09 a las 23:59:59.
-- Devuelve NULL si @fechaHoraFinSesionUtc es NULL, si N falta, no es entero o es negativo, o si la zona falta o no existe
-- en sys.time_zone_info: el llamador decide (REV_025). Sin escrituras. El texto vacio del parametro cuenta como ausente
-- (ufn_obtener_parametro devuelve '' para un parametro inexistente y CAST('' AS INT) seria 0).
-- ============================================================================
CREATE OR ALTER FUNCTION [dbo].[ufn_calcular_fecha_limite_justificacion] (
    @fechaHoraFinSesionUtc DATETIME2(7)
)
RETURNS DATETIME2(7)
AS
BEGIN
    IF @fechaHoraFinSesionUtc IS NULL
        RETURN NULL;

    DECLARE @textoDias NVARCHAR(MAX) = dbo.ufn_obtener_parametro_texto(NULL, 'ASISTENCIA', 'DIAS_LIMITE_JUSTIFICACION');
    DECLARE @textoZona NVARCHAR(MAX) = dbo.ufn_obtener_parametro_texto(NULL, 'TIEMPO', 'ZONA_HORARIA_SQLSERVER');
    DECLARE @dias INT = TRY_CAST(@textoDias AS INT);

    IF @textoDias IS NULL OR @textoDias = N'' OR @dias IS NULL OR @dias < 0
        RETURN NULL;
    IF @textoZona IS NULL OR @textoZona = N'' OR NOT EXISTS (SELECT 1 FROM sys.time_zone_info WHERE name = @textoZona)
        RETURN NULL;

    DECLARE @zona NVARCHAR(128) = CAST(@textoZona AS NVARCHAR(128));
    DECLARE @fechaLocalFin DATE = CAST((@fechaHoraFinSesionUtc AT TIME ZONE 'UTC') AT TIME ZONE @zona AS DATE);

    -- Defensa de desbordamiento: el limite debe seguir siendo una fecha valida.
    IF @dias + 1 > DATEDIFF(DAY, @fechaLocalFin, CAST('9999-12-30' AS DATE))
        RETURN NULL;

    DECLARE @limiteLocal DATETIME2(7) = CAST(DATEADD(DAY, @dias + 1, @fechaLocalFin) AS DATETIME2(7));
    RETURN CAST((@limiteLocal AT TIME ZONE @zona) AT TIME ZONE 'UTC' AS DATETIME2(7));
END;
GO
-- ---- schema/stored-procedures/usp_internal_validar_plazo_justificacion.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_internal_validar_plazo_justificacion (CULM-001 D.1, HU026B; CONTRACT §2.2)
--
-- Nucleo interno: NO se concede a ningun rol. Valida que la radicacion de una excusa este dentro del plazo de la sesion.
--   * limite NULL (falta ASISTENCIA/DIAS_LIMITE_JUSTIFICACION o TIEMPO/ZONA_HORARIA_SQLSERVER, o la sesion no existe) => REV_025
--   * SYSUTCDATETIME() >= limite                                                                                       => REV_020
-- Devuelve el limite en @fechaLimiteUtc (NULL si no se pudo calcular). Sin escrituras ni transacciones: lo invocan los
-- SP de radicacion v1 y v2, que deciden el commit o rollback. En exito deja intactos los mensajes y @estadoResultado.
-- REV_020 informa la ULTIMA fecha local admitida (yyyy-MM-dd); su mensaje tecnico lleva instante, limite y N.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_internal_validar_plazo_justificacion]
(
    @idSesion                UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @fechaLimiteUtc          DATETIME2(7)   OUTPUT,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT            OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @fin DATETIME2(7) = (SELECT s.fechaHoraFin FROM dbo.Sesion s WHERE s.id = @idSesion);
    DECLARE @ahora DATETIME2(7) = SYSUTCDATETIME();
    DECLARE @dias NVARCHAR(20), @ultimoDia NVARCHAR(10), @instante NVARCHAR(40), @limiteTexto NVARCHAR(40), @descartado NVARCHAR(4000);
    DECLARE @zona NVARCHAR(128) = CAST(dbo.ufn_obtener_parametro_texto(NULL, 'TIEMPO', 'ZONA_HORARIA_SQLSERVER') AS NVARCHAR(128));

    SET @fechaLimiteUtc = dbo.ufn_calcular_fecha_limite_justificacion(@fin);

    IF @fechaLimiteUtc IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'REV_025',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacion);
        SET @estadoResultado = 0;
        RETURN;
    END

    IF @ahora >= @fechaLimiteUtc
    BEGIN
        SET @dias = CONVERT(NVARCHAR(20), dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'DIAS_LIMITE_JUSTIFICACION'));
        SET @ultimoDia = CONVERT(NVARCHAR(10), DATEADD(DAY, -1, CAST((@fechaLimiteUtc AT TIME ZONE 'UTC') AT TIME ZONE @zona AS DATE)), 23);
        SET @instante = CONVERT(NVARCHAR(40), @ahora, 126);
        SET @limiteTexto = CONVERT(NVARCHAR(40), @fechaLimiteUtc, 126);
        -- El mensaje de usuario usa solo {1} (ultimo dia local); el tecnico usa {1}=instante, {2}=limite, {3}=N.
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'REV_020', @p_param1 = @ultimoDia,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @descartado OUTPUT;
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'REV_020', @p_param1 = @instante, @p_param2 = @limiteTexto, @p_param3 = @dias,
            @mensajeUsuarioResultado = @descartado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacion);
        SET @estadoResultado = 0;
    END
END;
GO
-- ---- schema/views/uv_sesion_estudiante_reclamo.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.1 (CONTRACT §2.2, DEC-044 (2); HU026B): una fila por (sesion, matricula del estudiante) con la fecha limite
-- para justificar. Sobre uv_sesion_v2 + uv_sesion_estado (B.1) + uv_estudiante_grupo; uv_sesion (congelada) no se toca.
--   fechaLimiteJustificacionUtc = ufn_calcular_fecha_limite_justificacion(fechaHoraFin)  (limite exclusivo; NULL si falta
--                                 ASISTENCIA/DIAS_LIMITE_JUSTIFICACION o TIEMPO/ZONA_HORARIA_SQLSERVER)
--   plazoJustificacionVigente   = 1 solo si la sesion NO esta cancelada y SYSUTCDATETIME() < limite
-- idAsignatura, codigo, numeroSemana, codigoGrupo, nombreGrupo y codigoEstadoEstudiante completan las columnas que hoy
-- entrega la consulta de sesiones de la materia y permiten al SP filtrar la matricula inscrita.
CREATE OR ALTER VIEW [dbo].[uv_sesion_estudiante_reclamo]
AS
SELECT  idSesion = s.id,
        idGrupo = s.idGrupo,
        idEstudianteGrupo = eg.id,
        idEstudiante = eg.idEstudiante,
        codigoEstadoEstudiante = eg.codigoEstadoEstudiante,
        idAsignatura = g.idAsignatura,
        numero = s.numero,
        nombre = s.nombre,
        codigo = s.codigo,
        numeroSemana = s.numeroSemana,
        codigoGrupo = s.codigoGrupo,
        nombreGrupo = s.nombreGrupo,
        fechaHoraInicio = s.fechaHoraInicio,
        fechaHoraFin = s.fechaHoraFin,
        estaCancelada = se.estaCancelada,
        fechaLimiteJustificacionUtc = lim.fechaLimiteUtc,
        plazoJustificacionVigente = CAST(IIF(se.estaCancelada = 0 AND lim.fechaLimiteUtc IS NOT NULL
                                             AND SYSUTCDATETIME() < lim.fechaLimiteUtc, 1, 0) AS BIT)
FROM    dbo.uv_sesion_v2 s
INNER JOIN dbo.uv_sesion_estado se
ON      se.idSesion = s.id
INNER JOIN dbo.uv_estudiante_grupo eg
ON      eg.idGrupo = s.idGrupo
INNER JOIN dbo.uv_grupo g
ON      g.id = s.idGrupo
CROSS APPLY (SELECT fechaLimiteUtc = dbo.ufn_calcular_fecha_limite_justificacion(s.fechaHoraFin)) lim;
GO
-- ---- schema/stored-procedures/usp_consultar_sesiones_materia_estudiante.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_sesiones_materia_estudiante (CULM-001 D.1, HU026B; CONTRACT §2.2, DEC-044 (2))
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW 51000 si la validacion falla: GEN_002, SEC_001,
-- PAG_001). Sesiones de GET /api/v1/estudiante/materias/{materiaId}/sesiones. RBAC ESTUDIANTE; el ambito esta dentro del SP:
-- solo las matriculas del ejecutor con el estado de MATRICULA/ESTADO_INSCRITA en los grupos de la asignatura @idMateria
-- (los grupos I, CI, CVP y F no devuelven filas: cambio intencional de DEC-022 §3; una materia ajena devuelve 0 filas).
-- Columnas: id, nombre, numero, codigo, numeroSemana, idGrupo, codigoGrupo, nombreGrupo, fechaHoraInicio, fechaHoraFin
-- (las de la consulta que sustituye), fechaLimiteJustificacionUtc, plazoJustificacionVigente y totalRegistros
-- (COUNT(1) OVER()). Orden numero, fechaHoraInicio. Paginacion: @numeroPagina >= 1 y @tamanoPagina entre 1 y
-- PAGINACION/TAMANO_MAXIMO. Solo lectura.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_sesiones_materia_estudiante]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idMateria         UNIQUEIDENTIFIER,
    @numeroPagina      INT = 1,
    @tamanoPagina      INT = 100
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @tamanoMaximo         INT = dbo.ufn_obtener_parametro_int(NULL, 'PAGINACION', 'TAMANO_MAXIMO');
    DECLARE @codigoInscrita       NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @offset INT;
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500);

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 1 AND @idMateria IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idMateria',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 1
        EXEC dbo.usp_validar_permiso_rbac_usuario_interno
            @idUsuario = @idUsuarioDefecto, @codigoPerfilRequerido = 'ESTUDIANTE', @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1
       AND (@numeroPagina IS NULL OR @numeroPagina < 1 OR @tamanoPagina IS NULL OR @tamanoPagina < 1
            OR @tamanoMaximo IS NULL OR @tamanoPagina > @tamanoMaximo)
    BEGIN
        SELECT @p1 = CONVERT(NVARCHAR(20), @numeroPagina), @p2 = CONVERT(NVARCHAR(20), @tamanoPagina);
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'PAG_001', @p_param1 = @p1, @p_param2 = @p2,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    SET @offset = (@numeroPagina - 1) * @tamanoPagina;
    SELECT
        id                          = r.idSesion,
        nombre                      = r.nombre,
        numero                      = r.numero,
        codigo                      = r.codigo,
        numeroSemana                = r.numeroSemana,
        idGrupo                     = r.idGrupo,
        codigoGrupo                 = r.codigoGrupo,
        nombreGrupo                 = r.nombreGrupo,
        fechaHoraInicio             = r.fechaHoraInicio,
        fechaHoraFin                = r.fechaHoraFin,
        fechaLimiteJustificacionUtc = r.fechaLimiteJustificacionUtc,
        plazoJustificacionVigente   = r.plazoJustificacionVigente,
        totalRegistros              = COUNT(1) OVER()
    FROM dbo.uv_sesion_estudiante_reclamo r
    INNER JOIN dbo.Estudiante e ON e.id = r.idEstudiante
    WHERE e.usuario = @idUsuarioDefecto
      AND r.idAsignatura = @idMateria
      AND r.codigoEstadoEstudiante = @codigoInscrita
    ORDER BY r.numero ASC, r.fechaHoraInicio ASC, r.idSesion ASC
    OFFSET @offset ROWS FETCH NEXT @tamanoPagina ROWS ONLY;
END;
GO
-- ---- schema/stored-procedures/usp_radicar_solicitud_revision_asistencia.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_radicar_solicitud_revision_asistencia]
(
    @idEstudiante       UNIQUEIDENTIFIER,
    @idSesion           UNIQUEIDENTIFIER,
    @categoria          NVARCHAR(50),
    @justificacion      NVARCHAR(MAX),
    @soporteNombre      NVARCHAR(250),
    @soporteUrl         NVARCHAR(500),
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idEstudianteDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idEstudiante, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto          UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @categoriaDefecto         NVARCHAR(50)     = TRIM(@categoria);
    DECLARE @justificacionDefecto     NVARCHAR(MAX)    = TRIM(@justificacion);
    DECLARE @soporteNombreDefecto     NVARCHAR(250)    = TRIM(@soporteNombre);
    DECLARE @soporteUrlDefecto        NVARCHAR(500)    = TRIM(@soporteUrl);

    DECLARE @idAsistencia         UNIQUEIDENTIFIER;
    DECLARE @idEstudianteGrupo    UNIQUEIDENTIFIER;
    DECLARE @nuevaSolicitudId     UNIQUEIDENTIFIER = NEWID();
    DECLARE @nombreSolicitud      NVARCHAR(50);
    DECLARE @idEstadoPendiente    UNIQUEIDENTIFIER;
    DECLARE @fechaLimiteUtc       DATETIME2(7);
    DECLARE @zonaLocal            NVARCHAR(128);

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    -- REC3 (auditoria BD 2026-10-28): cualquier error o cancelacion del cliente revierte la transaccion completa.
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: Validación de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 1.5: Validación de perfil RBAC del usuario ejecutor si es suministrado
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
                @codigoPerfilRequerido = 'ESTUDIANTE',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2: Validar existencia del estudiante
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_estudiante_exista_por_id_interno
                @idEstudiante = @idEstudianteDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: Validar existencia de la sesión
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_sesion_exista_por_id_interno
                @idSesion = @idSesionDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: Validar pertenencia del estudiante a la sesión
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno
                @idEstudiante = @idEstudianteDefecto,
                @idSesion = @idSesionDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4.5 (CULM-001 D.1, HU026B): plazo de excusas (REV_020 vencido, REV_025 sin parametros); antes de toda escritura.
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_internal_validar_plazo_justificacion
                @idSesion = @idSesionDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @fechaLimiteUtc = @fechaLimiteUtc OUTPUT,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 5: Radicación atómica transaccional de la solicitud
        IF @estadoResultado = 1
        BEGIN
            SET @zonaLocal = CAST(dbo.ufn_obtener_parametro_texto(NULL, 'TIEMPO', 'ZONA_HORARIA_SQLSERVER') AS NVARCHAR(128));
            SELECT TOP 1 @idEstudianteGrupo = eg.id
            FROM dbo.Sesion s
            INNER JOIN dbo.EstudianteGrupo eg ON eg.grupo = s.grupo
            WHERE s.id = @idSesionDefecto AND eg.estudiante = @idEstudianteDefecto;

            SELECT TOP 1 @idAsistencia = id
            FROM dbo.Asistencia
            WHERE estudianteGrupo = @idEstudianteGrupo AND sesion = @idSesionDefecto;

            SELECT TOP 1 @idEstadoPendiente = id FROM dbo.Estado WHERE codigo IN ('P', 'PEND') ORDER BY id ASC;
            IF @idEstadoPendiente IS NULL
            BEGIN
                SELECT TOP 1 @idEstadoPendiente = id FROM dbo.Estado ORDER BY id ASC;
            END

            SET @nombreSolicitud = CONCAT('REC-', UPPER(SUBSTRING(CAST(@nuevaSolicitudId AS VARCHAR(36)), 1, 8)));

            BEGIN TRANSACTION;

            IF @idAsistencia IS NULL
            BEGIN
                SET @idAsistencia = NEWID();
                INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion)
                VALUES (@idAsistencia, @idEstudianteGrupo, @idSesionDefecto);
            END

            INSERT INTO dbo.SolicitudRevisionAsistencia (
                id, nombre, asistencia, fecha, estado,
                justificacionSolicitud, justificacionRespuesta
            )
            VALUES (
                @nuevaSolicitudId,
                @nombreSolicitud,
                @idAsistencia,
                CAST((SYSUTCDATETIME() AT TIME ZONE 'UTC') AT TIME ZONE @zonaLocal AS DATE),
                @idEstadoPendiente,
                CASE WHEN @justificacionDefecto IS NOT NULL AND @justificacionDefecto <> '' THEN @justificacionDefecto ELSE 'Solicitud de revisión de asistencia radicada por estudiante.' END,
                ''
            );

            COMMIT TRANSACTION;

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'SolicitudRevisionAsistencia',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

    END TRY
    BEGIN CATCH
        -- REC3: solo se revierte si hay una transaccion viva (XACT_STATE <> 0); evita un segundo error en el CATCH.
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- BLOQUE FINAL: Retorno unificado de resultados
    SELECT 
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
-- ---- schema/stored-procedures/usp_radicar_solicitud_revision_asistencia_v2.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_radicar_solicitud_revision_asistencia_v2  (LB-004D, W2)
--
-- Radica la solicitud de revision y, si se indica @idArchivoSoporte, vincula el soporte
-- (DRAFT -> ATTACHED) en la MISMA transaccion. La v1 permanece intacta.
--
--   * Sin @soporteNombre/@soporteUrl: la v2 no confia en datos de soporte del cliente.
--   * Verifica que @idEstudiante pertenezca a @idUsuarioEjecutor (defensa en profundidad, H-01).
--   * El soporte es opcional: sin @idArchivoSoporte el comportamiento es el de la v1.
--   * Soporte inexistente, ajeno, ya vinculado u huerfano => ARC_001 identico, sin escritura.
--   * Reintento con la misma correlacion tras un exito => exito idempotente (sin segunda solicitud).
--   * Carrera por el mismo fileId: el UPDLOCK sobre la fila serializa; la segunda ve ATTACHED => ARC_001.
--   * CULM-001 D.1 (HU026B): el plazo de excusas se valida DESPUES de la reejecucion idempotente por correlacion y antes de
--     cualquier escritura (usp_internal_validar_plazo_justificacion: REV_020 vencido, REV_025 sin parametros). Un reintento
--     legitimo con la misma correlacion tras el vencimiento sigue devolviendo el exito original.
--   * `fecha` es la fecha LOCAL de radicacion (TIEMPO/ZONA_HORARIA_SQLSERVER), no la fecha UTC del servidor.
--
-- Resultset: MUTATION_COMMAND_RESULTSET (4 columnas canonicas).
-- Ownership transaccional: transaccion propia o SAVE TRANSACTION si el llamador ya tiene una.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_radicar_solicitud_revision_asistencia_v2]
(
    @idEstudiante       UNIQUEIDENTIFIER,
    @idSesion           UNIQUEIDENTIFIER,
    @categoria          NVARCHAR(50),
    @justificacion      NVARCHAR(MAX),
    @idArchivoSoporte   UNIQUEIDENTIFIER = NULL,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idEstudianteDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idEstudiante, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto          UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio                UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @justificacionDefecto     NVARCHAR(MAX)    = TRIM(@justificacion);

    DECLARE @idAsistencia         UNIQUEIDENTIFIER;
    DECLARE @idEstudianteGrupo    UNIQUEIDENTIFIER;
    DECLARE @nuevaSolicitudId     UNIQUEIDENTIFIER = NEWID();
    DECLARE @nombreSolicitud      NVARCHAR(50);
    DECLARE @idEstadoPendiente    UNIQUEIDENTIFIER;

    DECLARE @tieneSoporte         BIT = IIF(@idArchivoSoporte IS NULL, 0, 1);
    DECLARE @propietarioSoporte   UNIQUEIDENTIFIER;
    DECLARE @estadoSoporte        VARCHAR(10);
    DECLARE @correlacionAdjuncion UNIQUEIDENTIFIER;
    DECLARE @esReintento          BIT = 0;
    DECLARE @fechaLimiteUtc       DATETIME2(7);
    DECLARE @zonaLocal            NVARCHAR(128);
    DECLARE @fechaLocalRadicacion DATE;
    DECLARE @filasActualizadas    INT;
    DECLARE @escrituraRealizada   BIT = 0;

    DECLARE @conteoTransaccionesInicial INT;
    DECLARE @transaccionPropia    BIT = 0;
    DECLARE @savepointCreado      BIT = 0;

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: Validacion de correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Ejecutor obligatorio (no nulo, no GUID vacio)
        IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuarioEjecutorDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: Perfil RBAC ESTUDIANTE
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'ESTUDIANTE',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: Existencia del estudiante
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_estudiante_exista_por_id_interno
                @idEstudiante = @idEstudianteDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 5: El estudiante debe corresponder al ejecutor autenticado (H-01)
        IF @estadoResultado = 1
           AND NOT EXISTS (
                SELECT 1 FROM dbo.Estudiante e
                WHERE e.id = @idEstudianteDefecto AND e.usuario = @idUsuarioEjecutorDefecto)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'ARC_005',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 6: Existencia de la sesion
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_sesion_exista_por_id_interno
                @idSesion = @idSesionDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 7: Matricula: el estudiante pertenece al grupo de la sesion
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno
                @idEstudiante = @idEstudianteDefecto,
                @idSesion = @idSesionDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 8: Transaccion propia (o savepoint si el llamador ya tiene una)
        IF @estadoResultado = 1
        BEGIN
            SET @conteoTransaccionesInicial = @@TRANCOUNT;
            IF @conteoTransaccionesInicial = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_lb004d_radicar_v2;
                SET @savepointCreado = 1;
            END
        END

        -- PASO 9: Soporte opcional. UPDLOCK serializa radicaciones concurrentes con el mismo fileId.
        IF @estadoResultado = 1 AND @tieneSoporte = 1
        BEGIN
            SELECT @propietarioSoporte   = a.usuarioPropietario,
                   @estadoSoporte        = a.estado,
                   @correlacionAdjuncion = a.idCorrelacionAdjuncion
            FROM dbo.ArchivoSoporte a WITH (UPDLOCK, ROWLOCK)
            WHERE a.id = @idArchivoSoporte;

            IF @propietarioSoporte IS NULL OR @propietarioSoporte <> @idUsuarioEjecutorDefecto
            BEGIN
                SET @estadoResultado = 0;
            END
            ELSE IF @estadoSoporte = 'ATTACHED' AND @correlacionAdjuncion = @idCorrelacionDefecto
            BEGIN
                SET @esReintento = 1;
            END
            ELSE IF @estadoSoporte <> 'DRAFT'
            BEGIN
                SET @estadoResultado = 0;
            END

            IF @estadoResultado = 0
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'ARC_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END
        END

        -- PASO 9.5 (D.1): plazo de excusas. Solo cuando NO es la reejecucion idempotente de una radicacion ya exitosa.
        IF @estadoResultado = 1 AND @esReintento = 0
        BEGIN
            EXEC dbo.usp_internal_validar_plazo_justificacion
                @idSesion = @idSesionDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @fechaLimiteUtc = @fechaLimiteUtc OUTPUT,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 10: Creacion de la solicitud y vinculo atomico del soporte
        IF @estadoResultado = 1 AND @esReintento = 0
        BEGIN
            SET @zonaLocal = CAST(dbo.ufn_obtener_parametro_texto(NULL, 'TIEMPO', 'ZONA_HORARIA_SQLSERVER') AS NVARCHAR(128));
            SET @fechaLocalRadicacion = CAST((SYSUTCDATETIME() AT TIME ZONE 'UTC') AT TIME ZONE @zonaLocal AS DATE);

            SELECT TOP 1 @idEstudianteGrupo = eg.id
            FROM dbo.Sesion s
            INNER JOIN dbo.EstudianteGrupo eg ON eg.grupo = s.grupo
            WHERE s.id = @idSesionDefecto AND eg.estudiante = @idEstudianteDefecto;

            SELECT TOP 1 @idAsistencia = id
            FROM dbo.Asistencia
            WHERE estudianteGrupo = @idEstudianteGrupo AND sesion = @idSesionDefecto;

            SELECT TOP 1 @idEstadoPendiente = id FROM dbo.Estado WHERE codigo IN ('P', 'PEND') ORDER BY id ASC;
            IF @idEstadoPendiente IS NULL
            BEGIN
                SELECT TOP 1 @idEstadoPendiente = id FROM dbo.Estado ORDER BY id ASC;
            END

            SET @nombreSolicitud = CONCAT('REC-', UPPER(SUBSTRING(CAST(@nuevaSolicitudId AS VARCHAR(36)), 1, 8)));

            SET @escrituraRealizada = 1;
            IF @idAsistencia IS NULL
            BEGIN
                SET @idAsistencia = NEWID();
                INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion)
                VALUES (@idAsistencia, @idEstudianteGrupo, @idSesionDefecto);
            END

            INSERT INTO dbo.SolicitudRevisionAsistencia (
                id, nombre, asistencia, fecha, estado,
                justificacionSolicitud, justificacionRespuesta
            )
            VALUES (
                @nuevaSolicitudId,
                @nombreSolicitud,
                @idAsistencia,
                @fechaLocalRadicacion,
                @idEstadoPendiente,
                CASE WHEN @justificacionDefecto IS NOT NULL AND @justificacionDefecto <> '' THEN @justificacionDefecto ELSE 'Solicitud de revision de asistencia radicada por estudiante.' END,
                ''
            );

            IF @tieneSoporte = 1
            BEGIN
                UPDATE dbo.ArchivoSoporte
                SET estado = 'ATTACHED',
                    solicitudRevisionAsistencia = @nuevaSolicitudId,
                    fechaAdjuncionUtc = SYSUTCDATETIME(),
                    fechaCambioEstadoUtc = SYSUTCDATETIME(),
                    idCorrelacionAdjuncion = @idCorrelacionDefecto
                WHERE id = @idArchivoSoporte
                  AND estado = 'DRAFT'
                  AND usuarioPropietario = @idUsuarioEjecutorDefecto;
                SET @filasActualizadas = @@ROWCOUNT;

                -- Postcondicion verificada por lectura (no solo @@ROWCOUNT): el soporte quedo vinculado a ESTA solicitud.
                IF @filasActualizadas <> 1
                   OR NOT EXISTS (SELECT 1 FROM dbo.ArchivoSoporte a
                                  WHERE a.id = @idArchivoSoporte AND a.estado = 'ATTACHED'
                                    AND a.solicitudRevisionAsistencia = @nuevaSolicitudId)
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'ARC_001',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
            END
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'SolicitudRevisionAsistencia',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

        -- PASO 11: Finalizacion respetando ownership: commit solo si el resultado es exitoso
        IF @transaccionPropia = 1
        BEGIN
            IF XACT_STATE() = 1
            BEGIN
                IF @estadoResultado = 1
                    COMMIT TRANSACTION;
                ELSE
                    ROLLBACK TRANSACTION;
            END
            ELSE IF XACT_STATE() = -1
            BEGIN
                ROLLBACK TRANSACTION;
            END
        END
        ELSE IF @savepointCreado = 1
        BEGIN
            -- Solo se revierte lo escrito (un rechazo previo a las escrituras no deja nada que deshacer).
            IF XACT_STATE() = 1 AND @estadoResultado = 0 AND @escrituraRealizada = 1
                ROLLBACK TRANSACTION sp_lb004d_radicar_v2;
        END
    END TRY
    BEGIN CATCH
        DECLARE @estadoTransaccionCatch INT = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION sp_lb004d_radicar_v2;
        END

        -- Transaccion externa condenada que no nos pertenece: propagar la excepcion original al propietario
        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
        BEGIN
            THROW;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- BLOQUE FINAL: Retorno unificado de resultados (4 columnas canonicas)
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
-- ---- schema/security/rol_asistencias_runtime_culm001_d1.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.1 (CONTRACT §2.2): permisos del plazo de excusas (HU026B). Solo EXECUTE sobre el SP publico de consulta y
-- SELECT sobre la vista nueva; el nucleo usp_internal_validar_plazo_justificacion NO se concede (lo invocan v1 y v2).
-- Aditivo e idempotente. El bucle uv_* de rol_asistencias_runtime.sql ya cubre la vista cuando deploy_schema.ps1 aplica la
-- seguridad despues de las vistas; el GRANT explicito cubre la vista creada por la migracion 20 fuera de ese despliegue.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_consultar_sesiones_materia_estudiante', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_sesiones_materia_estudiante] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_sesion_estudiante_reclamo', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_sesion_estudiante_reclamo] TO [rol_asistencias_runtime];
GO
