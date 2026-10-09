USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT 'TEST START: test_uv_estudiante_programa_identity';

-- LB-008 JPA-05: dbo.uv_estudiante_programa debe devolver exactamente una fila por dbo.EstudiantePrograma.id.
-- Causa previa: la vista unia uv_estudiante (estudiante x grupo x asignatura x programa), que expande la fila.
-- Correccion: la vista une uv_estudiante_identidad (una fila por estudiante). Shape publico sin cambios.
-- Ver docs/work-items/LB-008-JPA05-db-view-identity-alignment/.

-- 1) SHAPE: exactamente 5 columnas, en el orden y con los nombres publicos congelados.
DECLARE @expectedColumns TABLE (column_id INT NOT NULL, name SYSNAME NOT NULL);
INSERT INTO @expectedColumns (column_id, name)
VALUES (1, N'id'), (2, N'idEstudiante'), (3, N'nombreEstudiante'), (4, N'idPrograma'), (5, N'nombrePrograma');

IF (SELECT COUNT(*) FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.uv_estudiante_programa')) <> 5
    THROW 53000, 'TEST FAILED: VIEW_ESTUDIANTE_PROGRAMA_SHAPE no tiene exactamente 5 columnas.', 1;

IF EXISTS (
        SELECT column_id, name COLLATE Latin1_General_CS_AS FROM @expectedColumns
        EXCEPT
        SELECT column_id, name COLLATE Latin1_General_CS_AS FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.uv_estudiante_programa'))
   OR EXISTS (
        SELECT column_id, name COLLATE Latin1_General_CS_AS FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.uv_estudiante_programa')
        EXCEPT
        SELECT column_id, name COLLATE Latin1_General_CS_AS FROM @expectedColumns)
    THROW 53001, 'TEST FAILED: VIEW_ESTUDIANTE_PROGRAMA_SHAPE no coincide con id, idEstudiante, nombreEstudiante, idPrograma, nombrePrograma.', 1;

PRINT 'TEST_PASS:VIEW_ESTUDIANTE_PROGRAMA_SHAPE';

-- 2) IDENTITY: ningun id puede aparecer mas de una vez en la vista (estado actual de la base).
IF EXISTS (SELECT id FROM dbo.uv_estudiante_programa GROUP BY id HAVING COUNT(*) <> 1)
    THROW 53002, 'TEST FAILED: VIEW_ESTUDIANTE_PROGRAMA_IDENTITY encontro un id con cardinalidad distinta de 1.', 1;

PRINT 'TEST_PASS:VIEW_ESTUDIANTE_PROGRAMA_IDENTITY';

-- 3) CARDINALITY con fixture: un estudiante matriculado en dos grupos y una sola EstudiantePrograma.
--    Con la definicion anterior (uv_estudiante) este escenario producia 2 filas para el mismo id.
DECLARE @student UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Estudiante ORDER BY id);
DECLARE @program UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_programa ORDER BY id);
DECLARE @activeState UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_estado_estudiante_grupo WHERE codigo = 'A');
DECLARE @baseGroup UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_grupo WHERE grupoEstaHablitado = 1 ORDER BY id);
DECLARE @assignment UNIQUEIDENTIFIER = (SELECT idAsignatura FROM dbo.uv_grupo WHERE id = @baseGroup);
DECLARE @period UNIQUEIDENTIFIER = (SELECT idPeriodoAcademico FROM dbo.uv_grupo WHERE id = @baseGroup);
DECLARE @teacher UNIQUEIDENTIFIER = (SELECT idDocente FROM dbo.uv_grupo WHERE id = @baseGroup);
DECLARE @group1 UNIQUEIDENTIFIER = NEWID();
DECLARE @group2 UNIQUEIDENTIFIER = NEWID();
DECLARE @epId UNIQUEIDENTIFIER = NEWID();

IF @student IS NULL OR @program IS NULL OR @activeState IS NULL OR @baseGroup IS NULL OR @teacher IS NULL
    THROW 53010, 'TEST FAILED: VIEW_ESTUDIANTE_PROGRAMA fixture incompleto (estudiante, programa, grupo base o estado activo).', 1;

