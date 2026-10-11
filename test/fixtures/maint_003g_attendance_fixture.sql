USE [gestionasistenciadb];
GO

/*
  Isolated Java-integration fixture for MAINT-003G.
  It is not deployment seed data: it is executed explicitly only against the
  controlled Developer SQL Server container. The public procedures under test
  create the session and attendance rows; direct DELETE is used solely to make
  repeated preparation idempotent.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @fixtureName NVARCHAR(50) = N'IT-MAINT003G-ATTENDANCE';
DECLARE @group UNIQUEIDENTIFIER;
DECLARE @teacherUser UNIQUEIDENTIFIER;
DECLARE @session UNIQUEIDENTIFIER;
DECLARE @attendanceJson NVARCHAR(MAX);
DECLARE @correlation UNIQUEIDENTIFIER = NEWID();
DECLARE @attendanceCorrelation UNIQUEIDENTIFIER = NEWID();
DECLARE @result TABLE (
    idCorrelacion UNIQUEIDENTIFIER,
    mensajeUsuarioResultado NVARCHAR(4000),
    mensajeTecnicoResultado NVARCHAR(4000),
    estadoResultado BIT
);

BEGIN TRANSACTION;

DELETE r
FROM dbo.SolicitudRevisionAsistencia r
INNER JOIN dbo.Asistencia a ON a.id = r.asistencia
INNER JOIN dbo.Sesion s ON s.id = a.sesion
WHERE s.nombre = @fixtureName;

DELETE d
FROM dbo.DetalleAsistencia d
INNER JOIN dbo.Asistencia a ON a.id = d.asistencia
INNER JOIN dbo.Sesion s ON s.id = a.sesion
WHERE s.nombre = @fixtureName;

DELETE a
FROM dbo.Asistencia a
INNER JOIN dbo.Sesion s ON s.id = a.sesion
WHERE s.nombre = @fixtureName;

DELETE FROM dbo.Sesion WHERE nombre = @fixtureName;

SELECT TOP (1)
    @group = g.id,
    @teacherUser = d.usuario
FROM dbo.Grupo g
INNER JOIN dbo.Docente d ON d.id = g.docente
INNER JOIN dbo.EstudianteGrupo eg ON eg.grupo = g.id
INNER JOIN dbo.EstadoEstudianteGrupo eeg ON eeg.id = eg.estado AND eeg.codigo = 'A'
GROUP BY g.id, d.usuario
HAVING COUNT(*) >= 2
ORDER BY g.id;

IF @group IS NULL OR @teacherUser IS NULL
    THROW 52201, 'MAINT-003G fixture requires one teacher-owned group with two active students.', 1;

INSERT INTO @result
EXEC dbo.usp_crear_sesion
    @idGrupo = @group,
    @nombre = @fixtureName,
    @fechaHoraInicio = '2040-01-15T08:00:00',
    @fechaHoraFin = '2040-01-15T10:00:00',
    @idCorrelacion = @correlation,
    @idUsuarioEjecutor = @teacherUser;

IF NOT EXISTS (SELECT 1 FROM @result WHERE estadoResultado = 1)
    THROW 52202, 'MAINT-003G fixture session creation was rejected by the public contract.', 1;

SELECT @session = id FROM dbo.Sesion WHERE nombre = @fixtureName;
IF @session IS NULL
    THROW 52203, 'MAINT-003G fixture session was not persisted.', 1;

SELECT @attendanceJson = CONCAT(
    '[',
    STRING_AGG(CONCAT('{"idEstudiante":"', CONVERT(VARCHAR(36), q.estudiante), '","estado":"', q.estado, '"}'), ','),
    ']')
FROM (
    SELECT TOP (2) eg.estudiante, CASE ROW_NUMBER() OVER (ORDER BY eg.estudiante)
        WHEN 1 THEN 'AN' ELSE 'SJC' END AS estado
    FROM dbo.EstudianteGrupo eg
    INNER JOIN dbo.EstadoEstudianteGrupo eeg ON eeg.id = eg.estado AND eeg.codigo = 'A'
    WHERE eg.grupo = @group
    ORDER BY eg.estudiante
) q;

IF @attendanceJson IS NULL OR @attendanceJson = '[]'
    THROW 52204, 'MAINT-003G fixture did not resolve two active students.', 1;

DELETE FROM @result;
INSERT INTO @result
EXEC dbo.usp_registrar_asistencias_sesion
    @idSesion = @session,
    @asistenciaJSON = @attendanceJson,
    @idCorrelacion = @attendanceCorrelation,
    @idUsuarioEjecutor = @teacherUser;

IF NOT EXISTS (SELECT 1 FROM @result WHERE estadoResultado = 1)
    THROW 52205, 'MAINT-003G fixture attendance registration was rejected by the public contract.', 1;

IF (SELECT COUNT(*) FROM dbo.uv_detalle_asistencia da
    INNER JOIN dbo.uv_asistencia a ON a.id = da.idAsistencia
    WHERE a.idSesion = @session) <> 2
    THROW 52206, 'MAINT-003G fixture must expose exactly two attendance-detail rows.', 1;

COMMIT TRANSACTION;

SELECT CONCAT('TEST_FIXTURE_READY|session=', CONVERT(VARCHAR(36), @session), '|rows=2');
GO
