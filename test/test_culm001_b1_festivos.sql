USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- CULM-001 B.1 (CONTRACT §2.2, §2.5, §2.7.4..§2.7.7, §2.16.1 B1-FES-01..13): festivos de Colombia como SSOT en
-- dbo.DiaFestivo (la BD nunca llama a internet: el backend entrega el JSON), aplicacion a las sesiones (cancelacion
-- automatica FESTIVO solo sin asistencia), generacion v2 y precarga con festivos cancelados.
-- Oraculo: tabla §3.4.1 del contrato (19 festivos de 2026 y 19 de 2027: fijos, trasladados al lunes, de Pascua y
-- Chiquinquira). Todo corre en una transaccion revertida; B1-FES-05, 07 (tupla), 08a y 08b los ejecuta
-- test/test_culm001_b1.ps1 porque requieren dos conexiones o leer la tupla de un SP que usa INSERT ... EXEC.
PRINT 'TEST START: test_culm001_b1_festivos (CULM-001 B.1)';

IF OBJECT_ID(N'dbo.DiaFestivo', N'U') IS NULL OR OBJECT_ID(N'dbo.CargaDiaFestivo', N'U') IS NULL
   OR OBJECT_ID(N'dbo.uv_dia_festivo', N'V') IS NULL OR OBJECT_ID(N'dbo.uv_carga_dia_festivo', N'V') IS NULL
   OR OBJECT_ID(N'dbo.usp_internal_cargar_dias_festivos', N'P') IS NULL OR OBJECT_ID(N'dbo.usp_cargar_dias_festivos', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_cargar_dias_festivos_automatico', N'P') IS NULL OR OBJECT_ID(N'dbo.usp_internal_aplicar_festivos_grupo', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_aplicar_festivos_grupo', N'P') IS NULL OR OBJECT_ID(N'dbo.usp_aplicar_festivos_periodo', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_aplicar_festivos_automatico', N'P') IS NULL OR OBJECT_ID(N'dbo.usp_consultar_sesiones_festivo_con_asistencia_paginado', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_consultar_dias_festivos', N'P') IS NULL OR OBJECT_ID(N'dbo.usp_consultar_carga_festivos_anio', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_generar_sesiones_grupo_v2', N'P') IS NULL
    THROW 57200, 'TEST FAILED CULM001_B1_FES_00: faltan objetos de festivos de B.1 (tablas, vistas o SP).', 1;
IF EXISTS (SELECT 1 FROM (VALUES ('HABILITADO'), ('PROVEEDOR_PRINCIPAL'), ('ORDEN_RESPALDO'), ('FUENTES_VALIDAS'), ('URL_CALENDARIOS_NACIONALES'),
                                 ('URL_FERIADOS_IO'), ('NOMBRE_SECRETO_FERIADOS_IO'), ('TIMEOUT_SEGUNDOS'), ('ANIOS_ADELANTE'), ('ANIO_MINIMO'),
                                 ('ANIO_MAXIMO'), ('MINIMO_POR_ANIO'), ('MAXIMO_POR_ANIO'), ('PREFIJO_MOTIVO_CANCELACION'), ('ATRIBUCION_TEXTO'),
                                 ('ATRIBUCION_URL')) c(clave)
           WHERE NOT EXISTS (SELECT 1 FROM dbo.uv_parametro p WHERE p.grupo = 'FESTIVOS' AND p.clave = c.clave))
   OR dbo.ufn_obtener_parametro('FESTIVOS', 'PREFIJO_MOTIVO_CANCELACION') <> N'Día festivo: '
   OR dbo.ufn_obtener_parametro('FESTIVOS', 'FUENTES_VALIDAS') <> N'CALENDARIOS_NACIONALES,FERIADOS_IO,CALCULO_LOCAL'
   OR dbo.ufn_obtener_parametro_int(NULL, 'FESTIVOS', 'MINIMO_POR_ANIO') <> 15 OR dbo.ufn_obtener_parametro_int(NULL, 'FESTIVOS', 'MAXIMO_POR_ANIO') <> 25
   OR dbo.ufn_obtener_parametro_int(NULL, 'FESTIVOS', 'ANIO_MINIMO') <> 2000 OR dbo.ufn_obtener_parametro_int(NULL, 'FESTIVOS', 'ANIO_MAXIMO') <> 2100
    THROW 57201, 'TEST FAILED CULM001_B1_FES_00: parametros FESTIVOS/* ausentes o distintos de la semilla del contrato (§2.11).', 1;
IF EXISTS (SELECT 1 FROM (VALUES ('FES_001'), ('FES_002'), ('FES_003'), ('FES_004'), ('FES_005'), ('FES_006'), ('FES_007'), ('FES_008'), ('FES_009'), ('FES_010')) c(codigo)
           WHERE NOT EXISTS (SELECT 1 FROM dbo.uv_mensaje_usuario u WHERE u.codigo = c.codigo)
              OR NOT EXISTS (SELECT 1 FROM dbo.uv_mensaje_tecnico t WHERE t.codigo = c.codigo))
    THROW 57202, 'TEST FAILED CULM001_B1_FES_00: mensajes FES_001..FES_010 ausentes.', 1;
-- El SP congelado no usa INSERT ... EXEC (requisito del v2, §2.7.6 paso 1): ninguna sentencia INSERT termina en EXEC
IF EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_generar_sesiones_grupo')
           AND (definition LIKE N'%INSERT INTO @%EXEC dbo.usp[_]generar%' OR definition LIKE N'%INSERT INTO #%' ))
    THROW 57203, 'TEST FAILED CULM001_B1_FES_00: usp_generar_sesiones_grupo usa INSERT ... EXEC o tablas temporales.', 1;
PRINT 'TEST_PASS:CULM001_B1_FES_00_OBJETOS_Y_SEMILLAS';
GO

DECLARE @zona SYSNAME = dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER');
DECLARE @prefijo NVARCHAR(200) = dbo.ufn_obtener_parametro('FESTIVOS', 'PREFIJO_MOTIVO_CANCELACION');
DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @uAdmin UNIQUEIDENTIFIER, @idInstitucion UNIQUEIDENTIFIER;
SELECT TOP 1 @uAdmin = a.usuario, @idInstitucion = a.institucion
FROM dbo.Administrador a JOIN dbo.uv_usuario u ON u.id = a.usuario WHERE u.estaActivoUsuario = 1 ORDER BY a.id;
DECLARE @idAsig UNIQUEIDENTIFIER = (
    SELECT TOP 1 a.id FROM dbo.uv_asignatura a
    INNER JOIN dbo.uv_semestre_plan_estudio spe ON a.idSemestrePlanEstudio = spe.id
    INNER JOIN dbo.uv_plan_estudio pe ON spe.idPlanEstudio = pe.id
    INNER JOIN dbo.uv_programa pr ON pe.idPrograma = pr.id
    WHERE pr.idInstitucion = @idInstitucion AND a.estaActivaAsignatura = 1 ORDER BY a.id);
DECLARE @estadoA UNIQUEIDENTIFIER = (SELECT id FROM dbo.uv_estado_estudiante_grupo WHERE codigo = 'A');
IF @zona IS NULL OR @tipoCC IS NULL OR @uAdmin IS NULL OR @idInstitucion IS NULL OR @idAsig IS NULL OR @estadoA IS NULL
    THROW 57210, 'TEST FAILED CULM001_B1_FES: faltan fixtures del seed (administrador activo, asignatura de su institucion, zona horaria).', 1;

