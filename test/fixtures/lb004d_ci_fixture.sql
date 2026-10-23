USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/*
   LB-004D CI fixture. This is test data, not deployment seed data.
   It is intentionally limited to one second teacher, one second student,
   one second group and one enrollment so test_lb004d_support_binding.sql
   can resolve its cross-group and cross-owner matrix on a fresh CI database.
*/
IF DB_NAME() <> N'gestionasistenciadb'
    THROW 52310, 'BLOCKED: LB004D fixture requires gestionasistenciadb.', 1;
IF CONVERT(NVARCHAR(200), SERVERPROPERTY('Edition')) NOT LIKE N'%Developer%'
    THROW 52311, 'BLOCKED: LB004D fixture is restricted to SQL Server Developer Edition.', 1;

DECLARE @typeCc UNIQUEIDENTIFIER = (
    SELECT TOP (1) id FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = 'CC'
);
DECLARE @activeState UNIQUEIDENTIFIER = (
    SELECT TOP (1) id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'A'
);
DECLARE @baseGroup UNIQUEIDENTIFIER;
DECLARE @assignment UNIQUEIDENTIFIER;
DECLARE @period UNIQUEIDENTIFIER;
DECLARE @baseTeacher UNIQUEIDENTIFIER;

SELECT TOP (1)
    @baseGroup = g.id,
    @assignment = g.asignatura,
    @period = g.periodoAcademico,
    @baseTeacher = g.docente
FROM dbo.Grupo g
WHERE (SELECT COUNT(*)
       FROM dbo.uv_estudiante_grupo eg
       WHERE eg.idGrupo = g.id AND eg.codigoEstadoEstudiante = 'A') >= 2
ORDER BY g.id;

IF @typeCc IS NULL OR @activeState IS NULL OR @baseGroup IS NULL OR @assignment IS NULL
   OR @period IS NULL OR @baseTeacher IS NULL
    THROW 52312, 'BLOCKED: LB004D fixture requires the canonical CC, active-state and base-group seeds.', 1;

DECLARE @fixtureTeacherUser UNIQUEIDENTIFIER = 'D004D001-004D-4D00-8000-000000000001';
DECLARE @fixtureTeacher UNIQUEIDENTIFIER = 'D004D002-004D-4D00-8000-000000000002';
DECLARE @fixtureStudentUser UNIQUEIDENTIFIER = 'D004D003-004D-4D00-8000-000000000003';
DECLARE @fixtureStudent UNIQUEIDENTIFIER = 'D004D004-004D-4D00-8000-000000000004';
DECLARE @fixtureGroup UNIQUEIDENTIFIER = 'D004D005-004D-4D00-8000-000000000005';
DECLARE @fixtureEnrollment UNIQUEIDENTIFIER = 'D004D006-004D-4D00-8000-000000000006';
DECLARE @teacherEmail NVARCHAR(100) = N'lb004d-ci.teacher2@fixture.invalid';
DECLARE @studentEmail NVARCHAR(100) = N'lb004d-ci.studentC@fixture.invalid';

IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE (id = @fixtureTeacherUser AND correo <> @teacherEmail)
                                      OR (correo = @teacherEmail AND id <> @fixtureTeacherUser))
    THROW 52313, 'LB004D fixture identity conflict for teacher user.', 1;
IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE (id = @fixtureStudentUser AND correo <> @studentEmail)
                                      OR (correo = @studentEmail AND id <> @fixtureStudentUser))
    THROW 52314, 'LB004D fixture identity conflict for student user.', 1;
IF EXISTS (SELECT 1 FROM dbo.Docente WHERE id = @fixtureTeacher AND usuario <> @fixtureTeacherUser)
    THROW 52315, 'LB004D fixture identity conflict for teacher.', 1;
IF EXISTS (SELECT 1 FROM dbo.Estudiante WHERE id = @fixtureStudent AND usuario <> @fixtureStudentUser)
    THROW 52316, 'LB004D fixture identity conflict for student.', 1;

IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @fixtureTeacherUser)
BEGIN
    INSERT dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido,
                        primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@fixtureTeacherUser, @typeCc, 99040002, N'Fixture', N'LB004D', N'Teacher', N'CI',
            @teacherEmail, 1, 1, N'NOT_A_CREDENTIAL_FIXTURE');
END;

IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @fixtureStudentUser)
BEGIN
    INSERT dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido,
                        primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@fixtureStudentUser, @typeCc, 99040003, N'Fixture', N'LB004D', N'Student', N'CI',
            @studentEmail, 1, 1, N'NOT_A_CREDENTIAL_FIXTURE');
END;

IF NOT EXISTS (SELECT 1 FROM dbo.Docente WHERE id = @fixtureTeacher)
    INSERT dbo.Docente (id, usuario) VALUES (@fixtureTeacher, @fixtureTeacherUser);
IF NOT EXISTS (SELECT 1 FROM dbo.Estudiante WHERE id = @fixtureStudent)
    INSERT dbo.Estudiante (id, usuario) VALUES (@fixtureStudent, @fixtureStudentUser);

IF NOT EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @fixtureGroup)
BEGIN
    INSERT dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes,
                      cantidadEstudiantesFinalizaron, cantidadEstudiantesCancelaronVoluntadPropia,
                      cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@fixtureGroup, @assignment, @period, 94002, N'FIXTURE LB004D CI', 1, 0, 0, 0, @fixtureTeacher);
END
ELSE
BEGIN
    UPDATE dbo.Grupo
       SET asignatura = @assignment,
           periodoAcademico = @period,
           codigo = 94002,
           nombre = N'FIXTURE LB004D CI',
           cantidadEstudiantes = 1,
           cantidadEstudiantesFinalizaron = 0,
           cantidadEstudiantesCancelaronVoluntadPropia = 0,
           cantidadEstudiantesCancelaronAutomaticamente = 0,
           docente = @fixtureTeacher
     WHERE id = @fixtureGroup;
END;

IF NOT EXISTS (SELECT 1 FROM dbo.EstudianteGrupo WHERE id = @fixtureEnrollment)
    INSERT dbo.EstudianteGrupo (id, estado, estudiante, grupo)
    VALUES (@fixtureEnrollment, @activeState, @fixtureStudent, @fixtureGroup);
ELSE
    UPDATE dbo.EstudianteGrupo
       SET estado = @activeState, estudiante = @fixtureStudent, grupo = @fixtureGroup
     WHERE id = @fixtureEnrollment;

-- HU091 R2: el docente del fixture tiene grupo, por lo tanto debe tener su vinculo docente-programa.
INSERT dbo.DocentePrograma (id, docente, programa, tipoVinculacion, estado, fechaVinculacionUtc)
SELECT NEWID(), par.idDocente, par.idPrograma,
       (SELECT TOP 1 tv.id FROM dbo.TipoVinculacion tv WHERE tv.codigo = 'PLA' AND tv.estado = 1),
       1, SYSUTCDATETIME()
FROM (SELECT DISTINCT id AS idDocente, idPrograma FROM dbo.uv_docente WHERE id = @fixtureTeacher) par
WHERE NOT EXISTS (SELECT 1 FROM dbo.DocentePrograma dp WHERE dp.docente = par.idDocente AND dp.programa = par.idPrograma);
SELECT CONCAT(
    'TEST_FIXTURE_READY|LB004D|base_group=', CONVERT(VARCHAR(36), @baseGroup),
    '|group2=1|teacher2=1|studentC=1|active_enrollment=1'
);
GO
