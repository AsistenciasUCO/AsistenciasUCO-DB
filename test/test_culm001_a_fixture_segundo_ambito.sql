USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ============================================================================
-- CULM-001 A2-T-18 (CONTRACT §8.2.4, N7): el fixture test/fixtures/culm1_segundo_ambito.sql es idempotente y su _down
-- deja la BD como antes, sin borrar una CULM1-Facultad B que ya existia. Todo corre dentro de UNA transaccion que se
-- revierte al final (las transacciones del fixture quedan anidadas), asi la prueba pasa con o sin el fixture aplicado
-- (A2-T-15) y no deja residuos. Usa :r con la ruta de test_suite.sql (/tmp/test).
-- ============================================================================
PRINT 'TEST START: test_culm001_a_fixture_segundo_ambito';
CREATE TABLE #snap (fase VARCHAR(10) PRIMARY KEY, valor NVARCHAR(1000), propias INT, facultadPorNombre INT);
BEGIN TRANSACTION;
-- Garantiza el caso "la facultad ya existia": si no hay CULM1-Facultad B, se crea una por nombre (no es C1B0...).
IF NOT EXISTS (SELECT 1 FROM dbo.Facultad WHERE nombre = N'CULM1-Facultad B')
    INSERT INTO dbo.Facultad (id, nombre, institucion, decano, estado)
    SELECT TOP 1 NEWID(), N'CULM1-Facultad B', f.institucion, f.decano, 1 FROM dbo.Facultad f ORDER BY f.id;
GO
:r /tmp/test/fixtures/culm1_segundo_ambito_down.sql
GO
SET NOCOUNT ON;
INSERT INTO #snap (fase, valor, propias, facultadPorNombre)
SELECT 'S0', CONCAT((SELECT COUNT(*) FROM dbo.Usuario), '|', (SELECT COUNT(*) FROM dbo.Estudiante), '|', (SELECT COUNT(*) FROM dbo.Docente), '|',
    (SELECT COUNT(*) FROM dbo.Coordinador), '|', (SELECT COUNT(*) FROM dbo.Decano), '|', (SELECT COUNT(*) FROM dbo.Facultad), '|',
    (SELECT COUNT(*) FROM dbo.Programa), '|', (SELECT COUNT(*) FROM dbo.PlanEstudio), '|', (SELECT COUNT(*) FROM dbo.Asignatura), '|',
    (SELECT COUNT(*) FROM dbo.Grupo), '|', (SELECT COUNT(*) FROM dbo.Horario), '|', (SELECT COUNT(*) FROM dbo.EstudianteGrupo), '|',
    (SELECT COUNT(*) FROM dbo.EstudiantePrograma), '|', (SELECT COUNT(*) FROM dbo.Sesion), '|', (SELECT COUNT(*) FROM dbo.Asistencia), '|',
    (SELECT COUNT(*) FROM dbo.DetalleAsistencia), '|', (SELECT COUNT(*) FROM dbo.SolicitudRevisionAsistencia)),
    (SELECT COUNT(*) FROM dbo.Grupo WHERE id = 'C1B00000-0000-4000-8000-00000000000C'),
    (SELECT COUNT(*) FROM dbo.Facultad WHERE nombre = N'CULM1-Facultad B');
GO
:r /tmp/test/fixtures/culm1_segundo_ambito.sql
GO
SET NOCOUNT ON;
INSERT INTO #snap (fase, valor, propias, facultadPorNombre)
SELECT 'S1', CONCAT((SELECT COUNT(*) FROM dbo.Usuario), '|', (SELECT COUNT(*) FROM dbo.Estudiante), '|', (SELECT COUNT(*) FROM dbo.Docente), '|',
    (SELECT COUNT(*) FROM dbo.Coordinador), '|', (SELECT COUNT(*) FROM dbo.Decano), '|', (SELECT COUNT(*) FROM dbo.Facultad), '|',
    (SELECT COUNT(*) FROM dbo.Programa), '|', (SELECT COUNT(*) FROM dbo.PlanEstudio), '|', (SELECT COUNT(*) FROM dbo.Asignatura), '|',
    (SELECT COUNT(*) FROM dbo.Grupo), '|', (SELECT COUNT(*) FROM dbo.Horario), '|', (SELECT COUNT(*) FROM dbo.EstudianteGrupo), '|',
    (SELECT COUNT(*) FROM dbo.EstudiantePrograma), '|', (SELECT COUNT(*) FROM dbo.Sesion), '|', (SELECT COUNT(*) FROM dbo.Asistencia), '|',
    (SELECT COUNT(*) FROM dbo.DetalleAsistencia), '|', (SELECT COUNT(*) FROM dbo.SolicitudRevisionAsistencia)),
    (SELECT COUNT(*) FROM dbo.Grupo WHERE id = 'C1B00000-0000-4000-8000-00000000000C'),
    (SELECT COUNT(*) FROM dbo.Facultad WHERE nombre = N'CULM1-Facultad B');