-- Oraculo §3.4.1 (19 festivos por anio)
CREATE TABLE #culm1Esp (fecha DATE NOT NULL PRIMARY KEY, nombre NVARCHAR(120) NOT NULL);
INSERT INTO #culm1Esp (fecha, nombre) VALUES
    ('2026-01-01', N'Año Nuevo'), ('2026-01-12', N'Reyes Magos'), ('2026-03-23', N'San José'), ('2026-04-02', N'Jueves Santo'),
    ('2026-04-03', N'Viernes Santo'), ('2026-05-01', N'Día del Trabajo'), ('2026-05-18', N'Ascensión del Señor'), ('2026-06-08', N'Corpus Christi'),
    ('2026-06-15', N'Sagrado Corazón'), ('2026-06-29', N'San Pedro y San Pablo'), ('2026-07-13', N'Nuestra Señora del Rosario de Chiquinquirá'),
    ('2026-07-20', N'Independencia'), ('2026-08-07', N'Batalla de Boyacá'), ('2026-08-17', N'Asunción de la Virgen'), ('2026-10-12', N'Día de la Raza'),
    ('2026-11-02', N'Todos los Santos'), ('2026-11-16', N'Independencia de Cartagena'), ('2026-12-08', N'Inmaculada Concepción'), ('2026-12-25', N'Navidad'),
    ('2027-01-01', N'Año Nuevo'), ('2027-01-11', N'Reyes Magos'), ('2027-03-22', N'San José'), ('2027-03-25', N'Jueves Santo'),
    ('2027-03-26', N'Viernes Santo'), ('2027-05-01', N'Día del Trabajo'), ('2027-05-10', N'Ascensión del Señor'), ('2027-05-31', N'Corpus Christi'),
    ('2027-06-07', N'Sagrado Corazón'), ('2027-07-05', N'San Pedro y San Pablo'), ('2027-07-12', N'Nuestra Señora del Rosario de Chiquinquirá'),
    ('2027-07-20', N'Independencia'), ('2027-08-07', N'Batalla de Boyacá'), ('2027-08-16', N'Asunción de la Virgen'), ('2027-10-18', N'Día de la Raza'),
    ('2027-11-01', N'Todos los Santos'), ('2027-11-15', N'Independencia de Cartagena'), ('2027-12-08', N'Inmaculada Concepción'), ('2027-12-25', N'Navidad');
DECLARE @json2026 NVARCHAR(MAX) = (SELECT fecha = CONVERT(CHAR(10), fecha, 23), nombre FROM #culm1Esp WHERE YEAR(fecha) = 2026 ORDER BY fecha FOR JSON PATH);
DECLARE @json2027 NVARCHAR(MAX) = (SELECT fecha = CONVERT(CHAR(10), fecha, 23), nombre FROM #culm1Esp WHERE YEAR(fecha) = 2027 ORDER BY fecha FOR JSON PATH);
DECLARE @json2026SinRaza NVARCHAR(MAX) = (SELECT fecha = CONVERT(CHAR(10), fecha, 23), nombre FROM #culm1Esp WHERE YEAR(fecha) = 2026 AND fecha <> '2026-10-12' ORDER BY fecha FOR JSON PATH);

CREATE TABLE #culm1Carga (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(4000) NULL, mensajeTecnicoResultado NVARCHAR(4000) NULL, estadoResultado BIT NOT NULL,
    anio INT NULL, totalFestivos INT NULL, festivosInsertados INT NULL, festivosActualizados INT NULL, festivosDesactivados INT NULL);
CREATE TABLE #culm1AplGrupo (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(4000) NULL, mensajeTecnicoResultado NVARCHAR(4000) NULL, estadoResultado BIT NOT NULL,
    sesionesCanceladas INT NULL, sesionesConAsistencia INT NULL);
CREATE TABLE #culm1AplPeriodo (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(4000) NULL, mensajeTecnicoResultado NVARCHAR(4000) NULL, estadoResultado BIT NOT NULL,
    gruposProcesados INT NULL, sesionesCanceladas INT NULL, sesionesConAsistencia INT NULL);
CREATE TABLE #culm1Precarga (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(4000) NULL, mensajeTecnicoResultado NVARCHAR(4000) NULL, estadoResultado BIT NOT NULL);
CREATE TABLE #culm1Dias (id UNIQUEIDENTIFIER, fecha DATE, anio SMALLINT, nombre NVARCHAR(120), fuente NVARCHAR(40), estaActivo BIT, fechaCargaUtc DATETIME2(0),
    idCorrelacionCarga UNIQUEIDENTIFIER, fuenteUltimaCarga NVARCHAR(40), fechaUltimaCargaUtc DATETIME2(0), diferenciasCalculoLocal INT, totalRegistros INT);
CREATE TABLE #culm1SesFest (idSesion UNIQUEIDENTIFIER, idGrupo UNIQUEIDENTIFIER, nombreGrupo NVARCHAR(300), nombreAsignatura NVARCHAR(200), nombreDocente NVARCHAR(400),
    fechaHoraInicio DATETIME2, fecha DATE, nombreFestivo NVARCHAR(120), totalTomas INT, totalRegistrosAsistencia INT, totalRegistros INT);
CREATE TABLE #culm1CargaAnio (anio INT, totalActivos INT, fuenteUltimaCarga NVARCHAR(40), fechaUltimaCargaUtc DATETIME2(0));

DECLARE @corr UNIQUEIDENTIFIER, @userMsg NVARCHAR(4000), @techMsg NVARCHAR(4000), @err NVARCHAR(4000);
DECLARE @cargasAntes INT, @activosAntes INT;

