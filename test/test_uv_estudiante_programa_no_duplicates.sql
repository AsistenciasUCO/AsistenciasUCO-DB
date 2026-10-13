USE [gestionasistenciadb];
GO
-- MAINT-003K: uv_estudiante_programa expone EXACTAMENTE una fila por EstudiantePrograma aunque el estudiante este
-- matriculado en varios grupos (antes: una fila por matricula). Transaccion revertida; no deja datos.
SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT 'TEST START: test_uv_estudiante_programa_no_duplicates';

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @baseGrupo UNIQUEIDENTIFIER = (SELECT TOP (1) id FROM dbo.Grupo ORDER BY id);
    DECLARE @programa UNIQUEIDENTIFIER = (SELECT TOP (1) id FROM dbo.Programa ORDER BY id);
    DECLARE @tipo UNIQUEIDENTIFIER = (SELECT TOP (1) id FROM dbo.TipoIdentificacion ORDER BY id);
    DECLARE @estadoA UNIQUEIDENTIFIER = (SELECT TOP (1) id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'A');
    IF @baseGrupo IS NULL OR @programa IS NULL OR @tipo IS NULL OR @estadoA IS NULL
        THROW 53301, 'TEST FAILED: UV_ESTUDIANTE_PROGRAMA_NO_DUPLICATES base seed missing.', 1;

    DECLARE @usuario UNIQUEIDENTIFIER = NEWID(), @estudiante UNIQUEIDENTIFIER = NEWID(), @ep UNIQUEIDENTIFIER = NEWID();
    DECLARE @grupo2 UNIQUEIDENTIFIER = NEWID(), @grupo3 UNIQUEIDENTIFIER = NEWID();
    DECLARE @codigo INT = (SELECT ISNULL(MAX(codigo), 0) + 1000 FROM dbo.Grupo);

    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@usuario, @tipo, 2100000001, N'Multigrupo', N'', N'Prueba', N'', N'multigrupo.prueba@fixture.invalid', 1, 1, N'FIXTURE_DISABLED_ACCOUNT');
    INSERT INTO dbo.Estudiante (id, usuario) VALUES (@estudiante, @usuario);
    INSERT INTO dbo.EstudiantePrograma (id, estudiante, programa) VALUES (@ep, @estudiante, @programa);

    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron, cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    SELECT @grupo2, asignatura, periodoAcademico, @codigo + 1, N'Multigrupo 2', 1, 0, 0, 0, docente FROM dbo.Grupo WHERE id = @baseGrupo;
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron, cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    SELECT @grupo3, asignatura, periodoAcademico, @codigo + 2, N'Multigrupo 3', 1, 0, 0, 0, docente FROM dbo.Grupo WHERE id = @baseGrupo;

    INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo)
    VALUES (NEWID(), @estadoA, @estudiante, @baseGrupo), (NEWID(), @estadoA, @estudiante, @grupo2), (NEWID(), @estadoA, @estudiante, @grupo3);

    IF (SELECT COUNT(*) FROM dbo.uv_estudiante WHERE id = @estudiante) < 3
        THROW 53302, 'TEST FAILED: UV_ESTUDIANTE_PROGRAMA_NO_DUPLICATES precondition: the student must have 3 academic-context rows.', 1;
    IF (SELECT COUNT(*) FROM dbo.uv_estudiante_programa WHERE id = @ep) <> 1
        THROW 53303, 'TEST FAILED: UV_ESTUDIANTE_PROGRAMA_NO_DUPLICATES one EstudiantePrograma produced several rows for a multi-group student.', 1;
    IF EXISTS (SELECT 1 FROM dbo.uv_estudiante_programa GROUP BY id HAVING COUNT(*) > 1)
        THROW 53304, 'TEST FAILED: UV_ESTUDIANTE_PROGRAMA_NO_DUPLICATES duplicated view ids.', 1;
    IF (SELECT COUNT(*) FROM sys.columns WHERE object_id = OBJECT_ID('dbo.uv_estudiante_programa')) <> 5
        THROW 53305, 'TEST FAILED: UV_ESTUDIANTE_PROGRAMA_NO_DUPLICATES view shape changed (expected 5 columns).', 1;

    PRINT 'TEST_PASS:UV_ESTUDIANTE_PROGRAMA_NO_DUPLICATES';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @msg NVARCHAR(2000) = ERROR_MESSAGE();
    THROW 53399, @msg, 1;
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO
