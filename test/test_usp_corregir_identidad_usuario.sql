USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- HU159 (decision de John 2026-11-05): correccion de los datos de identidad por jerarquia.
--   * usp_corregir_identidad_usuario: ESTUDIANTE (coordinador de su programa) y DECANO (administrador), motivo siempre.
--   * usp_actualizar_coordinador (HU121) y usp_actualizar_docente_programa (HU092): documento opcional, motivo solo si
--     cambia el documento.
--   * IDENTIDAD.PERMITIR_CORREGIR_DOCUMENTO = 0: el documento se rechaza (IDE_003) y los nombres siguen funcionando.
-- Todo dentro de una transaccion revertida.
PRINT 'TEST START: test_usp_corregir_identidad_usuario';

DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @tipoOtro UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE id <> @tipoCC ORDER BY tipoIdentificacion);
DECLARE @idPrograma UNIQUEIDENTIFIER, @uCoord UNIQUEIDENTIFIER, @idFacultad UNIQUEIDENTIFIER, @idCoordinador UNIQUEIDENTIFIER;
SELECT TOP 1 @idPrograma = p.id, @uCoord = ci.idUsuario, @idFacultad = p.idFacultad, @idCoordinador = ci.id
FROM dbo.uv_programa p
INNER JOIN dbo.uv_coordinador_identidad ci ON ci.id = p.idCoordinador
WHERE ci.estaActivoUsuario = 1
ORDER BY p.id;
DECLARE @idDecano UNIQUEIDENTIFIER, @uDecano UNIQUEIDENTIFIER, @idInstitucion UNIQUEIDENTIFIER;
SELECT @idDecano = d.id, @uDecano = d.idUsuario, @idInstitucion = f.idInstitucion
FROM dbo.uv_facultad f INNER JOIN dbo.uv_decano d ON d.id = f.idDecano
WHERE f.id = @idFacultad;
DECLARE @uAdmin UNIQUEIDENTIFIER = (SELECT TOP 1 a.idUsuario FROM dbo.uv_administrador a WHERE a.idInstitucion = @idInstitucion ORDER BY a.id);
IF @tipoCC IS NULL OR @tipoOtro IS NULL OR @idPrograma IS NULL OR @uCoord IS NULL OR @uDecano IS NULL OR @uAdmin IS NULL
    THROW 56300, 'TEST FAILED: faltan fixtures del seed (tipos de documento, programa con coordinador, decano y administrador).', 1;

