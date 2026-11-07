USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ============================================================================
-- CULM-001 paquete A.1 (CONTRACT §2.6): retiro de las solicitudes de ingreso a grupos (HU026, HU053, HU054 y HU055
-- descartadas), reactivacion de la matricula retirada por las dos vias que quedan (DEC-009: manual HU050 y QR/PIN
-- HU176B) y matricula manual solo del DOCENTE titular (F-COO-004).
--   T-01  objetos retirados y catalogos de A           T-01b tablas de archivo aisladas (solo si existen)
--   T-04  reactivacion por QR con cupo                 T-05  QR con grupo lleno (caracterizacion)
--   T-06  QR con matricula activa (MQR_004)            T-08  el coordinador no matricula (SEC_001)
--   T-09  docente no titular (SEC_002)                 T-12  transacciones (b, c, d)
-- Formato del repo: fixtures dentro de UNA transaccion con ROLLBACK final, salvo los casos que exigen @@TRANCOUNT = 0
-- en la entrada (T-12b y T-12c), que siguen el patron de test_rec3_falla_intermedia_transaccion.sql: fixtures
-- confirmadas y limpiadas en todos los caminos. SQL Server no permite ROLLBACK dentro de INSERT ... EXEC, asi que las
-- llamadas que revierten un savepoint se hacen con EXEC directo (su resultset queda en la salida).
-- ============================================================================
PRINT 'TEST START: test_culm001_a_retiro_solicitudes';
GO

-- ---------------------------------------------------------------------------
-- T-01: objetos retirados tras la migracion 13 / deploy_schema.ps1, y catalogos que siembra A.
-- ---------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.SolicitudIngresoGrupo', N'U') IS NOT NULL
   OR OBJECT_ID(N'dbo.usp_registrar_solicitud_ingreso_grupo', N'P') IS NOT NULL
   OR OBJECT_ID(N'dbo.usp_resolver_solicitud_ingreso_grupo', N'P') IS NOT NULL
   OR OBJECT_ID(N'dbo.usp_retirar_solicitud_ingreso_grupo', N'P') IS NOT NULL
   OR OBJECT_ID(N'dbo.usp_consultar_solicitudes_ingreso_grupo_docente', N'P') IS NOT NULL
   OR OBJECT_ID(N'dbo.usp_consultar_solicitudes_ingreso_estudiante', N'P') IS NOT NULL
   OR OBJECT_ID(N'dbo.usp_consultar_destinatarios_solicitud_ingreso_grupo', N'P') IS NOT NULL
    THROW 57100, 'TEST FAILED: T-01 la tabla SolicitudIngresoGrupo y sus 6 SP deben estar retirados.', 1;
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name LIKE N'FK[_]SolicitudIngresoGrupo[_]%')
    THROW 57101, 'TEST FAILED: T-01 no deben quedar FK FK_SolicitudIngresoGrupo_*.', 1;
IF EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo LIKE 'SIG[_]0%' OR codigo LIKE 'SIG[_]1%' OR codigo = 'ERR_SOLICITUD_MATRICULA_NO_IMPLEMENTADA')
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeTecnico WHERE codigo LIKE 'SIG[_]0%' OR codigo LIKE 'SIG[_]1%' OR codigo = 'ERR_SOLICITUD_MATRICULA_NO_IMPLEMENTADA')
    THROW 57102, 'TEST FAILED: T-01 no deben quedar mensajes SIG_* ni ERR_SOLICITUD_MATRICULA_NO_IMPLEMENTADA.', 1;
IF EXISTS (SELECT 1 FROM dbo.PlantillaNotificacion WHERE tipo LIKE 'SOLICITUD[_]INGRESO[_]%')
   OR EXISTS (SELECT 1 FROM dbo.PlantillaNotificacionMarcador WHERE tipo LIKE 'SOLICITUD[_]INGRESO[_]%')
    THROW 57103, 'TEST FAILED: T-01 no deben quedar plantillas ni marcadores SOLICITUD_INGRESO_*.', 1;
IF EXISTS (SELECT 1 FROM dbo.Estado WHERE codigo = 'E')
   OR NOT EXISTS (SELECT 1 FROM dbo.Estado WHERE codigo = 'X' AND id = 'D6E2F3A4-5B6C-4D7E-9F80-A12B3C4D5E6F')
    THROW 57104, 'TEST FAILED: T-01 el estado E (en espera) se retira y el estado X (retirada) se conserva.', 1;
IF dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_RETIRADA') <> N'I'
   OR dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') <> N'A'
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo = 'MATRICULA' AND clave = 'ESTADO_RETIRADA' AND valor = N'I')
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo = 'MATRICULA' AND clave = 'ESTADO_INSCRITA' AND valor = N'A')
    THROW 57105, 'TEST FAILED: T-01 parametros MATRICULA/ESTADO_RETIRADA = I y MATRICULA/ESTADO_INSCRITA = A.', 1;
IF OBJECT_ID(N'dbo.usp_internal_reactivar_matricula_retirada', N'P') IS NULL
    THROW 57106, 'TEST FAILED: T-01 falta el SP interno usp_internal_reactivar_matricula_retirada.', 1;
PRINT 'TEST_PASS:CULM001A_T01_OBJETOS_RETIRADOS';
GO

-- ---------------------------------------------------------------------------
-- T-01b: las tablas de archivo (si existen; una BD construida solo con deploy_schema.ps1 no las tiene) no tienen FK,
-- ni permisos del runtime, ni modulos que las lean. Su existencia la exige T-10 (test_migracion_13_culm001_a.ps1).
-- ---------------------------------------------------------------------------
DECLARE @archivos TABLE (nombre SYSNAME);
INSERT @archivos (nombre) VALUES (N'zz_archivo_SolicitudIngresoGrupo'), (N'zz_archivo_NotificacionSolicitudIngreso'),
    (N'zz_archivo_PlantillaSolicitudIngreso'), (N'zz_archivo_PlantillaMarcadorSolicitudIngreso');
