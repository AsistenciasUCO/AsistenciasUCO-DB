-- ============================================================================
-- HU008 — Depuracion MANUAL y OPCIONAL de EstudiantePrograma creados por asignaturas transversales.
--
-- Contexto: antes de la regla de John (2026-10-27), matricular a un estudiante en CUALQUIER grupo creaba la fila
-- EstudiantePrograma del programa del grupo. Ahora solo una asignatura ESPECIFICA (componente ESP) inscribe en el
-- programa. Este script elimina las filas antiguas que no se sostienen con la regla nueva.
--
-- Criterio de borrado (conservador): fila (estudiante, programa) SIN ninguna matricula del estudiante (en cualquier
-- estado: activa, finalizada o cancelada) en un grupo de una asignatura ESP de ese programa. Se usa "cualquier
-- estado" y no solo "activa" para no desvincular a estudiantes que ya cursaron especificas del programa en periodos
-- anteriores.
--
-- NO forma parte de deploy_schema.ps1 ni del despliegue automatico. Uso:
--   1) Ejecutar con @soloConteo = 1 (por defecto): lista las filas candidatas y su total. No modifica nada.
--   2) Respaldar la base (o al menos SELECT * INTO de EstudiantePrograma) antes de borrar.
--   3) Ejecutar con @soloConteo = 0 y @filasEsperadas = <total del paso 1>. El borrado corre en una transaccion: si el
--      numero de filas borradas no coincide con @filasEsperadas, hace ROLLBACK y no cambia nada.
-- Idempotente: una segunda ejecucion encuentra 0 candidatas.
-- ============================================================================
USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @soloConteo     BIT = 1;     -- 1 = solo conteo (dry run); 0 = borrar
DECLARE @filasEsperadas INT = NULL;  -- obligatorio con @soloConteo = 0: total que mostro el dry run

IF OBJECT_ID('tempdb..#candidatas') IS NOT NULL DROP TABLE #candidatas;

SELECT
    ep.id AS idEstudiantePrograma,
    ep.estudiante AS idEstudiante,
    u.numeroIdentificacion,
    CONCAT_WS(N' ', u.primerNombre, u.primerApellido, u.segundoApellido) AS nombreEstudiante,
    ep.programa AS idPrograma,
    p.nombre AS nombrePrograma,
    gruposTransversales = (SELECT COUNT(*) FROM dbo.EstudianteGrupo eg
                           INNER JOIN dbo.Grupo g ON g.id = eg.grupo
                           INNER JOIN dbo.Asignatura a ON a.id = g.asignatura
                           INNER JOIN dbo.Componente c ON c.id = a.componente
                           INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = a.semestrePlanEstudio
                           INNER JOIN dbo.PlanEstudio pe ON pe.id = spe.planEstudio
                           WHERE eg.estudiante = ep.estudiante AND pe.programa = ep.programa AND c.codigo IN ('BAS', 'INS'))
INTO #candidatas
FROM dbo.EstudiantePrograma ep
INNER JOIN dbo.Estudiante e ON e.id = ep.estudiante
INNER JOIN dbo.Usuario u ON u.id = e.usuario
INNER JOIN dbo.Programa p ON p.id = ep.programa
WHERE NOT EXISTS (
    SELECT 1
    FROM dbo.EstudianteGrupo eg
    INNER JOIN dbo.Grupo g ON g.id = eg.grupo
    INNER JOIN dbo.Asignatura a ON a.id = g.asignatura
    INNER JOIN dbo.Componente c ON c.id = a.componente
    INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = a.semestrePlanEstudio
    INNER JOIN dbo.PlanEstudio pe ON pe.id = spe.planEstudio
    WHERE eg.estudiante = ep.estudiante
      AND pe.programa = ep.programa
      AND c.codigo = 'ESP'
);

DECLARE @total INT = (SELECT COUNT(*) FROM #candidatas);
SELECT * FROM #candidatas ORDER BY nombrePrograma, nombreEstudiante;
PRINT CONCAT('HU008_DEPURACION_CANDIDATAS=', @total);

IF @soloConteo = 1
BEGIN
    PRINT 'HU008_DEPURACION_MODO=SOLO_CONTEO (no se modifico nada)';
END
ELSE
BEGIN
    IF @filasEsperadas IS NULL
        THROW 54001, 'HU008_DEPURACION: indique @filasEsperadas con el total del dry run.', 1;

    BEGIN TRANSACTION;
    DELETE ep
    FROM dbo.EstudiantePrograma ep
    INNER JOIN #candidatas c ON c.idEstudiantePrograma = ep.id;
    DECLARE @borradas INT = @@ROWCOUNT;

    IF @borradas <> @filasEsperadas
    BEGIN
        ROLLBACK TRANSACTION;
        PRINT CONCAT('HU008_DEPURACION_ROLLBACK borradas=', @borradas, ' esperadas=', @filasEsperadas);
        THROW 54002, 'HU008_DEPURACION: el numero de filas no coincide con el dry run; no se cambio nada.', 1;
    END

    COMMIT TRANSACTION;
    PRINT CONCAT('HU008_DEPURACION_BORRADAS=', @borradas);
END

DROP TABLE #candidatas;
GO
