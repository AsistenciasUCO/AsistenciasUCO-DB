USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- Contrato de dbo.usp_registrar_estudiante_en_grupo (provider publico de matricula, TD-043).
-- Cubre: roles DOCENTE/COORDINADOR, ADMINISTRADOR denegado, titularidad OR (docente titular / coordinador
-- del programa), DBCODE de ejecutor y tipo de identificacion, conflicto de identidad, password de usuario
-- existente, atomicidad (savepoint y transaccion propia) y preservacion de la transaccion externa.
-- Cada escenario de escritura corre dentro de una transaccion externa que se revierte al final.
PRINT 'TEST START: test_registrar_estudiante_en_grupo_contrato';

DECLARE @grupo UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_grupo WHERE grupoEstaHablitado = 1 AND cuposDisponibles > 0 ORDER BY id);
DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @docenteTitularId UNIQUEIDENTIFIER = (SELECT idDocente FROM dbo.uv_grupo WHERE id = @grupo);
DECLARE @docenteTitularUser UNIQUEIDENTIFIER = (SELECT idUsuario FROM dbo.uv_docente_identidad WHERE id = @docenteTitularId);
DECLARE @programa UNIQUEIDENTIFIER = (
    SELECT TOP 1 spe.idPrograma
    FROM dbo.uv_grupo g
    INNER JOIN dbo.uv_asignatura a ON a.id = g.idAsignatura
    INNER JOIN dbo.uv_semestre_plan_estudio spe ON spe.id = a.idSemestrePlanEstudio
    WHERE g.id = @grupo);
DECLARE @coordTitularId UNIQUEIDENTIFIER = (SELECT idCoordinador FROM dbo.uv_programa WHERE id = @programa);
DECLARE @coordTitularUser UNIQUEIDENTIFIER = (SELECT idUsuario FROM dbo.uv_coordinador_identidad WHERE id = @coordTitularId);
DECLARE @docenteNoTitularUser UNIQUEIDENTIFIER = (
    SELECT TOP 1 idUsuario FROM dbo.uv_docente_identidad
    WHERE estaActivoUsuario = 1 AND id <> @docenteTitularId AND idUsuario <> @coordTitularUser
    ORDER BY idUsuario);
DECLARE @coordOtroUser UNIQUEIDENTIFIER = (
    SELECT TOP 1 ci.idUsuario
    FROM dbo.uv_coordinador_identidad ci
    INNER JOIN dbo.uv_programa p ON p.idCoordinador = ci.id
    WHERE p.id <> @programa AND ci.estaActivoUsuario = 1 AND ci.idUsuario <> @docenteTitularUser
    ORDER BY ci.idUsuario);
DECLARE @adminUser UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_administrador WHERE estaActivoUsuario = 1 ORDER BY idUsuario);
DECLARE @estudianteSinGrupo UNIQUEIDENTIFIER = (
    SELECT TOP 1 ei.idUsuario FROM dbo.uv_estudiante_identidad ei
    WHERE ei.estaActivoUsuario = 1 AND NOT EXISTS (SELECT 1 FROM dbo.EstudianteGrupo eg WHERE eg.estudiante = ei.id)
    ORDER BY ei.idUsuario);

CREATE TABLE #res (
    idCorrelacion UNIQUEIDENTIFIER NULL,
    mensajeUsuarioResultado NVARCHAR(MAX) NULL,
    mensajeTecnicoResultado NVARCHAR(MAX) NULL,
    estadoResultado INT NOT NULL
);

CREATE TABLE #snap (
    fase VARCHAR(10) NOT NULL,
    usuarios INT NOT NULL,
    estudiantes INT NOT NULL,
    programas INT NOT NULL,
    matriculas INT NOT NULL
);


-- Fixture aislado: la BD de prueba no tiene un segundo docente, un segundo programa ni estudiantes sin grupo.
-- Se crean dentro de una transaccion externa que se revierte al final (no queda ningun residuo).
BEGIN TRANSACTION;
DECLARE @uD2 UNIQUEIDENTIFIER = NEWID(), @uE UNIQUEIDENTIFIER = NEWID(), @uC2 UNIQUEIDENTIFIER = NEWID();
DECLARE @programaOtro UNIQUEIDENTIFIER = NEWID(), @coordOtroId UNIQUEIDENTIFIER = NEWID();
DECLARE @facultadPrograma UNIQUEIDENTIFIER = (SELECT facultad FROM dbo.Programa WHERE id = @programa);
DECLARE @tipoProgramaFx UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoPrograma);
INSERT dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
VALUES (@uD2, @tipoCC, 1000000001 + ABS(CHECKSUM(NEWID()) % 100000000), N'Fixture', N'Docente', N'NoTitular', N'QA',
        CONCAT(N'qa.fx.d2.', REPLACE(CONVERT(VARCHAR(36), @uD2), '-', ''), N'@test.local'), 0, 1, N'HashBackend_QaFixture1234567890'),
       (@uE, @tipoCC, 1000000001 + ABS(CHECKSUM(NEWID()) % 100000000), N'Fixture', N'Estudiante', N'Sin', N'Grupo',
        CONCAT(N'qa.fx.e.', REPLACE(CONVERT(VARCHAR(36), @uE), '-', ''), N'@test.local'), 0, 1, N'HashBackend_QaFixture1234567890'),
       (@uC2, @tipoCC, 1000000001 + ABS(CHECKSUM(NEWID()) % 100000000), N'Fixture', N'Coordinador', N'Otro', N'Programa',
        CONCAT(N'qa.fx.c2.', REPLACE(CONVERT(VARCHAR(36), @uC2), '-', ''), N'@test.local'), 0, 1, N'HashBackend_QaFixture1234567890');