GO
:r /tmp/test/fixtures/culm1_segundo_ambito.sql
GO
SET NOCOUNT ON;
INSERT INTO #snap (fase, valor, propias, facultadPorNombre)
SELECT 'S2', CONCAT((SELECT COUNT(*) FROM dbo.Usuario), '|', (SELECT COUNT(*) FROM dbo.Estudiante), '|', (SELECT COUNT(*) FROM dbo.Docente), '|',
    (SELECT COUNT(*) FROM dbo.Coordinador), '|', (SELECT COUNT(*) FROM dbo.Decano), '|', (SELECT COUNT(*) FROM dbo.Facultad), '|',
    (SELECT COUNT(*) FROM dbo.Programa), '|', (SELECT COUNT(*) FROM dbo.PlanEstudio), '|', (SELECT COUNT(*) FROM dbo.Asignatura), '|',
    (SELECT COUNT(*) FROM dbo.Grupo), '|', (SELECT COUNT(*) FROM dbo.Horario), '|', (SELECT COUNT(*) FROM dbo.EstudianteGrupo), '|',
    (SELECT COUNT(*) FROM dbo.EstudiantePrograma), '|', (SELECT COUNT(*) FROM dbo.Sesion), '|', (SELECT COUNT(*) FROM dbo.Asistencia), '|',
    (SELECT COUNT(*) FROM dbo.DetalleAsistencia), '|', (SELECT COUNT(*) FROM dbo.SolicitudRevisionAsistencia)),
    (SELECT COUNT(*) FROM dbo.Grupo WHERE id = 'C1B00000-0000-4000-8000-00000000000C'),
    (SELECT COUNT(*) FROM dbo.Facultad WHERE nombre = N'CULM1-Facultad B');
GO
:r /tmp/test/fixtures/culm1_segundo_ambito_down.sql
GO
SET NOCOUNT ON;
INSERT INTO #snap (fase, valor, propias, facultadPorNombre)
SELECT 'S3', CONCAT((SELECT COUNT(*) FROM dbo.Usuario), '|', (SELECT COUNT(*) FROM dbo.Estudiante), '|', (SELECT COUNT(*) FROM dbo.Docente), '|',
    (SELECT COUNT(*) FROM dbo.Coordinador), '|', (SELECT COUNT(*) FROM dbo.Decano), '|', (SELECT COUNT(*) FROM dbo.Facultad), '|',
    (SELECT COUNT(*) FROM dbo.Programa), '|', (SELECT COUNT(*) FROM dbo.PlanEstudio), '|', (SELECT COUNT(*) FROM dbo.Asignatura), '|',
    (SELECT COUNT(*) FROM dbo.Grupo), '|', (SELECT COUNT(*) FROM dbo.Horario), '|', (SELECT COUNT(*) FROM dbo.EstudianteGrupo), '|',
    (SELECT COUNT(*) FROM dbo.EstudiantePrograma), '|', (SELECT COUNT(*) FROM dbo.Sesion), '|', (SELECT COUNT(*) FROM dbo.Asistencia), '|',
    (SELECT COUNT(*) FROM dbo.DetalleAsistencia), '|', (SELECT COUNT(*) FROM dbo.SolicitudRevisionAsistencia)),
    (SELECT COUNT(*) FROM dbo.Grupo WHERE id = 'C1B00000-0000-4000-8000-00000000000C'),
    (SELECT COUNT(*) FROM dbo.Facultad WHERE nombre = N'CULM1-Facultad B');
GO
SET NOCOUNT ON;
DECLARE @fallo NVARCHAR(400) = NULL;
IF @@TRANCOUNT <> 1
    SET @fallo = CONCAT('el fixture altero el nivel de transaccion del llamador: ', @@TRANCOUNT);
ELSE IF (SELECT propias FROM #snap WHERE fase = 'S0') <> 0 OR (SELECT propias FROM #snap WHERE fase = 'S1') <> 1
    SET @fallo = 'el fixture debe crear CULM1-Grupo B (C1B0...0C) y el _down retirarlo.';
ELSE IF (SELECT valor FROM #snap WHERE fase = 'S1') <> (SELECT valor FROM #snap WHERE fase = 'S2')
    SET @fallo = 'aplicar el fixture dos veces debe dejar los mismos conteos.';
ELSE IF (SELECT valor FROM #snap WHERE fase = 'S3') <> (SELECT valor FROM #snap WHERE fase = 'S0')
    SET @fallo = 'el _down debe dejar los conteos como antes del fixture.';
ELSE IF (SELECT facultadPorNombre FROM #snap WHERE fase = 'S3') <> 1
    SET @fallo = 'el _down no debe borrar una CULM1-Facultad B que ya existia.';
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
DROP TABLE #snap;
IF @fallo IS NOT NULL
BEGIN
    SET @fallo = CONCAT(N'TEST FAILED: A2-T-18 ', @fallo);
    THROW 58600, @fallo, 1;
END
PRINT 'TEST_PASS:CULM001A2_T18_FIXTURE_IDEMPOTENTE';
IF @@TRANCOUNT <> 0 THROW 58699, 'TEST FAILED: test_culm001_a_fixture_segundo_ambito dejo transacciones abiertas.', 1;
PRINT 'TEST END: test_culm001_a_fixture_segundo_ambito';
GO
