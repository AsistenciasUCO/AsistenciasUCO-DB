USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/* Cleanup is deliberately restricted to the deterministic LB-004D fixture namespace. */
IF DB_NAME() <> N'gestionasistenciadb'
    THROW 52320, 'BLOCKED: LB004D fixture cleanup requires gestionasistenciadb.', 1;
IF CONVERT(NVARCHAR(200), SERVERPROPERTY('Edition')) NOT LIKE N'%Developer%'
    THROW 52321, 'BLOCKED: LB004D fixture cleanup is restricted to SQL Server Developer Edition.', 1;

DECLARE @fixtureTeacherUser UNIQUEIDENTIFIER = 'D004D001-004D-4D00-8000-000000000001';
DECLARE @fixtureTeacher UNIQUEIDENTIFIER = 'D004D002-004D-4D00-8000-000000000002';
DECLARE @fixtureStudentUser UNIQUEIDENTIFIER = 'D004D003-004D-4D00-8000-000000000003';
DECLARE @fixtureStudent UNIQUEIDENTIFIER = 'D004D004-004D-4D00-8000-000000000004';
DECLARE @fixtureGroup UNIQUEIDENTIFIER = 'D004D005-004D-4D00-8000-000000000005';
DECLARE @fixtureEnrollment UNIQUEIDENTIFIER = 'D004D006-004D-4D00-8000-000000000006';

IF EXISTS (SELECT 1 FROM dbo.Sesion WHERE grupo = @fixtureGroup)
    THROW 52322, 'BLOCKED: LB004D fixture group has sessions; cleanup will not delete them.', 1;
IF EXISTS (SELECT 1 FROM dbo.Asistencia a JOIN dbo.EstudianteGrupo eg ON eg.id = a.estudianteGrupo WHERE eg.grupo = @fixtureGroup)
    THROW 52323, 'BLOCKED: LB004D fixture group has attendance; cleanup will not delete it.', 1;

DELETE FROM dbo.EstudianteGrupo
 WHERE id = @fixtureEnrollment OR estudiante = @fixtureStudent OR grupo = @fixtureGroup;
DELETE FROM dbo.Grupo WHERE id = @fixtureGroup;
DELETE FROM dbo.Estudiante WHERE id = @fixtureStudent AND usuario = @fixtureStudentUser;
DELETE FROM dbo.DocentePrograma WHERE docente = @fixtureTeacher;
DELETE FROM dbo.Docente WHERE id = @fixtureTeacher AND usuario = @fixtureTeacherUser;
DELETE FROM dbo.Usuario WHERE id IN (@fixtureTeacherUser, @fixtureStudentUser);

SELECT 'TEST_FIXTURE_CLEANED|LB004D' AS evidence;
GO
