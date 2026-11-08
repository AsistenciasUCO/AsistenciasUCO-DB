USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- CULM-001 B.2 (CONTRACT §2.1-§2.3, §2.5, §2.8.1, §2.8.2, §2.8.4, §2.16.2 B2-TOM-01..11, B2-MIG-06): tomas de asistencia.
-- Una toma = comportamiento actual (el lote congelado crea la toma 1 implicita y cerrada); apertura MANUAL/QR dentro de la
-- ventana con tolerancia; una sola toma abierta; maximo TOMA_ASISTENCIA/MAXIMO_TOMAS_POR_SESION; lote por toma; cierre con
-- @marcarAusentes (QR marca SJC a los activos sin registro); faltantes; cierre automatico de tomas vencidas.
-- Todo dentro de una transaccion revertida. Requiere el helper test/fixtures/culm001_b2_toma_fixture.sql (test_suite.sql).
PRINT 'TEST START: test_culm001_b2_tomas (CULM-001 B.2, HU175)';

-- ------------------------------------------------------------------------------------------------------------------
-- B2-TOM-00: objetos, catalogos con ids fijos, parametros, mensajes, columna toma NOT NULL, indices y secuencia
-- ------------------------------------------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.TomaAsistencia', N'U') IS NULL OR OBJECT_ID(N'dbo.TokenAsistenciaToma', N'U') IS NULL
   OR OBJECT_ID(N'dbo.ModoTomaAsistencia', N'U') IS NULL OR OBJECT_ID(N'dbo.EstadoTomaAsistencia', N'U') IS NULL
   OR OBJECT_ID(N'dbo.uv_toma_asistencia', N'V') IS NULL OR OBJECT_ID(N'dbo.uv_token_asistencia_toma', N'V') IS NULL
   OR OBJECT_ID(N'dbo.uv_detalle_asistencia_v2', N'V') IS NULL OR OBJECT_ID(N'dbo.uv_asistencia_sesion_horas', N'V') IS NULL
   OR OBJECT_ID(N'dbo.uv_faltantes_toma', N'V') IS NULL OR OBJECT_ID(N'dbo.uv_modo_toma_asistencia', N'V') IS NULL
   OR OBJECT_ID(N'dbo.uv_estado_toma_asistencia', N'V') IS NULL
   OR OBJECT_ID(N'dbo.usp_abrir_toma_asistencia', N'P') IS NULL OR OBJECT_ID(N'dbo.usp_cerrar_toma_asistencia', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_cerrar_tomas_vencidas', N'P') IS NULL OR OBJECT_ID(N'dbo.usp_registrar_asistencias_toma', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_internal_marcar_ausentes_toma', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_consultar_tomas_sesion', N'P') IS NULL OR OBJECT_ID(N'dbo.usp_consultar_faltantes_toma_paginado', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_consultar_asistencias_toma_paginado', N'P') IS NULL
   OR OBJECT_ID(N'dbo.ufn_horas_sesion', N'FN') IS NULL OR OBJECT_ID(N'dbo.ufn_horas_toma', N'FN') IS NULL
   OR OBJECT_ID(N'dbo.ufn_calcular_porcentaje_inasistencia_horas', N'FN') IS NULL
   OR OBJECT_ID(N'dbo.seq_detalle_asistencia_codigo', N'SO') IS NULL
    THROW 57200, 'TEST FAILED CULM001_B2_TOM_00: faltan objetos de B.2 (tablas, vistas, SP, funciones o secuencia de tomas).', 1;
IF (SELECT COUNT(*) FROM dbo.uv_modo_toma_asistencia) <> 2
   OR NOT EXISTS (SELECT 1 FROM dbo.uv_modo_toma_asistencia WHERE id = '7C1E0B20-5E51-4C0A-9A01-000000000001' AND codigo = N'MANUAL' AND usaCodigoQr = 0 AND marcaAusentesAlCerrar = 0)
   OR NOT EXISTS (SELECT 1 FROM dbo.uv_modo_toma_asistencia WHERE id = '7C1E0B20-5E51-4C0A-9A01-000000000002' AND codigo = N'QR' AND usaCodigoQr = 1 AND marcaAusentesAlCerrar = 1)
   OR (SELECT COUNT(*) FROM dbo.uv_estado_toma_asistencia) <> 2
   OR NOT EXISTS (SELECT 1 FROM dbo.uv_estado_toma_asistencia WHERE id = '7C1E0B30-5E51-4C0A-9A01-000000000001' AND codigo = N'ABIERTA' AND estaAbierta = 1)
   OR NOT EXISTS (SELECT 1 FROM dbo.uv_estado_toma_asistencia WHERE id = '7C1E0B30-5E51-4C0A-9A01-000000000002' AND codigo = N'CERRADA' AND estaAbierta = 0)
    THROW 57201, 'TEST FAILED CULM001_B2_TOM_00: catalogos ModoTomaAsistencia / EstadoTomaAsistencia distintos de la semilla 35.', 1;
IF dbo.ufn_obtener_parametro_int(NULL, 'TOMA_ASISTENCIA', 'MAXIMO_TOMAS_POR_SESION') <> 4
   OR dbo.ufn_obtener_parametro_int(NULL, 'TOMA_ASISTENCIA', 'LOTE_CIERRE_AUTOMATICO') <> 200
   OR CAST(dbo.ufn_obtener_parametro('ASISTENCIA', 'CODIGO_RAZON_PRESENTE') AS NVARCHAR(10)) <> N'AN'
   OR CAST(dbo.ufn_obtener_parametro('ASISTENCIA', 'CODIGO_RAZON_SIN_JUSTA_CAUSA') AS NVARCHAR(10)) <> N'SJC'
   OR CAST(dbo.ufn_obtener_parametro('ASISTENCIA', 'CODIGO_RAZON_EXCUSA') AS NVARCHAR(10)) <> N'EX'
    THROW 57202, 'TEST FAILED CULM001_B2_TOM_00: parametros TOMA_ASISTENCIA/* o ASISTENCIA/CODIGO_RAZON_* ausentes o distintos de la semilla.', 1;
IF EXISTS (SELECT 1 FROM (VALUES ('TOM_001'), ('TOM_002'), ('TOM_003'), ('TOM_004'), ('TOM_008'), ('TOM_009'), ('TOM_010'), ('TOM_011')) c(codigo)
           WHERE NOT EXISTS (SELECT 1 FROM dbo.uv_mensaje_usuario u WHERE u.codigo = c.codigo)
              OR NOT EXISTS (SELECT 1 FROM dbo.uv_mensaje_tecnico t WHERE t.codigo = c.codigo))
   OR EXISTS (SELECT 1 FROM dbo.uv_mensaje_usuario WHERE codigo IN ('TOM_005', 'TOM_006', 'TOM_007'))
    THROW 57203, 'TEST FAILED CULM001_B2_TOM_00: mensajes TOM_* ausentes o TOM_005..007 (reservados) sembrados.', 1;
IF COLUMNPROPERTY(OBJECT_ID(N'dbo.DetalleAsistencia'), 'toma', 'AllowsNull') <> 0
   OR COLUMNPROPERTY(OBJECT_ID(N'dbo.DetalleAsistencia'), 'registradoPorEstudiante', 'AllowsNull') <> 0
   OR COLUMNPROPERTY(OBJECT_ID(N'dbo.DetalleAsistencia'), 'fechaRegistroUtc', 'AllowsNull') <> 1
   OR NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.DetalleAsistencia') AND name = 'UX_DetalleAsistencia_Asistencia_Toma' AND is_unique = 1)
   OR NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.DetalleAsistencia') AND name = 'IX_DetalleAsistencia_Toma')
   OR NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_DetalleAsistencia_TomaAsistencia' AND parent_object_id = OBJECT_ID(N'dbo.DetalleAsistencia'))
   OR EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.DetalleAsistencia') AND name = 'UX_DetalleAsistencia_Asistencia')
   OR NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.TomaAsistencia') AND name = 'UX_TomaAsistencia_Sesion_Abierta' AND is_unique = 1 AND has_filter = 1)
   OR NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.TokenAsistenciaToma') AND name = 'UX_TokenAsistenciaToma_pin_activo' AND is_unique = 1 AND has_filter = 1)
   OR NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.TokenAsistenciaToma') AND name = 'UX_TokenAsistenciaToma_toma_activo' AND is_unique = 1 AND has_filter = 1)
   OR EXISTS (SELECT 1 FROM dbo.DetalleAsistencia WHERE toma IS NULL)
    THROW 57204, 'TEST FAILED CULM001_B2_TOM_00: DetalleAsistencia.toma no es NOT NULL o faltan/sobran sus indices y FK (B-1).', 1;
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.TokenAsistenciaToma') AND name IN ('token', 'tokenTexto', 'totalRegistros'))
   OR EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.uv_token_asistencia_toma') AND name IN ('tokenHash', 'tokenHashAnterior'))
    THROW 57205, 'TEST FAILED CULM001_B2_TOM_00: el token en claro, su hash en la vista o un contador por fila no deben existir.', 1;
