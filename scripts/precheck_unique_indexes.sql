-- ============================================================================
-- PRECHECK READ-ONLY: duplicados que rechazarian los indices unicos del baseline.
--
-- Uso (ANTES de desplegar sobre una base con datos existentes):
--   sqlcmd -S <server> -d gestionasistenciadb -U <user> -C -b -i scripts/precheck_unique_indexes.sql
--
-- Solo ejecuta SELECT: no modifica ni borra datos.
-- Esperado en una base limpia: duplicate_groups = 0 en las 3 filas.
-- Si alguna fila es > 0: DETENER el despliegue sobre ese ambiente y resolver los duplicados
-- manualmente (decision de negocio; este script NO los corrige).
-- ============================================================================
SET NOCOUNT ON;

SELECT check_name, unique_index, duplicate_groups
FROM (
    SELECT 'Asistencia(estudianteGrupo, sesion)' AS check_name,
           'UX_Asistencia_EstudianteGrupo_Sesion' AS unique_index,
           (SELECT COUNT(*) FROM (
                SELECT estudianteGrupo, sesion FROM dbo.Asistencia
                GROUP BY estudianteGrupo, sesion HAVING COUNT(*) > 1) d) AS duplicate_groups
    UNION ALL
    SELECT 'DetalleAsistencia(asistencia)',
           'UX_DetalleAsistencia_Asistencia',
           (SELECT COUNT(*) FROM (
                SELECT asistencia FROM dbo.DetalleAsistencia
                GROUP BY asistencia HAVING COUNT(*) > 1) d)
    UNION ALL
    SELECT 'RazonCausa(codigo)',
           'UX_RazonCausa_Codigo',
           (SELECT COUNT(*) FROM (
                SELECT codigo FROM dbo.RazonCausa
                GROUP BY codigo HAVING COUNT(*) > 1) d)
) r
ORDER BY check_name;

-- Codigo de salida legible: THROW si hay duplicados (con -b, sqlcmd retorna exit code != 0).
IF EXISTS (
    SELECT 1 FROM dbo.Asistencia GROUP BY estudianteGrupo, sesion HAVING COUNT(*) > 1
    UNION ALL SELECT 1 FROM dbo.DetalleAsistencia GROUP BY asistencia HAVING COUNT(*) > 1
    UNION ALL SELECT 1 FROM dbo.RazonCausa GROUP BY codigo HAVING COUNT(*) > 1
)
    THROW 52200, 'PRECHECK FAILED: existen duplicados que rechazarian los indices unicos. Detener el despliegue.', 1;
GO
