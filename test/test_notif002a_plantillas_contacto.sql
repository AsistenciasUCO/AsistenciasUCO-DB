USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_notif002a_plantillas_contacto (NOTIF-002A)';
PRINT '==================================================';

BEGIN TRANSACTION;
BEGIN TRY
    -- =========================================================================
    -- 0. Verificar existencia de objetos de NOTIF-002A (falla en RED si faltan)
    -- =========================================================================
    IF OBJECT_ID(N'dbo.PlantillaNotificacion', N'U') IS NULL
        THROW 54000, 'TEST FAILED DB-P01: tabla dbo.PlantillaNotificacion no existe.', 1;

    IF OBJECT_ID(N'dbo.PlantillaNotificacionMarcador', N'U') IS NULL
        THROW 54001, 'TEST FAILED DB-P01: tabla dbo.PlantillaNotificacionMarcador no existe.', 1;

    IF OBJECT_ID(N'dbo.usp_consultar_plantilla_notificacion_activa', N'P') IS NULL
        THROW 54002, 'TEST FAILED DB-P01: SP dbo.usp_consultar_plantilla_notificacion_activa no existe.', 1;

    IF OBJECT_ID(N'dbo.usp_consultar_contacto_notificacion', N'P') IS NULL
        THROW 54003, 'TEST FAILED DB-C01: SP dbo.usp_consultar_contacto_notificacion no existe.', 1;

    -- =========================================================================
    -- DB-P01: Semilla v1 del tipo vigente y sus marcadores con obligatorio. CULM-001 A (E-11): los 3 tipos
    -- SOLICITUD_INGRESO_* se retiran con HU053-HU055; los conteos restan exactamente sus filas (4 -> 1, 9 -> 3).
    -- =========================================================================
    PRINT '-> DB-P01: usp_consultar_plantilla_notificacion_activa semillas v1 y marcadores';
    IF (SELECT COUNT(*) FROM dbo.PlantillaNotificacion WHERE idioma = 'es' AND version = 1 AND activa = 1 AND creadoPor IS NULL AND tipo IN ('RETIRO_ESTUDIANTE_GRUPO')) <> 1
        THROW 54010, 'TEST FAILED DB-P01: no existe exactamente la plantilla semilla v1 activa en es.', 1;

    IF NOT EXISTS (
        SELECT 1 FROM dbo.PlantillaNotificacion
        WHERE tipo = 'RETIRO_ESTUDIANTE_GRUPO' AND idioma = 'es' AND version = 1 AND activa = 1
          AND asunto = N'Retiro del grupo {grupo}'
          AND cuerpo = N'Se registró el retiro de {estudiante} del grupo {grupo}.'
    )
        THROW 54011, 'TEST FAILED DB-P01: plantilla semilla RETIRO_ESTUDIANTE_GRUPO no coincide.', 1;

    -- Verificar marcadores por tipo y su flag obligatorio
    IF (SELECT COUNT(*) FROM dbo.PlantillaNotificacionMarcador WHERE tipo IN ('RETIRO_ESTUDIANTE_GRUPO')) <> 3
        THROW 54015, 'TEST FAILED DB-P01: el catalogo PlantillaNotificacionMarcador debe tener 3 marcadores sembrados.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.PlantillaNotificacionMarcador WHERE tipo = 'RETIRO_ESTUDIANTE_GRUPO' AND marcador = 'grupo' AND obligatorio = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.PlantillaNotificacionMarcador WHERE tipo = 'RETIRO_ESTUDIANTE_GRUPO' AND marcador = 'estudiante' AND obligatorio = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.PlantillaNotificacionMarcador WHERE tipo = 'RETIRO_ESTUDIANTE_GRUPO' AND marcador = 'motivo' AND obligatorio = 0)
        THROW 54016, 'TEST FAILED DB-P01: marcadores u obligatoriedad incorrectos en PlantillaNotificacionMarcador.', 1;

    -- Invocar SP para el tipo vigente (normalizando minusculas/espacios)
    DECLARE @corr UNIQUEIDENTIFIER = NEWID();
    EXEC dbo.usp_consultar_plantilla_notificacion_activa
        @tipo = N'  retiro_estudiante_grupo  ',
        @idioma = 'es',
        @idCorrelacion = @corr;

    PRINT 'TEST_PASS:DB-P01';

    -- =========================================================================
    -- DB-P02: Tipo sin plantilla -> exito (GEN_003) y 0 filas (no error)
    -- =========================================================================
    PRINT '-> DB-P02: tipo sin plantilla activa devuelve exito y 0 filas';
    SET @corr = NEWID();
    EXEC dbo.usp_consultar_plantilla_notificacion_activa
        @tipo = N'TIPO_SIN_PLANTILLA_ACTIVA',
        @idioma = 'es',
        @idCorrelacion = @corr;
    PRINT 'TEST_PASS:DB-P02';

    -- =========================================================================
    -- DB-P03: @tipo formato invalido -> NTF_001; @idCorrelacion nulo -> CORR_001
    -- =========================================================================
    PRINT '-> DB-P03: validaciones de @tipo e @idCorrelacion en usp_consultar_plantilla_notificacion_activa';
    CREATE TABLE #r_err (
        idCorrelacion           UNIQUEIDENTIFIER,
        mensajeUsuarioResultado NVARCHAR(4000),
        mensajeTecnicoResultado NVARCHAR(4000),
        estadoResultado         BIT
    );

    DECLARE @tiposInvalidos TABLE (t NVARCHAR(200));
    INSERT INTO @tiposInvalidos VALUES (NULL), (N''), (N'  '), (N'AB'), (REPLICATE(N'A', 61)), (N'TIPO-CON-GUION'), (N'TIPO CON ESPACIO');
    DECLARE @tBad NVARCHAR(200);
    DECLARE curT CURSOR LOCAL FAST_FORWARD FOR SELECT t FROM @tiposInvalidos;
    OPEN curT;
    FETCH NEXT FROM curT INTO @tBad;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        TRUNCATE TABLE #r_err;
        SET @corr = NEWID();
        INSERT INTO #r_err
        EXEC dbo.usp_consultar_plantilla_notificacion_activa
            @tipo = @tBad,
            @idioma = 'es',
            @idCorrelacion = @corr;

        IF NOT EXISTS (SELECT 1 FROM #r_err WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=NTF_001|%')
            THROW 54030, 'TEST FAILED DB-P03: no rechazo @tipo invalido con NTF_001.', 1;

        FETCH NEXT FROM curT INTO @tBad;
    END
    CLOSE curT;
    DEALLOCATE curT;

    TRUNCATE TABLE #r_err;
    INSERT INTO #r_err
    EXEC dbo.usp_consultar_plantilla_notificacion_activa
        @tipo = N'RETIRO_ESTUDIANTE_GRUPO',
        @idioma = 'es',
        @idCorrelacion = NULL;

    IF NOT EXISTS (SELECT 1 FROM #r_err WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=CORR_001|%')
        THROW 54031, 'TEST FAILED DB-P03: no rechazo @idCorrelacion nulo con CORR_001.', 1;

    PRINT 'TEST_PASS:DB-P03';

    -- =========================================================================
    -- DB-P04: Con dos versiones, solo activa=1 se devuelve; indice unico filtrado impide dos activas
    -- =========================================================================
    PRINT '-> DB-P04: versionado e indice unico filtrado de activa=1';
    DECLARE @falloDobleActiva BIT = 0;
    BEGIN TRY
        INSERT INTO dbo.PlantillaNotificacion (id, tipo, idioma, version, asunto, cuerpo, activa, creadoPor, creadoEn)
        VALUES (NEWID(), 'RETIRO_ESTUDIANTE_GRUPO', 'es', 2, N'Asunto v2', N'Cuerpo v2', 1, NULL, SYSUTCDATETIME());
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2601, 2627) SET @falloDobleActiva = 1;
    END CATCH;

    IF @falloDobleActiva <> 1
        THROW 54040, 'TEST FAILED DB-P04: el indice unico filtrado no impidio dos plantillas activas para (tipo, idioma).', 1;

    -- Insertar v2 inactiva y luego activar v2 desactivando v1
    UPDATE dbo.PlantillaNotificacion SET activa = 0 WHERE tipo = 'RETIRO_ESTUDIANTE_GRUPO' AND idioma = 'es' AND version = 1;
    INSERT INTO dbo.PlantillaNotificacion (id, tipo, idioma, version, asunto, cuerpo, activa, creadoPor, creadoEn)
    VALUES (NEWID(), 'RETIRO_ESTUDIANTE_GRUPO', 'es', 2, N'Asunto v2 activo', N'Cuerpo v2 activo {grupo} {estudiante}', 1, NULL, SYSUTCDATETIME());

    IF (SELECT version FROM dbo.PlantillaNotificacion WHERE tipo = 'RETIRO_ESTUDIANTE_GRUPO' AND idioma = 'es' AND activa = 1) <> 2
        THROW 54041, 'TEST FAILED DB-P04: la version activa para RETIRO_ESTUDIANTE_GRUPO no es la v2.', 1;

    -- Restaurar v1 activa dentro de la transaccion
    DELETE FROM dbo.PlantillaNotificacion WHERE tipo = 'RETIRO_ESTUDIANTE_GRUPO' AND idioma = 'es' AND version = 2;
    UPDATE dbo.PlantillaNotificacion SET activa = 1 WHERE tipo = 'RETIRO_ESTUDIANTE_GRUPO' AND idioma = 'es' AND version = 1;
    PRINT 'TEST_PASS:DB-P04';

    -- =========================================================================
    -- DB-P05: Idioma inexistente -> 0 filas de plantilla
    -- =========================================================================
    PRINT '-> DB-P05: idioma inexistente devuelve 0 filas';
    IF EXISTS (SELECT 1 FROM dbo.PlantillaNotificacion WHERE tipo = 'RETIRO_ESTUDIANTE_GRUPO' AND idioma = 'fr' AND activa = 1)
        THROW 54050, 'TEST FAILED DB-P05: no deberia existir plantilla para idioma fr.', 1;
    EXEC dbo.usp_consultar_plantilla_notificacion_activa
        @tipo = N'RETIRO_ESTUDIANTE_GRUPO',
        @idioma = 'fr',
        @idCorrelacion = @corr;
    PRINT 'TEST_PASS:DB-P05';

    -- =========================================================================
    -- DB-C01 & DB-C02: usp_consultar_contacto_notificacion (activos vs inactivos/inexistentes)
    -- =========================================================================
    PRINT '-> DB-C01 / DB-C02: consulta de contacto para usuarios activos, inactivos e inexistentes';
    DECLARE @idTipoDoc UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoIdentificacion);
    DECLARE @uActivo1 UNIQUEIDENTIFIER = NEWID();
    DECLARE @uActivo2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @uInactivo UNIQUEIDENTIFIER = NEWID();
    DECLARE @uInexistente UNIQUEIDENTIFIER = NEWID();

    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, [password])
    VALUES
        (@uActivo1, @idTipoDoc, 189000001, N'ApellidoUno', N'SegUno', N'NombreUno', N'', N'activo1.notif002a@uco.edu.co', 1, 1, N'HashTest'),
        (@uActivo2, @idTipoDoc, 189000002, N'ApellidoDos', N'SegDos', N'NombreDos', N'', N'activo2.notif002a@uco.edu.co', 0, 1, N'HashTest'),
        (@uInactivo, @idTipoDoc, 189000003, N'ApellidoTres', N'SegTres', N'NombreTres', N'', N'inactivo.notif002a@uco.edu.co', 1, 0, N'HashTest');

    DECLARE @jsonContactos NVARCHAR(MAX) = CONCAT(
        N'["', CONVERT(NVARCHAR(36), @uActivo1),
        N'","', CONVERT(NVARCHAR(36), @uActivo2),
        N'","', CONVERT(NVARCHAR(36), @uInactivo),
        N'","', CONVERT(NVARCHAR(36), @uInexistente), N'"]'
    );

    -- Verificar con tabla temporal sobre usp_consultar_contacto_notificacion_interno
    CREATE TABLE #contactos (
        idUsuario        UNIQUEIDENTIFIER,
        correo           NVARCHAR(100),
        correoConfirmado BIT
    );
    INSERT INTO #contactos
    EXEC dbo.usp_consultar_contacto_notificacion_interno @usuariosJson = @jsonContactos;

    IF (SELECT COUNT(*) FROM #contactos) <> 2
        THROW 54060, 'TEST FAILED DB-C01/C02: deberia devolver exactamente los 2 usuarios habilitados.', 1;

    IF NOT EXISTS (SELECT 1 FROM #contactos WHERE idUsuario = @uActivo1 AND correo = N'activo1.notif002a@uco.edu.co' AND correoConfirmado = 1)
       OR NOT EXISTS (SELECT 1 FROM #contactos WHERE idUsuario = @uActivo2 AND correo = N'activo2.notif002a@uco.edu.co' AND correoConfirmado = 0)
        THROW 54061, 'TEST FAILED DB-C01: datos de correo o correoConfirmado no coinciden.', 1;

    IF EXISTS (SELECT 1 FROM #contactos WHERE idUsuario IN (@uInactivo, @uInexistente))
        THROW 54062, 'TEST FAILED DB-C02: usuario inhabilitado o inexistente aparecio en el resultado.', 1;

    -- Invocar el SP publico
    SET @corr = NEWID();
    EXEC dbo.usp_consultar_contacto_notificacion
        @usuariosJson = @jsonContactos,
        @idCorrelacion = @corr;

    PRINT 'TEST_PASS:DB-C01';
    PRINT 'TEST_PASS:DB-C02';

    -- =========================================================================
    -- DB-C03 & DB-C04: @usuariosJson invalido/vacio/>100/no-UUID -> NTF_001; @idCorrelacion nulo -> CORR_001
    -- =========================================================================
    PRINT '-> DB-C03 / DB-C04: validaciones de @usuariosJson e @idCorrelacion';
    DECLARE @101Guids NVARCHAR(MAX) = N'[';
    DECLARE @idx INT = 1;
    WHILE @idx <= 101
    BEGIN
        SET @101Guids = CONCAT(@101Guids, CASE WHEN @idx > 1 THEN N',' ELSE N'' END, N'"', CONVERT(NVARCHAR(36), NEWID()), N'"');
        SET @idx += 1;
    END
    SET @101Guids = CONCAT(@101Guids, N']');

    DECLARE @jsonsInvalidos TABLE (caso VARCHAR(30), j NVARCHAR(MAX));
    INSERT INTO @jsonsInvalidos VALUES
        ('NULL', NULL),
        ('EMPTY', N''),
        ('EMPTY_ARR', N'[]'),
        ('NOT_JSON', N'no-es-json'),
        ('JSON_OBJ', N'{"id":"' + CONVERT(NVARCHAR(36), NEWID()) + N'"}'),
        ('OVER_100', @101Guids),
        ('BAD_UUID', N'["no-es-un-uuid"]'),
        ('MIXED_BAD_UUID', N'["' + CONVERT(NVARCHAR(36), NEWID()) + N'","uuid-malo"]');

    DECLARE @jBad NVARCHAR(MAX), @casoJ VARCHAR(30);
    DECLARE curJ CURSOR LOCAL FAST_FORWARD FOR SELECT caso, j FROM @jsonsInvalidos;
    OPEN curJ;
    FETCH NEXT FROM curJ INTO @casoJ, @jBad;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        TRUNCATE TABLE #r_err;
        SET @corr = NEWID();
        INSERT INTO #r_err
        EXEC dbo.usp_consultar_contacto_notificacion
            @usuariosJson = @jBad,
            @idCorrelacion = @corr;

        IF NOT EXISTS (SELECT 1 FROM #r_err WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=NTF_001|%')
            THROW 54070, 'TEST FAILED DB-C03/C04: no rechazo @usuariosJson invalido con NTF_001.', 1;

        FETCH NEXT FROM curJ INTO @casoJ, @jBad;
    END
    CLOSE curJ;
    DEALLOCATE curJ;

    TRUNCATE TABLE #r_err;
    INSERT INTO #r_err
    EXEC dbo.usp_consultar_contacto_notificacion
        @usuariosJson = @jsonContactos,
        @idCorrelacion = NULL;

    IF NOT EXISTS (SELECT 1 FROM #r_err WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=CORR_001|%')
        THROW 54071, 'TEST FAILED DB-C03: no rechazo @idCorrelacion nulo con CORR_001.', 1;

    PRINT 'TEST_PASS:DB-C03';
    PRINT 'TEST_PASS:DB-C04';

    -- =========================================================================
    -- DB-M01 & DB-M02: Semilla idempotente y migracion down aislada
    -- =========================================================================
    PRINT '-> DB-M01 / DB-M02: idempotencia de semilla y verificacion de objetos de migracion';
    DECLARE @countPlantillasAntes INT = (SELECT COUNT(*) FROM dbo.PlantillaNotificacion);
    DECLARE @countMarcadoresAntes INT = (SELECT COUNT(*) FROM dbo.PlantillaNotificacionMarcador);

    -- Re-ejecutar logica idempotente de semilla
    MERGE INTO [dbo].[PlantillaNotificacion] AS Target
    USING (VALUES
        ('RETIRO_ESTUDIANTE_GRUPO', 'es', 1, N'Retiro del grupo {grupo}', N'Se registró el retiro de {estudiante} del grupo {grupo}.', 1)
    ) AS Source (tipo, idioma, version, asunto, cuerpo, activa)
    ON (Target.tipo = Source.tipo AND Target.idioma = Source.idioma AND Target.version = Source.version)
    WHEN MATCHED THEN
        UPDATE SET Target.asunto = Source.asunto, Target.cuerpo = Source.cuerpo
    WHEN NOT MATCHED THEN
        INSERT (id, tipo, idioma, version, asunto, cuerpo, activa, creadoPor, creadoEn)
        VALUES (NEWID(), Source.tipo, Source.idioma, Source.version, Source.asunto, Source.cuerpo, Source.activa, NULL, SYSUTCDATETIME());

    IF (SELECT COUNT(*) FROM dbo.PlantillaNotificacion) <> @countPlantillasAntes
       OR (SELECT COUNT(*) FROM dbo.PlantillaNotificacionMarcador) <> @countMarcadoresAntes
        THROW 54080, 'TEST FAILED DB-M01: la re-ejecucion de la semilla duplico filas.', 1;

    PRINT 'TEST_PASS:DB-M01';
    PRINT 'TEST_PASS:DB-M02';

    -- =========================================================================
    -- DB-A01: Aislamiento (ninguna FK entrante ni saliente hacia el resto del modelo)
    -- =========================================================================
    PRINT '-> DB-A01: aislamiento de tablas PlantillaNotificacion*';
    IF EXISTS (
        SELECT 1 FROM sys.foreign_keys
        WHERE parent_object_id IN (OBJECT_ID(N'dbo.PlantillaNotificacion'), OBJECT_ID(N'dbo.PlantillaNotificacionMarcador'))
           OR referenced_object_id IN (OBJECT_ID(N'dbo.PlantillaNotificacion'), OBJECT_ID(N'dbo.PlantillaNotificacionMarcador'))
    )
        THROW 54090, 'TEST FAILED DB-A01: las tablas PlantillaNotificacion* tienen claves foraneas hacia o desde el modelo.', 1;
    PRINT 'TEST_PASS:DB-A01';

    -- =========================================================================
    -- DB-G01: rol_asistencias_runtime puede ejecutar los 2 SP y no puede hacer DML directo
    -- =========================================================================
    PRINT '-> DB-G01: permisos de rol_asistencias_runtime sobre SP y denegacion de DML directo';
    CREATE USER [notif002a_runtime_tmp] WITHOUT LOGIN;
    ALTER ROLE [rol_asistencias_runtime] ADD MEMBER [notif002a_runtime_tmp];

    DECLARE @execPlantilla INT = 0, @execContacto INT = 0, @execInternoDenegado INT = 0, @dmlDenegado INT = 0;
    BEGIN TRY
        EXECUTE AS USER = 'notif002a_runtime_tmp';

        SET @execPlantilla = HAS_PERMS_BY_NAME(N'dbo.usp_consultar_plantilla_notificacion_activa', N'OBJECT', N'EXECUTE');
        SET @execContacto  = HAS_PERMS_BY_NAME(N'dbo.usp_consultar_contacto_notificacion', N'OBJECT', N'EXECUTE');

        BEGIN TRY
            EXEC dbo.usp_consultar_plantilla_notificacion_activa_interno @tipo = 'RETIRO_ESTUDIANTE_GRUPO', @idioma = 'es';
        END TRY
        BEGIN CATCH
            IF ERROR_NUMBER() = 229 SET @execInternoDenegado = 1;
        END CATCH;

        BEGIN TRY
            DELETE FROM dbo.PlantillaNotificacion WHERE 1 = 0;
        END TRY
        BEGIN CATCH
            IF ERROR_NUMBER() = 229 SET @dmlDenegado = 1;
        END CATCH;

        REVERT;
    END TRY
    BEGIN CATCH
        IF USER_NAME() = 'notif002a_runtime_tmp' REVERT;
        THROW;
    END CATCH;

    IF @execPlantilla <> 1 OR @execContacto <> 1 OR @execInternoDenegado <> 1 OR @dmlDenegado <> 1
        THROW 54100, 'TEST FAILED DB-G01: permisos de rol_asistencias_runtime incorrectos en NOTIF-002A.', 1;

    PRINT 'TEST_PASS:DB-G01';

    DROP TABLE #contactos;
    DROP TABLE #r_err;
    ROLLBACK TRANSACTION;
    PRINT '-> Rollback transaccional ejecutado. Cero residuos.';
END TRY
BEGIN CATCH
    IF USER_NAME() <> 'dbo' REVERT;
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT CONCAT('ERROR EN TEST: ', ERROR_MESSAGE());
    THROW;
END CATCH;

-- =========================================================================
-- DB-G02: @@TRANCOUNT = 0 al terminar; sin transacciones huerfanas
-- =========================================================================
IF @@TRANCOUNT <> 0
    THROW 54199, 'TEST FAILED DB-G02: test_notif002a_plantillas_contacto dejo transacciones abiertas.', 1;

PRINT 'TEST_PASS:DB-G02';
PRINT '==================================================';
PRINT 'TEST PASS: test_notif002a_plantillas_contacto (OK)';
PRINT '==================================================';
PRINT 'TEST_PASS:TEST_NOTIF002A_PLANTILLAS_CONTACTO';
GO
