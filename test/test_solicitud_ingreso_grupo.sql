USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
-- El indice unico filtrado de SolicitudIngresoGrupo exige QUOTED_IDENTIFIER ON para el DML (sqlcmd lo deja OFF).
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ============================================================================
-- HU053/HU054/HU055: solicitudes de ingreso a un grupo (S-01..S-12 del TEST_PLAN). Diseño aprobado por John
-- (2026-10-27): el estudiante solicita; el DOCENTE TITULAR acepta (con cupo => matricula; sin cupo => EN ESPERA) o
-- rechaza con motivo; puede aceptar a CUALQUIERA de la lista de espera cuando se libera cupo; el estudiante retira su
-- solicitud abierta; sin vencimiento. Estados (dbo.Estado): P, A, R, E (en espera), X (retirada).
-- Fixtures dentro de UNA transaccion con ROLLBACK final; los THROW de las consultas corren fuera.
-- ============================================================================
IF OBJECT_ID('tempdb..#sig_expect') IS NOT NULL DROP PROCEDURE #sig_expect;
GO
CREATE PROCEDURE #sig_expect @label VARCHAR(100), @ok BIT
AS
BEGIN
    IF @ok IS NULL OR @ok <> 1
    BEGIN
        DECLARE @mensaje NVARCHAR(400) = CONCAT('TEST FAILED: HU053_HU055_', @label);
        THROW 52360, @mensaje, 1;
    END
END;
GO

PRINT 'TEST START: test_solicitud_ingreso_grupo';

DECLARE @group UNIQUEIDENTIFIER, @teacher UNIQUEIDENTIFIER, @periodo UNIQUEIDENTIFIER, @userT UNIQUEIDENTIFIER;
DECLARE @userOtroDocente UNIQUEIDENTIFIER, @studentActivo UNIQUEIDENTIFIER, @userActivo UNIQUEIDENTIFIER, @tipoCC UNIQUEIDENTIFIER;

SELECT TOP 1 @group = g.id, @teacher = g.docente, @periodo = g.periodoAcademico
FROM dbo.Grupo g
WHERE EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo x WHERE x.idGrupo = g.id AND x.codigoEstadoEstudiante = 'A')
ORDER BY g.id;
SELECT @userT = usuario FROM dbo.Docente WHERE id = @teacher;
SELECT TOP 1 @userOtroDocente = usuario FROM dbo.Docente WHERE id <> @teacher AND usuario <> @userT ORDER BY id;
SELECT TOP 1 @studentActivo = idEstudiante FROM dbo.uv_estudiante_grupo WHERE idGrupo = @group AND codigoEstadoEstudiante = 'A' ORDER BY idEstudiante;
SELECT @userActivo = usuario FROM dbo.Estudiante WHERE id = @studentActivo;
SELECT TOP 1 @tipoCC = id FROM dbo.TipoIdentificacion ORDER BY id;

IF @group IS NULL OR @userT IS NULL OR @userOtroDocente IS NULL OR @studentActivo IS NULL OR @tipoCC IS NULL
    THROW 52361, 'TEST FAILED: HU053_HU055 fixture missing (seed data).', 1;

DECLARE @corr UNIQUEIDENTIFIER = NEWID(), @ok BIT, @msg NVARCHAR(4000), @n INT;
DECLARE @zona NVARCHAR(100) = dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER');
DECLARE @hoyLocal DATE = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE @zona AS DATE);
DECLARE @uA UNIQUEIDENTIFIER = NEWID(), @uB UNIQUEIDENTIFIER = NEWID(), @uC UNIQUEIDENTIFIER = NEWID(), @uD UNIQUEIDENTIFIER = NEWID();
DECLARE @eA UNIQUEIDENTIFIER = NEWID(), @eB UNIQUEIDENTIFIER = NEWID(), @eC UNIQUEIDENTIFIER = NEWID(), @eD UNIQUEIDENTIFIER = NEWID();
DECLARE @sA UNIQUEIDENTIFIER = NEWID(), @sB UNIQUEIDENTIFIER = NEWID(), @sC UNIQUEIDENTIFIER = NEWID(), @sD UNIQUEIDENTIFIER = NEWID();
DECLARE @sD2 UNIQUEIDENTIFIER = NEWID(), @sX UNIQUEIDENTIFIER = NEWID();