BEGIN TRANSACTION;
BEGIN TRY
    -- Estado limpio de 2026/2027 dentro de la transaccion (se restaura con el ROLLBACK final)
    DELETE sc FROM dbo.SesionCancelacion sc JOIN dbo.DiaFestivo df ON df.id = sc.diaFestivo WHERE df.anio IN (2026, 2027);
    DELETE FROM dbo.CargaDiaFestivo WHERE anio IN (2026, 2027);
    DELETE FROM dbo.DiaFestivo WHERE anio IN (2026, 2027);

    -- Fixture: docente titular, estudiante activo, administrador de otra institucion
    DECLARE @tag NVARCHAR(12) = LEFT(REPLACE(CONVERT(NVARCHAR(36), NEWID()), N'-', N''), 12);
    DECLARE @uD1 UNIQUEIDENTIFIER = NEWID(), @d1 UNIQUEIDENTIFIER = NEWID(), @uE1 UNIQUEIDENTIFIER = NEWID(), @e1 UNIQUEIDENTIFIER = NEWID();
    DECLARE @uAdminOtro UNIQUEIDENTIFIER = NEWID(), @instOtra UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uD1, @tipoCC, 986000000 + ABS(CHECKSUM(NEWID()) % 999999), N'Festivo', N'Culm', N'Fabio', N'B1', CONCAT(N'culm1.fd1.', @tag, N'@test.local'), 1, 1, N'HashBackend_CULM1'),
           (@uE1, @tipoCC, 987000000 + ABS(CHECKSUM(NEWID()) % 999999), N'Festivo', N'Culm', N'Flor', N'B1', CONCAT(N'culm1.fe1.', @tag, N'@test.local'), 1, 1, N'HashBackend_CULM1'),
           (@uAdminOtro, @tipoCC, 988000000 + ABS(CHECKSUM(NEWID()) % 999999), N'Admin', N'Otra', N'Olga', N'B1', CONCAT(N'culm1.adm.', @tag, N'@test.local'), 1, 1, N'HashBackend_CULM1');
    INSERT INTO dbo.Docente (id, usuario) VALUES (@d1, @uD1);
    INSERT INTO dbo.Estudiante (id, usuario) VALUES (@e1, @uE1);
    INSERT INTO dbo.Institucion (id, nombre, estado) VALUES (@instOtra, CONCAT(N'CULM1 Institucion ', @tag), 1);
    INSERT INTO dbo.Administrador (id, usuario, institucion) VALUES (NEWID(), @uAdminOtro, @instOtra);

    -- ========================================================================================================
    -- B1-FES-01: carga 2026 con los 19 festivos del calculo local
    -- ========================================================================================================
    SET @corr = NEWID();
    INSERT INTO #culm1Carga EXEC dbo.usp_cargar_dias_festivos @anio = 2026, @festivosJSON = @json2026, @fuente = N'CALCULO_LOCAL',
        @diferenciasCalculoLocal = 0, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'FES_005', @p_param1 = N'19', @p_param2 = N'2026', @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    IF NOT EXISTS (SELECT 1 FROM #culm1Carga WHERE estadoResultado = 1 AND idCorrelacion = @corr AND mensajeTecnicoResultado LIKE N'DBCODE=FES[_]005|%'
                   AND mensajeUsuarioResultado = @userMsg AND anio = 2026 AND totalFestivos = 19 AND festivosInsertados = 19
                   AND festivosActualizados = 0 AND festivosDesactivados = 0)
        THROW 57220, 'TEST FAILED CULM001_B1_FES_01: la carga 2026 debe responder FES_005 con 19 insertados.', 1;
    IF (SELECT COUNT(*) FROM dbo.uv_dia_festivo WHERE anio = 2026 AND estaActivo = 1) <> 19
       OR EXISTS (SELECT 1 FROM #culm1Esp e WHERE YEAR(e.fecha) = 2026 AND NOT EXISTS (
                    SELECT 1 FROM dbo.uv_dia_festivo d WHERE d.fecha = e.fecha AND d.nombre = e.nombre AND d.fuente = N'CALCULO_LOCAL'
                    AND d.estaActivo = 1 AND d.idCorrelacionCarga = @corr))
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_carga_dia_festivo WHERE anio = 2026 AND fuente = N'CALCULO_LOCAL' AND totalFestivos = 19
                      AND festivosInsertados = 19 AND idUsuarioEjecutor = @uAdmin AND idCorrelacion = @corr AND esUltimaCargaAnio = 1
                      AND fechaCargaUtc >= DATEADD(MINUTE, -5, SYSUTCDATETIME()))
        THROW 57221, 'TEST FAILED CULM001_B1_FES_01: DiaFestivo/CargaDiaFestivo no reflejan la carga 2026 (fechas, nombres, fuente, bitacora).', 1;
    TRUNCATE TABLE #culm1Carga;
    PRINT 'TEST_PASS:CULM001_B1_FES_01_CARGA_2026';

    -- ========================================================================================================
    -- B1-FES-02: misma carga dos veces => mismo conjunto activo, 0 insertados la segunda vez
    -- ========================================================================================================
    SET @corr = NEWID();
    INSERT INTO #culm1Carga EXEC dbo.usp_cargar_dias_festivos @anio = 2026, @festivosJSON = @json2026, @fuente = N'CALENDARIOS_NACIONALES',
        @diferenciasCalculoLocal = 0, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    IF NOT EXISTS (SELECT 1 FROM #culm1Carga WHERE estadoResultado = 1 AND festivosInsertados = 0 AND festivosActualizados = 19 AND festivosDesactivados = 0 AND totalFestivos = 19)
       OR (SELECT COUNT(*) FROM dbo.DiaFestivo WHERE anio = 2026) <> 19
       OR (SELECT COUNT(*) FROM dbo.DiaFestivo WHERE anio = 2026 AND estaActivo = 1 AND fuente = N'CALENDARIOS_NACIONALES') <> 19
       OR (SELECT COUNT(*) FROM dbo.CargaDiaFestivo WHERE anio = 2026) <> 2
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_carga_dia_festivo WHERE anio = 2026 AND idCorrelacion = @corr AND esUltimaCargaAnio = 1)
       OR (SELECT COUNT(*) FROM dbo.uv_carga_dia_festivo WHERE anio = 2026 AND esUltimaCargaAnio = 1) <> 1
        THROW 57222, 'TEST FAILED CULM001_B1_FES_02: la segunda carga debe ser idempotente (0 insertados, 19 actualizados, mismo conjunto).', 1;
    TRUNCATE TABLE #culm1Carga;
    PRINT 'TEST_PASS:CULM001_B1_FES_02_CARGA_IDEMPOTENTE';

    -- Carga automatica 2027 (job: sin usuario)
    SET @corr = NEWID();
    INSERT INTO #culm1Carga EXEC dbo.usp_cargar_dias_festivos_automatico @anio = 2027, @festivosJSON = @json2027, @fuente = N'CALCULO_LOCAL',
        @diferenciasCalculoLocal = 2, @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #culm1Carga WHERE estadoResultado = 1 AND festivosInsertados = 19 AND anio = 2027)
       OR NOT EXISTS (SELECT 1 FROM dbo.CargaDiaFestivo WHERE anio = 2027 AND usuarioEjecutor IS NULL AND diferenciasCalculoLocal = 2 AND idCorrelacion = @corr)
        THROW 57223, 'TEST FAILED CULM001_B1_FES_AUTO: la carga automatica 2027 debe insertar 19 sin usuario ejecutor.', 1;
    TRUNCATE TABLE #culm1Carga;
    PRINT 'TEST_PASS:CULM001_B1_FES_CARGA_AUTOMATICA';

    -- ========================================================================================================
    -- B1-FES-04: entradas invalidas => FES_002/FES_002/FES_002/FES_003/FES_004/FES_001 sin escrituras; RBAC
    -- ========================================================================================================
    SELECT @cargasAntes = (SELECT COUNT(*) FROM dbo.CargaDiaFestivo), @activosAntes = (SELECT COUNT(*) FROM dbo.DiaFestivo WHERE estaActivo = 1);
    DECLARE @jsonExtra NVARCHAR(MAX) = REPLACE(@json2026, N'"nombre":"Navidad"', N'"nombre":"Navidad","tipo":"nacional"');
    DECLARE @jsonOtroAnio NVARCHAR(MAX) = REPLACE(@json2026, N'"2026-12-25"', N'"2027-12-25"');
    DECLARE @jsonRepetida NVARCHAR(MAX) = REPLACE(@json2026, N'"2026-12-25"', N'"2026-12-08"');
    DECLARE @json5 NVARCHAR(MAX) = (SELECT TOP 5 fecha = CONVERT(CHAR(10), fecha, 23), nombre FROM #culm1Esp WHERE YEAR(fecha) = 2026 ORDER BY fecha FOR JSON PATH);
    DECLARE @jsonNombreVacio NVARCHAR(MAX) = REPLACE(@json2026, N'"nombre":"Navidad"', N'"nombre":"   "');
    DECLARE @json1999 NVARCHAR(MAX) = REPLACE(@json2026, N'"2026-', N'"1999-');
    SET @corr = NEWID();
    INSERT INTO #culm1Carga EXEC dbo.usp_cargar_dias_festivos @anio = 2026, @festivosJSON = @jsonExtra, @fuente = N'CALCULO_LOCAL', @diferenciasCalculoLocal = 0, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    INSERT INTO #culm1Carga EXEC dbo.usp_cargar_dias_festivos @anio = 2026, @festivosJSON = @jsonOtroAnio, @fuente = N'CALCULO_LOCAL', @diferenciasCalculoLocal = 0, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    INSERT INTO #culm1Carga EXEC dbo.usp_cargar_dias_festivos @anio = 2026, @festivosJSON = @jsonRepetida, @fuente = N'CALCULO_LOCAL', @diferenciasCalculoLocal = 0, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    INSERT INTO #culm1Carga EXEC dbo.usp_cargar_dias_festivos @anio = 2026, @festivosJSON = @jsonNombreVacio, @fuente = N'CALCULO_LOCAL', @diferenciasCalculoLocal = 0, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    INSERT INTO #culm1Carga EXEC dbo.usp_cargar_dias_festivos @anio = 2026, @festivosJSON = N'esto no es json', @fuente = N'CALCULO_LOCAL', @diferenciasCalculoLocal = 0, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    INSERT INTO #culm1Carga EXEC dbo.usp_cargar_dias_festivos @anio = 2026, @festivosJSON = @json2026, @fuente = N'CALCULO_LOCAL', @diferenciasCalculoLocal = -1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    IF (SELECT COUNT(*) FROM #culm1Carga WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=FES[_]002|%' AND anio IS NULL) <> 6
        THROW 57240, 'TEST FAILED CULM001_B1_FES_04: clave extra, fecha de otro anio, fecha repetida, nombre vacio, JSON invalido y diferencias < 0 deben responder FES_002.', 1;
    TRUNCATE TABLE #culm1Carga;
    INSERT INTO #culm1Carga EXEC dbo.usp_cargar_dias_festivos @anio = 2026, @festivosJSON = @json5, @fuente = N'CALCULO_LOCAL', @diferenciasCalculoLocal = 0, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    IF NOT EXISTS (SELECT 1 FROM #culm1Carga WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=FES[_]003|%')
        THROW 57241, 'TEST FAILED CULM001_B1_FES_04: 5 festivos deben responder FES_003.', 1;
    TRUNCATE TABLE #culm1Carga;
    INSERT INTO #culm1Carga EXEC dbo.usp_cargar_dias_festivos @anio = 2026, @festivosJSON = @json2026, @fuente = N'GOOGLE', @diferenciasCalculoLocal = 0, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    IF NOT EXISTS (SELECT 1 FROM #culm1Carga WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=FES[_]004|%')
        THROW 57242, 'TEST FAILED CULM001_B1_FES_04: una fuente desconocida debe responder FES_004.', 1;
    TRUNCATE TABLE #culm1Carga;
    INSERT INTO #culm1Carga EXEC dbo.usp_cargar_dias_festivos @anio = 1999, @festivosJSON = @json1999, @fuente = N'CALCULO_LOCAL', @diferenciasCalculoLocal = 0, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    IF NOT EXISTS (SELECT 1 FROM #culm1Carga WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=FES[_]001|%')
        THROW 57243, 'TEST FAILED CULM001_B1_FES_04: el anio 1999 debe responder FES_001.', 1;
    TRUNCATE TABLE #culm1Carga;
    INSERT INTO #culm1Carga EXEC dbo.usp_cargar_dias_festivos @anio = 2026, @festivosJSON = @json2026, @fuente = N'CALCULO_LOCAL', @diferenciasCalculoLocal = 0, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    INSERT INTO #culm1Carga EXEC dbo.usp_cargar_dias_festivos @anio = 2026, @festivosJSON = @json2026, @fuente = N'CALCULO_LOCAL', @diferenciasCalculoLocal = 0, @idCorrelacion = @corr, @idUsuarioEjecutor = NULL;
    IF NOT EXISTS (SELECT 1 FROM #culm1Carga WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SEC[_]001|%')
       OR NOT EXISTS (SELECT 1 FROM #culm1Carga WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=GEN[_]002|%')
        THROW 57244, 'TEST FAILED CULM001_B1_FES_04: un docente (SEC_001) o un ejecutor NULL (GEN_002) no pueden cargar festivos.', 1;
    IF (SELECT COUNT(*) FROM dbo.CargaDiaFestivo) <> @cargasAntes OR (SELECT COUNT(*) FROM dbo.DiaFestivo WHERE estaActivo = 1) <> @activosAntes
        THROW 57245, 'TEST FAILED CULM001_B1_FES_04: una carga rechazada escribio en DiaFestivo o CargaDiaFestivo.', 1;
    TRUNCATE TABLE #culm1Carga;
    PRINT 'TEST_PASS:CULM001_B1_FES_04_ENTRADAS_INVALIDAS';

    -- ========================================================================================================
    -- B1-FES-06 / B1-FES-07 / B1-FES-08c: generacion v2 de 2026-2027 (todos los dias 08:00-09:00 hora local)
    -- dentro de una transaccion externa. Cada una de las 38 fechas nace cancelada; el dia anterior y el siguiente no.
    -- ========================================================================================================
    DECLARE @per1 UNIQUEIDENTIFIER = NEWID(), @g1 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@per1, @idInstitucion, N'CULM1 periodo festivos 2026-2027', 3200000 + ABS(CHECKSUM(NEWID()) % 700000), '2026-01-01', '2027-12-31', 2026);
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
        cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@g1, @idAsig, @per1, 941000 + ABS(CHECKSUM(NEWID()) % 58999), N'CULM1 Grupo festivos v2', 30, 0, 0, 0, @d1);
    INSERT INTO dbo.Horario (id, grupo, dia, horaInicio, horaFin) SELECT NEWID(), @g1, id, '08:00', '09:00' FROM dbo.uv_dia;

    SET @corr = NEWID();
    EXEC dbo.usp_generar_sesiones_grupo_v2 @idGrupo = @g1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF @@TRANCOUNT <> 1
        THROW 57260, 'TEST FAILED CULM001_B1_FES_08C: la generacion v2 dentro de una transaccion externa altero @@TRANCOUNT.', 1;
    IF (SELECT COUNT(*) FROM dbo.Sesion WHERE grupo = @g1) <> 730
        THROW 57261, 'TEST FAILED CULM001_B1_FES_08C: la generacion v2 debe crear las 730 sesiones de 2026-2027 en la transaccion externa.', 1;
    PRINT 'TEST_PASS:CULM001_B1_FES_08C_RUTA_FELIZ_TRANSACCION_EXTERNA';

    IF EXISTS (
        SELECT 1 FROM #culm1Esp e
        WHERE NOT EXISTS (
            SELECT 1 FROM dbo.Sesion s
            JOIN dbo.SesionCancelacion sc ON sc.sesion = s.id
            JOIN dbo.TipoCancelacionSesion t ON t.id = sc.tipoCancelacion
            JOIN dbo.DiaFestivo df ON df.id = sc.diaFestivo
            WHERE s.grupo = @g1
              AND CAST((s.fechaHoraInicio AT TIME ZONE 'UTC') AT TIME ZONE @zona AS DATE) = e.fecha
              AND t.esAutomatica = 1 AND df.fecha = e.fecha AND sc.usuarioEjecutor IS NULL
              AND sc.motivo = CONCAT(@prefijo, e.nombre)))
        THROW 57262, 'TEST FAILED CULM001_B1_FES_06: alguna de las 38 fechas festivas de 2026-2027 no nacio cancelada con motivo "Día festivo: <nombre>".', 1;
    IF (SELECT COUNT(*) FROM dbo.SesionCancelacion sc JOIN dbo.Sesion s ON s.id = sc.sesion WHERE s.grupo = @g1) <> 38
        THROW 57263, 'TEST FAILED CULM001_B1_FES_06: la generacion debe cancelar exactamente 38 sesiones (una por festivo).', 1;
    IF EXISTS (
        SELECT 1 FROM #culm1Esp e
        CROSS APPLY (VALUES (DATEADD(DAY, -1, e.fecha)), (DATEADD(DAY, 1, e.fecha))) v(f)
        JOIN dbo.Sesion s ON s.grupo = @g1 AND CAST((s.fechaHoraInicio AT TIME ZONE 'UTC') AT TIME ZONE @zona AS DATE) = v.f
        WHERE NOT EXISTS (SELECT 1 FROM #culm1Esp x WHERE x.fecha = v.f)
          AND EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc WHERE sc.sesion = s.id))
       OR (SELECT COUNT(*) FROM #culm1Esp e CROSS APPLY (VALUES (DATEADD(DAY, -1, e.fecha)), (DATEADD(DAY, 1, e.fecha))) v(f)
           JOIN dbo.Sesion s ON s.grupo = @g1 AND CAST((s.fechaHoraInicio AT TIME ZONE 'UTC') AT TIME ZONE @zona AS DATE) = v.f
           WHERE NOT EXISTS (SELECT 1 FROM #culm1Esp x WHERE x.fecha = v.f)) < 60
        THROW 57264, 'TEST FAILED CULM001_B1_FES_06: una sesion del dia anterior o siguiente a un festivo quedo cancelada.', 1;
    IF EXISTS (SELECT 1 FROM dbo.uv_sesion_estado v JOIN #culm1Esp e ON e.fecha = CAST((v.fechaHoraInicio AT TIME ZONE 'UTC') AT TIME ZONE @zona AS DATE)
               WHERE v.idGrupo = @g1 AND (v.estaCancelada = 0 OR v.codigoTipoCancelacion <> N'FESTIVO' OR v.esCancelacionAutomatica = 0 OR v.nombreDiaFestivo <> e.nombre))
        THROW 57265, 'TEST FAILED CULM001_B1_FES_06: uv_sesion_estado no expone la cancelacion FESTIVO con el nombre del festivo.', 1;
    IF EXISTS (SELECT 1 FROM dbo.uv_cumplimiento_sesion_grupo c JOIN dbo.SesionCancelacion sc ON sc.sesion = c.idSesion WHERE c.idGrupo = @g1)
       OR (SELECT COUNT(*) FROM dbo.uv_cumplimiento_sesion_grupo WHERE idGrupo = @g1) <> 730 - 38
        THROW 57266, 'TEST FAILED CULM001_B1_FES_06: las sesiones canceladas por festivo deben salir del cumplimiento.', 1;
    PRINT 'TEST_PASS:CULM001_B1_FES_06_38_FECHAS_2026_2027';

    -- B1-FES-07: segunda ejecucion => 0 sesiones nuevas y 0 cancelaciones nuevas
    SET @corr = NEWID();
    EXEC dbo.usp_generar_sesiones_grupo_v2 @idGrupo = @g1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF (SELECT COUNT(*) FROM dbo.Sesion WHERE grupo = @g1) <> 730
       OR (SELECT COUNT(*) FROM dbo.SesionCancelacion sc JOIN dbo.Sesion s ON s.id = sc.sesion WHERE s.grupo = @g1) <> 38
       OR @@TRANCOUNT <> 1
        THROW 57270, 'TEST FAILED CULM001_B1_FES_07: la segunda generacion v2 debe ser idempotente (0 sesiones y 0 cancelaciones nuevas).', 1;
    PRINT 'TEST_PASS:CULM001_B1_FES_07_GENERACION_IDEMPOTENTE';

    -- ========================================================================================================
    -- B1-FES-03: recarga 2026 sin un festivo => inactivo; la sesion ya cancelada por el no cambia
    -- ========================================================================================================
    DECLARE @sRaza UNIQUEIDENTIFIER = (SELECT s.id FROM dbo.Sesion s WHERE s.grupo = @g1
                                       AND CAST((s.fechaHoraInicio AT TIME ZONE 'UTC') AT TIME ZONE @zona AS DATE) = '2026-10-12');
    DECLARE @idRaza UNIQUEIDENTIFIER = (SELECT id FROM dbo.DiaFestivo WHERE fecha = '2026-10-12');
    SET @corr = NEWID();
    INSERT INTO #culm1Carga EXEC dbo.usp_cargar_dias_festivos @anio = 2026, @festivosJSON = @json2026SinRaza, @fuente = N'CALENDARIOS_NACIONALES',
        @diferenciasCalculoLocal = 1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    IF NOT EXISTS (SELECT 1 FROM #culm1Carga WHERE estadoResultado = 1 AND totalFestivos = 18 AND festivosInsertados = 0 AND festivosActualizados = 18 AND festivosDesactivados = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.DiaFestivo WHERE id = @idRaza AND estaActivo = 0)
       OR (SELECT COUNT(*) FROM dbo.uv_dia_festivo WHERE anio = 2026 AND estaActivo = 1) <> 18
       OR NOT EXISTS (SELECT 1 FROM dbo.SesionCancelacion WHERE sesion = @sRaza AND diaFestivo = @idRaza)
        THROW 57230, 'TEST FAILED CULM001_B1_FES_03: la recarga sin un festivo debe desactivarlo (nunca borrarlo) sin revertir la sesion cancelada.', 1;
    TRUNCATE TABLE #culm1Carga;
    -- Consulta del administrador (con y sin inactivos)
    SET @corr = NEWID();
    INSERT INTO #culm1Dias EXEC dbo.usp_consultar_dias_festivos @idUsuarioEjecutor = @uAdmin, @idCorrelacion = @corr, @anio = 2026;
    IF (SELECT COUNT(*) FROM #culm1Dias) <> 18 OR EXISTS (SELECT 1 FROM #culm1Dias WHERE totalRegistros <> 18 OR estaActivo = 0 OR fuenteUltimaCarga <> N'CALENDARIOS_NACIONALES'
                                                    OR diferenciasCalculoLocal <> 1 OR fechaUltimaCargaUtc IS NULL)
        THROW 57231, 'TEST FAILED CULM001_B1_FES_CONSULTA: usp_consultar_dias_festivos debe listar los 18 activos con la ultima carga.', 1;
    TRUNCATE TABLE #culm1Dias;
    INSERT INTO #culm1Dias EXEC dbo.usp_consultar_dias_festivos @idUsuarioEjecutor = @uAdmin, @idCorrelacion = @corr, @anio = 2026, @incluirInactivos = 1, @numeroPagina = 2, @tamanoPagina = 10;
    IF (SELECT COUNT(*) FROM #culm1Dias) <> 9 OR EXISTS (SELECT 1 FROM #culm1Dias WHERE totalRegistros <> 19)
        THROW 57232, 'TEST FAILED CULM001_B1_FES_CONSULTA: con inactivos la pagina 2 de 10 debe traer 9 de 19 festivos.', 1;
    TRUNCATE TABLE #culm1Dias;
    SET @corr = NEWID();
    INSERT INTO #culm1CargaAnio EXEC dbo.usp_consultar_carga_festivos_anio @anio = 2026, @idCorrelacion = @corr;
    INSERT INTO #culm1CargaAnio EXEC dbo.usp_consultar_carga_festivos_anio @anio = 2099, @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #culm1CargaAnio WHERE anio = 2026 AND totalActivos = 18 AND fuenteUltimaCarga = N'CALENDARIOS_NACIONALES' AND fechaUltimaCargaUtc IS NOT NULL)
       OR NOT EXISTS (SELECT 1 FROM #culm1CargaAnio WHERE anio = 2099 AND totalActivos = 0 AND fuenteUltimaCarga IS NULL)
        THROW 57235, 'TEST FAILED CULM001_B1_FES_CONSULTA: usp_consultar_carga_festivos_anio debe dar 18 activos en 2026 y 0 en un anio sin carga.', 1;
    -- Recarga completa: el festivo vuelve a estar activo (MATCHED => estaActivo = 1)
    SET @corr = NEWID();
    INSERT INTO #culm1Carga EXEC dbo.usp_cargar_dias_festivos @anio = 2026, @festivosJSON = @json2026, @fuente = N'CALENDARIOS_NACIONALES',
        @diferenciasCalculoLocal = 0, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    IF NOT EXISTS (SELECT 1 FROM #culm1Carga WHERE estadoResultado = 1 AND festivosInsertados = 0 AND festivosActualizados = 19 AND festivosDesactivados = 0)
       OR NOT EXISTS (SELECT 1 FROM dbo.DiaFestivo WHERE id = @idRaza AND estaActivo = 1)
        THROW 57236, 'TEST FAILED CULM001_B1_FES_03: la recarga completa debe reactivar el festivo sin crear filas nuevas.', 1;
    TRUNCATE TABLE #culm1Carga;
    PRINT 'TEST_PASS:CULM001_B1_FES_03_RECARGA_DESACTIVA_SIN_REVERTIR';

    -- ========================================================================================================
    -- B1-FES-09: precarga (grupo + horario) en periodo futuro con festivos (2027-03-15..2027-03-31)
    -- ========================================================================================================
    DECLARE @per3 UNIQUEIDENTIFIER = NEWID(), @g3 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@per3, @idInstitucion, N'CULM1 periodo precarga festivos', 3200000 + ABS(CHECKSUM(NEWID()) % 700000), '2027-03-15', '2027-03-31', 2027);
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
        cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@g3, @idAsig, @per3, 941000 + ABS(CHECKSUM(NEWID()) % 58999), N'CULM1 Grupo precarga festivos', 30, 0, 0, 0, @d1);
    INSERT INTO dbo.Horario (id, grupo, dia, horaInicio, horaFin) SELECT NEWID(), @g3, id, '08:00', '09:00' FROM dbo.uv_dia;
    SET @corr = NEWID();
    INSERT INTO #culm1Precarga EXEC dbo.usp_precargar_sesiones_grupo @idGrupo = @g3, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF NOT EXISTS (SELECT 1 FROM #culm1Precarga WHERE estadoResultado = 1)
       OR (SELECT COUNT(*) FROM dbo.Sesion WHERE grupo = @g3) <> 17
       OR (SELECT COUNT(*) FROM dbo.uv_sesion_estado WHERE idGrupo = @g3 AND estaCancelada = 1 AND codigoTipoCancelacion = N'FESTIVO') <> 3
       OR EXISTS (SELECT 1 FROM dbo.uv_sesion_estado v WHERE v.idGrupo = @g3 AND v.estaCancelada = 1
                  AND CAST((v.fechaHoraInicio AT TIME ZONE 'UTC') AT TIME ZONE @zona AS DATE) NOT IN ('2027-03-22', '2027-03-25', '2027-03-26'))
        THROW 57290, 'TEST FAILED CULM001_B1_FES_09: la precarga debe crear 17 sesiones y cancelar en la misma transaccion las de 22, 25 y 26 de marzo.', 1;
    TRUNCATE TABLE #culm1Precarga;
    -- El horario deja de tener lunes: la sesion futura cancelada del lunes 22 se borra junto con su SesionCancelacion
    DECLARE @sLunes22 UNIQUEIDENTIFIER = (SELECT s.id FROM dbo.Sesion s WHERE s.grupo = @g3 AND CAST((s.fechaHoraInicio AT TIME ZONE 'UTC') AT TIME ZONE @zona AS DATE) = '2027-03-22');
    DELETE h FROM dbo.Horario h JOIN dbo.uv_dia d ON d.id = h.dia WHERE h.grupo = @g3 AND d.codigo = N'LU';
    SET @corr = NEWID();
    INSERT INTO #culm1Precarga EXEC dbo.usp_precargar_sesiones_grupo @idGrupo = @g3, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF NOT EXISTS (SELECT 1 FROM #culm1Precarga WHERE estadoResultado = 1)
       OR EXISTS (SELECT 1 FROM dbo.Sesion WHERE id = @sLunes22) OR EXISTS (SELECT 1 FROM dbo.SesionCancelacion WHERE sesion = @sLunes22)
       OR (SELECT COUNT(*) FROM dbo.uv_sesion_estado WHERE idGrupo = @g3 AND estaCancelada = 1) <> 2
       OR (SELECT COUNT(*) FROM dbo.Sesion WHERE grupo = @g3) <> 14
        THROW 57291, 'TEST FAILED CULM001_B1_FES_09: el cambio de horario debe borrar la sesion futura cancelada y su SesionCancelacion.', 1;
    TRUNCATE TABLE #culm1Precarga;
    PRINT 'TEST_PASS:CULM001_B1_FES_09_PRECARGA_CON_FESTIVOS';

    -- ========================================================================================================
    -- B1-FES-10 / B1-FES-12 / B1-FES-13: grupo ya creado; aplicar festivos (solo futuras sin asistencia)
    -- ========================================================================================================
    DECLARE @per4 UNIQUEIDENTIFIER = NEWID(), @g4 UNIQUEIDENTIFIER = NEWID(), @eg4 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@per4, @idInstitucion, N'CULM1 periodo aplicar festivos', 3200000 + ABS(CHECKSUM(NEWID()) % 700000), '2026-10-01', '2027-04-30', 2026);
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
        cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@g4, @idAsig, @per4, 941000 + ABS(CHECKSUM(NEWID()) % 58999), N'CULM1 Grupo aplicar festivos', 30, 0, 0, 0, @d1);
    INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo) VALUES (@eg4, @estadoA, @e1, @g4);
    DECLARE @sFutFest UNIQUEIDENTIFIER = NEWID(), @sFutFestAsis UNIQUEIDENTIFIER = NEWID(), @sPasFest UNIQUEIDENTIFIER = NEWID();
    DECLARE @sFutNormal UNIQUEIDENTIFIER = NEWID(), @sNocheAntes UNIQUEIDENTIFIER = NEWID(), @sMadrugada UNIQUEIDENTIFIER = NEWID();
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    VALUES -- 2027-03-22 (San Jose, futuro) 08:00-10:00 Bogota = 13:00-15:00 UTC, sin asistencia => se cancela
           (@sFutFest,     N'CULM1-FES10 futura festivo',      1, N'CULMF1', 1, @g4, '2027-03-22T13:00:00', '2027-03-22T15:00:00', N'UTC_V2'),
           -- 2027-03-25 (Jueves Santo, futuro) con asistencia => no se toca, se reporta
           (@sFutFestAsis, N'CULM1-FES10 futura festivo asis', 2, N'CULMF2', 1, @g4, '2027-03-25T13:00:00', '2027-03-25T15:00:00', N'UTC_V2'),
           -- 2026-10-12 (Dia de la Raza, pasado) sin asistencia => no se toca con @soloFuturas = 1
           (@sPasFest,     N'CULM1-FES10 pasada festivo',      3, N'CULMF3', 1, @g4, '2026-10-12T13:00:00', '2026-10-12T15:00:00', N'UTC_V2'),
           -- 2027-03-23 (dia normal) => no se cancela
           (@sFutNormal,   N'CULM1-FES10 futura normal',       4, N'CULMF4', 1, @g4, '2027-03-23T13:00:00', '2027-03-23T15:00:00', N'UTC_V2'),
           -- B1-FES-13: 2027-03-21 19:00-21:00 Bogota = 2027-03-22 00:00-02:00 UTC (dia del festivo en UTC) => NO se cancela
           (@sNocheAntes,  N'CULM1-FES13 noche antes',         5, N'CULMF5', 1, @g4, '2027-03-22T00:00:00', '2027-03-22T02:00:00', N'UTC_V2'),
           -- B1-FES-13: 2027-03-26 06:00 Bogota (Viernes Santo) = 11:00 UTC => SI se cancela
           (@sMadrugada,   N'CULM1-FES13 madrugada festivo',   6, N'CULMF6', 1, @g4, '2027-03-26T11:00:00', '2027-03-26T12:00:00', N'UTC_V2');
    INSERT dbo.Asistencia (id, estudianteGrupo, sesion) VALUES (NEWID(), @eg4, @sFutFestAsis);

    -- RBAC y ambito: docente (SEC_001), administrador de otra institucion (SEC_002)
    SET @corr = NEWID();
    INSERT INTO #culm1AplGrupo EXEC dbo.usp_aplicar_festivos_grupo @idGrupo = @g4, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    INSERT INTO #culm1AplGrupo EXEC dbo.usp_aplicar_festivos_grupo @idGrupo = @g4, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdminOtro;
    IF NOT EXISTS (SELECT 1 FROM #culm1AplGrupo WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SEC[_]001|%' AND sesionesCanceladas IS NULL)
       OR NOT EXISTS (SELECT 1 FROM #culm1AplGrupo WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SEC[_]002|%')
       OR EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc JOIN dbo.Sesion s ON s.id = sc.sesion WHERE s.grupo = @g4)
        THROW 57300, 'TEST FAILED CULM001_B1_FES_10: un docente (SEC_001) o un administrador de otra institucion (SEC_002) no pueden aplicar festivos.', 1;
    TRUNCATE TABLE #culm1AplGrupo;

    SET @corr = NEWID();
    INSERT INTO #culm1AplGrupo EXEC dbo.usp_aplicar_festivos_grupo @idGrupo = @g4, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'FES_008', @p_param1 = N'2', @p_param2 = N'1', @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    IF NOT EXISTS (SELECT 1 FROM #culm1AplGrupo WHERE estadoResultado = 1 AND mensajeTecnicoResultado LIKE N'DBCODE=FES[_]008|%' AND mensajeUsuarioResultado = @userMsg
                   AND sesionesCanceladas = 2 AND sesionesConAsistencia = 1)
        THROW 57301, 'TEST FAILED CULM001_B1_FES_10: aplicar festivos debe cancelar 2 sesiones futuras sin asistencia y reportar 1 con asistencia (FES_008).', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc JOIN dbo.DiaFestivo df ON df.id = sc.diaFestivo
                   WHERE sc.sesion = @sFutFest AND df.fecha = '2027-03-22' AND sc.usuarioEjecutor = @uAdmin AND sc.motivo = CONCAT(@prefijo, N'San José'))
       OR NOT EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc JOIN dbo.DiaFestivo df ON df.id = sc.diaFestivo WHERE sc.sesion = @sMadrugada AND df.fecha = '2027-03-26')
       OR EXISTS (SELECT 1 FROM dbo.SesionCancelacion WHERE sesion IN (@sFutFestAsis, @sPasFest, @sFutNormal, @sNocheAntes))
        THROW 57302, 'TEST FAILED CULM001_B1_FES_10_13: solo deben cancelarse la futura en festivo y la de las 06:00 locales del festivo (no la de 19:00 local del dia anterior, ni la pasada, ni la que tiene asistencia).', 1;
    TRUNCATE TABLE #culm1AplGrupo;
    SET @corr = NEWID();
    INSERT INTO #culm1AplGrupo EXEC dbo.usp_aplicar_festivos_grupo @idGrupo = @g4, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin, @soloFuturas = 1;
    IF NOT EXISTS (SELECT 1 FROM #culm1AplGrupo WHERE estadoResultado = 1 AND sesionesCanceladas = 0 AND sesionesConAsistencia = 1)
       OR (SELECT COUNT(*) FROM dbo.SesionCancelacion sc JOIN dbo.Sesion s ON s.id = sc.sesion WHERE s.grupo = @g4) <> 2
        THROW 57303, 'TEST FAILED CULM001_B1_FES_10: la segunda aplicacion debe ser idempotente (0 canceladas).', 1;
    TRUNCATE TABLE #culm1AplGrupo;
    PRINT 'TEST_PASS:CULM001_B1_FES_10_APLICAR_GRUPO';
    PRINT 'TEST_PASS:CULM001_B1_FES_13_FECHA_LOCAL_VS_UTC';

    -- B1-FES-12: sesiones en festivo que no se cancelaron por tener asistencia
    SET @corr = NEWID();
    INSERT INTO #culm1SesFest EXEC dbo.usp_consultar_sesiones_festivo_con_asistencia_paginado @idUsuarioEjecutor = @uAdmin, @idCorrelacion = @corr, @anio = 2027;
    IF NOT EXISTS (SELECT 1 FROM #culm1SesFest WHERE idSesion = @sFutFestAsis AND idGrupo = @g4 AND fecha = '2027-03-25' AND nombreFestivo = N'Jueves Santo'
                   AND totalRegistrosAsistencia = 1 AND nombreGrupo IS NOT NULL AND nombreAsignatura IS NOT NULL AND nombreDocente LIKE N'%Fabio%')
       OR EXISTS (SELECT 1 FROM #culm1SesFest WHERE idGrupo IN (@g1, @g3, @g4) AND idSesion <> @sFutFestAsis)
       OR EXISTS (SELECT 1 FROM #culm1SesFest WHERE totalRegistros <> (SELECT COUNT(*) FROM #culm1SesFest))
        THROW 57320, 'TEST FAILED CULM001_B1_FES_12: la consulta debe listar exactamente la sesion en festivo con asistencia reportada en B1-FES-10.', 1;
    TRUNCATE TABLE #culm1SesFest;
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #culm1SesFest EXEC dbo.usp_consultar_sesiones_festivo_con_asistencia_paginado @idUsuarioEjecutor = @uAdminOtro, @idCorrelacion = @corr, @anio = 2027;
    END TRY
    BEGIN CATCH SET @err = ERROR_MESSAGE(); END CATCH;
    IF @err IS NOT NULL OR EXISTS (SELECT 1 FROM #culm1SesFest WHERE idGrupo IN (@g1, @g3, @g4))
        THROW 57321, 'TEST FAILED CULM001_B1_FES_12: un administrador de otra institucion no debe ver sesiones de esta institucion.', 1;
    PRINT 'TEST_PASS:CULM001_B1_FES_12_SESIONES_REPORTADAS';

    -- ========================================================================================================
    -- B1-FES-11: aplicar por periodo / anio; filtros FES_006; periodo inexistente FES_007; otra institucion SEC_002
    -- ========================================================================================================
    SET @corr = NEWID();
    INSERT INTO #culm1AplPeriodo EXEC dbo.usp_aplicar_festivos_periodo @idPeriodoAcademico = @per4, @anio = 2027, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    INSERT INTO #culm1AplPeriodo EXEC dbo.usp_aplicar_festivos_periodo @idPeriodoAcademico = NULL, @anio = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    IF (SELECT COUNT(*) FROM #culm1AplPeriodo WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=FES[_]006|%' AND gruposProcesados IS NULL) <> 2
        THROW 57310, 'TEST FAILED CULM001_B1_FES_11: con ambos filtros o con ninguno debe responder FES_006.', 1;
    TRUNCATE TABLE #culm1AplPeriodo;
    INSERT INTO #culm1AplPeriodo EXEC dbo.usp_aplicar_festivos_periodo @idPeriodoAcademico = @uD1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    INSERT INTO #culm1AplPeriodo EXEC dbo.usp_aplicar_festivos_periodo @idPeriodoAcademico = @per4, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdminOtro;
    INSERT INTO #culm1AplPeriodo EXEC dbo.usp_aplicar_festivos_periodo @idPeriodoAcademico = @per4, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF NOT EXISTS (SELECT 1 FROM #culm1AplPeriodo WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=FES[_]007|%')
       OR NOT EXISTS (SELECT 1 FROM #culm1AplPeriodo WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SEC[_]002|%')
       OR NOT EXISTS (SELECT 1 FROM #culm1AplPeriodo WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SEC[_]001|%')
        THROW 57311, 'TEST FAILED CULM001_B1_FES_11: periodo inexistente FES_007, otra institucion SEC_002, docente SEC_001.', 1;
    TRUNCATE TABLE #culm1AplPeriodo;
    -- Periodo propio con un grupo nuevo de sesiones futuras en festivo
    DECLARE @g5 UNIQUEIDENTIFIER = NEWID(), @sG5 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
        cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@g5, @idAsig, @per4, 941000 + ABS(CHECKSUM(NEWID()) % 58999), N'CULM1 Grupo aplicar periodo', 30, 0, 0, 0, @d1);
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    VALUES (@sG5, N'CULM1-FES11 periodo', 1, N'CULMG5', 1, @g5, '2027-01-11T13:00:00', '2027-01-11T15:00:00', N'UTC_V2');
    SET @corr = NEWID();
    INSERT INTO #culm1AplPeriodo EXEC dbo.usp_aplicar_festivos_periodo @idPeriodoAcademico = @per4, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    IF NOT EXISTS (SELECT 1 FROM #culm1AplPeriodo WHERE estadoResultado = 1 AND mensajeTecnicoResultado LIKE N'DBCODE=FES[_]008|%'
                   AND gruposProcesados = 2 AND sesionesCanceladas = 1 AND sesionesConAsistencia = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.SesionCancelacion WHERE sesion = @sG5)
        THROW 57312, 'TEST FAILED CULM001_B1_FES_11: aplicar por periodo debe procesar sus 2 grupos (1 cancelada nueva, 1 con asistencia).', 1;
    TRUNCATE TABLE #culm1AplPeriodo;
    -- Por anio (grupos de la institucion del administrador cuyos periodos se cruzan con 2027) y automatico (job)
    SET @corr = NEWID();
    INSERT INTO #culm1AplPeriodo EXEC dbo.usp_aplicar_festivos_periodo @anio = 2027, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    INSERT INTO #culm1AplPeriodo EXEC dbo.usp_aplicar_festivos_automatico @anio = 2027, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #culm1AplPeriodo WHERE estadoResultado = 1 AND gruposProcesados >= 4 AND sesionesCanceladas = 0 AND sesionesConAsistencia >= 1) <> 2
        THROW 57313, 'TEST FAILED CULM001_B1_FES_11: aplicar por anio y el automatico deben procesar los grupos del anio sin cancelaciones nuevas.', 1;
    TRUNCATE TABLE #culm1AplPeriodo;
    INSERT INTO #culm1AplPeriodo EXEC dbo.usp_aplicar_festivos_periodo @anio = 2027, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdminOtro;
    IF NOT EXISTS (SELECT 1 FROM #culm1AplPeriodo WHERE estadoResultado = 1 AND gruposProcesados = 0)
        THROW 57314, 'TEST FAILED CULM001_B1_FES_11: un administrador de otra institucion no procesa grupos ajenos.', 1;
    TRUNCATE TABLE #culm1AplPeriodo;
    PRINT 'TEST_PASS:CULM001_B1_FES_11_APLICAR_PERIODO';

    -- Invariante: toda cancelacion automatica tiene festivo; ninguna sesion con asistencia quedo cancelada por festivo
    IF EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc JOIN dbo.TipoCancelacionSesion t ON t.id = sc.tipoCancelacion
               WHERE (t.esAutomatica = 1 AND sc.diaFestivo IS NULL) OR (t.esAutomatica = 0 AND sc.diaFestivo IS NOT NULL))
       OR EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc JOIN dbo.TipoCancelacionSesion t ON t.id = sc.tipoCancelacion
                  WHERE t.esAutomatica = 1 AND EXISTS (SELECT 1 FROM dbo.Asistencia a WHERE a.sesion = sc.sesion)
                    AND sc.idCorrelacion IN (SELECT idCorrelacion FROM dbo.SesionCancelacion x JOIN dbo.Sesion s ON s.id = x.sesion WHERE s.grupo IN (@g1, @g3, @g4, @g5)))
        THROW 57330, 'TEST FAILED INV_SESION_CANCELACION_COHERENTE: cancelacion automatica sin festivo o sobre una sesion con asistencia.', 1;
    PRINT 'TEST_PASS:CULM001_B1_FES_INV_COHERENCIA';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DROP TABLE IF EXISTS #culm1Esp, #culm1Carga, #culm1AplGrupo, #culm1AplPeriodo, #culm1Precarga, #culm1Dias, #culm1SesFest, #culm1CargaAnio;
    THROW;
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
-- B1-FES-08c: el llamador revirtio todo (generacion, festivos aplicados y precarga)
IF EXISTS (SELECT 1 FROM dbo.Sesion WHERE grupo IN (@g1, @g3, @g4, @g5)) OR EXISTS (SELECT 1 FROM dbo.Grupo WHERE id IN (@g1, @g3, @g4, @g5))
    THROW 57340, 'TEST FAILED CULM001_B1_FES_08C: el ROLLBACK del llamador no revirtio la generacion v2 ni la aplicacion de festivos.', 1;
DROP TABLE IF EXISTS #culm1Esp, #culm1Carga, #culm1AplGrupo, #culm1AplPeriodo, #culm1Precarga, #culm1Dias, #culm1SesFest, #culm1CargaAnio;
IF @@TRANCOUNT <> 0 THROW 57399, 'TEST FAILED CULM001_B1_FES: quedaron transacciones abiertas.', 1;
PRINT 'TEST_PASS:CULM001_B1_FES_08C_LLAMADOR_REVIERTE';
GO

-- Consultas de festivos: RBAC (SEC_001), paginacion (PAG_001) y anio (FES_001) con THROW 51000. Fuera de la transaccion
-- de la prueba porque el THROW de un SP de consulta con SET XACT_ABORT ON condena la transaccion del llamador.
DECLARE @uDocente UNIQUEIDENTIFIER = (SELECT TOP 1 di.idUsuario FROM dbo.uv_docente_identidad di WHERE di.estaActivoUsuario = 1
                                      AND NOT EXISTS (SELECT 1 FROM dbo.Administrador a WHERE a.usuario = di.idUsuario) ORDER BY di.id);
DECLARE @uAdminSeed UNIQUEIDENTIFIER = (SELECT TOP 1 a.usuario FROM dbo.Administrador a JOIN dbo.uv_usuario u ON u.id = a.usuario
                                        WHERE u.estaActivoUsuario = 1 ORDER BY a.id);
DECLARE @err NVARCHAR(4000) = NULL, @corr UNIQUEIDENTIFIER = NEWID();
CREATE TABLE #culm1DiasX (id UNIQUEIDENTIFIER, fecha DATE, anio SMALLINT, nombre NVARCHAR(120), fuente NVARCHAR(40), estaActivo BIT, fechaCargaUtc DATETIME2(0),
    idCorrelacionCarga UNIQUEIDENTIFIER, fuenteUltimaCarga NVARCHAR(40), fechaUltimaCargaUtc DATETIME2(0), diferenciasCalculoLocal INT, totalRegistros INT);
BEGIN TRY
    INSERT INTO #culm1DiasX EXEC dbo.usp_consultar_dias_festivos @idUsuarioEjecutor = @uDocente, @idCorrelacion = @corr, @anio = 2026;
END TRY
BEGIN CATCH SET @err = ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
IF @uDocente IS NULL OR @err IS NULL OR @err NOT LIKE N'%DBCODE=SEC[_]001|%'
    THROW 57233, 'TEST FAILED CULM001_B1_FES_CONSULTA: un docente no puede consultar los festivos del administrador (SEC_001).', 1;
SET @err = NULL;
BEGIN TRY
    INSERT INTO #culm1DiasX EXEC dbo.usp_consultar_dias_festivos @idUsuarioEjecutor = @uAdminSeed, @idCorrelacion = @corr, @anio = 2026, @numeroPagina = 0;
END TRY
BEGIN CATCH SET @err = ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
IF @err IS NULL OR @err NOT LIKE N'%DBCODE=PAG[_]001|%'
    THROW 57234, 'TEST FAILED CULM001_B1_FES_CONSULTA: la pagina 0 debe rechazarse con PAG_001.', 1;
SET @err = NULL;
BEGIN TRY
    INSERT INTO #culm1DiasX EXEC dbo.usp_consultar_dias_festivos @idUsuarioEjecutor = @uAdminSeed, @idCorrelacion = @corr, @anio = 1999;
END TRY
BEGIN CATCH SET @err = ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
IF @err IS NULL OR @err NOT LIKE N'%DBCODE=FES[_]001|%'
    THROW 57235, 'TEST FAILED CULM001_B1_FES_CONSULTA: un anio fuera de rango debe rechazarse con FES_001.', 1;
DROP TABLE #culm1DiasX;
PRINT 'TEST_PASS:CULM001_B1_FES_CONSULTA_RBAC_PAGINACION';
GO

-- ============================================================================================================
-- B1-FES-08b2 (R2-1): falla inyectada en la fase 1 (patron CK_REC3_TMP_SESION de test_rec3, TX-04) CON transaccion
-- externa: el v2 hace THROW sin ROLLBACK y no devuelve tupla; el CATCH del llamador ve XACT_STATE() = -1 y revierte.
-- ============================================================================================================
DECLARE @institution UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion);
DECLARE @assignment UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_asignatura);
DECLARE @teacher UNIQUEIDENTIFIER = (SELECT TOP 1 d.id FROM dbo.uv_docente d JOIN dbo.uv_docente_identidad di ON di.id = d.id WHERE di.estaActivoUsuario = 1 ORDER BY d.id);
DECLARE @teacherUser UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_docente WHERE id = @teacher);
DECLARE @period UNIQUEIDENTIFIER = NEWID(), @group UNIQUEIDENTIFIER = NEWID(), @corr UNIQUEIDENTIFIER = NEWID();
DECLARE @fallo NVARCHAR(4000) = NULL, @sql NVARCHAR(MAX), @estadoCatch INT = NULL, @errorCatch NVARCHAR(4000) = NULL;
DECLARE @firstDay DATE = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER') AS DATE);
IF @institution IS NULL OR @assignment IS NULL OR @teacher IS NULL OR @teacherUser IS NULL
    THROW 57350, 'TEST FAILED CULM001_B1_FES_08B2: fixture faltante.', 1;