IF EXISTS (SELECT 1 FROM sys.foreign_keys fk INNER JOIN @archivos a ON OBJECT_ID(N'dbo.' + a.nombre, N'U') IN (fk.parent_object_id, fk.referenced_object_id))
    THROW 57110, 'TEST FAILED: T-01b las tablas de archivo no deben tener FK.', 1;
IF EXISTS (SELECT 1 FROM sys.database_permissions p INNER JOIN @archivos a ON p.major_id = OBJECT_ID(N'dbo.' + a.nombre, N'U')
           WHERE p.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime'))
    THROW 57111, 'TEST FAILED: T-01b el runtime no debe tener permisos sobre las tablas de archivo.', 1;
IF EXISTS (SELECT 1 FROM sys.sql_expression_dependencies d INNER JOIN @archivos a ON d.referenced_entity_name = a.nombre)
    THROW 57112, 'TEST FAILED: T-01b ningun modulo debe referenciar las tablas de archivo.', 1;
PRINT 'TEST_PASS:CULM001A_T01B_ARCHIVO_AISLADO';
GO

-- ---------------------------------------------------------------------------
-- T-04, T-05 (QR), T-06 (QR), T-08 y T-09 dentro de UNA transaccion con ROLLBACK final (T-12a).
-- ---------------------------------------------------------------------------
SET NOCOUNT ON;
SET XACT_ABORT OFF;
DECLARE @grupo UNIQUEIDENTIFIER, @docenteTitular UNIQUEIDENTIFIER, @userTitular UNIQUEIDENTIFIER;
SELECT TOP 1 @grupo = g.id, @docenteTitular = g.docente
FROM dbo.Grupo g INNER JOIN dbo.uv_grupo vg ON vg.id = g.id
WHERE vg.grupoEstaHablitado = 1 AND vg.cuposDisponibles > 5
ORDER BY vg.cuposDisponibles DESC, g.id;
SELECT @userTitular = usuario FROM dbo.Docente WHERE id = @docenteTitular;
DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = 'CC');
DECLARE @facultad UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Facultad ORDER BY id);
DECLARE @dominio NVARCHAR(255) = dbo.ufn_obtener_parametro('REGISTRO', 'DOMINIO_CORREO_ESTUDIANTE');
DECLARE @estadoActiva NVARCHAR(10) = dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_ACTIVA');
DECLARE @estadoCerrada NVARCHAR(10) = dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_CERRADA');
IF @grupo IS NULL OR @userTitular IS NULL OR @tipoCC IS NULL OR @facultad IS NULL OR @dominio = N''
    THROW 57120, 'TEST FAILED: CULM001A fixture de grupo/docente/tipo/facultad/dominio faltante (semilla).', 1;

DECLARE @corr UNIQUEIDENTIFIER = NEWID(), @msgU NVARCHAR(4000), @msgT NVARCHAR(4000);
DECLARE @sufijo NVARCHAR(32) = REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', '');
DECLARE @base INT = 1600000000 + ABS(CHECKSUM(NEWID()) % 400000000);
DECLARE @u2 UNIQUEIDENTIFIER = NEWID(), @e2 UNIQUEIDENTIFIER = NEWID();
DECLARE @uCoord UNIQUEIDENTIFIER = NEWID(), @coord UNIQUEIDENTIFIER = NEWID();
DECLARE @uDoc2 UNIQUEIDENTIFIER = NEWID(), @doc2 UNIQUEIDENTIFIER = NEWID();
DECLARE @correoE2 NVARCHAR(255) = CONCAT(N'culm001a.e2.', @sufijo, @dominio);
DECLARE @correoNuevo NVARCHAR(255) = CONCAT(N'culm001a.nuevo.', @sufijo, @dominio);
DECLARE @numE2 INT = @base + 1, @numNuevo INT = @base + 2;
DECLARE @eg2 UNIQUEIDENTIFIER, @idV UNIQUEIDENTIFIER, @totalAntes INT, @capacidadOriginal INT;
DECLARE @usrAntes INT, @estAntes INT, @egAntes INT, @epAntes INT;
DECLARE @tok NVARCHAR(100) = CONCAT(N'tok-', @sufijo);
DECLARE @hash VARBINARY(32) = HASHBYTES('SHA2_256', @tok);
DECLARE @pin NCHAR(6) = RIGHT(CONCAT('000000', CAST(ABS(CHECKSUM(NEWID())) % 1000000 AS VARCHAR(6))), 6);

CREATE TABLE #r (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
CREATE TABLE #v (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(MAX), mensajeTecnicoResultado NVARCHAR(MAX), estadoResultado BIT,
    idVentana UNIQUEIDENTIFIER, fechaExpiracionUtc DATETIME2(0));
CREATE TABLE #m (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(MAX), mensajeTecnicoResultado NVARCHAR(MAX), estadoResultado BIT,
    idEstudiante UNIQUEIDENTIFIER, idUsuario UNIQUEIDENTIFIER, idGrupo UNIQUEIDENTIFIER);

