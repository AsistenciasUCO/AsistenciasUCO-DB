USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_buscar_estudiantes_institucion_paginado (HU157 buscador de estudiantes del administrador)
--
-- Una fila por estudiante de la institucion del administrador ejecutor con las facultades y programas en que esta
-- matriculado y su numero de grupos. Es la entrada a la ficha unificada (usp_consultar_historial_estudiante).
-- @busqueda compara contra nombre y documento; @idFacultad y @estaActivo acotan el resultado.
--
-- Resultset: READ_QUERY_RESULTSET (filas + totalRegistros), NO el resultset canonico de 4 columnas
-- de los comandos. Las fallas de validacion se propagan con THROW (VAL_001 / SEC_001 / PAG_001).
-- Ambito: perfil ADMINISTRADOR; filas de uv_auth_estudiante (fail-closed) restringidas a la institucion que
-- administra (uv_administrador). El decano usa su propio directorio (/decano/estudiantes).
-- SESSION_CONTEXT: se captura el previo y SIEMPRE se restaura (exito y error).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_buscar_estudiantes_institucion_paginado]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @numeroPagina       INT,
    @tamanoPagina       INT,
    @busqueda           NVARCHAR(100)    = NULL,
    @idFacultad         UNIQUEIDENTIFIER = NULL,
    @estaActivo         BIT              = NULL
)
AS
    DECLARE @idUsuario               UNIQUEIDENTIFIER;
    DECLARE @offset                  INT;
    DECLARE @busquedaFiltro          NVARCHAR(100) = NULLIF(TRIM(@busqueda), '');
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

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END;

        -- PASO 2: Consulta y retorno de resultados
        WITH matriculas AS (
            SELECT  e.id, e.idUsuario, e.numeroIdentificacion, e.nombreCompleto, e.estaActivoUsuario,
                    e.idFacultad, e.nombreFacultad, e.nombrePrograma, e.idGrupo
            FROM    dbo.uv_auth_estudiante e
            WHERE   e.idInstitucion IN (SELECT a.idInstitucion FROM dbo.uv_administrador a WHERE a.idUsuario = @idUsuario)
        ),
        candidatos AS (
            SELECT  m.id, m.idUsuario, m.numeroIdentificacion, m.nombreCompleto, m.estaActivoUsuario,
                    totalGrupos = COUNT(DISTINCT m.idGrupo)
            FROM    matriculas m
            WHERE   (@idFacultad IS NULL OR EXISTS (SELECT 1 FROM matriculas mf WHERE mf.id = m.id AND mf.idFacultad = @idFacultad))
            GROUP BY m.id, m.idUsuario, m.numeroIdentificacion, m.nombreCompleto, m.estaActivoUsuario
        )
        SELECT
            idEstudiante          = c.id,
            idUsuario             = c.idUsuario,
            numeroIdentificacion  = c.numeroIdentificacion,
            nombreCompleto        = c.nombreCompleto,
            correo                = u.correo,
            estaActivoUsuario     = c.estaActivoUsuario,
            facultades            = (SELECT STRING_AGG(CONVERT(NVARCHAR(MAX), x.nombreFacultad), N', ') WITHIN GROUP (ORDER BY x.nombreFacultad)
                                     FROM (SELECT DISTINCT nombreFacultad FROM matriculas WHERE id = c.id) x),
            programas             = (SELECT STRING_AGG(CONVERT(NVARCHAR(MAX), x.nombrePrograma), N', ') WITHIN GROUP (ORDER BY x.nombrePrograma)
                                     FROM (SELECT DISTINCT nombrePrograma FROM matriculas WHERE id = c.id) x),
            totalGrupos           = c.totalGrupos,
            totalRegistros        = COUNT(*) OVER()
        FROM candidatos c
        LEFT JOIN dbo.uv_usuario u ON u.id = c.idUsuario
        WHERE
            (@estaActivo IS NULL OR c.estaActivoUsuario = @estaActivo)
            AND (
                @busquedaFiltro IS NULL
                OR CHARINDEX(@busquedaFiltro, c.nombreCompleto) > 0
                OR CHARINDEX(@busquedaFiltro, CONVERT(NVARCHAR(20), c.numeroIdentificacion)) > 0
            )
        ORDER BY c.nombreCompleto ASC, c.id ASC
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
