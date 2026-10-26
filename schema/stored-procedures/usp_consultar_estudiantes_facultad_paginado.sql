USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_estudiantes_facultad_paginado (HU104 directorio, HU105 busqueda)
--
-- Directorio consolidado de los estudiantes de la facultad del decano ejecutor: una fila por estudiante con
-- los programas en que esta matriculado y su numero de grupos. @busqueda compara contra nombre y documento.
--
-- Resultset: READ_QUERY_RESULTSET (filas + totalRegistros), NO el resultset canonico de 4 columnas
-- de los comandos. Las fallas de paginacion se propagan con THROW (DBCODE=PAG_001).
-- Ambito: filas de uv_auth_estudiante (fail-closed sin contexto) restringidas a las facultades cuyo decano es
-- el ejecutor; cualquier otro usuario recibe 0 filas.
-- SESSION_CONTEXT: se captura el previo y SIEMPRE se restaura (exito y error).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_estudiantes_facultad_paginado]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @numeroPagina       INT,
    @tamanoPagina       INT,
    @busqueda           NVARCHAR(100)    = NULL,
    @idPrograma         UNIQUEIDENTIFIER = NULL,
    @estaActivo         BIT              = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    -- Consulta de solo lectura: sin XACT_ABORT para no invalidar la transaccion del llamador ante un THROW de validacion.

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @tamanoMaximo         INT = TRY_CAST(dbo.ufn_obtener_parametro('PAGINACION', 'TAMANO_MAXIMO') AS INT);
    DECLARE @busquedaFiltro       NVARCHAR(100) = NULLIF(TRIM(@busqueda), '');
    DECLARE @offset               INT;

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

            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        SET @offset = (@numeroPagina - 1) * @tamanoPagina;

        EXEC dbo.usp_establecer_contexto_usuario_ejecutor
            @p_idUsuario = @idUsuarioDefecto;

        WITH matriculas AS (
            SELECT  e.id, e.idUsuario, e.numeroIdentificacion, e.nombreCompleto, e.estaActivoUsuario,
                    e.idPrograma, e.nombrePrograma, e.idGrupo
            FROM    dbo.uv_auth_estudiante e
            WHERE   e.idFacultad IN (
                        SELECT f.id FROM dbo.Facultad f INNER JOIN dbo.Decano d ON d.id = f.decano
                        WHERE d.usuario = @idUsuarioDefecto
                    )
               AND  (@idPrograma IS NULL OR e.idPrograma = @idPrograma)
        ),
        estudiantes AS (
            SELECT  id, idUsuario, numeroIdentificacion, nombreCompleto, estaActivoUsuario,
                    COUNT(DISTINCT idGrupo) AS totalGrupos
            FROM    matriculas
            GROUP BY id, idUsuario, numeroIdentificacion, nombreCompleto, estaActivoUsuario
        ),
        programas AS (
            SELECT  id, STRING_AGG(CONVERT(NVARCHAR(MAX), nombrePrograma), N', ') WITHIN GROUP (ORDER BY nombrePrograma) AS programas
            FROM    (SELECT DISTINCT id, nombrePrograma FROM matriculas) mp
            GROUP BY id
        )
        SELECT
            es.id                   AS idEstudiante,
            es.idUsuario,
            es.numeroIdentificacion,
            es.nombreCompleto,
            u.correo,
            es.estaActivoUsuario,
            pr.programas,
            es.totalGrupos,
            COUNT(*) OVER()         AS totalRegistros
        FROM estudiantes es
        INNER JOIN programas pr ON pr.id = es.id
        LEFT JOIN dbo.uv_usuario u ON u.id = es.idUsuario
        WHERE
            (@estaActivo IS NULL OR es.estaActivoUsuario = @estaActivo)
            AND (
                @busquedaFiltro IS NULL
                OR CHARINDEX(@busquedaFiltro, es.nombreCompleto) > 0
                OR CHARINDEX(@busquedaFiltro, CONVERT(NVARCHAR(20), es.numeroIdentificacion)) > 0
            )
        ORDER BY es.nombreCompleto ASC, es.id ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamanoPagina ROWS ONLY;

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