BEGIN TRANSACTION;
BEGIN TRY
    INSERT dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@period, @institution, N'CULM1 Periodo 08b2', 3900000 + ABS(CHECKSUM(NEWID()) % 99999), @firstDay, DATEADD(DAY, 7, @firstDay), YEAR(@firstDay));
    INSERT dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
        cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@group, @assignment, @period, 942000 + ABS(CHECKSUM(NEWID()) % 57999), N'CULM1 Grupo 08b2', 20, 0, 0, 0, @teacher);
    INSERT dbo.Horario (id, grupo, dia, horaInicio, horaFin) SELECT NEWID(), @group, id, '08:00', '09:00' FROM dbo.uv_dia;
    SET @sql = CONCAT(N'ALTER TABLE dbo.Sesion WITH NOCHECK ADD CONSTRAINT CK_CULM1_TMP_SESION CHECK (grupo <> ''',
                      CONVERT(NVARCHAR(36), @group), N''' OR numero < 2);');
    EXEC sys.sp_executesql @sql;
    EXEC dbo.usp_generar_sesiones_grupo_v2 @idGrupo = @group, @idCorrelacion = @corr, @idUsuarioEjecutor = @teacherUser;
    SET @fallo = 'TEST FAILED CULM001_B1_FES_08B2: con transaccion externa el v2 debio propagar el error (THROW) en lugar de continuar.';
END TRY
BEGIN CATCH
    SET @estadoCatch = XACT_STATE();
    SET @errorCatch = ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
IF OBJECT_ID('dbo.CK_CULM1_TMP_SESION', 'C') IS NOT NULL ALTER TABLE dbo.Sesion DROP CONSTRAINT CK_CULM1_TMP_SESION;
IF @fallo IS NULL AND (@estadoCatch IS NULL OR @estadoCatch <> -1)
    SET @fallo = CONCAT('TEST FAILED CULM001_B1_FES_08B2: el llamador debio ver XACT_STATE() = -1; vio ', ISNULL(CONVERT(NVARCHAR(10), @estadoCatch), 'NULL'), ' (', @errorCatch, ').');
IF @fallo IS NULL AND (EXISTS (SELECT 1 FROM dbo.Sesion WHERE grupo = @group) OR EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @group) OR @@TRANCOUNT <> 0)
    SET @fallo = 'TEST FAILED CULM001_B1_FES_08B2: tras el ROLLBACK del llamador quedaron sesiones del grupo o transacciones abiertas.';
IF @fallo IS NOT NULL THROW 57351, @fallo, 1;
PRINT 'TEST_PASS:CULM001_B1_FES_08B2_TRANSACCION_EXTERNA_THROW';
IF @@TRANCOUNT <> 0 THROW 57398, 'TEST FAILED CULM001_B1_FES: quedaron transacciones abiertas.', 1;
PRINT 'TEST END: test_culm001_b1_festivos';
GO