BEGIN TRANSACTION;
BEGIN TRY
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@u2, @tipoCC, @numE2, N'Dos', N'Culm', N'Est', N'A', LOWER(@correoE2), 1, 1, N'HashBackend_Culm001A'),
           (@uCoord, @tipoCC, @base + 3, N'Coord', N'Culm', N'Coor', N'A', CONCAT(N'culm001a.coord.', @sufijo, N'@test.local'), 1, 1, N'HashBackend_Culm001A'),
           (@uDoc2, @tipoCC, @base + 4, N'Doc', N'Culm', N'Doce', N'A', CONCAT(N'culm001a.doc2.', @sufijo, N'@test.local'), 1, 1, N'HashBackend_Culm001A');
    INSERT INTO dbo.Estudiante (id, usuario) VALUES (@e2, @u2);
    INSERT INTO dbo.Coordinador (id, usuario, facultad) VALUES (@coord, @uCoord, @facultad);
    INSERT INTO dbo.Docente (id, usuario) VALUES (@doc2, @uDoc2);

    -- Ventana QR abierta por el titular (patron de test_usp_matricular_estudiante_por_token.sql).
    UPDATE dbo.TokenMatriculaGrupo SET estado = @estadoCerrada WHERE grupo = @grupo AND estado = @estadoActiva;
    INSERT INTO #v EXEC dbo.usp_abrir_ventana_matricula_grupo @idGrupo = @grupo, @tokenHash = @hash, @pin = @pin,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @userTitular;
    SELECT @idV = idVentana FROM #v WHERE estadoResultado = 1;
    IF @idV IS NULL THROW 57121, 'TEST FAILED: CULM001A no se pudo abrir la ventana QR de prueba.', 1;

    -- E2 matriculado a mano por el titular y retirado (HU051: A -> I).
    INSERT INTO #r EXEC dbo.usp_registrar_estudiante_en_grupo @idGrupo = @grupo, @numeroIdentificacion = @numE2,
        @primerNombre = N'Est', @segundoNombre = N'A', @primerApellido = N'Dos', @segundoApellido = N'Culm',
        @correo = @correoE2, @password = N'HashBackend_Culm001A', @idCorrelacion = @corr, @idUsuarioEjecutor = @userTitular;
    SELECT @eg2 = id FROM dbo.EstudianteGrupo WHERE grupo = @grupo AND estudiante = @e2;
    INSERT INTO #r EXEC dbo.usp_retirar_estudiante_grupo @idGrupo = @grupo, @idEstudiante = @e2, @motivo = N'Retiro CULM001A',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @userTitular;
    IF @eg2 IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo WHERE id = @eg2 AND codigoEstadoEstudiante = 'I')
        THROW 57122, 'TEST FAILED: CULM001A precondicion (E2 con matricula retirada I).', 1;

    -- T-04: la matricula por PIN de un retirado reactiva la MISMA fila (A) y suma 1 a totalMatriculas.
    SET @totalAntes = (SELECT totalMatriculas FROM dbo.TokenMatriculaGrupo WHERE id = @idV);
    TRUNCATE TABLE #m;
    INSERT INTO #m EXEC dbo.usp_matricular_estudiante_por_token @tokenHash = NULL, @pin = @pin, @idUsuarioEjecutor = @u2, @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #m WHERE estadoResultado = 1 AND idEstudiante = @e2 AND idGrupo = @grupo)
       OR (SELECT COUNT(*) FROM dbo.EstudianteGrupo WHERE grupo = @grupo AND estudiante = @e2) <> 1
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo WHERE id = @eg2 AND codigoEstadoEstudiante = 'A')
       OR (SELECT totalMatriculas FROM dbo.TokenMatriculaGrupo WHERE id = @idV) <> @totalAntes + 1
        THROW 57123, 'TEST FAILED: T-04 el QR debe reactivar la misma matricula (A) y sumar 1 a totalMatriculas.', 1;
    IF @@TRANCOUNT <> 1 THROW 57124, 'TEST FAILED: T-04 altero el nivel de transaccion del llamador (T-12a).', 1;
    PRINT 'TEST_PASS:CULM001A_T04_QR_REACTIVA';

    -- T-06 (QR): con la matricula activa, el QR sigue respondiendo MQR_004 sin cambios.
    SET @totalAntes = (SELECT totalMatriculas FROM dbo.TokenMatriculaGrupo WHERE id = @idV);
    TRUNCATE TABLE #m;
    INSERT INTO #m EXEC dbo.usp_matricular_estudiante_por_token @tokenHash = NULL, @pin = @pin, @idUsuarioEjecutor = @u2, @idCorrelacion = @corr;
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'MQR_004', @mensajeUsuarioResultado = @msgU OUTPUT, @mensajeTecnicoResultado = @msgT OUTPUT;
    IF NOT EXISTS (SELECT 1 FROM #m WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msgU)
       OR (SELECT totalMatriculas FROM dbo.TokenMatriculaGrupo WHERE id = @idV) <> @totalAntes
       OR (SELECT COUNT(*) FROM dbo.EstudianteGrupo WHERE grupo = @grupo AND estudiante = @e2) <> 1
        THROW 57125, 'TEST FAILED: T-06 una matricula activa debe seguir bloqueando el QR (MQR_004).', 1;
    PRINT 'TEST_PASS:CULM001A_T06_QR_ACTIVA_BLOQUEADA';

    -- T-05 (QR): grupo lleno y E2 retirado: el QR rechaza la reactivacion y totalMatriculas no cambia.
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_retirar_estudiante_grupo @idGrupo = @grupo, @idEstudiante = @e2, @motivo = N'Retiro CULM001A 2',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @userTitular;
    SET @capacidadOriginal = (SELECT cantidadEstudiantes FROM dbo.Grupo WHERE id = @grupo);
    UPDATE dbo.Grupo SET cantidadEstudiantes = (SELECT estudiantesActivos FROM dbo.uv_grupo WHERE id = @grupo) WHERE id = @grupo;
    SET @totalAntes = (SELECT totalMatriculas FROM dbo.TokenMatriculaGrupo WHERE id = @idV);
    TRUNCATE TABLE #m;
    INSERT INTO #m EXEC dbo.usp_matricular_estudiante_por_token @tokenHash = NULL, @pin = @pin, @idUsuarioEjecutor = @u2, @idCorrelacion = @corr;
    UPDATE dbo.Grupo SET cantidadEstudiantes = @capacidadOriginal WHERE id = @grupo;
    IF NOT EXISTS (SELECT 1 FROM #m WHERE estadoResultado = 0)
       OR (SELECT totalMatriculas FROM dbo.TokenMatriculaGrupo WHERE id = @idV) <> @totalAntes
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo WHERE id = @eg2 AND codigoEstadoEstudiante = 'I')
       OR (SELECT COUNT(*) FROM dbo.EstudianteGrupo WHERE grupo = @grupo AND estudiante = @e2) <> 1
        THROW 57126, 'TEST FAILED: T-05 un grupo lleno debe rechazar la reactivacion por QR sin cambios.', 1;
    PRINT 'TEST_PASS:CULM001A_T05_QR_CUPO_LLENO';

    -- T-08 (F-COO-004): el coordinador ya no matricula (SEC_001), sin Usuario/Estudiante/EstudianteGrupo nuevos.
    SELECT @usrAntes = COUNT(*) FROM dbo.Usuario; SELECT @estAntes = COUNT(*) FROM dbo.Estudiante;
    SELECT @egAntes = COUNT(*) FROM dbo.EstudianteGrupo; SELECT @epAntes = COUNT(*) FROM dbo.EstudiantePrograma;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_registrar_estudiante_en_grupo @idGrupo = @grupo, @numeroIdentificacion = @numNuevo,
        @primerNombre = N'Nuevo', @segundoNombre = N'A', @primerApellido = N'Coord', @segundoApellido = N'Culm',
        @correo = @correoNuevo, @password = N'HashBackend_Culm001A', @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SEC[_]001|%')
       OR (SELECT COUNT(*) FROM dbo.Usuario) <> @usrAntes OR (SELECT COUNT(*) FROM dbo.Estudiante) <> @estAntes
       OR (SELECT COUNT(*) FROM dbo.EstudianteGrupo) <> @egAntes OR (SELECT COUNT(*) FROM dbo.EstudiantePrograma) <> @epAntes
        THROW 57127, 'TEST FAILED: T-08 el coordinador no debe poder matricular (SEC_001, sin escrituras).', 1;
    PRINT 'TEST_PASS:CULM001A_T08_COORDINADOR_403';

    -- T-09: un docente activo que no es titular del grupo no matricula (SEC_002), sin escrituras.
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_registrar_estudiante_en_grupo @idGrupo = @grupo, @numeroIdentificacion = @numNuevo,
        @primerNombre = N'Nuevo', @segundoNombre = N'A', @primerApellido = N'Doc', @segundoApellido = N'Culm',
        @correo = @correoNuevo, @password = N'HashBackend_Culm001A', @idCorrelacion = @corr, @idUsuarioEjecutor = @uDoc2;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SEC[_]002|%')
       OR (SELECT COUNT(*) FROM dbo.Usuario) <> @usrAntes OR (SELECT COUNT(*) FROM dbo.Estudiante) <> @estAntes
       OR (SELECT COUNT(*) FROM dbo.EstudianteGrupo) <> @egAntes OR (SELECT COUNT(*) FROM dbo.EstudiantePrograma) <> @epAntes
        THROW 57128, 'TEST FAILED: T-09 un docente no titular no debe poder matricular (SEC_002, sin escrituras).', 1;
    PRINT 'TEST_PASS:CULM001A_T09_DOCENTE_NO_TITULAR';

    IF @@TRANCOUNT <> 1 THROW 57198, 'TEST FAILED: CULM001A el objeto altero el nivel de transaccion del llamador (T-12a).', 1;
    ROLLBACK TRANSACTION;
    PRINT '-> Rollback transaccional ejecutado. Cero residuos.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT CONCAT('ERROR EN TEST: ', ERROR_MESSAGE());
    THROW;
END CATCH;
IF @@TRANCOUNT <> 0 THROW 57199, 'TEST FAILED: CULM001A dejo transacciones abiertas.', 1;
DROP TABLE IF EXISTS #r;
DROP TABLE IF EXISTS #v;
DROP TABLE IF EXISTS #m;
GO

-- ---------------------------------------------------------------------------
-- T-12b: usp_internal_reactivar_matricula_retirada llamado directamente con @@TRANCOUNT = 0 (sale en 0) y con
-- @@TRANCOUNT = 1 (sale en 1), en un caso feliz, uno con cupo lleno BAJO BLOQUEO (regla 6) y uno sin matricula
-- retirada. Fixtures confirmadas (se necesita @@TRANCOUNT = 0) y limpiadas en todos los caminos.
-- ---------------------------------------------------------------------------
SET NOCOUNT ON;
SET XACT_ABORT OFF;
DECLARE @base UNIQUEIDENTIFIER = (SELECT TOP 1 g.id FROM dbo.uv_grupo g WHERE g.grupoEstaHablitado = 1 ORDER BY g.id);
DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoIdentificacion ORDER BY id);
DECLARE @estA UNIQUEIDENTIFIER = (SELECT id FROM dbo.uv_estado_estudiante_grupo WHERE codigo = N'A');
DECLARE @estI UNIQUEIDENTIFIER = (SELECT id FROM dbo.uv_estado_estudiante_grupo WHERE codigo = N'I');
DECLARE @destino NVARCHAR(10) = dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA');
DECLARE @g UNIQUEIDENTIFIER = NEWID(), @u1 UNIQUEIDENTIFIER = NEWID(), @u2 UNIQUEIDENTIFIER = NEWID();
DECLARE @e1 UNIQUEIDENTIFIER = NEWID(), @e2 UNIQUEIDENTIFIER = NEWID(), @eg1 UNIQUEIDENTIFIER = NEWID(), @eg2 UNIQUEIDENTIFIER = NEWID();
DECLARE @num INT = 1500000000 + ABS(CHECKSUM(NEWID()) % 90000000);
DECLARE @corr UNIQUEIDENTIFIER = NEWID(), @fallo NVARCHAR(4000) = NULL;
DECLARE @mu NVARCHAR(4000), @mt NVARCHAR(4000), @ok BIT, @reactivada BIT;
IF @base IS NULL OR @tipoCC IS NULL OR @estA IS NULL OR @estI IS NULL
    THROW 57130, 'TEST FAILED: T-12b fixture missing (semilla).', 1;

