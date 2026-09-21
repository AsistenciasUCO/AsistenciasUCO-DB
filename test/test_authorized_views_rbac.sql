USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- ============================================================================
-- PRUEBA 1: Contexto NULL (Administración Global / Mantenimiento)
-- ============================================================================
EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = NULL;

DECLARE @countBaseInst INT = (SELECT COUNT(*) FROM dbo.uv_institucion);
DECLARE @countAuthInst INT = (SELECT COUNT(*) FROM dbo.uv_auth_institucion);

IF @countBaseInst <> @countAuthInst
    THROW 52001, 'TEST FAILED: NULL context should return full uv_auth_institucion visibility.', 1;

DECLARE @countBaseFac INT = (SELECT COUNT(*) FROM dbo.uv_facultad);
DECLARE @countAuthFac INT = (SELECT COUNT(*) FROM dbo.uv_auth_facultad);

IF @countBaseFac <> @countAuthFac
    THROW 52002, 'TEST FAILED: NULL context should return full uv_auth_facultad visibility.', 1;

PRINT 'TEST_PASS:RBAC_NULL_CONTEXT_FULL_ACCESS';
GO

-- ============================================================================
-- PRUEBA 2: Contexto de Administrador de Institución
-- ============================================================================
SET NOCOUNT ON;
DECLARE @adminUser UNIQUEIDENTIFIER;
SELECT TOP 1 @adminUser = a.usuario 
FROM dbo.Administrador a
INNER JOIN dbo.Usuario u ON a.usuario = u.id 
WHERE u.estado = 1;

IF @adminUser IS NOT NULL
BEGIN
    EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = @adminUser;

    DECLARE @adminInst UNIQUEIDENTIFIER = (SELECT institucion FROM dbo.Administrador WHERE usuario = @adminUser);

    IF EXISTS (SELECT 1 FROM dbo.uv_auth_facultad WHERE idInstitucion <> @adminInst)
        THROW 52003, 'TEST FAILED: Admin context leaked faculties outside institution.', 1;

    PRINT 'TEST_PASS:RBAC_ADMIN_INSTITUTION_ISOLATION';
END
ELSE
BEGIN
    PRINT 'TEST_PASS:RBAC_ADMIN_INSTITUTION_ISOLATION';
END;
GO

-- ============================================================================
-- PRUEBA 3: Contexto de Decano
-- ============================================================================
SET NOCOUNT ON;
DECLARE @deanUser UNIQUEIDENTIFIER, @deanFacultad UNIQUEIDENTIFIER;
SELECT TOP 1 @deanUser = d.usuario, @deanFacultad = f.id
FROM dbo.Decano d
INNER JOIN dbo.Usuario u ON d.usuario = u.id
INNER JOIN dbo.Facultad f ON d.id = f.decano
WHERE u.estado = 1;

IF @deanUser IS NOT NULL
BEGIN
    EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = @deanUser;

    IF EXISTS (SELECT 1 FROM dbo.uv_auth_facultad WHERE id <> @deanFacultad)
        THROW 52004, 'TEST FAILED: Decano context leaked faculties outside assigned faculty.', 1;

    IF EXISTS (SELECT 1 FROM dbo.uv_auth_programa WHERE idFacultad <> @deanFacultad)
        THROW 52005, 'TEST FAILED: Decano context leaked programs outside assigned faculty.', 1;

    PRINT 'TEST_PASS:RBAC_DECANO_FACULTY_ISOLATION';
END
ELSE
BEGIN
    PRINT 'TEST_PASS:RBAC_DECANO_FACULTY_ISOLATION';
END;
GO

-- ============================================================================
-- PRUEBA 4: Contexto de Coordinador
-- ============================================================================
SET NOCOUNT ON;
DECLARE @coordUser UNIQUEIDENTIFIER, @coordPrograma UNIQUEIDENTIFIER;
SELECT TOP 1 @coordUser = c.usuario, @coordPrograma = pr.id
FROM dbo.Coordinador c
INNER JOIN dbo.Usuario u ON c.usuario = u.id
INNER JOIN dbo.Programa pr ON c.id = pr.coordinador
WHERE u.estado = 1;

IF @coordUser IS NOT NULL
BEGIN
    EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = @coordUser;

    IF EXISTS (SELECT 1 FROM dbo.uv_auth_programa WHERE id <> @coordPrograma)
        THROW 52006, 'TEST FAILED: Coordinador context leaked programs outside assigned program.', 1;

    PRINT 'TEST_PASS:RBAC_COORDINADOR_PROGRAM_ISOLATION';
END
ELSE
BEGIN
    PRINT 'TEST_PASS:RBAC_COORDINADOR_PROGRAM_ISOLATION';
END;
GO

-- ============================================================================
-- PRUEBA 5: Contexto de Docente
-- ============================================================================
SET NOCOUNT ON;
DECLARE @docenteUser UNIQUEIDENTIFIER, @docenteId UNIQUEIDENTIFIER;
SELECT TOP 1 @docenteUser = doc.usuario, @docenteId = doc.id
FROM dbo.Docente doc
INNER JOIN dbo.Usuario u ON doc.usuario = u.id
INNER JOIN dbo.Grupo g ON doc.id = g.docente
WHERE u.estado = 1;

IF @docenteUser IS NOT NULL
BEGIN
    EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = @docenteUser;

    IF EXISTS (SELECT 1 FROM dbo.uv_auth_grupo WHERE idDocente <> @docenteId)
        THROW 52007, 'TEST FAILED: Docente context leaked groups outside assigned groups.', 1;

    PRINT 'TEST_PASS:RBAC_DOCENTE_GROUP_ISOLATION';
END
ELSE
BEGIN
    PRINT 'TEST_PASS:RBAC_DOCENTE_GROUP_ISOLATION';
END;
GO

-- Restablecer contexto a NULL al finalizar
EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = NULL;
PRINT 'TEST_PASS:RBAC_RESET_CONTEXT';
GO
