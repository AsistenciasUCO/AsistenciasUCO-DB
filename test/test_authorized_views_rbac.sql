USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- ============================================================================
-- DB-GP-001C: politica de las vistas autorizadas uv_auth_* = FAIL CLOSED.
--   uv_*      : semantica interna/base (datos completos).
--   uv_auth_* : semantica externa autorizada. Sin identidad => 0 filas.
-- Ausencia de SESSION_CONTEXT('idUsuarioEjecutor') NO equivale a acceso total.
-- El mantenimiento/administracion SQL directa usa las vistas base uv_*.
-- Los tests establecen su propio contexto y lo restauran a NULL al finalizar.
-- ============================================================================

-- ============================================================================
-- PRUEBA 0: Inventario de vistas uv_auth_* (nadie agrega una vista sin clasificarla)
-- ============================================================================
DECLARE @expectedAuthViews TABLE (viewName SYSNAME PRIMARY KEY, clasificacion VARCHAR(30) NOT NULL);
INSERT @expectedAuthViews (viewName, clasificacion) VALUES
    ('uv_auth_institucion', 'DIRECT_CONTEXT_FILTER'),
    ('uv_auth_facultad', 'DIRECT_CONTEXT_FILTER'),
    ('uv_auth_programa', 'DIRECT_CONTEXT_FILTER'),
    ('uv_auth_grupo', 'DIRECT_CONTEXT_FILTER'),
    ('uv_auth_decano', 'DIRECT_CONTEXT_FILTER'),
    ('uv_auth_coordinador', 'DIRECT_CONTEXT_FILTER'),
    ('uv_auth_docente', 'DIRECT_CONTEXT_FILTER'),
    ('uv_auth_estudiante', 'DIRECT_CONTEXT_FILTER'),
    ('uv_auth_periodo_academico', 'INHERITS_AUTH_VIEW'),
    ('uv_auth_sesion', 'INHERITS_AUTH_VIEW'),
    ('uv_auth_asistencia', 'INHERITS_AUTH_VIEW'),
    ('uv_auth_solicitud_revision_asistencia', 'INHERITS_AUTH_VIEW');

IF EXISTS (SELECT 1 FROM @expectedAuthViews e WHERE OBJECT_ID(CONCAT('dbo.', e.viewName), 'V') IS NULL)
   OR EXISTS (
        SELECT 1 FROM sys.views v
        WHERE v.schema_id = SCHEMA_ID('dbo') AND v.name LIKE 'uv[_]auth[_]%'
          AND v.name NOT IN (SELECT viewName FROM @expectedAuthViews)
   )
    THROW 52010, 'TEST FAILED: inventario uv_auth_* difiere del clasificado (DIRECT_CONTEXT_FILTER/INHERITS_AUTH_VIEW).', 1;

-- Definicion: las DIRECT exigen contexto NOT NULL; las que heredan referencian otra uv_auth_*.
IF EXISTS (
    SELECT 1
    FROM @expectedAuthViews e
    CROSS APPLY (SELECT REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID(CONCAT('dbo.', e.viewName))), CHAR(13), ' '), CHAR(10), ' '), CHAR(9), ' ') AS def) d
    WHERE (e.clasificacion = 'DIRECT_CONTEXT_FILTER'
           AND (d.def NOT LIKE '%ufn_obtener_usuario_ejecutor_contexto() IS NOT NULL%'
                OR d.def LIKE '%ufn_obtener_usuario_ejecutor_contexto() IS NULL%'))
       OR (e.clasificacion = 'INHERITS_AUTH_VIEW'
           AND (d.def NOT LIKE '%dbo.uv[_]auth[_]%'
                OR d.def LIKE '%ufn_obtener_usuario_ejecutor_contexto() IS NULL%'))
)
    THROW 52011, 'TEST FAILED: definicion uv_auth_* no es fail-closed (IS NULL bypass o falta IS NOT NULL / herencia).', 1;
PRINT 'TEST_PASS:RBAC_AUTH_VIEWS_FAIL_CLOSED_DEFINITION';
GO

-- ============================================================================
-- PRUEBA 1: Contexto NULL => 0 filas en TODAS las uv_auth_* (sin acceso total implicito)
-- ============================================================================
SET NOCOUNT ON;
EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = NULL;