INSERT dbo.Docente (id, usuario) VALUES (NEWID(), @uD2);
INSERT dbo.Estudiante (id, usuario) VALUES (NEWID(), @uE);
INSERT dbo.Coordinador (id, usuario) VALUES (@coordOtroId, @uC2);
INSERT dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado)
VALUES (@programaOtro, @facultadPrograma, @tipoProgramaFx, N'QA Otro Programa', @coordOtroId, 1);
SET @docenteNoTitularUser = @uD2;
SET @coordOtroUser = @uC2;
SET @estudianteSinGrupo = @uE;

IF @grupo IS NULL OR @tipoCC IS NULL OR @docenteTitularUser IS NULL OR @programa IS NULL OR @coordTitularUser IS NULL
   OR @docenteNoTitularUser IS NULL OR @coordOtroUser IS NULL OR @adminUser IS NULL OR @estudianteSinGrupo IS NULL
    THROW 52600, 'TEST FAILED: ENROLL_CONTRACT fixture missing.', 1;
IF @coordTitularUser = @docenteTitularUser OR @coordOtroUser = @docenteTitularUser OR @docenteNoTitularUser = @coordTitularUser
    THROW 52601, 'TEST FAILED: ENROLL_CONTRACT fixture roles overlap unexpectedly.', 1;
IF EXISTS (SELECT 1 FROM dbo.uv_usuario_perfil WHERE idUsuario = @adminUser AND codigoPerfil IN ('DO', 'CD'))
    THROW 52602, 'TEST FAILED: ENROLL_CONTRACT admin fixture also has DOCENTE/COORDINADOR.', 1;