CREATE TABLE #r (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
CREATE TABLE #rx (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000),
    estadoResultado BIT, codigoEstadoResultante CHAR(1));
CREATE TABLE #doc (idSolicitud UNIQUEIDENTIFIER, idEstudiante UNIQUEIDENTIFIER, nombreEstudiante NVARCHAR(400), numeroIdentificacion INT,
    codigoEstado CHAR(1), nombreEstado NVARCHAR(50), fechaSolicitudUtc DATETIME2(7), fechaResolucionUtc DATETIME2(7),
    motivoRechazo NVARCHAR(500), posicionEspera INT, capacidadGrupo INT, cuposDisponibles INT, totalRegistros INT);
CREATE TABLE #est (idSolicitud UNIQUEIDENTIFIER, idGrupo UNIQUEIDENTIFIER, codigoGrupo INT, nombreGrupo NVARCHAR(50),
    idAsignatura UNIQUEIDENTIFIER, nombreAsignatura NVARCHAR(100), nombreDocente NVARCHAR(400), codigoEstado CHAR(1),
    nombreEstado NVARCHAR(50), fechaSolicitudUtc DATETIME2(7), fechaResolucionUtc DATETIME2(7), motivoRechazo NVARCHAR(500),
    totalRegistros INT);
CREATE TABLE #d (rolDestinatario VARCHAR(20), idUsuario UNIQUEIDENTIFIER, nombreCompleto NVARCHAR(400), correo NVARCHAR(100),
    idGrupo UNIQUEIDENTIFIER, codigoGrupo INT, nombreGrupo NVARCHAR(50), nombreAsignatura NVARCHAR(100));