BEGIN TRANSACTION;
BEGIN TRY
    CREATE TABLE #r (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000),
                     estadoResultado BIT, idUsuario UNIQUEIDENTIFIER, correo NVARCHAR(100), numeroIdentificacion INT);
    CREATE TABLE #c (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000),
                     estadoResultado BIT, idUsuario UNIQUEIDENTIFIER);
    CREATE TABLE #d (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000),
                     estadoResultado BIT);
    DECLARE @mu NVARCHAR(4000), @mt NVARCHAR(4000), @ok BIT;
    DECLARE @corr UNIQUEIDENTIFIER = NEWID();

    -- Fixtures: E1 del programa del coordinador, E2 sin vinculo con el programa (p. ej. solo en un grupo BAS/INS)
    -- y D1 docente vinculado al programa.
    EXEC dbo.usp_sincronizar_usuario_interno @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 915900001,
        @primerApellido = N'Gomes', @segundoApellido = N'Ruis', @primerNombre = N'Ana', @segundoNombre = N'',
        @correo = N'est1.qa159@test.local', @password = N'HashBackend_QaIde1234567890', @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 THROW 56301, 'TEST FAILED: no se pudo crear el usuario del estudiante E1.', 1;
    EXEC dbo.usp_sincronizar_usuario_interno @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 915900002,
        @primerApellido = N'Otro', @segundoApellido = N'Programa', @primerNombre = N'Luis', @segundoNombre = N'',
        @correo = N'est2.qa159@test.local', @password = N'HashBackend_QaIde1234567890', @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 THROW 56302, 'TEST FAILED: no se pudo crear el usuario del estudiante E2.', 1;
    EXEC dbo.usp_sincronizar_usuario_interno @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 915900003,
        @primerApellido = N'Docente', @segundoApellido = N'Qa', @primerNombre = N'Pedro', @segundoNombre = N'',
        @correo = N'doc1.qa159@test.local', @password = N'HashBackend_QaIde1234567890', @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 THROW 56303, 'TEST FAILED: no se pudo crear el usuario del docente D1.', 1;

    DECLARE @uE1 UNIQUEIDENTIFIER = (SELECT id FROM dbo.Usuario WHERE correo = N'est1.qa159@test.local');
    DECLARE @uE2 UNIQUEIDENTIFIER = (SELECT id FROM dbo.Usuario WHERE correo = N'est2.qa159@test.local');
    DECLARE @uD1 UNIQUEIDENTIFIER = (SELECT id FROM dbo.Usuario WHERE correo = N'doc1.qa159@test.local');
    DECLARE @e1 UNIQUEIDENTIFIER = NEWID(), @e2 UNIQUEIDENTIFIER = NEWID(), @d1 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Estudiante (id, usuario) VALUES (@e1, @uE1), (@e2, @uE2);
    INSERT INTO dbo.EstudiantePrograma (id, estudiante, programa) VALUES (NEWID(), @e1, @idPrograma);
    INSERT INTO dbo.Docente (id, usuario) VALUES (@d1, @uD1);
    INSERT INTO dbo.DocentePrograma (id, docente, programa, tipoVinculacion, estado, fechaVinculacionUtc)
    VALUES (NEWID(), @d1, @idPrograma, (SELECT id FROM dbo.TipoVinculacion WHERE codigo = 'CAT'), 1, SYSUTCDATETIME());

    DECLARE @msgExito NVARCHAR(4000) = (SELECT contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'IDE_002');
    DECLARE @msgMotivo NVARCHAR(4000) = (SELECT contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'IDE_001');
    DECLARE @msgApagado NVARCHAR(4000) = (SELECT contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'IDE_003');
    DECLARE @msgNoExiste NVARCHAR(4000) = (SELECT dbo.ufn_reemplazar_plantilla_mensaje(contenido, N'Estudiante', NULL, NULL) FROM dbo.uv_mensaje_usuario WHERE codigo = 'GEN_001');
    DECLARE @msgSinEjecutor NVARCHAR(4000) = (SELECT dbo.ufn_reemplazar_plantilla_mensaje(contenido, N'idUsuarioEjecutor', NULL, NULL) FROM dbo.uv_mensaje_usuario WHERE codigo = 'GEN_002');
    IF @msgExito IS NULL OR @msgMotivo IS NULL OR @msgApagado IS NULL THROW 56304, 'TEST FAILED: faltan los mensajes IDE_001..IDE_003.', 1;
    IF dbo.ufn_obtener_parametro_int(NULL, 'IDENTIDAD', 'PERMITIR_CORREGIR_DOCUMENTO') <> 1
        THROW 56305, 'TEST FAILED: IDENTIDAD.PERMITIR_CORREGIR_DOCUMENTO debe ser 1 por defecto.', 1;

    -- HU159_SUCCESS: corrige documento y nombres del estudiante; el correo no cambia; auditoria con motivo, anterior y nuevo
    INSERT INTO #r EXEC dbo.usp_corregir_identidad_usuario @tipoUsuario = 'ESTUDIANTE', @idRegistro = @e1,
        @idTipoIdIdentificacion = @tipoOtro, @numeroIdentificacion = 915900011, @primerNombre = N'Ana', @segundoNombre = N'Maria',
        @primerApellido = N'Gomez', @segundoApellido = N'Ruiz', @motivo = N'  Error de digitacion al inscribir  ',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND mensajeUsuarioResultado = @msgExito AND idUsuario = @uE1
                   AND correo = N'est1.qa159@test.local' AND numeroIdentificacion = 915900011)
        THROW 56306, 'TEST FAILED HU159_SUCCESS: la correccion no retorno IDE_002 con idUsuario, correo y documento nuevo.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @uE1 AND tipoIdIdentificacion = @tipoOtro AND numeroIdentificacion = 915900011
                   AND segundoNombre = N'Maria' AND primerApellido = N'Gomez' AND segundoApellido = N'Ruiz' AND correo = N'est1.qa159@test.local')
        THROW 56307, 'TEST FAILED HU159_SUCCESS: dbo.Usuario no refleja la correccion o cambio el correo.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.AuditoriaEvento WHERE action = 'CORREGIR_IDENTIDAD_ESTUDIANTE' AND resourceId = CAST(@e1 AS NVARCHAR(120))
                   AND actorId = CAST(@uCoord AS NVARCHAR(120)) AND correlationId = @corr
                   AND JSON_VALUE(metadata, '$.motivo') = N'Error de digitacion al inscribir'
                   AND JSON_VALUE(metadata, '$.anterior.numeroIdentificacion') = N'915900001'
                   AND JSON_VALUE(metadata, '$.nuevo.numeroIdentificacion') = N'915900011'
                   AND JSON_VALUE(metadata, '$.anterior.primerApellido') = N'Gomes'
                   AND JSON_VALUE(metadata, '$.nuevo.primerApellido') = N'Gomez')
        THROW 56308, 'TEST FAILED HU159_SUCCESS: la auditoria no tiene el motivo y los valores anterior y nuevo.', 1;
    PRINT 'TEST_PASS:HU159_IDENTITY_CORRECTION_SUCCESS';

    -- HU159_REASON: motivo vacio, nulo o de mas de 500 caracteres (IDE_001), sin cambios
    DECLARE @motivoLargo NVARCHAR(MAX) = REPLICATE(N'x', 501);
    DELETE FROM #r;
    INSERT INTO #r EXEC dbo.usp_corregir_identidad_usuario @tipoUsuario = 'ESTUDIANTE', @idRegistro = @e1,
        @idTipoIdIdentificacion = @tipoOtro, @numeroIdentificacion = 915900011, @primerNombre = N'SinMotivo', @segundoNombre = NULL,
        @primerApellido = N'Gomez', @segundoApellido = NULL, @motivo = N'   ', @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    INSERT INTO #r EXEC dbo.usp_corregir_identidad_usuario @tipoUsuario = 'ESTUDIANTE', @idRegistro = @e1,
        @idTipoIdIdentificacion = @tipoOtro, @numeroIdentificacion = 915900011, @primerNombre = N'SinMotivo', @segundoNombre = NULL,
        @primerApellido = N'Gomez', @segundoApellido = NULL, @motivo = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    INSERT INTO #r EXEC dbo.usp_corregir_identidad_usuario @tipoUsuario = 'ESTUDIANTE', @idRegistro = @e1,
        @idTipoIdIdentificacion = @tipoOtro, @numeroIdentificacion = 915900011, @primerNombre = N'SinMotivo', @segundoNombre = NULL,
        @primerApellido = N'Gomez', @segundoApellido = NULL, @motivo = @motivoLargo, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF (SELECT COUNT(*) FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msgMotivo AND idUsuario IS NULL) <> 3
       OR EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @uE1 AND primerNombre = N'SinMotivo')
        THROW 56309, 'TEST FAILED HU159_REASON: un motivo vacio, nulo o largo no retorno IDE_001 o modifico datos.', 1;
    PRINT 'TEST_PASS:HU159_IDENTITY_CORRECTION_REASON_REQUIRED';

    -- HU159_SCOPE: estudiante sin vinculo con el programa del coordinador o inexistente (GEN_001); tipo no soportado
    DELETE FROM #r;
    INSERT INTO #r EXEC dbo.usp_corregir_identidad_usuario @tipoUsuario = 'ESTUDIANTE', @idRegistro = @e2,
        @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 915900002, @primerNombre = N'Intruso', @segundoNombre = NULL,
        @primerApellido = N'Otro', @segundoApellido = NULL, @motivo = N'Prueba de alcance', @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    INSERT INTO #r EXEC dbo.usp_corregir_identidad_usuario @tipoUsuario = 'ESTUDIANTE', @idRegistro = @corr,
        @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 915900099, @primerNombre = N'Nadie', @segundoNombre = NULL,
        @primerApellido = N'Nadie', @segundoApellido = NULL, @motivo = N'Prueba de inexistente', @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF (SELECT COUNT(*) FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msgNoExiste) <> 2
       OR EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @uE2 AND primerNombre = N'Intruso')
        THROW 56310, 'TEST FAILED HU159_SCOPE: un estudiante fuera del programa o inexistente no retorno GEN_001 o se modifico.', 1;
    DELETE FROM #r;
    INSERT INTO #r EXEC dbo.usp_corregir_identidad_usuario @tipoUsuario = 'ADMINISTRADOR', @idRegistro = @e1,
        @idTipoIdIdentificacion = NULL, @numeroIdentificacion = NULL, @primerNombre = N'Tipo', @segundoNombre = NULL,
        @primerApellido = N'NoSoportado', @segundoApellido = NULL, @motivo = N'Prueba de tipo', @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE 'DBCODE=GEN_001|%')
       OR EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @uE1 AND primerNombre = N'Tipo')
        THROW 56311, 'TEST FAILED HU159_SCOPE: un tipo de usuario no soportado no fue rechazado.', 1;
    PRINT 'TEST_PASS:HU159_IDENTITY_CORRECTION_SCOPE';

    -- HU159_DOCUMENT_UNIQUE: el documento de otro usuario (ERR_UNICIDAD_DOCUMENTO) y la transaccion externa sobrevive
    DELETE FROM #r;
    DECLARE @auditoriasAntes INT = (SELECT COUNT(*) FROM dbo.AuditoriaEvento WHERE action = 'CORREGIR_IDENTIDAD_ESTUDIANTE');
    INSERT INTO #r EXEC dbo.usp_corregir_identidad_usuario @tipoUsuario = 'ESTUDIANTE', @idRegistro = @e1,
        @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 915900002, @primerNombre = N'Duplicado', @segundoNombre = NULL,
        @primerApellido = N'Gomez', @segundoApellido = NULL, @motivo = N'Prueba de duplicado', @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE 'DBCODE=ERR_UNICIDAD_DOCUMENTO|%')
       OR EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @uE1 AND primerNombre = N'Duplicado')
       OR (SELECT COUNT(*) FROM dbo.AuditoriaEvento WHERE action = 'CORREGIR_IDENTIDAD_ESTUDIANTE') <> @auditoriasAntes
        THROW 56312, 'TEST FAILED HU159_DOCUMENT_UNIQUE: un documento duplicado no retorno ERR_UNICIDAD_DOCUMENTO o dejo cambios.', 1;
    IF @@TRANCOUNT <> 1 THROW 56313, 'TEST FAILED HU159_DOCUMENT_UNIQUE: el rechazo rompio la transaccion externa del llamador.', 1;
    -- Reenviar su propio documento no cuenta como duplicado
    DELETE FROM #r;
    INSERT INTO #r EXEC dbo.usp_corregir_identidad_usuario @tipoUsuario = 'ESTUDIANTE', @idRegistro = @e1,
        @idTipoIdIdentificacion = @tipoOtro, @numeroIdentificacion = 915900011, @primerNombre = N'Ana', @segundoNombre = N'Maria',
        @primerApellido = N'Gomez', @segundoApellido = N'Ruiz', @motivo = N'Mismo documento', @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1)
        THROW 56314, 'TEST FAILED HU159_DOCUMENT_UNIQUE: reenviar el documento propio fue rechazado.', 1;
    PRINT 'TEST_PASS:HU159_IDENTITY_CORRECTION_DOCUMENT_UNIQUE';

    -- HU159_RBAC: ejecutor nulo (GEN_002); el propio estudiante; un coordinador corrigiendo a un decano
    DELETE FROM #r;
    INSERT INTO #r EXEC dbo.usp_corregir_identidad_usuario @tipoUsuario = 'ESTUDIANTE', @idRegistro = @e1,
        @idTipoIdIdentificacion = NULL, @numeroIdentificacion = NULL, @primerNombre = N'Nulo', @segundoNombre = NULL,
        @primerApellido = N'Gomez', @segundoApellido = NULL, @motivo = N'Prueba', @idCorrelacion = @corr, @idUsuarioEjecutor = NULL;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msgSinEjecutor)
        THROW 56315, 'TEST FAILED HU159_RBAC: ejecutor NULL no retorno GEN_002.', 1;
    DELETE FROM #r;
    INSERT INTO #r EXEC dbo.usp_corregir_identidad_usuario @tipoUsuario = 'ESTUDIANTE', @idRegistro = @e1,
        @idTipoIdIdentificacion = NULL, @numeroIdentificacion = NULL, @primerNombre = N'Propio', @segundoNombre = NULL,
        @primerApellido = N'Gomez', @segundoApellido = NULL, @motivo = N'Prueba', @idCorrelacion = @corr, @idUsuarioEjecutor = @uE1;
    INSERT INTO #r EXEC dbo.usp_corregir_identidad_usuario @tipoUsuario = 'DECANO', @idRegistro = @idDecano,
        @idTipoIdIdentificacion = NULL, @numeroIdentificacion = NULL, @primerNombre = N'Propio', @segundoNombre = NULL,
        @primerApellido = N'Coordinador', @segundoApellido = NULL, @motivo = N'Prueba', @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF (SELECT COUNT(*) FROM #r WHERE estadoResultado = 0) <> 2
       OR EXISTS (SELECT 1 FROM dbo.Usuario WHERE id IN (@uE1, @uDecano) AND primerNombre = N'Propio')
        THROW 56316, 'TEST FAILED HU159_RBAC: un ejecutor sin el perfil de la jerarquia no fue rechazado.', 1;
    PRINT 'TEST_PASS:HU159_IDENTITY_CORRECTION_RBAC';

    -- HU159_DEAN: el administrador corrige al decano (documento y nombres, auditado)
    DECLARE @numeroDecano INT = (SELECT numeroIdentificacion FROM dbo.Usuario WHERE id = @uDecano);
    DELETE FROM #r;
    INSERT INTO #r EXEC dbo.usp_corregir_identidad_usuario @tipoUsuario = 'DECANO', @idRegistro = @idDecano,
        @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 915900031, @primerNombre = N'Decano', @segundoNombre = N'Corregido',
        @primerApellido = N'Qa', @segundoApellido = NULL, @motivo = N'Documento mal digitado', @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idUsuario = @uDecano AND numeroIdentificacion = 915900031)
       OR NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @uDecano AND numeroIdentificacion = 915900031 AND segundoNombre = N'Corregido')
       OR NOT EXISTS (SELECT 1 FROM dbo.AuditoriaEvento WHERE action = 'CORREGIR_IDENTIDAD_DECANO' AND resourceId = CAST(@idDecano AS NVARCHAR(120))
                      AND correlationId = @corr AND JSON_VALUE(metadata, '$.anterior.numeroIdentificacion') = CAST(@numeroDecano AS NVARCHAR(20)))
        THROW 56317, 'TEST FAILED HU159_DEAN: el administrador no pudo corregir al decano o no quedo auditado.', 1;
    PRINT 'TEST_PASS:HU159_DEAN_IDENTITY_CORRECTION';

    -- HU121_DOCUMENT: el decano corrige el documento del coordinador; sin documento nada cambia; motivo si cambia
    DECLARE @uCoordTipo UNIQUEIDENTIFIER, @uCoordNumero INT, @uCoordCorreo NVARCHAR(100), @n1 NVARCHAR(50), @a1 NVARCHAR(50);
    SELECT @uCoordTipo = tipoIdIdentificacion, @uCoordNumero = numeroIdentificacion, @uCoordCorreo = correo,
           @n1 = primerNombre, @a1 = primerApellido
    FROM dbo.Usuario WHERE id = @uCoord;
    INSERT INTO #c EXEC dbo.usp_actualizar_coordinador @idCoordinador = @idCoordinador, @primerNombre = @n1, @segundoNombre = NULL,
        @primerApellido = @a1, @segundoApellido = NULL, @correo = @uCoordCorreo, @idFacultad = @idFacultad,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uDecano;
    IF NOT EXISTS (SELECT 1 FROM #c WHERE estadoResultado = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @uCoord AND tipoIdIdentificacion = @uCoordTipo AND numeroIdentificacion = @uCoordNumero)
       OR EXISTS (SELECT 1 FROM dbo.AuditoriaEvento WHERE action = 'CORREGIR_DOCUMENTO_COORDINADOR' AND correlationId = @corr)
        THROW 56318, 'TEST FAILED HU121_DOCUMENT: sin documento la edicion cambio el documento o audito una correccion.', 1;
    DELETE FROM #c;
    INSERT INTO #c EXEC dbo.usp_actualizar_coordinador @idCoordinador = @idCoordinador, @primerNombre = @n1, @segundoNombre = NULL,
        @primerApellido = @a1, @segundoApellido = NULL, @correo = @uCoordCorreo, @idFacultad = @idFacultad,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uDecano, @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 915900021;
    IF NOT EXISTS (SELECT 1 FROM #c WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msgMotivo)
       OR NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @uCoord AND numeroIdentificacion = @uCoordNumero)
        THROW 56319, 'TEST FAILED HU121_DOCUMENT: cambiar el documento sin motivo no retorno IDE_001.', 1;
    DELETE FROM #c;
    INSERT INTO #c EXEC dbo.usp_actualizar_coordinador @idCoordinador = @idCoordinador, @primerNombre = @n1, @segundoNombre = NULL,
        @primerApellido = @a1, @segundoApellido = NULL, @correo = @uCoordCorreo, @idFacultad = @idFacultad,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uDecano, @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 915900021,
        @motivo = N'Documento mal digitado';
    IF NOT EXISTS (SELECT 1 FROM #c WHERE estadoResultado = 1 AND idUsuario = @uCoord)
       OR NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @uCoord AND tipoIdIdentificacion = @tipoCC AND numeroIdentificacion = 915900021)
       OR NOT EXISTS (SELECT 1 FROM dbo.AuditoriaEvento WHERE action = 'CORREGIR_DOCUMENTO_COORDINADOR' AND correlationId = @corr
                      AND resourceId = CAST(@idCoordinador AS NVARCHAR(120))
                      AND JSON_VALUE(metadata, '$.motivo') = N'Documento mal digitado'
                      AND JSON_VALUE(metadata, '$.anterior.numeroIdentificacion') = CAST(@uCoordNumero AS NVARCHAR(20))
                      AND JSON_VALUE(metadata, '$.nuevo.numeroIdentificacion') = N'915900021')
        THROW 56320, 'TEST FAILED HU121_DOCUMENT: la correccion del documento del coordinador no se aplico o no se audito.', 1;
    DELETE FROM #c;
    INSERT INTO #c EXEC dbo.usp_actualizar_coordinador @idCoordinador = @idCoordinador, @primerNombre = @n1, @segundoNombre = NULL,
        @primerApellido = @a1, @segundoApellido = NULL, @correo = @uCoordCorreo, @idFacultad = @idFacultad,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uDecano, @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 915900002,
        @motivo = N'Duplicado';
    IF NOT EXISTS (SELECT 1 FROM #c WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE 'DBCODE=ERR_UNICIDAD_DOCUMENTO|%')
       OR NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @uCoord AND numeroIdentificacion = 915900021)
        THROW 56321, 'TEST FAILED HU121_DOCUMENT: el documento de otro usuario no fue rechazado.', 1;
    PRINT 'TEST_PASS:HU121_COORDINATOR_DOCUMENT_CORRECTION';

    -- HU092_DOCUMENT: el coordinador corrige el documento del docente vinculado; motivo si cambia
    INSERT INTO #d EXEC dbo.usp_actualizar_docente_programa @idDocente = @d1, @idPrograma = @idPrograma,
        @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 915900041, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF NOT EXISTS (SELECT 1 FROM #d WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msgMotivo)
       OR NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @uD1 AND numeroIdentificacion = 915900003)
        THROW 56322, 'TEST FAILED HU092_DOCUMENT: cambiar el documento del docente sin motivo no retorno IDE_001.', 1;
    DELETE FROM #d;
    INSERT INTO #d EXEC dbo.usp_actualizar_docente_programa @idDocente = @d1, @idPrograma = @idPrograma,
        @primerNombre = N'Pablo', @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 915900041,
        @motivo = N'Cedula mal digitada', @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF NOT EXISTS (SELECT 1 FROM #d WHERE estadoResultado = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @uD1 AND numeroIdentificacion = 915900041 AND primerNombre = N'Pablo')
       OR NOT EXISTS (SELECT 1 FROM dbo.AuditoriaEvento WHERE action = 'CORREGIR_DOCUMENTO_DOCENTE' AND correlationId = @corr
                      AND resourceId = CAST(@d1 AS NVARCHAR(120))
                      AND JSON_VALUE(metadata, '$.anterior.numeroIdentificacion') = N'915900003'
                      AND JSON_VALUE(metadata, '$.nuevo.numeroIdentificacion') = N'915900041')
        THROW 56323, 'TEST FAILED HU092_DOCUMENT: la correccion del documento del docente no se aplico o no se audito.', 1;
    PRINT 'TEST_PASS:HU092_TEACHER_DOCUMENT_CORRECTION';

    -- PARAMETER_OFF: con IDENTIDAD.PERMITIR_CORREGIR_DOCUMENTO = 0 el documento se rechaza (IDE_003) y los nombres siguen
    UPDATE dbo.CatalogoParametro SET valor = N'0' WHERE grupo = 'IDENTIDAD' AND clave = 'PERMITIR_CORREGIR_DOCUMENTO';
    DELETE FROM #r;
    INSERT INTO #r EXEC dbo.usp_corregir_identidad_usuario @tipoUsuario = 'ESTUDIANTE', @idRegistro = @e1,
        @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 915900051, @primerNombre = N'Apagado', @segundoNombre = NULL,
        @primerApellido = N'Gomez', @segundoApellido = NULL, @motivo = N'Prueba apagado', @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msgApagado)
       OR EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @uE1 AND (numeroIdentificacion = 915900051 OR primerNombre = N'Apagado'))
        THROW 56324, 'TEST FAILED PARAMETER_OFF: con el parametro en 0 el documento no fue rechazado con IDE_003.', 1;
    DELETE FROM #r;
    INSERT INTO #r EXEC dbo.usp_corregir_identidad_usuario @tipoUsuario = 'ESTUDIANTE', @idRegistro = @e1,
        @idTipoIdIdentificacion = NULL, @numeroIdentificacion = NULL, @primerNombre = N'SoloNombre', @segundoNombre = NULL,
        @primerApellido = N'Gomez', @segundoApellido = NULL, @motivo = N'Prueba apagado nombres', @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @uE1 AND primerNombre = N'SoloNombre' AND numeroIdentificacion = 915900011)
        THROW 56325, 'TEST FAILED PARAMETER_OFF: con el parametro en 0 la correccion de nombres dejo de funcionar.', 1;
    DELETE FROM #d;
    INSERT INTO #d EXEC dbo.usp_actualizar_docente_programa @idDocente = @d1, @idPrograma = @idPrograma,
        @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 915900061, @motivo = N'Apagado',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF NOT EXISTS (SELECT 1 FROM #d WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msgApagado)
        THROW 56326, 'TEST FAILED PARAMETER_OFF: con el parametro en 0 el documento del docente no fue rechazado.', 1;
    PRINT 'TEST_PASS:IDENTITY_DOCUMENT_CORRECTION_PARAMETER_OFF';

    DROP TABLE #r;
    DROP TABLE #c;
    DROP TABLE #d;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH
ROLLBACK TRANSACTION;

IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo LIKE N'%.qa159@test.local')
    THROW 56327, 'TEST FAILED: la correccion de identidad dejo datos permanentes.', 1;
IF dbo.ufn_obtener_parametro_int(NULL, 'IDENTIDAD', 'PERMITIR_CORREGIR_DOCUMENTO') <> 1
    THROW 56328, 'TEST FAILED: la prueba dejo apagado el parametro de correccion de documento.', 1;
IF @@TRANCOUNT <> 0 THROW 56329, 'TEST FAILED: la correccion de identidad dejo transacciones abiertas.', 1;
PRINT 'TEST END: test_usp_corregir_identidad_usuario';
GO