DECLARE @corr UNIQUEIDENTIFIER;
DECLARE @msgUsuario NVARCHAR(4000), @msgTecnico NVARCHAR(4000);
DECLARE @correo NVARCHAR(100), @num INT, @tipo UNIQUEIDENTIFIER;
-- Fallo forzado con CHECK (error 547), no con THROW en trigger: un THROW en trigger condena la transaccion
-- externa (XACT_STATE = -1) y no permite ROLLBACK TO SAVEPOINT. El CHECK deja la transaccion utilizable.
DECLARE @triggerSql NVARCHAR(MAX) = CONCAT(
    N'ALTER TABLE dbo.EstudianteGrupo WITH NOCHECK ADD CONSTRAINT ck_qa_contrato_matricula_falla CHECK (grupo <> ''',
    CONVERT(NVARCHAR(36), @grupo), N''')');

-- ---------------------------------------------------------------------------------------------
-- 1. ADMINISTRADOR denegado (sin bypass). Pre-escritura: canonico, cero escrituras.
-- ---------------------------------------------------------------------------------------------
SET @corr = NEWID();
SET @correo = CONCAT(N'qa.contrato.admin.', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), N'@test.local');
SET @num = 1000000000 + ABS(CHECKSUM(NEWID()) % 500000000);
TRUNCATE TABLE #res; TRUNCATE TABLE #snap;
INSERT #snap SELECT 'before', (SELECT COUNT(*) FROM dbo.Usuario), (SELECT COUNT(*) FROM dbo.Estudiante), (SELECT COUNT(*) FROM dbo.EstudiantePrograma), (SELECT COUNT(*) FROM dbo.EstudianteGrupo);
INSERT INTO #res EXEC dbo.usp_registrar_estudiante_en_grupo
    @numeroIdentificacion = @num, @primerApellido = N'Quality', @segundoApellido = N'Gate',
    @primerNombre = N'Contrato', @segundoNombre = N'Admin', @correo = @correo,
    @password = N'HashBackend_QaContrato1234567890', @idGrupo = @grupo, @idCorrelacion = @corr,
    @idUsuarioEjecutor = @adminUser, @idTipoIdIdentificacion = @tipoCC;
EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SEC_001', @p_param1 = 'DOCENTE,COORDINADOR',
    @mensajeUsuarioResultado = @msgUsuario OUTPUT, @mensajeTecnicoResultado = @msgTecnico OUTPUT;
IF NOT EXISTS (SELECT 1 FROM #res WHERE estadoResultado = 0 AND idCorrelacion = @corr
    AND mensajeUsuarioResultado = @msgUsuario AND mensajeTecnicoResultado = CONCAT(@msgTecnico, ' Correlacion: ', @corr))
    THROW 52610, 'TEST FAILED: ENROLL_ADMIN_DENIED expected canonical SEC_001 with estado 0.', 1;
INSERT #snap SELECT 'after', (SELECT COUNT(*) FROM dbo.Usuario), (SELECT COUNT(*) FROM dbo.Estudiante), (SELECT COUNT(*) FROM dbo.EstudiantePrograma), (SELECT COUNT(*) FROM dbo.EstudianteGrupo);
IF EXISTS (SELECT 1 FROM #snap b INNER JOIN #snap a ON a.fase = 'after' WHERE b.fase = 'before'
    AND (a.usuarios <> b.usuarios OR a.estudiantes <> b.estudiantes OR a.programas <> b.programas OR a.matriculas <> b.matriculas))
    THROW 52611, 'TEST FAILED: ENROLL_ADMIN_DENIED produced writes.', 1;
PRINT 'TEST_PASS:ENROLL_ADMIN_DENIED';

-- ---------------------------------------------------------------------------------------------
-- 2. Ejecutor NULL -> GEN_002 (formal), cero escrituras.
-- ---------------------------------------------------------------------------------------------
SET @corr = NEWID();
SET @correo = CONCAT(N'qa.contrato.exec.', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), N'@test.local');
SET @num = 1000000000 + ABS(CHECKSUM(NEWID()) % 500000000);
TRUNCATE TABLE #res; TRUNCATE TABLE #snap;
INSERT #snap SELECT 'before', (SELECT COUNT(*) FROM dbo.Usuario), (SELECT COUNT(*) FROM dbo.Estudiante), (SELECT COUNT(*) FROM dbo.EstudiantePrograma), (SELECT COUNT(*) FROM dbo.EstudianteGrupo);
INSERT INTO #res EXEC dbo.usp_registrar_estudiante_en_grupo
    @numeroIdentificacion = @num, @primerApellido = N'Quality', @segundoApellido = N'Gate',
    @primerNombre = N'Contrato', @segundoNombre = N'Exec', @correo = @correo,
    @password = N'HashBackend_QaContrato1234567890', @idGrupo = @grupo, @idCorrelacion = @corr,
    @idUsuarioEjecutor = NULL, @idTipoIdIdentificacion = @tipoCC;
EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
    @mensajeUsuarioResultado = @msgUsuario OUTPUT, @mensajeTecnicoResultado = @msgTecnico OUTPUT;
IF NOT EXISTS (SELECT 1 FROM #res WHERE estadoResultado = 0 AND idCorrelacion = @corr
    AND mensajeUsuarioResultado = @msgUsuario AND mensajeTecnicoResultado = CONCAT(@msgTecnico, ' Correlacion: ', @corr))
    THROW 52612, 'TEST FAILED: ENROLL_EXECUTOR_NULL_DBCODE expected GEN_002 idUsuarioEjecutor.', 1;
INSERT #snap SELECT 'after', (SELECT COUNT(*) FROM dbo.Usuario), (SELECT COUNT(*) FROM dbo.Estudiante), (SELECT COUNT(*) FROM dbo.EstudiantePrograma), (SELECT COUNT(*) FROM dbo.EstudianteGrupo);
IF EXISTS (SELECT 1 FROM #snap b INNER JOIN #snap a ON a.fase = 'after' WHERE b.fase = 'before'
    AND (a.usuarios <> b.usuarios OR a.estudiantes <> b.estudiantes OR a.programas <> b.programas OR a.matriculas <> b.matriculas))
    THROW 52613, 'TEST FAILED: ENROLL_EXECUTOR_NULL_DBCODE produced writes.', 1;
PRINT 'TEST_PASS:ENROLL_EXECUTOR_NULL_DBCODE';

-- ---------------------------------------------------------------------------------------------
-- 3. Tipo de identificacion NULL -> GEN_002 (sin fallback a CC), y tipo inexistente -> cero escrituras.
-- ---------------------------------------------------------------------------------------------
SET @corr = NEWID();
SET @correo = CONCAT(N'qa.contrato.tipo.', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), N'@test.local');
SET @num = 1000000000 + ABS(CHECKSUM(NEWID()) % 500000000);
TRUNCATE TABLE #res; TRUNCATE TABLE #snap;
INSERT #snap SELECT 'before', (SELECT COUNT(*) FROM dbo.Usuario), (SELECT COUNT(*) FROM dbo.Estudiante), (SELECT COUNT(*) FROM dbo.EstudiantePrograma), (SELECT COUNT(*) FROM dbo.EstudianteGrupo);
INSERT INTO #res EXEC dbo.usp_registrar_estudiante_en_grupo
    @numeroIdentificacion = @num, @primerApellido = N'Quality', @segundoApellido = N'Gate',
    @primerNombre = N'Contrato', @segundoNombre = N'Tipo', @correo = @correo,
    @password = N'HashBackend_QaContrato1234567890', @idGrupo = @grupo, @idCorrelacion = @corr,
    @idUsuarioEjecutor = @docenteTitularUser, @idTipoIdIdentificacion = NULL;
EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idTipoIdIdentificacion',
    @mensajeUsuarioResultado = @msgUsuario OUTPUT, @mensajeTecnicoResultado = @msgTecnico OUTPUT;
IF NOT EXISTS (SELECT 1 FROM #res WHERE estadoResultado = 0 AND idCorrelacion = @corr
    AND mensajeUsuarioResultado = @msgUsuario AND mensajeTecnicoResultado = CONCAT(@msgTecnico, ' Correlacion: ', @corr))
    THROW 52614, 'TEST FAILED: ENROLL_TYPE_NULL_DBCODE expected GEN_002 idTipoIdIdentificacion.', 1;
PRINT 'TEST_PASS:ENROLL_TYPE_NULL_DBCODE';

SET @corr = NEWID();
SET @tipo = NEWID();
TRUNCATE TABLE #res;
INSERT INTO #res EXEC dbo.usp_registrar_estudiante_en_grupo
    @numeroIdentificacion = @num, @primerApellido = N'Quality', @segundoApellido = N'Gate',
    @primerNombre = N'Contrato', @segundoNombre = N'Tipo', @correo = @correo,
    @password = N'HashBackend_QaContrato1234567890', @idGrupo = @grupo, @idCorrelacion = @corr,
    @idUsuarioEjecutor = @docenteTitularUser, @idTipoIdIdentificacion = @tipo;
IF NOT EXISTS (SELECT 1 FROM #res WHERE estadoResultado = 0 AND idCorrelacion = @corr)
    THROW 52615, 'TEST FAILED: ENROLL_TYPE_INVALID_ZERO_WRITES expected estado 0 for unknown tipo.', 1;
INSERT #snap SELECT 'after', (SELECT COUNT(*) FROM dbo.Usuario), (SELECT COUNT(*) FROM dbo.Estudiante), (SELECT COUNT(*) FROM dbo.EstudiantePrograma), (SELECT COUNT(*) FROM dbo.EstudianteGrupo);
IF EXISTS (SELECT 1 FROM #snap b INNER JOIN #snap a ON a.fase = 'after' WHERE b.fase = 'before'
    AND (a.usuarios <> b.usuarios OR a.estudiantes <> b.estudiantes OR a.programas <> b.programas OR a.matriculas <> b.matriculas))
    THROW 52616, 'TEST FAILED: ENROLL_TYPE_INVALID_ZERO_WRITES produced writes.', 1;
PRINT 'TEST_PASS:ENROLL_TYPE_INVALID_ZERO_WRITES';

-- ---------------------------------------------------------------------------------------------
-- 4. DOCENTE titular -> permitido (exito dentro de transaccion externa, revertida al final).
-- ---------------------------------------------------------------------------------------------
SAVE TRANSACTION qa_contrato_1;
SET @corr = NEWID();
SET @correo = CONCAT(N'qa.contrato.titular.', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), N'@test.local');
SET @num = 1000000000 + ABS(CHECKSUM(NEWID()) % 500000000);
TRUNCATE TABLE #res; TRUNCATE TABLE #snap;
INSERT #snap SELECT 'before', (SELECT COUNT(*) FROM dbo.Usuario), (SELECT COUNT(*) FROM dbo.Estudiante), (SELECT COUNT(*) FROM dbo.EstudiantePrograma), (SELECT COUNT(*) FROM dbo.EstudianteGrupo);
INSERT INTO #res EXEC dbo.usp_registrar_estudiante_en_grupo
    @numeroIdentificacion = @num, @primerApellido = N'Quality', @segundoApellido = N'Gate',
    @primerNombre = N'Contrato', @segundoNombre = N'Titular', @correo = @correo,
    @password = N'HashBackend_QaContrato1234567890', @idGrupo = @grupo, @idCorrelacion = @corr,
    @idUsuarioEjecutor = @docenteTitularUser, @idTipoIdIdentificacion = @tipoCC;
IF @@TRANCOUNT <> 1 THROW 52620, 'TEST FAILED: ENROLL_DOCENTE_TITULAR_SUCCESS changed the external transaction.', 1;
IF NOT EXISTS (SELECT 1 FROM #res WHERE estadoResultado = 1 AND idCorrelacion = @corr)
    THROW 52621, 'TEST FAILED: ENROLL_DOCENTE_TITULAR_SUCCESS expected estado 1.', 1;
INSERT #snap SELECT 'after', (SELECT COUNT(*) FROM dbo.Usuario), (SELECT COUNT(*) FROM dbo.Estudiante), (SELECT COUNT(*) FROM dbo.EstudiantePrograma), (SELECT COUNT(*) FROM dbo.EstudianteGrupo);
IF (SELECT usuarios FROM #snap WHERE fase = 'after') - (SELECT usuarios FROM #snap WHERE fase = 'before') <> 1
   OR (SELECT matriculas FROM #snap WHERE fase = 'after') - (SELECT matriculas FROM #snap WHERE fase = 'before') <> 1
    THROW 52622, 'TEST FAILED: ENROLL_DOCENTE_TITULAR_SUCCESS did not create exactly one Usuario and one matricula.', 1;
ROLLBACK TRANSACTION qa_contrato_1;
PRINT 'TEST_PASS:ENROLL_DOCENTE_TITULAR_SUCCESS';

-- ---------------------------------------------------------------------------------------------
-- 5. DOCENTE no titular -> SEC_002, cero escrituras.
-- ---------------------------------------------------------------------------------------------
SET @corr = NEWID();
SET @correo = CONCAT(N'qa.contrato.notitular.', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), N'@test.local');
SET @num = 1000000000 + ABS(CHECKSUM(NEWID()) % 500000000);
TRUNCATE TABLE #res; TRUNCATE TABLE #snap;
INSERT #snap SELECT 'before', (SELECT COUNT(*) FROM dbo.Usuario), (SELECT COUNT(*) FROM dbo.Estudiante), (SELECT COUNT(*) FROM dbo.EstudiantePrograma), (SELECT COUNT(*) FROM dbo.EstudianteGrupo);
INSERT INTO #res EXEC dbo.usp_registrar_estudiante_en_grupo
    @numeroIdentificacion = @num, @primerApellido = N'Quality', @segundoApellido = N'Gate',
    @primerNombre = N'Contrato', @segundoNombre = N'NoTitular', @correo = @correo,
    @password = N'HashBackend_QaContrato1234567890', @idGrupo = @grupo, @idCorrelacion = @corr,
    @idUsuarioEjecutor = @docenteNoTitularUser, @idTipoIdIdentificacion = @tipoCC;
IF NOT EXISTS (SELECT 1 FROM #res WHERE estadoResultado = 0 AND idCorrelacion = @corr)
    THROW 52630, 'TEST FAILED: ENROLL_DOCENTE_NO_TITULAR_DENIED expected estado 0.', 1;
EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SEC_002', @p_param1 = 'Titularidad Grupo o Programa',
    @mensajeUsuarioResultado = @msgUsuario OUTPUT, @mensajeTecnicoResultado = @msgTecnico OUTPUT;
IF NOT EXISTS (SELECT 1 FROM #res WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msgUsuario)
    THROW 52631, 'TEST FAILED: ENROLL_DOCENTE_NO_TITULAR_DENIED expected SEC_002 titularidad.', 1;
INSERT #snap SELECT 'after', (SELECT COUNT(*) FROM dbo.Usuario), (SELECT COUNT(*) FROM dbo.Estudiante), (SELECT COUNT(*) FROM dbo.EstudiantePrograma), (SELECT COUNT(*) FROM dbo.EstudianteGrupo);
IF EXISTS (SELECT 1 FROM #snap b INNER JOIN #snap a ON a.fase = 'after' WHERE b.fase = 'before'
    AND (a.usuarios <> b.usuarios OR a.estudiantes <> b.estudiantes OR a.programas <> b.programas OR a.matriculas <> b.matriculas))
    THROW 52632, 'TEST FAILED: ENROLL_DOCENTE_NO_TITULAR_DENIED produced writes.', 1;
PRINT 'TEST_PASS:ENROLL_DOCENTE_NO_TITULAR_DENIED';

-- ---------------------------------------------------------------------------------------------
-- 6. COORDINADOR del programa del grupo -> permitido (exito revertido).
-- ---------------------------------------------------------------------------------------------
SAVE TRANSACTION qa_contrato_2;
SET @corr = NEWID();
SET @correo = CONCAT(N'qa.contrato.coord.', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), N'@test.local');
SET @num = 1000000000 + ABS(CHECKSUM(NEWID()) % 500000000);
TRUNCATE TABLE #res;
INSERT INTO #res EXEC dbo.usp_registrar_estudiante_en_grupo
    @numeroIdentificacion = @num, @primerApellido = N'Quality', @segundoApellido = N'Gate',
    @primerNombre = N'Contrato', @segundoNombre = N'Coord', @correo = @correo,
    @password = N'HashBackend_QaContrato1234567890', @idGrupo = @grupo, @idCorrelacion = @corr,
    @idUsuarioEjecutor = @coordTitularUser, @idTipoIdIdentificacion = @tipoCC;
IF NOT EXISTS (SELECT 1 FROM #res WHERE estadoResultado = 1 AND idCorrelacion = @corr)
    THROW 52640, 'TEST FAILED: ENROLL_COORDINADOR_PROGRAM_SUCCESS expected estado 1.', 1;
IF @@TRANCOUNT <> 1 THROW 52641, 'TEST FAILED: ENROLL_COORDINADOR_PROGRAM_SUCCESS changed the external transaction.', 1;
ROLLBACK TRANSACTION qa_contrato_2;
PRINT 'TEST_PASS:ENROLL_COORDINADOR_PROGRAM_SUCCESS';

-- ---------------------------------------------------------------------------------------------
-- 7. COORDINADOR de OTRO programa -> SEC_002, cero escrituras.
-- ---------------------------------------------------------------------------------------------
SET @corr = NEWID();
SET @correo = CONCAT(N'qa.contrato.otroprog.', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), N'@test.local');
SET @num = 1000000000 + ABS(CHECKSUM(NEWID()) % 500000000);
TRUNCATE TABLE #res; TRUNCATE TABLE #snap;
INSERT #snap SELECT 'before', (SELECT COUNT(*) FROM dbo.Usuario), (SELECT COUNT(*) FROM dbo.Estudiante), (SELECT COUNT(*) FROM dbo.EstudiantePrograma), (SELECT COUNT(*) FROM dbo.EstudianteGrupo);
INSERT INTO #res EXEC dbo.usp_registrar_estudiante_en_grupo
    @numeroIdentificacion = @num, @primerApellido = N'Quality', @segundoApellido = N'Gate',
    @primerNombre = N'Contrato', @segundoNombre = N'OtroPrograma', @correo = @correo,
    @password = N'HashBackend_QaContrato1234567890', @idGrupo = @grupo, @idCorrelacion = @corr,
    @idUsuarioEjecutor = @coordOtroUser, @idTipoIdIdentificacion = @tipoCC;
IF NOT EXISTS (SELECT 1 FROM #res WHERE estadoResultado = 0 AND idCorrelacion = @corr)
    THROW 52650, 'TEST FAILED: ENROLL_COORDINADOR_OTHER_PROGRAM_DENIED expected estado 0.', 1;
INSERT #snap SELECT 'after', (SELECT COUNT(*) FROM dbo.Usuario), (SELECT COUNT(*) FROM dbo.Estudiante), (SELECT COUNT(*) FROM dbo.EstudiantePrograma), (SELECT COUNT(*) FROM dbo.EstudianteGrupo);
IF EXISTS (SELECT 1 FROM #snap b INNER JOIN #snap a ON a.fase = 'after' WHERE b.fase = 'before'
    AND (a.usuarios <> b.usuarios OR a.estudiantes <> b.estudiantes OR a.programas <> b.programas OR a.matriculas <> b.matriculas))
    THROW 52651, 'TEST FAILED: ENROLL_COORDINADOR_OTHER_PROGRAM_DENIED produced writes.', 1;
PRINT 'TEST_PASS:ENROLL_COORDINADOR_OTHER_PROGRAM_DENIED';

-- ---------------------------------------------------------------------------------------------
-- 8. Usuario con DOCENTE (no titular) + COORDINADOR del programa -> OR: basta una regla (exito revertido).
--    Fixture: el docente no titular pasa a ser coordinador del programa dentro de la transaccion.
-- ---------------------------------------------------------------------------------------------
SAVE TRANSACTION qa_contrato_3;
DECLARE @coordDualId UNIQUEIDENTIFIER = NEWID();
INSERT dbo.Coordinador (id, usuario) VALUES (@coordDualId, @docenteNoTitularUser);
UPDATE dbo.Programa SET coordinador = @coordDualId WHERE id = @programa;
SET @corr = NEWID();
SET @correo = CONCAT(N'qa.contrato.dual.', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), N'@test.local');
SET @num = 1000000000 + ABS(CHECKSUM(NEWID()) % 500000000);
TRUNCATE TABLE #res;
INSERT INTO #res EXEC dbo.usp_registrar_estudiante_en_grupo
    @numeroIdentificacion = @num, @primerApellido = N'Quality', @segundoApellido = N'Gate',
    @primerNombre = N'Contrato', @segundoNombre = N'Dual', @correo = @correo,
    @password = N'HashBackend_QaContrato1234567890', @idGrupo = @grupo, @idCorrelacion = @corr,
    @idUsuarioEjecutor = @docenteNoTitularUser, @idTipoIdIdentificacion = @tipoCC;
IF NOT EXISTS (SELECT 1 FROM #res WHERE estadoResultado = 1 AND idCorrelacion = @corr)
    THROW 52660, 'TEST FAILED: ENROLL_DUAL_ROLE_OR_SUCCESS expected estado 1 via coordinator rule.', 1;
IF @@TRANCOUNT <> 1 THROW 52661, 'TEST FAILED: ENROLL_DUAL_ROLE_OR_SUCCESS changed the external transaction.', 1;
ROLLBACK TRANSACTION qa_contrato_3;
PRINT 'TEST_PASS:ENROLL_DUAL_ROLE_OR_SUCCESS';

-- ---------------------------------------------------------------------------------------------
-- 9. Conflicto de identidad: correo de usuario A + documento de usuario B -> IDN_001, cero escrituras.
-- ---------------------------------------------------------------------------------------------
DECLARE @correoTitular NVARCHAR(100) = (SELECT correo FROM dbo.uv_usuario WHERE id = @docenteTitularUser);
DECLARE @tipoOtro UNIQUEIDENTIFIER, @numOtro INT;
SELECT @tipoOtro = idTipoIdentificacion, @numOtro = numeroIdentificacion FROM dbo.uv_usuario WHERE id = @coordOtroUser;
SET @corr = NEWID();
TRUNCATE TABLE #res; TRUNCATE TABLE #snap;
INSERT #snap SELECT 'before', (SELECT COUNT(*) FROM dbo.Usuario), (SELECT COUNT(*) FROM dbo.Estudiante), (SELECT COUNT(*) FROM dbo.EstudiantePrograma), (SELECT COUNT(*) FROM dbo.EstudianteGrupo);
INSERT INTO #res EXEC dbo.usp_registrar_estudiante_en_grupo
    @numeroIdentificacion = @numOtro, @primerApellido = N'Quality', @segundoApellido = N'Gate',
    @primerNombre = N'Contrato', @segundoNombre = N'Conflicto', @correo = @correoTitular,
    @password = N'HashBackend_QaContrato1234567890', @idGrupo = @grupo, @idCorrelacion = @corr,
    @idUsuarioEjecutor = @docenteTitularUser, @idTipoIdIdentificacion = @tipoOtro;
EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'IDN_001',
    @mensajeUsuarioResultado = @msgUsuario OUTPUT, @mensajeTecnicoResultado = @msgTecnico OUTPUT;
IF NOT EXISTS (SELECT 1 FROM #res WHERE estadoResultado = 0 AND idCorrelacion = @corr
    AND mensajeUsuarioResultado = @msgUsuario AND mensajeTecnicoResultado = CONCAT(@msgTecnico, ' Correlacion: ', @corr))
    THROW 52670, 'TEST FAILED: ENROLL_IDENTITY_CONFLICT_IDN_001 expected canonical IDN_001.', 1;
INSERT #snap SELECT 'after', (SELECT COUNT(*) FROM dbo.Usuario), (SELECT COUNT(*) FROM dbo.Estudiante), (SELECT COUNT(*) FROM dbo.EstudiantePrograma), (SELECT COUNT(*) FROM dbo.EstudianteGrupo);
IF EXISTS (SELECT 1 FROM #snap b INNER JOIN #snap a ON a.fase = 'after' WHERE b.fase = 'before'
    AND (a.usuarios <> b.usuarios OR a.estudiantes <> b.estudiantes OR a.programas <> b.programas OR a.matriculas <> b.matriculas))
    THROW 52671, 'TEST FAILED: ENROLL_IDENTITY_CONFLICT_IDN_001 produced writes or merged identities.', 1;
PRINT 'TEST_PASS:ENROLL_IDENTITY_CONFLICT_IDN_001';

-- ---------------------------------------------------------------------------------------------
-- 10. Usuario existente (correo y documento del mismo usuario): se reutiliza, su password NO cambia.
-- ---------------------------------------------------------------------------------------------
DECLARE @correoExistente NVARCHAR(100), @tipoExistente UNIQUEIDENTIFIER, @numExistente INT, @passExistente NVARCHAR(500);
SELECT @correoExistente = correo, @tipoExistente = idTipoIdentificacion, @numExistente = numeroIdentificacion
FROM dbo.uv_usuario WHERE id = @estudianteSinGrupo;
SELECT @passExistente = password FROM dbo.Usuario WHERE id = @estudianteSinGrupo;

SAVE TRANSACTION qa_contrato_4;
SET @corr = NEWID();
TRUNCATE TABLE #res; TRUNCATE TABLE #snap;
INSERT #snap SELECT 'before', (SELECT COUNT(*) FROM dbo.Usuario), (SELECT COUNT(*) FROM dbo.Estudiante), (SELECT COUNT(*) FROM dbo.EstudiantePrograma), (SELECT COUNT(*) FROM dbo.EstudianteGrupo);
INSERT INTO #res EXEC dbo.usp_registrar_estudiante_en_grupo
    @numeroIdentificacion = @numExistente, @primerApellido = N'Quality', @segundoApellido = N'Gate',
    @primerNombre = N'Contrato', @segundoNombre = N'Existente', @correo = @correoExistente,
    @password = N'OtraClave_NoDebeGuardarse123', @idGrupo = @grupo, @idCorrelacion = @corr,
    @idUsuarioEjecutor = @docenteTitularUser, @idTipoIdIdentificacion = @tipoExistente;
IF NOT EXISTS (SELECT 1 FROM #res WHERE estadoResultado = 1 AND idCorrelacion = @corr)
    THROW 52680, 'TEST FAILED: ENROLL_EXISTING_USER_PASSWORD_UNCHANGED expected estado 1.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @estudianteSinGrupo AND password = @passExistente)
    THROW 52681, 'TEST FAILED: ENROLL_EXISTING_USER_PASSWORD_UNCHANGED overwrote the password of an existing user.', 1;
INSERT #snap SELECT 'after', (SELECT COUNT(*) FROM dbo.Usuario), (SELECT COUNT(*) FROM dbo.Estudiante), (SELECT COUNT(*) FROM dbo.EstudiantePrograma), (SELECT COUNT(*) FROM dbo.EstudianteGrupo);
IF (SELECT usuarios FROM #snap WHERE fase = 'after') <> (SELECT usuarios FROM #snap WHERE fase = 'before')
   OR (SELECT estudiantes FROM #snap WHERE fase = 'after') <> (SELECT estudiantes FROM #snap WHERE fase = 'before')
   OR (SELECT matriculas FROM #snap WHERE fase = 'after') - (SELECT matriculas FROM #snap WHERE fase = 'before') <> 1
    THROW 52682, 'TEST FAILED: ENROLL_EXISTING_USER_PASSWORD_UNCHANGED created duplicate Usuario/Estudiante or missed the matricula.', 1;
ROLLBACK TRANSACTION qa_contrato_4;
PRINT 'TEST_PASS:ENROLL_EXISTING_USER_PASSWORD_UNCHANGED';

-- ---------------------------------------------------------------------------------------------
-- 11. Atomicidad con transaccion externa: fallo forzado DESPUES de crear Usuario/Estudiante.
--     Debe revertirse solo el savepoint; no quedan residuos y la transaccion externa sigue viva.
-- ---------------------------------------------------------------------------------------------
SAVE TRANSACTION qa_contrato_5;
EXEC sys.sp_executesql @triggerSql;
DECLARE @hitPreflight INT = 0;
BEGIN TRY
    INSERT dbo.EstudianteGrupo (id, estado, estudiante, grupo)
    SELECT NEWID(), (SELECT TOP 1 id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'A'), (SELECT TOP 1 id FROM dbo.Estudiante), @grupo;
END TRY
BEGIN CATCH
    SET @hitPreflight = CASE WHEN ERROR_NUMBER() = 547 THEN 1 ELSE 0 END;
END CATCH;
IF @hitPreflight = 0 THROW 52690, 'TEST FAILED: ENROLL_ATOMIC preflight: forced trigger did not fire.', 1;
IF XACT_STATE() <> 1 THROW 52691, 'TEST FAILED: ENROLL_ATOMIC preflight doomed the external transaction.', 1;

SET @corr = NEWID();
SET @correo = CONCAT(N'qa.contrato.atomic.', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), N'@test.local');
SET @num = 1000000000 + ABS(CHECKSUM(NEWID()) % 500000000);
TRUNCATE TABLE #snap;
INSERT #snap SELECT 'before', (SELECT COUNT(*) FROM dbo.Usuario), (SELECT COUNT(*) FROM dbo.Estudiante), (SELECT COUNT(*) FROM dbo.EstudiantePrograma), (SELECT COUNT(*) FROM dbo.EstudianteGrupo);
EXEC dbo.usp_registrar_estudiante_en_grupo
    @numeroIdentificacion = @num, @primerApellido = N'Quality', @segundoApellido = N'Gate',
    @primerNombre = N'Contrato', @segundoNombre = N'Atomic', @correo = @correo,
    @password = N'HashBackend_QaContrato1234567890', @idGrupo = @grupo, @idCorrelacion = @corr,
    @idUsuarioEjecutor = @docenteTitularUser, @idTipoIdIdentificacion = @tipoCC;
IF @@TRANCOUNT <> 1 THROW 52692, 'TEST FAILED: ENROLL_ATOMIC changed the external transaction count.', 1;
IF XACT_STATE() <> 1 THROW 52693, 'TEST FAILED: ENROLL_ATOMIC external transaction not usable after savepoint rollback.', 1;
INSERT #snap SELECT 'after', (SELECT COUNT(*) FROM dbo.Usuario), (SELECT COUNT(*) FROM dbo.Estudiante), (SELECT COUNT(*) FROM dbo.EstudiantePrograma), (SELECT COUNT(*) FROM dbo.EstudianteGrupo);
IF EXISTS (SELECT 1 FROM #snap b INNER JOIN #snap a ON a.fase = 'after' WHERE b.fase = 'before'
    AND (a.usuarios <> b.usuarios OR a.estudiantes <> b.estudiantes OR a.programas <> b.programas OR a.matriculas <> b.matriculas))
    THROW 52694, 'TEST FAILED: ENROLL_ATOMIC_SAVEPOINT_ROLLBACK left residual rows.', 1;
IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo = @correo)
    THROW 52695, 'TEST FAILED: ENROLL_ATOMIC_SAVEPOINT_ROLLBACK left a partial Usuario.', 1;
ROLLBACK TRANSACTION qa_contrato_5;
PRINT 'TEST_PASS:ENROLL_ATOMIC_SAVEPOINT_ROLLBACK';

-- ---------------------------------------------------------------------------------------------
-- 12. Atomicidad con transaccion propia (sin transaccion externa): mismo fallo forzado, cero residuos.
-- ---------------------------------------------------------------------------------------------
-- Cierra el fixture aislado: el caso de transaccion propia debe ejecutarse sin transaccion externa.
ROLLBACK TRANSACTION;
IF @@TRANCOUNT <> 0 THROW 52696, 'TEST FAILED: ENROLL_ATOMIC_OWNER_ROLLBACK must start without external transaction.', 1;
IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo LIKE N'qa.fx.%@test.local')
    THROW 52692, 'TEST FAILED: ENROLL_CONTRACT fixture leaked Usuario rows after rollback.', 1;
EXEC sys.sp_executesql @triggerSql;
BEGIN TRY
    SET @corr = NEWID();
    SET @correo = CONCAT(N'qa.contrato.owner.', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), N'@test.local');
    SET @num = 1000000000 + ABS(CHECKSUM(NEWID()) % 500000000);
    TRUNCATE TABLE #snap;
    INSERT #snap SELECT 'before', (SELECT COUNT(*) FROM dbo.Usuario), (SELECT COUNT(*) FROM dbo.Estudiante), (SELECT COUNT(*) FROM dbo.EstudiantePrograma), (SELECT COUNT(*) FROM dbo.EstudianteGrupo);
    EXEC dbo.usp_registrar_estudiante_en_grupo
        @numeroIdentificacion = @num, @primerApellido = N'Quality', @segundoApellido = N'Gate',
        @primerNombre = N'Contrato', @segundoNombre = N'Owner', @correo = @correo,
        @password = N'HashBackend_QaContrato1234567890', @idGrupo = @grupo, @idCorrelacion = @corr,
        @idUsuarioEjecutor = @docenteTitularUser, @idTipoIdIdentificacion = @tipoCC;
    IF @@TRANCOUNT <> 0 THROW 52697, 'TEST FAILED: ENROLL_ATOMIC_OWNER_ROLLBACK left an open transaction.', 1;
    INSERT #snap SELECT 'after', (SELECT COUNT(*) FROM dbo.Usuario), (SELECT COUNT(*) FROM dbo.Estudiante), (SELECT COUNT(*) FROM dbo.EstudiantePrograma), (SELECT COUNT(*) FROM dbo.EstudianteGrupo);
    IF EXISTS (SELECT 1 FROM #snap b INNER JOIN #snap a ON a.fase = 'after' WHERE b.fase = 'before'
        AND (a.usuarios <> b.usuarios OR a.estudiantes <> b.estudiantes OR a.programas <> b.programas OR a.matriculas <> b.matriculas))
        THROW 52698, 'TEST FAILED: ENROLL_ATOMIC_OWNER_ROLLBACK left residual rows.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo = @correo)
        THROW 52699, 'TEST FAILED: ENROLL_ATOMIC_OWNER_ROLLBACK left a partial Usuario.', 1;
END TRY
BEGIN CATCH
    IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'ck_qa_contrato_matricula_falla') ALTER TABLE dbo.EstudianteGrupo DROP CONSTRAINT ck_qa_contrato_matricula_falla;
    THROW;
END CATCH;
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'ck_qa_contrato_matricula_falla') ALTER TABLE dbo.EstudianteGrupo DROP CONSTRAINT ck_qa_contrato_matricula_falla;
PRINT 'TEST_PASS:ENROLL_ATOMIC_OWNER_ROLLBACK';

-- ---------------------------------------------------------------------------------------------
-- 13. Transaccion externa condenada (THROW en trigger -> XACT_STATE = -1): no admite savepoint.
--     El SP debe PROPAGAR el error al propietario (no devolver estado 0 silencioso); el propietario revierte completo.
-- ---------------------------------------------------------------------------------------------
DECLARE @doomSql NVARCHAR(MAX) = CONCAT(
    N'CREATE OR ALTER TRIGGER dbo.tr_qa_contrato_doom ON dbo.EstudianteGrupo AFTER INSERT AS ',
    N'BEGIN SET NOCOUNT ON; IF EXISTS (SELECT 1 FROM inserted WHERE grupo = ''', CONVERT(NVARCHAR(36), @grupo), N''') ',
    N'THROW 52950, ''QA forced doomed transaction'', 1; END;');
DECLARE @doomPropagado BIT = 0, @doomErrorNumero INT = NULL, @doomXactState INT = NULL;
DECLARE @usuariosAntesDoom INT = (SELECT COUNT(*) FROM dbo.Usuario);
BEGIN TRANSACTION;
EXEC sys.sp_executesql @doomSql;
SET @corr = NEWID();
SET @correo = CONCAT(N'qa.contrato.doom.', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), N'@test.local');
SET @num = 1000000000 + ABS(CHECKSUM(NEWID()) % 500000000);
BEGIN TRY
    EXEC dbo.usp_registrar_estudiante_en_grupo
        @numeroIdentificacion = @num, @primerApellido = N'Quality', @segundoApellido = N'Gate',
        @primerNombre = N'Contrato', @segundoNombre = N'Doom', @correo = @correo,
        @password = N'HashBackend_QaContrato1234567890', @idGrupo = @grupo, @idCorrelacion = @corr,
        @idUsuarioEjecutor = @docenteTitularUser, @idTipoIdIdentificacion = @tipoCC;
END TRY
BEGIN CATCH
    SET @doomPropagado = 1;
    SET @doomErrorNumero = ERROR_NUMBER();
    SET @doomXactState = XACT_STATE();
END CATCH;
IF @doomPropagado = 0
    THROW 52970, 'TEST FAILED: ENROLL_DOOMED_TX_PROPAGATED returned silently with a doomed external transaction.', 1;
IF @doomXactState <> -1 OR @doomErrorNumero <> 51000
    THROW 52971, 'TEST FAILED: ENROLL_DOOMED_TX_PROPAGATED wrong propagation state or error number.', 1;
ROLLBACK TRANSACTION;
IF @@TRANCOUNT <> 0 THROW 52972, 'TEST FAILED: ENROLL_DOOMED_TX_PROPAGATED left a transaction open.', 1;
IF EXISTS (SELECT 1 FROM sys.triggers WHERE name = N'tr_qa_contrato_doom')
    THROW 52973, 'TEST FAILED: ENROLL_DOOMED_TX_PROPAGATED leaked the forced trigger.', 1;
IF (SELECT COUNT(*) FROM dbo.Usuario) <> @usuariosAntesDoom
    THROW 52974, 'TEST FAILED: ENROLL_DOOMED_TX_PROPAGATED left residual Usuario rows.', 1;
PRINT 'TEST_PASS:ENROLL_DOOMED_TX_PROPAGATED';

IF @@TRANCOUNT <> 0 THROW 52699, 'TEST FAILED: test_registrar_estudiante_en_grupo_contrato left transactions open.', 1;
PRINT 'TEST END: test_registrar_estudiante_en_grupo_contrato';
GO
