USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_programas_creditos_facultad_paginado (HU112 tabla unificada de programas y creditos)
--
-- Una fila por programa y plan de estudio de la facultad del decano ejecutor, con el numero de semestres,
-- asignaturas y la suma de creditos (Asignatura.credito) del plan. Los programas sin plan salen con una fila
-- de plan vacio (totales en 0). @busqueda compara contra el nombre del programa y el INP del plan.
-- Los totales cuentan todas las asignaturas del plan (activas o no), igual que la malla de /decano/planes-estudio.
-- totalSemestres: mayor numero de semestre del plan (regla HU082/HU083 del coordinador); antes contaba los semestres
-- creados (certificacion F3, 2026-11-06, decision de John).
--
-- Resultset: READ_QUERY_RESULTSET (filas + totalRegistros), NO el resultset canonico de 4 columnas
-- de los comandos. Las fallas de validacion se propagan con THROW (VAL_001 / SEC_001 / PAG_001).
-- Ambito: perfil DECANO; filas de uv_auth_programa (fail-closed) restringidas a la facultad a su cargo (uv_decano).
-- SESSION_CONTEXT: se captura el previo y SIEMPRE se restaura (exito y error).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_programas_creditos_facultad_paginado]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @numeroPagina       INT,
    @tamanoPagina       INT,
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
        WITH totalesPlan AS (
            SELECT  sp.idPlanEstudio,
                    totalSemestres = ISNULL(MAX(sp.numeroSemestre), 0),
                    totalAsignaturas = COUNT(a.id),
                    totalCreditos = SUM(a.credito)
            FROM    dbo.uv_semestre_plan_estudio sp
            LEFT JOIN dbo.uv_asignatura a ON a.idSemestrePlanEstudio = sp.id
            GROUP BY sp.idPlanEstudio
        )
        SELECT
            idPrograma            = p.id,
            nombrePrograma        = p.nombrePrograma,
            nombreTipoPrograma    = p.nombreTipoPrograma,
            nombreModalidad       = p.nombreModalidad,
            nombreJornada         = p.nombreJornada,
            estaActivoPrograma    = p.estaActivoPrograma,
            idPlanEstudio         = pe.id,
            inpPlanEstudio        = pe.inp,
            estaActivoPlanEstudio = pe.estaActivoPlanEstudio,
            -- ISNULL permitido solo sobre agregaciones (REC4 #3): un plan o programa sin filas suma 0.
            totalSemestres        = ISNULL(tp.totalSemestres, 0),
            totalAsignaturas      = ISNULL(tp.totalAsignaturas, 0),
            totalCreditos         = ISNULL(tp.totalCreditos, 0),
            totalRegistros        = COUNT(*) OVER()
        FROM dbo.uv_auth_programa p
        LEFT JOIN dbo.uv_plan_estudio pe ON pe.idPrograma = p.id
        LEFT JOIN totalesPlan tp ON tp.idPlanEstudio = pe.id
        WHERE
            p.idFacultad IN (SELECT d.idFacultad FROM dbo.uv_decano d WHERE d.idUsuario = @idUsuario)
            AND (@estaActivo IS NULL OR p.estaActivoPrograma = @estaActivo)
            AND (
                @busquedaFiltro IS NULL
                OR CHARINDEX(@busquedaFiltro, p.nombrePrograma) > 0
                OR CHARINDEX(@busquedaFiltro, CONVERT(NVARCHAR(20), pe.inp)) > 0
            )
        ORDER BY p.nombrePrograma ASC, p.id ASC, pe.inp DESC, pe.id ASC
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
