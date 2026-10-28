USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_resumen_docentes_programa (HU095)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW ante ejecutor nulo).
-- Consolidado del directorio docente del programa del COORDINADOR: una fila por tipo de vinculacion con los
-- vinculos activos e inactivos (mismo criterio estaActivoDocentePrograma del directorio HU062/HU089).
--   - el programa se resuelve del ejecutor (usp_resolver_programa_coordinador_interno; KPI_001 si no coordina);
--   - incluye los tipos de vinculacion activos aunque no tengan docentes (contadores en cero) y los inactivos
--     que aun tengan vinculos en el programa.
-- Solo lectura: sin XACT_ABORT.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_resumen_docentes_programa]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @idPrograma UNIQUEIDENTIFIER;

    EXEC dbo.usp_resolver_programa_coordinador_interno
        @idUsuarioEjecutor = @idUsuarioEjecutor,
        @idCorrelacion = @idCorrelacion,
        @validarUmbrales = 0,
        @idPrograma = @idPrograma OUTPUT;

    SELECT
        idTipoVinculacion     = tv.id,
        codigoTipoVinculacion = tv.codigo,
        nombreTipoVinculacion = tv.nombre,
        totalActivos          = SUM(CASE WHEN d.idDocentePrograma IS NOT NULL AND d.estaActivoDocentePrograma = 1 THEN 1 ELSE 0 END),
        totalInactivos        = SUM(CASE WHEN d.idDocentePrograma IS NOT NULL AND d.estaActivoDocentePrograma = 0 THEN 1 ELSE 0 END)
    FROM dbo.TipoVinculacion tv
    LEFT JOIN dbo.uv_docente_programa d
           ON d.idTipoVinculacion = tv.id
          AND d.idPrograma = @idPrograma
    GROUP BY tv.id, tv.codigo, tv.nombre, tv.estado
    HAVING tv.estado = 1 OR COUNT(d.idDocentePrograma) > 0
    ORDER BY tv.nombre ASC, tv.id ASC;
END;
GO
