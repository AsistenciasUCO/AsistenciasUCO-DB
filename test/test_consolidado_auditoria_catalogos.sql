USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- HU061 (consolidado por periodo, asignatura y docente), HU172 (auditoria), HU147 (componentes), HU153 (tipos de
-- documento) y P5 (asignaturas sin area/componente/semestre "cualquiera"). Todo dentro de una transaccion revertida.
PRINT 'TEST START: test_consolidado_auditoria_catalogos';

DECLARE @plan UNIQUEIDENTIFIER, @uCoord UNIQUEIDENTIFIER, @idPrograma UNIQUEIDENTIFIER;
SELECT TOP 1 @plan = sp.idPlanEstudio, @uCoord = ci.idUsuario, @idPrograma = p.id
FROM dbo.uv_semestre_plan_estudio sp
INNER JOIN dbo.uv_programa p ON p.id = sp.idPrograma
INNER JOIN dbo.uv_coordinador_identidad ci ON ci.id = p.idCoordinador
WHERE ci.estaActivoUsuario = 1
ORDER BY sp.idPlanEstudio;
DECLARE @idFacultad UNIQUEIDENTIFIER = (SELECT idFacultad FROM dbo.uv_programa WHERE id = @idPrograma);
DECLARE @idInstitucion UNIQUEIDENTIFIER = (SELECT idInstitucion FROM dbo.uv_programa WHERE id = @idPrograma);
DECLARE @uDecano UNIQUEIDENTIFIER = (SELECT d.idUsuario FROM dbo.uv_decano d WHERE d.idFacultad = @idFacultad);
DECLARE @uAdmin UNIQUEIDENTIFIER = (SELECT TOP 1 a.idUsuario FROM dbo.uv_administrador a WHERE a.idInstitucion = @idInstitucion ORDER BY a.id);
DECLARE @uEstudiante UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_estudiante_identidad ORDER BY id);
DECLARE @semestre INT = (SELECT TOP 1 numeroSemestre FROM dbo.uv_semestre_plan_estudio WHERE idPlanEstudio = @plan ORDER BY numeroSemestre);
DECLARE @areaCodigo NVARCHAR(10) = (SELECT TOP 1 codigo FROM dbo.uv_area ORDER BY codigo);
IF @plan IS NULL OR @uDecano IS NULL OR @uAdmin IS NULL OR @uEstudiante IS NULL OR @semestre IS NULL OR @areaCodigo IS NULL
    THROW 56200, 'TEST FAILED: faltan fixtures del seed (coordinador con plan, decano, administrador, estudiante, area).', 1;

CREATE TABLE #consolidado (
    idGrupo UNIQUEIDENTIFIER, codigoGrupo INT, nombreGrupo NVARCHAR(100), idPeriodoAcademico UNIQUEIDENTIFIER,
    nombrePeriodoAcademico NVARCHAR(100), idPrograma UNIQUEIDENTIFIER, nombrePrograma NVARCHAR(100),
    idAsignatura UNIQUEIDENTIFIER, nombreAsignatura NVARCHAR(100), idDocente UNIQUEIDENTIFIER, nombreDocente NVARCHAR(250),
    estudiantesActivos INT, sesionesEjecutadas INT, asistencias INT, faltasSinJustaCausa INT, excusas INT,
    porcentajeAsistencia DECIMAL(5,2), porcentajeInasistencia DECIMAL(5,2), estudiantesRiesgo INT, estudiantesPerdida INT,
    totalRegistros INT);
CREATE TABLE #auditoria (
    id UNIQUEIDENTIFIER, occurredAt DATETIMEOFFSET(7), actorId NVARCHAR(120), actorType VARCHAR(20), nombreActor NVARCHAR(250),
    action VARCHAR(120), resourceType VARCHAR(120), resourceId NVARCHAR(120), result VARCHAR(20), correlationId UNIQUEIDENTIFIER,
    httpMethod VARCHAR(16), path NVARCHAR(240), httpStatus SMALLINT, clientIp VARCHAR(45), errorCode VARCHAR(120),
    metadata NVARCHAR(MAX), esAccionAsistencia BIT, totalRegistros INT);
