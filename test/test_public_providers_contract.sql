USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- Contrato de los providers PUBLICOS DB consumidos por el backend (fase de alineacion de procedimientos).
--   - nombres exactos; ningun objeto publico con nombre alternativo (usp_matricula_grupo, usp_asistencia_autonomo, usp_cierre_masivo);
--   - sin parametros OUTPUT en la firma publica;
--   - resultado canonico de 1 fila y 4 columnas (usp_sincronizar_usuario);
--   - el provider de matricula solo invoca SP _interno existentes (nunca los expone).
PRINT 'TEST START: test_public_providers_contract';

-- 1. Nombres publicos exactos existen y los alternativos no existen.
DECLARE @nombresPublicos TABLE (nombre SYSNAME PRIMARY KEY);
INSERT @nombresPublicos VALUES
    (N'usp_registrar_estudiante_en_grupo'), (N'usp_sincronizar_usuario'),
    (N'usp_registrar_asistencia_estudiante_autonomo'), (N'usp_radicar_solicitud_revision_asistencia'),
    (N'usp_resolver_solicitud_revision_asistencia'), (N'usp_ejecutar_cierre_masivo_periodo'), (N'usp_cerrar_sesion'),
    (N'usp_registrar_o_actualizar_plan_estudio');
IF EXISTS (SELECT 1 FROM @nombresPublicos n WHERE OBJECT_ID(CONCAT(N'dbo.', n.nombre), N'P') IS NULL)
    THROW 53000, 'TEST FAILED: PUBLIC_SP_NAMES_CORRECT missing an exact public procedure name.', 1;
IF EXISTS (SELECT 1 FROM sys.objects WHERE type = 'P' AND name IN (N'usp_matricula_grupo', N'usp_matricula_grupo_interno', N'usp_asistencia_autonomo', N'usp_cierre_masivo'))
    THROW 53001, 'TEST FAILED: PUBLIC_SP_NAMES_CORRECT found a forbidden alternative procedure name.', 1;
PRINT 'TEST_PASS:PUBLIC_SP_NAMES_CORRECT';

-- 2. Ningun provider publico expone parametros OUTPUT.
IF EXISTS (
    SELECT 1
    FROM sys.parameters p
    INNER JOIN sys.procedures sp ON sp.object_id = p.object_id
    INNER JOIN @nombresPublicos n ON n.nombre = sp.name
    WHERE p.is_output = 1)
    THROW 53002, 'TEST FAILED: PUBLIC_NO_OUTPUT_PARAMS a public provider exposes an OUTPUT parameter.', 1;
PRINT 'TEST_PASS:PUBLIC_NO_OUTPUT_PARAMS';

-- 3. Firma de usp_cerrar_sesion (TD-039): (@idSesion, @idDocente, @idCorrelacion, @idUsuarioEjecutor = NULL).
IF (SELECT COUNT(*) FROM sys.parameters p INNER JOIN sys.procedures sp ON sp.object_id = p.object_id
    WHERE sp.name = N'usp_cerrar_sesion' AND p.name IN (N'@idSesion', N'@idDocente', N'@idCorrelacion', N'@idUsuarioEjecutor')) <> 4
    THROW 53003, 'TEST FAILED: SESSION_CLOSE_SIGNATURE usp_cerrar_sesion does not expose the documented parameters.', 1;
PRINT 'TEST_PASS:SESSION_CLOSE_SIGNATURE';

-- 4. usp_registrar_estudiante_en_grupo invoca unicamente SP internos reales (STUDENT_ENROLLMENT_INTERNAL_CALLS).
IF EXISTS (
    SELECT 1 FROM sys.sql_expression_dependencies d
    INNER JOIN sys.objects o ON o.object_id = d.referencing_id
    WHERE o.name = N'usp_registrar_estudiante_en_grupo' AND d.referenced_database_name IS NULL
      AND d.referenced_entity_name LIKE N'usp[_]%'
      AND d.referenced_id IS NULL)
    THROW 53004, 'TEST FAILED: STUDENT_ENROLLMENT_INTERNAL_CALLS references a missing procedure.', 1;
