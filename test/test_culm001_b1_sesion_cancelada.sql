USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- CULM-001 B.1 (CONTRACT §2.2, §2.5, §2.6, §2.7.2, §2.7.3, §2.16.1 B1-CAN-01..08): HU047 cancelar sesion con
-- justificacion. Sesion futura o sin asistencia (tambien pasada) se cancela; con asistencia SES_012 (ventana vigente)
-- o SES_016 (ventana terminada); doble cancelacion SES_011; motivo fuera de 10..500 SES_013. La sesion cancelada sale
-- de uv_cumplimiento_sesion_grupo y se expone en uv_sesion_estado. Todo dentro de una transaccion revertida.
-- La prueba up -> down -> up de la migracion 15 la ejecuta test/test_culm001_b1.ps1 (CULM001_B1_MIG_*).
PRINT 'TEST START: test_culm001_b1_sesion_cancelada (CULM-001 B.1, HU047)';

IF OBJECT_ID(N'dbo.SesionCancelacion', N'U') IS NULL OR OBJECT_ID(N'dbo.TipoCancelacionSesion', N'U') IS NULL
   OR OBJECT_ID(N'dbo.uv_sesion_estado', N'V') IS NULL OR OBJECT_ID(N'dbo.uv_tipo_cancelacion_sesion', N'V') IS NULL
   OR OBJECT_ID(N'dbo.usp_cancelar_sesion', N'P') IS NULL OR OBJECT_ID(N'dbo.usp_consultar_destinatarios_sesion_cancelada', N'P') IS NULL
    THROW 57100, 'TEST FAILED CULM001_B1_CAN_00: faltan objetos de B.1 (SesionCancelacion, TipoCancelacionSesion, uv_sesion_estado, uv_tipo_cancelacion_sesion, usp_cancelar_sesion, usp_consultar_destinatarios_sesion_cancelada).', 1;
-- Catalogo con exactamente un tipo por bandera (ids fijos de la semilla 34)
IF (SELECT COUNT(*) FROM dbo.uv_tipo_cancelacion_sesion) <> 2
   OR NOT EXISTS (SELECT 1 FROM dbo.uv_tipo_cancelacion_sesion WHERE id = '7C1E0B10-5E51-4C0A-9A01-000000000001' AND codigo = N'DOCENTE' AND esAutomatica = 0)
   OR NOT EXISTS (SELECT 1 FROM dbo.uv_tipo_cancelacion_sesion WHERE id = '7C1E0B10-5E51-4C0A-9A01-000000000002' AND codigo = N'FESTIVO' AND esAutomatica = 1)
    THROW 57101, 'TEST FAILED CULM001_B1_CAN_00: TipoCancelacionSesion no tiene las 2 filas de la semilla (DOCENTE/0, FESTIVO/1).', 1;
IF dbo.ufn_obtener_parametro_int(NULL, 'SESION', 'MOTIVO_CANCELACION_LONGITUD_MINIMA') <> 10
   OR dbo.ufn_obtener_parametro_int(NULL, 'SESION', 'MOTIVO_CANCELACION_LONGITUD_MAXIMA') <> 500
    THROW 57102, 'TEST FAILED CULM001_B1_CAN_00: parametros SESION/MOTIVO_CANCELACION_LONGITUD_* ausentes o distintos de 10/500.', 1;
IF EXISTS (SELECT 1 FROM (VALUES ('SES_010'), ('SES_011'), ('SES_012'), ('SES_013'), ('SES_014'), ('SES_016')) c(codigo)
           WHERE NOT EXISTS (SELECT 1 FROM dbo.uv_mensaje_usuario u WHERE u.codigo = c.codigo)
              OR NOT EXISTS (SELECT 1 FROM dbo.uv_mensaje_tecnico t WHERE t.codigo = c.codigo))
   OR EXISTS (SELECT 1 FROM dbo.uv_mensaje_usuario WHERE codigo = 'SES_015')
    THROW 57103, 'TEST FAILED CULM001_B1_CAN_00: mensajes SES_010..SES_014/SES_016 ausentes o SES_015 (reservado) sembrado.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.PlantillaNotificacion WHERE tipo = 'SESION_CANCELADA' AND activa = 1)
   OR (SELECT COUNT(*) FROM dbo.PlantillaNotificacionMarcador WHERE tipo = 'SESION_CANCELADA'
       AND marcador IN ('estudiante', 'asignatura', 'grupo', 'fecha', 'horaInicio', 'horaFin', 'motivo', 'docente')) <> 8
    THROW 57104, 'TEST FAILED CULM001_B1_CAN_00: plantilla SESION_CANCELADA o sus 8 marcadores ausentes.', 1;
