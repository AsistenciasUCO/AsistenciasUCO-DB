USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- SES-01: cierre estricto de la ventana de registro ordinario de asistencia.
-- Regla: fechaHoraInicio <= SYSUTCDATETIME() < fechaHoraFin con procedencia UTC confirmada. Fuera de ella:
-- SES_007 (no iniciada), SES_008 (cerrada) o SES_009 (procedencia INDETERMINADA), sin escrituras y sin tolerancia.
-- Los rechazos ocurren dentro de la transaccion del SP (ROLLBACK a savepoint, prohibido dentro de INSERT ... EXEC):
-- su resultset lo verifica test_summary.ps1 (TEST_RESULT_BEGIN/END) y el estado de la DB se verifica aqui.
DECLARE @group UNIQUEIDENTIFIER, @student UNIQUEIDENTIFIER, @enrollment UNIQUEIDENTIFIER, @owner UNIQUEIDENTIFIER;
SELECT TOP 1 @group = eg.idGrupo, @student = eg.idEstudiante, @enrollment = eg.id, @owner = di.idUsuario
FROM dbo.uv_estudiante_grupo eg
JOIN dbo.uv_grupo g ON g.id = eg.idGrupo
JOIN dbo.uv_docente_identidad di ON di.id = g.idDocente
WHERE eg.codigoEstadoEstudiante = 'A' AND g.grupoEstaHablitado = 1 AND di.estaActivoUsuario = 1
ORDER BY eg.id;
DECLARE @student2 UNIQUEIDENTIFIER = (
    SELECT TOP 1 eg.idEstudiante FROM dbo.uv_estudiante_grupo eg
    WHERE eg.idGrupo = @group AND eg.codigoEstadoEstudiante = 'A' AND eg.idEstudiante <> @student
    ORDER BY eg.id);
DECLARE @studentUser UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_estudiante_identidad WHERE id = @student);
DECLARE @existingSession UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Sesion ORDER BY id);
IF @group IS NULL OR @student IS NULL OR @student2 IS NULL OR @owner IS NULL OR @studentUser IS NULL OR @existingSession IS NULL
    THROW 53100, 'TEST FAILED: SES01 fixture missing (grupo con docente activo, dos estudiantes activos y una sesion existente).', 1;

DECLARE @sFuture UNIQUEIDENTIFIER = NEWID(), @sExactStart UNIQUEIDENTIFIER = NEWID(), @sDuring UNIQUEIDENTIFIER = NEWID();
DECLARE @sJustBeforeEnd UNIQUEIDENTIFIER = NEWID(), @sExactEnd UNIQUEIDENTIFIER = NEWID(), @sTwoHoursAfter UNIQUEIDENTIFIER = NEWID();
DECLARE @sIndeterminate UNIQUEIDENTIFIER = NEWID(), @sHistory UNIQUEIDENTIFIER = NEWID();
DECLARE @sAutoClosed UNIQUEIDENTIFIER = NEWID(), @sAutoFuture UNIQUEIDENTIFIER = NEWID(), @sAutoIndeterminate UNIQUEIDENTIFIER = NEWID();
DECLARE @codeAutoClosed NVARCHAR(50) = LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8);
DECLARE @codeAutoFuture NVARCHAR(50) = LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8);
DECLARE @codeAutoIndeterminate NVARCHAR(50) = LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8);
DECLARE @firstNumber INT = 1 + (SELECT ISNULL(MAX(numero), 0) FROM dbo.Sesion WHERE grupo = @group);
DECLARE @corr UNIQUEIDENTIFIER, @userMsg NVARCHAR(4000), @techMsg NVARCHAR(4000), @json NVARCHAR(MAX), @jsonTwo NVARCHAR(MAX);
DECLARE @tranBefore INT;
CREATE TABLE #ses01Result (
    idCorrelacion UNIQUEIDENTIFIER NULL,
    mensajeUsuarioResultado NVARCHAR(MAX) NULL,
    mensajeTecnicoResultado NVARCHAR(MAX) NULL,
    estadoResultado INT NOT NULL
);

