USE [gestionasistenciadb];
GO

/*
  Isolated Java-integration data fixture for MAINT-003H.
  It is NOT deployment seed data: it is executed explicitly (test/prepare_java_integration_fixture.ps1) only against
  the controlled Developer SQL Server container. It gives the three data-dependent Failsafe scenarios the rows they
  need to RUN instead of being skipped by Assumptions.assumeTrue (the tests and their assumptions are unchanged):
    * DocenteRepositorySqlServerIT.uv_docente_puede_devolver_multiples_filas_para_un_docente -> a teacher with >1 groups
    * DocenteRepositorySqlServerIT.docente_puede_no_tener_filas_en_uv_docente               -> a teacher with no groups
    * AcademicQueryJpaParityIT.horarios_conservan_horas_locales_y_nulos                     -> live teacher/student schedules
  Idempotent: rows are tagged (group name, e-mail, unusual 05:xx times) and removed before being recreated. Direct
  DML is used only because no public procedure creates schedules; user creation goes through the public provider.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @tag NVARCHAR(50) = N'IT-MAINT003H';
DECLARE @groupName NVARCHAR(50) = N'IT-MAINT003H-G2';
DECLARE @emptyTeacherEmail NVARCHAR(100) = N'it.maint003h.docente.sin.grupo@test.local';
DECLARE @baseGroup UNIQUEIDENTIFIER;
DECLARE @dayMonday UNIQUEIDENTIFIER;
DECLARE @tipo UNIQUEIDENTIFIER;
DECLARE @emptyTeacherUser UNIQUEIDENTIFIER;
DECLARE @correlation UNIQUEIDENTIFIER = NEWID();
DECLARE @result TABLE (
    idCorrelacion UNIQUEIDENTIFIER,
    mensajeUsuarioResultado NVARCHAR(4000),
    mensajeTecnicoResultado NVARCHAR(4000),
    estadoResultado BIT
);

BEGIN TRANSACTION;

-- Idempotent cleanup of rows created by a previous preparation
DELETE h FROM dbo.Horario h
INNER JOIN dbo.Grupo g ON g.id = h.grupo
WHERE g.nombre = @groupName;
DELETE FROM dbo.Horario WHERE horaInicio = '05:00' AND horaFin = '05:30';
DELETE FROM dbo.Grupo WHERE nombre = @groupName;
DELETE d FROM dbo.Docente d
INNER JOIN dbo.Usuario u ON u.id = d.usuario
WHERE u.correo = @emptyTeacherEmail;
DELETE FROM dbo.Usuario WHERE correo = @emptyTeacherEmail;

-- Base group: the teacher-owned group that already has active students (same shape the MAINT-003G fixture needs)
SELECT TOP (1) @baseGroup = g.id
FROM dbo.Grupo g
INNER JOIN dbo.EstudianteGrupo eg ON eg.grupo = g.id
INNER JOIN dbo.EstadoEstudianteGrupo eeg ON eeg.id = eg.estado AND eeg.codigo = 'A'
WHERE g.nombre <> @groupName
GROUP BY g.id
ORDER BY g.id;
SELECT TOP (1) @dayMonday = id FROM dbo.Dia WHERE codigo = 'LU';
SELECT TOP (1) @tipo = id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC';
IF @baseGroup IS NULL OR @dayMonday IS NULL OR @tipo IS NULL
    THROW 52301, 'MAINT-003H fixture requires a group with active students, the Lunes day and the CC identification type.', 1;

-- 1) Teacher with more than one assignment: a second group for the same teacher/subject/period
SELECT * INTO #g2 FROM dbo.Grupo WHERE id = @baseGroup;
UPDATE #g2 SET id = NEWID(), nombre = @groupName, codigo = (SELECT MAX(codigo) + 1 FROM dbo.Grupo);
INSERT INTO dbo.Grupo SELECT * FROM #g2;
DROP TABLE #g2;

-- 2) Live schedules (teacher and student views): rows on the base group with unusual local times
INSERT INTO dbo.Horario (id, grupo, dia, horaInicio, horaFin)
VALUES (NEWID(), @baseGroup, @dayMonday, '05:00', '05:30');

-- 3) Teacher with no groups: user through the PUBLIC provider, then the Docente role row
INSERT INTO @result
EXEC dbo.usp_sincronizar_usuario
    @idTipoIdIdentificacion = @tipo, @numeroIdentificacion = 1800000001,
    @primerApellido = N'Fixture', @segundoApellido = N'Maint003h', @primerNombre = N'Docente', @segundoNombre = N'SinGrupo',
    @correo = @emptyTeacherEmail, @password = N'HashBackend_Maint003hFixture_NotASecret', @idCorrelacion = @correlation;
IF NOT EXISTS (SELECT 1 FROM @result WHERE estadoResultado = 1)
    THROW 52302, 'MAINT-003H fixture user creation was rejected by usp_sincronizar_usuario.', 1;
SELECT @emptyTeacherUser = id FROM dbo.Usuario WHERE correo = @emptyTeacherEmail;
INSERT INTO dbo.Docente (id, usuario) VALUES (NEWID(), @emptyTeacherUser);

IF NOT EXISTS (SELECT 1 FROM dbo.uv_docente GROUP BY id HAVING COUNT(*) > 1)
    THROW 52303, 'MAINT-003H fixture did not produce a teacher with multiple assignments.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.uv_docente_identidad i WHERE NOT EXISTS (SELECT 1 FROM dbo.uv_docente d WHERE d.id = i.id))
    THROW 52304, 'MAINT-003H fixture did not produce a teacher without assignments.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.uv_horario_docente) OR NOT EXISTS (SELECT 1 FROM dbo.uv_horario_estudiante)
    THROW 52305, 'MAINT-003H fixture did not produce live teacher and student schedules.', 1;

COMMIT TRANSACTION;

SELECT CONCAT('TEST_FIXTURE_READY|maint003h|multi=1|empty=1|horarios=',
    (SELECT COUNT(*) FROM dbo.uv_horario_docente), '|', (SELECT COUNT(*) FROM dbo.uv_horario_estudiante));
GO
