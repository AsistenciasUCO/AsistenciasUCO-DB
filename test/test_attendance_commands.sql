USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- Contrato canonico del batch: estados publicos AN / SJC / EX, idUsuarioEjecutor = Usuario.id
-- del docente titular (requerido semanticamente), atomicidad del lote y RazonCausa como catalogo cerrado.
DECLARE @group UNIQUEIDENTIFIER, @student UNIQUEIDENTIFIER, @enrollment UNIQUEIDENTIFIER, @owner UNIQUEIDENTIFIER, @ownerRole UNIQUEIDENTIFIER;
SELECT TOP 1 @group = eg.idGrupo, @student = eg.idEstudiante, @enrollment = eg.id,
             @owner = di.idUsuario, @ownerRole = di.id
FROM dbo.uv_estudiante_grupo eg
JOIN dbo.uv_grupo g ON g.id = eg.idGrupo
JOIN dbo.uv_docente_identidad di ON di.id = g.idDocente
WHERE eg.codigoEstadoEstudiante = 'A' AND g.grupoEstaHablitado = 1
  AND di.estaActivoUsuario = 1 AND di.id <> di.idUsuario
ORDER BY eg.id;
DECLARE @student2 UNIQUEIDENTIFIER, @enrollment2 UNIQUEIDENTIFIER;
SELECT TOP 1 @student2 = eg.idEstudiante, @enrollment2 = eg.id
FROM dbo.uv_estudiante_grupo eg
WHERE eg.idGrupo = @group
  AND eg.codigoEstadoEstudiante = 'A'
  AND eg.idEstudiante <> @student
ORDER BY eg.id;
DECLARE @nonOwner UNIQUEIDENTIFIER =
    (SELECT TOP 1 idUsuario FROM dbo.uv_docente_identidad
     WHERE idUsuario <> @owner AND id <> idUsuario AND estaActivoUsuario = 1 ORDER BY id);
DECLARE @studentUser UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_estudiante_identidad WHERE id = @student);
DECLARE @reason UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.RazonCausa WHERE codigo = 'AN');
IF @group IS NULL OR @student IS NULL OR @student2 IS NULL OR @enrollment IS NULL OR @enrollment2 IS NULL OR @owner IS NULL OR @studentUser IS NULL OR @reason IS NULL
    THROW 51800, 'TEST FAILED: ATTENDANCE fixture missing (grupo con docente activo con Usuario.id <> Docente.id, razon AN).', 1;

DECLARE @sessionBulk UNIQUEIDENTIFIER = NEWID(), @sessionAuto UNIQUEIDENTIFIER = NEWID(), @sessionSingle UNIQUEIDENTIFIER = NEWID();
DECLARE @sessionSjc UNIQUEIDENTIFIER = NEWID(), @sessionEx UNIQUEIDENTIFIER = NEWID(), @sessionInvalid UNIQUEIDENTIFIER = NEWID();
DECLARE @sessionNoExec UNIQUEIDENTIFIER = NEWID(), @sessionNonOwner UNIQUEIDENTIFIER = NEWID(), @sessionAtomic UNIQUEIDENTIFIER = NEWID();
DECLARE @sessionPartial UNIQUEIDENTIFIER = NEWID(), @sessionOmitted UNIQUEIDENTIFIER = NEWID(), @sessionIdempotent UNIQUEIDENTIFIER = NEWID(), @sessionUpdate UNIQUEIDENTIFIER = NEWID();
DECLARE @codeAuto NVARCHAR(50) = LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8);
DECLARE @firstNumber INT = 1 + (SELECT ISNULL(MAX(numero), 0) FROM dbo.Sesion WHERE grupo = @group);
DECLARE @corr UNIQUEIDENTIFIER, @userMsg NVARCHAR(4000), @techMsg NVARCHAR(4000), @failure NVARCHAR(2048);
DECLARE @tranBefore INT = 0, @abcBefore INT, @rcBefore INT;
CREATE TABLE #attendanceResult (
    idCorrelacion UNIQUEIDENTIFIER NULL,
    mensajeUsuarioResultado NVARCHAR(MAX) NULL,
    mensajeTecnicoResultado NVARCHAR(MAX) NULL,
    estadoResultado INT NOT NULL
);