-- Columnas de uv_sesion_estado (§2.5)
IF (SELECT COUNT(*) FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.uv_sesion_estado') AND name IN (
        'idSesion', 'idGrupo', 'numero', 'nombre', 'fechaHoraInicio', 'fechaHoraFin', 'procedenciaTemporal', 'estaCancelada',
        'idTipoCancelacion', 'codigoTipoCancelacion', 'nombreTipoCancelacion', 'esCancelacionAutomatica', 'motivoCancelacion',
        'idDiaFestivo', 'nombreDiaFestivo', 'fechaCancelacionUtc', 'idUsuarioCancelacion', 'ventanaAperturaUtc', 'ventanaCierreUtc',
        'ventanaAbierta', 'horasSesion')) <> 21
    THROW 57105, 'TEST FAILED CULM001_B1_CAN_00: uv_sesion_estado no expone las 21 columnas del contrato.', 1;
IF (SELECT COUNT(*) FROM dbo.uv_sesion_estado) <> (SELECT COUNT(*) FROM dbo.uv_sesion_v2)
    THROW 57106, 'TEST FAILED CULM001_B1_CAN_00: uv_sesion_estado debe tener exactamente una fila por sesion.', 1;
PRINT 'TEST_PASS:CULM001_B1_CAN_00_OBJETOS_Y_SEMILLAS';
GO

DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @idAsig UNIQUEIDENTIFIER, @idProg UNIQUEIDENTIFIER, @uCoord UNIQUEIDENTIFIER, @idInstitucion UNIQUEIDENTIFIER;
SELECT TOP 1 @idAsig = a.id, @idProg = pe.idPrograma, @uCoord = ci.idUsuario, @idInstitucion = pr.idInstitucion
FROM dbo.uv_asignatura a
INNER JOIN dbo.uv_semestre_plan_estudio spe ON a.idSemestrePlanEstudio = spe.id
INNER JOIN dbo.uv_plan_estudio pe ON spe.idPlanEstudio = pe.id
INNER JOIN dbo.uv_programa pr ON pe.idPrograma = pr.id
INNER JOIN dbo.uv_coordinador_identidad ci ON ci.id = pr.idCoordinador
WHERE pr.estaActivoPrograma = 1 AND ci.estaActivoUsuario = 1 AND ci.estaActivoRolCoordinador = 1 AND a.estaActivaAsignatura = 1
ORDER BY a.id;
DECLARE @estadoA UNIQUEIDENTIFIER = (SELECT id FROM dbo.uv_estado_estudiante_grupo WHERE codigo = 'A');
DECLARE @estadoI UNIQUEIDENTIFIER = (SELECT id FROM dbo.uv_estado_estudiante_grupo WHERE codigo = 'I');
DECLARE @zona SYSNAME = dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER');
DECLARE @hoy DATE = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE @zona AS DATE);
IF @tipoCC IS NULL OR @idAsig IS NULL OR @uCoord IS NULL OR @idInstitucion IS NULL OR @estadoA IS NULL OR @estadoI IS NULL
    THROW 57110, 'TEST FAILED CULM001_B1_CAN: faltan fixtures del seed (asignatura con coordinador, estados A/I).', 1;

CREATE TABLE #culm1Cancel (
    idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(4000) NULL, mensajeTecnicoResultado NVARCHAR(4000) NULL,
    estadoResultado BIT NOT NULL, idSesion UNIQUEIDENTIFIER NULL, idGrupo UNIQUEIDENTIFIER NULL, fechaCancelacionUtc DATETIME2(0) NULL,
    totalEstudiantesActivos INT NULL);
CREATE TABLE #culm1Kpi (
    idPrograma UNIQUEIDENTIFIER, nombrePrograma NVARCHAR(200), idPeriodoAcademico UNIQUEIDENTIFIER, nombrePeriodoAcademico NVARCHAR(100),
    totalEstudiantes INT, estudiantesRegulares INT, estudiantesRiesgo INT, estudiantesPerdida INT, tasaPermanencia DECIMAL(5,2),
    sesionesProgramadas INT, sesionesVencidas INT, sesionesEjecutadas INT, sesionesVencidasSinRegistro INT, sesionesSinProcedenciaTemporal INT,
    porcentajeCumplimiento DECIMAL(5,2), porcentajeProgresoCalendario DECIMAL(5,2), umbralAdvertencia DECIMAL(5,2), umbralPerdida DECIMAL(5,2));
CREATE TABLE #culm1Dest (
    idEstudiante UNIQUEIDENTIFIER, idUsuario UNIQUEIDENTIFIER, nombreCompleto NVARCHAR(400), correo NVARCHAR(200), nombreAsignatura NVARCHAR(200),
    nombreGrupo NVARCHAR(300), nombreDocente NVARCHAR(400), fechaHoraInicio DATETIME2, fechaHoraFin DATETIME2, motivoCancelacion NVARCHAR(500));

