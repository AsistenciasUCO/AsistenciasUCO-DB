USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- CULM-001 B.2 (CONTRACT §2.4, §2.5, §2.6, §2.9, §2.16.2 B2-HOR-01..09, B2-HOR-11): inasistencia por horas (DEC-012 + DEC-024).
--   horasToma = horasSesion / tomas de la sesion; horasDictadas = suma de horasSesion de las sesiones vencidas, con registro y
--   no canceladas (sin mirar el estado de la toma); EX fuera de las faltas y dentro del denominador; porcentajeInasistencia y
--   codigoPermanencia por horas con el mismo nombre; porcentajeInasistenciaSesiones con la formula anterior (trazabilidad).
-- Fixtures por insercion directa (sesiones ya vencidas) dentro de una transaccion revertida. Requiere el helper de tomas.
PRINT 'TEST START: test_culm001_b2_horas (CULM-001 B.2, DEC-012, DEC-024)';

IF (SELECT COUNT(*) FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.uv_resumen_asistencia_estudiante_grupo') AND name IN (
        'idEstudianteGrupo', 'idEstudiante', 'idGrupo', 'idAsignatura', 'idPrograma', 'idPeriodoAcademico', 'codigoEstadoEstudiante',
        'sesionesEjecutadas', 'asistencias', 'faltasSinJustaCausa', 'excusas', 'porcentajeInasistencia', 'codigoPermanencia',
        'tomasDictadas', 'horasDictadas', 'horasAsistidas', 'horasFalta', 'horasExcusa', 'horasSinRegistro', 'porcentajeAsistenciaHoras',
        'porcentajeExcusaHoras', 'porcentajeSinRegistroHoras', 'porcentajeInasistenciaSesiones', 'umbralAdvertencia', 'umbralPerdida',
        'sesionesAsistidas', 'sesionesConFaltaSinJustaCausa', 'sesionesConExcusa')) <> 28
   OR (SELECT COUNT(*) FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.uv_asistencia_sesion_horas') AND name IN (
        'idAsistencia', 'idEstudianteGrupo', 'idSesion', 'idGrupo', 'totalTomasSesion', 'tomasConRegistro', 'horasSesion', 'horasAsistidas',
        'horasFalta', 'horasExcusa', 'horasSinRegistro', 'codigoRazonCausaConsolidado', 'esParcial', 'tieneFaltaSinJustaCausa')) <> 14
   OR (SELECT system_type_name FROM sys.dm_exec_describe_first_result_set(N'SELECT porcentajeInasistencia FROM dbo.uv_resumen_asistencia_estudiante_grupo', NULL, 0)) <> 'decimal(5,2)'
   OR (SELECT system_type_name FROM sys.dm_exec_describe_first_result_set(N'SELECT horasDictadas FROM dbo.uv_resumen_asistencia_estudiante_grupo', NULL, 0)) <> 'decimal(12,6)'
    THROW 57600, 'TEST FAILED CULM001_B2_HOR_00: uv_resumen_asistencia_estudiante_grupo / uv_asistencia_sesion_horas sin las columnas del contrato.', 1;
-- Funciones (§2.4)
IF dbo.ufn_horas_sesion('2026-01-01T08:00:00', '2026-01-01T10:30:00') <> 2.500000
   OR dbo.ufn_horas_sesion('2026-01-01T10:00:00', '2026-01-01T08:00:00') <> 0
   OR dbo.ufn_horas_sesion(NULL, '2026-01-01T08:00:00') <> 0
   OR dbo.ufn_calcular_porcentaje_inasistencia_horas(1, 3) <> 33.33
   OR dbo.ufn_calcular_porcentaje_inasistencia_horas(2, 3) <> 66.67
   OR dbo.ufn_calcular_porcentaje_inasistencia_horas(5, 0) <> 0
   OR dbo.ufn_calcular_porcentaje_inasistencia_horas(5, NULL) <> 0
   OR dbo.ufn_calcular_porcentaje_inasistencia_horas(7, 4) <> 100.00
   OR dbo.ufn_calcular_porcentaje_inasistencia_horas(-1, 4) <> 0.00
   OR dbo.ufn_horas_toma(NEWID()) <> 0
    THROW 57601, 'TEST FAILED CULM001_B2_HOR_00: ufn_horas_sesion / ufn_calcular_porcentaje_inasistencia_horas / ufn_horas_toma no cumplen el contrato.', 1;
PRINT 'TEST_PASS:CULM001_B2_HOR_00_FUNCIONES_Y_COLUMNAS';
GO

DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @estadoA UNIQUEIDENTIFIER = (SELECT id FROM dbo.uv_estado_estudiante_grupo WHERE codigo = 'A');
DECLARE @tipoManual UNIQUEIDENTIFIER = (SELECT id FROM dbo.TipoCancelacionSesion WHERE esAutomatica = 0);
DECLARE @modoManual UNIQUEIDENTIFIER = (SELECT id FROM dbo.ModoTomaAsistencia WHERE usaCodigoQr = 0);
DECLARE @estCerrada UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoTomaAsistencia WHERE estaAbierta = 0);
DECLARE @pending UNIQUEIDENTIFIER = (SELECT id FROM dbo.Estado WHERE codigo = 'P');
DECLARE @zona SYSNAME = dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER');
DECLARE @hoy DATE = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE @zona AS DATE);
-- Ambito real del seed: asignatura de un programa con coordinador activo, decano de su facultad y administrador de su institucion
DECLARE @idAsig UNIQUEIDENTIFIER, @idProg UNIQUEIDENTIFIER, @idFac UNIQUEIDENTIFIER, @idInst UNIQUEIDENTIFIER;
DECLARE @uCoord UNIQUEIDENTIFIER, @uDec UNIQUEIDENTIFIER, @uAdm UNIQUEIDENTIFIER;
SELECT TOP 1 @idAsig = a.id, @idProg = pr.id, @idFac = pr.idFacultad, @idInst = pr.idInstitucion, @uCoord = ci.idUsuario, @uDec = di.idUsuario, @uAdm = ad.idUsuario
FROM dbo.uv_asignatura a
INNER JOIN dbo.uv_semestre_plan_estudio spe ON a.idSemestrePlanEstudio = spe.id
INNER JOIN dbo.uv_plan_estudio pe ON spe.idPlanEstudio = pe.id
INNER JOIN dbo.uv_programa pr ON pe.idPrograma = pr.id
INNER JOIN dbo.uv_coordinador_identidad ci ON ci.id = pr.idCoordinador
INNER JOIN dbo.uv_facultad f ON f.id = pr.idFacultad
INNER JOIN dbo.uv_decano_identidad di ON di.id = f.idDecano
INNER JOIN dbo.uv_administrador ad ON ad.idInstitucion = pr.idInstitucion
WHERE pr.estaActivoPrograma = 1 AND ci.estaActivoUsuario = 1 AND ci.estaActivoRolCoordinador = 1 AND a.estaActivaAsignatura = 1
  AND di.estaActivoUsuario = 1 AND ad.estaActivoUsuario = 1 AND ad.estaActivoAdministrador = 1
