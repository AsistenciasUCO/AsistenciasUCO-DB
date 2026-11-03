USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_docentes_facultad_paginado (HU128 filtro de profesores por programa asignado)
--
-- Directorio de los docentes de la facultad del decano ejecutor: una fila por docente con los programas en que
-- tiene un vinculo activo (DocentePrograma.estado = 1) y su numero de grupos en ellos. @idPrograma deja solo los
-- docentes con vinculo activo en ese programa (los programas listados siguen siendo todos los de la facultad).
-- @busqueda compara contra nombre y documento; @estaActivo filtra por el estado del usuario.
--
-- Resultset: READ_QUERY_RESULTSET (filas + totalRegistros), NO el resultset canonico de 4 columnas
-- de los comandos. Las fallas de validacion se propagan con THROW (VAL_001 / SEC_001 / PAG_001).
-- Ambito: perfil DECANO; filas de uv_auth_docente_programa (fail-closed) restringidas a la facultad a su cargo.
-- SESSION_CONTEXT: se captura el previo y SIEMPRE se restaura (exito y error).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_docentes_facultad_paginado]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @numeroPagina       INT,
    @tamanoPagina       INT,
    @idPrograma         UNIQUEIDENTIFIER = NULL,
    @busqueda           NVARCHAR(100)    = NULL,
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
        -- PASO 1: Correlacion, ejecutor, perfil DECANO y paginacion; fija el contexto (usp_validar_consulta_paginada_interno)
        EXEC dbo.usp_validar_consulta_paginada_interno
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @idCorrelacion = @idCorrelacion,
            @codigoPerfilRequerido = 'DECANO',
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
        WITH vinculos AS (
            SELECT  dp.idDocente, dp.idUsuario, dp.numeroIdentificacion, dp.nombreCompleto, dp.correo,
                    dp.estaActivoUsuario, dp.idPrograma, dp.nombrePrograma, dp.totalGruposPrograma
            FROM    dbo.uv_auth_docente_programa dp
            WHERE   dp.estaActivoVinculacion = 1
               AND  dp.idFacultad IN (SELECT d.idFacultad FROM dbo.uv_decano d WHERE d.idUsuario = @idUsuario)
        ),
        docentes AS (
            SELECT  idDocente, idUsuario, numeroIdentificacion, nombreCompleto, correo, estaActivoUsuario,
                    totalProgramas = COUNT(DISTINCT idPrograma),
                    totalGrupos = SUM(totalGruposPrograma),
                    programas = STRING_AGG(CONVERT(NVARCHAR(MAX), nombrePrograma), N', ') WITHIN GROUP (ORDER BY nombrePrograma)
            FROM    vinculos
            GROUP BY idDocente, idUsuario, numeroIdentificacion, nombreCompleto, correo, estaActivoUsuario
        )
        SELECT
            d.idDocente,
            d.idUsuario,
            d.numeroIdentificacion,
            d.nombreCompleto,
            d.correo,
            d.estaActivoUsuario,
            d.programas,
            d.totalProgramas,
            d.totalGrupos,
            totalRegistros = COUNT(*) OVER()
        FROM docentes d
        WHERE
            (@idPrograma IS NULL OR EXISTS (SELECT 1 FROM vinculos v WHERE v.idDocente = d.idDocente AND v.idPrograma = @idPrograma))
            AND (@estaActivo IS NULL OR d.estaActivoUsuario = @estaActivo)
            AND (
                @busquedaFiltro IS NULL
                OR CHARINDEX(@busquedaFiltro, d.nombreCompleto) > 0
                OR CHARINDEX(@busquedaFiltro, CONVERT(NVARCHAR(20), d.numeroIdentificacion)) > 0
            )
        ORDER BY d.nombreCompleto ASC, d.idDocente ASC
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