BEGIN TRY
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
        cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    SELECT @g, g.asignatura, g.periodoAcademico, 600000 + ABS(CHECKSUM(NEWID()) % 300000), N'Grupo QA CULM001A T12B', 5, 0, 0, 0, g.docente
    FROM dbo.Grupo g WHERE g.id = @base;
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@u1, @tipoCC, @num, N'Uno', N'T12b', N'Est', N'A', CONCAT(N'culm001a.t12b.1.', @num, N'@test.local'), 1, 1, N'HashBackend_T12b'),
           (@u2, @tipoCC, @num + 1, N'Dos', N'T12b', N'Est', N'A', CONCAT(N'culm001a.t12b.2.', @num, N'@test.local'), 1, 1, N'HashBackend_T12b');
    INSERT INTO dbo.Estudiante (id, usuario) VALUES (@e1, @u1), (@e2, @u2);
    INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo) VALUES (@eg1, @estI, @e1, @g);

    -- (1) @@TRANCOUNT = 0, caso feliz: misma fila I -> A, sale en 0.
    EXEC dbo.usp_internal_reactivar_matricula_retirada @idEstudiante = @e1, @idGrupo = @g, @idCorrelacion = @corr,
        @codigoEstadoDestino = @destino, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT,
        @estadoResultado = @ok OUTPUT, @reactivada = @reactivada OUTPUT;
    IF @@TRANCOUNT <> 0 SET @fallo = 'T-12b(1) con @@TRANCOUNT = 0 debe salir en 0.';
    ELSE IF @ok <> 1 OR @reactivada <> 1 OR NOT EXISTS (SELECT 1 FROM dbo.EstudianteGrupo WHERE id = @eg1 AND estado = @estA)
        SET @fallo = 'T-12b(1) debe reactivar la misma fila (A) con @reactivada = 1.';
    ELSE IF @mt NOT LIKE CONCAT(N'%Correlacion: ', @corr)
        SET @fallo = 'T-12b(1) el mensaje tecnico debe terminar con la correlacion.';

    -- (2) @@TRANCOUNT = 0, sin matricula retirada (E1 ya esta en A): @reactivada = 0, exito, sin escrituras.
    IF @fallo IS NULL
    BEGIN
        EXEC dbo.usp_internal_reactivar_matricula_retirada @idEstudiante = @e2, @idGrupo = @g, @idCorrelacion = @corr,
            @codigoEstadoDestino = @destino, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT,
            @estadoResultado = @ok OUTPUT, @reactivada = @reactivada OUTPUT;
        IF @@TRANCOUNT <> 0 OR @ok <> 1 OR @reactivada <> 0 OR EXISTS (SELECT 1 FROM dbo.EstudianteGrupo WHERE estudiante = @e2)
            SET @fallo = 'T-12b(2) sin matricula retirada: @reactivada = 0, exito y sin escrituras.';
    END

    -- (3) @@TRANCOUNT = 0, cupo lleno bajo bloqueo: E1 vuelve a I, E2 activo y capacidad 1 => ERR_CUPO_SUPERADO.
    IF @fallo IS NULL
    BEGIN
        UPDATE dbo.EstudianteGrupo SET estado = @estI WHERE id = @eg1;
        INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo) VALUES (@eg2, @estA, @e2, @g);
        UPDATE dbo.Grupo SET cantidadEstudiantes = 1 WHERE id = @g;
        EXEC dbo.usp_internal_reactivar_matricula_retirada @idEstudiante = @e1, @idGrupo = @g, @idCorrelacion = @corr,
            @codigoEstadoDestino = @destino, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT,
            @estadoResultado = @ok OUTPUT, @reactivada = @reactivada OUTPUT;
        IF @@TRANCOUNT <> 0 OR @ok <> 0 OR @reactivada <> 0 OR @mt NOT LIKE N'DBCODE=ERR[_]CUPO[_]SUPERADO|%'
           OR NOT EXISTS (SELECT 1 FROM dbo.EstudianteGrupo WHERE id = @eg1 AND estado = @estI)
            SET @fallo = 'T-12b(3) con cupo lleno debe rechazar con ERR_CUPO_SUPERADO, sin escrituras y salir en 0.';
    END

    -- (4) @@TRANCOUNT = 1: cupo lleno (sale en 1 y la transaccion sigue confirmable) y caso feliz (sale en 1).
    IF @fallo IS NULL
    BEGIN
        BEGIN TRANSACTION;
        EXEC dbo.usp_internal_reactivar_matricula_retirada @idEstudiante = @e1, @idGrupo = @g, @idCorrelacion = @corr,
            @codigoEstadoDestino = @destino, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT,
            @estadoResultado = @ok OUTPUT, @reactivada = @reactivada OUTPUT;
        IF @@TRANCOUNT <> 1 OR XACT_STATE() <> 1 OR @ok <> 0 OR @reactivada <> 0
            SET @fallo = 'T-12b(4) con @@TRANCOUNT = 1 y cupo lleno debe salir en 1, confirmable y con rechazo.';
        IF @fallo IS NULL
        BEGIN
            UPDATE dbo.Grupo SET cantidadEstudiantes = 5 WHERE id = @g;
            EXEC dbo.usp_internal_reactivar_matricula_retirada @idEstudiante = @e1, @idGrupo = @g, @idCorrelacion = @corr,
                @codigoEstadoDestino = @destino, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT,
                @estadoResultado = @ok OUTPUT, @reactivada = @reactivada OUTPUT;
            IF @@TRANCOUNT <> 1 OR @ok <> 1 OR @reactivada <> 1 OR NOT EXISTS (SELECT 1 FROM dbo.EstudianteGrupo WHERE id = @eg1 AND estado = @estA)
                SET @fallo = 'T-12b(4) con @@TRANCOUNT = 1 el caso feliz debe reactivar y salir en 1.';
        END
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    END

    -- (5) Codigo destino inexistente: GEN_001, sin escrituras.
    IF @fallo IS NULL
    BEGIN
        EXEC dbo.usp_internal_reactivar_matricula_retirada @idEstudiante = @e1, @idGrupo = @g, @idCorrelacion = @corr,
            @codigoEstadoDestino = N'ZZ', @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT,
            @estadoResultado = @ok OUTPUT, @reactivada = @reactivada OUTPUT;
        IF @@TRANCOUNT <> 0 OR @ok <> 0 OR @reactivada <> 0 OR @mt NOT LIKE N'DBCODE=GEN[_]001|%'
           OR NOT EXISTS (SELECT 1 FROM dbo.EstudianteGrupo WHERE id = @eg1 AND estado = @estI)
            SET @fallo = 'T-12b(5) un estado destino inexistente debe responder GEN_001 sin escrituras.';
    END