ORDER BY a.id;
IF @tipoCC IS NULL OR @estadoA IS NULL OR @tipoManual IS NULL OR @modoManual IS NULL OR @estCerrada IS NULL OR @pending IS NULL
   OR @idAsig IS NULL OR @uCoord IS NULL OR @uDec IS NULL OR @uAdm IS NULL
    THROW 57610, 'TEST FAILED CULM001_B2_HOR: faltan fixtures del seed (programa con coordinador, decano y administrador activos).', 1;

CREATE TABLE #b2hS (k NVARCHAR(10) PRIMARY KEY, id UNIQUEIDENTIFIER, grupo NVARCHAR(4), horas INT, diasAtras INT, tomas INT);
CREATE TABLE #b2hD (k NVARCHAR(10), est INT, tomaNum INT, codigo NVARCHAR(5));
CREATE TABLE #b2hKc (idPrograma UNIQUEIDENTIFIER, nombrePrograma NVARCHAR(50), idPeriodoAcademico UNIQUEIDENTIFIER, nombrePeriodoAcademico NVARCHAR(50),
    totalEstudiantes INT, estudiantesRegulares INT, estudiantesRiesgo INT, estudiantesPerdida INT, tasaPermanencia DECIMAL(5,2),
    sesionesProgramadas INT, sesionesVencidas INT, sesionesEjecutadas INT, sesionesVencidasSinRegistro INT, sesionesSinProcedenciaTemporal INT,
    porcentajeCumplimiento DECIMAL(5,2), porcentajeProgresoCalendario DECIMAL(5,2), umbralAdvertencia DECIMAL(5,2), umbralPerdida DECIMAL(5,2));
CREATE TABLE #b2hKd (idFacultad UNIQUEIDENTIFIER, nombreFacultad NVARCHAR(50), idPeriodoAcademico UNIQUEIDENTIFIER, nombrePeriodoAcademico NVARCHAR(50),
    totalProgramas INT, totalEstudiantes INT, estudiantesRegulares INT, estudiantesRiesgo INT, estudiantesPerdida INT, tasaRetencion DECIMAL(5,2),
    sesionesEjecutadas INT, faltasSinJustaCausa INT, porcentajeAusentismo DECIMAL(5,2), porcentajeAsistencia DECIMAL(5,2),
    gruposActivos INT, cupoTotal INT, matriculadosActivos INT, tasaAforo DECIMAL(7,2), umbralAdvertencia DECIMAL(5,2), umbralPerdida DECIMAL(5,2),
    tomasDictadas INT, horasDictadas DECIMAL(12,6), horasFalta DECIMAL(12,6));
CREATE TABLE #b2hKi (idInstitucion UNIQUEIDENTIFIER, nombreInstitucion NVARCHAR(50), idPeriodoAcademico UNIQUEIDENTIFIER, nombrePeriodoAcademico NVARCHAR(50),
    totalFacultades INT, totalProgramas INT, totalEstudiantes INT, estudiantesRegulares INT, estudiantesRiesgo INT, estudiantesPerdida INT, tasaRetencion DECIMAL(5,2),
    sesionesEjecutadas INT, faltasSinJustaCausa INT, porcentajeAusentismo DECIMAL(5,2), porcentajeAsistencia DECIMAL(5,2),
    sesionesVencidas INT, sesionesConRegistro INT, porcentajeCumplimiento DECIMAL(5,2),
    estudiantesConMatriculaActiva INT, estudiantesRegistrados INT, docentesConGrupoActivo INT, docentesRegistrados INT,
    umbralAdvertencia DECIMAL(5,2), umbralPerdida DECIMAL(5,2), tomasDictadas INT, horasDictadas DECIMAL(12,6), horasFalta DECIMAL(12,6));
CREATE TABLE #b2hCo (corrida INT, idGrupo UNIQUEIDENTIFIER, codigoGrupo INT, nombreGrupo NVARCHAR(100), idPeriodoAcademico UNIQUEIDENTIFIER,
    nombrePeriodoAcademico NVARCHAR(100), idPrograma UNIQUEIDENTIFIER, nombrePrograma NVARCHAR(100),
    idAsignatura UNIQUEIDENTIFIER, nombreAsignatura NVARCHAR(100), idDocente UNIQUEIDENTIFIER, nombreDocente NVARCHAR(250),
    estudiantesActivos INT, sesionesEjecutadas INT, asistencias INT, faltasSinJustaCausa INT, excusas INT,
    porcentajeAsistencia DECIMAL(5,2), porcentajeInasistencia DECIMAL(5,2), estudiantesRiesgo INT, estudiantesPerdida INT, totalRegistros INT);
CREATE TABLE #b2hCoX (idGrupo UNIQUEIDENTIFIER, codigoGrupo INT, nombreGrupo NVARCHAR(100), idPeriodoAcademico UNIQUEIDENTIFIER,
    nombrePeriodoAcademico NVARCHAR(100), idPrograma UNIQUEIDENTIFIER, nombrePrograma NVARCHAR(100),
    idAsignatura UNIQUEIDENTIFIER, nombreAsignatura NVARCHAR(100), idDocente UNIQUEIDENTIFIER, nombreDocente NVARCHAR(250),
    estudiantesActivos INT, sesionesEjecutadas INT, asistencias INT, faltasSinJustaCausa INT, excusas INT,
    porcentajeAsistencia DECIMAL(5,2), porcentajeInasistencia DECIMAL(5,2), estudiantesRiesgo INT, estudiantesPerdida INT, totalRegistros INT);
CREATE TABLE #b2hTe (corrida INT, inicioIntervalo DATE, finIntervalo DATE, sesionesEjecutadas INT, faltasSinJustaCausa INT, porcentajeAusentismo DECIMAL(5,2));
CREATE TABLE #b2hTeX (inicioIntervalo DATE, finIntervalo DATE, sesionesEjecutadas INT, faltasSinJustaCausa INT, porcentajeAusentismo DECIMAL(5,2));
CREATE TABLE #b2hCf (corrida INT, idFacultad UNIQUEIDENTIFIER, nombreFacultad NVARCHAR(50), estaActivaFacultad BIT, totalProgramas INT, totalEstudiantes INT,
    estudiantesRiesgo INT, estudiantesPerdida INT, tasaRetencion DECIMAL(5,2), sesionesEjecutadas INT, faltasSinJustaCausa INT, porcentajeAusentismo DECIMAL(5,2));
CREATE TABLE #b2hCfX (idFacultad UNIQUEIDENTIFIER, nombreFacultad NVARCHAR(50), estaActivaFacultad BIT, totalProgramas INT, totalEstudiantes INT,
    estudiantesRiesgo INT, estudiantesPerdida INT, tasaRetencion DECIMAL(5,2), sesionesEjecutadas INT, faltasSinJustaCausa INT, porcentajeAusentismo DECIMAL(5,2));
CREATE TABLE #b2hCp (corrida INT, idPrograma UNIQUEIDENTIFIER, nombrePrograma NVARCHAR(50), estaActivoPrograma BIT, totalEstudiantes INT, estudiantesRiesgo INT, estudiantesPerdida INT,
    tasaRetencion DECIMAL(5,2), sesionesEjecutadas INT, faltasSinJustaCausa INT, porcentajeAusentismo DECIMAL(5,2));
