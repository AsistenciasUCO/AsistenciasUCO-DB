USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_archivo_soporte_autorizado  (LB-004D, R1)
--
-- Clasificacion (DB-GP-001C):
--   NON_GOLDEN_PATH_EXTENSION   no forma parte de docs/contracts/DB_BASELINE_CONTRACT.md
--
-- Resultset: READ_QUERY_RESULTSET (0..1 fila de datos). NO es un MUTATION_COMMAND_RESULTSET: el
-- resultset de 4 columnas aplica solo a comandos, por eso este SP queda excluido de esa regla en
-- test/test_contract_closure.sql. Los parametros invalidos se propagan con THROW (como
-- usp_consultar_grupos_paginado).
--
-- Autorizacion (se resuelve aqui, ANTES de que el backend pida bytes al storage):
--   PROPIETARIO     usuarioPropietario = ejecutor y estado IN (DRAFT, ATTACHED)
--   DOCENTE_TITULAR estado = ATTACHED y el ejecutor es Docente.usuario del Grupo.docente de la
--                   sesion de la asistencia de la solicitud
-- Cualquier otro caso (inexistente, otro estudiante incluso del mismo grupo, docente no titular,
-- administrador, decano, coordinador, ORPHAN) => 0 filas, sin senal que distinga los casos.
-- Une tablas base: NO usa SESSION_CONTEXT ni uv_auth_* (que exponen reclamos a companeros/roles
-- administrativos, hallazgo H-03).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_archivo_soporte_autorizado]
(
    @idArchivoSoporte   UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idArchivoDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idArchivoSoporte, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    -- Validacion de correlacion
    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuarioDefecto = @guidVacio)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001',
            @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 1 AND (@idArchivoSoporte IS NULL OR @idArchivoDefecto = @guidVacio)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_002',
            @p_param1 = 'idArchivoSoporte',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    SELECT
        idArchivoSoporte              = a.id,
        estado                        = a.estado,
        nombreOriginal                = a.nombreOriginal,
        tipoContenido                 = a.tipoContenido,
        tamanioBytes                  = a.tamanioBytes,
        checksumSha256                = a.checksumSha256,
        fechaRegistroUtc              = a.fechaRegistroUtc,
        fechaAdjuncionUtc             = a.fechaAdjuncionUtc,
        idSolicitudRevisionAsistencia = a.solicitudRevisionAsistencia,
        relacionAcceso                = CAST(CASE
                                            WHEN a.usuarioPropietario = @idUsuarioDefecto
                                                 AND a.estado IN ('DRAFT', 'ATTACHED') THEN 'PROPIETARIO'
                                            ELSE 'DOCENTE_TITULAR'
                                        END AS VARCHAR(20))
    FROM dbo.ArchivoSoporte a
    WHERE a.id = @idArchivoDefecto
      AND (
            (a.usuarioPropietario = @idUsuarioDefecto AND a.estado IN ('DRAFT', 'ATTACHED'))
         OR (a.estado = 'ATTACHED'
             AND EXISTS (
                SELECT 1
                FROM dbo.SolicitudRevisionAsistencia sra
                INNER JOIN dbo.Asistencia asi ON asi.id = sra.asistencia
                INNER JOIN dbo.Sesion ses     ON ses.id = asi.sesion
                INNER JOIN dbo.Grupo gru      ON gru.id = ses.grupo
                INNER JOIN dbo.Docente doc    ON doc.id = gru.docente
                WHERE sra.id = a.solicitudRevisionAsistencia
                  AND doc.usuario = @idUsuarioDefecto))
          );
END;
GO