END TRY
BEGIN CATCH
    SET @fallo = CONCAT('T-12b error no controlado: ', ERROR_MESSAGE());
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
DELETE FROM dbo.EstudianteGrupo WHERE grupo = @g;
DELETE FROM dbo.Grupo WHERE id = @g;
DELETE FROM dbo.Estudiante WHERE id IN (@e1, @e2);
DELETE FROM dbo.Usuario WHERE id IN (@u1, @u2);
IF @fallo IS NOT NULL THROW 57131, @fallo, 1;
PRINT 'TEST_PASS:CULM001A_T12B_REACTIVAR_TRANCOUNT';
GO

-- ---------------------------------------------------------------------------
-- T-12c: usp_registrar_estudiante_en_grupo con un USUARIO NUEVO cuya matricula falla en el interno DESPUES de crear
-- Usuario/Estudiante => estadoResultado = 0 y 0 filas nuevas en Usuario, Estudiante, EstudiantePrograma y
-- EstudianteGrupo.
--   (a) @@TRANCOUNT = 0, error forzado con la CHECK temporal CK_CULM001A_TMP_EG sobre EstudianteGrupo: el SP es dueno de
--       la transaccion, la revierte toda y sale en 0.
--   (b) dentro de una transaccion del test (@@TRANCOUNT = 1), rechazo de negocio despues de escribir (un trigger temporal
--       sobre Estudiante deja el grupo sin cupo, ERR_CUPO_SUPERADO en el interno): el SP revierte su savepoint, sale en 1
--       y la transaccion del llamador sigue confirmable (XACT_STATE() = 1).
--   (c) dentro de una transaccion del test con la CHECK temporal: con XACT_ABORT ON un error vuelve la transaccion no
--       confirmable; el SP no la confirma ni la revierte (no es suya), sale en 1 con XACT_STATE() = -1 y el llamador
--       revierte (mismo criterio que T-12d, N12).
-- ---------------------------------------------------------------------------
SET NOCOUNT ON;
SET XACT_ABORT OFF;
IF OBJECT_ID(N'dbo.CK_CULM001A_TMP_EG', N'C') IS NOT NULL ALTER TABLE dbo.EstudianteGrupo DROP CONSTRAINT CK_CULM001A_TMP_EG;
IF OBJECT_ID(N'dbo.tr_culm001a_tmp_estudiante', N'TR') IS NOT NULL DROP TRIGGER dbo.tr_culm001a_tmp_estudiante;
DECLARE @base UNIQUEIDENTIFIER = (SELECT TOP 1 g.id FROM dbo.uv_grupo g WHERE g.grupoEstaHablitado = 1 ORDER BY g.id);
DECLARE @userTitular UNIQUEIDENTIFIER = (SELECT di.idUsuario FROM dbo.uv_grupo g INNER JOIN dbo.uv_docente_identidad di ON di.id = g.idDocente WHERE g.id = @base);
DECLARE @dominio NVARCHAR(255) = dbo.ufn_obtener_parametro('REGISTRO', 'DOMINIO_CORREO_ESTUDIANTE');
DECLARE @g UNIQUEIDENTIFIER = NEWID(), @corr UNIQUEIDENTIFIER = NEWID(), @fallo NVARCHAR(4000) = NULL, @sql NVARCHAR(MAX);
DECLARE @num INT = 1400000000 + ABS(CHECKSUM(NEWID()) % 90000000);
DECLARE @correo NVARCHAR(255) = CONCAT(N'culm001a.t12c.', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), @dominio);
DECLARE @usr INT, @est INT, @ep INT, @eg INT;
IF @base IS NULL OR @userTitular IS NULL OR @dominio = N'' THROW 57140, 'TEST FAILED: T-12c fixture missing (semilla).', 1;

INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
    cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
SELECT @g, g.asignatura, g.periodoAcademico, 600000 + ABS(CHECKSUM(NEWID()) % 300000), N'Grupo QA CULM001A T12C', 5, 0, 0, 0, g.docente
FROM dbo.Grupo g WHERE g.id = @base;
-- Precondicion: sin falla inyectada la misma llamada es exitosa (en una transaccion que se revierte).
CREATE TABLE #pre (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
BEGIN TRANSACTION;
INSERT INTO #pre EXEC dbo.usp_registrar_estudiante_en_grupo @idGrupo = @g, @numeroIdentificacion = @num,
    @primerNombre = N'Nuevo', @segundoNombre = N'T12c', @primerApellido = N'Culm', @segundoApellido = N'A',
    @correo = @correo, @password = N'HashBackend_T12c', @idCorrelacion = @corr, @idUsuarioEjecutor = @userTitular;
IF NOT EXISTS (SELECT 1 FROM #pre WHERE estadoResultado = 1) SET @fallo = 'T-12c precondicion: la llamada sin falla inyectada no fue exitosa.';
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
DROP TABLE #pre;

SELECT @usr = COUNT(*) FROM dbo.Usuario; SELECT @est = COUNT(*) FROM dbo.Estudiante;
SELECT @ep = COUNT(*) FROM dbo.EstudiantePrograma; SELECT @eg = COUNT(*) FROM dbo.EstudianteGrupo;
SET @sql = CONCAT(N'ALTER TABLE dbo.EstudianteGrupo WITH NOCHECK ADD CONSTRAINT CK_CULM001A_TMP_EG CHECK (grupo <> ''', CONVERT(NVARCHAR(36), @g), N''');');
EXEC sys.sp_executesql @sql;
BEGIN TRY
    IF @fallo IS NOT NULL THROW 57190, @fallo, 1;
    -- (a)
    EXEC dbo.usp_registrar_estudiante_en_grupo @idGrupo = @g, @numeroIdentificacion = @num,
        @primerNombre = N'Nuevo', @segundoNombre = N'T12c', @primerApellido = N'Culm', @segundoApellido = N'A',
        @correo = @correo, @password = N'HashBackend_T12c', @idCorrelacion = @corr, @idUsuarioEjecutor = @userTitular;
    IF @@TRANCOUNT <> 0 SET @fallo = 'T-12c(a) dejo una transaccion abierta.';
    ELSE IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo = LOWER(@correo))
         OR (SELECT COUNT(*) FROM dbo.Usuario) <> @usr OR (SELECT COUNT(*) FROM dbo.Estudiante) <> @est
         OR (SELECT COUNT(*) FROM dbo.EstudiantePrograma) <> @ep OR (SELECT COUNT(*) FROM dbo.EstudianteGrupo) <> @eg
        SET @fallo = 'T-12c(a) la falla del interno debe revertir Usuario, Estudiante, EstudiantePrograma y EstudianteGrupo.';

    -- (c) misma falla dentro de una transaccion del test.
    IF @fallo IS NULL
    BEGIN
        BEGIN TRANSACTION;
        EXEC dbo.usp_registrar_estudiante_en_grupo @idGrupo = @g, @numeroIdentificacion = @num,
            @primerNombre = N'Nuevo', @segundoNombre = N'T12c', @primerApellido = N'Culm', @segundoApellido = N'A',
            @correo = @correo, @password = N'HashBackend_T12c', @idCorrelacion = @corr, @idUsuarioEjecutor = @userTitular;
        IF @@TRANCOUNT <> 1 OR XACT_STATE() <> -1
            SET @fallo = CONCAT('T-12c(c) con transaccion del llamador debe salir en 1 y no confirmable; trancount=', @@TRANCOUNT, ' xact=', XACT_STATE());
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF @fallo IS NULL AND (EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo = LOWER(@correo)) OR (SELECT COUNT(*) FROM dbo.Usuario) <> @usr)
            SET @fallo = 'T-12c(c) quedo un Usuario despues de revertir.';
    END
END TRY
BEGIN CATCH
    SET @fallo = CONCAT('T-12c error no controlado: ', ERROR_MESSAGE());
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
IF OBJECT_ID(N'dbo.CK_CULM001A_TMP_EG', N'C') IS NOT NULL ALTER TABLE dbo.EstudianteGrupo DROP CONSTRAINT CK_CULM001A_TMP_EG;

-- (b) rechazo de negocio despues de escribir, dentro de la transaccion del test.
BEGIN TRY
    IF @fallo IS NULL
    BEGIN
        BEGIN TRANSACTION;
        SET @sql = CONCAT(N'CREATE TRIGGER dbo.tr_culm001a_tmp_estudiante ON dbo.Estudiante AFTER INSERT AS BEGIN SET NOCOUNT ON; ',
                          N'UPDATE dbo.Grupo SET cantidadEstudiantes = 0 WHERE id = ''', CONVERT(NVARCHAR(36), @g), N'''; END;');
        EXEC sys.sp_executesql @sql;
        EXEC dbo.usp_registrar_estudiante_en_grupo @idGrupo = @g, @numeroIdentificacion = @num,
            @primerNombre = N'Nuevo', @segundoNombre = N'T12c', @primerApellido = N'Culm', @segundoApellido = N'A',
            @correo = @correo, @password = N'HashBackend_T12c', @idCorrelacion = @corr, @idUsuarioEjecutor = @userTitular;
        IF @@TRANCOUNT <> 1 OR XACT_STATE() <> 1
            SET @fallo = CONCAT('T-12c(b) debe salir en 1 y confirmable; trancount=', @@TRANCOUNT, ' xact=', XACT_STATE());
        ELSE IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo = LOWER(@correo))
             OR (SELECT COUNT(*) FROM dbo.Usuario) <> @usr OR (SELECT COUNT(*) FROM dbo.Estudiante) <> @est
             OR (SELECT COUNT(*) FROM dbo.EstudiantePrograma) <> @ep OR (SELECT COUNT(*) FROM dbo.EstudianteGrupo) <> @eg
            SET @fallo = 'T-12c(b) el savepoint de negocio debe revertir Usuario, Estudiante y matricula.';
        ELSE IF (SELECT cantidadEstudiantes FROM dbo.Grupo WHERE id = @g) <> 5
            SET @fallo = 'T-12c(b) el savepoint de negocio debe revertir tambien lo escrito despues de el.';
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    END
END TRY
BEGIN CATCH
    SET @fallo = CONCAT('T-12c(b) error no controlado: ', ERROR_MESSAGE());
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
IF OBJECT_ID(N'dbo.tr_culm001a_tmp_estudiante', N'TR') IS NOT NULL DROP TRIGGER dbo.tr_culm001a_tmp_estudiante;
DELETE FROM dbo.EstudianteGrupo WHERE grupo = @g;
DELETE FROM dbo.Grupo WHERE id = @g;
DELETE e FROM dbo.Estudiante e INNER JOIN dbo.Usuario u ON u.id = e.usuario WHERE u.correo = LOWER(@correo);
DELETE FROM dbo.Usuario WHERE correo = LOWER(@correo);
IF @fallo IS NOT NULL THROW 57141, @fallo, 1;
PRINT 'TEST_PASS:CULM001A_T12C_MATRICULA_MANUAL_ATOMICA';
GO

-- ---------------------------------------------------------------------------
-- T-12d: error forzado DENTRO del SP de reactivacion bajo el QR, con transaccion externa del test: el error no se
-- relanza al llamador (el CATCH del interno lo convierte en estadoResultado = 0), pero la transaccion del llamador
-- vuelve no confirmable (XACT_STATE() = -1) y la revierte el test. Nada persiste.
-- ---------------------------------------------------------------------------
SET NOCOUNT ON;
SET XACT_ABORT OFF;
DECLARE @grupo UNIQUEIDENTIFIER, @userTitular UNIQUEIDENTIFIER;
SELECT TOP 1 @grupo = g.id, @userTitular = di.idUsuario
FROM dbo.uv_grupo g INNER JOIN dbo.uv_docente_identidad di ON di.id = g.idDocente
WHERE g.grupoEstaHablitado = 1 AND g.cuposDisponibles > 1 ORDER BY g.cuposDisponibles DESC, g.id;
DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoIdentificacion ORDER BY id);
DECLARE @estA UNIQUEIDENTIFIER = (SELECT id FROM dbo.uv_estado_estudiante_grupo WHERE codigo = N'A');
DECLARE @estI UNIQUEIDENTIFIER = (SELECT id FROM dbo.uv_estado_estudiante_grupo WHERE codigo = N'I');
DECLARE @estadoActiva NVARCHAR(10) = dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_ACTIVA');
DECLARE @estadoCerrada NVARCHAR(10) = dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_CERRADA');
DECLARE @u UNIQUEIDENTIFIER = NEWID(), @e UNIQUEIDENTIFIER = NEWID(), @eg UNIQUEIDENTIFIER = NEWID();
DECLARE @num INT = 1300000000 + ABS(CHECKSUM(NEWID()) % 90000000);
DECLARE @corr UNIQUEIDENTIFIER = NEWID(), @fallo NVARCHAR(4000) = NULL, @sql NVARCHAR(MAX), @idV UNIQUEIDENTIFIER;
DECLARE @tok NVARCHAR(100) = CONCAT(N'tok-t12d-', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''));
DECLARE @hash VARBINARY(32) = HASHBYTES('SHA2_256', @tok);
DECLARE @pin NCHAR(6) = RIGHT(CONCAT('000000', CAST(ABS(CHECKSUM(NEWID())) % 1000000 AS VARCHAR(6))), 6);
IF @grupo IS NULL OR @userTitular IS NULL OR @tipoCC IS NULL OR @estA IS NULL OR @estI IS NULL
    THROW 57150, 'TEST FAILED: T-12d fixture missing (semilla).', 1;
CREATE TABLE #v (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(MAX), mensajeTecnicoResultado NVARCHAR(MAX), estadoResultado BIT,
    idVentana UNIQUEIDENTIFIER, fechaExpiracionUtc DATETIME2(0));

BEGIN TRANSACTION;
BEGIN TRY
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@u, @tipoCC, @num, N'Uno', N'T12d', N'Est', N'A', CONCAT(N'culm001a.t12d.', @num, N'@test.local'), 1, 1, N'HashBackend_T12d');
    INSERT INTO dbo.Estudiante (id, usuario) VALUES (@e, @u);
    INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo) VALUES (@eg, @estI, @e, @grupo);
    UPDATE dbo.TokenMatriculaGrupo SET estado = @estadoCerrada WHERE grupo = @grupo AND estado = @estadoActiva;
    INSERT INTO #v EXEC dbo.usp_abrir_ventana_matricula_grupo @idGrupo = @grupo, @tokenHash = @hash, @pin = @pin,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @userTitular;
    SELECT @idV = idVentana FROM #v WHERE estadoResultado = 1;
    IF @idV IS NULL THROW 57151, 'TEST FAILED: T-12d no se pudo abrir la ventana QR.', 1;
    -- La reactivacion de @eg (I -> A) viola la CHECK temporal: el error ocurre dentro del SP nuevo.
    SET @sql = CONCAT(N'ALTER TABLE dbo.EstudianteGrupo WITH NOCHECK ADD CONSTRAINT CK_CULM001A_TMP_EG_QR CHECK (id <> ''',
                      CONVERT(NVARCHAR(36), @eg), N''' OR estado <> ''', CONVERT(NVARCHAR(36), @estA), N''');');
    EXEC sys.sp_executesql @sql;
    EXEC dbo.usp_matricular_estudiante_por_token @tokenHash = NULL, @pin = @pin, @idUsuarioEjecutor = @u, @idCorrelacion = @corr;
    IF @@TRANCOUNT <> 1 OR XACT_STATE() <> -1
        SET @fallo = CONCAT('T-12d el llamador debe recibir su transaccion no confirmable; trancount=', @@TRANCOUNT, ' xact=', XACT_STATE());
END TRY
BEGIN CATCH
    SET @fallo = CONCAT('T-12d el error no debe propagarse al llamador: ', ERROR_MESSAGE());
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
DROP TABLE IF EXISTS #v;
IF @fallo IS NULL AND (OBJECT_ID(N'dbo.CK_CULM001A_TMP_EG_QR', N'C') IS NOT NULL OR EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @u)
    OR EXISTS (SELECT 1 FROM dbo.EstudianteGrupo WHERE id = @eg))
    SET @fallo = 'T-12d nada debe persistir despues del ROLLBACK del llamador.';
IF @fallo IS NOT NULL THROW 57152, @fallo, 1;
PRINT 'TEST_PASS:CULM001A_T12D_QR_TRANSACCION_EXTERNA';
PRINT 'TEST_PASS:CULM001A_T12_TRANCOUNT';
GO

IF @@TRANCOUNT <> 0 THROW 57159, 'TEST FAILED: test_culm001_a_retiro_solicitudes dejo transacciones abiertas.', 1;
PRINT 'TEST END: test_culm001_a_retiro_solicitudes';
GO