DECLARE @viewName SYSNAME, @sql NVARCHAR(400), @rows INT, @failure NVARCHAR(2048);
DECLARE authViews CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.views WHERE schema_id = SCHEMA_ID('dbo') AND name LIKE 'uv[_]auth[_]%' ORDER BY name;
OPEN authViews;
FETCH NEXT FROM authViews INTO @viewName;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = CONCAT(N'SELECT @rows = COUNT(*) FROM dbo.', QUOTENAME(@viewName), N';');
    EXEC sys.sp_executesql @sql, N'@rows INT OUTPUT', @rows = @rows OUTPUT;
    IF @rows <> 0
    BEGIN
        SET @failure = CONCAT('TEST FAILED: contexto NULL debe retornar 0 filas; ', @viewName, ' retorno ', @rows, '.');
        CLOSE authViews; DEALLOCATE authViews;
        THROW 52001, @failure, 1;
    END
    FETCH NEXT FROM authViews INTO @viewName;
END
CLOSE authViews; DEALLOCATE authViews;

-- Control: las vistas base conservan semantica completa (mantenimiento usa uv_*).
IF (SELECT COUNT(*) FROM dbo.uv_institucion) = 0 OR (SELECT COUNT(*) FROM dbo.uv_grupo) = 0
    THROW 52002, 'TEST FAILED: fixture base vacio; el control de vistas base uv_* no es concluyente.', 1;

PRINT 'TEST_PASS:RBAC_NULL_CONTEXT_NO_ROWS';
GO

-- ============================================================================
-- PRUEBA 1b: Contexto con UUID inexistente => 0 filas (no equivale a administrador)
-- ============================================================================
SET NOCOUNT ON;
DECLARE @unknownUser UNIQUEIDENTIFIER = 'DEADBEEF-0000-4000-8000-00000000C0DE';
IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @unknownUser)
    THROW 52012, 'TEST FAILED: el UUID de contexto desconocido existe como Usuario.', 1;
EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = @unknownUser;

DECLARE @viewName SYSNAME, @sql NVARCHAR(400), @rows INT, @failure NVARCHAR(2048);
DECLARE authViews CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.views WHERE schema_id = SCHEMA_ID('dbo') AND name LIKE 'uv[_]auth[_]%' ORDER BY name;
OPEN authViews;
FETCH NEXT FROM authViews INTO @viewName;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = CONCAT(N'SELECT @rows = COUNT(*) FROM dbo.', QUOTENAME(@viewName), N';');
    EXEC sys.sp_executesql @sql, N'@rows INT OUTPUT', @rows = @rows OUTPUT;
    IF @rows <> 0
    BEGIN
        SET @failure = CONCAT('TEST FAILED: usuario desconocido debe retornar 0 filas; ', @viewName, ' retorno ', @rows, '.');
        CLOSE authViews; DEALLOCATE authViews;
        EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = NULL;
        THROW 52013, @failure, 1;
    END
    FETCH NEXT FROM authViews INTO @viewName;
END
CLOSE authViews; DEALLOCATE authViews;
EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = NULL;

PRINT 'TEST_PASS:RBAC_UNKNOWN_CONTEXT_NO_ROWS';
GO

-- ============================================================================
-- PRUEBA 2: Administrador de institucion (alcance exacto de su institucion)
-- ============================================================================
SET NOCOUNT ON;
DECLARE @adminUser UNIQUEIDENTIFIER, @adminInst UNIQUEIDENTIFIER;
SELECT TOP 1 @adminUser = a.usuario, @adminInst = a.institucion
FROM dbo.Administrador a
INNER JOIN dbo.Usuario u ON a.usuario = u.id
WHERE u.estado = 1
ORDER BY a.id;

IF @adminUser IS NULL
    THROW 52020, 'TEST FAILED: fixture Administrador activo ausente.', 1;

EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = @adminUser;

IF EXISTS (SELECT 1 FROM dbo.uv_auth_institucion WHERE id <> @adminInst)
   OR (SELECT COUNT(*) FROM dbo.uv_auth_institucion WHERE id = @adminInst) <> 1
    THROW 52021, 'TEST FAILED: Admin debe ver exactamente su institucion.', 1;
