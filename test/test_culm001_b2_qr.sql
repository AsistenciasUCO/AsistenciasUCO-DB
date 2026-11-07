USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- CULM-001 B.2 (CONTRACT §2.2, §2.8.3, §2.16.2 B2-QR-01..10): QR y PIN rotativos de asistencia por toma (DEC-015, HU175,
-- HU176). Solo SHA-256 del token en la BD; PIN unico entre activos y anteriores vigentes; registro idempotente por
-- estudiante y toma; el token/PIN anterior vale solo ASISTENCIA_QR/TOLERANCIA_SEGUNDOS tras la rotacion; un estudiante de
-- otro grupo o con matricula CI/I nunca escribe. Todo dentro de una transaccion revertida.
PRINT 'TEST START: test_culm001_b2_qr (CULM-001 B.2, HU175, HU176)';

IF OBJECT_ID(N'dbo.usp_abrir_qr_toma', N'P') IS NULL OR OBJECT_ID(N'dbo.usp_internal_rotar_token_asistencia', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_rotar_token_asistencia_toma', N'P') IS NULL OR OBJECT_ID(N'dbo.usp_rotar_token_asistencia_automatico', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_consultar_tomas_qr_por_rotar', N'P') IS NULL OR OBJECT_ID(N'dbo.usp_cerrar_qr_toma', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_internal_resolver_token_asistencia', N'P') IS NULL OR OBJECT_ID(N'dbo.usp_registrar_asistencia_por_token', N'P') IS NULL
    THROW 57400, 'TEST FAILED CULM001_B2_QR_00: faltan los SP del QR de asistencia.', 1;
IF dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA_QR', 'ROTACION_SEGUNDOS') <> 60
   OR dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA_QR', 'TOLERANCIA_SEGUNDOS') <> 60
   OR dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA_QR', 'LOTE_ROTACION') <> 200
   OR dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA_QR', 'LIMITE_FALLIDOS_IP_POR_MINUTO') <> 600
   OR dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA_QR', 'LIMITE_TOKEN_POR_MINUTO') <> 120
   OR dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA_QR', 'LIMITE_ESTUDIANTE_POR_MINUTO') <> 6
   OR CAST(dbo.ufn_obtener_parametro('ASISTENCIA_QR', 'HABILITADA') AS NVARCHAR(10)) <> N'true'
   OR CAST(dbo.ufn_obtener_parametro('ASISTENCIA_QR', 'URL_BASE_FRONTEND') AS NVARCHAR(200)) <> N'http://localhost:4200'
    THROW 57401, 'TEST FAILED CULM001_B2_QR_00: parametros ASISTENCIA_QR/* ausentes o distintos de la semilla 35.', 1;
IF EXISTS (SELECT 1 FROM (VALUES ('AQR_001'), ('AQR_002'), ('AQR_003'), ('AQR_004'), ('AQR_005'), ('AQR_006'), ('AQR_007'), ('AQR_008'),
                                 ('AQR_009'), ('AQR_010'), ('AQR_011'), ('AQR_012'), ('AQR_013')) c(codigo)
           WHERE NOT EXISTS (SELECT 1 FROM dbo.uv_mensaje_usuario u WHERE u.codigo = c.codigo)
              OR NOT EXISTS (SELECT 1 FROM dbo.uv_mensaje_tecnico t WHERE t.codigo = c.codigo))
    THROW 57402, 'TEST FAILED CULM001_B2_QR_00: mensajes AQR_001..AQR_013 ausentes.', 1;
PRINT 'TEST_PASS:CULM001_B2_QR_00_OBJETOS_Y_SEMILLAS';
GO

DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @idAsig UNIQUEIDENTIFIER = (SELECT TOP 1 a.id FROM dbo.uv_asignatura a WHERE a.estaActivaAsignatura = 1 ORDER BY a.id);
DECLARE @idInstitucion UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion ORDER BY id);
DECLARE @estadoA UNIQUEIDENTIFIER = (SELECT id FROM dbo.uv_estado_estudiante_grupo WHERE codigo = 'A');
DECLARE @estadoI UNIQUEIDENTIFIER = (SELECT id FROM dbo.uv_estado_estudiante_grupo WHERE codigo = 'I');
DECLARE @estadoCI UNIQUEIDENTIFIER = (SELECT id FROM dbo.uv_estado_estudiante_grupo WHERE codigo = 'CI');
DECLARE @tipoManual UNIQUEIDENTIFIER = (SELECT id FROM dbo.TipoCancelacionSesion WHERE esAutomatica = 0);
DECLARE @modoQr UNIQUEIDENTIFIER = (SELECT id FROM dbo.ModoTomaAsistencia WHERE usaCodigoQr = 1);
DECLARE @estAbierta UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoTomaAsistencia WHERE estaAbierta = 1);
DECLARE @estCerrada UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoTomaAsistencia WHERE estaAbierta = 0);
DECLARE @zona SYSNAME = dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER');
DECLARE @hoy DATE = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE @zona AS DATE);
IF @tipoCC IS NULL OR @idAsig IS NULL OR @idInstitucion IS NULL OR @estadoA IS NULL OR @estadoI IS NULL OR @estadoCI IS NULL
   OR @tipoManual IS NULL OR @modoQr IS NULL OR @estAbierta IS NULL OR @estCerrada IS NULL
    THROW 57410, 'TEST FAILED CULM001_B2_QR: faltan fixtures del seed.', 1;

CREATE TABLE #b2qO (idCorrelacion UNIQUEIDENTIFIER NULL, mu NVARCHAR(4000) NULL, mt NVARCHAR(4000) NULL, estado BIT NOT NULL,
    idTokenAsistencia UNIQUEIDENTIFIER NULL, idToma UNIQUEIDENTIFIER NULL, idSesion UNIQUEIDENTIFIER NULL, idGrupo UNIQUEIDENTIFIER NULL,
    fechaRotacionUtc DATETIME2(0) NULL, fechaExpiracionUtc DATETIME2(0) NULL, rotacionSegundos INT NULL);