BEGIN TRANSACTION;
BEGIN TRY
    -- Grupos nuevos dentro de la transaccion (misma asignatura, periodo y docente que el grupo base); se descartan con ROLLBACK.
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes,
        cantidadEstudiantesFinalizaron, cantidadEstudiantesCancelaronVoluntadPropia,
        cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@group1, @assignment, @period, 500000 + ABS(CHECKSUM(NEWID()) % 100000), N'Grupo QA Identidad UEP 1', 0, 0, 0, 0, @teacher),
           (@group2, @assignment, @period, 500000 + ABS(CHECKSUM(NEWID()) % 100000), N'Grupo QA Identidad UEP 2', 0, 0, 0, 0, @teacher);

    INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo)
    VALUES (NEWID(), @activeState, @student, @group1),
           (NEWID(), @activeState, @student, @group2);

    INSERT INTO dbo.EstudiantePrograma (id, estudiante, programa)
    VALUES (@epId, @student, @program);

    IF (SELECT COUNT(*) FROM dbo.uv_estudiante WHERE id = @student) < 2
        THROW 53012, 'TEST FAILED: VIEW_ESTUDIANTE_PROGRAMA fixture no expande estudiante en dos grupos; escenario no representativo.', 1;

    IF (SELECT COUNT(*) FROM dbo.uv_estudiante_programa WHERE id = @epId) <> 1
        THROW 53013, 'TEST FAILED: VIEW_ESTUDIANTE_PROGRAMA_CARDINALITY produjo filas distintas de 1 para una EstudiantePrograma con dos grupos.', 1;

    IF (SELECT COUNT(*) FROM dbo.uv_estudiante_programa) <> (SELECT COUNT(*) FROM dbo.EstudiantePrograma)
        THROW 53014, 'TEST FAILED: COUNT(uv_estudiante_programa) difiere de COUNT(EstudiantePrograma).', 1;

    IF EXISTS (
        SELECT 1
        FROM dbo.uv_estudiante_programa v
        LEFT JOIN dbo.EstudiantePrograma ep ON ep.id = v.id
        WHERE ep.id IS NULL)
        THROW 53015, 'TEST FAILED: uv_estudiante_programa contiene un id que no es EstudiantePrograma.id.', 1;

    IF EXISTS (SELECT id FROM dbo.uv_estudiante_programa GROUP BY id HAVING COUNT(*) <> 1)
        THROW 53016, 'TEST FAILED: VIEW_ESTUDIANTE_PROGRAMA_IDENTITY fallo con el fixture de dos grupos.', 1;

    PRINT 'TEST_PASS:VIEW_ESTUDIANTE_PROGRAMA_CARDINALITY';

    -- 4) DEPENDENCY: uv_estudiante_programa debe depender de uv_estudiante_identidad y NO de uv_estudiante.
    IF NOT EXISTS (
        SELECT 1 FROM sys.sql_expression_dependencies
        WHERE referencing_id = OBJECT_ID(N'dbo.uv_estudiante_programa')
          AND referenced_id = OBJECT_ID(N'dbo.uv_estudiante_identidad'))
        THROW 53020, 'TEST FAILED: uv_estudiante_programa no depende de uv_estudiante_identidad.', 1;

    IF EXISTS (
        SELECT 1 FROM sys.sql_expression_dependencies
        WHERE referencing_id = OBJECT_ID(N'dbo.uv_estudiante_programa')
          AND referenced_id = OBJECT_ID(N'dbo.uv_estudiante'))
        THROW 53021, 'TEST FAILED: uv_estudiante_programa aun depende de uv_estudiante (expansion estudiante x grupo).', 1;

    PRINT 'TEST_PASS:VIEW_ESTUDIANTE_PROGRAMA_DEPENDENCY';

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

IF @@TRANCOUNT <> 0 THROW 53099, 'TEST FAILED: test_uv_estudiante_programa_identity left an open transaction.', 1;

PRINT 'TEST END: test_uv_estudiante_programa_identity';
GO