IF EXISTS (SELECT 1 FROM dbo.uv_auth_facultad WHERE idInstitucion <> @adminInst)
    THROW 52003, 'TEST FAILED: Admin context leaked faculties outside institution.', 1;
IF (SELECT COUNT(*) FROM dbo.uv_auth_facultad) <> (SELECT COUNT(*) FROM dbo.uv_facultad WHERE idInstitucion = @adminInst)
   OR (SELECT COUNT(*) FROM dbo.uv_auth_facultad) = 0
    THROW 52022, 'TEST FAILED: Admin no ve todas las facultades de su institucion.', 1;
IF (SELECT COUNT(*) FROM dbo.uv_auth_programa) <> (SELECT COUNT(*) FROM dbo.uv_programa WHERE idInstitucion = @adminInst)
   OR (SELECT COUNT(*) FROM dbo.uv_auth_programa) = 0
    THROW 52023, 'TEST FAILED: Admin no ve todos los programas de su institucion.', 1;
IF (SELECT COUNT(*) FROM dbo.uv_auth_grupo) = 0
    THROW 52024, 'TEST FAILED: Admin no ve grupos de su institucion.', 1;
IF EXISTS (
    SELECT 1 FROM dbo.uv_auth_grupo ag
    JOIN dbo.Asignatura a ON a.id = ag.idAsignatura
    JOIN dbo.SemestrePlanEstudio spe ON spe.id = a.semestrePlanEstudio
    JOIN dbo.PlanEstudio pe ON pe.id = spe.planEstudio
    JOIN dbo.Programa pr ON pr.id = pe.programa
    JOIN dbo.Facultad f ON f.id = pr.facultad
    WHERE f.institucion <> @adminInst
)
    THROW 52025, 'TEST FAILED: Admin context leaked groups outside institution.', 1;

PRINT 'TEST_PASS:RBAC_ADMIN_INSTITUTION_ISOLATION';
EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = NULL;
GO

-- ============================================================================
-- PRUEBA 2b: Usuario inactivo. Las uv_auth_* filtran por rol/titularidad, no por
-- Usuario.estado (la validacion de actividad es SEC_001 en los SP publicos). Un
-- Administrador inactivo NO puede tener un alcance mayor que su institucion.
-- ============================================================================
SET NOCOUNT ON;
DECLARE @inactiveAdmin UNIQUEIDENTIFIER, @inactiveInst UNIQUEIDENTIFIER;
SELECT TOP 1 @inactiveAdmin = a.usuario, @inactiveInst = a.institucion
FROM dbo.Administrador a INNER JOIN dbo.Usuario u ON a.usuario = u.id
WHERE u.estado = 1 ORDER BY a.id;
IF @inactiveAdmin IS NULL
    THROW 52026, 'TEST FAILED: fixture Administrador activo ausente para prueba de usuario inactivo.', 1;

BEGIN TRANSACTION;
BEGIN TRY
    UPDATE dbo.Usuario SET estado = 0 WHERE id = @inactiveAdmin;
    EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = @inactiveAdmin;

    IF EXISTS (SELECT 1 FROM dbo.uv_auth_institucion WHERE id <> @inactiveInst)
       OR EXISTS (SELECT 1 FROM dbo.uv_auth_facultad WHERE idInstitucion <> @inactiveInst)
       OR EXISTS (SELECT 1 FROM dbo.uv_auth_programa WHERE idInstitucion <> @inactiveInst)
        THROW 52027, 'TEST FAILED: usuario inactivo obtuvo alcance mayor que su institucion.', 1;

    EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = NULL;
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = NULL;
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
PRINT 'TEST_PASS:RBAC_INACTIVE_USER_NO_BROADER_SCOPE';
GO

-- ============================================================================
-- PRUEBA 3: Decano (solo su facultad)
-- ============================================================================
SET NOCOUNT ON;
DECLARE @deanUser UNIQUEIDENTIFIER, @deanFacultad UNIQUEIDENTIFIER;
SELECT TOP 1 @deanUser = d.usuario, @deanFacultad = f.id
FROM dbo.Decano d
INNER JOIN dbo.Usuario u ON d.usuario = u.id
INNER JOIN dbo.Facultad f ON d.id = f.decano
WHERE u.estado = 1
ORDER BY f.id;

