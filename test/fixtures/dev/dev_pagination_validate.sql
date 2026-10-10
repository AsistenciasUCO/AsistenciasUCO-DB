USE [gestionasistenciadb];
GO
/*
  MAINT-003K - validacion de los fixtures sinteticos de desarrollo (solo lectura).
  Verifica: cardinalidades exactas, duplicados multi-grupo, orden estable + paginacion (primera/ultima/fuera de rango/vacia),
  filtros, estados academicos, sesiones UTC DATETIME2(7) con procedencia y asistencia. Falla con THROW ante cualquier desvio.
*/
SET NOCOUNT ON;

DECLARE @esc TABLE (code INT, size INT);
INSERT INTO @esc (code, size)
SELECT v.code, v.size
FROM (VALUES (1, 300), (2, 1000), (3, 5000)) v(code, size)
WHERE EXISTS (SELECT 1 FROM dbo.Grupo g WHERE g.id = CONVERT(UNIQUEIDENTIFIER, CONCAT('DE000005-0000-4000-8000-', RIGHT(CONCAT('000000000000', CONVERT(VARCHAR(8), CONVERT(VARBINARY(4), v.code), 2)), 12))));
IF NOT EXISTS (SELECT 1 FROM @esc) THROW 56001, 'VALIDATE FAILED: no fixture groups found.', 1;

