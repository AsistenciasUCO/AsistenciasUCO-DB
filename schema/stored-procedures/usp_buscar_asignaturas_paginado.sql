USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_buscar_asignaturas_paginado (HU143 busqueda transversal de asignaturas)
--
-- Catalogo de asignaturas con su programa, facultad, plan, semestre, area, componente y creditos. Es transversal a
-- los programas y planes del ambito del ejecutor: el ADMINISTRADOR busca en todas las facultades de su institucion y
-- el DECANO solo en su facultad (decision del dueno del producto, 2026-11-02). @busqueda compara contra el codigo y el
-- nombre de la asignatura; @idFacultad y @estaActiva acotan el resultado.
--
-- Resultset: READ_QUERY_RESULTSET (filas + totalRegistros), NO el resultset canonico de 4 columnas
-- de los comandos. Las fallas de validacion se propagan con THROW (VAL_001 / SEC_001 / PAG_001).
-- Ambito: perfiles ADMINISTRADOR o DECANO; programas de uv_auth_programa (fail-closed) restringidos a la institucion
-- que administra el ejecutor (uv_administrador) o a la facultad a su cargo (uv_decano).
-- SESSION_CONTEXT: se captura el previo y SIEMPRE se restaura (exito y error).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_buscar_asignaturas_paginado]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @numeroPagina       INT,
    @tamanoPagina       INT,
    @busqueda           NVARCHAR(100)    = NULL,
    @idFacultad         UNIQUEIDENTIFIER = NULL,
    @estaActiva         BIT              = NULL
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
        -- PASO 1: Correlacion, ejecutor, perfil y paginacion; fija el contexto (usp_validar_consulta_paginada_interno)
        EXEC dbo.usp_validar_consulta_paginada_interno
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @idCorrelacion = @idCorrelacion,
            @codigoPerfilRequerido = 'ADMINISTRADOR,DECANO',
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
        WITH programasAmbito AS (
            SELECT  p.id, p.nombrePrograma, p.idFacultad, p.nombreFacultad
            FROM    dbo.uv_auth_programa p
            WHERE   p.idInstitucion IN (SELECT a.idInstitucion FROM dbo.uv_administrador a WHERE a.idUsuario = @idUsuario)
               OR   p.idFacultad IN (SELECT d.idFacultad FROM dbo.uv_decano d WHERE d.idUsuario = @idUsuario)
        )
        SELECT
            idAsignatura          = a.id,
            codigo                = a.codigo,
            nombre                = a.nombre,
            credito               = a.credito,
            nombreArea            = a.nombreArea,
            nombreComponente      = a.nombreComponente,
            codigoSemestre        = a.codigoSemestre,
            idPlanEstudio         = sp.idPlanEstudio,
            inpPlanEstudio        = a.inp,
            idPrograma            = pa.id,
            nombrePrograma        = pa.nombrePrograma,
            idFacultad            = pa.idFacultad,
            nombreFacultad        = pa.nombreFacultad,
            estaActivaAsignatura  = a.estaActivaAsignatura,
            totalRegistros        = COUNT(*) OVER()
        FROM dbo.uv_asignatura a
        INNER JOIN dbo.uv_semestre_plan_estudio sp ON sp.id = a.idSemestrePlanEstudio
        INNER JOIN programasAmbito pa ON pa.id = sp.idPrograma
        WHERE
            (@idFacultad IS NULL OR pa.idFacultad = @idFacultad)
            AND (@estaActiva IS NULL OR a.estaActivaAsignatura = @estaActiva)
            AND (
                @busquedaFiltro IS NULL
                OR CHARINDEX(@busquedaFiltro, a.codigo) > 0
                OR CHARINDEX(@busquedaFiltro, a.nombre) > 0
            )
        ORDER BY a.nombre ASC, a.codigo ASC, a.id ASC
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