IF @deanUser IS NULL
    THROW 52030, 'TEST FAILED: fixture Decano activo con facultad ausente.', 1;

EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = @deanUser;

IF EXISTS (SELECT 1 FROM dbo.uv_auth_facultad WHERE id <> @deanFacultad)
    THROW 52004, 'TEST FAILED: Decano context leaked faculties outside assigned faculty.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.uv_auth_facultad WHERE id = @deanFacultad)
    THROW 52031, 'TEST FAILED: Decano no ve su facultad asignada.', 1;
IF EXISTS (SELECT 1 FROM dbo.uv_auth_programa WHERE idFacultad <> @deanFacultad)
    THROW 52005, 'TEST FAILED: Decano context leaked programs outside assigned faculty.', 1;
IF (SELECT COUNT(*) FROM dbo.uv_auth_programa) <> (SELECT COUNT(*) FROM dbo.uv_programa WHERE idFacultad = @deanFacultad)
   OR (SELECT COUNT(*) FROM dbo.uv_auth_programa) = 0
    THROW 52032, 'TEST FAILED: Decano no ve todos los programas de su facultad.', 1;
IF (SELECT COUNT(*) FROM dbo.uv_auth_grupo) = 0
    THROW 52033, 'TEST FAILED: Decano no ve grupos de su facultad.', 1;

PRINT 'TEST_PASS:RBAC_DECANO_FACULTY_ISOLATION';
EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = NULL;
GO

-- ============================================================================
-- PRUEBA 4: Coordinador (solo sus programas)
-- ============================================================================
SET NOCOUNT ON;
DECLARE @coordUser UNIQUEIDENTIFIER, @coordId UNIQUEIDENTIFIER, @coordPrograma UNIQUEIDENTIFIER;
SELECT TOP 1 @coordUser = c.usuario, @coordId = c.id, @coordPrograma = pr.id
FROM dbo.Coordinador c
INNER JOIN dbo.Usuario u ON c.usuario = u.id
INNER JOIN dbo.Programa pr ON c.id = pr.coordinador
WHERE u.estado = 1
ORDER BY pr.id;

IF @coordUser IS NULL
    THROW 52040, 'TEST FAILED: fixture Coordinador activo con programa ausente.', 1;

EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = @coordUser;

IF EXISTS (SELECT 1 FROM dbo.uv_auth_programa WHERE idCoordinador <> @coordId)
    THROW 52006, 'TEST FAILED: Coordinador context leaked programs outside assigned program.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.uv_auth_programa WHERE id = @coordPrograma)
    THROW 52041, 'TEST FAILED: Coordinador no ve su programa asignado.', 1;
IF (SELECT COUNT(*) FROM dbo.uv_auth_grupo) = 0
    THROW 52042, 'TEST FAILED: Coordinador no ve grupos de su programa.', 1;
IF EXISTS (
    SELECT 1 FROM dbo.uv_auth_grupo ag
    JOIN dbo.Asignatura a ON a.id = ag.idAsignatura
    JOIN dbo.SemestrePlanEstudio spe ON spe.id = a.semestrePlanEstudio
    JOIN dbo.PlanEstudio pe ON pe.id = spe.planEstudio
    JOIN dbo.Programa pr ON pr.id = pe.programa
    WHERE pr.coordinador <> @coordId
)
    THROW 52043, 'TEST FAILED: Coordinador context leaked groups outside assigned programs.', 1;

PRINT 'TEST_PASS:RBAC_COORDINADOR_PROGRAM_ISOLATION';
EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = NULL;
GO

-- ============================================================================
-- PRUEBA 5: Docente (solo sus grupos y sesiones)
-- ============================================================================
SET NOCOUNT ON;
DECLARE @docenteUser UNIQUEIDENTIFIER, @docenteId UNIQUEIDENTIFIER;
SELECT TOP 1 @docenteUser = doc.usuario, @docenteId = doc.id
FROM dbo.Docente doc
INNER JOIN dbo.Usuario u ON doc.usuario = u.id
INNER JOIN dbo.Grupo g ON doc.id = g.docente
WHERE u.estado = 1
ORDER BY g.id;