DECLARE @code INT, @size INT, @g UNIQUEIDENTIFIER, @n INT, @expected INT, @h1 VARBINARY(32), @h2 VARBINARY(32), @pageSize INT, @pages INT, @last INT, @off INT;
DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT code, size FROM @esc ORDER BY code;
OPEN cur;
FETCH NEXT FROM cur INTO @code, @size;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @g = CONVERT(UNIQUEIDENTIFIER, CONCAT('DE000005-0000-4000-8000-', RIGHT(CONCAT('000000000000', CONVERT(VARCHAR(8), CONVERT(VARBINARY(4), @code), 2)), 12)));

    -- V1: cardinalidad de matriculas y filas de uv_estudiante (una por matricula) en el grupo
    SELECT @n = COUNT(*) FROM dbo.EstudianteGrupo WHERE grupo = @g;
    IF @n <> @size THROW 56010, 'VALIDATE FAILED: enrollments <> scenario size.', 1;
    SELECT @n = COUNT(*) FROM dbo.uv_estudiante WHERE idGrupo = @g;
    IF @n <> @size THROW 56011, 'VALIDATE FAILED: uv_estudiante rows <> scenario size.', 1;
    SELECT @n = COUNT(DISTINCT id) FROM dbo.uv_estudiante WHERE idGrupo = @g;
    IF @n <> @size THROW 56012, 'VALIDATE FAILED: distinct students in group <> scenario size.', 1;

    -- V2: estados academicos exactos (i%50: 0=CI, 1=CVP, 2=F, 3=I, resto=A)
    SELECT @expected = COUNT(*) FROM GENERATE_SERIES(1, @size) s WHERE s.value % 50 = 0;
    SELECT @n = COUNT(*) FROM dbo.uv_estudiante_grupo WHERE idGrupo = @g AND codigoEstadoEstudiante = 'CI';
    IF @n <> @expected THROW 56013, 'VALIDATE FAILED: CI count.', 1;
    SELECT @expected = COUNT(*) FROM GENERATE_SERIES(1, @size) s WHERE s.value % 50 NOT IN (0, 1, 2, 3);
    SELECT @n = COUNT(*) FROM dbo.uv_estudiante_grupo WHERE idGrupo = @g AND codigoEstadoEstudiante = 'A';
    IF @n <> @expected THROW 56014, 'VALIDATE FAILED: A count.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @g AND cantidadEstudiantes = @size
        AND cantidadEstudiantesFinalizaron = (SELECT COUNT(*) FROM GENERATE_SERIES(1, @size) s WHERE s.value % 50 = 2)
        AND cantidadEstudiantesCancelaronVoluntadPropia = (SELECT COUNT(*) FROM GENERATE_SERIES(1, @size) s WHERE s.value % 50 = 1)
        AND cantidadEstudiantesCancelaronAutomaticamente = (SELECT COUNT(*) FROM GENERATE_SERIES(1, @size) s WHERE s.value % 50 = 0))
        THROW 56015, 'VALIDATE FAILED: group counters do not match the enrollment distribution.', 1;

    -- V3: orden estable (nombreCompleto, id): dos ejecuciones identicas y paginas concatenadas == lista completa
    SET @pageSize = CASE WHEN @size = 300 THEN 40 ELSE 100 END;
    SET @pages = (@size + @pageSize - 1) / @pageSize;
    SET @last = @size - (@pages - 1) * @pageSize;
    SELECT @h1 = HASHBYTES('SHA2_256', STRING_AGG(CONVERT(VARCHAR(MAX), id), ',') WITHIN GROUP (ORDER BY nombreCompleto, id))
    FROM dbo.uv_estudiante WHERE idGrupo = @g;
    SELECT @h2 = HASHBYTES('SHA2_256', STRING_AGG(CONVERT(VARCHAR(MAX), id), ',') WITHIN GROUP (ORDER BY nombreCompleto, id))
    FROM dbo.uv_estudiante WHERE idGrupo = @g;
    IF @h1 <> @h2 THROW 56016, 'VALIDATE FAILED: ordering is not stable between executions.', 1;

    DECLARE @paged TABLE (pos INT IDENTITY(1,1), id UNIQUEIDENTIFIER);
    DELETE FROM @paged;
    DECLARE @p INT = 0;
    WHILE @p < @pages
    BEGIN
        INSERT INTO @paged (id)
        SELECT id FROM dbo.uv_estudiante WHERE idGrupo = @g ORDER BY nombreCompleto, id OFFSET @p * @pageSize ROWS FETCH NEXT @pageSize ROWS ONLY;
        SET @p += 1;
    END
    IF (SELECT COUNT(*) FROM @paged) <> @size THROW 56017, 'VALIDATE FAILED: paged rows <> size (gap or overlap).', 1;
    IF (SELECT COUNT(DISTINCT id) FROM @paged) <> @size THROW 56018, 'VALIDATE FAILED: duplicate students across pages.', 1;
    IF (SELECT HASHBYTES('SHA2_256', STRING_AGG(CONVERT(VARCHAR(MAX), id), ',') WITHIN GROUP (ORDER BY pos)) FROM @paged) <> @h1
        THROW 56019, 'VALIDATE FAILED: concatenated pages differ from the full ordered list.', 1;
    -- primera pagina: tamano completo; ultima: resto; fuera de rango y vacio
    SET @off = (@pages - 1) * @pageSize;
    SELECT @n = COUNT(*) FROM (SELECT id FROM dbo.uv_estudiante WHERE idGrupo = @g ORDER BY nombreCompleto, id OFFSET @off ROWS FETCH NEXT @pageSize ROWS ONLY) t;
    IF @n <> @last THROW 56020, 'VALIDATE FAILED: last page size.', 1;
    SET @off = @pages * @pageSize;
    SELECT @n = COUNT(*) FROM (SELECT id FROM dbo.uv_estudiante WHERE idGrupo = @g ORDER BY nombreCompleto, id OFFSET @off ROWS FETCH NEXT @pageSize ROWS ONLY) t;
    IF @n <> 0 THROW 56021, 'VALIDATE FAILED: out-of-range page must be empty.', 1;
    SELECT @n = COUNT(*) FROM dbo.uv_estudiante WHERE idGrupo = @g AND nombreCompleto LIKE N'%zzzz-no-existe%';
    IF @n <> 0 THROW 56022, 'VALIDATE FAILED: empty filter must return no rows.', 1;

    -- V4: parejas con el mismo nombre completo (desempate por id)
    IF @size >= 50 AND NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante WHERE idGrupo = @g GROUP BY nombreCompleto HAVING COUNT(*) > 1)
        THROW 56023, 'VALIDATE FAILED: expected same-name pairs to exercise the id tie-break.', 1;

    -- V5: sesiones UTC DATETIME2(7) con procedencia; la sesion 1 conserva 100 ns
    SELECT @n = COUNT(*) FROM dbo.Sesion WHERE grupo = @g AND procedenciaTemporal = N'UTC_V2' AND LEFT(CONVERT(CHAR(36), id), 6) = 'DE0000';
    IF @n <> 4 THROW 56024, 'VALIDATE FAILED: expected 4 UTC_V2 sessions.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Sesion WHERE grupo = @g AND numero = 1
        AND fechaHoraInicio = CAST('2026-09-14T13:00:00.1234567' AS DATETIME2(7)) AND fechaHoraFin = CAST('2026-09-14T15:00:00.7654321' AS DATETIME2(7)))
        THROW 56025, 'VALIDATE FAILED: session 1 lost 100 ns precision.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_sesion_v2 WHERE idGrupo = @g AND procedenciaTemporal = N'UTC_V2') THROW 56026, 'VALIDATE FAILED: uv_sesion_v2 does not expose the sessions.', 1;

    -- (Solo se cuentan filas del fixture, prefijo DE0000: otros tests pueden agregar sesiones propias al grupo, p. ej. el fixture Java IT-MAINT003G.)
    -- V6: asistencia (solo matriculas A): sesion 1 siempre; el grupo 300 ademas sesiones 2 y 3
    SELECT @expected = COUNT(*) * (CASE WHEN @size = 300 THEN 3 ELSE 1 END) FROM GENERATE_SERIES(1, @size) s WHERE s.value % 50 NOT IN (0, 1, 2, 3);
    SELECT @n = COUNT(*) FROM dbo.Asistencia a JOIN dbo.Sesion ses ON ses.id = a.sesion WHERE ses.grupo = @g AND LEFT(CONVERT(CHAR(36), ses.id), 6) = 'DE0000';
    IF @n <> @expected THROW 56027, 'VALIDATE FAILED: attendance rows.', 1;
    SELECT @n = COUNT(*) FROM dbo.DetalleAsistencia d JOIN dbo.Asistencia a ON a.id = d.asistencia JOIN dbo.Sesion ses ON ses.id = a.sesion WHERE ses.grupo = @g AND LEFT(CONVERT(CHAR(36), ses.id), 6) = 'DE0000'
        AND d.fechaHoraInicio = ses.fechaHoraInicio AND d.fechaHoraFin = ses.fechaHoraFin;
    IF @n <> @expected THROW 56028, 'VALIDATE FAILED: attendance detail snapshot differs from the session.', 1;

    PRINT CONCAT('TEST_PASS:DEV_FIXTURE_SCENARIO_', @size);
    FETCH NEXT FROM cur INTO @code, @size;