DECLARE @userMsg NVARCHAR(4000), @techMsg NVARCHAR(4000), @corr UNIQUEIDENTIFIER, @err NVARCHAR(4000);

BEGIN TRANSACTION;
BEGIN TRY
    -- Fixture: docente titular, otro docente, 2 estudiantes activos y 1 inactivo, periodo vigente y grupo del programa
    DECLARE @uD1 UNIQUEIDENTIFIER = NEWID(), @uD2 UNIQUEIDENTIFIER = NEWID(), @uE1 UNIQUEIDENTIFIER = NEWID(), @uE2 UNIQUEIDENTIFIER = NEWID(), @uE3 UNIQUEIDENTIFIER = NEWID();
    DECLARE @d1 UNIQUEIDENTIFIER = NEWID(), @d2 UNIQUEIDENTIFIER = NEWID(), @e1 UNIQUEIDENTIFIER = NEWID(), @e2 UNIQUEIDENTIFIER = NEWID(), @e3 UNIQUEIDENTIFIER = NEWID();
    DECLARE @tag NVARCHAR(12) = LEFT(REPLACE(CONVERT(NVARCHAR(36), NEWID()), N'-', N''), 12);
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uD1, @tipoCC, 981000000 + ABS(CHECKSUM(NEWID()) % 999999), N'Titular', N'Culm', N'Diana', N'B1', CONCAT(N'culm1.d1.', @tag, N'@test.local'), 1, 1, N'HashBackend_CULM1'),
           (@uD2, @tipoCC, 982000000 + ABS(CHECKSUM(NEWID()) % 999999), N'Ajeno', N'Culm', N'Dario', N'B1', CONCAT(N'culm1.d2.', @tag, N'@test.local'), 1, 1, N'HashBackend_CULM1'),
           (@uE1, @tipoCC, 983000000 + ABS(CHECKSUM(NEWID()) % 999999), N'Uno', N'Culm', N'Elena', N'B1', CONCAT(N'culm1.e1.', @tag, N'@test.local'), 1, 1, N'HashBackend_CULM1'),
           (@uE2, @tipoCC, 984000000 + ABS(CHECKSUM(NEWID()) % 999999), N'Dos', N'Culm', N'Ernesto', N'B1', CONCAT(N'culm1.e2.', @tag, N'@test.local'), 1, 1, N'HashBackend_CULM1'),
           (@uE3, @tipoCC, 985000000 + ABS(CHECKSUM(NEWID()) % 999999), N'Tres', N'Culm', N'Eva', N'B1', CONCAT(N'culm1.e3.', @tag, N'@test.local'), 1, 1, N'HashBackend_CULM1');
    INSERT INTO dbo.Docente (id, usuario) VALUES (@d1, @uD1), (@d2, @uD2);
    INSERT INTO dbo.Estudiante (id, usuario) VALUES (@e1, @uE1), (@e2, @uE2), (@e3, @uE3);

    DECLARE @per UNIQUEIDENTIFIER = NEWID(), @g UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@per, @idInstitucion, N'CULM1 periodo cancelacion', 3100000 + ABS(CHECKSUM(NEWID()) % 800000), DATEADD(DAY, -30, @hoy), DATEADD(DAY, 30, @hoy), YEAR(@hoy));
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
        cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@g, @idAsig, @per, 940000 + ABS(CHECKSUM(NEWID()) % 59999), N'CULM1 Grupo cancelacion', 30, 0, 0, 0, @d1);
    DECLARE @eg1 UNIQUEIDENTIFIER = NEWID(), @eg2 UNIQUEIDENTIFIER = NEWID(), @eg3 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo) VALUES (@eg1, @estadoA, @e1, @g), (@eg2, @estadoA, @e2, @g), (@eg3, @estadoI, @e3, @g);

    DECLARE @sFut UNIQUEIDENTIFIER = NEWID(), @sFut2 UNIQUEIDENTIFIER = NEWID(), @sPastNoAtt UNIQUEIDENTIFIER = NEWID();
    DECLARE @sAttOpen UNIQUEIDENTIFIER = NEWID(), @sAttEnded UNIQUEIDENTIFIER = NEWID(), @sNormal UNIQUEIDENTIFIER = NEWID();
    DECLARE @sAttMargen UNIQUEIDENTIFIER = NEWID();
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    VALUES (@sFut,       N'CULM1-CAN futura',            1, N'CULM1A', 1, @g, DATEADD(DAY, 2, SYSUTCDATETIME()),  DATEADD(MINUTE, 2 * 1440 + 120, SYSUTCDATETIME()), N'UTC_V2'),
           (@sFut2,      N'CULM1-CAN futura 2',          2, N'CULM1B', 1, @g, DATEADD(DAY, 3, SYSUTCDATETIME()),  DATEADD(MINUTE, 3 * 1440 + 120, SYSUTCDATETIME()), N'UTC_V2'),
           (@sPastNoAtt, N'CULM1-CAN pasada sin asist.', 3, N'CULM1C', 1, @g, DATEADD(DAY, -3, SYSUTCDATETIME()), DATEADD(MINUTE, -3 * 1440 + 120, SYSUTCDATETIME()), N'UTC_V2'),
           (@sAttOpen,   N'CULM1-CAN en curso con asist', 4, N'CULM1D', 1, @g, DATEADD(HOUR, -1, SYSUTCDATETIME()), DATEADD(HOUR, 1, SYSUTCDATETIME()), N'UTC_V2'),
           (@sAttEnded,  N'CULM1-CAN terminada c/asist', 5, N'CULM1E', 1, @g, DATEADD(DAY, -4, SYSUTCDATETIME()), DATEADD(MINUTE, -4 * 1440 + 120, SYSUTCDATETIME()), N'UTC_V2'),
           (@sNormal,    N'CULM1-CAN normal',            6, N'CULM1F', 1, @g, DATEADD(DAY, -5, SYSUTCDATETIME()), DATEADD(MINUTE, -5 * 1440 + 120, SYSUTCDATETIME()), N'UTC_V2'),
           -- fin hace 10 min: con asistencia y dentro del margen de 30 min => SES_012 (no SES_016)
           (@sAttMargen, N'CULM1-CAN en margen c/asist', 7, N'CULM1G', 1, @g, DATEADD(MINUTE, -130, SYSUTCDATETIME()), DATEADD(MINUTE, -10, SYSUTCDATETIME()), N'UTC_V2');
    INSERT dbo.Asistencia (id, estudianteGrupo, sesion) VALUES (NEWID(), @eg1, @sAttOpen), (NEWID(), @eg1, @sAttEnded), (NEWID(), @eg1, @sAttMargen);

    -- KPI del coordinador antes de cancelar (B1-CAN-06)
    SET @corr = NEWID();
    INSERT INTO #culm1Kpi EXEC dbo.usp_consultar_kpis_coordinador @idUsuarioEjecutor = @uCoord, @idCorrelacion = @corr, @idPeriodoAcademico = @per;
    DECLARE @progAntes INT, @vencAntes INT, @ejecAntes INT;
    SELECT @progAntes = sesionesProgramadas, @vencAntes = sesionesVencidas, @ejecAntes = sesionesEjecutadas FROM #culm1Kpi;
    IF @progAntes IS NULL OR @progAntes < 7
        THROW 57111, 'TEST FAILED CULM001_B1_CAN_06: el KPI del coordinador no ve las sesiones del grupo de prueba.', 1;

    -- --------------------------------------------------------------------------------------------------------
    -- Validaciones previas: ejecutor NULL (GEN_002) y sesion inexistente (SES_001)
    -- --------------------------------------------------------------------------------------------------------
    SET @corr = NEWID();
    INSERT INTO #culm1Cancel EXEC dbo.usp_cancelar_sesion @idSesion = @sFut, @motivo = N'Motivo valido de prueba', @idCorrelacion = @corr, @idUsuarioEjecutor = NULL;
    IF NOT EXISTS (SELECT 1 FROM #culm1Cancel WHERE estadoResultado = 0 AND idCorrelacion = @corr AND mensajeTecnicoResultado LIKE N'DBCODE=GEN[_]002|%' AND idSesion IS NULL)
        THROW 57112, 'TEST FAILED CULM001_B1_CAN_GEN002: sin ejecutor debe responder GEN_002.', 1;
    TRUNCATE TABLE #culm1Cancel;
    SET @corr = NEWID();
    INSERT INTO #culm1Cancel EXEC dbo.usp_cancelar_sesion @idSesion = @uD1, @motivo = N'Motivo valido de prueba', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF NOT EXISTS (SELECT 1 FROM #culm1Cancel WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SES[_]001|%')
        THROW 57113, 'TEST FAILED CULM001_B1_CAN_SES001: una sesion inexistente debe responder SES_001.', 1;
    TRUNCATE TABLE #culm1Cancel;
    PRINT 'TEST_PASS:CULM001_B1_CAN_VALIDACIONES_PREVIAS';

    -- --------------------------------------------------------------------------------------------------------
    -- B1-CAN-02: no titular / estudiante / coordinador => SEC_002 o RBAC (SEC_001); sin fila
    -- --------------------------------------------------------------------------------------------------------
    SET @corr = NEWID();
    INSERT INTO #culm1Cancel EXEC dbo.usp_cancelar_sesion @idSesion = @sFut, @motivo = N'Motivo valido de prueba', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD2;
    INSERT INTO #culm1Cancel EXEC dbo.usp_cancelar_sesion @idSesion = @sFut, @motivo = N'Motivo valido de prueba', @idCorrelacion = @corr, @idUsuarioEjecutor = @uE1;
    INSERT INTO #culm1Cancel EXEC dbo.usp_cancelar_sesion @idSesion = @sFut, @motivo = N'Motivo valido de prueba', @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF (SELECT COUNT(*) FROM #culm1Cancel WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SEC[_]00[12]|%') <> 3
       OR NOT EXISTS (SELECT 1 FROM #culm1Cancel WHERE mensajeTecnicoResultado LIKE N'DBCODE=SEC[_]002|%')
       OR EXISTS (SELECT 1 FROM dbo.SesionCancelacion WHERE sesion = @sFut)
        THROW 57120, 'TEST FAILED CULM001_B1_CAN_02: un no titular, un estudiante o un coordinador no pueden cancelar (SEC_002/SEC_001, sin fila).', 1;
    TRUNCATE TABLE #culm1Cancel;
    PRINT 'TEST_PASS:CULM001_B1_CAN_02_SOLO_TITULAR';

    -- --------------------------------------------------------------------------------------------------------
    -- B1-CAN-03: motivo de 9 / 501 caracteres / solo espacios / 9 tras recortar => SES_013 con los limites
    -- --------------------------------------------------------------------------------------------------------
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SES_013', @p_param1 = N'10', @p_param2 = N'500',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    SET @corr = NEWID();
    INSERT INTO #culm1Cancel EXEC dbo.usp_cancelar_sesion @idSesion = @sFut, @motivo = N'123456789', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    DECLARE @m501 NVARCHAR(600) = REPLICATE(N'x', 501);
    INSERT INTO #culm1Cancel EXEC dbo.usp_cancelar_sesion @idSesion = @sFut, @motivo = @m501, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    INSERT INTO #culm1Cancel EXEC dbo.usp_cancelar_sesion @idSesion = @sFut, @motivo = N'            ', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    INSERT INTO #culm1Cancel EXEC dbo.usp_cancelar_sesion @idSesion = @sFut, @motivo = N'    123456789     ', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    INSERT INTO #culm1Cancel EXEC dbo.usp_cancelar_sesion @idSesion = @sFut, @motivo = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF (SELECT COUNT(*) FROM #culm1Cancel WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SES[_]013|%' AND mensajeUsuarioResultado = @userMsg) <> 5
       OR EXISTS (SELECT 1 FROM dbo.SesionCancelacion WHERE sesion = @sFut)
       OR @userMsg NOT LIKE N'%10%500%'
        THROW 57130, 'TEST FAILED CULM001_B1_CAN_03: motivos fuera de 10..500 (tras recortar) deben responder SES_013 con los limites y sin escribir.', 1;
    TRUNCATE TABLE #culm1Cancel;
    PRINT 'TEST_PASS:CULM001_B1_CAN_03_MOTIVO_SES013';

    -- --------------------------------------------------------------------------------------------------------
    -- B1-CAN-01: el titular cancela una sesion futura sin registros (motivo recortado)
    -- --------------------------------------------------------------------------------------------------------
    SET @corr = NEWID();
    INSERT INTO #culm1Cancel EXEC dbo.usp_cancelar_sesion @idSesion = @sFut, @motivo = N'   Calamidad domestica del docente   ', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF NOT EXISTS (SELECT 1 FROM #culm1Cancel WHERE estadoResultado = 1 AND idCorrelacion = @corr AND mensajeTecnicoResultado LIKE N'DBCODE=SES[_]014|%'
                   AND idSesion = @sFut AND idGrupo = @g AND fechaCancelacionUtc IS NOT NULL AND totalEstudiantesActivos = 2)
        THROW 57140, 'TEST FAILED CULM001_B1_CAN_01: la cancelacion del titular debe responder SES_014 con idSesion, idGrupo, fecha y 2 estudiantes activos.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc JOIN dbo.TipoCancelacionSesion t ON t.id = sc.tipoCancelacion
                   WHERE sc.sesion = @sFut AND t.esAutomatica = 0 AND sc.usuarioEjecutor = @uD1 AND sc.diaFestivo IS NULL
                     AND sc.motivo = N'Calamidad domestica del docente' AND sc.idCorrelacion = @corr)
        THROW 57141, 'TEST FAILED CULM001_B1_CAN_01: la fila de SesionCancelacion no refleja el contrato (tipo manual, usuario, motivo recortado, correlacion).', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_sesion_estado WHERE idSesion = @sFut AND estaCancelada = 1 AND codigoTipoCancelacion = N'DOCENTE'
                   AND esCancelacionAutomatica = 0 AND motivoCancelacion = N'Calamidad domestica del docente' AND idUsuarioCancelacion = @uD1
                   AND idDiaFestivo IS NULL AND ventanaAbierta = 0)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_sesion_estado WHERE idSesion = @sFut2 AND estaCancelada = 0 AND codigoTipoCancelacion IS NULL)
        THROW 57142, 'TEST FAILED CULM001_B1_CAN_01: uv_sesion_estado no refleja la cancelacion.', 1;
    TRUNCATE TABLE #culm1Cancel;
    PRINT 'TEST_PASS:CULM001_B1_CAN_01_TITULAR_CANCELA';

    -- uv_sesion_estado: ventana con tolerancia/margen y horas de la sesion
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_sesion_estado v JOIN dbo.Sesion s ON s.id = v.idSesion
                   WHERE v.idSesion = @sAttOpen AND v.ventanaAbierta = 1 AND v.horasSesion = 2.000000
                     AND v.ventanaAperturaUtc = DATEADD(MINUTE, -15, s.fechaHoraInicio) AND v.ventanaCierreUtc = DATEADD(MINUTE, 30, s.fechaHoraFin))
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_sesion_estado WHERE idSesion = @sAttMargen AND ventanaAbierta = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_sesion_estado WHERE idSesion = @sNormal AND ventanaAbierta = 0)
        THROW 57143, 'TEST FAILED CULM001_B1_CAN_ESTADO: uv_sesion_estado no calcula la ventana [inicio - 15, fin + 30) ni horasSesion.', 1;
    PRINT 'TEST_PASS:CULM001_B1_CAN_UV_SESION_ESTADO_VENTANA';

    -- --------------------------------------------------------------------------------------------------------
    -- B1-CAN-05: cancelar dos veces => SES_011 y motivo original intacto
    -- --------------------------------------------------------------------------------------------------------
    SET @corr = NEWID();
    INSERT INTO #culm1Cancel EXEC dbo.usp_cancelar_sesion @idSesion = @sFut, @motivo = N'Otro motivo distinto de prueba', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF NOT EXISTS (SELECT 1 FROM #culm1Cancel WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SES[_]011|%' AND idSesion IS NULL)
       OR NOT EXISTS (SELECT 1 FROM dbo.SesionCancelacion WHERE sesion = @sFut AND motivo = N'Calamidad domestica del docente')
       OR (SELECT COUNT(*) FROM dbo.SesionCancelacion WHERE sesion = @sFut) <> 1
        THROW 57150, 'TEST FAILED CULM001_B1_CAN_05: la segunda cancelacion debe responder SES_011 y conservar el motivo original.', 1;
    TRUNCATE TABLE #culm1Cancel;
    PRINT 'TEST_PASS:CULM001_B1_CAN_05_DOBLE_SES011';

    -- --------------------------------------------------------------------------------------------------------
    -- B1-CAN-04 / B1-CAN-08: con asistencia => SES_012 (ventana vigente) o SES_016 (terminada); pasada sin asistencia se cancela
    -- --------------------------------------------------------------------------------------------------------
    SET @corr = NEWID();
    INSERT INTO #culm1Cancel EXEC dbo.usp_cancelar_sesion @idSesion = @sAttOpen, @motivo = N'Motivo valido de prueba', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    INSERT INTO #culm1Cancel EXEC dbo.usp_cancelar_sesion @idSesion = @sAttMargen, @motivo = N'Motivo valido de prueba', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF (SELECT COUNT(*) FROM #culm1Cancel WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SES[_]012|%') <> 2
       OR EXISTS (SELECT 1 FROM dbo.SesionCancelacion WHERE sesion IN (@sAttOpen, @sAttMargen))
        THROW 57160, 'TEST FAILED CULM001_B1_CAN_04: una sesion con asistencia y ventana vigente (en curso o dentro del margen) debe responder SES_012 sin fila.', 1;
    TRUNCATE TABLE #culm1Cancel;
    PRINT 'TEST_PASS:CULM001_B1_CAN_04_CON_ASISTENCIA_SES012';

    SET @corr = NEWID();
    INSERT INTO #culm1Cancel EXEC dbo.usp_cancelar_sesion @idSesion = @sAttEnded, @motivo = N'Motivo valido de prueba', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF NOT EXISTS (SELECT 1 FROM #culm1Cancel WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SES[_]016|%')
       OR EXISTS (SELECT 1 FROM dbo.SesionCancelacion WHERE sesion = @sAttEnded)
        THROW 57161, 'TEST FAILED CULM001_B1_CAN_08: una sesion terminada con asistencia debe responder SES_016 sin fila.', 1;
    TRUNCATE TABLE #culm1Cancel;
    SET @corr = NEWID();
    INSERT INTO #culm1Cancel EXEC dbo.usp_cancelar_sesion @idSesion = @sPastNoAtt, @motivo = N'Se reporta que la clase no se dicto', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD1;
    IF NOT EXISTS (SELECT 1 FROM #culm1Cancel WHERE estadoResultado = 1 AND mensajeTecnicoResultado LIKE N'DBCODE=SES[_]014|%')
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_sesion_estado WHERE idSesion = @sPastNoAtt AND estaCancelada = 1)
        THROW 57162, 'TEST FAILED CULM001_B1_CAN_08: una sesion pasada sin asistencia debe poder cancelarse.', 1;
    TRUNCATE TABLE #culm1Cancel;
    PRINT 'TEST_PASS:CULM001_B1_CAN_08_PASADA_Y_TERMINADA';

    -- --------------------------------------------------------------------------------------------------------
    -- B1-CAN-06: la sesion cancelada sale del cumplimiento (programadas -2: @sFut y @sPastNoAtt; vencidas -1)
    -- --------------------------------------------------------------------------------------------------------
    IF EXISTS (SELECT 1 FROM dbo.uv_cumplimiento_sesion_grupo WHERE idSesion IN (@sFut, @sPastNoAtt))
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_cumplimiento_sesion_grupo WHERE idSesion = @sNormal)
        THROW 57170, 'TEST FAILED CULM001_B1_CAN_06: uv_cumplimiento_sesion_grupo debe excluir solo las sesiones canceladas.', 1;
    TRUNCATE TABLE #culm1Kpi;
    SET @corr = NEWID();
    INSERT INTO #culm1Kpi EXEC dbo.usp_consultar_kpis_coordinador @idUsuarioEjecutor = @uCoord, @idCorrelacion = @corr, @idPeriodoAcademico = @per;
    IF NOT EXISTS (SELECT 1 FROM #culm1Kpi WHERE sesionesProgramadas = @progAntes - 2 AND sesionesVencidas = @vencAntes - 1 AND sesionesEjecutadas = @ejecAntes
                   AND porcentajeProgresoCalendario = CAST(IIF(@progAntes - 2 = 0, NULL, 100.0 * (@vencAntes - 1) / (@progAntes - 2)) AS DECIMAL(5,2))
                   AND ISNULL(porcentajeCumplimiento, -1) = ISNULL(CAST(IIF(@vencAntes - 1 = 0, NULL, 100.0 * @ejecAntes / (@vencAntes - 1)) AS DECIMAL(5,2)), -1))
        THROW 57171, 'TEST FAILED CULM001_B1_CAN_06: el KPI del coordinador sigue contando las sesiones canceladas.', 1;
    PRINT 'TEST_PASS:CULM001_B1_CAN_06_FUERA_DE_CUMPLIMIENTO';

    -- --------------------------------------------------------------------------------------------------------
    -- B1-CAN-07: destinatarios = matriculas A de la sesion cancelada; sesion no cancelada => sin filas; no titular => THROW
    -- --------------------------------------------------------------------------------------------------------
    SET @corr = NEWID();
    INSERT INTO #culm1Dest EXEC dbo.usp_consultar_destinatarios_sesion_cancelada @idUsuarioEjecutor = @uD1, @idCorrelacion = @corr, @idSesion = @sFut;
    IF (SELECT COUNT(*) FROM #culm1Dest) <> 2
       OR EXISTS (SELECT 1 FROM #culm1Dest WHERE idEstudiante NOT IN (@e1, @e2))
       OR EXISTS (SELECT 1 FROM #culm1Dest WHERE idUsuario NOT IN (@uE1, @uE2) OR correo NOT LIKE N'culm1.e%@test.local'
                  OR motivoCancelacion <> N'Calamidad domestica del docente' OR nombreAsignatura IS NULL OR nombreGrupo IS NULL
                  OR nombreDocente NOT LIKE N'%Diana%' OR fechaHoraInicio IS NULL OR fechaHoraFin IS NULL OR nombreCompleto IS NULL)
        THROW 57180, 'TEST FAILED CULM001_B1_CAN_07: los destinatarios deben ser solo las 2 matriculas activas, con correo, docente y motivo.', 1;
    TRUNCATE TABLE #culm1Dest;
    INSERT INTO #culm1Dest EXEC dbo.usp_consultar_destinatarios_sesion_cancelada @idUsuarioEjecutor = @uD1, @idCorrelacion = @corr, @idSesion = @sFut2;
    IF EXISTS (SELECT 1 FROM #culm1Dest)
        THROW 57181, 'TEST FAILED CULM001_B1_CAN_07: una sesion no cancelada no debe tener destinatarios.', 1;
    PRINT 'TEST_PASS:CULM001_B1_CAN_07_DESTINATARIOS';

    -- Invariante de coherencia tipo/diaFestivo en toda la tabla
    IF EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc JOIN dbo.TipoCancelacionSesion t ON t.id = sc.tipoCancelacion
               WHERE (t.esAutomatica = 1 AND sc.diaFestivo IS NULL) OR (t.esAutomatica = 0 AND (sc.diaFestivo IS NOT NULL OR sc.usuarioEjecutor IS NULL)))
        THROW 57190, 'TEST FAILED INV_SESION_CANCELACION_COHERENTE: tipo automatico <=> diaFestivo NOT NULL.', 1;
    PRINT 'TEST_PASS:CULM001_B1_INV_SESION_CANCELACION_COHERENTE';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DROP TABLE IF EXISTS #culm1Cancel, #culm1Kpi, #culm1Dest;
    THROW;
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
DROP TABLE IF EXISTS #culm1Cancel, #culm1Kpi, #culm1Dest;
IF @@TRANCOUNT <> 0 THROW 57199, 'TEST FAILED CULM001_B1_CAN: quedaron transacciones abiertas.', 1;
IF EXISTS (SELECT 1 FROM dbo.Sesion WHERE nombre LIKE N'CULM1-CAN%')
    THROW 57198, 'TEST FAILED CULM001_B1_CAN: quedaron sesiones de prueba CULM1-CAN.', 1;
PRINT 'TEST_PASS:CULM001_B1_CAN_TRANCOUNT_ZERO';
GO

-- B1-CAN-07 (ambito): un docente no titular recibe SEC_002 (THROW 51000). Fuera de la transaccion de la prueba porque
-- el THROW de un SP de consulta con SET XACT_ABORT ON condena la transaccion del llamador.
DECLARE @sesionAjena UNIQUEIDENTIFIER, @docenteAjeno UNIQUEIDENTIFIER, @err NVARCHAR(4000) = NULL, @corr UNIQUEIDENTIFIER = NEWID();
SELECT TOP 1 @sesionAjena = s.id, @docenteAjeno = di2.idUsuario
FROM dbo.uv_sesion s
JOIN dbo.uv_grupo g ON g.id = s.idGrupo
JOIN dbo.uv_docente_identidad di2 ON di2.id <> g.idDocente AND di2.estaActivoUsuario = 1
WHERE NOT EXISTS (SELECT 1 FROM dbo.uv_grupo g2 JOIN dbo.uv_docente_identidad d3 ON d3.id = g2.idDocente
                  WHERE g2.id = s.idGrupo AND d3.idUsuario = di2.idUsuario)
ORDER BY s.id, di2.id;
IF @sesionAjena IS NULL THROW 57183, 'TEST FAILED CULM001_B1_CAN_07: no hay sesion con un docente no titular para la prueba de ambito.', 1;
CREATE TABLE #culm1DestAjeno (idEstudiante UNIQUEIDENTIFIER, idUsuario UNIQUEIDENTIFIER, nombreCompleto NVARCHAR(400), correo NVARCHAR(200), nombreAsignatura NVARCHAR(200),
    nombreGrupo NVARCHAR(300), nombreDocente NVARCHAR(400), fechaHoraInicio DATETIME2, fechaHoraFin DATETIME2, motivoCancelacion NVARCHAR(500));
BEGIN TRY
    INSERT INTO #culm1DestAjeno EXEC dbo.usp_consultar_destinatarios_sesion_cancelada @idUsuarioEjecutor = @docenteAjeno, @idCorrelacion = @corr, @idSesion = @sesionAjena;
END TRY
BEGIN CATCH
    SET @err = ERROR_MESSAGE();
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
IF @err IS NULL OR @err NOT LIKE N'%DBCODE=SEC[_]002|%' OR EXISTS (SELECT 1 FROM #culm1DestAjeno)
    THROW 57182, 'TEST FAILED CULM001_B1_CAN_07: un docente no titular debe recibir SEC_002 (THROW) al consultar destinatarios.', 1;
DROP TABLE #culm1DestAjeno;
PRINT 'TEST_PASS:CULM001_B1_CAN_07_AMBITO_SEC002';
PRINT 'TEST END: test_culm001_b1_sesion_cancelada';
GO