IF @docenteUser IS NULL
    THROW 52050, 'TEST FAILED: fixture Docente activo con grupo ausente.', 1;

EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = @docenteUser;

IF EXISTS (SELECT 1 FROM dbo.uv_auth_grupo WHERE idDocente <> @docenteId)
    THROW 52007, 'TEST FAILED: Docente context leaked groups outside assigned groups.', 1;
IF (SELECT COUNT(*) FROM dbo.uv_auth_grupo) <> (SELECT COUNT(*) FROM dbo.Grupo WHERE docente = @docenteId)
   OR (SELECT COUNT(*) FROM dbo.uv_auth_grupo) = 0
    THROW 52051, 'TEST FAILED: Docente no ve exactamente sus grupos.', 1;
IF EXISTS (SELECT 1 FROM dbo.uv_auth_sesion s WHERE s.idGrupo NOT IN (SELECT id FROM dbo.Grupo WHERE docente = @docenteId))
    THROW 52052, 'TEST FAILED: Docente context leaked sessions outside assigned groups.', 1;
IF (SELECT COUNT(*) FROM dbo.uv_auth_sesion) <> (SELECT COUNT(*) FROM dbo.Sesion WHERE grupo IN (SELECT id FROM dbo.Grupo WHERE docente = @docenteId))
    THROW 52053, 'TEST FAILED: Docente no ve todas las sesiones de sus grupos.', 1;

PRINT 'TEST_PASS:RBAC_DOCENTE_GROUP_ISOLATION';
EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = NULL;
GO

-- ============================================================================
-- PRUEBA 6: Estudiante (solo sus grupos y su propia fila)
-- ============================================================================
SET NOCOUNT ON;
DECLARE @estUser UNIQUEIDENTIFIER, @estId UNIQUEIDENTIFIER;
SELECT TOP 1 @estUser = e.usuario, @estId = e.id
FROM dbo.Estudiante e
INNER JOIN dbo.Usuario u ON e.usuario = u.id
INNER JOIN dbo.EstudianteGrupo eg ON eg.estudiante = e.id
WHERE u.estado = 1
ORDER BY eg.id;

IF @estUser IS NULL
    THROW 52060, 'TEST FAILED: fixture Estudiante activo con grupo ausente.', 1;

EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = @estUser;

IF (SELECT COUNT(*) FROM dbo.uv_auth_grupo) = 0
   OR EXISTS (
        SELECT 1 FROM dbo.uv_auth_grupo g
        WHERE g.id NOT IN (SELECT eg.grupo FROM dbo.EstudianteGrupo eg WHERE eg.estudiante = @estId)
   )
    THROW 52061, 'TEST FAILED: Estudiante debe ver unicamente los grupos donde esta inscrito.', 1;
IF EXISTS (SELECT 1 FROM dbo.uv_auth_estudiante WHERE idUsuario <> @estUser)
   OR NOT EXISTS (SELECT 1 FROM dbo.uv_auth_estudiante WHERE idUsuario = @estUser)
    THROW 52062, 'TEST FAILED: Estudiante debe ver unicamente su propia fila en uv_auth_estudiante.', 1;
IF EXISTS (SELECT 1 FROM dbo.uv_auth_docente) OR EXISTS (SELECT 1 FROM dbo.uv_auth_decano) OR EXISTS (SELECT 1 FROM dbo.uv_auth_coordinador)
    THROW 52063, 'TEST FAILED: Estudiante no debe ver identidades de docente/decano/coordinador.', 1;
IF EXISTS (SELECT 1 FROM dbo.uv_auth_programa) OR EXISTS (SELECT 1 FROM dbo.uv_auth_facultad WHERE idInstitucion IS NULL)
    THROW 52064, 'TEST FAILED: Estudiante obtuvo alcance de programa/facultad.', 1;

PRINT 'TEST_PASS:RBAC_ESTUDIANTE_ENROLLED_GROUP_ISOLATION';
EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = NULL;
GO

-- Restablecer contexto a NULL al finalizar
EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = NULL;
IF SESSION_CONTEXT(N'idUsuarioEjecutor') IS NOT NULL
    THROW 52070, 'TEST FAILED: contexto no restablecido a NULL.', 1;
PRINT 'TEST_PASS:RBAC_RESET_CONTEXT';
GO