BEGIN TRANSACTION;
BEGIN TRY
    SET @tranBefore = @@TRANCOUNT;
    SET @json = CONCAT(N'[{"idEstudiante":"', CONVERT(NVARCHAR(36), @student), N'","estado":"AN"}]');
    SET @jsonTwo = CONCAT(N'[{"idEstudiante":"', CONVERT(NVARCHAR(36), @student), N'","estado":"SJC"},{"idEstudiante":"',
                          CONVERT(NVARCHAR(36), @student2), N'","estado":"EX"}]');

    -- A. La validacion bloquea la fila de la sesion (UPDLOCK + HOLDLOCK) hasta el fin de la transaccion del llamador:
    --    el horario no cambia entre validacion y escritura y los lotes concurrentes se serializan.
    DECLARE @lockUser NVARCHAR(4000), @lockTech NVARCHAR(4000), @lockState BIT;
    SET @corr = NEWID();
    EXEC dbo.usp_validar_sesion_ventana_registro_interno
        @idSesion = @existingSession, @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @lockUser OUTPUT, @mensajeTecnicoResultado = @lockTech OUTPUT, @estadoResultado = @lockState OUTPUT;
    IF NOT EXISTS (
        SELECT 1
        FROM sys.dm_tran_locks l
        JOIN sys.partitions p ON p.hobt_id = l.resource_associated_entity_id
        WHERE l.request_session_id = @@SPID
          AND l.resource_type = 'KEY'
          AND p.object_id = OBJECT_ID('dbo.Sesion')
          AND l.request_mode IN ('U', 'RangeS-U')
    )
        THROW 53101, 'TEST FAILED: SES01_WINDOW_LOCK_HELD la validacion no retuvo el bloqueo de actualizacion sobre dbo.Sesion.', 1;
    PRINT 'TEST_PASS:SES01_WINDOW_LOCK_HELD';

    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    VALUES
        (@sFuture,        N'SES01 Futura',         @firstNumber,     LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group, DATEADD(HOUR, 1, SYSUTCDATETIME()),  DATEADD(HOUR, 2, SYSUTCDATETIME()),     N'UTC_V2'),
        (@sDuring,        N'SES01 Durante',        @firstNumber + 1, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group, DATEADD(HOUR, -1, SYSUTCDATETIME()), DATEADD(HOUR, 1, SYSUTCDATETIME()),     N'UTC_V2'),
        (@sJustBeforeEnd, N'SES01 Antes cierre',   @firstNumber + 2, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group, DATEADD(HOUR, -2, SYSUTCDATETIME()), DATEADD(SECOND, 30, SYSUTCDATETIME()),  N'UTC_V2'),
        (@sTwoHoursAfter, N'SES01 Dos horas',      @firstNumber + 3, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group, DATEADD(HOUR, -4, SYSUTCDATETIME()), DATEADD(HOUR, -2, SYSUTCDATETIME()),    N'UTC_V2'),
        (@sIndeterminate, N'SES01 Indeterminada',  @firstNumber + 4, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group, DATEADD(HOUR, -1, SYSUTCDATETIME()), DATEADD(HOUR, 1, SYSUTCDATETIME()),     NULL),
        (@sHistory,       N'SES01 Historica',      @firstNumber + 5, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group, DATEADD(HOUR, -4, SYSUTCDATETIME()), DATEADD(HOUR, -2, SYSUTCDATETIME()),    N'UTC_V2'),
        (@sAutoClosed,    N'SES01 Auto cerrada',   @firstNumber + 6, @codeAutoClosed,                                         1, @group, DATEADD(HOUR, -4, SYSUTCDATETIME()), DATEADD(HOUR, -2, SYSUTCDATETIME()),    N'UTC_V2'),
        (@sAutoFuture,    N'SES01 Auto futura',    @firstNumber + 7, @codeAutoFuture,                                         1, @group, DATEADD(HOUR, 1, SYSUTCDATETIME()),  DATEADD(HOUR, 2, SYSUTCDATETIME()),     N'UTC_V2'),
        (@sAutoIndeterminate, N'SES01 Auto indet', @firstNumber + 8, @codeAutoIndeterminate,                                  1, @group, DATEADD(HOUR, -1, SYSUTCDATETIME()), DATEADD(HOUR, 1, SYSUTCDATETIME()),     NULL);

    -- B. Antes del inicio (07:59:59 de una sesion 08:00-10:00): SES_007, sin escritura.
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SES_007', @p_param1 = @sFuture,
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    PRINT CONCAT('TEST_EXPECTED_USER:SES01_BULK_BEFORE_START|', @userMsg);
    PRINT CONCAT('TEST_EXPECTED_TECH:SES01_BULK_BEFORE_START|', @techMsg, ' Correlacion: ', @corr);
    PRINT 'TEST_RESULT_BEGIN:SES01_BULK_BEFORE_START';
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sFuture, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @owner;
    PRINT 'TEST_RESULT_END:SES01_BULK_BEFORE_START';
    IF EXISTS (SELECT 1 FROM dbo.Asistencia WHERE sesion = @sFuture) OR @@TRANCOUNT <> @tranBefore
        THROW 53102, 'TEST FAILED: SES01_BULK_BEFORE_START escribio asistencia o altero la transaccion externa.', 1;
    PRINT 'TEST_STATE_PASS:SES01_BULK_BEFORE_START';

    -- C. Inicio exacto (08:00:00): el inicio pertenece a la ventana. La sesion se crea con inicio = reloj del motor
    --    inmediatamente antes de invocar el SP, que lee el reloj despues (>= inicio).
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    VALUES (@sExactStart, N'SES01 Inicio exacto', @firstNumber + 9, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group,
            SYSUTCDATETIME(), DATEADD(HOUR, 2, SYSUTCDATETIME()), N'UTC_V2');
    TRUNCATE TABLE #ses01Result;
    SET @corr = NEWID();
    INSERT INTO #ses01Result
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sExactStart, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @owner;
    IF (SELECT COUNT(*) FROM #ses01Result WHERE idCorrelacion = @corr AND estadoResultado = 1) <> 1
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_asistencia a JOIN dbo.uv_detalle_asistencia d ON d.idAsistencia = a.id
                      WHERE a.idSesion = @sExactStart AND a.idEstudianteGrupo = @enrollment AND d.codigoRazonCausa = 'AN' AND d.asistio = 1)
        THROW 53103, 'TEST FAILED: SES01_BULK_EXACT_START el inicio exacto no permitio registrar.', 1;
    PRINT 'TEST_PASS:SES01_BULK_EXACT_START';

    -- D. Durante la sesion: lote de dos estudiantes registrado completo.
    TRUNCATE TABLE #ses01Result;
    SET @corr = NEWID();
    INSERT INTO #ses01Result
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sDuring, @asistenciaJSON = @jsonTwo, @idCorrelacion = @corr, @idUsuarioEjecutor = @owner;
    IF (SELECT COUNT(*) FROM #ses01Result WHERE idCorrelacion = @corr AND estadoResultado = 1) <> 1
       OR (SELECT COUNT(*) FROM dbo.Asistencia WHERE sesion = @sDuring) <> 2
        THROW 53104, 'TEST FAILED: SES01_BULK_DURING la sesion activa no registro el lote completo.', 1;
    PRINT 'TEST_PASS:SES01_BULK_DURING';

    -- E. Instante inmediatamente anterior al cierre (09:59:59): aun permitido.
    TRUNCATE TABLE #ses01Result;
    SET @corr = NEWID();
    INSERT INTO #ses01Result
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sJustBeforeEnd, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @owner;
    IF (SELECT COUNT(*) FROM #ses01Result WHERE idCorrelacion = @corr AND estadoResultado = 1) <> 1
       OR NOT EXISTS (SELECT 1 FROM dbo.Asistencia WHERE sesion = @sJustBeforeEnd)
        THROW 53105, 'TEST FAILED: SES01_BULK_JUST_BEFORE_END rechazo un registro antes del fin.', 1;
    PRINT 'TEST_PASS:SES01_BULK_JUST_BEFORE_END';

    -- F. Fin exacto (10:00:00): el fin NO pertenece a la ventana. La sesion se crea con fin = reloj del motor
    --    inmediatamente antes de invocar el SP, que lee el reloj despues (>= fin).
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    VALUES (@sExactEnd, N'SES01 Fin exacto', @firstNumber + 10, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group,
            DATEADD(HOUR, -2, SYSUTCDATETIME()), SYSUTCDATETIME(), N'UTC_V2');
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SES_008', @p_param1 = @sExactEnd,
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    PRINT CONCAT('TEST_EXPECTED_USER:SES01_BULK_EXACT_END|', @userMsg);
    PRINT CONCAT('TEST_EXPECTED_TECH:SES01_BULK_EXACT_END|', @techMsg, ' Correlacion: ', @corr);
    PRINT 'TEST_RESULT_BEGIN:SES01_BULK_EXACT_END';
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sExactEnd, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @owner;
    PRINT 'TEST_RESULT_END:SES01_BULK_EXACT_END';
    IF EXISTS (SELECT 1 FROM dbo.Asistencia WHERE sesion = @sExactEnd) OR @@TRANCOUNT <> @tranBefore
        THROW 53106, 'TEST FAILED: SES01_BULK_EXACT_END escribio asistencia al fin exacto.', 1;
    PRINT 'TEST_STATE_PASS:SES01_BULK_EXACT_END';

    -- G. Dos horas despues del cierre (12:00 de una sesion 08:00-10:00): SES_008, lote completo rechazado.
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SES_008', @p_param1 = @sTwoHoursAfter,
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    PRINT CONCAT('TEST_EXPECTED_USER:SES01_BULK_TWO_HOURS_AFTER|', @userMsg);
    PRINT CONCAT('TEST_EXPECTED_TECH:SES01_BULK_TWO_HOURS_AFTER|', @techMsg, ' Correlacion: ', @corr);
    PRINT 'TEST_RESULT_BEGIN:SES01_BULK_TWO_HOURS_AFTER';
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sTwoHoursAfter, @asistenciaJSON = @jsonTwo, @idCorrelacion = @corr, @idUsuarioEjecutor = @owner;
    PRINT 'TEST_RESULT_END:SES01_BULK_TWO_HOURS_AFTER';
    IF EXISTS (SELECT 1 FROM dbo.Asistencia WHERE sesion = @sTwoHoursAfter) OR @@TRANCOUNT <> @tranBefore
        THROW 53107, 'TEST FAILED: SES01_BULK_TWO_HOURS_AFTER escribio asistencia despues del cierre.', 1;
    PRINT 'TEST_STATE_PASS:SES01_BULK_TWO_HOURS_AFTER';

    -- H. Procedencia INDETERMINADA (NULL): nunca se supone zona; SES_009 aunque el DATETIME2 pareciera activo.
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SES_009', @p_param1 = @sIndeterminate,
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    PRINT CONCAT('TEST_EXPECTED_USER:SES01_BULK_INDETERMINATE|', @userMsg);
    PRINT CONCAT('TEST_EXPECTED_TECH:SES01_BULK_INDETERMINATE|', @techMsg, ' Correlacion: ', @corr);
    PRINT 'TEST_RESULT_BEGIN:SES01_BULK_INDETERMINATE';
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sIndeterminate, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @owner;
    PRINT 'TEST_RESULT_END:SES01_BULK_INDETERMINATE';
    IF EXISTS (SELECT 1 FROM dbo.Asistencia WHERE sesion = @sIndeterminate) OR @@TRANCOUNT <> @tranBefore
        THROW 53108, 'TEST FAILED: SES01_BULK_INDETERMINATE escribio asistencia con procedencia indeterminada.', 1;
    PRINT 'TEST_STATE_PASS:SES01_BULK_INDETERMINATE';

    -- I. Historico conservado: una asistencia existente de una sesion cerrada no cambia por el registro ordinario.
    --    (Preparacion con el helper interno, que no es alcanzable por el rol runtime.)
    DECLARE @helperUser NVARCHAR(4000), @helperTech NVARCHAR(4000), @helperState BIT;
    EXEC dbo.usp_sincronizar_asistencia_estudiante_interno
        @idEstudiante = @student, @idSesion = @sHistory, @codigoEstado = N'AN', @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @helperUser OUTPUT, @mensajeTecnicoResultado = @helperTech OUTPUT, @estadoResultado = @helperState OUTPUT;
    IF @helperState <> 1
        THROW 53109, 'TEST FAILED: SES01_BULK_CLOSED_HISTORY_PRESERVED no pudo preparar el historico.', 1;
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SES_008', @p_param1 = @sHistory,
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    PRINT CONCAT('TEST_EXPECTED_USER:SES01_BULK_CLOSED_HISTORY_PRESERVED|', @userMsg);
    PRINT CONCAT('TEST_EXPECTED_TECH:SES01_BULK_CLOSED_HISTORY_PRESERVED|', @techMsg, ' Correlacion: ', @corr);
    PRINT 'TEST_RESULT_BEGIN:SES01_BULK_CLOSED_HISTORY_PRESERVED';
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sHistory, @asistenciaJSON = @jsonTwo, @idCorrelacion = @corr, @idUsuarioEjecutor = @owner;
    PRINT 'TEST_RESULT_END:SES01_BULK_CLOSED_HISTORY_PRESERVED';
    IF (SELECT COUNT(*) FROM dbo.Asistencia WHERE sesion = @sHistory) <> 1
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_asistencia a JOIN dbo.uv_detalle_asistencia d ON d.idAsistencia = a.id
                      WHERE a.idSesion = @sHistory AND a.idEstudianteGrupo = @enrollment AND d.codigoRazonCausa = 'AN' AND d.asistio = 1)
       OR @@TRANCOUNT <> @tranBefore
        THROW 53110, 'TEST FAILED: SES01_BULK_CLOSED_HISTORY_PRESERVED el registro ordinario altero el historico de una sesion cerrada.', 1;
    PRINT 'TEST_STATE_PASS:SES01_BULK_CLOSED_HISTORY_PRESERVED';

    -- J. Registro autonomo del estudiante: ninguna ruta alternativa escribe fuera de la ventana.
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SES_008', @p_param1 = @sAutoClosed,
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    PRINT CONCAT('TEST_EXPECTED_USER:SES01_AUTO_CLOSED|', @userMsg);
    PRINT CONCAT('TEST_EXPECTED_TECH:SES01_AUTO_CLOSED|', @techMsg, ' Correlacion: ', @corr);
    PRINT 'TEST_RESULT_BEGIN:SES01_AUTO_CLOSED';
    EXEC dbo.usp_registrar_asistencia_estudiante_autonomo
        @idEstudiante = @student, @idSesion = @sAutoClosed, @codigoVerificacion = @codeAutoClosed,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @studentUser;
    PRINT 'TEST_RESULT_END:SES01_AUTO_CLOSED';
    IF EXISTS (SELECT 1 FROM dbo.Asistencia WHERE sesion = @sAutoClosed) OR @@TRANCOUNT <> @tranBefore
        THROW 53111, 'TEST FAILED: SES01_AUTO_CLOSED el registro autonomo escribio despues del cierre.', 1;
    PRINT 'TEST_STATE_PASS:SES01_AUTO_CLOSED';

    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SES_007', @p_param1 = @sAutoFuture,
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    PRINT CONCAT('TEST_EXPECTED_USER:SES01_AUTO_BEFORE_START|', @userMsg);
    PRINT CONCAT('TEST_EXPECTED_TECH:SES01_AUTO_BEFORE_START|', @techMsg, ' Correlacion: ', @corr);
    PRINT 'TEST_RESULT_BEGIN:SES01_AUTO_BEFORE_START';
    EXEC dbo.usp_registrar_asistencia_estudiante_autonomo
        @idEstudiante = @student, @idSesion = @sAutoFuture, @codigoVerificacion = @codeAutoFuture,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @studentUser;
    PRINT 'TEST_RESULT_END:SES01_AUTO_BEFORE_START';
    IF EXISTS (SELECT 1 FROM dbo.Asistencia WHERE sesion = @sAutoFuture) OR @@TRANCOUNT <> @tranBefore
        THROW 53112, 'TEST FAILED: SES01_AUTO_BEFORE_START el registro autonomo escribio antes del inicio.', 1;
    PRINT 'TEST_STATE_PASS:SES01_AUTO_BEFORE_START';

    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SES_009', @p_param1 = @sAutoIndeterminate,
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    PRINT CONCAT('TEST_EXPECTED_USER:SES01_AUTO_INDETERMINATE|', @userMsg);
    PRINT CONCAT('TEST_EXPECTED_TECH:SES01_AUTO_INDETERMINATE|', @techMsg, ' Correlacion: ', @corr);
    PRINT 'TEST_RESULT_BEGIN:SES01_AUTO_INDETERMINATE';
    EXEC dbo.usp_registrar_asistencia_estudiante_autonomo
        @idEstudiante = @student, @idSesion = @sAutoIndeterminate, @codigoVerificacion = @codeAutoIndeterminate,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @studentUser;
    PRINT 'TEST_RESULT_END:SES01_AUTO_INDETERMINATE';
    IF EXISTS (SELECT 1 FROM dbo.Asistencia WHERE sesion = @sAutoIndeterminate) OR @@TRANCOUNT <> @tranBefore
        THROW 53113, 'TEST FAILED: SES01_AUTO_INDETERMINATE el registro autonomo escribio con procedencia indeterminada.', 1;
    PRINT 'TEST_STATE_PASS:SES01_AUTO_INDETERMINATE';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
ROLLBACK TRANSACTION;
DROP TABLE #ses01Result;
-- SES01_BULK_BEFORE_START, SES01_BULK_EXACT_END, SES01_BULK_TWO_HOURS_AFTER, SES01_BULK_INDETERMINATE,
-- SES01_BULK_CLOSED_HISTORY_PRESERVED y SES01_AUTO_*: TEST_PASS lo emite test_summary.ps1 (result set + estado).
PRINT 'TEST END: test_ses01_ventana_asistencia';
GO
