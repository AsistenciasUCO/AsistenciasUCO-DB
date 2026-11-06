USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_docentes_facultad_paginado (HU128 filtro de profesores por programa asignado; HU136 directorio de
-- profesores de la institucion para el administrador, decision de John 2026-11-05)
--
-- Directorio de los docentes de la facultad del decano ejecutor: una fila por docente con los programas en que
-- tiene un vinculo activo (DocentePrograma.estado = 1) y su numero de grupos en ellos. @idPrograma deja solo los
-- docentes con vinculo activo en ese programa (los programas listados siguen siendo todos los de la facultad).
-- @busqueda compara contra nombre y documento; @estaActivo filtra por el estado del usuario.
--
-- Resultset: READ_QUERY_RESULTSET (filas + totalRegistros), NO el resultset canonico de 4 columnas
-- de los comandos. Las fallas de validacion se propagan con THROW (VAL_001 / SEC_001 / PAG_001).
-- Ambito: perfil DECANO (la facultad a su cargo) o ADMINISTRADOR (las facultades de su institucion); filas de
-- uv_auth_docente_programa (fail-closed). @idFacultad (HU136) acota a una facultad dentro de ese ambito.
-- HU136 (ajuste aprobado por John 2026-11-05): para el ADMINISTRADOR, @estadoVinculo = ACTIVO (por defecto, como
-- HU128), SIN_VINCULO (docentes de la institucion que tuvieron vinculo y hoy no tienen ninguno activo, p. ej.
-- retirados de todos sus programas) o TODOS. Un docente que nunca tuvo vinculo no se puede atribuir a una
-- institucion y no aparece (fail-closed). El DECANO siempre ve solo vinculos activos. Programas, grupos y los
-- filtros de facultad y programa cuentan solo vinculos activos; la ultima columna es tieneVinculoActivo.
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
    @estaActivo         BIT              = NULL,
    @idFacultad         UNIQUEIDENTIFIER = NULL,
    @estadoVinculo      VARCHAR(20)      = NULL
)
AS
    DECLARE @idUsuario               UNIQUEIDENTIFIER;
    DECLARE @offset                  INT;
    DECLARE @busquedaFiltro          NVARCHAR(100) = NULLIF(TRIM(@busqueda), '');
    DECLARE @contextoPrevio          SQL_VARIANT = SESSION_CONTEXT(N'idUsuarioEjecutor');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
    DECLARE @modoVinculo             VARCHAR(20);
BEGIN
    SET NOCOUNT ON;
    -- Consulta de solo lectura: sin XACT_ABORT para no invalidar la transaccion del llamador ante un THROW de validacion.
    BEGIN TRY
        -- PASO 1: Correlacion, ejecutor, perfil DECANO o ADMINISTRADOR y paginacion; fija el contexto (usp_validar_consulta_paginada_interno)
        EXEC dbo.usp_validar_consulta_paginada_interno
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @idCorrelacion = @idCorrelacion,
            @codigoPerfilRequerido = 'DECANO,ADMINISTRADOR',
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

        -- El modo de vinculo solo aplica al ADMINISTRADOR; el DECANO conserva el comportamiento de HU128.
        SET @modoVinculo = IIF(EXISTS (SELECT 1 FROM dbo.uv_administrador a WHERE a.idUsuario = @idUsuario)
                                   AND UPPER(TRIM(@estadoVinculo)) IN ('SIN_VINCULO', 'TODOS'),
                               UPPER(TRIM(@estadoVinculo)), 'ACTIVO');

        -- PASO 2: Consulta y retorno de resultados
        WITH vinculos AS (
            SELECT  dp.idDocente, dp.idUsuario, dp.numeroIdentificacion, dp.nombreCompleto, dp.correo,
                    dp.estaActivoUsuario, dp.idPrograma, dp.nombrePrograma, dp.idFacultad, dp.totalGruposPrograma,
                    dp.estaActivoVinculacion
            FROM    dbo.uv_auth_docente_programa dp
            WHERE   (dp.estaActivoVinculacion = 1 OR @modoVinculo <> 'ACTIVO')
               AND  (dp.idFacultad IN (SELECT d.idFacultad FROM dbo.uv_decano d WHERE d.idUsuario = @idUsuario)
                     OR EXISTS (SELECT 1 FROM dbo.uv_administrador a
                                WHERE a.idUsuario = @idUsuario AND a.idInstitucion = dp.idInstitucion))
        ),
        activos AS (
            SELECT * FROM vinculos WHERE estaActivoVinculacion = 1
        ),
        docentes AS (
            SELECT  v.idDocente, v.idUsuario, v.numeroIdentificacion, v.nombreCompleto, v.correo, v.estaActivoUsuario,
                    totalProgramas = COUNT(DISTINCT IIF(v.estaActivoVinculacion = 1, v.idPrograma, NULL)),
                    totalGrupos = SUM(IIF(v.estaActivoVinculacion = 1, v.totalGruposPrograma, 0)),
                    programas = STRING_AGG(IIF(v.estaActivoVinculacion = 1, CONVERT(NVARCHAR(MAX), v.nombrePrograma), NULL), N', ')
                                WITHIN GROUP (ORDER BY v.nombrePrograma),
                    tieneVinculoActivo = CAST(MAX(IIF(v.estaActivoVinculacion = 1, 1, 0)) AS BIT)
            FROM    vinculos v
            GROUP BY v.idDocente, v.idUsuario, v.numeroIdentificacion, v.nombreCompleto, v.correo, v.estaActivoUsuario
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
            totalRegistros = COUNT(*) OVER(),
            d.tieneVinculoActivo
        FROM docentes d
        WHERE
            (@modoVinculo = 'TODOS' OR d.tieneVinculoActivo = IIF(@modoVinculo = 'ACTIVO', 1, 0))
            AND (@idPrograma IS NULL OR EXISTS (SELECT 1 FROM activos v WHERE v.idDocente = d.idDocente AND v.idPrograma = @idPrograma))
            AND (@idFacultad IS NULL OR EXISTS (SELECT 1 FROM activos v WHERE v.idDocente = d.idDocente AND v.idFacultad = @idFacultad))
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