CREATE TABLE #b2hCpX (idPrograma UNIQUEIDENTIFIER, nombrePrograma NVARCHAR(50), estaActivoPrograma BIT, totalEstudiantes INT, estudiantesRiesgo INT, estudiantesPerdida INT,
    tasaRetencion DECIMAL(5,2), sesionesEjecutadas INT, faltasSinJustaCausa INT, porcentajeAusentismo DECIMAL(5,2));
CREATE TABLE #b2hR (idSolicitudRevisionAsistencia UNIQUEIDENTIFIER, nombreSolicitud NVARCHAR(50), fechaSolicitud DATE,
    codigoEstado NVARCHAR(5), nombreEstado NVARCHAR(100), justificacionSolicitud NVARCHAR(MAX), justificacionRespuesta NVARCHAR(MAX),
    idEstudiante UNIQUEIDENTIFIER, nombreEstudiante NVARCHAR(400), idSesion UNIQUEIDENTIFIER, numeroSesion INT,
    fechaHoraInicioSesion DATETIME2(7), procedenciaTemporalSesion NVARCHAR(24), idGrupo UNIQUEIDENTIFIER, codigoGrupo INT,
    nombreGrupo NVARCHAR(100), idAsignatura UNIQUEIDENTIFIER, codigoAsignatura NVARCHAR(100), nombreAsignatura NVARCHAR(100),
    asistio BIT, codigoRazonCausa NVARCHAR(5), nombreRazonCausa NVARCHAR(50),
    idArchivoSoporte UNIQUEIDENTIFIER, nombreSoporte NVARCHAR(250), tipoContenidoSoporte VARCHAR(50),
    tamanioSoporteBytes BIGINT, fechaRegistroSoporteUtc DATETIME2(7));