CREATE TABLE #b2qT (idCorrelacion UNIQUEIDENTIFIER NULL, mu NVARCHAR(4000) NULL, mt NVARCHAR(4000) NULL, estado BIT NOT NULL,
    idTokenAsistencia UNIQUEIDENTIFIER NULL, idToma UNIQUEIDENTIFIER NULL, idGrupo UNIQUEIDENTIFIER NULL, idDocenteEmisor UNIQUEIDENTIFIER NULL,
    fechaRotacionUtc DATETIME2(0) NULL, fechaExpiracionUtc DATETIME2(0) NULL, rotado BIT NULL);
CREATE TABLE #b2qR (idCorrelacion UNIQUEIDENTIFIER NULL, mu NVARCHAR(4000) NULL, mt NVARCHAR(4000) NULL, estado BIT NOT NULL,
    idToma UNIQUEIDENTIFIER NULL, idSesion UNIQUEIDENTIFIER NULL, idGrupo UNIQUEIDENTIFIER NULL, nombreAsignatura NVARCHAR(200) NULL,
    nombreGrupo NVARCHAR(300) NULL, numeroSesion INT NULL, numeroToma SMALLINT NULL, yaRegistrado BIT NULL, fechaRegistroUtc DATETIME2(0) NULL);
CREATE TABLE #b2qX (idCorrelacion UNIQUEIDENTIFIER NULL, mu NVARCHAR(4000) NULL, mt NVARCHAR(4000) NULL, estado BIT NOT NULL,
    idToma UNIQUEIDENTIFIER NULL, idSesion UNIQUEIDENTIFIER NULL, idGrupo UNIQUEIDENTIFIER NULL);
CREATE TABLE #b2qL (idCorrelacion UNIQUEIDENTIFIER NULL, mu NVARCHAR(4000) NULL, mt NVARCHAR(4000) NULL, estado BIT NOT NULL,
    idToma UNIQUEIDENTIFIER NULL, idSesion UNIQUEIDENTIFIER NULL, idGrupo UNIQUEIDENTIFIER NULL, totalRegistros INT NULL);
CREATE TABLE #b2qP (idToma UNIQUEIDENTIFIER, idGrupo UNIQUEIDENTIFIER, idDocenteEmisor UNIQUEIDENTIFIER);