END
CLOSE cur; DEALLOCATE cur;

-- Duplicados multi-grupo (solo si estan cargados los tres escenarios): 1..300 en 3 grupos, 301..1000 en 2, el resto en 1
IF (SELECT COUNT(*) FROM @esc) = 3
BEGIN
    IF (SELECT COUNT(*) FROM (SELECT id FROM dbo.uv_estudiante WHERE LEFT(CONVERT(CHAR(36), id), 6) = 'DE0000' GROUP BY id HAVING COUNT(DISTINCT idGrupo) = 3) t) <> 300
        THROW 56030, 'VALIDATE FAILED: expected 300 students enrolled in three groups.', 1;
    IF (SELECT COUNT(*) FROM (SELECT id FROM dbo.uv_estudiante WHERE LEFT(CONVERT(CHAR(36), id), 6) = 'DE0000' GROUP BY id HAVING COUNT(DISTINCT idGrupo) = 2) t) <> 700
        THROW 56031, 'VALIDATE FAILED: expected 700 students enrolled in two groups.', 1;
    PRINT 'TEST_PASS:DEV_FIXTURE_MULTIGROUP_DUPLICATES';
END

-- Integridad referencial de toda la base
DECLARE @chk TABLE (tbl NVARCHAR(256), cons NVARCHAR(256), wh NVARCHAR(MAX));
INSERT INTO @chk EXEC ('DBCC CHECKCONSTRAINTS WITH ALL_CONSTRAINTS, NO_INFOMSGS');
IF EXISTS (SELECT 1 FROM @chk) THROW 56040, 'VALIDATE FAILED: DBCC CHECKCONSTRAINTS reported violations.', 1;
PRINT 'TEST_PASS:DEV_FIXTURE_REFERENTIAL_INTEGRITY';

SELECT
    (SELECT COUNT(*) FROM dbo.Usuario WHERE LEFT(CONVERT(CHAR(36), id), 6) = 'DE0000') AS usuarios,
    (SELECT COUNT(*) FROM dbo.Estudiante WHERE LEFT(CONVERT(CHAR(36), id), 6) = 'DE0000') AS estudiantes,
    (SELECT COUNT(*) FROM dbo.Docente WHERE LEFT(CONVERT(CHAR(36), id), 6) = 'DE0000') AS docentes,
    (SELECT COUNT(*) FROM dbo.Grupo WHERE LEFT(CONVERT(CHAR(36), id), 6) = 'DE0000') AS grupos,
    (SELECT COUNT(*) FROM dbo.EstudianteGrupo WHERE LEFT(CONVERT(CHAR(36), id), 6) = 'DE0000') AS matriculas,
    (SELECT COUNT(*) FROM dbo.Sesion WHERE LEFT(CONVERT(CHAR(36), id), 6) = 'DE0000') AS sesiones,
    (SELECT COUNT(*) FROM dbo.Asistencia WHERE LEFT(CONVERT(CHAR(36), id), 6) = 'DE0000') AS asistencias,
    (SELECT COUNT(*) FROM dbo.DetalleAsistencia WHERE LEFT(CONVERT(CHAR(36), id), 6) = 'DE0000') AS detalles;
PRINT 'DEV_FIXTURE_VALIDATE_OK';
GO