DECLARE @corr UNIQUEIDENTIFIER;

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @uD UNIQUEIDENTIFIER = NEWID(), @d UNIQUEIDENTIFIER = NEWID();
    DECLARE @tag NVARCHAR(12) = LEFT(REPLACE(CONVERT(NVARCHAR(36), NEWID()), N'-', N''), 12);
    CREATE TABLE #b2hE (n INT PRIMARY KEY, idUsuario UNIQUEIDENTIFIER, idEstudiante UNIQUEIDENTIFIER);
    INSERT INTO #b2hE (n, idUsuario, idEstudiante) SELECT v.n, NEWID(), NEWID() FROM (VALUES (1),(2),(3),(4)) v(n);
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uD, @tipoCC, 977000000 + ABS(CHECKSUM(NEWID()) % 999999), N'Horas', N'CulmB', N'Hugo', N'B2', CONCAT(N'culmb2h.d.', @tag, N'@test.local'), 1, 1, N'HashBackend_CULMB2');
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    SELECT e.idUsuario, @tipoCC, 978000000 + e.n * 10000 + ABS(CHECKSUM(NEWID()) % 9999), CONCAT(N'Horas', e.n), N'CulmB', N'Est', N'B2',
           CONCAT(N'culmb2h.e', e.n, N'.', @tag, N'@test.local'), 1, 1, N'HashBackend_CULMB2'
    FROM #b2hE e;
    INSERT INTO dbo.Docente (id, usuario) VALUES (@d, @uD);
    INSERT INTO dbo.Estudiante (id, usuario) SELECT idEstudiante, idUsuario FROM #b2hE;
    INSERT INTO dbo.EstudiantePrograma (id, estudiante, programa) SELECT NEWID(), idEstudiante, @idProg FROM #b2hE;

    -- Periodo propio (solo tiene los grupos del fixture): los KPI se piden con @idPeriodoAcademico explicito
    DECLARE @per UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@per, @idInst, N'CULMB2 periodo horas', 3400000 + ABS(CHECKSUM(NEWID()) % 500000), DATEADD(DAY, -60, @hoy), DATEADD(DAY, 30, @hoy), YEAR(@hoy));
    CREATE TABLE #b2hG (k NVARCHAR(4) PRIMARY KEY, id UNIQUEIDENTIFIER);
    INSERT INTO #b2hG (k, id) VALUES (N'H1', NEWID()), (N'H2', NEWID()), (N'H3', NEWID()), (N'H4', NEWID()), (N'H5', NEWID()), (N'H9', NEWID()), (N'HK', NEWID());
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
        cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    SELECT g.id, @idAsig, @per, 948000 + ABS(CHECKSUM(NEWID()) % 51999), CONCAT(N'CULMB2 Grupo ', g.k), 30, 0, 0, 0, @d FROM #b2hG g;
    CREATE TABLE #b2hEG (est INT, grupo NVARCHAR(4), id UNIQUEIDENTIFIER);
    INSERT INTO #b2hEG (est, grupo, id) SELECT e.n, g.k, NEWID() FROM #b2hE e CROSS JOIN #b2hG g;
    INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo)
    SELECT x.id, @estadoA, e.idEstudiante, g.id FROM #b2hEG x INNER JOIN #b2hE e ON e.n = x.est INNER JOIN #b2hG g ON g.k = x.grupo;

    -- Sesiones vencidas (ya terminadas): clave, grupo, duracion en horas, dias atras, numero de tomas
    INSERT INTO #b2hS (k, id, grupo, horas, diasAtras, tomas) VALUES
        (N'H1S1', NEWID(), N'H1', 2, 3, 2),                                      -- B2-HOR-01: 2 h con 2 tomas
        (N'H2A',  NEWID(), N'H2', 2, 4, 1), (N'H2B', NEWID(), N'H2', 4, 3, 1),  -- B2-HOR-02: 2 h y 4 h
        (N'H2C',  NEWID(), N'H2', 3, 2, 0),                                      -- B2-HOR-06: sin registro ni tomas
        (N'H3A',  NEWID(), N'H3', 1, 5, 1), (N'H3B', NEWID(), N'H3', 1, 4, 1), (N'H3C', NEWID(), N'H3', 1, 3, 1),  -- B2-HOR-03
        (N'H4S',  NEWID(), N'H4', 4, 3, 4),                                      -- B2-HOR-04: 4 tomas de 1 h
        (N'H5A',  NEWID(), N'H5', 4, 9, 4), (N'H5B', NEWID(), N'H5', 4, 8, 4), (N'H5C', NEWID(), N'H5', 4, 7, 4),
        (N'H5D',  NEWID(), N'H5', 4, 6, 4), (N'H5E', NEWID(), N'H5', 4, 5, 4),  -- B2-HOR-05: 20 h en 20 tomas de 1 h
        (N'H9S',  NEWID(), N'H9', 2, 3, 0),                                      -- B2-HOR-09: cabecera sin detalle ni tomas
        (N'HKA',  NEWID(), N'HK', 2, 4, 2), (N'HKB', NEWID(), N'HK', 4, 3, 1);  -- B2-HOR-07/08: KPI y reclamo
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    SELECT s.id, CONCAT(N'CULMB2 ', s.k), ROW_NUMBER() OVER (PARTITION BY s.grupo ORDER BY s.diasAtras DESC), CONCAT(N'CB2H', s.k), 1, g.id,
           DATEADD(HOUR, -s.horas, DATEADD(DAY, -s.diasAtras, SYSUTCDATETIME())), DATEADD(DAY, -s.diasAtras, SYSUTCDATETIME()), N'UTC_V2'
    FROM #b2hS s INNER JOIN #b2hG g ON g.k = s.grupo;
    -- Tomas cerradas (numero 1..n) por insercion directa
    INSERT INTO dbo.TomaAsistencia (id, sesion, numero, modo, estado, esImplicita, docenteApertura, fechaAperturaUtc, fechaCierreUtc, idCorrelacionApertura)
    SELECT NEWID(), s.id, v.n, @modoManual, @estCerrada, 0, @d, CAST(se.fechaHoraInicio AS DATETIME2(0)), CAST(se.fechaHoraFin AS DATETIME2(0)), NEWID()
    FROM #b2hS s INNER JOIN dbo.Sesion se ON se.id = s.id
    INNER JOIN (VALUES (1), (2), (3), (4)) v(n) ON v.n <= s.tomas;
    -- Detalles: sesion, estudiante, numero de toma, codigo
    INSERT INTO #b2hD (k, est, tomaNum, codigo) VALUES
        (N'H1S1', 1, 1, N'AN'), (N'H1S1', 1, 2, N'SJC'), (N'H1S1', 2, 1, N'AN'), (N'H1S1', 2, 2, N'AN'),
        (N'H2A', 1, 1, N'AN'), (N'H2B', 1, 1, N'SJC'), (N'H2A', 2, 1, N'AN'), (N'H2B', 2, 1, N'AN'),
        (N'H3A', 1, 1, N'AN'), (N'H3B', 1, 1, N'SJC'), (N'H3C', 1, 1, N'AN'),
        (N'H4S', 1, 1, N'SJC'), (N'H4S', 1, 2, N'EX'), (N'H4S', 1, 3, N'AN'), (N'H4S', 1, 4, N'AN'),
        (N'HKA', 1, 1, N'AN'), (N'HKA', 1, 2, N'SJC'), (N'HKA', 2, 1, N'AN'), (N'HKA', 2, 2, N'AN'), (N'HKB', 1, 1, N'SJC'), (N'HKB', 2, 1, N'EX');
    -- H5: estudiante 1 con SJC en 3 tomas (15 %), estudiante 2 con SJC en 4 tomas (20 %), el resto AN
    INSERT INTO #b2hD (k, est, tomaNum, codigo)
    SELECT s.k, e.n, v.n, CASE WHEN e.n = 1 AND s.k = N'H5A' AND v.n <= 3 THEN N'SJC' WHEN e.n = 2 AND s.k = N'H5B' THEN N'SJC' ELSE N'AN' END
    FROM #b2hS s CROSS JOIN (VALUES (1), (2)) e(n) CROSS JOIN (VALUES (1), (2), (3), (4)) v(n) WHERE s.grupo = N'H5';
    INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion)
    SELECT NEWID(), x.id, s.id
    FROM (SELECT DISTINCT k, est FROM #b2hD) d INNER JOIN #b2hS s ON s.k = d.k INNER JOIN #b2hEG x ON x.est = d.est AND x.grupo = s.grupo;
    INSERT INTO dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin, toma, registradoPorEstudiante, fechaRegistroUtc)
    SELECT NEWID(), NEXT VALUE FOR dbo.seq_detalle_asistencia_codigo, a.id, IIF(d.codigo = N'AN', 1, 0), rc.id, se.fechaHoraInicio, se.fechaHoraFin, t.id, 0, SYSUTCDATETIME()
    FROM #b2hD d INNER JOIN #b2hS s ON s.k = d.k INNER JOIN dbo.Sesion se ON se.id = s.id
    INNER JOIN #b2hEG x ON x.est = d.est AND x.grupo = s.grupo
    INNER JOIN dbo.Asistencia a ON a.estudianteGrupo = x.id AND a.sesion = s.id
    INNER JOIN dbo.TomaAsistencia t ON t.sesion = s.id AND t.numero = d.tomaNum
    INNER JOIN dbo.RazonCausa rc ON rc.codigo = d.codigo;
    -- B2-HOR-09: cabecera Asistencia (creada por un reclamo) sin detalle ni tomas
    INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion)
    SELECT NEWID(), x.id, s.id FROM #b2hS s INNER JOIN #b2hEG x ON x.grupo = s.grupo AND x.est = 1 WHERE s.k = N'H9S';
    -- B2-HOR-03: la tercera sesion del grupo H3 (con registro) se cancela
    INSERT dbo.SesionCancelacion (sesion, tipoCancelacion, motivo, diaFestivo, usuarioEjecutor, idCorrelacion)
    SELECT s.id, @tipoManual, N'CULMB2 cancelada para horas', NULL, @uD, NEWID() FROM #b2hS s WHERE s.k = N'H3C';

    DECLARE @gH1 UNIQUEIDENTIFIER = (SELECT id FROM #b2hG WHERE k = N'H1'), @gH2 UNIQUEIDENTIFIER = (SELECT id FROM #b2hG WHERE k = N'H2');
    DECLARE @gH3 UNIQUEIDENTIFIER = (SELECT id FROM #b2hG WHERE k = N'H3'), @gH4 UNIQUEIDENTIFIER = (SELECT id FROM #b2hG WHERE k = N'H4');
    DECLARE @gH5 UNIQUEIDENTIFIER = (SELECT id FROM #b2hG WHERE k = N'H5'), @gH9 UNIQUEIDENTIFIER = (SELECT id FROM #b2hG WHERE k = N'H9');
    DECLARE @gHK UNIQUEIDENTIFIER = (SELECT id FROM #b2hG WHERE k = N'HK');
    DECLARE @e1 UNIQUEIDENTIFIER = (SELECT idEstudiante FROM #b2hE WHERE n = 1), @e2 UNIQUEIDENTIFIER = (SELECT idEstudiante FROM #b2hE WHERE n = 2);
    DECLARE @e3 UNIQUEIDENTIFIER = (SELECT idEstudiante FROM #b2hE WHERE n = 3);

    -- --------------------------------------------------------------------------------------------------------
    -- B2-HOR-01: sesion de 2 h con 2 tomas; AN en la toma 1 y SJC en la toma 2
    -- --------------------------------------------------------------------------------------------------------
    IF EXISTS (SELECT 1 FROM dbo.uv_toma_asistencia t INNER JOIN #b2hS s ON s.id = t.idSesion WHERE s.k = N'H1S1' AND (t.horasToma <> 1.000000 OR t.totalTomasSesion <> 2))
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_asistencia_sesion_horas h INNER JOIN #b2hS s ON s.id = h.idSesion INNER JOIN #b2hEG x ON x.id = h.idEstudianteGrupo
                      WHERE s.k = N'H1S1' AND x.est = 1 AND h.totalTomasSesion = 2 AND h.tomasConRegistro = 2 AND h.horasSesion = 2.000000
                        AND h.horasAsistidas = 1.000000 AND h.horasFalta = 1.000000 AND h.horasExcusa = 0 AND h.horasSinRegistro = 0
                        AND h.esParcial = 1 AND h.codigoRazonCausaConsolidado = N'SJC' AND h.tieneFaltaSinJustaCausa = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_asistencia_sesion_horas h INNER JOIN #b2hS s ON s.id = h.idSesion INNER JOIN #b2hEG x ON x.id = h.idEstudianteGrupo
                      WHERE s.k = N'H1S1' AND x.est = 2 AND h.horasAsistidas = 2.000000 AND h.esParcial = 0 AND h.codigoRazonCausaConsolidado = N'AN' AND h.tieneFaltaSinJustaCausa = 0)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_detalle_asistencia_v2 v INNER JOIN #b2hS s ON s.id = v.idSesion WHERE s.k = N'H1S1' AND v.horasToma = 1.000000 AND v.numeroToma = 2 AND v.codigoModoToma = N'MANUAL')
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_resumen_asistencia_estudiante_grupo r WHERE r.idGrupo = @gH1 AND r.idEstudiante = @e1
                      AND r.sesionesEjecutadas = 1 AND r.tomasDictadas = 2 AND r.horasDictadas = 2.000000 AND r.horasFalta = 1.000000 AND r.horasAsistidas = 1.000000
                      AND r.asistencias = 1 AND r.faltasSinJustaCausa = 1 AND r.porcentajeInasistencia = 50.00 AND r.porcentajeInasistenciaSesiones = 100.00
                      AND r.sesionesConFaltaSinJustaCausa = 1 AND r.sesionesAsistidas = 0)
        THROW 57620, 'TEST FAILED CULM001_B2_HOR_01: con 2 tomas de una sesion de 2 h, AN + SJC deben dar 1 h asistida, 1 h de falta, parcial y consolidado SJC.', 1;
    PRINT 'TEST_PASS:CULM001_B2_HOR_01_DOS_TOMAS';

    -- --------------------------------------------------------------------------------------------------------
    -- B2-HOR-02 / B2-HOR-06: sesiones de 2 h y 4 h con falta en la de 4 h => 66.67 por horas y 50.00 por sesiones;
    -- una sesion vencida sin registro ni tomas no entra en el denominador
    -- --------------------------------------------------------------------------------------------------------
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_resumen_asistencia_estudiante_grupo r WHERE r.idGrupo = @gH2 AND r.idEstudiante = @e1
                   AND r.sesionesEjecutadas = 2 AND r.horasDictadas = 6.000000 AND r.horasFalta = 4.000000 AND r.horasAsistidas = 2.000000
                   AND r.porcentajeInasistencia = 66.67 AND r.porcentajeInasistenciaSesiones = 50.00 AND r.porcentajeAsistenciaHoras = 33.33
                   AND r.codigoPermanencia = N'PERDIDA')
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_resumen_asistencia_estudiante_grupo r WHERE r.idGrupo = @gH2 AND r.idEstudiante = @e3
                   AND r.horasDictadas = 6.000000 AND r.horasSinRegistro = 6.000000 AND r.porcentajeSinRegistroHoras = 100.00 AND r.porcentajeInasistencia = 0.00)
        THROW 57621, 'TEST FAILED CULM001_B2_HOR_02: sesiones de 2 h y 4 h con falta en la de 4 h deben dar 66.67 por horas y 50.00 por sesiones.', 1;
    PRINT 'TEST_PASS:CULM001_B2_HOR_02_DURACIONES_DISTINTAS';
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_cumplimiento_sesion_grupo c INNER JOIN #b2hS s ON s.id = c.idSesion WHERE s.k = N'H2C' AND c.estaVencida = 1 AND c.tieneRegistroAsistencia = 0 AND c.totalTomas = 0 AND c.horasSesion = 3.000000)
        THROW 57622, 'TEST FAILED CULM001_B2_HOR_06: una sesion vencida sin registro ni tomas no cuenta como ejecutada.', 1;
    PRINT 'TEST_PASS:CULM001_B2_HOR_06_SIN_REGISTRO_FUERA_DEL_DENOMINADOR';

    -- --------------------------------------------------------------------------------------------------------
    -- B2-HOR-03: grupo con 3 sesiones vencidas, una cancelada => horasDictadas y sesionesEjecutadas la excluyen
    -- --------------------------------------------------------------------------------------------------------
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_resumen_asistencia_estudiante_grupo r WHERE r.idGrupo = @gH3 AND r.idEstudiante = @e1
                   AND r.sesionesEjecutadas = 2 AND r.tomasDictadas = 2 AND r.horasDictadas = 2.000000 AND r.horasFalta = 1.000000 AND r.asistencias = 1
                   AND r.porcentajeInasistencia = 50.00)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_toma_asistencia t INNER JOIN #b2hS s ON s.id = t.idSesion WHERE s.k = N'H3C' AND t.estaSesionCancelada = 1 AND t.horasToma = 0)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_detalle_asistencia_v2 v INNER JOIN #b2hS s ON s.id = v.idSesion WHERE s.k = N'H3C' AND v.estaSesionCancelada = 1 AND v.horasToma = 0)
        THROW 57623, 'TEST FAILED CULM001_B2_HOR_03: una sesion cancelada no entra en horasDictadas ni en sesionesEjecutadas.', 1;
    PRINT 'TEST_PASS:CULM001_B2_HOR_03_SESION_CANCELADA';

    -- --------------------------------------------------------------------------------------------------------
    -- B2-HOR-04: EX fuera de faltas y dentro del denominador: 1 SJC y 1 EX en 4 tomas de 1 h => 25.00
    -- --------------------------------------------------------------------------------------------------------
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_resumen_asistencia_estudiante_grupo r WHERE r.idGrupo = @gH4 AND r.idEstudiante = @e1
                   AND r.horasFalta = 1.000000 AND r.horasExcusa = 1.000000 AND r.horasAsistidas = 2.000000 AND r.horasDictadas = 4.000000
                   AND r.horasSinRegistro = 0 AND r.porcentajeInasistencia = 25.00 AND r.porcentajeExcusaHoras = 25.00 AND r.porcentajeAsistenciaHoras = 50.00
                   AND r.excusas = 1 AND r.faltasSinJustaCausa = 1 AND r.asistencias = 2 AND r.tomasDictadas = 4 AND r.sesionesEjecutadas = 1)
        THROW 57624, 'TEST FAILED CULM001_B2_HOR_04: 1 SJC y 1 EX en 4 tomas de 1 h deben dar horasFalta 1, horasExcusa 1, horasDictadas 4 y 25.00.', 1;
    PRINT 'TEST_PASS:CULM001_B2_HOR_04_EXCUSA_EN_DENOMINADOR';

    -- --------------------------------------------------------------------------------------------------------
    -- B2-HOR-05: umbrales: 15.00 => RIESGO, 20.00 => PERDIDA; umbrales iguales a los parametros
    -- --------------------------------------------------------------------------------------------------------
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_resumen_asistencia_estudiante_grupo r WHERE r.idGrupo = @gH5 AND r.idEstudiante = @e1
                   AND r.horasDictadas = 20.000000 AND r.horasFalta = 3.000000 AND r.porcentajeInasistencia = 15.00 AND r.codigoPermanencia = N'RIESGO')
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_resumen_asistencia_estudiante_grupo r WHERE r.idGrupo = @gH5 AND r.idEstudiante = @e2
                   AND r.horasFalta = 4.000000 AND r.porcentajeInasistencia = 20.00 AND r.codigoPermanencia = N'PERDIDA')
       OR EXISTS (SELECT 1 FROM dbo.uv_resumen_asistencia_estudiante_grupo r WHERE r.idGrupo = @gH5
                  AND (r.umbralAdvertencia <> TRY_CAST(CAST(dbo.ufn_obtener_parametro('ASISTENCIA', 'UMBRAL_ALERTA_ADVERTENCIA') AS NVARCHAR(20)) AS DECIMAL(5,2))
                    OR r.umbralPerdida <> TRY_CAST(CAST(dbo.ufn_obtener_parametro('ASISTENCIA', 'UMBRAL_ALERTA_PERDIDA') AS NVARCHAR(20)) AS DECIMAL(5,2))
                    OR r.umbralAdvertencia IS NULL OR r.umbralPerdida IS NULL))
        THROW 57625, 'TEST FAILED CULM001_B2_HOR_05: 15.00 debe ser RIESGO y 20.00 PERDIDA (ufn_clasificar_permanencia sin cambio) con los umbrales de parametros.', 1;
    PRINT 'TEST_PASS:CULM001_B2_HOR_05_UMBRALES';

    -- --------------------------------------------------------------------------------------------------------
    -- B2-HOR-09: sesion vencida con cabecera Asistencia y sin detalle ni tomas: horasSinRegistro = horasSesion y entra
    -- en horasDictadas (DEC-024)
    -- --------------------------------------------------------------------------------------------------------
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_asistencia_sesion_horas h INNER JOIN #b2hS s ON s.id = h.idSesion WHERE s.k = N'H9S'
                   AND h.totalTomasSesion = 0 AND h.tomasConRegistro = 0 AND h.horasSesion = 2.000000 AND h.horasSinRegistro = 2.000000
                   AND h.horasFalta = 0 AND h.horasAsistidas = 0 AND h.codigoRazonCausaConsolidado IS NULL AND h.esParcial = 0)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_resumen_asistencia_estudiante_grupo r WHERE r.idGrupo = @gH9 AND r.idEstudiante = @e1
                   AND r.sesionesEjecutadas = 1 AND r.tomasDictadas = 0 AND r.horasDictadas = 2.000000 AND r.horasSinRegistro = 2.000000 AND r.porcentajeInasistencia = 0.00)
        THROW 57626, 'TEST FAILED CULM001_B2_HOR_09: una cabecera sin detalle ni tomas debe sumar horasSesion como horasSinRegistro y entrar en horasDictadas.', 1;
    PRINT 'TEST_PASS:CULM001_B2_HOR_09_CABECERA_SIN_DETALLE';

    -- --------------------------------------------------------------------------------------------------------
    -- B2-HOR-07: KPI por horas. Periodo del fixture: grupos H1..H5, H9, HK con 4 estudiantes activos cada uno.
    -- Calculo manual: Sigma horasFalta / Sigma horasDictadas de las matriculas A del periodo.
    -- --------------------------------------------------------------------------------------------------------
    DECLARE @hFalta DECIMAL(12,6), @hDict DECIMAL(12,6), @tDict INT, @esperado DECIMAL(5,2);
    SELECT @hFalta = SUM(r.horasFalta), @hDict = SUM(r.horasDictadas), @tDict = SUM(r.tomasDictadas)
    FROM dbo.uv_resumen_asistencia_estudiante_grupo r WHERE r.idPeriodoAcademico = @per AND r.codigoEstadoEstudiante = N'A';
    -- H1 1 + H2 4 + H3 1 + H4 1 + H5 (3 + 4) + HK (1 + 4) = 19 h de falta; dictadas por estudiante 2 + 6 + 2 + 4 + 20 + 2 + 6 = 42 => 168
    IF @hFalta <> 19.000000 OR @hDict <> 168.000000
        THROW 57627, 'TEST FAILED CULM001_B2_HOR_07: el fixture de horas no suma 19 h de falta sobre 168 h dictadas.', 1;
    SET @esperado = CAST(100.0 * @hFalta / @hDict AS DECIMAL(5,2));
    SET @corr = NEWID();
    INSERT INTO #b2hKd EXEC dbo.usp_consultar_kpis_decano @idUsuarioEjecutor = @uDec, @idCorrelacion = @corr, @idPeriodoAcademico = @per;
    INSERT INTO #b2hKi EXEC dbo.usp_consultar_kpis_institucion @idUsuarioEjecutor = @uAdm, @idCorrelacion = @corr, @idPeriodoAcademico = @per;
    INSERT INTO #b2hKc EXEC dbo.usp_consultar_kpis_coordinador @idUsuarioEjecutor = @uCoord, @idCorrelacion = @corr, @idPeriodoAcademico = @per;
    IF NOT EXISTS (SELECT 1 FROM #b2hKd WHERE idPeriodoAcademico = @per AND porcentajeAusentismo = @esperado AND porcentajeAsistencia = 100.00 - @esperado
                   AND tomasDictadas = @tDict AND horasDictadas = @hDict AND horasFalta = @hFalta)
       OR NOT EXISTS (SELECT 1 FROM #b2hKi WHERE idPeriodoAcademico = @per AND porcentajeAusentismo = @esperado
                   AND tomasDictadas = @tDict AND horasDictadas = @hDict AND horasFalta = @hFalta)
        THROW 57628, 'TEST FAILED CULM001_B2_HOR_07: porcentajeAusentismo de decano e institucion debe ser 100 * horasFalta / horasDictadas.', 1;
    -- Semaforo del coordinador sobre el porcentaje por horas (vista): estudiante en RIESGO o PERDIDA segun su peor matricula
    IF NOT EXISTS (SELECT 1 FROM #b2hKc k
                   WHERE k.idPeriodoAcademico = @per AND k.totalEstudiantes = 4
                     AND k.estudiantesPerdida = (SELECT COUNT(DISTINCT r.idEstudiante) FROM dbo.uv_resumen_asistencia_estudiante_grupo r
                                                 WHERE r.idPeriodoAcademico = @per AND r.codigoPermanencia = N'PERDIDA')
                     AND k.sesionesEjecutadas = (SELECT COUNT(*) FROM dbo.uv_cumplimiento_sesion_grupo c WHERE c.idPeriodoAcademico = @per AND c.estaVencida = 1 AND c.tieneRegistroAsistencia = 1))
        THROW 57629, 'TEST FAILED CULM001_B2_HOR_07: el KPI del coordinador debe usar la clasificacion por horas y el cumplimiento sin canceladas.', 1;
    PRINT 'TEST_PASS:CULM001_B2_HOR_07_KPIS_POR_HORAS';

    -- Diferidos a D (consolidado, tendencia, comparativas): con 2 tomas dan el mismo resultado que con 1 toma del mismo
    -- estado consolidado. Corrida 1 con el fixture; luego HKA (AN + SJC) colapsa a 1 toma SJC y H1S1 a 1 toma SJC.
    INSERT INTO #b2hCoX EXEC dbo.usp_consultar_consolidado_asistencia_grupos_paginado @idUsuarioEjecutor = @uCoord, @idCorrelacion = @corr,
        @numeroPagina = 1, @tamanoPagina = 50, @idPeriodoAcademico = @per;
    INSERT INTO #b2hCo SELECT 1, * FROM #b2hCoX; TRUNCATE TABLE #b2hCoX;
    INSERT INTO #b2hTeX EXEC dbo.usp_consultar_tendencia_ausentismo @idUsuarioEjecutor = @uAdm, @idCorrelacion = @corr, @idPeriodoAcademico = @per, @granularidad = N'SEMANA';
    INSERT INTO #b2hTe SELECT 1, * FROM #b2hTeX; TRUNCATE TABLE #b2hTeX;
    INSERT INTO #b2hCfX EXEC dbo.usp_consultar_comparativa_facultades @idUsuarioEjecutor = @uAdm, @idCorrelacion = @corr, @idPeriodoAcademico = @per;
    INSERT INTO #b2hCf SELECT 1, * FROM #b2hCfX; TRUNCATE TABLE #b2hCfX;
    INSERT INTO #b2hCpX EXEC dbo.usp_consultar_comparativa_programas_facultad @idUsuarioEjecutor = @uDec, @idCorrelacion = @corr, @idPeriodoAcademico = @per;
    INSERT INTO #b2hCp SELECT 1, * FROM #b2hCpX; TRUNCATE TABLE #b2hCpX;
    IF NOT EXISTS (SELECT 1 FROM #b2hCo WHERE idGrupo = @gHK) OR NOT EXISTS (SELECT 1 FROM #b2hTe) OR NOT EXISTS (SELECT 1 FROM #b2hCf WHERE idFacultad = @idFac)
       OR NOT EXISTS (SELECT 1 FROM #b2hCp WHERE idPrograma = @idProg)
        THROW 57630, 'TEST FAILED CULM001_B2_HOR_07: los consumidores diferidos no ven el periodo del fixture.', 1;
    -- colapso a 1 toma del mismo estado consolidado: se borran las tomas > 1 (y sus detalles) y el detalle de la toma 1 toma el consolidado
    UPDATE da SET razonCausa = rcS.id, asistio = 0
    FROM dbo.DetalleAsistencia da
    INNER JOIN dbo.Asistencia a ON a.id = da.asistencia
    INNER JOIN dbo.TomaAsistencia t ON t.id = da.toma AND t.numero = 1
    INNER JOIN #b2hS s ON s.id = a.sesion AND s.k IN (N'HKA', N'H1S1')
    INNER JOIN #b2hEG x ON x.id = a.estudianteGrupo AND x.est = 1
    CROSS JOIN (SELECT id FROM dbo.RazonCausa WHERE codigo = N'SJC') rcS;
    DELETE da FROM dbo.DetalleAsistencia da INNER JOIN dbo.TomaAsistencia t ON t.id = da.toma INNER JOIN #b2hS s ON s.id = t.sesion
    WHERE s.k IN (N'HKA', N'H1S1') AND t.numero > 1;
    DELETE t FROM dbo.TomaAsistencia t INNER JOIN #b2hS s ON s.id = t.sesion WHERE s.k IN (N'HKA', N'H1S1') AND t.numero > 1;
    INSERT INTO #b2hCoX EXEC dbo.usp_consultar_consolidado_asistencia_grupos_paginado @idUsuarioEjecutor = @uCoord, @idCorrelacion = @corr,
        @numeroPagina = 1, @tamanoPagina = 50, @idPeriodoAcademico = @per;
    INSERT INTO #b2hCo SELECT 2, * FROM #b2hCoX;
    INSERT INTO #b2hTeX EXEC dbo.usp_consultar_tendencia_ausentismo @idUsuarioEjecutor = @uAdm, @idCorrelacion = @corr, @idPeriodoAcademico = @per, @granularidad = N'SEMANA';
    INSERT INTO #b2hTe SELECT 2, * FROM #b2hTeX;
    INSERT INTO #b2hCfX EXEC dbo.usp_consultar_comparativa_facultades @idUsuarioEjecutor = @uAdm, @idCorrelacion = @corr, @idPeriodoAcademico = @per;
    INSERT INTO #b2hCf SELECT 2, * FROM #b2hCfX;
    INSERT INTO #b2hCpX EXEC dbo.usp_consultar_comparativa_programas_facultad @idUsuarioEjecutor = @uDec, @idCorrelacion = @corr, @idPeriodoAcademico = @per;
    INSERT INTO #b2hCp SELECT 2, * FROM #b2hCpX;
    IF EXISTS ((SELECT idGrupo, sesionesEjecutadas, asistencias, faltasSinJustaCausa, excusas, porcentajeAsistencia, porcentajeInasistencia FROM #b2hCo WHERE corrida = 1)
               EXCEPT (SELECT idGrupo, sesionesEjecutadas, asistencias, faltasSinJustaCausa, excusas, porcentajeAsistencia, porcentajeInasistencia FROM #b2hCo WHERE corrida = 2))
       OR EXISTS ((SELECT idGrupo, sesionesEjecutadas, asistencias, faltasSinJustaCausa, excusas, porcentajeAsistencia, porcentajeInasistencia FROM #b2hCo WHERE corrida = 2)
               EXCEPT (SELECT idGrupo, sesionesEjecutadas, asistencias, faltasSinJustaCausa, excusas, porcentajeAsistencia, porcentajeInasistencia FROM #b2hCo WHERE corrida = 1))
       OR EXISTS ((SELECT inicioIntervalo, finIntervalo, sesionesEjecutadas, faltasSinJustaCausa, porcentajeAusentismo FROM #b2hTe WHERE corrida = 1)
               EXCEPT (SELECT inicioIntervalo, finIntervalo, sesionesEjecutadas, faltasSinJustaCausa, porcentajeAusentismo FROM #b2hTe WHERE corrida = 2))
       OR (SELECT COUNT(*) FROM #b2hTe WHERE corrida = 1) <> (SELECT COUNT(*) FROM #b2hTe WHERE corrida = 2)
       OR EXISTS ((SELECT idFacultad, sesionesEjecutadas, faltasSinJustaCausa, porcentajeAusentismo FROM #b2hCf WHERE corrida = 1)
               EXCEPT (SELECT idFacultad, sesionesEjecutadas, faltasSinJustaCausa, porcentajeAusentismo FROM #b2hCf WHERE corrida = 2))
       OR EXISTS ((SELECT idPrograma, sesionesEjecutadas, faltasSinJustaCausa, porcentajeAusentismo FROM #b2hCp WHERE corrida = 1)
               EXCEPT (SELECT idPrograma, sesionesEjecutadas, faltasSinJustaCausa, porcentajeAusentismo FROM #b2hCp WHERE corrida = 2))
        THROW 57631, 'TEST FAILED CULM001_B2_HOR_07: consolidado, tendencia y comparativas (diferidos a D) deben dar con 2 tomas lo mismo que con 1 toma del mismo estado consolidado.', 1;
    PRINT 'TEST_PASS:CULM001_B2_HOR_07_DIFERIDOS_SIN_DUPLICAR';

    -- --------------------------------------------------------------------------------------------------------
    -- B2-HOR-08: reclamo aprobado con varias tomas => todas las SJC de la asistencia pasan a EX; el detalle del reclamo
    -- devuelve una sola fila. Sesion H4S del estudiante 1 (SJC, EX, AN, AN) + una toma 5 SJC agregada.
    -- --------------------------------------------------------------------------------------------------------
    DECLARE @sH4 UNIQUEIDENTIFIER = (SELECT id FROM #b2hS WHERE k = N'H4S');
    DECLARE @aH4 UNIQUEIDENTIFIER = (SELECT a.id FROM dbo.Asistencia a INNER JOIN #b2hEG x ON x.id = a.estudianteGrupo AND x.est = 1 AND x.grupo = N'H4' WHERE a.sesion = @sH4);
    DECLARE @t5 UNIQUEIDENTIFIER = NEWID(), @sol UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.TomaAsistencia (id, sesion, numero, modo, estado, esImplicita, docenteApertura, fechaAperturaUtc, fechaCierreUtc, idCorrelacionApertura)
    SELECT @t5, se.id, 5, @modoManual, @estCerrada, 0, @d, CAST(se.fechaHoraInicio AS DATETIME2(0)), CAST(se.fechaHoraFin AS DATETIME2(0)), NEWID() FROM dbo.Sesion se WHERE se.id = @sH4;
    INSERT INTO dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin, toma, registradoPorEstudiante, fechaRegistroUtc)
    SELECT NEWID(), NEXT VALUE FOR dbo.seq_detalle_asistencia_codigo, @aH4, 0, rc.id, se.fechaHoraInicio, se.fechaHoraFin, @t5, 0, SYSUTCDATETIME()
    FROM dbo.Sesion se CROSS JOIN dbo.RazonCausa rc WHERE se.id = @sH4 AND rc.codigo = N'SJC';
    INSERT INTO dbo.SolicitudRevisionAsistencia (id, nombre, asistencia, fecha, estado, justificacionSolicitud, justificacionRespuesta)
    VALUES (@sol, N'REC-CULMB2', @aH4, CAST(SYSUTCDATETIME() AS DATE), @pending, N'Cita medica CULMB2', N'');
    SET @corr = NEWID();
    INSERT INTO #b2hR EXEC dbo.usp_consultar_detalle_solicitud_revision_docente @idSolicitud = @sol, @idUsuarioEjecutor = @uD, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #b2hR) <> 1 OR NOT EXISTS (SELECT 1 FROM #b2hR WHERE codigoRazonCausa = N'SJC' AND asistio = 0)
        THROW 57640, 'TEST FAILED CULM001_B2_HOR_08: el detalle del reclamo debe devolver una sola fila con el estado consolidado (SJC).', 1;
    TRUNCATE TABLE #b2hR;
    EXEC dbo.usp_resolver_solicitud_revision_asistencia @idSolicitud = @sol, @idDocente = @d, @accion = N'APROBAR', @respuestaDocente = N'Aprobado CULMB2',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uD;
    IF EXISTS (SELECT 1 FROM dbo.DetalleAsistencia da INNER JOIN dbo.RazonCausa rc ON rc.id = da.razonCausa WHERE da.asistencia = @aH4 AND rc.codigo = N'SJC')
       OR (SELECT COUNT(*) FROM dbo.DetalleAsistencia da INNER JOIN dbo.RazonCausa rc ON rc.id = da.razonCausa WHERE da.asistencia = @aH4 AND rc.codigo = N'EX' AND da.asistio = 0) <> 3
       OR (SELECT COUNT(*) FROM dbo.DetalleAsistencia da INNER JOIN dbo.RazonCausa rc ON rc.id = da.razonCausa WHERE da.asistencia = @aH4 AND rc.codigo = N'AN') <> 2
       OR NOT EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia sra INNER JOIN dbo.Estado e ON e.id = sra.estado WHERE sra.id = @sol AND e.codigo = 'A')
        THROW 57641, 'TEST FAILED CULM001_B2_HOR_08: aprobar el reclamo debe pasar a EX todas las SJC de la asistencia (y no tocar las AN).', 1;
    INSERT INTO #b2hR EXEC dbo.usp_consultar_detalle_solicitud_revision_docente @idSolicitud = @sol, @idUsuarioEjecutor = @uD, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #b2hR) <> 1 OR NOT EXISTS (SELECT 1 FROM #b2hR WHERE codigoRazonCausa = N'EX')
        THROW 57642, 'TEST FAILED CULM001_B2_HOR_08: tras aprobar, el detalle del reclamo devuelve una fila con estado consolidado EX.', 1;
    PRINT 'TEST_PASS:CULM001_B2_HOR_08_RECLAMO_VARIAS_TOMAS';

    -- --------------------------------------------------------------------------------------------------------
    -- B2-HOR-11 (NB-2): tomasDictadas junto a sesionesEjecutadas en los SP de §2.9 que exponen conteos
    -- --------------------------------------------------------------------------------------------------------
    IF EXISTS (
        SELECT 1 FROM (VALUES (N'usp_consultar_historial_estudiante'), (N'usp_consultar_resumen_asistencia_estudiante_programa'),
                              (N'usp_consultar_kpis_decano'), (N'usp_consultar_kpis_institucion'),
                              (N'usp_consultar_resumen_asistencia_grupo_docente_paginado'), (N'usp_consultar_resumen_asistencia_estudiante')) p(nombre)
        WHERE (SELECT COUNT(*) FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID(N'dbo.' + p.nombre), 0) d
               WHERE d.name IN (N'sesionesEjecutadas', N'tomasDictadas', N'horasDictadas', N'horasFalta')) <> 4)
       OR (SELECT COUNT(*) FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID(N'dbo.usp_consultar_alerta_temprana_programa'), 0) d
           WHERE d.name IN (N'tomasDictadas', N'horasDictadas', N'horasFalta')) <> 3
       OR (SELECT COUNT(*) FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID(N'dbo.usp_consultar_asistencias_sesion_paginado'), 0) d
           WHERE d.name IN (N'totalTomas', N'horasAsistidas', N'horasFalta', N'horasExcusa')) <> 4
        THROW 57650, 'TEST FAILED CULM001_B2_HOR_11: los SP que exponen conteos deben exponer tomasDictadas/horas junto a sesionesEjecutadas (NB-2).', 1;
    PRINT 'TEST_PASS:CULM001_B2_HOR_11_UNIDADES';

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
    THROW 57699, 'TEST FAILED CULM001_B2_HOR: @@TRANCOUNT distinto de 0 al terminar.', 1;
PRINT 'TEST_PASS:CULM001_B2_HOR_TRANCOUNT_ZERO';
PRINT 'TEST END: test_culm001_b2_horas';
GO