DECLARE @corr UNIQUEIDENTIFIER, @json NVARCHAR(MAX);
DECLARE @h1 VARBINARY(32) = HASHBYTES('SHA2_256', CONCAT(N'culmb2-token-1-', NEWID()));
DECLARE @h2 VARBINARY(32) = HASHBYTES('SHA2_256', CONCAT(N'culmb2-token-2-', NEWID()));
DECLARE @h3 VARBINARY(32) = HASHBYTES('SHA2_256', CONCAT(N'culmb2-token-3-', NEWID()));
DECLARE @h4 VARBINARY(32) = HASHBYTES('SHA2_256', CONCAT(N'culmb2-token-4-', NEWID()));
DECLARE @h5 VARBINARY(32) = HASHBYTES('SHA2_256', CONCAT(N'culmb2-token-5-', NEWID()));
DECLARE @hX VARBINARY(32) = HASHBYTES('SHA2_256', CONCAT(N'culmb2-token-desconocido-', NEWID()));
-- PIN de 6 digitos que no colisionan con un PIN activo de otra prueba (bloque 9xxxxx reservado a esta prueba)
DECLARE @pinBase INT = 900000 + ABS(CHECKSUM(NEWID()) % 9000) * 10;
DECLARE @p1 NCHAR(6) = CAST(@pinBase + 1 AS NCHAR(6)), @p2 NCHAR(6) = CAST(@pinBase + 2 AS NCHAR(6)), @p3 NCHAR(6) = CAST(@pinBase + 3 AS NCHAR(6));
DECLARE @p4 NCHAR(6) = CAST(@pinBase + 4 AS NCHAR(6)), @p5 NCHAR(6) = CAST(@pinBase + 5 AS NCHAR(6));

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @uD1 UNIQUEIDENTIFIER = NEWID(), @uD2 UNIQUEIDENTIFIER = NEWID(), @d1 UNIQUEIDENTIFIER = NEWID(), @d2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @tag NVARCHAR(12) = LEFT(REPLACE(CONVERT(NVARCHAR(36), NEWID()), N'-', N''), 12);
    CREATE TABLE #b2qE (n INT, idUsuario UNIQUEIDENTIFIER, idEstudiante UNIQUEIDENTIFIER, idEG UNIQUEIDENTIFIER);
    INSERT INTO #b2qE (n, idUsuario, idEstudiante, idEG) SELECT v.n, NEWID(), NEWID(), NEWID() FROM (VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9)) v(n);
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uD1, @tipoCC, 974000000 + ABS(CHECKSUM(NEWID()) % 999999), N'Titular', N'CulmB', N'Quique', N'B2', CONCAT(N'culmb2q.d1.', @tag, N'@test.local'), 1, 1, N'HashBackend_CULMB2'),
           (@uD2, @tipoCC, 975000000 + ABS(CHECKSUM(NEWID()) % 999999), N'Otro', N'CulmB', N'Quintin', N'B2', CONCAT(N'culmb2q.d2.', @tag, N'@test.local'), 1, 1, N'HashBackend_CULMB2');
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    SELECT e.idUsuario, @tipoCC, 976000000 + e.n * 10000 + ABS(CHECKSUM(NEWID()) % 9999), CONCAT(N'Qr', e.n), N'CulmB', N'Est', N'B2',
           CONCAT(N'culmb2q.e', e.n, N'.', @tag, N'@test.local'), 1, 1, N'HashBackend_CULMB2'
    FROM #b2qE e;
    INSERT INTO dbo.Docente (id, usuario) VALUES (@d1, @uD1), (@d2, @uD2);
    INSERT INTO dbo.Estudiante (id, usuario) SELECT idEstudiante, idUsuario FROM #b2qE;
    DECLARE @per UNIQUEIDENTIFIER = NEWID(), @g UNIQUEIDENTIFIER = NEWID(), @g2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@per, @idInstitucion, N'CULMB2 periodo QR', 3300000 + ABS(CHECKSUM(NEWID()) % 600000), DATEADD(DAY, -30, @hoy), DATEADD(DAY, 30, @hoy), YEAR(@hoy));
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
        cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@g, @idAsig, @per, 946000 + ABS(CHECKSUM(NEWID()) % 53999), N'CULMB2 Grupo QR', 30, 0, 0, 0, @d1),
           (@g2, @idAsig, @per, 947000 + ABS(CHECKSUM(NEWID()) % 52999), N'CULMB2 Grupo QR 2', 30, 0, 0, 0, @d2);
    -- e1..e4, e8, e9 activos en g; e5 CI y e6 I en g; e7 activo solo en g2
    INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo)
    SELECT e.idEG, CASE e.n WHEN 5 THEN @estadoCI WHEN 6 THEN @estadoI ELSE @estadoA END, e.idEstudiante, IIF(e.n = 7, @g2, @g) FROM #b2qE e;
    DECLARE @uE1 UNIQUEIDENTIFIER = (SELECT idUsuario FROM #b2qE WHERE n = 1), @uE2 UNIQUEIDENTIFIER = (SELECT idUsuario FROM #b2qE WHERE n = 2);
    DECLARE @uE3 UNIQUEIDENTIFIER = (SELECT idUsuario FROM #b2qE WHERE n = 3), @uE4 UNIQUEIDENTIFIER = (SELECT idUsuario FROM #b2qE WHERE n = 4);
    DECLARE @uE5 UNIQUEIDENTIFIER = (SELECT idUsuario FROM #b2qE WHERE n = 5), @uE6 UNIQUEIDENTIFIER = (SELECT idUsuario FROM #b2qE WHERE n = 6);
    DECLARE @uE7 UNIQUEIDENTIFIER = (SELECT idUsuario FROM #b2qE WHERE n = 7), @uE8 UNIQUEIDENTIFIER = (SELECT idUsuario FROM #b2qE WHERE n = 8);
    DECLARE @uE9 UNIQUEIDENTIFIER = (SELECT idUsuario FROM #b2qE WHERE n = 9);
    DECLARE @e4 UNIQUEIDENTIFIER = (SELECT idEstudiante FROM #b2qE WHERE n = 4);

    DECLARE @sA UNIQUEIDENTIFIER = NEWID(), @sB UNIQUEIDENTIFIER = NEWID(), @sC UNIQUEIDENTIFIER = NEWID(), @sPast UNIQUEIDENTIFIER = NEWID();
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    VALUES (@sA,    N'CULMB2Q A',      1, N'CB2Q01', 1, @g, DATEADD(MINUTE, -30, SYSUTCDATETIME()), DATEADD(MINUTE, 90, SYSUTCDATETIME()), N'UTC_V2'),
           (@sB,    N'CULMB2Q B',      2, N'CB2Q02', 1, @g, DATEADD(MINUTE, -30, SYSUTCDATETIME()), DATEADD(MINUTE, 90, SYSUTCDATETIME()), N'UTC_V2'),
           (@sC,    N'CULMB2Q C',      3, N'CB2Q03', 1, @g, DATEADD(MINUTE, -30, SYSUTCDATETIME()), DATEADD(MINUTE, 90, SYSUTCDATETIME()), N'UTC_V2'),
           (@sPast, N'CULMB2Q pasada', 4, N'CB2Q04', 1, @g, DATEADD(MINUTE, -300, SYSUTCDATETIME()), DATEADD(MINUTE, -180, SYSUTCDATETIME()), N'UTC_V2');
    -- Tomas: tA (QR abierta en sA), tB (QR abierta en sB), tC (QR abierta en sC), tM (MANUAL abierta en ... sA no: una por sesion)
    DECLARE @tA UNIQUEIDENTIFIER, @tB UNIQUEIDENTIFIER, @tC UNIQUEIDENTIFIER, @tM UNIQUEIDENTIFIER, @tCerrada UNIQUEIDENTIFIER = NEWID(), @tPast UNIQUEIDENTIFIER = NEWID();
    CREATE TABLE #b2qA (idCorrelacion UNIQUEIDENTIFIER NULL, mu NVARCHAR(4000) NULL, mt NVARCHAR(4000) NULL, estado BIT NOT NULL,
        idToma UNIQUEIDENTIFIER NULL, numero SMALLINT NULL, codigoModo NVARCHAR(20) NULL, usaCodigoQr BIT NULL, fechaAperturaUtc DATETIME2(0) NULL,
        ventanaCierreUtc DATETIME2(0) NULL, totalTomasSesion INT NULL, horasToma DECIMAL(12,6) NULL);
    SET @corr = NEWID();
    -- en sC: una toma QR cerrada (numero 1) y luego una MANUAL abierta (numero 2)
    INSERT INTO dbo.TomaAsistencia (id, sesion, numero, modo, estado, esImplicita, docenteApertura, fechaAperturaUtc, fechaCierreUtc, idCorrelacionApertura)
    VALUES (@tCerrada, @sC, 1, @modoQr, @estCerrada, 0, @d1, DATEADD(MINUTE, -25, SYSUTCDATETIME()), DATEADD(MINUTE, -20, SYSUTCDATETIME()), NEWID()),
           (@tPast, @sPast, 1, @modoQr, @estAbierta, 0, @d1, DATEADD(MINUTE, -290, SYSUTCDATETIME()), NULL, NEWID());
    INSERT INTO #b2qA EXEC dbo.usp_abrir_toma_asistencia @idSesion = @sA, @codigoModo = N'QR', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    SET @tA = (SELECT idToma FROM #b2qA WHERE estado = 1 AND numero = 1 AND codigoModo = N'QR');
    TRUNCATE TABLE #b2qA;
    INSERT INTO #b2qA EXEC dbo.usp_abrir_toma_asistencia @idSesion = @sB, @codigoModo = N'QR', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    SET @tB = (SELECT idToma FROM #b2qA WHERE estado = 1 AND numero = 1 AND codigoModo = N'QR');
    TRUNCATE TABLE #b2qA;
    INSERT INTO #b2qA EXEC dbo.usp_abrir_toma_asistencia @idSesion = @sC, @codigoModo = N'MANUAL', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    SET @tM = (SELECT idToma FROM #b2qA WHERE estado = 1 AND numero = 2 AND codigoModo = N'MANUAL');
    TRUNCATE TABLE #b2qA;
    IF @tA IS NULL OR @tB IS NULL OR @tM IS NULL
        THROW 57411, 'TEST FAILED CULM001_B2_QR: no se pudieron abrir las tomas del fixture.', 1;

    -- --------------------------------------------------------------------------------------------------------
    -- B2-QR-01: abrir QR en toma MANUAL AQR_003 / toma cerrada AQR_005 / ventana vencida SES_008
    -- --------------------------------------------------------------------------------------------------------
    SET @corr = NEWID();
    INSERT INTO #b2qO EXEC dbo.usp_abrir_qr_toma @idToma = @tM, @tokenHash = @h5, @pin = @p5, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    INSERT INTO #b2qO EXEC dbo.usp_abrir_qr_toma @idToma = @tCerrada, @tokenHash = @h5, @pin = @p5, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    INSERT INTO #b2qO EXEC dbo.usp_abrir_qr_toma @idToma = @tPast, @tokenHash = @h5, @pin = @p5, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    INSERT INTO #b2qO EXEC dbo.usp_abrir_qr_toma @idToma = @tA, @tokenHash = @h5, @pin = @p5, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD2;
    INSERT INTO #b2qO EXEC dbo.usp_abrir_qr_toma @idToma = @corr, @tokenHash = @h5, @pin = @p5, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    INSERT INTO #b2qO EXEC dbo.usp_abrir_qr_toma @idToma = @tA, @tokenHash = @h5, @pin = N'12a456', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF (SELECT COUNT(*) FROM #b2qO WHERE estado = 0 AND idTokenAsistencia IS NULL) <> 6
       OR NOT EXISTS (SELECT 1 FROM #b2qO WHERE mt LIKE N'DBCODE=AQR[_]003|%')
       OR NOT EXISTS (SELECT 1 FROM #b2qO WHERE mt LIKE N'DBCODE=AQR[_]005|%')
       OR NOT EXISTS (SELECT 1 FROM #b2qO WHERE mt LIKE N'DBCODE=SES[_]008|%')
       OR NOT EXISTS (SELECT 1 FROM #b2qO WHERE mt LIKE N'DBCODE=SEC[_]002|%')
       OR NOT EXISTS (SELECT 1 FROM #b2qO WHERE mt LIKE N'DBCODE=TOM[_]001|%')
       OR NOT EXISTS (SELECT 1 FROM #b2qO WHERE mt LIKE N'DBCODE=GEN[_]002|%')
       OR EXISTS (SELECT 1 FROM dbo.TokenAsistenciaToma WHERE toma IN (@tM, @tCerrada, @tPast, @tA))
        THROW 57420, 'TEST FAILED CULM001_B2_QR_01: abrir QR en toma MANUAL AQR_003, cerrada AQR_005, vencida SES_008, ajena SEC_002, inexistente TOM_001, PIN invalido GEN_002.', 1;
    TRUNCATE TABLE #b2qO;
    PRINT 'TEST_PASS:CULM001_B2_QR_01_ABRIR_QR_REGLAS';

    -- --------------------------------------------------------------------------------------------------------
    -- B2-QR-02: abrir QR en tA (p1/h1); PIN repetido con un activo o con un anterior vigente => AQR_006 sin escritura
    -- --------------------------------------------------------------------------------------------------------
    SET @corr = NEWID();
    INSERT INTO #b2qO EXEC dbo.usp_abrir_qr_toma @idToma = @tA, @tokenHash = @h1, @pin = @p1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF NOT EXISTS (SELECT 1 FROM #b2qO o INNER JOIN dbo.Sesion s ON s.id = @sA
                   WHERE o.estado = 1 AND o.mt LIKE N'DBCODE=AQR[_]012|%' AND o.idToma = @tA AND o.idSesion = @sA AND o.idGrupo = @g AND o.rotacionSegundos = 60
                     AND o.fechaExpiracionUtc = CAST(DATEADD(MINUTE, 30, s.fechaHoraFin) AS DATETIME2(0)) AND o.idTokenAsistencia IS NOT NULL)
       OR NOT EXISTS (SELECT 1 FROM dbo.TokenAsistenciaToma WHERE toma = @tA AND tokenHash = @h1 AND pin = @p1 AND fechaCierreUtc IS NULL AND docenteEmisor = @d1
                      AND tokenHashAnterior IS NULL AND fechaEmisionUtc = fechaRotacionUtc)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_token_asistencia_toma WHERE idToma = @tA AND estaActivo = 1 AND estaVigente = 1 AND debeRotar = 0 AND anteriorVigente = 0
                      AND totalRegistrosQr = 0 AND numeroToma = 1 AND idGrupo = @g)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_toma_asistencia WHERE idToma = @tA AND tieneQrActivo = 1)
        THROW 57421, 'TEST FAILED CULM001_B2_QR_02: abrir QR en una toma QR abierta debe responder AQR_012 y guardar solo el hash.', 1;
    TRUNCATE TABLE #b2qO;
    INSERT INTO #b2qO EXEC dbo.usp_abrir_qr_toma @idToma = @tB, @tokenHash = @h3, @pin = @p1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF NOT EXISTS (SELECT 1 FROM #b2qO WHERE estado = 0 AND mt LIKE N'DBCODE=AQR[_]006|%') OR EXISTS (SELECT 1 FROM dbo.TokenAsistenciaToma WHERE toma = @tB)
        THROW 57422, 'TEST FAILED CULM001_B2_QR_02: un PIN igual a un PIN activo debe responder AQR_006 sin escribir.', 1;
    TRUNCATE TABLE #b2qO;
    -- rotacion manual de tA: p1/h1 pasan a anteriores, p2/h2 vigentes
    SET @corr = NEWID();
    INSERT INTO #b2qT EXEC dbo.usp_rotar_token_asistencia_toma @idToma = @tA, @tokenHash = @h2, @pin = @p2, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF NOT EXISTS (SELECT 1 FROM #b2qT WHERE estado = 1 AND rotado = 1 AND idToma = @tA AND idGrupo = @g AND idDocenteEmisor = @d1)
       OR NOT EXISTS (SELECT 1 FROM dbo.TokenAsistenciaToma WHERE toma = @tA AND fechaCierreUtc IS NULL AND tokenHash = @h2 AND pin = @p2 AND tokenHashAnterior = @h1 AND pinAnterior = @p1)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_token_asistencia_toma WHERE idToma = @tA AND anteriorVigente = 1 AND pin = @p2 AND pinAnterior = @p1)
        THROW 57423, 'TEST FAILED CULM001_B2_QR_02: la rotacion manual debe mover el token y el PIN vigentes a los anteriores.', 1;
    TRUNCATE TABLE #b2qT;
    INSERT INTO #b2qT EXEC dbo.usp_rotar_token_asistencia_toma @idToma = @tA, @tokenHash = @h4, @pin = @p4, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD2;
    IF NOT EXISTS (SELECT 1 FROM #b2qT WHERE estado = 0 AND mt LIKE N'DBCODE=SEC[_]002|%')
        THROW 57424, 'TEST FAILED CULM001_B2_QR_02: solo el docente titular rota manualmente el token.', 1;
    TRUNCATE TABLE #b2qT;
    INSERT INTO #b2qO EXEC dbo.usp_abrir_qr_toma @idToma = @tB, @tokenHash = @h3, @pin = @p1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF NOT EXISTS (SELECT 1 FROM #b2qO WHERE estado = 0 AND mt LIKE N'DBCODE=AQR[_]006|%') OR EXISTS (SELECT 1 FROM dbo.TokenAsistenciaToma WHERE toma = @tB)
        THROW 57425, 'TEST FAILED CULM001_B2_QR_02: un PIN igual a un PIN anterior vigente debe responder AQR_006 sin escribir.', 1;
    TRUNCATE TABLE #b2qO;
    INSERT INTO #b2qO EXEC dbo.usp_abrir_qr_toma @idToma = @tB, @tokenHash = @h3, @pin = @p3, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF NOT EXISTS (SELECT 1 FROM #b2qO WHERE estado = 1 AND idToma = @tB)
        THROW 57426, 'TEST FAILED CULM001_B2_QR_02: un PIN libre debe abrir el QR de la otra toma.', 1;
    TRUNCATE TABLE #b2qO;
    PRINT 'TEST_PASS:CULM001_B2_QR_02_PIN_UNICO';

    -- --------------------------------------------------------------------------------------------------------
    -- B2-QR-03: registrar por token vigente (e1) y por PIN vigente (e2) => AQR_009, AN con registradoPorEstudiante = 1
    -- --------------------------------------------------------------------------------------------------------
    SET @corr = NEWID();
    INSERT INTO #b2qR EXEC dbo.usp_registrar_asistencia_por_token @tokenHash = @h2, @pin = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @uE1;
    INSERT INTO #b2qR EXEC dbo.usp_registrar_asistencia_por_token @tokenHash = NULL, @pin = @p2, @idCorrelacion = @corr, @idUsuarioEjecutor = @uE2;
    IF (SELECT COUNT(*) FROM #b2qR WHERE estado = 1 AND mt LIKE N'DBCODE=AQR[_]009|%' AND yaRegistrado = 0 AND idToma = @tA AND idSesion = @sA AND idGrupo = @g
          AND nombreGrupo = N'CULMB2 Grupo QR' AND numeroSesion = 1 AND numeroToma = 1 AND nombreAsignatura IS NOT NULL AND fechaRegistroUtc IS NOT NULL) <> 2
       OR (SELECT COUNT(*) FROM dbo.uv_detalle_asistencia_v2 v INNER JOIN #b2qE e ON e.idEG = v.idEstudianteGrupo
           WHERE v.idToma = @tA AND e.n IN (1, 2) AND v.codigoRazonCausa = N'AN' AND v.asistio = 1 AND v.registradoPorEstudiante = 1 AND v.fechaRegistroUtc IS NOT NULL) <> 2
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_token_asistencia_toma WHERE idToma = @tA AND totalRegistrosQr = 2)
        THROW 57430, 'TEST FAILED CULM001_B2_QR_03: registrar por token y por PIN vigentes debe responder AQR_009 y dejar AN registrado por el estudiante.', 1;
    TRUNCATE TABLE #b2qR;
    PRINT 'TEST_PASS:CULM001_B2_QR_03_REGISTRO_TOKEN_Y_PIN';

    -- --------------------------------------------------------------------------------------------------------
    -- B2-QR-04: idempotencia (token, PIN, token) => un solo detalle, AQR_008 con yaRegistrado = 1; una marca EX previa
    -- del docente no cambia
    -- --------------------------------------------------------------------------------------------------------
    SET @corr = NEWID();
    INSERT INTO #b2qR EXEC dbo.usp_registrar_asistencia_por_token @tokenHash = @h2, @idCorrelacion = @corr, @idUsuarioEjecutor = @uE3;
    INSERT INTO #b2qR EXEC dbo.usp_registrar_asistencia_por_token @pin = @p2, @idCorrelacion = @corr, @idUsuarioEjecutor = @uE3;
    INSERT INTO #b2qR EXEC dbo.usp_registrar_asistencia_por_token @tokenHash = @h2, @idCorrelacion = @corr, @idUsuarioEjecutor = @uE3;
    IF (SELECT COUNT(*) FROM #b2qR WHERE estado = 1) <> 3
       OR (SELECT COUNT(*) FROM #b2qR WHERE mt LIKE N'DBCODE=AQR[_]009|%' AND yaRegistrado = 0) <> 1
       OR (SELECT COUNT(*) FROM #b2qR WHERE mt LIKE N'DBCODE=AQR[_]008|%' AND yaRegistrado = 1 AND idToma = @tA) <> 2
       OR (SELECT COUNT(*) FROM dbo.DetalleAsistencia da INNER JOIN dbo.Asistencia a ON a.id = da.asistencia INNER JOIN #b2qE e ON e.idEG = a.estudianteGrupo
           WHERE e.n = 3 AND a.sesion = @sA) <> 1
        THROW 57440, 'TEST FAILED CULM001_B2_QR_04: tres registros del mismo estudiante deben dejar un solo detalle (AQR_009 + 2 x AQR_008).', 1;
    TRUNCATE TABLE #b2qR;
    SET @json = CONCAT(N'[{"idEstudiante":"', @e4, N'","estado":"EX"}]');
    INSERT INTO #b2qL EXEC dbo.usp_registrar_asistencias_toma @idToma = @tA, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    INSERT INTO #b2qR EXEC dbo.usp_registrar_asistencia_por_token @tokenHash = @h2, @idCorrelacion = @corr, @idUsuarioEjecutor = @uE4;
    IF NOT EXISTS (SELECT 1 FROM #b2qL WHERE estado = 1)
       OR NOT EXISTS (SELECT 1 FROM #b2qR WHERE estado = 1 AND mt LIKE N'DBCODE=AQR[_]008|%' AND yaRegistrado = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_detalle_asistencia_v2 v INNER JOIN #b2qE e ON e.idEG = v.idEstudianteGrupo
                      WHERE v.idToma = @tA AND e.n = 4 AND v.codigoRazonCausa = N'EX' AND v.registradoPorEstudiante = 0)
        THROW 57441, 'TEST FAILED CULM001_B2_QR_04: el registro por token no debe cambiar una marca EX previa del docente (AQR_008).', 1;
    TRUNCATE TABLE #b2qR; TRUNCATE TABLE #b2qL;
    PRINT 'TEST_PASS:CULM001_B2_QR_04_IDEMPOTENCIA';

    -- --------------------------------------------------------------------------------------------------------
    -- B2-QR-05: el token/PIN anterior vale hasta TOLERANCIA_SEGUNDOS despues de fechaRotacionUtc; despues AQR_001
    -- --------------------------------------------------------------------------------------------------------
    SET @corr = NEWID();
    INSERT INTO #b2qR EXEC dbo.usp_registrar_asistencia_por_token @tokenHash = @h1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uE8;
    IF NOT EXISTS (SELECT 1 FROM #b2qR WHERE estado = 1 AND mt LIKE N'DBCODE=AQR[_]009|%' AND idToma = @tA)
        THROW 57450, 'TEST FAILED CULM001_B2_QR_05: el token anterior debe valer dentro de la tolerancia tras la rotacion.', 1;
    TRUNCATE TABLE #b2qR;
    UPDATE dbo.TokenAsistenciaToma
    SET fechaEmisionUtc = DATEADD(SECOND, -61, fechaEmisionUtc), fechaRotacionUtc = DATEADD(SECOND, -61, fechaRotacionUtc)
    WHERE toma = @tA AND fechaCierreUtc IS NULL;
    INSERT INTO #b2qR EXEC dbo.usp_registrar_asistencia_por_token @tokenHash = @h1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uE9;
    INSERT INTO #b2qR EXEC dbo.usp_registrar_asistencia_por_token @pin = @p1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uE9;
    DECLARE @msgAqr001 NVARCHAR(4000) = (SELECT TOP 1 mu FROM #b2qR WHERE mt LIKE N'DBCODE=AQR[_]001|%');
    IF (SELECT COUNT(*) FROM #b2qR WHERE estado = 0 AND mt LIKE N'DBCODE=AQR[_]001|%' AND idToma IS NULL) <> 2
       OR EXISTS (SELECT 1 FROM dbo.Asistencia a INNER JOIN #b2qE e ON e.idEG = a.estudianteGrupo WHERE e.n = 9)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_token_asistencia_toma WHERE idToma = @tA AND anteriorVigente = 0 AND debeRotar = 1)
        THROW 57451, 'TEST FAILED CULM001_B2_QR_05: vencida la tolerancia el token y el PIN anteriores deben responder AQR_001 sin escribir.', 1;
    TRUNCATE TABLE #b2qR;
    INSERT INTO #b2qR EXEC dbo.usp_registrar_asistencia_por_token @tokenHash = @h2, @idCorrelacion = @corr, @idUsuarioEjecutor = @uE9;
    IF NOT EXISTS (SELECT 1 FROM #b2qR WHERE estado = 1 AND mt LIKE N'DBCODE=AQR[_]009|%')
        THROW 57452, 'TEST FAILED CULM001_B2_QR_05: el token vigente sigue valiendo aunque deba rotar (hasta la expiracion).', 1;
    TRUNCATE TABLE #b2qR;
    PRINT 'TEST_PASS:CULM001_B2_QR_05_TOKEN_ANTERIOR_TOLERANCIA';

    -- --------------------------------------------------------------------------------------------------------
    -- B2-QR-09: rotacion automatica: solo debeRotar; con @forzar = 0 una segunda instancia no rota (rotado = 0)
    -- --------------------------------------------------------------------------------------------------------
    SET @corr = NEWID();
    INSERT INTO #b2qP EXEC dbo.usp_consultar_tomas_qr_por_rotar @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #b2qP WHERE idToma = @tA AND idGrupo = @g AND idDocenteEmisor = @d1) OR EXISTS (SELECT 1 FROM #b2qP WHERE idToma = @tB)
        THROW 57490, 'TEST FAILED CULM001_B2_QR_09: usp_consultar_tomas_qr_por_rotar debe devolver solo los tokens que deben rotar.', 1;
    TRUNCATE TABLE #b2qP;
    INSERT INTO #b2qT EXEC dbo.usp_rotar_token_asistencia_automatico @idToma = @tA, @tokenHash = @h4, @pin = @p4, @forzar = 0, @idCorrelacion = @corr;
    INSERT INTO #b2qT EXEC dbo.usp_rotar_token_asistencia_automatico @idToma = @tA, @tokenHash = @h5, @pin = @p5, @forzar = 0, @idCorrelacion = @corr;
    INSERT INTO #b2qT EXEC dbo.usp_rotar_token_asistencia_automatico @idToma = @tM, @tokenHash = @h5, @pin = @p5, @forzar = 0, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #b2qT) <> 3
       OR NOT EXISTS (SELECT 1 FROM #b2qT WHERE estado = 1 AND rotado = 1 AND idToma = @tA AND idDocenteEmisor = @d1)
       OR NOT EXISTS (SELECT 1 FROM #b2qT WHERE estado = 1 AND rotado = 0 AND idToma = @tA)
       OR NOT EXISTS (SELECT 1 FROM #b2qT WHERE estado = 0 AND mt LIKE N'DBCODE=AQR[_]005|%')
       OR NOT EXISTS (SELECT 1 FROM dbo.TokenAsistenciaToma WHERE toma = @tA AND fechaCierreUtc IS NULL AND tokenHash = @h4 AND tokenHashAnterior = @h2 AND pinAnterior = @p2)
       OR EXISTS (SELECT 1 FROM dbo.TokenAsistenciaToma WHERE tokenHash = @h5)
        THROW 57491, 'TEST FAILED CULM001_B2_QR_09: la rotacion automatica con @forzar = 0 debe rotar una sola vez (rotado 1 y luego 0); sin token AQR_005.', 1;
    TRUNCATE TABLE #b2qT;
    PRINT 'TEST_PASS:CULM001_B2_QR_09_ROTACION_AUTOMATICA';

    -- --------------------------------------------------------------------------------------------------------
    -- B2-QR-06/07: estudiante de otro grupo (e7) y matriculas CI (e5) / I (e6) con token valido => AQR_004, sin escritura
    -- --------------------------------------------------------------------------------------------------------
    SET @corr = NEWID();
    INSERT INTO #b2qR EXEC dbo.usp_registrar_asistencia_por_token @tokenHash = @h4, @idCorrelacion = @corr, @idUsuarioEjecutor = @uE7;
    IF NOT EXISTS (SELECT 1 FROM #b2qR WHERE estado = 0 AND mt LIKE N'DBCODE=AQR[_]004|%' AND idToma IS NULL)
       OR EXISTS (SELECT 1 FROM dbo.Asistencia a INNER JOIN #b2qE e ON e.idEG = a.estudianteGrupo WHERE e.n = 7)
       OR EXISTS (SELECT 1 FROM dbo.Asistencia a INNER JOIN dbo.EstudianteGrupo eg ON eg.id = a.estudianteGrupo
                  INNER JOIN #b2qE e ON e.idEstudiante = eg.estudiante WHERE e.n = 7)
        THROW 57460, 'TEST FAILED CULM001_B2_QR_06: un estudiante de otro grupo con token valido debe recibir AQR_004 sin cabecera ni detalle.', 1;
    PRINT 'TEST_PASS:CULM001_B2_QR_06_OTRO_GRUPO';
    TRUNCATE TABLE #b2qR;
    INSERT INTO #b2qR EXEC dbo.usp_registrar_asistencia_por_token @tokenHash = @h4, @idCorrelacion = @corr, @idUsuarioEjecutor = @uE5;
    INSERT INTO #b2qR EXEC dbo.usp_registrar_asistencia_por_token @tokenHash = @h4, @idCorrelacion = @corr, @idUsuarioEjecutor = @uE6;
    IF (SELECT COUNT(*) FROM #b2qR WHERE estado = 0 AND mt LIKE N'DBCODE=AQR[_]004|%') <> 2
       OR EXISTS (SELECT 1 FROM dbo.Asistencia a INNER JOIN #b2qE e ON e.idEG = a.estudianteGrupo WHERE e.n IN (5, 6))
        THROW 57470, 'TEST FAILED CULM001_B2_QR_07: matriculas CI o I deben recibir AQR_004 sin escribir.', 1;
    TRUNCATE TABLE #b2qR;
    PRINT 'TEST_PASS:CULM001_B2_QR_07_MATRICULA_NO_ACTIVA';

    -- --------------------------------------------------------------------------------------------------------
    -- B2-QR-08: token y PIN a la vez / ninguno AQR_007; token desconocido / token cerrado AQR_001 (mismo mensaje);
    -- sin ejecutor GEN_002; un docente no registra (SEC_001)
    -- --------------------------------------------------------------------------------------------------------
    SET @corr = NEWID();
    INSERT INTO #b2qR EXEC dbo.usp_registrar_asistencia_por_token @tokenHash = @h4, @pin = @p4, @idCorrelacion = @corr, @idUsuarioEjecutor = @uE9;
    INSERT INTO #b2qR EXEC dbo.usp_registrar_asistencia_por_token @tokenHash = NULL, @pin = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @uE9;
    INSERT INTO #b2qR EXEC dbo.usp_registrar_asistencia_por_token @tokenHash = @hX, @idCorrelacion = @corr, @idUsuarioEjecutor = @uE9;
    INSERT INTO #b2qR EXEC dbo.usp_registrar_asistencia_por_token @tokenHash = @h4, @idCorrelacion = @corr, @idUsuarioEjecutor = NULL;
    INSERT INTO #b2qR EXEC dbo.usp_registrar_asistencia_por_token @tokenHash = @h4, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF (SELECT COUNT(*) FROM #b2qR WHERE estado = 0) <> 5
       OR (SELECT COUNT(*) FROM #b2qR WHERE mt LIKE N'DBCODE=AQR[_]007|%') <> 2
       OR NOT EXISTS (SELECT 1 FROM #b2qR WHERE mt LIKE N'DBCODE=AQR[_]001|%' AND mu = @msgAqr001)
       OR NOT EXISTS (SELECT 1 FROM #b2qR WHERE mt LIKE N'DBCODE=GEN[_]002|%')
       OR NOT EXISTS (SELECT 1 FROM #b2qR WHERE mt LIKE N'DBCODE=SEC[_]001|%')
        THROW 57480, 'TEST FAILED CULM001_B2_QR_08: token y PIN a la vez o ninguno AQR_007; desconocido AQR_001; sin ejecutor GEN_002; docente SEC_001.', 1;
    TRUNCATE TABLE #b2qR;
    -- cerrar el QR de tA (la toma sigue abierta), dos veces (idempotente AQR_013); el token cerrado responde AQR_001
    INSERT INTO #b2qX EXEC dbo.usp_cerrar_qr_toma @idToma = @tA, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    INSERT INTO #b2qX EXEC dbo.usp_cerrar_qr_toma @idToma = @tA, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    INSERT INTO #b2qX EXEC dbo.usp_cerrar_qr_toma @idToma = @tA, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD2;
    IF (SELECT COUNT(*) FROM #b2qX WHERE estado = 1 AND mt LIKE N'DBCODE=AQR[_]013|%' AND idToma = @tA AND idSesion = @sA AND idGrupo = @g) <> 2
       OR NOT EXISTS (SELECT 1 FROM #b2qX WHERE estado = 0 AND mt LIKE N'DBCODE=SEC[_]002|%')
       OR EXISTS (SELECT 1 FROM dbo.TokenAsistenciaToma WHERE toma = @tA AND fechaCierreUtc IS NULL)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_toma_asistencia WHERE idToma = @tA AND estaAbierta = 1 AND tieneQrActivo = 0)
        THROW 57481, 'TEST FAILED CULM001_B2_QR_08: usp_cerrar_qr_toma debe cerrar el token (AQR_013, idempotente) sin cerrar la toma.', 1;
    TRUNCATE TABLE #b2qX;
    INSERT INTO #b2qR EXEC dbo.usp_registrar_asistencia_por_token @tokenHash = @h4, @idCorrelacion = @corr, @idUsuarioEjecutor = @uE9;
    INSERT INTO #b2qR EXEC dbo.usp_registrar_asistencia_por_token @pin = @p4, @idCorrelacion = @corr, @idUsuarioEjecutor = @uE9;
    IF (SELECT COUNT(*) FROM #b2qR WHERE estado = 0 AND mt LIKE N'DBCODE=AQR[_]001|%' AND mu = @msgAqr001) <> 2
        THROW 57482, 'TEST FAILED CULM001_B2_QR_08: un token o PIN cerrado debe responder AQR_001 con el mismo mensaje que uno desconocido.', 1;
    TRUNCATE TABLE #b2qR;
    PRINT 'TEST_PASS:CULM001_B2_QR_08_ENTRADAS_Y_TOKEN_CERRADO';

    -- --------------------------------------------------------------------------------------------------------
    -- B2-QR-10: sesion cancelada con token activo => SES_010 en el registro; toma cerrada con token => AQR_005
    -- --------------------------------------------------------------------------------------------------------
    INSERT dbo.SesionCancelacion (sesion, tipoCancelacion, motivo, diaFestivo, usuarioEjecutor, idCorrelacion)
    VALUES (@sB, @tipoManual, N'CULMB2 cancelada con QR activo', NULL, @uD1, NEWID());
    SET @corr = NEWID();
    INSERT INTO #b2qR EXEC dbo.usp_registrar_asistencia_por_token @tokenHash = @h3, @idCorrelacion = @corr, @idUsuarioEjecutor = @uE1;
    IF NOT EXISTS (SELECT 1 FROM #b2qR WHERE estado = 0 AND mt LIKE N'DBCODE=SES[_]010|%')
       OR EXISTS (SELECT 1 FROM dbo.Asistencia WHERE sesion = @sB)
        THROW 57500, 'TEST FAILED CULM001_B2_QR_10: con la sesion cancelada el registro por token debe responder SES_010 sin escribir.', 1;
    TRUNCATE TABLE #b2qR;
    DELETE FROM dbo.SesionCancelacion WHERE sesion = @sB;
    UPDATE dbo.TomaAsistencia SET estado = @estCerrada, fechaCierreUtc = SYSUTCDATETIME() WHERE id = @tB;
    INSERT INTO #b2qR EXEC dbo.usp_registrar_asistencia_por_token @tokenHash = @h3, @idCorrelacion = @corr, @idUsuarioEjecutor = @uE1;
    IF NOT EXISTS (SELECT 1 FROM #b2qR WHERE estado = 0 AND mt LIKE N'DBCODE=AQR[_]005|%') OR EXISTS (SELECT 1 FROM dbo.Asistencia WHERE sesion = @sB)
        THROW 57501, 'TEST FAILED CULM001_B2_QR_10: con la toma cerrada el registro por token debe responder AQR_005 sin escribir.', 1;
    TRUNCATE TABLE #b2qR;
    PRINT 'TEST_PASS:CULM001_B2_QR_10_SESION_CANCELADA';

    -- Invariantes del QR: a lo sumo un token activo por toma; PIN activo unico; nunca el token en claro
    IF EXISTS (SELECT toma FROM dbo.TokenAsistenciaToma WHERE fechaCierreUtc IS NULL GROUP BY toma HAVING COUNT(*) > 1)
       OR EXISTS (SELECT pin FROM dbo.TokenAsistenciaToma WHERE fechaCierreUtc IS NULL GROUP BY pin HAVING COUNT(*) > 1)
       OR EXISTS (SELECT 1 FROM dbo.TokenAsistenciaToma WHERE DATALENGTH(tokenHash) <> 32)
        THROW 57510, 'TEST FAILED CULM001_B2_QR_INV: invariantes de TokenAsistenciaToma violados.', 1;
    PRINT 'TEST_PASS:CULM001_B2_QR_INVARIANTES';

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @err NVARCHAR(4000) = ERROR_MESSAGE();
    PRINT CONCAT('TEST FAILED: ', @err);
    THROW;
END CATCH;
GO

IF @@TRANCOUNT <> 0
    THROW 57599, 'TEST FAILED CULM001_B2_QR: @@TRANCOUNT distinto de 0 al terminar.', 1;
PRINT 'TEST_PASS:CULM001_B2_QR_TRANCOUNT_ZERO';
PRINT 'TEST END: test_culm001_b2_qr';
GO