BEGIN TRANSACTION;
BEGIN TRY
    SET @tranBefore = @@TRANCOUNT;
    SELECT @abcBefore = COUNT(*) FROM dbo.RazonCausa WHERE codigo = 'ABC';
    SELECT @rcBefore = COUNT(*) FROM dbo.RazonCausa;

    IF @nonOwner IS NULL
    BEGIN
        DECLARE @tipoIdDocenteTemporal UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = 'CC');
        DECLARE @usuarioDocenteTemporal UNIQUEIDENTIFIER = NEWID();
        DECLARE @docenteTemporal UNIQUEIDENTIFIER = NEWID();
        IF @tipoIdDocenteTemporal IS NULL
            THROW 51816, 'TEST FAILED: ATTENDANCE fixture missing tipo identificacion CC for non-owner docente.', 1;

        INSERT INTO dbo.Usuario (
            id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido,
            primerNombre, segundoNombre, correo, correoConfirmado, estado, password
        )
        VALUES (
            @usuarioDocenteTemporal, @tipoIdDocenteTemporal, 914000001, N'Docente', N'NoOwner',
            N'Attendance', N'QA', N'attendance.noowner.qa@test.local', 1, 1, N'HashBackend_QaAttendance1234567890'
        );

        INSERT INTO dbo.Docente (id, usuario)
        VALUES (@docenteTemporal, @usuarioDocenteTemporal);

        SET @nonOwner = @usuarioDocenteTemporal;
    END

    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
    VALUES
        (@sessionBulk,     N'QA Bulk AN',    @firstNumber,     LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group, DATEADD(HOUR, 1, GETDATE()),  DATEADD(HOUR, 2, GETDATE())),
        (@sessionAuto,     N'QA Auto',       @firstNumber + 1, @codeAuto,                                                1, @group, DATEADD(HOUR, 3, GETDATE()),  DATEADD(HOUR, 4, GETDATE())),
        (@sessionSingle,   N'QA Single',     @firstNumber + 2, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group, DATEADD(HOUR, 5, GETDATE()),  DATEADD(HOUR, 6, GETDATE())),
        (@sessionSjc,      N'QA Bulk SJC',   @firstNumber + 3, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group, DATEADD(HOUR, 7, GETDATE()),  DATEADD(HOUR, 8, GETDATE())),
        (@sessionEx,       N'QA Bulk EX',    @firstNumber + 4, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group, DATEADD(HOUR, 9, GETDATE()),  DATEADD(HOUR, 10, GETDATE())),
        (@sessionInvalid,  N'QA Invalid',    @firstNumber + 5, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group, DATEADD(HOUR, 11, GETDATE()), DATEADD(HOUR, 12, GETDATE())),
        (@sessionNoExec,   N'QA NoExec',     @firstNumber + 6, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group, DATEADD(HOUR, 13, GETDATE()), DATEADD(HOUR, 14, GETDATE())),
        (@sessionNonOwner, N'QA NonOwner',   @firstNumber + 7, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group, DATEADD(HOUR, 15, GETDATE()), DATEADD(HOUR, 16, GETDATE())),
        (@sessionAtomic,   N'QA Atomic',     @firstNumber + 8, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group, DATEADD(HOUR, 17, GETDATE()), DATEADD(HOUR, 18, GETDATE())),
        (@sessionPartial,  N'QA Partial',    @firstNumber + 9, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group, DATEADD(HOUR, 19, GETDATE()), DATEADD(HOUR, 20, GETDATE())),
        (@sessionOmitted,  N'QA Omitted',    @firstNumber + 10, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group, DATEADD(HOUR, 21, GETDATE()), DATEADD(HOUR, 22, GETDATE())),
        (@sessionIdempotent, N'QA Idempotent', @firstNumber + 11, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group, DATEADD(HOUR, 23, GETDATE()), DATEADD(HOUR, 24, GETDATE())),
        (@sessionUpdate,   N'QA Update',     @firstNumber + 12, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group, DATEADD(HOUR, 25, GETDATE()), DATEADD(HOUR, 26, GETDATE()));

    -- A. AN SUCCESS (owner = Usuario.id del docente titular)
    DECLARE @json NVARCHAR(MAX) = CONCAT(N'[{"idEstudiante":"', CONVERT(NVARCHAR(36), @student), N'","estado":"AN"}]');
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'BloqueAsistenciasSesion',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #attendanceResult
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sessionBulk, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @owner;
    IF (SELECT COUNT(*) FROM #attendanceResult WHERE idCorrelacion = @corr AND estadoResultado = 1
        AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
        THROW 51801, 'TEST FAILED: ATTENDANCE_BULK_SUCCESS wrong canonical result.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_asistencia a JOIN dbo.uv_detalle_asistencia d ON d.idAsistencia = a.id
        WHERE a.idSesion = @sessionBulk AND a.idEstudianteGrupo = @enrollment AND d.asistio = 1 AND d.idRazonCausa = @reason AND d.codigoRazonCausa = 'AN')
        THROW 51802, 'TEST FAILED: ATTENDANCE_BULK_SUCCESS did not persist visible attendance (AN, asistio=1).', 1;

    -- B. SJC SUCCESS (con normalizacion TRIM/UPPER del estado)
    TRUNCATE TABLE #attendanceResult;
    SET @json = CONCAT(N'[{"idEstudiante":"', CONVERT(NVARCHAR(36), @student), N'","estado":" sjc "}]');
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'BloqueAsistenciasSesion',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #attendanceResult
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sessionSjc, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @owner;
    IF (SELECT COUNT(*) FROM #attendanceResult WHERE idCorrelacion = @corr AND estadoResultado = 1
        AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
        THROW 51830, 'TEST FAILED: ATTENDANCE_BULK_SJC wrong canonical result.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_asistencia a JOIN dbo.uv_detalle_asistencia d ON d.idAsistencia = a.id
        WHERE a.idSesion = @sessionSjc AND a.idEstudianteGrupo = @enrollment AND d.asistio = 0 AND d.codigoRazonCausa = 'SJC')
        THROW 51831, 'TEST FAILED: ATTENDANCE_BULK_SJC did not persist SJC with asistio=0.', 1;

    -- C. EX SUCCESS
    TRUNCATE TABLE #attendanceResult;
    SET @json = CONCAT(N'[{"idEstudiante":"', CONVERT(NVARCHAR(36), @student), N'","estado":"EX"}]');
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'BloqueAsistenciasSesion',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #attendanceResult
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sessionEx, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @owner;
    IF (SELECT COUNT(*) FROM #attendanceResult WHERE idCorrelacion = @corr AND estadoResultado = 1
        AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
        THROW 51832, 'TEST FAILED: ATTENDANCE_BULK_EX wrong canonical result.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_asistencia a JOIN dbo.uv_detalle_asistencia d ON d.idAsistencia = a.id
        WHERE a.idSesion = @sessionEx AND a.idEstudianteGrupo = @enrollment AND d.asistio = 0 AND d.codigoRazonCausa = 'EX')
        THROW 51833, 'TEST FAILED: ATTENDANCE_BULK_EX did not persist EX with asistio=0.', 1;

    -- C.1 Lote parcial: solo cambia el estudiante enviado; el omitido no se materializa.
    TRUNCATE TABLE #attendanceResult;
    SET @json = CONCAT(N'[{"idEstudiante":"', CONVERT(NVARCHAR(36), @student), N'","estado":"AN"}]');
    SET @corr = NEWID();
    INSERT INTO #attendanceResult
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sessionPartial, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @owner;
    IF (SELECT COUNT(*) FROM #attendanceResult WHERE idCorrelacion = @corr AND estadoResultado = 1) <> 1
        THROW 51870, 'TEST FAILED: ATTENDANCE_BULK_PARTIAL_ALLOWED wrong canonical result.', 1;
    IF (SELECT COUNT(*) FROM dbo.Asistencia WHERE sesion = @sessionPartial) <> 1
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_asistencia WHERE idSesion = @sessionPartial AND idEstudianteGrupo = @enrollment)
       OR EXISTS (SELECT 1 FROM dbo.uv_asistencia WHERE idSesion = @sessionPartial AND idEstudianteGrupo = @enrollment2)
        THROW 51871, 'TEST FAILED: ATTENDANCE_BULK_PARTIAL_ALLOWED did not persist exactly the submitted student.', 1;

    -- C.2 Omitido con fila previa: conservar estado previo, no sobrescribir ni completar automáticamente.
    TRUNCATE TABLE #attendanceResult;
    SET @json = CONCAT(N'[{"idEstudiante":"', CONVERT(NVARCHAR(36), @student2), N'","estado":"SJC"}]');
    SET @corr = NEWID();
    INSERT INTO #attendanceResult
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sessionOmitted, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @owner;
    TRUNCATE TABLE #attendanceResult;
    SET @json = CONCAT(N'[{"idEstudiante":"', CONVERT(NVARCHAR(36), @student), N'","estado":"AN"}]');
    SET @corr = NEWID();
    INSERT INTO #attendanceResult
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sessionOmitted, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @owner;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_asistencia a JOIN dbo.uv_detalle_asistencia d ON d.idAsistencia = a.id
        WHERE a.idSesion = @sessionOmitted AND a.idEstudianteGrupo = @enrollment2 AND d.codigoRazonCausa = 'SJC')
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_asistencia a JOIN dbo.uv_detalle_asistencia d ON d.idAsistencia = a.id
        WHERE a.idSesion = @sessionOmitted AND a.idEstudianteGrupo = @enrollment AND d.codigoRazonCausa = 'AN')
        THROW 51872, 'TEST FAILED: ATTENDANCE_BULK_OMITTED_STUDENT_UNCHANGED did not preserve omitted student.', 1;

    -- C.3 Idempotencia y actualización: un header y un detalle lógico por estudiante/sesión.
    TRUNCATE TABLE #attendanceResult;
    SET @json = CONCAT(N'[{"idEstudiante":"', CONVERT(NVARCHAR(36), @student), N'","estado":"AN"}]');
    SET @corr = NEWID();
    INSERT INTO #attendanceResult
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sessionIdempotent, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @owner;
    SET @corr = NEWID();
    INSERT INTO #attendanceResult
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sessionIdempotent, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @owner;
    IF (SELECT COUNT(*) FROM dbo.Asistencia WHERE sesion = @sessionIdempotent AND estudianteGrupo = @enrollment) <> 1
       OR (SELECT COUNT(*) FROM dbo.DetalleAsistencia d JOIN dbo.Asistencia a ON a.id = d.asistencia WHERE a.sesion = @sessionIdempotent AND a.estudianteGrupo = @enrollment) <> 1
        THROW 51873, 'TEST FAILED: ATTENDANCE_BULK_IDEMPOTENT_SAME_STATE duplicated rows.', 1;

    TRUNCATE TABLE #attendanceResult;
    SET @json = CONCAT(N'[{"idEstudiante":"', CONVERT(NVARCHAR(36), @student), N'","estado":"AN"}]');
    SET @corr = NEWID();
    INSERT INTO #attendanceResult
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sessionUpdate, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @owner;
    SET @json = CONCAT(N'[{"idEstudiante":"', CONVERT(NVARCHAR(36), @student), N'","estado":"SJC"}]');
    SET @corr = NEWID();
    INSERT INTO #attendanceResult
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sessionUpdate, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @owner;
    IF (SELECT COUNT(*) FROM dbo.Asistencia WHERE sesion = @sessionUpdate AND estudianteGrupo = @enrollment) <> 1
       OR (SELECT COUNT(*) FROM dbo.DetalleAsistencia d JOIN dbo.Asistencia a ON a.id = d.asistencia WHERE a.sesion = @sessionUpdate AND a.estudianteGrupo = @enrollment) <> 1
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_asistencia a JOIN dbo.uv_detalle_asistencia d ON d.idAsistencia = a.id
            WHERE a.idSesion = @sessionUpdate AND a.idEstudianteGrupo = @enrollment AND d.codigoRazonCausa = 'SJC' AND d.asistio = 0)
        THROW 51874, 'TEST FAILED: ATTENDANCE_BULK_UPDATE_EXISTING_STATE did not update final state to SJC.', 1;

    IF EXISTS (SELECT 1 FROM dbo.Asistencia GROUP BY estudianteGrupo, sesion HAVING COUNT(*) > 1)
        THROW 51875, 'TEST FAILED: ATTENDANCE_NO_DUPLICATE_HEADER found duplicate headers.', 1;
    IF EXISTS (SELECT 1 FROM dbo.DetalleAsistencia GROUP BY asistencia HAVING COUNT(*) > 1)
        THROW 51876, 'TEST FAILED: ATTENDANCE_NO_DUPLICATE_DETAIL found duplicate details.', 1;
    IF EXISTS (SELECT 1 FROM dbo.uv_asistencia WHERE idSesion = @sessionPartial AND idEstudianteGrupo = @enrollment2)
        THROW 51877, 'TEST FAILED: ATTENDANCE_READ_ONLY_PERSISTED_ROWS returned omitted student.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_detalle_asistencia WHERE codigoRazonCausa IN ('AN', 'SJC', 'EX'))
        THROW 51878, 'TEST FAILED: ATTENDANCE_READ_CANONICAL_CODE did not expose canonical code.', 1;

    -- D. Estructura JSON inválida, no arreglo, lote vacío y duplicidad dentro del request.
    TRUNCATE TABLE #attendanceResult;
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'ATT_001',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #attendanceResult
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sessionInvalid, @asistenciaJSON = N'not-json', @idCorrelacion = @corr, @idUsuarioEjecutor = @owner;
    IF (SELECT COUNT(*) FROM #attendanceResult WHERE idCorrelacion = @corr AND estadoResultado = 0
        AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
        THROW 51860, 'TEST FAILED: ATTENDANCE_BULK_INVALID_JSON wrong ATT_001 result.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Asistencia WHERE sesion = @sessionInvalid)
        THROW 51861, 'TEST FAILED: ATTENDANCE_BULK_INVALID_JSON wrote attendance.', 1;

    TRUNCATE TABLE #attendanceResult;
    SET @corr = NEWID();
    INSERT INTO #attendanceResult
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sessionInvalid, @asistenciaJSON = N'{"idEstudiante":"x","estado":"AN"}', @idCorrelacion = @corr, @idUsuarioEjecutor = @owner;
    IF (SELECT COUNT(*) FROM #attendanceResult WHERE idCorrelacion = @corr AND estadoResultado = 0
        AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
        THROW 51862, 'TEST FAILED: ATTENDANCE_BULK_NOT_ARRAY wrong ATT_001 result.', 1;

    TRUNCATE TABLE #attendanceResult;
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'ATT_002',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #attendanceResult
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sessionInvalid, @asistenciaJSON = N'[]', @idCorrelacion = @corr, @idUsuarioEjecutor = @owner;
    IF (SELECT COUNT(*) FROM #attendanceResult WHERE idCorrelacion = @corr AND estadoResultado = 0
        AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
        THROW 51863, 'TEST FAILED: ATTENDANCE_BULK_EMPTY wrong ATT_002 result.', 1;

    TRUNCATE TABLE #attendanceResult;
    SET @json = CONCAT(N'[{"idEstudiante":"', CONVERT(NVARCHAR(36), @student), N'","estado":"AN"},{"idEstudiante":"',
                       CONVERT(NVARCHAR(36), @student), N'","estado":"SJC"}]');
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'ATT_003', @p_param1 = @student,
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #attendanceResult
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sessionInvalid, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @owner;
    IF (SELECT COUNT(*) FROM #attendanceResult WHERE idCorrelacion = @corr AND estadoResultado = 0
        AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
        THROW 51864, 'TEST FAILED: ATTENDANCE_BULK_DUPLICATE_STUDENT wrong ATT_003 result.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Asistencia WHERE sesion = @sessionInvalid)
        THROW 51865, 'TEST FAILED: ATTENDANCE_BULK_DUPLICATE_STUDENT wrote attendance.', 1;

    TRUNCATE TABLE #attendanceResult;
    SET @json = CONCAT(N'[{"idEstudiante":"', CONVERT(NVARCHAR(36), @student), N'"}]');
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'ATT_001',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #attendanceResult
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sessionInvalid, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @owner;
    IF (SELECT COUNT(*) FROM #attendanceResult WHERE idCorrelacion = @corr AND estadoResultado = 0
        AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
        THROW 51866, 'TEST FAILED: ATTENDANCE_BULK_MISSING_STATE wrong ATT_001 result.', 1;

    -- E. Estados invalidos en el batch publico: ABC, alias historicos A/F/T/J, vacio y ausente.
    --      Ninguno se interpreta ni crea RazonCausa; el lote no escribe nada (incluido un primer registro AN valido).
    CREATE TABLE #invalidStates (orden INT IDENTITY(1,1), etiqueta VARCHAR(20), estadoJson NVARCHAR(100), parametroEsperado NVARCHAR(50));
    INSERT #invalidStates (etiqueta, estadoJson, parametroEsperado) VALUES
        ('ABC',        N',"estado":"ABC"',   N'ABC'),
        ('A legacy',   N',"estado":"A"',     N'A'),
        ('F legacy',   N',"estado":"F"',     N'F'),
        ('T legacy',   N',"estado":"T"',     N'T'),
        ('J legacy',   N',"estado":"J"',     N'J'),
        ('vacio',      N',"estado":""',      N'(vacio)'),
        ('espacios',   N',"estado":"   "',   N'(vacio)');
    DECLARE @iv INT = 1, @ivMax INT = (SELECT MAX(orden) FROM #invalidStates), @ivLabel VARCHAR(20), @ivJson NVARCHAR(100), @ivParam NVARCHAR(50);
    WHILE @iv <= @ivMax
    BEGIN
        SELECT @ivLabel = etiqueta, @ivJson = estadoJson, @ivParam = parametroEsperado FROM #invalidStates WHERE orden = @iv;
        TRUNCATE TABLE #attendanceResult;
        SET @json = CONCAT(N'[{"idEstudiante":"', CONVERT(NVARCHAR(36), @student), N'","estado":"AN"},{"idEstudiante":"',
                           CONVERT(NVARCHAR(36), @student), N'"', @ivJson, N'}]');
        SET @corr = NEWID();
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'RC_001', @p_param1 = @ivParam,
            @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
        INSERT INTO #attendanceResult
        EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sessionInvalid, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @owner;
        IF (SELECT COUNT(*) FROM #attendanceResult WHERE idCorrelacion = @corr AND estadoResultado = 0
            AND mensajeUsuarioResultado = @userMsg
            AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
        BEGIN
            SET @failure = CONCAT('TEST FAILED: ATTENDANCE_BULK_INVALID_STATE wrong RC_001 result for ', @ivLabel, '.');
            THROW 51834, @failure, 1;
        END
        IF EXISTS (SELECT 1 FROM dbo.Asistencia WHERE sesion = @sessionInvalid)
        BEGIN
            SET @failure = CONCAT('TEST FAILED: ATTENDANCE_BULK_INVALID_STATE wrote attendance for ', @ivLabel, '.');
            THROW 51835, @failure, 1;
        END
        SET @iv += 1;
    END
    DROP TABLE #invalidStates;
    IF (SELECT COUNT(*) FROM dbo.RazonCausa WHERE codigo = 'ABC') <> @abcBefore OR (SELECT COUNT(*) FROM dbo.RazonCausa) <> @rcBefore
        THROW 51836, 'TEST FAILED: ATTENDANCE_BULK_INVALID_STATE creo filas en dbo.RazonCausa.', 1;

    -- F. idUsuarioEjecutor NULL: no salta RBAC/titularidad, resultado canonico, sin escritura
    TRUNCATE TABLE #attendanceResult;
    SET @json = CONCAT(N'[{"idEstudiante":"', CONVERT(NVARCHAR(36), @student), N'","estado":"AN"}]');
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #attendanceResult
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sessionNoExec, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = NULL;
    IF (SELECT COUNT(*) FROM #attendanceResult WHERE idCorrelacion = @corr AND estadoResultado = 0
        AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
        THROW 51837, 'TEST FAILED: ATTENDANCE_BULK_EXECUTOR_REQUIRED wrong canonical result.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Asistencia WHERE sesion = @sessionNoExec)
        THROW 51838, 'TEST FAILED: ATTENDANCE_BULK_EXECUTOR_REQUIRED wrote attendance.', 1;
    -- Omitir el parametro (default de firma) tampoco es un bypass.
    TRUNCATE TABLE #attendanceResult;
    SET @corr = NEWID();
    INSERT INTO #attendanceResult
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sessionNoExec, @asistenciaJSON = @json, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #attendanceResult WHERE idCorrelacion = @corr AND estadoResultado = 0) <> 1
        OR EXISTS (SELECT 1 FROM dbo.Asistencia WHERE sesion = @sessionNoExec)
        THROW 51839, 'TEST FAILED: ATTENDANCE_BULK_EXECUTOR_REQUIRED parametro omitido salto la seguridad.', 1;

    -- H. NON OWNER: otro docente valido (Usuario.id) no puede registrar; el Docente.id titular tampoco es Usuario.id valido
    DECLARE @expectedUser NVARCHAR(4000), @expectedTech NVARCHAR(4000), @expectedState BIT;
    TRUNCATE TABLE #attendanceResult;
    SET @corr = NEWID();
    EXEC dbo.usp_validar_titularidad_jerarquica_interno @idUsuario = @nonOwner, @idEntidadPadre = @sessionNonOwner, @tipoEntidadPadre = 'SESION',
        @idCorrelacion = @corr, @mensajeUsuarioResultado = @expectedUser OUTPUT, @mensajeTecnicoResultado = @expectedTech OUTPUT, @estadoResultado = @expectedState OUTPUT;
    IF @expectedState <> 0 THROW 51840, 'TEST FAILED: ATTENDANCE_BULK_NON_OWNER helper acepto a un no titular.', 1;
    INSERT INTO #attendanceResult
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sessionNonOwner, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @nonOwner;
    IF (SELECT COUNT(*) FROM #attendanceResult WHERE idCorrelacion = @corr AND estadoResultado = 0
        AND mensajeUsuarioResultado = @expectedUser AND mensajeTecnicoResultado = @expectedTech) <> 1
        THROW 51841, 'TEST FAILED: ATTENDANCE_BULK_NON_OWNER wrong canonical result.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Asistencia WHERE sesion = @sessionNonOwner)
        THROW 51842, 'TEST FAILED: ATTENDANCE_BULK_NON_OWNER wrote attendance.', 1;
    TRUNCATE TABLE #attendanceResult;
    SET @corr = NEWID();
    INSERT INTO #attendanceResult
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sessionNonOwner, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @ownerRole;
    IF (SELECT COUNT(*) FROM #attendanceResult WHERE idCorrelacion = @corr AND estadoResultado = 0) <> 1
        OR EXISTS (SELECT 1 FROM dbo.Asistencia WHERE sesion = @sessionNonOwner)
        THROW 51843, 'TEST FAILED: ATTENDANCE_BULK_NON_OWNER Docente.id fue aceptado como Usuario.id.', 1;

    -- I. Sesion inexistente (con ejecutor valido)
    TRUNCATE TABLE #attendanceResult;
    DECLARE @missingSession UNIQUEIDENTIFIER = NEWID();
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SES_001', @p_param1 = @missingSession,
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #attendanceResult
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @missingSession, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @owner;
    IF (SELECT COUNT(*) FROM #attendanceResult WHERE idCorrelacion = @corr AND estadoResultado = 0
        AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
        THROW 51803, 'TEST FAILED: ATTENDANCE_BULK_INVALID wrong canonical result.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Asistencia WHERE sesion = @missingSession)
        THROW 51804, 'TEST FAILED: ATTENDANCE_BULK_INVALID wrote attendance.', 1;

    -- J. Estudiante que no pertenece al grupo de la sesion.
    --    El SP hace ROLLBACK a savepoint tras escribir parcialmente: SQL Server prohibe ROLLBACK dentro de
    --    INSERT ... EXEC, asi que el result set lo verifica test_summary.ps1 (TEST_RESULT_BEGIN/END) y el
    --    estado de la DB se verifica aqui.
    DECLARE @strangerStudent UNIQUEIDENTIFIER = NEWID();
    DECLARE @jsonStranger NVARCHAR(MAX) = CONCAT(N'[{"idEstudiante":"', CONVERT(NVARCHAR(36), @strangerStudent), N'","estado":"AN"}]');
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'EST_004', @p_param1 = @strangerStudent, @p_param2 = @sessionNoExec,
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    PRINT CONCAT('TEST_EXPECTED_USER:ATTENDANCE_BULK_STUDENT_NOT_IN_GROUP|', @userMsg);
    PRINT CONCAT('TEST_EXPECTED_TECH:ATTENDANCE_BULK_STUDENT_NOT_IN_GROUP|', @techMsg, ' Correlacion: ', @corr);
    PRINT 'TEST_RESULT_BEGIN:ATTENDANCE_BULK_STUDENT_NOT_IN_GROUP';
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sessionNoExec, @asistenciaJSON = @jsonStranger, @idCorrelacion = @corr, @idUsuarioEjecutor = @owner;
    PRINT 'TEST_RESULT_END:ATTENDANCE_BULK_STUDENT_NOT_IN_GROUP';
    IF EXISTS (SELECT 1 FROM dbo.Asistencia WHERE sesion = @sessionNoExec)
        THROW 51845, 'TEST FAILED: ATTENDANCE_BULK_STUDENT_NOT_IN_GROUP wrote attendance.', 1;
    IF @@TRANCOUNT <> @tranBefore
        THROW 51850, 'TEST FAILED: ATTENDANCE_BULK_STUDENT_NOT_IN_GROUP altero la transaccion externa del test.', 1;
    PRINT 'TEST_STATE_PASS:ATTENDANCE_BULK_STUDENT_NOT_IN_GROUP';

    -- K. ATOMICIDAD: registro 1 valido (se escribe), registro 2 estudiante ajeno -> rollback completo del lote
    DECLARE @jsonAtomic NVARCHAR(MAX) = CONCAT(N'[{"idEstudiante":"', CONVERT(NVARCHAR(36), @student), N'","estado":"AN"},',
                                                N'{"idEstudiante":"', CONVERT(NVARCHAR(36), @strangerStudent), N'","estado":"AN"}]');
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'EST_004', @p_param1 = @strangerStudent, @p_param2 = @sessionAtomic,
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    PRINT CONCAT('TEST_EXPECTED_USER:ATTENDANCE_BULK_ATOMIC|', @userMsg);
    PRINT CONCAT('TEST_EXPECTED_TECH:ATTENDANCE_BULK_ATOMIC|', @techMsg, ' Correlacion: ', @corr);
    PRINT 'TEST_RESULT_BEGIN:ATTENDANCE_BULK_ATOMIC';
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sessionAtomic, @asistenciaJSON = @jsonAtomic, @idCorrelacion = @corr, @idUsuarioEjecutor = @owner;
    PRINT 'TEST_RESULT_END:ATTENDANCE_BULK_ATOMIC';
    IF EXISTS (SELECT 1 FROM dbo.Asistencia WHERE sesion = @sessionAtomic)
        OR EXISTS (SELECT 1 FROM dbo.uv_asistencia a JOIN dbo.uv_detalle_asistencia d ON d.idAsistencia = a.id WHERE a.idSesion = @sessionAtomic)
        THROW 51847, 'TEST FAILED: ATTENDANCE_BULK_ATOMIC el primer registro quedo persistido (sin rollback del lote).', 1;
    IF @@TRANCOUNT <> @tranBefore
        THROW 51848, 'TEST FAILED: ATTENDANCE_BULK_ATOMIC altero la transaccion externa del test.', 1;
    PRINT 'TEST_STATE_PASS:ATTENDANCE_BULK_ATOMIC';

    -- L. Helper interno compartido: RazonCausa es catalogo cerrado y no acepta aliases legacy A/F.
    DECLARE @helperUser NVARCHAR(4000), @helperTech NVARCHAR(4000), @helperState BIT, @rcCountBefore INT;
    SELECT @rcCountBefore = COUNT(*) FROM dbo.RazonCausa;
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'RC_001', @p_param1 = 'ZZZ',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    EXEC dbo.usp_sincronizar_asistencia_estudiante_interno
        @idEstudiante = @student, @idSesion = @sessionInvalid, @codigoEstado = N'ZZZ', @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @helperUser OUTPUT, @mensajeTecnicoResultado = @helperTech OUTPUT, @estadoResultado = @helperState OUTPUT;
    IF @helperState <> 0 OR @helperUser <> @userMsg OR @helperTech <> CONCAT(@techMsg, ' Correlacion: ', @corr)
        THROW 51851, 'TEST FAILED: ATTENDANCE_HELPER_CLOSED_CATALOG codigo desconocido no devolvio RC_001.', 1;
    IF (SELECT COUNT(*) FROM dbo.RazonCausa) <> @rcCountBefore OR EXISTS (SELECT 1 FROM dbo.RazonCausa WHERE codigo = 'ZZZ')
        THROW 51852, 'TEST FAILED: ATTENDANCE_HELPER_CLOSED_CATALOG creo una RazonCausa dinamica.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Asistencia WHERE sesion = @sessionInvalid)
        THROW 51853, 'TEST FAILED: ATTENDANCE_HELPER_CLOSED_CATALOG escribio asistencia con codigo desconocido.', 1;
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'RC_001', @p_param1 = 'F',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    EXEC dbo.usp_sincronizar_asistencia_estudiante_interno
        @idEstudiante = @student, @idSesion = @sessionInvalid, @codigoEstado = N'F', @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @helperUser OUTPUT, @mensajeTecnicoResultado = @helperTech OUTPUT, @estadoResultado = @helperState OUTPUT;
    IF @helperState <> 0 OR @helperUser <> @userMsg OR @helperTech <> CONCAT(@techMsg, ' Correlacion: ', @corr)
        THROW 51854, 'TEST FAILED: ATTENDANCE_NO_LEGACY_PUBLIC_STATE alias legacy F no devolvio RC_001.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Asistencia WHERE sesion = @sessionInvalid)
        THROW 51855, 'TEST FAILED: ATTENDANCE_NO_LEGACY_PUBLIC_STATE escribio asistencia con alias legacy F.', 1;
    IF (SELECT COUNT(*) FROM dbo.RazonCausa) <> @rcCountBefore
        THROW 51856, 'TEST FAILED: ATTENDANCE_HELPER_CLOSED_CATALOG altero dbo.RazonCausa.', 1;

    -- Comandos individuales / autonomo (contrato sin cambios)
    TRUNCATE TABLE #attendanceResult;
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'AsistenciaEstudianteAutonomo',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #attendanceResult
    EXEC dbo.usp_registrar_asistencia_estudiante_autonomo
        @idEstudiante = @student, @idSesion = @sessionAuto, @codigoVerificacion = @codeAuto,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @studentUser;
    IF (SELECT COUNT(*) FROM #attendanceResult WHERE idCorrelacion = @corr AND estadoResultado = 1
        AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
        THROW 51805, 'TEST FAILED: ATTENDANCE_AUTO_SUCCESS wrong canonical result.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_asistencia a JOIN dbo.uv_detalle_asistencia d ON d.idAsistencia = a.id
        WHERE a.idSesion = @sessionAuto AND a.idEstudianteGrupo = @enrollment AND d.asistio = 1 AND d.idRazonCausa = @reason)
        THROW 51806, 'TEST FAILED: ATTENDANCE_AUTO_SUCCESS did not persist visible attendance.', 1;

    TRUNCATE TABLE #attendanceResult;
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'VAL_007', @p_param1 = 'codigoVerificacion',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #attendanceResult
    EXEC dbo.usp_registrar_asistencia_estudiante_autonomo
        @idEstudiante = @student, @idSesion = @sessionSingle, @codigoVerificacion = N'BAD',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @studentUser;
    IF (SELECT COUNT(*) FROM #attendanceResult WHERE idCorrelacion = @corr AND estadoResultado = 0
        AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
        THROW 51807, 'TEST FAILED: ATTENDANCE_AUTO_INVALID wrong canonical result.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Asistencia WHERE sesion = @sessionSingle)
        THROW 51808, 'TEST FAILED: ATTENDANCE_AUTO_INVALID wrote attendance.', 1;

    TRUNCATE TABLE #attendanceResult;
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'AsistenciaEstudiante',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #attendanceResult
    EXEC dbo.usp_registrar_asistencia_estudiante
        @idEstudianteGrupo = @enrollment, @idGrupoSesion = @sessionSingle, @idEstadoAsistencia = @reason,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @studentUser;
    IF (SELECT COUNT(*) FROM #attendanceResult WHERE idCorrelacion = @corr AND estadoResultado = 1
        AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
        THROW 51809, 'TEST FAILED: ATTENDANCE_SINGLE_SUCCESS wrong canonical result.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_asistencia a JOIN dbo.uv_detalle_asistencia d ON d.idAsistencia = a.id
        WHERE a.idSesion = @sessionSingle AND a.idEstudianteGrupo = @enrollment AND d.asistio = 1 AND d.idRazonCausa = @reason)
        THROW 51810, 'TEST FAILED: ATTENDANCE_SINGLE_SUCCESS did not persist visible attendance.', 1;

    TRUNCATE TABLE #attendanceResult;
    DECLARE @missingEnrollment UNIQUEIDENTIFIER = NEWID();
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_001', @p_param1 = 'EstudianteGrupo',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #attendanceResult
    EXEC dbo.usp_registrar_asistencia_estudiante
        @idEstudianteGrupo = @missingEnrollment, @idGrupoSesion = @sessionSingle,
        @idEstadoAsistencia = @reason, @idCorrelacion = @corr, @idUsuarioEjecutor = @studentUser;
    IF (SELECT COUNT(*) FROM #attendanceResult WHERE idCorrelacion = @corr AND estadoResultado = 0
        AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
        THROW 51811, 'TEST FAILED: ATTENDANCE_SINGLE_INVALID wrong canonical result.', 1;
    IF (SELECT COUNT(*) FROM dbo.Asistencia WHERE sesion = @sessionSingle) <> 1
        THROW 51812, 'TEST FAILED: ATTENDANCE_SINGLE_INVALID changed existing attendance.', 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
ROLLBACK TRANSACTION;
IF EXISTS (SELECT 1 FROM dbo.Sesion WHERE id IN (@sessionBulk, @sessionAuto, @sessionSingle, @sessionSjc, @sessionEx, @sessionInvalid, @sessionNoExec, @sessionNonOwner, @sessionAtomic, @sessionPartial, @sessionOmitted, @sessionIdempotent, @sessionUpdate))
    THROW 51813, 'TEST FAILED: ATTENDANCE leaked sessions.', 1;
IF EXISTS (SELECT 1 FROM dbo.Asistencia WHERE sesion IN (@sessionBulk, @sessionAuto, @sessionSingle, @sessionSjc, @sessionEx, @sessionInvalid, @sessionNoExec, @sessionNonOwner, @sessionAtomic, @sessionPartial, @sessionOmitted, @sessionIdempotent, @sessionUpdate))
    THROW 51814, 'TEST FAILED: ATTENDANCE leaked rows.', 1;
IF (SELECT COUNT(*) FROM dbo.RazonCausa WHERE codigo = 'ABC') <> 0
    THROW 51849, 'TEST FAILED: ATTENDANCE leaked RazonCausa ABC.', 1;
IF @@TRANCOUNT <> 0 THROW 51815, 'TEST FAILED: ATTENDANCE left transaction open.', 1;
PRINT 'TEST_PASS:ATTENDANCE_BULK_SUCCESS';
PRINT 'TEST_PASS:ATTENDANCE_BULK_SJC';
PRINT 'TEST_PASS:ATTENDANCE_BULK_EX';
PRINT 'TEST_PASS:ATTENDANCE_BULK_PARTIAL_ALLOWED';
PRINT 'TEST_PASS:ATTENDANCE_BULK_OMITTED_STUDENT_UNCHANGED';
PRINT 'TEST_PASS:ATTENDANCE_BULK_IDEMPOTENT_SAME_STATE';
PRINT 'TEST_PASS:ATTENDANCE_BULK_UPDATE_EXISTING_STATE';
PRINT 'TEST_PASS:ATTENDANCE_NO_DUPLICATE_HEADER';
PRINT 'TEST_PASS:ATTENDANCE_NO_DUPLICATE_DETAIL';
PRINT 'TEST_PASS:ATTENDANCE_STATE_AN_CONSISTENCY';
PRINT 'TEST_PASS:ATTENDANCE_STATE_SJC_CONSISTENCY';
PRINT 'TEST_PASS:ATTENDANCE_STATE_EX_CONSISTENCY';
PRINT 'TEST_PASS:ATTENDANCE_READ_ONLY_PERSISTED_ROWS';
PRINT 'TEST_PASS:ATTENDANCE_READ_CANONICAL_CODE';
PRINT 'TEST_PASS:ATTENDANCE_BULK_INVALID_JSON';
PRINT 'TEST_PASS:ATTENDANCE_BULK_NOT_ARRAY';
PRINT 'TEST_PASS:ATTENDANCE_BULK_EMPTY';
PRINT 'TEST_PASS:ATTENDANCE_BULK_DUPLICATE_STUDENT';
PRINT 'TEST_PASS:ATTENDANCE_BULK_MISSING_STATE';
PRINT 'TEST_PASS:ATTENDANCE_BULK_INVALID';
PRINT 'TEST_PASS:ATTENDANCE_BULK_INVALID_STATE';
PRINT 'TEST_PASS:ATTENDANCE_BULK_EXECUTOR_REQUIRED';
PRINT 'TEST_PASS:ATTENDANCE_BULK_NON_OWNER';
PRINT 'TEST_PASS:ATTENDANCE_HELPER_CLOSED_CATALOG';
PRINT 'TEST_PASS:ATTENDANCE_NO_LEGACY_PUBLIC_STATE';
PRINT 'TEST_PASS:ATTENDANCE_AUTO_SUCCESS';
PRINT 'TEST_PASS:ATTENDANCE_AUTO_INVALID';
PRINT 'TEST_PASS:ATTENDANCE_SINGLE_SUCCESS';
PRINT 'TEST_PASS:ATTENDANCE_SINGLE_INVALID';
-- ATTENDANCE_BULK_STUDENT_NOT_IN_GROUP y ATTENDANCE_BULK_ATOMIC: TEST_PASS lo emite test_summary.ps1 (result set + estado).
PRINT 'TEST END: test_attendance_commands';
GO