IF (SELECT COUNT(*) FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.uv_toma_asistencia') AND name IN (
        'idToma', 'idSesion', 'idGrupo', 'numero', 'idModo', 'codigoModo', 'nombreModo', 'usaCodigoQr', 'marcaAusentesAlCerrar', 'idEstado',
        'codigoEstado', 'nombreEstado', 'estaAbierta', 'esImplicita', 'idDocenteApertura', 'fechaAperturaUtc', 'fechaCierreUtc',
        'totalAusentesMarcados', 'fechaHoraInicioSesion', 'fechaHoraFinSesion', 'estaSesionCancelada', 'horasSesion', 'totalTomasSesion',
        'horasToma', 'totalRegistros', 'totalPresentes', 'totalAusentes', 'totalExcusas', 'tieneQrActivo')) <> 29
   OR (SELECT COUNT(*) FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.uv_detalle_asistencia_v2') AND name IN (
        'id', 'codigo', 'idAsistencia', 'asistio', 'idRazonCausa', 'nombreRazonCausa', 'codigoRazonCausa', 'fechaHoraInicio', 'fechaHoraFin',
        'idToma', 'numeroToma', 'idSesion', 'idEstudianteGrupo', 'idModoToma', 'codigoModoToma', 'horasToma', 'registradoPorEstudiante',
        'fechaRegistroUtc', 'estaSesionCancelada')) <> 19
   OR (SELECT COUNT(*) FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.uv_faltantes_toma') AND name IN (
        'idToma', 'idSesion', 'idGrupo', 'numeroToma', 'idEstudianteGrupo', 'idEstudiante', 'nombreCompletoEstudiante', 'tieneRegistro',
        'idDetalleAsistencia', 'codigoRazonCausa', 'fueMarcadoAlCerrar')) <> 11
   OR (SELECT COUNT(*) FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.uv_sesion_estado') AND name IN ('totalTomas', 'tieneTomaAbierta', 'idTomaAbierta')) <> 3
   OR (SELECT COUNT(*) FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.uv_cumplimiento_sesion_grupo') AND name IN ('totalTomas', 'horasSesion')) <> 2
    THROW 57206, 'TEST FAILED CULM001_B2_TOM_00: las vistas de B.2 no exponen las columnas del contrato (§2.5, §2.6).', 1;
-- uv_detalle_asistencia (congelada) intacta: mismas 9 columnas en el mismo orden
IF (SELECT STRING_AGG(name, ',') WITHIN GROUP (ORDER BY column_id) FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.uv_detalle_asistencia'))
   <> N'id,codigo,idAsistencia,asistio,idRazonCausa,nombreRazonCausa,codigoRazonCausa,fechaHoraInicio,fechaHoraFin'
    THROW 57207, 'TEST FAILED CULM001_B2_TOM_00: uv_detalle_asistencia (congelada) cambio de forma.', 1;
-- Firma de usp_sincronizar_asistencia_estudiante_interno: los 7 parametros actuales + 5 nuevos opcionales al final
IF (SELECT STRING_AGG(name, ',') WITHIN GROUP (ORDER BY parameter_id) FROM sys.parameters WHERE object_id = OBJECT_ID(N'dbo.usp_sincronizar_asistencia_estudiante_interno'))
   <> N'@idEstudiante,@idSesion,@codigoEstado,@idCorrelacion,@mensajeUsuarioResultado,@mensajeTecnicoResultado,@estadoResultado,@idToma,@registradoPorEstudiante,@soloSiNoExiste,@idUsuarioEjecutor,@detalleCreado'
    THROW 57208, 'TEST FAILED CULM001_B2_TOM_00: firma de usp_sincronizar_asistencia_estudiante_interno distinta del contrato (§2.8.1).', 1;
PRINT 'TEST_PASS:CULM001_B2_TOM_00_OBJETOS_Y_SEMILLAS';

-- B2-MIG-06: la secuencia de DetalleAsistencia.codigo esta por delante del maximo actual (se lee sin consumir valores)
IF NOT EXISTS (
    SELECT 1 FROM sys.sequences sq
    WHERE sq.object_id = OBJECT_ID(N'dbo.seq_detalle_asistencia_codigo')
      AND sq.increment = 1 AND sq.is_cycling = 0
      AND CAST(sq.current_value AS BIGINT) >= (SELECT ISNULL(MAX(CAST(codigo AS BIGINT)), 0) FROM dbo.DetalleAsistencia))
    THROW 57209, 'TEST FAILED CULM001_B2_MIG_06: seq_detalle_asistencia_codigo no esta por delante de MAX(DetalleAsistencia.codigo).', 1;
PRINT 'TEST_PASS:CULM001_B2_MIG_06_SECUENCIA';
GO

DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @idAsig UNIQUEIDENTIFIER = (SELECT TOP 1 a.id FROM dbo.uv_asignatura a WHERE a.estaActivaAsignatura = 1 ORDER BY a.id);
DECLARE @idInstitucion UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion ORDER BY id);
DECLARE @estadoA UNIQUEIDENTIFIER = (SELECT id FROM dbo.uv_estado_estudiante_grupo WHERE codigo = 'A');
DECLARE @estadoI UNIQUEIDENTIFIER = (SELECT id FROM dbo.uv_estado_estudiante_grupo WHERE codigo = 'I');
DECLARE @estadoCI UNIQUEIDENTIFIER = (SELECT id FROM dbo.uv_estado_estudiante_grupo WHERE codigo = 'CI');
DECLARE @tipoManual UNIQUEIDENTIFIER = (SELECT id FROM dbo.TipoCancelacionSesion WHERE esAutomatica = 0);
DECLARE @modoQr UNIQUEIDENTIFIER = (SELECT id FROM dbo.ModoTomaAsistencia WHERE usaCodigoQr = 1);
DECLARE @modoManual UNIQUEIDENTIFIER = (SELECT id FROM dbo.ModoTomaAsistencia WHERE usaCodigoQr = 0);
DECLARE @estAbierta UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoTomaAsistencia WHERE estaAbierta = 1);
DECLARE @zona SYSNAME = dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER');
DECLARE @hoy DATE = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE @zona AS DATE);
IF @tipoCC IS NULL OR @idAsig IS NULL OR @idInstitucion IS NULL OR @estadoA IS NULL OR @estadoI IS NULL OR @estadoCI IS NULL
   OR @tipoManual IS NULL OR @modoQr IS NULL OR @estAbierta IS NULL
    THROW 57210, 'TEST FAILED CULM001_B2_TOM: faltan fixtures del seed (asignatura, institucion, estados, catalogos).', 1;

CREATE TABLE #b2tA (idCorrelacion UNIQUEIDENTIFIER NULL, mu NVARCHAR(4000) NULL, mt NVARCHAR(4000) NULL, estado BIT NOT NULL,
    idToma UNIQUEIDENTIFIER NULL, numero SMALLINT NULL, codigoModo NVARCHAR(20) NULL, usaCodigoQr BIT NULL, fechaAperturaUtc DATETIME2(0) NULL,
    ventanaCierreUtc DATETIME2(0) NULL, totalTomasSesion INT NULL, horasToma DECIMAL(12,6) NULL);
CREATE TABLE #b2tC (idCorrelacion UNIQUEIDENTIFIER NULL, mu NVARCHAR(4000) NULL, mt NVARCHAR(4000) NULL, estado BIT NOT NULL,
    idToma UNIQUEIDENTIFIER NULL, idSesion UNIQUEIDENTIFIER NULL, idGrupo UNIQUEIDENTIFIER NULL, fechaCierreUtc DATETIME2(0) NULL,
    totalAusentesMarcados INT NULL, totalFaltantes INT NULL, yaEstabaCerrada BIT NULL);
CREATE TABLE #b2tL (idCorrelacion UNIQUEIDENTIFIER NULL, mu NVARCHAR(4000) NULL, mt NVARCHAR(4000) NULL, estado BIT NOT NULL,
    idToma UNIQUEIDENTIFIER NULL, idSesion UNIQUEIDENTIFIER NULL, idGrupo UNIQUEIDENTIFIER NULL, totalRegistros INT NULL);
CREATE TABLE #b2tR (idCorrelacion UNIQUEIDENTIFIER NULL, mu NVARCHAR(4000) NULL, mt NVARCHAR(4000) NULL, estado BIT NOT NULL);
CREATE TABLE #b2tV (idToma UNIQUEIDENTIFIER, idSesion UNIQUEIDENTIFIER, idGrupo UNIQUEIDENTIFIER, totalAusentesMarcados INT);
CREATE TABLE #b2tK (idCorrelacion UNIQUEIDENTIFIER NULL, mu NVARCHAR(4000) NULL, mt NVARCHAR(4000) NULL, estado BIT NOT NULL,
    idSesion UNIQUEIDENTIFIER NULL, idGrupo UNIQUEIDENTIFIER NULL, fechaCancelacionUtc DATETIME2(0) NULL, totalEstudiantesActivos INT NULL);
CREATE TABLE #b2tS (idSesion UNIQUEIDENTIFIER, idGrupo UNIQUEIDENTIFIER, numeroSesion INT, horasSesion DECIMAL(12,6), estaSesionCancelada BIT,
    motivoCancelacion NVARCHAR(500), ventanaAperturaUtc DATETIME2, ventanaCierreUtc DATETIME2, ventanaAbierta BIT, maximoTomas INT, totalTomasSesion INT,
    idToma UNIQUEIDENTIFIER, numero SMALLINT, idModo UNIQUEIDENTIFIER, codigoModo NVARCHAR(20), nombreModo NVARCHAR(50), usaCodigoQr BIT,
    marcaAusentesAlCerrar BIT, idEstado UNIQUEIDENTIFIER, codigoEstado NVARCHAR(20), nombreEstado NVARCHAR(50), estaAbierta BIT, esImplicita BIT,
    idDocenteApertura UNIQUEIDENTIFIER, fechaAperturaUtc DATETIME2(0), fechaCierreUtc DATETIME2(0), totalAusentesMarcados INT, horasToma DECIMAL(12,6),
    totalRegistros INT, totalPresentes INT, totalAusentes INT, totalExcusas INT, tieneQrActivo BIT);