CREATE TABLE #componentes (idComponente UNIQUEIDENTIFIER, codigo NVARCHAR(3), nombre NVARCHAR(50), totalAsignaturas INT);
CREATE TABLE #canonico (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000),
    mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @c UNIQUEIDENTIFIER = NEWID();
    DECLARE @rechazo NVARCHAR(4000);

    PRINT '-> T-061-01: consolidado por grupo con el ambito de cada rol';
    INSERT INTO #consolidado EXEC dbo.usp_consultar_consolidado_asistencia_grupos_paginado
        @idUsuarioEjecutor = @uCoord, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 100;
    IF EXISTS (SELECT 1 FROM #consolidado WHERE idPrograma <> @idPrograma)
        THROW 56201, 'TEST FAILED T-061-01: el coordinador vio grupos de otro programa.', 1;
    IF EXISTS (
        SELECT 1 FROM #consolidado k
        WHERE k.estudiantesActivos <> (SELECT COUNT(*) FROM dbo.uv_resumen_asistencia_estudiante_grupo r
                                      WHERE r.idGrupo = k.idGrupo AND r.codigoEstadoEstudiante = N'A')
           OR k.faltasSinJustaCausa <> (SELECT ISNULL(SUM(r.faltasSinJustaCausa), 0) FROM dbo.uv_resumen_asistencia_estudiante_grupo r
                                       WHERE r.idGrupo = k.idGrupo AND r.codigoEstadoEstudiante = N'A'))
        THROW 56202, 'TEST FAILED T-061-01: los totales del consolidado no coinciden con el resumen por estudiante.', 1;
    TRUNCATE TABLE #consolidado;
    INSERT INTO #consolidado EXEC dbo.usp_consultar_consolidado_asistencia_grupos_paginado
        @idUsuarioEjecutor = @uDecano, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 100;
    IF EXISTS (SELECT 1 FROM #consolidado k INNER JOIN dbo.uv_programa p ON p.id = k.idPrograma WHERE p.idFacultad <> @idFacultad)
        THROW 56203, 'TEST FAILED T-061-01: el decano vio grupos de otra facultad.', 1;
    TRUNCATE TABLE #consolidado;
    INSERT INTO #consolidado EXEC dbo.usp_consultar_consolidado_asistencia_grupos_paginado
        @idUsuarioEjecutor = @uAdmin, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 100, @idPrograma = @idPrograma;
    IF EXISTS (SELECT 1 FROM #consolidado WHERE idPrograma <> @idPrograma)
        THROW 56204, 'TEST FAILED T-061-01: el filtro por programa del administrador no se aplico.', 1;
    SET @rechazo = NULL;
    BEGIN TRY
        EXEC dbo.usp_consultar_consolidado_asistencia_grupos_paginado @idUsuarioEjecutor = @uEstudiante, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 10;
    END TRY
    BEGIN CATCH
        SET @rechazo = ERROR_MESSAGE();
    END CATCH;
    IF @rechazo IS NULL OR @rechazo NOT LIKE 'DBCODE=SEC_001|%'
        THROW 56205, 'TEST FAILED T-061-01: un estudiante no fue rechazado con SEC_001.', 1;
    PRINT 'TEST_PASS:T-061-01';

    PRINT '-> T-172-01: auditoria paginada solo para el administrador';
    DECLARE @evAsis UNIQUEIDENTIFIER = NEWID(), @evOtro UNIQUEIDENTIFIER = NEWID(), @t0 DATETIMEOFFSET(7) = DATEADD(DAY, -1, SYSUTCDATETIME());
    INSERT INTO dbo.AuditoriaEvento (id, occurredAt, actorId, actorType, action, resourceType, resourceId, result, correlationId, traceId, spanId, httpMethod, path, httpStatus, clientIp, errorCode, metadata)
    VALUES (@evAsis, TODATETIMEOFFSET(DATEADD(MINUTE, 5, CAST(@t0 AS DATETIME2)), '+00:00'), CONVERT(NVARCHAR(120), @uCoord), 'USER', 'REGISTRAR_ASISTENCIAS_SESION', 'SESION', N'QA-SESION', 'SUCCESS', NEWID(), NULL, NULL, 'POST', N'/api/v1/asistencias/sesion', 200, NULL, NULL, NULL),
           (@evOtro, TODATETIMEOFFSET(DATEADD(MINUTE, 6, CAST(@t0 AS DATETIME2)), '+00:00'), CONVERT(NVARCHAR(120), @uCoord), 'USER', 'VINCULAR_DOCENTE_PROGRAMA', 'DOCENTE', N'QA-DOCENTE', 'FAILURE', NEWID(), NULL, NULL, 'POST', N'/api/v1/coordinador/docentes', 409, NULL, 'ERR_QA', NULL);
    DECLARE @desde DATETIMEOFFSET(7) = @t0, @hasta DATETIMEOFFSET(7) = DATEADD(HOUR, 1, SYSUTCDATETIME());
    INSERT INTO #auditoria EXEC dbo.usp_consultar_auditoria_eventos_paginado
        @idUsuarioEjecutor = @uAdmin, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 100, @desdeUtc = @desde, @hastaUtc = @hasta;
    IF NOT EXISTS (SELECT 1 FROM #auditoria WHERE id = @evAsis AND esAccionAsistencia = 1 AND nombreActor IS NOT NULL)
       OR EXISTS (SELECT 1 FROM #auditoria WHERE id = @evOtro)
        THROW 56206, 'TEST FAILED T-172-01: por defecto debe traer solo acciones de asistencia, con el nombre del usuario.', 1;
    TRUNCATE TABLE #auditoria;
    INSERT INTO #auditoria EXEC dbo.usp_consultar_auditoria_eventos_paginado
        @idUsuarioEjecutor = @uAdmin, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 100, @desdeUtc = @desde, @hastaUtc = @hasta,
        @soloAsistencia = 0, @resultado = 'FAILURE', @idUsuarioActor = @uCoord;
    IF NOT EXISTS (SELECT 1 FROM #auditoria WHERE id = @evOtro) OR EXISTS (SELECT 1 FROM #auditoria WHERE id = @evAsis)
        THROW 56207, 'TEST FAILED T-172-01: los filtros de resultado, usuario y "todas" no se aplicaron.', 1;
    SET @rechazo = NULL;
    BEGIN TRY
        EXEC dbo.usp_consultar_auditoria_eventos_paginado @idUsuarioEjecutor = @uDecano, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 10, @desdeUtc = @desde, @hastaUtc = @hasta;
    END TRY
    BEGIN CATCH
        SET @rechazo = ERROR_MESSAGE();
    END CATCH;
    IF @rechazo IS NULL OR @rechazo NOT LIKE 'DBCODE=SEC_001|%'
        THROW 56208, 'TEST FAILED T-172-01: un decano no fue rechazado con SEC_001.', 1;
    SET @rechazo = NULL;
    BEGIN TRY
        EXEC dbo.usp_consultar_auditoria_eventos_paginado @idUsuarioEjecutor = @uAdmin, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 10, @desdeUtc = NULL, @hastaUtc = @hasta;
    END TRY
    BEGIN CATCH
        SET @rechazo = ERROR_MESSAGE();
    END CATCH;
    IF @rechazo IS NULL OR @rechazo NOT LIKE 'DBCODE=GEN_002|%'
        THROW 56209, 'TEST FAILED T-172-01: el rango de fechas incompleto no fue rechazado con GEN_002.', 1;
    PRINT 'TEST_PASS:T-172-01';

    PRINT '-> T-147-01: componentes de formacion BAS, INS y ESP';
    INSERT INTO #componentes EXEC dbo.usp_consultar_componentes_formacion @idUsuarioEjecutor = @uCoord, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #componentes WHERE codigo IN ('BAS', 'INS', 'ESP')) <> 3
        THROW 56210, 'TEST FAILED T-147-01: no se listaron los componentes BAS, INS y ESP con su codigo.', 1;
    SET @rechazo = NULL;
    BEGIN TRY
        EXEC dbo.usp_consultar_componentes_formacion @idUsuarioEjecutor = @uEstudiante, @idCorrelacion = @c;
    END TRY
    BEGIN CATCH
        SET @rechazo = ERROR_MESSAGE();
    END CATCH;
    IF @rechazo IS NULL OR @rechazo NOT LIKE 'DBCODE=SEC_001|%'
        THROW 56211, 'TEST FAILED T-147-01: un estudiante no fue rechazado con SEC_001.', 1;
    PRINT 'TEST_PASS:T-147-01';

    PRINT '-> T-153-01: tipos de documento (crear y editar nombre; solo administrador)';
    DECLARE @codigoTipo NVARCHAR(5) = CONCAT(N'Q', CHAR(65 + ABS(CHECKSUM(NEWID())) % 26), CHAR(65 + ABS(CHECKSUM(NEWID())) % 26), N'X');
    DECLARE @nombreTipo NVARCHAR(50) = CONCAT(N'QA Documento ', @codigoTipo);
    INSERT INTO #canonico EXEC dbo.usp_guardar_tipo_identificacion @codigo = @codigoTipo, @nombre = @nombreTipo, @idCorrelacion = @c, @idUsuarioEjecutor = @uAdmin;
    DECLARE @idTipo UNIQUEIDENTIFIER = (SELECT id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = @codigoTipo);
    IF (SELECT estadoResultado FROM #canonico) <> 1 OR @idTipo IS NULL
        THROW 56212, 'TEST FAILED T-153-01: el administrador no pudo crear el tipo de documento.', 1;
    TRUNCATE TABLE #canonico;
    INSERT INTO #canonico EXEC dbo.usp_guardar_tipo_identificacion @codigo = @codigoTipo, @nombre = N'QA Otro nombre', @idCorrelacion = @c, @idUsuarioEjecutor = @uAdmin;
    IF NOT EXISTS (SELECT 1 FROM #canonico WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE 'DBCODE=GEN_003|%')
        THROW 56213, 'TEST FAILED T-153-01: el codigo duplicado no fue rechazado con GEN_003.', 1;
    TRUNCATE TABLE #canonico;
    INSERT INTO #canonico EXEC dbo.usp_guardar_tipo_identificacion @codigo = N'Q1', @nombre = N'QA Codigo invalido', @idCorrelacion = @c, @idUsuarioEjecutor = @uAdmin;
    IF NOT EXISTS (SELECT 1 FROM #canonico WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE 'DBCODE=GEN_002|%')
        THROW 56214, 'TEST FAILED T-153-01: un codigo con numeros no fue rechazado con GEN_002.', 1;
    TRUNCATE TABLE #canonico;
    INSERT INTO #canonico EXEC dbo.usp_guardar_tipo_identificacion @idTipoIdentificacion = @idTipo, @codigo = N'ZZ', @nombre = N'QA Nombre editado', @idCorrelacion = @c, @idUsuarioEjecutor = @uAdmin;
    IF (SELECT estadoResultado FROM #canonico) <> 1
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_tipo_identificacion WHERE id = @idTipo AND nombre = N'QA Nombre editado' AND tipoIdentificacion = @codigoTipo)
        THROW 56215, 'TEST FAILED T-153-01: la edicion debe cambiar solo el nombre y conservar el codigo.', 1;
    TRUNCATE TABLE #canonico;
    INSERT INTO #canonico EXEC dbo.usp_guardar_tipo_identificacion @idTipoIdentificacion = @idTipo, @nombre = N'Cedula de ciudadania', @idCorrelacion = @c, @idUsuarioEjecutor = @uAdmin;
    IF NOT EXISTS (SELECT 1 FROM #canonico WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE 'DBCODE=GEN_003|%')
        THROW 56216, 'TEST FAILED T-153-01: el nombre repetido de otro tipo no fue rechazado con GEN_003.', 1;
    TRUNCATE TABLE #canonico;
    INSERT INTO #canonico EXEC dbo.usp_guardar_tipo_identificacion @idTipoIdentificacion = @c, @nombre = N'QA No existe', @idCorrelacion = @c, @idUsuarioEjecutor = @uAdmin;
    IF NOT EXISTS (SELECT 1 FROM #canonico WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE 'DBCODE=GEN_001|%')
        THROW 56217, 'TEST FAILED T-153-01: un tipo inexistente no fue rechazado con GEN_001.', 1;
    TRUNCATE TABLE #canonico;
    INSERT INTO #canonico EXEC dbo.usp_guardar_tipo_identificacion @codigo = N'QZZ', @nombre = N'QA Coordinador', @idCorrelacion = @c, @idUsuarioEjecutor = @uCoord;
    IF NOT EXISTS (SELECT 1 FROM #canonico WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE 'DBCODE=SEC_001|%')
        THROW 56218, 'TEST FAILED T-153-01: un coordinador no fue rechazado con SEC_001.', 1;
    PRINT 'TEST_PASS:T-153-01';

    PRINT '-> T-P5-01: asignaturas solo con area, componente y semestre existentes';
    DECLARE @asig UNIQUEIDENTIFIER = NEWID();
    DECLARE @codAsig NVARCHAR(50) = CONCAT(N'QP5', LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8));
    TRUNCATE TABLE #canonico;
    INSERT INTO #canonico EXEC dbo.usp_crear_asignatura @idAsignatura = @asig, @codigo = @codAsig, @nombre = N'QA P5', @creditos = 3,
        @idPlanEstudio = @plan, @semestreNumero = @semestre, @nombreArea = @areaCodigo, @nombreComponente = N'Obligatoria',
        @idCorrelacion = @c, @idUsuarioEjecutor = @uCoord;
    IF NOT EXISTS (SELECT 1 FROM #canonico WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE 'DBCODE=GEN_001|%')
       OR EXISTS (SELECT 1 FROM dbo.uv_asignatura WHERE id = @asig)
        THROW 56219, 'TEST FAILED T-P5-01: un componente inexistente no fue rechazado con GEN_001.', 1;
    TRUNCATE TABLE #canonico;
    INSERT INTO #canonico EXEC dbo.usp_crear_asignatura @idAsignatura = @asig, @codigo = @codAsig, @nombre = N'QA P5', @creditos = 3,
        @idPlanEstudio = @plan, @semestreNumero = @semestre, @nombreArea = N'Area que no existe', @nombreComponente = N'ESP',
        @idCorrelacion = @c, @idUsuarioEjecutor = @uCoord;
    IF NOT EXISTS (SELECT 1 FROM #canonico WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE 'DBCODE=GEN_001|%')
        THROW 56220, 'TEST FAILED T-P5-01: un area inexistente no fue rechazada con GEN_001.', 1;
    TRUNCATE TABLE #canonico;
    INSERT INTO #canonico EXEC dbo.usp_crear_asignatura @idAsignatura = @asig, @codigo = @codAsig, @nombre = N'QA P5', @creditos = 3,
        @idPlanEstudio = @plan, @semestreNumero = 99, @nombreArea = @areaCodigo, @nombreComponente = N'ESP',
        @idCorrelacion = @c, @idUsuarioEjecutor = @uCoord;
    IF NOT EXISTS (SELECT 1 FROM #canonico WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE 'DBCODE=PLA_004|%')
        THROW 56221, 'TEST FAILED T-P5-01: un semestre que no esta en el plan no fue rechazado con PLA_004.', 1;
    TRUNCATE TABLE #canonico;
    INSERT INTO #canonico EXEC dbo.usp_crear_asignatura @idAsignatura = @asig, @codigo = @codAsig, @nombre = N'QA P5', @creditos = 3,
        @idPlanEstudio = @plan, @semestreNumero = @semestre, @nombreArea = @areaCodigo, @nombreComponente = N'especificas',
        @idCorrelacion = @c, @idUsuarioEjecutor = @uCoord;
    IF (SELECT estadoResultado FROM #canonico) <> 1
       OR NOT EXISTS (SELECT 1 FROM dbo.Asignatura a INNER JOIN dbo.Componente k ON k.id = a.componente WHERE a.id = @asig AND k.codigo = 'ESP')
        THROW 56222, 'TEST FAILED T-P5-01: crear con el nombre exacto del componente no asigno ESP.', 1;
    TRUNCATE TABLE #canonico;
    INSERT INTO #canonico EXEC dbo.usp_actualizar_asignatura @idAsignatura = @asig, @codigo = NULL, @nombre = NULL, @creditos = NULL,
        @idPlanEstudio = @plan, @semestreNumero = @semestre, @nombreArea = NULL, @nombreComponente = N'BAS',
        @idCorrelacion = @c, @idUsuarioEjecutor = @uCoord;
    IF (SELECT estadoResultado FROM #canonico) <> 1
       OR NOT EXISTS (SELECT 1 FROM dbo.Asignatura a INNER JOIN dbo.Componente k ON k.id = a.componente WHERE a.id = @asig AND k.codigo = 'BAS')
        THROW 56223, 'TEST FAILED T-P5-01: actualizar no aplico el componente BAS.', 1;
    TRUNCATE TABLE #canonico;
    INSERT INTO #canonico EXEC dbo.usp_actualizar_asignatura @idAsignatura = @asig, @codigo = NULL, @nombre = NULL, @creditos = NULL,
        @idPlanEstudio = @plan, @semestreNumero = @semestre, @nombreArea = NULL, @nombreComponente = N'Electiva',
        @idCorrelacion = @c, @idUsuarioEjecutor = @uCoord;
    IF NOT EXISTS (SELECT 1 FROM #canonico WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE 'DBCODE=GEN_001|%')
       OR NOT EXISTS (SELECT 1 FROM dbo.Asignatura a INNER JOIN dbo.Componente k ON k.id = a.componente WHERE a.id = @asig AND k.codigo = 'BAS')
        THROW 56224, 'TEST FAILED T-P5-01: actualizar con un componente inexistente debe rechazar y conservar el actual.', 1;
    PRINT 'TEST_PASS:T-P5-01';

    PRINT '-> T-ASI-01: creditos obligatorios, semestre del plan y plan del programa del coordinador (John 2026-11-04)';
    DECLARE @asig2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @codAsig2 NVARCHAR(50) = CONCAT(N'QAS', LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8));
    DECLARE @semFuera INT = (SELECT TOP 1 s.numero FROM dbo.uv_semestre s
                             WHERE NOT EXISTS (SELECT 1 FROM dbo.uv_semestre_plan_estudio sp
                                               WHERE sp.idPlanEstudio = @plan AND sp.numeroSemestre = s.numero)
                             ORDER BY s.numero);
    DECLARE @planAjeno UNIQUEIDENTIFIER = (SELECT TOP 1 pe.id FROM dbo.uv_plan_estudio pe
                                           INNER JOIN dbo.uv_programa p ON p.id = pe.idPrograma
                                           WHERE pe.idPrograma <> @idPrograma
                                             AND NOT EXISTS (SELECT 1 FROM dbo.uv_coordinador_identidad ci
                                                             WHERE ci.id = p.idCoordinador AND ci.idUsuario = @uCoord)
                                           ORDER BY pe.id);
    TRUNCATE TABLE #canonico;
    INSERT INTO #canonico EXEC dbo.usp_crear_asignatura @idAsignatura = @asig2, @codigo = @codAsig2, @nombre = N'QA ASI', @creditos = NULL,
        @idPlanEstudio = @plan, @semestreNumero = @semestre, @nombreArea = @areaCodigo, @nombreComponente = N'ESP',
        @idCorrelacion = @c, @idUsuarioEjecutor = @uCoord;
    IF NOT EXISTS (SELECT 1 FROM #canonico WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE 'DBCODE=ASI_001|%')
       OR EXISTS (SELECT 1 FROM dbo.uv_asignatura WHERE id = @asig2)
        THROW 56234, 'TEST FAILED T-ASI-01: creditos nulos no fueron rechazados con ASI_001.', 1;
    TRUNCATE TABLE #canonico;
    INSERT INTO #canonico EXEC dbo.usp_crear_asignatura @idAsignatura = @asig2, @codigo = @codAsig2, @nombre = N'QA ASI', @creditos = 0,
        @idPlanEstudio = @plan, @semestreNumero = @semestre, @nombreArea = @areaCodigo, @nombreComponente = N'ESP',
        @idCorrelacion = @c, @idUsuarioEjecutor = @uCoord;
    IF NOT EXISTS (SELECT 1 FROM #canonico WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE 'DBCODE=ASI_001|%')
        THROW 56235, 'TEST FAILED T-ASI-01: creditos en cero no fueron rechazados con ASI_001.', 1;
    TRUNCATE TABLE #canonico;
    INSERT INTO #canonico EXEC dbo.usp_crear_asignatura @idAsignatura = @asig2, @codigo = @codAsig2, @nombre = N'QA ASI', @creditos = 3,
        @idPlanEstudio = @c, @semestreNumero = @semestre, @nombreArea = @areaCodigo, @nombreComponente = N'ESP',
        @idCorrelacion = @c, @idUsuarioEjecutor = @uCoord;
    IF NOT EXISTS (SELECT 1 FROM #canonico WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE 'DBCODE=PLA_002|%')
        THROW 56236, 'TEST FAILED T-ASI-01: un plan inexistente no fue rechazado con PLA_002.', 1;
    IF @semFuera IS NOT NULL
    BEGIN
        DECLARE @semestresAntes INT = (SELECT COUNT(*) FROM dbo.uv_semestre_plan_estudio WHERE idPlanEstudio = @plan);
        TRUNCATE TABLE #canonico;
        INSERT INTO #canonico EXEC dbo.usp_crear_asignatura @idAsignatura = @asig2, @codigo = @codAsig2, @nombre = N'QA ASI', @creditos = 3,
            @idPlanEstudio = @plan, @semestreNumero = @semFuera, @nombreArea = @areaCodigo, @nombreComponente = N'ESP',
            @idCorrelacion = @c, @idUsuarioEjecutor = @uCoord;
        IF NOT EXISTS (SELECT 1 FROM #canonico WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE 'DBCODE=PLA_004|%')
           OR (SELECT COUNT(*) FROM dbo.uv_semestre_plan_estudio WHERE idPlanEstudio = @plan) <> @semestresAntes
            THROW 56237, 'TEST FAILED T-ASI-01: un semestre fuera del plan debe rechazarse con PLA_004 sin crearlo en el plan.', 1;
    END
    ELSE
        PRINT 'T-ASI-01: sin semestre del catalogo fuera del plan en el seed; caso PLA_004 cubierto por T-P5-01.';
    IF @planAjeno IS NOT NULL
    BEGIN
        DECLARE @semAjeno INT = (SELECT TOP 1 numeroSemestre FROM dbo.uv_semestre_plan_estudio WHERE idPlanEstudio = @planAjeno ORDER BY numeroSemestre);
        TRUNCATE TABLE #canonico;
        INSERT INTO #canonico EXEC dbo.usp_crear_asignatura @idAsignatura = @asig2, @codigo = @codAsig2, @nombre = N'QA ASI', @creditos = 3,
            @idPlanEstudio = @planAjeno, @semestreNumero = @semAjeno, @nombreArea = @areaCodigo, @nombreComponente = N'ESP',
            @idCorrelacion = @c, @idUsuarioEjecutor = @uCoord;
        IF NOT EXISTS (SELECT 1 FROM #canonico WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE 'DBCODE=SEC_002|%')
           OR EXISTS (SELECT 1 FROM dbo.uv_asignatura WHERE id = @asig2)
            THROW 56238, 'TEST FAILED T-ASI-01: el plan de otro programa no fue rechazado con SEC_002.', 1;
    END
    ELSE
        PRINT 'T-ASI-01: el seed no tiene planes de otro programa; titularidad cubierta por usp_validar_titularidad_jerarquica_interno.';
    TRUNCATE TABLE #canonico;
    INSERT INTO #canonico EXEC dbo.usp_actualizar_asignatura @idAsignatura = @asig, @codigo = NULL, @nombre = NULL, @creditos = -1,
        @idPlanEstudio = @plan, @semestreNumero = @semestre, @nombreArea = NULL, @nombreComponente = NULL,
        @idCorrelacion = @c, @idUsuarioEjecutor = @uCoord;
    IF NOT EXISTS (SELECT 1 FROM #canonico WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE 'DBCODE=ASI_001|%')
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_asignatura WHERE id = @asig AND credito = 3)
        THROW 56239, 'TEST FAILED T-ASI-01: actualizar con creditos negativos debe rechazar con ASI_001 y conservar los creditos.', 1;
    PRINT 'TEST_PASS:T-ASI-01';

    PRINT '-> T-PAG-03: paginacion invalida en las consultas nuevas';
    SET @rechazo = NULL;
    BEGIN TRY
        EXEC dbo.usp_consultar_consolidado_asistencia_grupos_paginado @idUsuarioEjecutor = @uCoord, @idCorrelacion = @c, @numeroPagina = 0, @tamanoPagina = 10;
    END TRY
    BEGIN CATCH
        SET @rechazo = ERROR_MESSAGE();
    END CATCH;
    IF @rechazo IS NULL OR @rechazo NOT LIKE 'DBCODE=PAG_001|%'
        THROW 56225, 'TEST FAILED T-PAG-03: la pagina 0 no fue rechazada con PAG_001.', 1;
    PRINT 'TEST_PASS:T-PAG-03';

    IF SESSION_CONTEXT(N'idUsuarioEjecutor') IS NOT NULL
        THROW 56226, 'TEST FAILED: las consultas no restauraron el SESSION_CONTEXT previo.', 1;
    IF XACT_STATE() <> 1
        THROW 56227, 'TEST FAILED: un rechazo de validacion condeno la transaccion del llamador.', 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DROP TABLE IF EXISTS #consolidado, #auditoria, #componentes, #canonico;
    THROW;
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
DROP TABLE IF EXISTS #consolidado, #auditoria, #componentes, #canonico;
PRINT 'TEST_PASS:TEST_CONSOLIDADO_AUDITORIA_CATALOGOS';
GO
