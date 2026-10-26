USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_estructura_facultad (HU109 organigrama, HU119 arbol Facultad -> Programa -> Plan)
--
-- Una fila por (facultad, programa, plan de estudio) de las facultades del decano ejecutor. Las facultades
-- sin programas y los programas sin plan aparecen con las columnas hijas en NULL (LEFT JOIN), para que el
-- arbol muestre todos los niveles.
-- clave: identificador unico de la fila (facultad|programa|plan) para el consumidor.
--
-- Resultset: READ_QUERY_RESULTSET (filas), NO el resultset canonico de 4 columnas de los comandos.
-- Las fallas se propagan con THROW (VAL_001).
-- Ambito: uv_auth_facultad / uv_auth_programa (fail-closed) restringidas a las facultades cuyo decano es el
-- ejecutor.
-- SESSION_CONTEXT: se captura el previo y SIEMPRE se restaura (exito y error).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_estructura_facultad]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    DECLARE @contextoPrevio SQL_VARIANT = SESSION_CONTEXT(N'idUsuarioEjecutor');

    BEGIN TRY
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND (@idUsuarioDefecto IS NULL OR @idUsuarioDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        EXEC dbo.usp_establecer_contexto_usuario_ejecutor
            @p_idUsuario = @idUsuarioDefecto;

        SELECT
            CONCAT(CONVERT(NVARCHAR(36), f.id), N'|', CONVERT(NVARCHAR(36), p.id), N'|', CONVERT(NVARCHAR(36), pe.id)) AS clave,
            f.id                    AS idFacultad,
            f.nombreFacultad,
            f.nombreCompletoDecano,
            f.estaActivaFacultad,
            p.id                    AS idPrograma,
            p.nombrePrograma,
            p.nombreCoordinador,
            p.estaActivoPrograma,
            p.nombreTipoPrograma,
            p.nombreModalidad,
            p.nombreJornada,
            pe.id                   AS idPlanEstudio,
            pe.inp                  AS inpPlanEstudio,
            pe.estaActivoPlanEstudio,
            sem.totalSemestres
        FROM dbo.uv_auth_facultad f
        LEFT JOIN dbo.uv_auth_programa p ON p.idFacultad = f.id
        LEFT JOIN dbo.uv_plan_estudio pe ON pe.idPrograma = p.id
        OUTER APPLY (
            SELECT COUNT(*) AS totalSemestres
            FROM dbo.uv_semestre_plan_estudio spe
            WHERE spe.idPlanEstudio = pe.id
        ) sem
        WHERE f.id IN (
                SELECT fd.id FROM dbo.Facultad fd INNER JOIN dbo.Decano d ON d.id = fd.decano
                WHERE d.usuario = @idUsuarioDefecto
              )
        ORDER BY f.nombreFacultad ASC, f.id ASC, p.nombrePrograma ASC, p.id ASC, pe.inp ASC, pe.id ASC;

        EXEC sys.sp_set_session_context
            @key = N'idUsuarioEjecutor',
            @value = @contextoPrevio,
            @read_only = 0;
    END TRY
    BEGIN CATCH
        EXEC sys.sp_set_session_context
            @key = N'idUsuarioEjecutor',
            @value = @contextoPrevio,
            @read_only = 0;
        THROW;
    END CATCH;
END;
GO