CREATE TABLE #b2tF (idToma UNIQUEIDENTIFIER, idSesion UNIQUEIDENTIFIER, idGrupo UNIQUEIDENTIFIER, numeroToma SMALLINT, idEstudianteGrupo UNIQUEIDENTIFIER,
    idEstudiante UNIQUEIDENTIFIER, nombreCompletoEstudiante NVARCHAR(400), tieneRegistro BIT, idDetalleAsistencia UNIQUEIDENTIFIER,
    codigoRazonCausa NVARCHAR(10), fueMarcadoAlCerrar BIT, totalRegistros INT);
CREATE TABLE #b2tT (idEstudiante UNIQUEIDENTIFIER, nombreCompletoEstudiante NVARCHAR(400), codigoRazonCausa NVARCHAR(10),
    registradoPorEstudiante BIT, fechaRegistroUtc DATETIME2(0), totalRegistros INT);

DECLARE @corr UNIQUEIDENTIFIER, @json NVARCHAR(MAX), @t1 UNIQUEIDENTIFIER, @t2 UNIQUEIDENTIFIER, @t3 UNIQUEIDENTIFIER, @n INT;

BEGIN TRANSACTION;
BEGIN TRY
    -- Fixture: docente titular d1, otro docente d2; estudiantes e1..e4 activos, e5 CI, e6 I; periodo vigente; grupo g
    DECLARE @uD1 UNIQUEIDENTIFIER = NEWID(), @uD2 UNIQUEIDENTIFIER = NEWID(), @d1 UNIQUEIDENTIFIER = NEWID(), @d2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @tag NVARCHAR(12) = LEFT(REPLACE(CONVERT(NVARCHAR(36), NEWID()), N'-', N''), 12);
    CREATE TABLE #b2tE (n INT, idUsuario UNIQUEIDENTIFIER, idEstudiante UNIQUEIDENTIFIER, idEG UNIQUEIDENTIFIER);
    INSERT INTO #b2tE (n, idUsuario, idEstudiante, idEG) SELECT v.n, NEWID(), NEWID(), NEWID() FROM (VALUES (1),(2),(3),(4),(5),(6)) v(n);
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uD1, @tipoCC, 971000000 + ABS(CHECKSUM(NEWID()) % 999999), N'Titular', N'CulmB', N'Tomas', N'B2', CONCAT(N'culmb2.d1.', @tag, N'@test.local'), 1, 1, N'HashBackend_CULMB2'),
           (@uD2, @tipoCC, 972000000 + ABS(CHECKSUM(NEWID()) % 999999), N'Ajeno', N'CulmB', N'Teo', N'B2', CONCAT(N'culmb2.d2.', @tag, N'@test.local'), 1, 1, N'HashBackend_CULMB2');
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    SELECT e.idUsuario, @tipoCC, 973000000 + e.n * 10000 + ABS(CHECKSUM(NEWID()) % 9999), CONCAT(N'Estudiante', e.n), N'CulmB', N'Est', N'B2',
           CONCAT(N'culmb2.e', e.n, N'.', @tag, N'@test.local'), 1, 1, N'HashBackend_CULMB2'
    FROM #b2tE e;
    INSERT INTO dbo.Docente (id, usuario) VALUES (@d1, @uD1), (@d2, @uD2);
    INSERT INTO dbo.Estudiante (id, usuario) SELECT idEstudiante, idUsuario FROM #b2tE;

    DECLARE @per UNIQUEIDENTIFIER = NEWID(), @g UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@per, @idInstitucion, N'CULMB2 periodo tomas', 3200000 + ABS(CHECKSUM(NEWID()) % 700000), DATEADD(DAY, -30, @hoy), DATEADD(DAY, 30, @hoy), YEAR(@hoy));
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
        cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@g, @idAsig, @per, 945000 + ABS(CHECKSUM(NEWID()) % 54999), N'CULMB2 Grupo tomas', 30, 0, 0, 0, @d1);
    INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo)
    SELECT e.idEG, CASE e.n WHEN 5 THEN @estadoCI WHEN 6 THEN @estadoI ELSE @estadoA END, e.idEstudiante, @g FROM #b2tE e;
    DECLARE @e1 UNIQUEIDENTIFIER = (SELECT idEstudiante FROM #b2tE WHERE n = 1), @e2 UNIQUEIDENTIFIER = (SELECT idEstudiante FROM #b2tE WHERE n = 2);
    DECLARE @e3 UNIQUEIDENTIFIER = (SELECT idEstudiante FROM #b2tE WHERE n = 3), @e4 UNIQUEIDENTIFIER = (SELECT idEstudiante FROM #b2tE WHERE n = 4);
    DECLARE @uE1 UNIQUEIDENTIFIER = (SELECT idUsuario FROM #b2tE WHERE n = 1);

    -- Sesiones (2 h cada una): en curso (ventana abierta), futura, pasada (ventana vencida), cancelada, y auxiliares
    DECLARE @sLote UNIQUEIDENTIFIER = NEWID(), @sNow UNIQUEIDENTIFIER = NEWID(), @sNow2 UNIQUEIDENTIFIER = NEWID(), @sNow3 UNIQUEIDENTIFIER = NEWID();
    DECLARE @sNow4 UNIQUEIDENTIFIER = NEWID(), @sFut UNIQUEIDENTIFIER = NEWID(), @sPast UNIQUEIDENTIFIER = NEWID(), @sCanc UNIQUEIDENTIFIER = NEWID();
    DECLARE @sMargen UNIQUEIDENTIFIER = NEWID();
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    VALUES (@sLote,   N'CULMB2 lote',      1, N'CB2T01', 1, @g, DATEADD(MINUTE, -30, SYSUTCDATETIME()), DATEADD(MINUTE, 90, SYSUTCDATETIME()), N'UTC_V2'),
           (@sNow,    N'CULMB2 en curso',  2, N'CB2T02', 1, @g, DATEADD(MINUTE, -30, SYSUTCDATETIME()), DATEADD(MINUTE, 90, SYSUTCDATETIME()), N'UTC_V2'),
           (@sNow2,   N'CULMB2 en curso2', 3, N'CB2T03', 1, @g, DATEADD(MINUTE, -30, SYSUTCDATETIME()), DATEADD(MINUTE, 90, SYSUTCDATETIME()), N'UTC_V2'),
           (@sNow3,   N'CULMB2 en curso3', 4, N'CB2T04', 1, @g, DATEADD(MINUTE, -30, SYSUTCDATETIME()), DATEADD(MINUTE, 90, SYSUTCDATETIME()), N'UTC_V2'),
           (@sNow4,   N'CULMB2 en curso4', 5, N'CB2T05', 1, @g, DATEADD(MINUTE, -30, SYSUTCDATETIME()), DATEADD(MINUTE, 90, SYSUTCDATETIME()), N'UTC_V2'),
           (@sFut,    N'CULMB2 futura',    6, N'CB2T06', 1, @g, DATEADD(DAY, 2, SYSUTCDATETIME()),     DATEADD(MINUTE, 2 * 1440 + 120, SYSUTCDATETIME()), N'UTC_V2'),
           (@sPast,   N'CULMB2 pasada',    7, N'CB2T07', 1, @g, DATEADD(MINUTE, -300, SYSUTCDATETIME()), DATEADD(MINUTE, -180, SYSUTCDATETIME()), N'UTC_V2'),
           (@sCanc,   N'CULMB2 cancelada', 8, N'CB2T08', 1, @g, DATEADD(MINUTE, -30, SYSUTCDATETIME()), DATEADD(MINUTE, 90, SYSUTCDATETIME()), N'UTC_V2'),
           -- termino hace 10 min: dentro del margen de 30 min (ventana con margen abierta, lote congelado cerrado)
           (@sMargen, N'CULMB2 en margen', 9, N'CB2T09', 1, @g, DATEADD(MINUTE, -130, SYSUTCDATETIME()), DATEADD(MINUTE, -10, SYSUTCDATETIME()), N'UTC_V2');
    INSERT dbo.SesionCancelacion (sesion, tipoCancelacion, motivo, diaFestivo, usuarioEjecutor, idCorrelacion)
    VALUES (@sCanc, @tipoManual, N'CULMB2 cancelada por el docente', NULL, @uD1, NEWID());

    -- --------------------------------------------------------------------------------------------------------
    -- B2-TOM-01: toma unica = comportamiento actual. El lote congelado sobre una sesion sin tomas crea la toma 1
    -- implicita y cerrada; un detalle por estudiante; uv_detalle_asistencia devuelve las mismas filas y columnas.
    -- --------------------------------------------------------------------------------------------------------
    SET @corr = NEWID();
    SET @json = CONCAT(N'[{"idEstudiante":"', @e1, N'","estado":"AN"},{"idEstudiante":"', @e2, N'","estado":"SJC"}]');
    INSERT INTO #b2tR EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sLote, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF NOT EXISTS (SELECT 1 FROM #b2tR WHERE estado = 1)
        THROW 57220, 'TEST FAILED CULM001_B2_TOM_01: el lote congelado debe seguir funcionando sobre una sesion sin tomas.', 1;
    IF (SELECT COUNT(*) FROM dbo.TomaAsistencia WHERE sesion = @sLote) <> 1
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_toma_asistencia WHERE idSesion = @sLote AND numero = 1 AND esImplicita = 1 AND estaAbierta = 0
                      AND usaCodigoQr = 0 AND fechaCierreUtc IS NOT NULL AND idDocenteApertura = @d1 AND totalRegistros = 2
                      AND totalPresentes = 1 AND totalAusentes = 1 AND totalExcusas = 0 AND horasToma = 2.000000)
        THROW 57221, 'TEST FAILED CULM001_B2_TOM_01: el lote congelado debe crear exactamente la toma 1 implicita, MANUAL y CERRADA (SUPUESTO-B-04).', 1;
    IF (SELECT COUNT(*) FROM dbo.uv_asistencia a INNER JOIN dbo.uv_detalle_asistencia d ON d.idAsistencia = a.id WHERE a.idSesion = @sLote) <> 2
       OR (SELECT COUNT(*) FROM dbo.DetalleAsistencia da INNER JOIN dbo.Asistencia a ON a.id = da.asistencia INNER JOIN dbo.TomaAsistencia t ON t.id = da.toma
           WHERE a.sesion = @sLote AND t.sesion = @sLote AND t.numero = 1 AND da.registradoPorEstudiante = 0 AND da.fechaRegistroUtc IS NOT NULL) <> 2
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_asistencia a INNER JOIN dbo.uv_detalle_asistencia d ON d.idAsistencia = a.id
                      INNER JOIN dbo.EstudianteGrupo eg ON eg.id = a.idEstudianteGrupo WHERE a.idSesion = @sLote AND eg.estudiante = @e1 AND d.codigoRazonCausa = N'AN' AND d.asistio = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_asistencia a INNER JOIN dbo.uv_detalle_asistencia d ON d.idAsistencia = a.id
                      INNER JOIN dbo.EstudianteGrupo eg ON eg.id = a.idEstudianteGrupo WHERE a.idSesion = @sLote AND eg.estudiante = @e2 AND d.codigoRazonCausa = N'SJC' AND d.asistio = 0)
        THROW 57222, 'TEST FAILED CULM001_B2_TOM_01: el lote congelado debe dejar un detalle por estudiante en la toma 1, visible en uv_detalle_asistencia.', 1;
    TRUNCATE TABLE #b2tR;

    -- --------------------------------------------------------------------------------------------------------
    -- B2-TOM-02: lote congelado repetido => actualiza el mismo detalle (sin segunda toma ni segundo detalle)
    -- --------------------------------------------------------------------------------------------------------
    SET @t1 = (SELECT id FROM dbo.TomaAsistencia WHERE sesion = @sLote);
    SET @corr = NEWID();
    SET @json = CONCAT(N'[{"idEstudiante":"', @e1, N'","estado":"SJC"}]');
    INSERT INTO #b2tR EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sLote, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF NOT EXISTS (SELECT 1 FROM #b2tR WHERE estado = 1)
       OR (SELECT COUNT(*) FROM dbo.TomaAsistencia WHERE sesion = @sLote) <> 1
       OR (SELECT COUNT(*) FROM dbo.DetalleAsistencia da INNER JOIN dbo.Asistencia a ON a.id = da.asistencia WHERE a.sesion = @sLote) <> 2
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_detalle_asistencia_v2 v INNER JOIN dbo.EstudianteGrupo eg ON eg.id = v.idEstudianteGrupo
                      WHERE v.idSesion = @sLote AND eg.estudiante = @e1 AND v.codigoRazonCausa = N'SJC' AND v.idToma = @t1 AND v.numeroToma = 1)
        THROW 57223, 'TEST FAILED CULM001_B2_TOM_02: el lote congelado repetido debe actualizar el detalle de la toma 1, sin crear otra toma.', 1;
    TRUNCATE TABLE #b2tR;
    PRINT 'TEST_PASS:CULM001_B2_TOM_02_LOTE_REPETIDO';

    -- Toma unica sobre una sesion ya vencida: el porcentaje por horas coincide con la formula anterior (sesiones de 2 h)
    UPDATE dbo.Sesion SET fechaHoraInicio = DATEADD(DAY, -1, fechaHoraInicio), fechaHoraFin = DATEADD(DAY, -1, fechaHoraFin), procedenciaTemporal = N'UTC_V2'
    WHERE id = @sLote;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_resumen_asistencia_estudiante_grupo r WHERE r.idGrupo = @g AND r.idEstudiante = @e1
                   AND r.sesionesEjecutadas = 1 AND r.tomasDictadas = 1 AND r.horasDictadas = 2.000000 AND r.faltasSinJustaCausa = 1 AND r.horasFalta = 2.000000
                   AND r.porcentajeInasistencia = 100.00 AND r.porcentajeInasistenciaSesiones = 100.00)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_resumen_asistencia_estudiante_grupo r WHERE r.idGrupo = @g AND r.idEstudiante = @e2
                   AND r.porcentajeInasistencia = r.porcentajeInasistenciaSesiones AND r.porcentajeInasistencia = 100.00)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_resumen_asistencia_estudiante_grupo r WHERE r.idGrupo = @g AND r.idEstudiante = @e3
                   AND r.porcentajeInasistencia = 0.00 AND r.porcentajeInasistenciaSesiones = 0.00 AND r.horasSinRegistro = 2.000000 AND r.porcentajeSinRegistroHoras = 100.00)
        THROW 57224, 'TEST FAILED CULM001_B2_TOM_01: con una toma por sesion de igual duracion porcentajeInasistencia debe ser igual a porcentajeInasistenciaSesiones.', 1;
    PRINT 'TEST_PASS:CULM001_B2_TOM_01_TOMA_UNICA_COMPORTAMIENTO_ACTUAL';

    -- --------------------------------------------------------------------------------------------------------
    -- B2-TOM-03: abrir MANUAL y QR dentro de la ventana; fuera de ventana SES_007/SES_008; cancelada SES_010
    -- --------------------------------------------------------------------------------------------------------
    SET @corr = NEWID();
    INSERT INTO #b2tA EXEC dbo.usp_abrir_toma_asistencia @idSesion = @sNow, @codigoModo = N'MANUAL', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    SET @t1 = (SELECT idToma FROM #b2tA WHERE estado = 1);
    IF @t1 IS NULL
       OR NOT EXISTS (SELECT 1 FROM #b2tA a INNER JOIN dbo.Sesion s ON s.id = @sNow
                      WHERE a.estado = 1 AND a.idCorrelacion = @corr AND a.mt LIKE N'DBCODE=TOM[_]008|%' AND a.numero = 1 AND a.codigoModo = N'MANUAL'
                        AND a.usaCodigoQr = 0 AND a.fechaAperturaUtc IS NOT NULL AND a.ventanaCierreUtc = CAST(DATEADD(MINUTE, 30, s.fechaHoraFin) AS DATETIME2(0))
                        AND a.totalTomasSesion = 1 AND a.horasToma = 2.000000)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_toma_asistencia WHERE idToma = @t1 AND estaAbierta = 1 AND fechaCierreUtc IS NULL AND esImplicita = 0
                      AND idDocenteApertura = @d1 AND codigoEstado = N'ABIERTA')
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_sesion_estado WHERE idSesion = @sNow AND totalTomas = 1 AND tieneTomaAbierta = 1 AND idTomaAbierta = @t1)
        THROW 57230, 'TEST FAILED CULM001_B2_TOM_03: abrir una toma MANUAL en ventana debe responder TOM_008 con numero 1 y la ventana con margen.', 1;
    TRUNCATE TABLE #b2tA;
    -- cierre de la MANUAL (sin marcar ausentes) y apertura QR => numero 2, horasToma = 1
    SET @corr = NEWID();
    INSERT INTO #b2tC EXEC dbo.usp_cerrar_toma_asistencia @idToma = @t1, @marcarAusentes = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF NOT EXISTS (SELECT 1 FROM #b2tC WHERE estado = 1 AND mt LIKE N'DBCODE=TOM[_]009|%' AND idToma = @t1 AND idSesion = @sNow AND idGrupo = @g
                   AND totalAusentesMarcados = 0 AND yaEstabaCerrada = 0 AND fechaCierreUtc IS NOT NULL)
        THROW 57231, 'TEST FAILED CULM001_B2_TOM_03: cerrar la toma MANUAL debe responder TOM_009 sin marcar ausentes.', 1;
    TRUNCATE TABLE #b2tC;
    SET @corr = NEWID();
    INSERT INTO #b2tA EXEC dbo.usp_abrir_toma_asistencia @idSesion = @sNow, @codigoModo = N' qr ', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    SET @t2 = (SELECT idToma FROM #b2tA WHERE estado = 1);
    IF @t2 IS NULL OR NOT EXISTS (SELECT 1 FROM #b2tA WHERE estado = 1 AND numero = 2 AND codigoModo = N'QR' AND usaCodigoQr = 1 AND totalTomasSesion = 2 AND horasToma = 1.000000)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_toma_asistencia WHERE idToma = @t1 AND horasToma = 1.000000 AND totalTomasSesion = 2)
       OR dbo.ufn_horas_toma(@sNow) <> 1.000000
        THROW 57232, 'TEST FAILED CULM001_B2_TOM_03: la segunda toma (QR) debe ser la numero 2 y repartir las 2 h de la sesion (1 h por toma).', 1;
    TRUNCATE TABLE #b2tA;
    SET @corr = NEWID();
    INSERT INTO #b2tA EXEC dbo.usp_abrir_toma_asistencia @idSesion = @sFut, @codigoModo = N'MANUAL', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    INSERT INTO #b2tA EXEC dbo.usp_abrir_toma_asistencia @idSesion = @sPast, @codigoModo = N'MANUAL', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    INSERT INTO #b2tA EXEC dbo.usp_abrir_toma_asistencia @idSesion = @sCanc, @codigoModo = N'QR', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF (SELECT COUNT(*) FROM #b2tA WHERE estado = 0 AND idToma IS NULL) <> 3
       OR NOT EXISTS (SELECT 1 FROM #b2tA WHERE mt LIKE N'DBCODE=SES[_]007|%')
       OR NOT EXISTS (SELECT 1 FROM #b2tA WHERE mt LIKE N'DBCODE=SES[_]008|%')
       OR NOT EXISTS (SELECT 1 FROM #b2tA WHERE mt LIKE N'DBCODE=SES[_]010|%')
       OR EXISTS (SELECT 1 FROM dbo.TomaAsistencia WHERE sesion IN (@sFut, @sPast, @sCanc))
        THROW 57233, 'TEST FAILED CULM001_B2_TOM_03: fuera de la ventana con tolerancia SES_007 / SES_008, sesion cancelada SES_010, sin escritura.', 1;
    TRUNCATE TABLE #b2tA;
    -- una sesion dentro del margen posterior (fin hace 10 min) admite abrir una toma (ventana [inicio - 15, fin + 30))
    SET @corr = NEWID();
    INSERT INTO #b2tA EXEC dbo.usp_abrir_toma_asistencia @idSesion = @sMargen, @codigoModo = N'MANUAL', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    SET @t3 = (SELECT idToma FROM #b2tA WHERE estado = 1);
    IF @t3 IS NULL
        THROW 57234, 'TEST FAILED CULM001_B2_TOM_03: dentro del margen de retardo se debe poder abrir una toma (tolerancia/margen del llamador).', 1;
    TRUNCATE TABLE #b2tA;
    PRINT 'TEST_PASS:CULM001_B2_TOM_03_ABRIR_EN_VENTANA';

    -- --------------------------------------------------------------------------------------------------------
    -- B2-TOM-04: otra abierta TOM_003 / quinta toma TOM_004 / modo FOO TOM_002 / no titular SEC_002 / estudiante SEC_001
    -- --------------------------------------------------------------------------------------------------------
    SET @corr = NEWID();
    INSERT INTO #b2tA EXEC dbo.usp_abrir_toma_asistencia @idSesion = @sNow, @codigoModo = N'MANUAL', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF NOT EXISTS (SELECT 1 FROM #b2tA WHERE estado = 0 AND mt LIKE N'DBCODE=TOM[_]003|%') OR (SELECT COUNT(*) FROM dbo.TomaAsistencia WHERE sesion = @sNow) <> 2
        THROW 57240, 'TEST FAILED CULM001_B2_TOM_04: con una toma abierta abrir otra debe responder TOM_003.', 1;
    TRUNCATE TABLE #b2tA;
    SET @n = 1;
    WHILE @n <= 4
    BEGIN
        SET @corr = NEWID();
        INSERT INTO #b2tA EXEC dbo.usp_abrir_toma_asistencia @idSesion = @sNow3, @codigoModo = N'MANUAL', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
        SET @t3 = (SELECT idToma FROM #b2tA WHERE estado = 1 AND numero = @n);
        IF @t3 IS NULL THROW 57241, 'TEST FAILED CULM001_B2_TOM_04: no se pudo abrir una de las 4 tomas permitidas.', 1;
        INSERT INTO #b2tC EXEC dbo.usp_cerrar_toma_asistencia @idToma = @t3, @marcarAusentes = 0, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
        SET @n += 1;
    END
    TRUNCATE TABLE #b2tA;
    SET @corr = NEWID();
    INSERT INTO #b2tA EXEC dbo.usp_abrir_toma_asistencia @idSesion = @sNow3, @codigoModo = N'MANUAL', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    INSERT INTO #b2tA EXEC dbo.usp_abrir_toma_asistencia @idSesion = @sNow4, @codigoModo = N'FOO', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    INSERT INTO #b2tA EXEC dbo.usp_abrir_toma_asistencia @idSesion = @sNow4, @codigoModo = N'MANUAL', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD2;
    INSERT INTO #b2tA EXEC dbo.usp_abrir_toma_asistencia @idSesion = @sNow4, @codigoModo = N'MANUAL', @idCorrelacion = @corr, @idUsuarioEjecutor = @uE1;
    INSERT INTO #b2tA EXEC dbo.usp_abrir_toma_asistencia @idSesion = @sNow4, @codigoModo = N'MANUAL', @idCorrelacion = @corr, @idUsuarioEjecutor = NULL;
    IF (SELECT COUNT(*) FROM dbo.TomaAsistencia WHERE sesion = @sNow3) <> 4 OR EXISTS (SELECT 1 FROM dbo.TomaAsistencia WHERE sesion = @sNow4)
       OR NOT EXISTS (SELECT 1 FROM #b2tA WHERE estado = 0 AND mt LIKE N'DBCODE=TOM[_]004|%' AND mu LIKE N'%4%')
       OR NOT EXISTS (SELECT 1 FROM #b2tA WHERE estado = 0 AND mt LIKE N'DBCODE=TOM[_]002|%')
       OR NOT EXISTS (SELECT 1 FROM #b2tA WHERE estado = 0 AND mt LIKE N'DBCODE=SEC[_]002|%')
       OR NOT EXISTS (SELECT 1 FROM #b2tA WHERE estado = 0 AND mt LIKE N'DBCODE=SEC[_]001|%')
       OR NOT EXISTS (SELECT 1 FROM #b2tA WHERE estado = 0 AND mt LIKE N'DBCODE=GEN[_]002|%')
       OR EXISTS (SELECT 1 FROM #b2tA WHERE estado = 1)
        THROW 57242, 'TEST FAILED CULM001_B2_TOM_04: quinta toma TOM_004, modo FOO TOM_002, no titular SEC_002, estudiante SEC_001, sin ejecutor GEN_002.', 1;
    TRUNCATE TABLE #b2tA; TRUNCATE TABLE #b2tC;
    PRINT 'TEST_PASS:CULM001_B2_TOM_04_REGLAS_DE_APERTURA';

    -- --------------------------------------------------------------------------------------------------------
    -- B2-TOM-05: lote por toma escribe en esa toma; el lote congelado con una toma ABIERTA escribe en la abierta
    -- --------------------------------------------------------------------------------------------------------
    SET @corr = NEWID();
    SET @json = CONCAT(N'[{"idEstudiante":"', @e1, N'","estado":"AN"}]');
    INSERT INTO #b2tL EXEC dbo.usp_registrar_asistencias_toma @idToma = @t2, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF NOT EXISTS (SELECT 1 FROM #b2tL WHERE estado = 1 AND mt LIKE N'DBCODE=TOM[_]010|%' AND idToma = @t2 AND idSesion = @sNow AND idGrupo = @g AND totalRegistros = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_detalle_asistencia_v2 v INNER JOIN dbo.EstudianteGrupo eg ON eg.id = v.idEstudianteGrupo
                      WHERE v.idToma = @t2 AND eg.estudiante = @e1 AND v.codigoRazonCausa = N'AN' AND v.registradoPorEstudiante = 0)
       OR EXISTS (SELECT 1 FROM dbo.DetalleAsistencia WHERE toma = @t1)
        THROW 57250, 'TEST FAILED CULM001_B2_TOM_05: el lote por toma debe escribir solo en la toma indicada (TOM_010).', 1;
    TRUNCATE TABLE #b2tL;
    SET @corr = NEWID();
    SET @json = CONCAT(N'[{"idEstudiante":"', @e2, N'","estado":"EX"}]');
    INSERT INTO #b2tR EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sNow, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF NOT EXISTS (SELECT 1 FROM #b2tR WHERE estado = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_detalle_asistencia_v2 v INNER JOIN dbo.EstudianteGrupo eg ON eg.id = v.idEstudianteGrupo
                      WHERE v.idToma = @t2 AND eg.estudiante = @e2 AND v.codigoRazonCausa = N'EX')
       OR (SELECT COUNT(*) FROM dbo.TomaAsistencia WHERE sesion = @sNow) <> 2
        THROW 57251, 'TEST FAILED CULM001_B2_TOM_05: con una toma ABIERTA el lote congelado debe escribir en la abierta (DEC-013).', 1;
    TRUNCATE TABLE #b2tR;
    -- lote por toma: estudiante inactivo EST_004 y estado invalido RC_001, sin escritura (mismas reglas del lote)
    SET @corr = NEWID();
    SET @json = CONCAT(N'[{"idEstudiante":"', (SELECT idEstudiante FROM #b2tE WHERE n = 5), N'","estado":"AN"}]');
    INSERT INTO #b2tL EXEC dbo.usp_registrar_asistencias_toma @idToma = @t2, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    SET @json = CONCAT(N'[{"idEstudiante":"', @e3, N'","estado":"T"}]');
    INSERT INTO #b2tL EXEC dbo.usp_registrar_asistencias_toma @idToma = @t2, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    INSERT INTO #b2tL EXEC dbo.usp_registrar_asistencias_toma @idToma = @t2, @asistenciaJSON = N'[]', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    INSERT INTO #b2tL EXEC dbo.usp_registrar_asistencias_toma @idToma = @t2, @asistenciaJSON = N'{"x":1}', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    SET @json = CONCAT(N'[{"idEstudiante":"', @e3, N'","estado":"AN"},{"idEstudiante":"', @e3, N'","estado":"SJC"}]');
    INSERT INTO #b2tL EXEC dbo.usp_registrar_asistencias_toma @idToma = @t2, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    SET @json = CONCAT(N'[{"idEstudiante":"', @e3, N'","estado":"AN"}]');
    INSERT INTO #b2tL EXEC dbo.usp_registrar_asistencias_toma @idToma = @sNow, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    INSERT INTO #b2tL EXEC dbo.usp_registrar_asistencias_toma @idToma = @t2, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD2;
    IF (SELECT COUNT(*) FROM #b2tL WHERE estado = 0) <> 7
       OR NOT EXISTS (SELECT 1 FROM #b2tL WHERE mt LIKE N'DBCODE=EST[_]004|%')
       OR NOT EXISTS (SELECT 1 FROM #b2tL WHERE mt LIKE N'DBCODE=RC[_]001|%')
       OR NOT EXISTS (SELECT 1 FROM #b2tL WHERE mt LIKE N'DBCODE=ATT[_]002|%')
       OR NOT EXISTS (SELECT 1 FROM #b2tL WHERE mt LIKE N'DBCODE=ATT[_]001|%')
       OR NOT EXISTS (SELECT 1 FROM #b2tL WHERE mt LIKE N'DBCODE=ATT[_]003|%')
       OR NOT EXISTS (SELECT 1 FROM #b2tL WHERE mt LIKE N'DBCODE=TOM[_]001|%')
       OR NOT EXISTS (SELECT 1 FROM #b2tL WHERE mt LIKE N'DBCODE=SEC[_]002|%')
       OR (SELECT COUNT(*) FROM dbo.DetalleAsistencia WHERE toma = @t2) <> 2
        THROW 57252, 'TEST FAILED CULM001_B2_TOM_05: el lote por toma debe aplicar EST_004/RC_001/ATT_001..003/TOM_001/SEC_002 sin escribir.', 1;
    TRUNCATE TABLE #b2tL;
    PRINT 'TEST_PASS:CULM001_B2_TOM_05_LOTE_POR_TOMA';

    -- --------------------------------------------------------------------------------------------------------
    -- B2-TOM-06: cerrar una toma QR sin @marcarAusentes => SJC a los activos sin registro (e3, e4); AN/EX intactos;
    -- matriculas CI / I sin fila. uv_faltantes_toma los lista con fueMarcadoAlCerrar = 1.
    -- --------------------------------------------------------------------------------------------------------
    SET @corr = NEWID();
    INSERT INTO #b2tC EXEC dbo.usp_cerrar_toma_asistencia @idToma = @t2, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF NOT EXISTS (SELECT 1 FROM #b2tC WHERE estado = 1 AND mt LIKE N'DBCODE=TOM[_]009|%' AND mu LIKE N'%2%' AND totalAusentesMarcados = 2 AND totalFaltantes = 2 AND yaEstabaCerrada = 0)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_toma_asistencia WHERE idToma = @t2 AND estaAbierta = 0 AND fechaCierreUtc IS NOT NULL AND totalAusentesMarcados = 2
                      AND totalRegistros = 4 AND totalPresentes = 1 AND totalExcusas = 1 AND totalAusentes = 2)
       OR (SELECT COUNT(*) FROM dbo.uv_faltantes_toma WHERE idToma = @t2 AND tieneRegistro = 1 AND codigoRazonCausa = N'SJC' AND fueMarcadoAlCerrar = 1
           AND idEstudiante IN (@e3, @e4)) <> 2
       OR (SELECT COUNT(*) FROM dbo.uv_faltantes_toma WHERE idToma = @t2) <> 2
       OR EXISTS (SELECT 1 FROM dbo.DetalleAsistencia da INNER JOIN dbo.Asistencia a ON a.id = da.asistencia INNER JOIN #b2tE e ON e.idEG = a.estudianteGrupo
                  WHERE da.toma = @t2 AND e.n IN (5, 6))
       OR EXISTS (SELECT 1 FROM dbo.uv_detalle_asistencia_v2 v INNER JOIN dbo.EstudianteGrupo eg ON eg.id = v.idEstudianteGrupo
                  WHERE v.idToma = @t2 AND ((eg.estudiante = @e1 AND v.codigoRazonCausa <> N'AN') OR (eg.estudiante = @e2 AND v.codigoRazonCausa <> N'EX')))
       OR EXISTS (SELECT 1 FROM dbo.uv_detalle_asistencia_v2 v WHERE v.idToma = @t2 AND v.asistio <> IIF(v.codigoRazonCausa = N'AN', 1, 0))
        THROW 57260, 'TEST FAILED CULM001_B2_TOM_06: cerrar una toma QR debe marcar SJC solo a los activos sin registro y dejar AN/EX intactos.', 1;
    TRUNCATE TABLE #b2tC;
    PRINT 'TEST_PASS:CULM001_B2_TOM_06_CIERRE_QR_MARCA_SJC';

    -- --------------------------------------------------------------------------------------------------------
    -- B2-TOM-08: cerrar dos veces => TOM_011 idempotente, sin SJC duplicados
    -- --------------------------------------------------------------------------------------------------------
    SET @corr = NEWID();
    INSERT INTO #b2tC EXEC dbo.usp_cerrar_toma_asistencia @idToma = @t2, @marcarAusentes = 1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF NOT EXISTS (SELECT 1 FROM #b2tC WHERE estado = 1 AND mt LIKE N'DBCODE=TOM[_]011|%' AND yaEstabaCerrada = 1 AND totalAusentesMarcados = 2)
       OR (SELECT COUNT(*) FROM dbo.DetalleAsistencia WHERE toma = @t2) <> 4
        THROW 57280, 'TEST FAILED CULM001_B2_TOM_08: cerrar una toma ya cerrada debe responder TOM_011 sin escribir.', 1;
    TRUNCATE TABLE #b2tC;
    PRINT 'TEST_PASS:CULM001_B2_TOM_08_CIERRE_IDEMPOTENTE';

    -- --------------------------------------------------------------------------------------------------------
    -- B2-TOM-09: despues del cierre el docente marca AN a un faltante con el lote por toma dentro de la ventana;
    -- el lote congelado con todas las tomas cerradas escribe en la ultima; fuera de la ventana SES_008
    -- --------------------------------------------------------------------------------------------------------
    SET @corr = NEWID();
    SET @json = CONCAT(N'[{"idEstudiante":"', @e4, N'","estado":"AN"}]');
    INSERT INTO #b2tL EXEC dbo.usp_registrar_asistencias_toma @idToma = @t2, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF NOT EXISTS (SELECT 1 FROM #b2tL WHERE estado = 1)
       OR EXISTS (SELECT 1 FROM dbo.uv_faltantes_toma WHERE idToma = @t2 AND idEstudiante = @e4)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_faltantes_toma WHERE idToma = @t2 AND idEstudiante = @e3)
        THROW 57290, 'TEST FAILED CULM001_B2_TOM_09: marcar AN a un faltante en una toma cerrada dentro de la ventana debe sacarlo de uv_faltantes_toma.', 1;
    TRUNCATE TABLE #b2tL;
    SET @corr = NEWID();
    SET @json = CONCAT(N'[{"idEstudiante":"', @e3, N'","estado":"AN"}]');
    INSERT INTO #b2tR EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sNow, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF NOT EXISTS (SELECT 1 FROM #b2tR WHERE estado = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_detalle_asistencia_v2 v INNER JOIN dbo.EstudianteGrupo eg ON eg.id = v.idEstudianteGrupo
                      WHERE v.idToma = @t2 AND eg.estudiante = @e3 AND v.codigoRazonCausa = N'AN')
       OR EXISTS (SELECT 1 FROM dbo.DetalleAsistencia WHERE toma = @t1)
       OR (SELECT COUNT(*) FROM dbo.TomaAsistencia WHERE sesion = @sNow) <> 2
        THROW 57291, 'TEST FAILED CULM001_B2_TOM_05: con todas las tomas cerradas el lote congelado debe escribir en la ultima toma.', 1;
    TRUNCATE TABLE #b2tR;
    DECLARE @tPast UNIQUEIDENTIFIER;
    EXEC #culm001_b2_crear_toma @idSesion = @sPast, @idToma = @tPast OUTPUT;
    SET @corr = NEWID();
    SET @json = CONCAT(N'[{"idEstudiante":"', @e1, N'","estado":"AN"}]');
    INSERT INTO #b2tL EXEC dbo.usp_registrar_asistencias_toma @idToma = @tPast, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF NOT EXISTS (SELECT 1 FROM #b2tL WHERE estado = 0 AND mt LIKE N'DBCODE=SES[_]008|%') OR EXISTS (SELECT 1 FROM dbo.DetalleAsistencia WHERE toma = @tPast)
        THROW 57292, 'TEST FAILED CULM001_B2_TOM_09: fuera de la ventana con margen el lote por toma debe responder SES_008 sin escribir.', 1;
    TRUNCATE TABLE #b2tL;
    PRINT 'TEST_PASS:CULM001_B2_TOM_09_FALTANTES_Y_CORRECCION';

    -- --------------------------------------------------------------------------------------------------------
    -- B2-TOM-07: cerrar una toma MANUAL sin @marcarAusentes no infiere faltas; con @marcarAusentes = 1 si
    -- --------------------------------------------------------------------------------------------------------
    SET @corr = NEWID();
    INSERT INTO #b2tA EXEC dbo.usp_abrir_toma_asistencia @idSesion = @sNow2, @codigoModo = N'MANUAL', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    SET @t3 = (SELECT idToma FROM #b2tA WHERE estado = 1);
    TRUNCATE TABLE #b2tA;
    SET @json = CONCAT(N'[{"idEstudiante":"', @e1, N'","estado":"AN"}]');
    INSERT INTO #b2tL EXEC dbo.usp_registrar_asistencias_toma @idToma = @t3, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    INSERT INTO #b2tC EXEC dbo.usp_cerrar_toma_asistencia @idToma = @t3, @marcarAusentes = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF @t3 IS NULL OR NOT EXISTS (SELECT 1 FROM #b2tC WHERE estado = 1 AND totalAusentesMarcados = 0 AND totalFaltantes = 3)
       OR (SELECT COUNT(*) FROM dbo.DetalleAsistencia WHERE toma = @t3) <> 1
       OR (SELECT COUNT(*) FROM dbo.uv_faltantes_toma WHERE idToma = @t3 AND tieneRegistro = 0 AND idDetalleAsistencia IS NULL AND codigoRazonCausa IS NULL AND fueMarcadoAlCerrar = 0) <> 3
        THROW 57270, 'TEST FAILED CULM001_B2_TOM_07: cerrar una toma MANUAL sin @marcarAusentes no debe inferir faltas (regla actual).', 1;
    TRUNCATE TABLE #b2tC; TRUNCATE TABLE #b2tL;
    SET @corr = NEWID();
    INSERT INTO #b2tA EXEC dbo.usp_abrir_toma_asistencia @idSesion = @sNow2, @codigoModo = N'MANUAL', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    SET @t3 = (SELECT idToma FROM #b2tA WHERE estado = 1);
    TRUNCATE TABLE #b2tA;
    INSERT INTO #b2tC EXEC dbo.usp_cerrar_toma_asistencia @idToma = @t3, @marcarAusentes = 1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF @t3 IS NULL OR NOT EXISTS (SELECT 1 FROM #b2tC WHERE estado = 1 AND totalAusentesMarcados = 4 AND totalFaltantes = 4)
       OR (SELECT COUNT(*) FROM dbo.DetalleAsistencia da INNER JOIN dbo.RazonCausa rc ON rc.id = da.razonCausa WHERE da.toma = @t3 AND rc.codigo = N'SJC' AND da.asistio = 0) <> 4
       OR (SELECT COUNT(*) FROM dbo.Asistencia WHERE sesion = @sNow2) <> 4
        THROW 57271, 'TEST FAILED CULM001_B2_TOM_07: cerrar una toma MANUAL con @marcarAusentes = 1 debe marcar SJC a los 4 activos sin registro.', 1;
    TRUNCATE TABLE #b2tC;
    PRINT 'TEST_PASS:CULM001_B2_TOM_07_CIERRE_MANUAL';

    -- --------------------------------------------------------------------------------------------------------
    -- B2-TOM-10: usp_cerrar_tomas_vencidas cierra solo tomas abiertas con ventana vencida o sesion cancelada; QR marca SJC
    -- --------------------------------------------------------------------------------------------------------
    DECLARE @tVencQr UNIQUEIDENTIFIER = NEWID(), @tCancMan UNIQUEIDENTIFIER = NEWID(), @tVigente UNIQUEIDENTIFIER = NEWID();
    DELETE FROM dbo.DetalleAsistencia WHERE toma = @tPast;
    DELETE FROM dbo.TomaAsistencia WHERE id = @tPast;
    INSERT INTO dbo.TomaAsistencia (id, sesion, numero, modo, estado, esImplicita, docenteApertura, fechaAperturaUtc, fechaCierreUtc, idCorrelacionApertura)
    VALUES (@tVencQr, @sPast, 1, @modoQr, @estAbierta, 0, @d1, DATEADD(MINUTE, -290, SYSUTCDATETIME()), NULL, NEWID()),
           (@tCancMan, @sCanc, 1, @modoManual, @estAbierta, 0, @d1, DATEADD(MINUTE, -20, SYSUTCDATETIME()), NULL, NEWID()),
           (@tVigente, @sNow4, 1, @modoQr, @estAbierta, 0, @d1, DATEADD(MINUTE, -20, SYSUTCDATETIME()), NULL, NEWID());
    SET @corr = NEWID();
    INSERT INTO #b2tV EXEC dbo.usp_cerrar_tomas_vencidas @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #b2tV WHERE idToma = @tVencQr AND idSesion = @sPast AND idGrupo = @g AND totalAusentesMarcados = 4)
       OR NOT EXISTS (SELECT 1 FROM #b2tV WHERE idToma = @tCancMan AND idSesion = @sCanc AND totalAusentesMarcados = 0)
       OR EXISTS (SELECT 1 FROM #b2tV WHERE idToma = @tVigente)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_toma_asistencia WHERE idToma = @tVencQr AND estaAbierta = 0 AND fechaCierreUtc IS NOT NULL AND totalAusentesMarcados = 4 AND totalAusentes = 4)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_toma_asistencia WHERE idToma = @tCancMan AND estaAbierta = 0 AND totalRegistros = 0)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_toma_asistencia WHERE idToma = @tVigente AND estaAbierta = 1)
        THROW 57300, 'TEST FAILED CULM001_B2_TOM_10: usp_cerrar_tomas_vencidas debe cerrar solo tomas vencidas o de sesiones canceladas (QR marca SJC).', 1;
    TRUNCATE TABLE #b2tV;
    SET @corr = NEWID();
    INSERT INTO #b2tV EXEC dbo.usp_cerrar_tomas_vencidas @idCorrelacion = @corr;
    IF EXISTS (SELECT 1 FROM #b2tV WHERE idToma IN (@tVencQr, @tCancMan, @tVigente))
       OR (SELECT COUNT(*) FROM dbo.DetalleAsistencia WHERE toma = @tVencQr) <> 4
        THROW 57301, 'TEST FAILED CULM001_B2_TOM_10: una segunda pasada no debe volver a cerrar la misma toma.', 1;
    TRUNCATE TABLE #b2tV;
    PRINT 'TEST_PASS:CULM001_B2_TOM_10_CIERRE_AUTOMATICO';

    -- --------------------------------------------------------------------------------------------------------
    -- B2-TOM-12: con una TomaAsistencia (sin Asistencia) la sesion ya no se cancela (SES_012, §2.7.2 paso 8)
    -- --------------------------------------------------------------------------------------------------------
    SET @corr = NEWID();
    INSERT INTO #b2tK EXEC dbo.usp_cancelar_sesion @idSesion = @sNow4, @motivo = N'Motivo valido de prueba B2', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF NOT EXISTS (SELECT 1 FROM #b2tK WHERE estado = 0 AND mt LIKE N'DBCODE=SES[_]012|%') OR EXISTS (SELECT 1 FROM dbo.SesionCancelacion WHERE sesion = @sNow4)
        THROW 57310, 'TEST FAILED CULM001_B2_TOM_12: una sesion con TomaAsistencia no se cancela (SES_012).', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_cumplimiento_sesion_grupo WHERE idSesion = @sNow4 AND tieneRegistroAsistencia = 1 AND totalTomas = 1 AND horasSesion = 2.000000)
        THROW 57311, 'TEST FAILED CULM001_B2_TOM_12: una toma sin lecturas cuenta como registro en uv_cumplimiento_sesion_grupo (SUPUESTO-B-06).', 1;
    TRUNCATE TABLE #b2tK;
    PRINT 'TEST_PASS:CULM001_B2_TOM_12_CANCELAR_CON_TOMA';

    -- --------------------------------------------------------------------------------------------------------
    -- Consultas de B.2: tomas de la sesion (con ventana; sin tomas una fila de la sesion), faltantes y asistencias
    -- --------------------------------------------------------------------------------------------------------
    SET @corr = NEWID();
    INSERT INTO #b2tS EXEC dbo.usp_consultar_tomas_sesion @idUsuarioEjecutor = @uD1, @idCorrelacion = @corr, @idSesion = @sNow;
    IF (SELECT COUNT(*) FROM #b2tS) <> 2
       OR NOT EXISTS (SELECT 1 FROM #b2tS WHERE numero = 1 AND idToma = @t1 AND codigoModo = N'MANUAL' AND ventanaAbierta = 1 AND maximoTomas = 4
                      AND totalTomasSesion = 2 AND horasSesion = 2.000000 AND horasToma = 1.000000 AND estaSesionCancelada = 0 AND tieneQrActivo = 0)
       OR NOT EXISTS (SELECT 1 FROM #b2tS WHERE numero = 2 AND idToma = @t2 AND codigoModo = N'QR' AND totalPresentes = 3 AND totalExcusas = 1)
        THROW 57320, 'TEST FAILED CULM001_B2_CONSULTAS: usp_consultar_tomas_sesion debe devolver las tomas de la sesion en orden con su ventana.', 1;
    TRUNCATE TABLE #b2tS;
    INSERT INTO #b2tS EXEC dbo.usp_consultar_tomas_sesion @idUsuarioEjecutor = @uD1, @idCorrelacion = @corr, @idSesion = @sFut;
    INSERT INTO #b2tS EXEC dbo.usp_consultar_tomas_sesion @idUsuarioEjecutor = @uD1, @idCorrelacion = @corr, @idSesion = @sCanc;
    IF (SELECT COUNT(*) FROM #b2tS) <> 2
       OR NOT EXISTS (SELECT 1 FROM #b2tS WHERE idSesion = @sFut AND idToma IS NULL AND totalTomasSesion = 0 AND ventanaAbierta = 0 AND ventanaAperturaUtc IS NOT NULL)
       OR NOT EXISTS (SELECT 1 FROM #b2tS WHERE idSesion = @sCanc AND idToma = @tCancMan AND estaSesionCancelada = 1 AND motivoCancelacion = N'CULMB2 cancelada por el docente' AND horasToma = 0)
        THROW 57321, 'TEST FAILED CULM001_B2_CONSULTAS: sin tomas usp_consultar_tomas_sesion devuelve la fila de la sesion; cancelada con su motivo.', 1;
    TRUNCATE TABLE #b2tS;
    INSERT INTO #b2tF EXEC dbo.usp_consultar_faltantes_toma_paginado @idUsuarioEjecutor = @uD1, @idCorrelacion = @corr, @idToma = @tVencQr, @numeroPagina = 1, @tamanoPagina = 3;
    IF (SELECT COUNT(*) FROM #b2tF) <> 3 OR EXISTS (SELECT 1 FROM #b2tF WHERE totalRegistros <> 4 OR fueMarcadoAlCerrar <> 1)
        THROW 57322, 'TEST FAILED CULM001_B2_CONSULTAS: usp_consultar_faltantes_toma_paginado debe paginar los 4 faltantes marcados.', 1;
    TRUNCATE TABLE #b2tF;
    INSERT INTO #b2tF EXEC dbo.usp_consultar_faltantes_toma_paginado @idUsuarioEjecutor = @uD1, @idCorrelacion = @corr, @idToma = @tVencQr, @numeroPagina = 2, @tamanoPagina = 3;
    IF (SELECT COUNT(*) FROM #b2tF) <> 1
        THROW 57323, 'TEST FAILED CULM001_B2_CONSULTAS: la pagina 2 de faltantes debe tener 1 fila.', 1;
    TRUNCATE TABLE #b2tF;
    INSERT INTO #b2tT EXEC dbo.usp_consultar_asistencias_toma_paginado @idUsuarioEjecutor = @uD1, @idCorrelacion = @corr, @idToma = @t3, @numeroPagina = 1, @tamanoPagina = 50;
    IF (SELECT COUNT(*) FROM #b2tT) <> 4 OR EXISTS (SELECT 1 FROM #b2tT WHERE totalRegistros <> 4 OR codigoRazonCausa <> N'SJC' OR registradoPorEstudiante <> 0)
        THROW 57324, 'TEST FAILED CULM001_B2_CONSULTAS: usp_consultar_asistencias_toma_paginado debe listar las 4 matriculas activas con su detalle.', 1;
    TRUNCATE TABLE #b2tT;
    INSERT INTO #b2tT EXEC dbo.usp_consultar_asistencias_toma_paginado @idUsuarioEjecutor = @uD1, @idCorrelacion = @corr, @idToma = @tVigente, @numeroPagina = 1, @tamanoPagina = 50;
    IF (SELECT COUNT(*) FROM #b2tT WHERE codigoRazonCausa IS NULL AND registradoPorEstudiante IS NULL) <> 4
        THROW 57325, 'TEST FAILED CULM001_B2_CONSULTAS: una toma sin registros lista a los activos con estado NULL.', 1;
    TRUNCATE TABLE #b2tT;
    PRINT 'TEST_PASS:CULM001_B2_TOM_CONSULTAS';

    -- --------------------------------------------------------------------------------------------------------
    -- B2-TOM-11: invariante estaAbierta <=> fechaCierreUtc IS NULL, una abierta por sesion y coherencia de SesionCancelacion
    -- --------------------------------------------------------------------------------------------------------
    IF EXISTS (SELECT 1 FROM dbo.TomaAsistencia t INNER JOIN dbo.EstadoTomaAsistencia e ON e.id = t.estado
               WHERE (e.estaAbierta = 1 AND t.fechaCierreUtc IS NOT NULL) OR (e.estaAbierta = 0 AND t.fechaCierreUtc IS NULL))
       OR EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc INNER JOIN dbo.TipoCancelacionSesion t ON t.id = sc.tipoCancelacion
                  WHERE (t.esAutomatica = 1 AND sc.diaFestivo IS NULL) OR (t.esAutomatica = 0 AND sc.diaFestivo IS NOT NULL))
       OR EXISTS (SELECT 1 FROM dbo.DetalleAsistencia da INNER JOIN dbo.TomaAsistencia t ON t.id = da.toma INNER JOIN dbo.Asistencia a ON a.id = da.asistencia
                  WHERE a.sesion <> t.sesion)
        THROW 57330, 'TEST FAILED CULM001_B2_TOM_11: invariantes de TomaAsistencia o de SesionCancelacion violados.', 1;
    PRINT 'TEST_PASS:CULM001_B2_INV_TOMA_ESTADO_CIERRE';

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @err NVARCHAR(4000) = ERROR_MESSAGE();
    PRINT CONCAT('TEST FAILED: ', @err);
    THROW;
END CATCH;
GO

-- Validaciones de las consultas (READ_QUERY_RESULTSET con THROW 51000) fuera de transaccion, con datos existentes:
-- toma inexistente TOM_001, ejecutor no titular SEC_002, ejecutor NULL GEN_002.
DECLARE @corr UNIQUEIDENTIFIER = NEWID(), @ok INT = 0, @msg NVARCHAR(4000);
DECLARE @toma UNIQUEIDENTIFIER, @sesion UNIQUEIDENTIFIER, @ajeno UNIQUEIDENTIFIER;
SELECT TOP 1 @toma = t.id, @sesion = t.sesion FROM dbo.TomaAsistencia t ORDER BY t.id;
SELECT TOP 1 @ajeno = di.idUsuario FROM dbo.uv_docente_identidad di
WHERE di.estaActivoUsuario = 1
  AND (@sesion IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.Sesion s INNER JOIN dbo.Grupo g ON g.id = s.grupo WHERE s.id = @sesion AND g.docente = di.id))
ORDER BY di.id;
CREATE TABLE #b2qF (idToma UNIQUEIDENTIFIER, idSesion UNIQUEIDENTIFIER, idGrupo UNIQUEIDENTIFIER, numeroToma SMALLINT, idEstudianteGrupo UNIQUEIDENTIFIER,
    idEstudiante UNIQUEIDENTIFIER, nombreCompletoEstudiante NVARCHAR(400), tieneRegistro BIT, idDetalleAsistencia UNIQUEIDENTIFIER,
    codigoRazonCausa NVARCHAR(10), fueMarcadoAlCerrar BIT, totalRegistros INT);
BEGIN TRY
    INSERT INTO #b2qF EXEC dbo.usp_consultar_faltantes_toma_paginado @idUsuarioEjecutor = @ajeno, @idCorrelacion = @corr, @idToma = @corr;
END TRY
BEGIN CATCH
    SET @msg = ERROR_MESSAGE();
    IF ERROR_NUMBER() = 51000 AND @msg LIKE N'DBCODE=TOM[_]001|%' SET @ok += 1;
END CATCH;
IF @toma IS NOT NULL AND @ajeno IS NOT NULL
BEGIN
    BEGIN TRY
        INSERT INTO #b2qF EXEC dbo.usp_consultar_faltantes_toma_paginado @idUsuarioEjecutor = @ajeno, @idCorrelacion = @corr, @idToma = @toma;
    END TRY
    BEGIN CATCH
        SET @msg = ERROR_MESSAGE();
        IF ERROR_NUMBER() = 51000 AND @msg LIKE N'DBCODE=SEC[_]002|%' SET @ok += 1;
    END CATCH;
END
ELSE SET @ok += 1;
BEGIN TRY
    INSERT INTO #b2qF EXEC dbo.usp_consultar_faltantes_toma_paginado @idUsuarioEjecutor = NULL, @idCorrelacion = @corr, @idToma = @toma;
END TRY
BEGIN CATCH
    SET @msg = ERROR_MESSAGE();
    IF ERROR_NUMBER() = 51000 AND @msg LIKE N'DBCODE=GEN[_]002|%' SET @ok += 1;
END CATCH;
IF @toma IS NOT NULL AND @ajeno IS NOT NULL
BEGIN
    BEGIN TRY
        INSERT INTO #b2qF EXEC dbo.usp_consultar_faltantes_toma_paginado @idUsuarioEjecutor = @ajeno, @idCorrelacion = @corr, @idToma = @toma, @numeroPagina = 0, @tamanoPagina = 50;
    END TRY
    BEGIN CATCH
        SET @msg = ERROR_MESSAGE();
        IF ERROR_NUMBER() = 51000 AND @msg LIKE N'DBCODE=PAG[_]001|%' SET @ok += 1;
    END CATCH;
END
ELSE SET @ok += 1;
DROP TABLE #b2qF;
IF @ok <> 4 OR @@TRANCOUNT <> 0
    THROW 57340, 'TEST FAILED CULM001_B2_CONSULTAS_VALIDACION: las consultas de B.2 deben lanzar 51000 con TOM_001 / SEC_002 / GEN_002 / PAG_001.', 1;
PRINT 'TEST_PASS:CULM001_B2_TOM_CONSULTAS_VALIDACION';
GO

IF @@TRANCOUNT <> 0
    THROW 57399, 'TEST FAILED CULM001_B2_TOM: @@TRANCOUNT distinto de 0 al terminar.', 1;
PRINT 'TEST_PASS:CULM001_B2_TOM_TRANCOUNT_ZERO';
PRINT 'TEST END: test_culm001_b2_tomas';
GO