BEGIN TRANSACTION;
BEGIN TRY
    -- Periodo vigente y UN cupo libre (capacidad = activos + 1).
    UPDATE dbo.PeriodoAcademico SET fechaFin = DATEADD(DAY, 30, @hoyLocal) WHERE id = @periodo;
    UPDATE dbo.Grupo SET cantidadEstudiantes = (SELECT COUNT(*) FROM dbo.uv_estudiante_grupo
        WHERE idGrupo = @group AND codigoEstadoEstudiante = 'A') + 1 WHERE id = @group;

    -- Cuatro estudiantes sin matricula en el grupo.
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uA, @tipoCC, 970005301, N'Ana', N'Qa', N'Ana', N'Sig', N'qa.sig.a@test.local', 1, 1, N'HashBackend_R1'),
           (@uB, @tipoCC, 970005302, N'Beto', N'Qa', N'Beto', N'Sig', N'qa.sig.b@test.local', 1, 1, N'HashBackend_R1'),
           (@uC, @tipoCC, 970005303, N'Caro', N'Qa', N'Caro', N'Sig', N'qa.sig.c@test.local', 1, 1, N'HashBackend_R1'),
           (@uD, @tipoCC, 970005304, N'Dani', N'Qa', N'Dani', N'Sig', N'qa.sig.d@test.local', 1, 1, N'HashBackend_R1');
    INSERT INTO dbo.Estudiante (id, usuario) VALUES (@eA, @uA), (@eB, @uB), (@eC, @uC), (@eD, @uD);

    -- -------------------------------------------------------- S-01 el estudiante A solicita ingreso: PENDIENTE
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SIG_006';
    INSERT INTO #r EXEC dbo.usp_registrar_solicitud_ingreso_grupo @idSolicitud = @sA, @idGrupo = @group, @idCorrelacion = @corr, @idUsuarioEjecutor = @uA;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND mensajeUsuarioResultado = @msg)
        AND EXISTS (SELECT 1 FROM dbo.SolicitudIngresoGrupo s INNER JOIN dbo.Estado est ON est.id = s.estado
            WHERE s.id = @sA AND s.estudiante = @eA AND s.grupo = @group AND est.codigo = 'P' AND s.fechaSolicitudUtc IS NOT NULL
              AND s.fechaResolucionUtc IS NULL AND s.estudianteGrupo IS NULL), 1, 0);
    EXEC #sig_expect 'S01_REGISTER_PENDING', @ok;
    PRINT 'TEST_PASS:S-01';

    -- -------------------------------------------------------- S-02 rechazos al solicitar
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_registrar_solicitud_ingreso_grupo @idSolicitud = @sX, @idGrupo = @group, @idCorrelacion = @corr, @idUsuarioEjecutor = @uA;
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SIG_005';
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg), 1, 0);
    EXEC #sig_expect 'S02_DUPLICATE_OPEN_REQUEST', @ok;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_registrar_solicitud_ingreso_grupo @idSolicitud = @sX, @idGrupo = @group, @idCorrelacion = @corr, @idUsuarioEjecutor = @userActivo;
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SIG_004';
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg), 1, 0);
    EXEC #sig_expect 'S02_ALREADY_ENROLLED', @ok;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_registrar_solicitud_ingreso_grupo @idSolicitud = @sX, @idGrupo = @group, @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SIG_001';
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg), 1, 0);
    EXEC #sig_expect 'S02_NOT_A_STUDENT', @ok;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_registrar_solicitud_ingreso_grupo @idSolicitud = @sX, @idGrupo = '00000000-0000-0000-0000-0000000000AB', @idCorrelacion = @corr, @idUsuarioEjecutor = @uB;
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SIG_002';
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg), 1, 0);
    EXEC #sig_expect 'S02_UNKNOWN_GROUP', @ok;
    UPDATE dbo.PeriodoAcademico SET fechaFin = DATEADD(DAY, -1, @hoyLocal) WHERE id = @periodo;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_registrar_solicitud_ingreso_grupo @idSolicitud = @sX, @idGrupo = @group, @idCorrelacion = @corr, @idUsuarioEjecutor = @uB;
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SIG_003';
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg)
        AND NOT EXISTS (SELECT 1 FROM dbo.SolicitudIngresoGrupo WHERE id = @sX), 1, 0);
    EXEC #sig_expect 'S02_PERIOD_FINISHED', @ok;
    UPDATE dbo.PeriodoAcademico SET fechaFin = DATEADD(DAY, 30, @hoyLocal) WHERE id = @periodo;
    PRINT 'TEST_PASS:S-02';

    -- -------------------------------------------------------- S-03 B, C y D solicitan
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_registrar_solicitud_ingreso_grupo @idSolicitud = @sB, @idGrupo = @group, @idCorrelacion = @corr, @idUsuarioEjecutor = @uB;
    INSERT INTO #r EXEC dbo.usp_registrar_solicitud_ingreso_grupo @idSolicitud = @sC, @idGrupo = @group, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC;
    INSERT INTO #r EXEC dbo.usp_registrar_solicitud_ingreso_grupo @idSolicitud = @sD, @idGrupo = @group, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD;
    SET @ok = IIF((SELECT COUNT(*) FROM #r WHERE estadoResultado = 1) = 3, 1, 0);
    EXEC #sig_expect 'S03_OTHERS_REGISTER', @ok;
    PRINT 'TEST_PASS:S-03';

    -- -------------------------------------------------------- S-04 resolver: otro docente, accion invalida, rechazo sin motivo
    INSERT INTO #rx EXEC dbo.usp_resolver_solicitud_ingreso_grupo @idSolicitud = @sA, @accion = N'ACEPTAR', @motivo = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @userOtroDocente;
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SIG_007';
    SET @ok = IIF(EXISTS (SELECT 1 FROM #rx WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg), 1, 0);
    EXEC #sig_expect 'S04_ONLY_TITULAR', @ok;
    TRUNCATE TABLE #rx;
    INSERT INTO #rx EXEC dbo.usp_resolver_solicitud_ingreso_grupo @idSolicitud = @sA, @accion = N'BORRAR', @motivo = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SIG_009';
    SET @ok = IIF(EXISTS (SELECT 1 FROM #rx WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg), 1, 0);
    EXEC #sig_expect 'S04_INVALID_ACTION', @ok;
    TRUNCATE TABLE #rx;
    INSERT INTO #rx EXEC dbo.usp_resolver_solicitud_ingreso_grupo @idSolicitud = @sC, @accion = N'RECHAZAR', @motivo = N'  ', @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SIG_010';
    SET @ok = IIF(EXISTS (SELECT 1 FROM #rx WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg), 1, 0);
    EXEC #sig_expect 'S04_REJECT_REASON_REQUIRED', @ok;
    PRINT 'TEST_PASS:S-04';

    -- -------------------------------------------------------- S-05 aceptar A con el unico cupo: matricula activa
    TRUNCATE TABLE #rx;
    INSERT INTO #rx EXEC dbo.usp_resolver_solicitud_ingreso_grupo @idSolicitud = @sA, @accion = N'ACEPTAR', @motivo = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SIG_011';
    SET @ok = IIF(EXISTS (SELECT 1 FROM #rx WHERE estadoResultado = 1 AND mensajeUsuarioResultado = @msg AND codigoEstadoResultante = 'A')
        AND EXISTS (SELECT 1 FROM dbo.SolicitudIngresoGrupo s INNER JOIN dbo.Estado est ON est.id = s.estado
            INNER JOIN dbo.EstudianteGrupo eg ON eg.id = s.estudianteGrupo
            WHERE s.id = @sA AND est.codigo = 'A' AND eg.estudiante = @eA AND eg.grupo = @group AND s.fechaResolucionUtc IS NOT NULL
              AND s.docenteResolutor = @teacher)
        AND (SELECT cuposDisponibles FROM dbo.uv_grupo WHERE id = @group) = 0, 1, 0);
    EXEC #sig_expect 'S05_ACCEPT_ENROLS', @ok;
    PRINT 'TEST_PASS:S-05';

    -- -------------------------------------------------------- S-06 aceptar B sin cupo: EN ESPERA; reintentar: conflicto
    TRUNCATE TABLE #rx;
    INSERT INTO #rx EXEC dbo.usp_resolver_solicitud_ingreso_grupo @idSolicitud = @sB, @accion = N'ACEPTAR', @motivo = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SIG_012';
    SET @ok = IIF(EXISTS (SELECT 1 FROM #rx WHERE estadoResultado = 1 AND mensajeUsuarioResultado = @msg AND codigoEstadoResultante = 'E')
        AND NOT EXISTS (SELECT 1 FROM dbo.EstudianteGrupo WHERE estudiante = @eB AND grupo = @group), 1, 0);
    EXEC #sig_expect 'S06_NO_SEAT_WAITING_LIST', @ok;
    -- D tambien queda en espera (despues de B): la lista guarda el orden de llegada.
    TRUNCATE TABLE #rx;
    INSERT INTO #rx EXEC dbo.usp_resolver_solicitud_ingreso_grupo @idSolicitud = @sD, @accion = N'ACEPTAR', @motivo = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    TRUNCATE TABLE #rx;
    INSERT INTO #rx EXEC dbo.usp_resolver_solicitud_ingreso_grupo @idSolicitud = @sB, @accion = N'ACEPTAR', @motivo = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SIG_013';
    SET @ok = IIF(EXISTS (SELECT 1 FROM #rx WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg), 1, 0);
    EXEC #sig_expect 'S06_STILL_NO_SEAT', @ok;
    PRINT 'TEST_PASS:S-06';

    -- -------------------------------------------------------- S-07 rechazar C con motivo; resolverla de nuevo: ya resuelta
    TRUNCATE TABLE #rx;
    INSERT INTO #rx EXEC dbo.usp_resolver_solicitud_ingreso_grupo @idSolicitud = @sC, @accion = N'RECHAZAR', @motivo = N'  Grupo exclusivo de otra cohorte  ', @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SIG_014';
    SET @ok = IIF(EXISTS (SELECT 1 FROM #rx WHERE estadoResultado = 1 AND mensajeUsuarioResultado = @msg AND codigoEstadoResultante = 'R')
        AND EXISTS (SELECT 1 FROM dbo.SolicitudIngresoGrupo WHERE id = @sC AND motivoRechazo = N'Grupo exclusivo de otra cohorte'), 1, 0);
    EXEC #sig_expect 'S07_REJECT_WITH_REASON', @ok;
    TRUNCATE TABLE #rx;
    INSERT INTO #rx EXEC dbo.usp_resolver_solicitud_ingreso_grupo @idSolicitud = @sC, @accion = N'ACEPTAR', @motivo = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SIG_008';
    SET @ok = IIF(EXISTS (SELECT 1 FROM #rx WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg), 1, 0);
    EXEC #sig_expect 'S07_ALREADY_RESOLVED', @ok;
    PRINT 'TEST_PASS:S-07';

    -- -------------------------------------------------------- S-08 se libera cupo (HU051) y el docente elige a D (no al primero de la lista)
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_retirar_estudiante_grupo @idGrupo = @group, @idEstudiante = @eA, @motivo = N'Libera cupo QA', @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    TRUNCATE TABLE #rx;
    INSERT INTO #rx EXEC dbo.usp_resolver_solicitud_ingreso_grupo @idSolicitud = @sD, @accion = N'ACEPTAR', @motivo = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1)
        AND EXISTS (SELECT 1 FROM #rx WHERE estadoResultado = 1 AND codigoEstadoResultante = 'A')
        AND EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo WHERE idGrupo = @group AND idEstudiante = @eD AND codigoEstadoEstudiante = 'A')
        AND EXISTS (SELECT 1 FROM dbo.SolicitudIngresoGrupo s INNER JOIN dbo.Estado est ON est.id = s.estado WHERE s.id = @sB AND est.codigo = 'E'), 1, 0);
    EXEC #sig_expect 'S08_TEACHER_PICKS_ANY_FROM_WAITING_LIST', @ok;
    PRINT 'TEST_PASS:S-08';

    -- -------------------------------------------------------- S-09 consultas: bandeja del docente (orden de llegada y posicion) y mis solicitudes
    INSERT INTO #doc EXEC dbo.usp_consultar_solicitudes_ingreso_grupo_docente
        @idGrupo = @group, @codigoEstado = NULL, @numeroPagina = 1, @tamanoPagina = 100, @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    SET @ok = IIF((SELECT COUNT(*) FROM #doc WHERE idSolicitud IN (@sA, @sB, @sC, @sD)) = 4
        AND EXISTS (SELECT 1 FROM #doc WHERE idSolicitud = @sB AND codigoEstado = 'E' AND posicionEspera = 1 AND cuposDisponibles = 0
            AND nombreEstudiante LIKE N'Beto%' AND numeroIdentificacion = 970005302)
        AND EXISTS (SELECT 1 FROM #doc WHERE idSolicitud = @sC AND codigoEstado = 'R' AND posicionEspera IS NULL
            AND motivoRechazo = N'Grupo exclusivo de otra cohorte')
        AND (SELECT TOP 1 idSolicitud FROM #doc WHERE idSolicitud IN (@sA, @sB, @sC, @sD) ORDER BY fechaSolicitudUtc, idSolicitud) = @sA, 1, 0);
    EXEC #sig_expect 'S09_TEACHER_INBOX', @ok;
    TRUNCATE TABLE #doc;
    INSERT INTO #doc EXEC dbo.usp_consultar_solicitudes_ingreso_grupo_docente
        @idGrupo = @group, @codigoEstado = N'E', @numeroPagina = 1, @tamanoPagina = 100, @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    SET @ok = IIF(NOT EXISTS (SELECT 1 FROM #doc WHERE codigoEstado <> 'E') AND EXISTS (SELECT 1 FROM #doc WHERE idSolicitud = @sB), 1, 0);
    EXEC #sig_expect 'S09_TEACHER_FILTER', @ok;
    TRUNCATE TABLE #doc;
    INSERT INTO #doc EXEC dbo.usp_consultar_solicitudes_ingreso_grupo_docente
        @idGrupo = @group, @codigoEstado = NULL, @numeroPagina = 1, @tamanoPagina = 100, @idCorrelacion = @corr, @idUsuarioEjecutor = @userOtroDocente;
    SET @ok = IIF((SELECT COUNT(*) FROM #doc) = 0, 1, 0);
    EXEC #sig_expect 'S09_TEACHER_SCOPED', @ok;
    INSERT INTO #est EXEC dbo.usp_consultar_solicitudes_ingreso_estudiante
        @codigoEstado = NULL, @numeroPagina = 1, @tamanoPagina = 100, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC;
    SET @ok = IIF((SELECT COUNT(*) FROM #est) = 1 AND EXISTS (SELECT 1 FROM #est WHERE idSolicitud = @sC AND codigoEstado = 'R'
        AND idGrupo = @group AND nombreAsignatura IS NOT NULL AND nombreDocente <> N'' AND totalRegistros = 1), 1, 0);
    EXEC #sig_expect 'S09_STUDENT_OWN_ONLY', @ok;
    PRINT 'TEST_PASS:S-09';

    -- -------------------------------------------------------- S-10 el estudiante retira su solicitud abierta y puede volver a solicitar
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_retirar_solicitud_ingreso_grupo @idSolicitud = @sB, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC;
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SIG_007';
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg), 1, 0);
    EXEC #sig_expect 'S10_ONLY_OWNER_WITHDRAWS', @ok;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_retirar_solicitud_ingreso_grupo @idSolicitud = @sB, @idCorrelacion = @corr, @idUsuarioEjecutor = @uB;
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SIG_015';
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND mensajeUsuarioResultado = @msg)
        AND EXISTS (SELECT 1 FROM dbo.SolicitudIngresoGrupo s INNER JOIN dbo.Estado est ON est.id = s.estado
            WHERE s.id = @sB AND est.codigo = 'X' AND s.fechaResolucionUtc IS NOT NULL), 1, 0);
    EXEC #sig_expect 'S10_WITHDRAW', @ok;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_retirar_solicitud_ingreso_grupo @idSolicitud = @sB, @idCorrelacion = @corr, @idUsuarioEjecutor = @uB;
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SIG_008';
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg), 1, 0);
    EXEC #sig_expect 'S10_WITHDRAW_TWICE', @ok;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_registrar_solicitud_ingreso_grupo @idSolicitud = @sD2, @idGrupo = @group, @idCorrelacion = @corr, @idUsuarioEjecutor = @uB;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1), 1, 0);
    EXEC #sig_expect 'S10_CAN_REQUEST_AGAIN', @ok;
    PRINT 'TEST_PASS:S-10';

    -- -------------------------------------------------------- S-11 destinatarios: estudiante y docente; terceros sin filas
    INSERT INTO #d EXEC dbo.usp_consultar_destinatarios_solicitud_ingreso_grupo @idSolicitud = @sC, @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    INSERT INTO #d EXEC dbo.usp_consultar_destinatarios_solicitud_ingreso_grupo @idSolicitud = @sC, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC;
    SET @ok = IIF((SELECT COUNT(*) FROM #d) = 4
        AND (SELECT COUNT(*) FROM #d WHERE rolDestinatario = 'ESTUDIANTE' AND idUsuario = @uC AND correo = N'qa.sig.c@test.local') = 2
        AND (SELECT COUNT(*) FROM #d WHERE rolDestinatario = 'DOCENTE' AND idUsuario = @userT) = 2, 1, 0);
    EXEC #sig_expect 'S11_RECIPIENTS', @ok;
    TRUNCATE TABLE #d;
    INSERT INTO #d EXEC dbo.usp_consultar_destinatarios_solicitud_ingreso_grupo @idSolicitud = @sC, @idCorrelacion = @corr, @idUsuarioEjecutor = @uA;
    INSERT INTO #d EXEC dbo.usp_consultar_destinatarios_solicitud_ingreso_grupo @idSolicitud = @sC, @idCorrelacion = @corr, @idUsuarioEjecutor = @userOtroDocente;
    SET @ok = IIF((SELECT COUNT(*) FROM #d) = 0, 1, 0);
    EXEC #sig_expect 'S11_RECIPIENTS_SCOPED', @ok;
    PRINT 'TEST_PASS:S-11';

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

-- ------------------------------------------------------------ S-12 consultas con ejecutor nulo: THROW
DECLARE @lanzo INT = 0;
BEGIN TRY
    EXEC dbo.usp_consultar_solicitudes_ingreso_estudiante @codigoEstado = NULL, @numeroPagina = 1, @tamanoPagina = 10, @idCorrelacion = @corr, @idUsuarioEjecutor = NULL;
END TRY
BEGIN CATCH
    SET @lanzo += 1;
END CATCH;
BEGIN TRY
    EXEC dbo.usp_consultar_solicitudes_ingreso_grupo_docente @idGrupo = @group, @codigoEstado = NULL, @numeroPagina = 1, @tamanoPagina = 10, @idCorrelacion = @corr, @idUsuarioEjecutor = NULL;
END TRY
BEGIN CATCH
    SET @lanzo += 1;
END CATCH;
BEGIN TRY
    EXEC dbo.usp_consultar_destinatarios_solicitud_ingreso_grupo @idSolicitud = @sA, @idCorrelacion = @corr, @idUsuarioEjecutor = NULL;
END TRY
BEGIN CATCH
    SET @lanzo += 1;
END CATCH;
SET @ok = IIF(@lanzo = 3, 1, 0);
EXEC #sig_expect 'S12_NULL_EXECUTOR_THROWS', @ok;
PRINT 'TEST_PASS:S-12';

DROP TABLE #r;
DROP TABLE #rx;
DROP TABLE #doc;
DROP TABLE #est;
DROP TABLE #d;
PRINT 'TEST_PASS:TEST_SOLICITUD_INGRESO_GRUPO';
GO