IF NOT EXISTS (SELECT 1 FROM sys.sql_expression_dependencies d INNER JOIN sys.objects o ON o.object_id = d.referencing_id
    WHERE o.name = N'usp_registrar_estudiante_en_grupo' AND d.referenced_entity_name = N'usp_registrar_estudiante_en_grupo_interno')
    OR NOT EXISTS (SELECT 1 FROM sys.sql_expression_dependencies d INNER JOIN sys.objects o ON o.object_id = d.referencing_id
    WHERE o.name = N'usp_registrar_estudiante_en_grupo' AND d.referenced_entity_name = N'usp_sincronizar_usuario_interno')
    THROW 53005, 'TEST FAILED: STUDENT_ENROLLMENT_INTERNAL_CALLS does not compose the canonical internal procedures.', 1;
PRINT 'TEST_PASS:STUDENT_ENROLLMENT_INTERNAL_CALLS';

-- 5. usp_sincronizar_usuario (publico): resultado canonico 1 fila / 4 columnas.
DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @corr UNIQUEIDENTIFIER = NEWID();
DECLARE @correoSync NVARCHAR(255) = CONCAT(N'qa.sync.', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), N'@test.local');
DECLARE @numSync INT = 1000000000 + ABS(CHECKSUM(NEWID()) % 500000000);
CREATE TABLE #syncRes (
    idCorrelacion UNIQUEIDENTIFIER NULL,
    mensajeUsuarioResultado NVARCHAR(MAX) NULL,
    mensajeTecnicoResultado NVARCHAR(MAX) NULL,
    estadoResultado INT NOT NULL
);

-- 5a. Fallo: correo invalido -> canonico, estado 0, cero escrituras.
DECLARE @usuariosAntes INT = (SELECT COUNT(*) FROM dbo.Usuario);
INSERT INTO #syncRes EXEC dbo.usp_sincronizar_usuario
    @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = @numSync,
    @primerApellido = N'Quality', @segundoApellido = N'Gate', @primerNombre = N'Contrato', @segundoNombre = N'Sync',
    @correo = N'correo-invalido', @password = N'HashBackend_QaSync1234567890', @idCorrelacion = @corr;
IF NOT EXISTS (SELECT 1 FROM #syncRes WHERE estadoResultado = 0 AND idCorrelacion = @corr)
    THROW 53010, 'TEST FAILED: USER_SYNC_PUBLIC_PROVIDER invalid input must return canonical estado 0.', 1;
IF @usuariosAntes <> (SELECT COUNT(*) FROM dbo.Usuario)
    THROW 53011, 'TEST FAILED: USER_SYNC_PUBLIC_PROVIDER invalid input wrote a Usuario.', 1;
PRINT 'TEST_PASS:USER_SYNC_PUBLIC_INVALID';

-- 5b. Exito dentro de transaccion externa (revertida): estado 1 y exactamente un Usuario nuevo.
BEGIN TRANSACTION;
TRUNCATE TABLE #syncRes;
INSERT INTO #syncRes EXEC dbo.usp_sincronizar_usuario
    @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = @numSync,
    @primerApellido = N'Quality', @segundoApellido = N'Gate', @primerNombre = N'Contrato', @segundoNombre = N'Sync',
    @correo = @correoSync, @password = N'HashBackend_QaSync1234567890', @idCorrelacion = @corr;
IF NOT EXISTS (SELECT 1 FROM #syncRes WHERE estadoResultado = 1 AND idCorrelacion = @corr)
    THROW 53012, 'TEST FAILED: USER_SYNC_PUBLIC_PROVIDER valid input must return canonical estado 1.', 1;
IF (SELECT COUNT(*) FROM dbo.Usuario WHERE correo = @correoSync) <> 1
    THROW 53013, 'TEST FAILED: USER_SYNC_PUBLIC_PROVIDER did not create exactly one Usuario.', 1;
ROLLBACK TRANSACTION;
PRINT 'TEST_PASS:USER_SYNC_PUBLIC_PROVIDER';

IF @@TRANCOUNT <> 0 THROW 53014, 'TEST FAILED: test_public_providers_contract left transaction open.', 1;
PRINT 'TEST END: test_public_providers_contract';
GO
