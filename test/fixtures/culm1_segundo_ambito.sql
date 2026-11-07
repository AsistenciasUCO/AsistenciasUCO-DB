USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- culm1_segundo_ambito.sql (CULM-001 A.2-13, CONTRACT §8.2.3 A2-DB-7; F-TRX-008, F-DEC-011)
--
-- Segundo ambito de datos para la matriz de la Fase 3 y la verificacion A.2 por API: los usuarios uco-* del laboratorio
-- NO deben ver nada de este ambito. Fuera del despliegue (deploy_schema.ps1 no lee test/). Idempotente: cada fila tiene
-- un id fijo con el prefijo C1B0... y se inserta solo si no existe.
-- En la institucion sembrada:
--   * CULM1-Facultad B (se busca PRIMERO por nombre; si ya existe se usa tal cual y el _down nunca la borra; si no
--     existe se crea con id C1B0...01 y su CULM1-Decano B);
--   * CULM1-Programa B con CULM1-Coordinador B, plan, semestre y asignatura CULM1-ASG-B (componente ESP);
--   * CULM1-Docente B y CULM1-Grupo B en el periodo vigente, con horario;
--   * 3 estudiantes CULM1-Est B1..B3 con matricula A y EstudiantePrograma;
--   * una sesion vencida con asistencias y un reclamo P de B1 (ambito de reclamos).
-- Usuarios solo en BD (correo @uco.edu.co de prueba, contrasena con hash de relleno, sin cuentas en el realm).
-- Rollback: culm1_segundo_ambito_down.sql (borra solo las filas C1B0...). seed-clean-data.ps1 de Infra borra todo el
-- fixture al restablecer los datos: despues hay que volver a aplicarlo.
-- ============================================================================
SET XACT_ABORT ON;
BEGIN TRANSACTION;

DECLARE @p CHAR(34) = 'C1B00000-0000-4000-8000-0000000000';
DECLARE @inst UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Institucion ORDER BY id);
DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = 'CC');
DECLARE @tipoProg UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoPrograma ORDER BY nombre);
DECLARE @semestre UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Semestre ORDER BY id);
DECLARE @area UNIQUEIDENTIFIER = (SELECT TOP 1 area FROM dbo.Asignatura ORDER BY id);
DECLARE @esp UNIQUEIDENTIFIER = (SELECT id FROM dbo.Componente WHERE codigo = N'ESP');
DECLARE @estA UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoEstudianteGrupo WHERE codigo = N'A');
DECLARE @an UNIQUEIDENTIFIER = (SELECT id FROM dbo.RazonCausa WHERE codigo = 'AN');
DECLARE @sjc UNIQUEIDENTIFIER = (SELECT id FROM dbo.RazonCausa WHERE codigo = 'SJC');
DECLARE @recP UNIQUEIDENTIFIER = (SELECT id FROM dbo.Estado WHERE codigo = 'P');
DECLARE @dia UNIQUEIDENTIFIER = (SELECT id FROM dbo.Dia WHERE codigo = N'MI');
DECLARE @hoy DATE = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE CAST(dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER') AS NVARCHAR(100)) AS DATE);
DECLARE @periodo UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.PeriodoAcademico WHERE institucion = @inst AND fechaInicio <= @hoy AND fechaFin >= @hoy ORDER BY fechaFin DESC, id);
IF @periodo IS NULL SET @periodo = (SELECT TOP 1 id FROM dbo.PeriodoAcademico WHERE institucion = @inst ORDER BY fechaFin DESC, id);
IF @inst IS NULL OR @tipoCC IS NULL OR @tipoProg IS NULL OR @semestre IS NULL OR @area IS NULL OR @esp IS NULL OR @estA IS NULL
   OR @an IS NULL OR @sjc IS NULL OR @recP IS NULL OR @dia IS NULL OR @periodo IS NULL
    THROW 58500, 'CULM1_SEGUNDO_AMBITO: catalogos o periodo de la semilla no disponibles.', 1;

DECLARE @uDecano UNIQUEIDENTIFIER = CAST(@p + '02' AS UNIQUEIDENTIFIER), @decano UNIQUEIDENTIFIER = CAST(@p + '03' AS UNIQUEIDENTIFIER);
DECLARE @uCoord UNIQUEIDENTIFIER = CAST(@p + '04' AS UNIQUEIDENTIFIER), @coord UNIQUEIDENTIFIER = CAST(@p + '05' AS UNIQUEIDENTIFIER);
DECLARE @programa UNIQUEIDENTIFIER = CAST(@p + '06' AS UNIQUEIDENTIFIER), @plan UNIQUEIDENTIFIER = CAST(@p + '07' AS UNIQUEIDENTIFIER);
DECLARE @spe UNIQUEIDENTIFIER = CAST(@p + '08' AS UNIQUEIDENTIFIER), @asignatura UNIQUEIDENTIFIER = CAST(@p + '09' AS UNIQUEIDENTIFIER);
DECLARE @uDocente UNIQUEIDENTIFIER = CAST(@p + '0A' AS UNIQUEIDENTIFIER), @docente UNIQUEIDENTIFIER = CAST(@p + '0B' AS UNIQUEIDENTIFIER);
DECLARE @grupo UNIQUEIDENTIFIER = CAST(@p + '0C' AS UNIQUEIDENTIFIER), @horario UNIQUEIDENTIFIER = CAST(@p + '0D' AS UNIQUEIDENTIFIER);
DECLARE @sesion UNIQUEIDENTIFIER = CAST(@p + '51' AS UNIQUEIDENTIFIER), @reclamo UNIQUEIDENTIFIER = CAST(@p + '81' AS UNIQUEIDENTIFIER);

-- Facultad: primero por nombre (puede existir ya); si no, se crea con su decano.
DECLARE @facultad UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Facultad WHERE nombre = N'CULM1-Facultad B' ORDER BY id);
IF @facultad IS NULL
BEGIN
    SET @facultad = CAST(@p + '01' AS UNIQUEIDENTIFIER);
    IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @uDecano)
        INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
        VALUES (@uDecano, @tipoCC, 1985100002, N'CULM1', N'B', N'Decano', N'B', N'culm1.fixture.decano.b@uco.edu.co', 1, 1, N'HashRelleno_CULM1_B_SinCuenta');
    IF NOT EXISTS (SELECT 1 FROM dbo.Decano WHERE id = @decano)
        INSERT INTO dbo.Decano (id, usuario) VALUES (@decano, @uDecano);
    INSERT INTO dbo.Facultad (id, nombre, institucion, decano, estado) VALUES (@facultad, N'CULM1-Facultad B', @inst, @decano, 1);
END

-- Usuarios del ambito (solo BD).
INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
SELECT CAST(@p + v.k AS UNIQUEIDENTIFIER), @tipoCC, 1985100000 + v.n, N'CULM1', N'B', v.nombre, v.nombre2, v.correo, 1, 1, N'HashRelleno_CULM1_B_SinCuenta'
FROM (VALUES
    ('04', 4, N'Coordinador', N'B', N'culm1.fixture.coordinador.b@uco.edu.co'),
    ('0A', 10, N'Docente', N'B', N'culm1.fixture.docente.b@uco.edu.co'),
    ('11', 11, N'Est', N'B1', N'culm1.fixture.est.b1@uco.edu.co'),
    ('12', 12, N'Est', N'B2', N'culm1.fixture.est.b2@uco.edu.co'),
    ('13', 13, N'Est', N'B3', N'culm1.fixture.est.b3@uco.edu.co')
) v (k, n, nombre, nombre2, correo)
WHERE NOT EXISTS (SELECT 1 FROM dbo.Usuario u WHERE u.id = CAST(@p + v.k AS UNIQUEIDENTIFIER));

IF NOT EXISTS (SELECT 1 FROM dbo.Coordinador WHERE id = @coord)
    INSERT INTO dbo.Coordinador (id, usuario, facultad) VALUES (@coord, @uCoord, @facultad);
IF NOT EXISTS (SELECT 1 FROM dbo.Docente WHERE id = @docente)
    INSERT INTO dbo.Docente (id, usuario) VALUES (@docente, @uDocente);
INSERT INTO dbo.Estudiante (id, usuario)
SELECT CAST(@p + v.e AS UNIQUEIDENTIFIER), CAST(@p + v.u AS UNIQUEIDENTIFIER)
-- B1 recibe el id de estudiante MAYOR (..23): las pruebas que toman los dos primeros estudiantes de un grupo por id
-- (p. ej. test_consultas_reclamos_estudiante) no chocan con el reclamo de B1 (A2-T-15).
FROM (VALUES ('21', '13'), ('22', '12'), ('23', '11')) v (e, u)
WHERE NOT EXISTS (SELECT 1 FROM dbo.Estudiante x WHERE x.id = CAST(@p + v.e AS UNIQUEIDENTIFIER));

-- Estructura academica.
IF NOT EXISTS (SELECT 1 FROM dbo.Programa WHERE id = @programa)
    INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado) VALUES (@programa, @facultad, @tipoProg, N'CULM1-Programa B', @coord, 1);
IF NOT EXISTS (SELECT 1 FROM dbo.PlanEstudio WHERE id = @plan)
    INSERT INTO dbo.PlanEstudio (id, programa, inp, estado) VALUES (@plan, @programa, 99091, 1);
IF NOT EXISTS (SELECT 1 FROM dbo.SemestrePlanEstudio WHERE id = @spe)
    INSERT INTO dbo.SemestrePlanEstudio (id, planEstudio, semestre) VALUES (@spe, @plan, @semestre);
IF NOT EXISTS (SELECT 1 FROM dbo.Asignatura WHERE id = @asignatura)
    INSERT INTO dbo.Asignatura (id, codigo, nombre, credito, area, componente, semestrePlanEstudio, estado)
    VALUES (@asignatura, N'CULM1-ASG-B', N'CULM1-Asignatura B', 3, @area, @esp, @spe, 1);
IF NOT EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @grupo)
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
        cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@grupo, @asignatura, @periodo, 990901, N'CULM1-Grupo B', 30, 0, 0, 0, @docente);
IF NOT EXISTS (SELECT 1 FROM dbo.Horario WHERE id = @horario)
    INSERT INTO dbo.Horario (id, grupo, dia, horaInicio, horaFin) VALUES (@horario, @grupo, @dia, '07:00', '09:00');
-- Vinculo docente-programa (HU091): todo docente con grupos en un programa tiene su DocentePrograma (T-MIG-02).
IF NOT EXISTS (SELECT 1 FROM dbo.DocentePrograma WHERE id = CAST(@p + '0E' AS UNIQUEIDENTIFIER))
   AND NOT EXISTS (SELECT 1 FROM dbo.DocentePrograma WHERE docente = @docente AND programa = @programa)
    INSERT INTO dbo.DocentePrograma (id, docente, programa, tipoVinculacion, estado, fechaVinculacionUtc)
    SELECT CAST(@p + '0E' AS UNIQUEIDENTIFIER), @docente, @programa, tv.id, 1, SYSUTCDATETIME()
    FROM dbo.TipoVinculacion tv WHERE tv.codigo = 'PLA';

-- Matriculas activas y programa.
INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo)
SELECT CAST(@p + v.k AS UNIQUEIDENTIFIER), @estA, CAST(@p + v.e AS UNIQUEIDENTIFIER), @grupo
FROM (VALUES ('31', '21'), ('32', '22'), ('33', '23')) v (k, e)
WHERE NOT EXISTS (SELECT 1 FROM dbo.EstudianteGrupo x WHERE x.id = CAST(@p + v.k AS UNIQUEIDENTIFIER));
INSERT INTO dbo.EstudiantePrograma (id, estudiante, programa)
SELECT CAST(@p + v.k AS UNIQUEIDENTIFIER), CAST(@p + v.e AS UNIQUEIDENTIFIER), @programa
FROM (VALUES ('41', '21'), ('42', '22'), ('43', '23')) v (k, e)
WHERE NOT EXISTS (SELECT 1 FROM dbo.EstudiantePrograma x WHERE x.id = CAST(@p + v.k AS UNIQUEIDENTIFIER));

-- Sesion vencida (ayer) con asistencias y un reclamo P de B1.
IF NOT EXISTS (SELECT 1 FROM dbo.Sesion WHERE id = @sesion)
    INSERT INTO dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
    VALUES (@sesion, N'CULM1-Sesion B1', 1, N'SES-01', 1, @grupo,
            DATEADD(HOUR, 12, CAST(DATEADD(DAY, -1, @hoy) AS DATETIME2)), DATEADD(HOUR, 14, CAST(DATEADD(DAY, -1, @hoy) AS DATETIME2)));
INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion)
SELECT CAST(@p + v.k AS UNIQUEIDENTIFIER), CAST(@p + v.eg AS UNIQUEIDENTIFIER), @sesion
FROM (VALUES ('61', '31'), ('62', '32'), ('63', '33')) v (k, eg)
WHERE NOT EXISTS (SELECT 1 FROM dbo.Asistencia x WHERE x.id = CAST(@p + v.k AS UNIQUEIDENTIFIER));
DECLARE @inicioSesion DATETIME2 = (SELECT fechaHoraInicio FROM dbo.Sesion WHERE id = @sesion);
DECLARE @finSesion DATETIME2 = (SELECT fechaHoraFin FROM dbo.Sesion WHERE id = @sesion);
DECLARE @codigoDetalle INT = 1 + (SELECT ISNULL(MAX(codigo), 0) FROM dbo.DetalleAsistencia);
INSERT INTO dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin)
SELECT CAST(@p + v.k AS UNIQUEIDENTIFIER), @codigoDetalle + v.n, CAST(@p + v.a AS UNIQUEIDENTIFIER), v.asistio, IIF(v.asistio = 1, @an, @sjc), @inicioSesion, @finSesion
FROM (VALUES ('71', '61', 0, 1), ('72', '62', 1, 1), ('73', '63', 2, 0)) v (k, a, n, asistio)
WHERE NOT EXISTS (SELECT 1 FROM dbo.DetalleAsistencia x WHERE x.id = CAST(@p + v.k AS UNIQUEIDENTIFIER));
IF NOT EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia WHERE id = @reclamo)
    INSERT INTO dbo.SolicitudRevisionAsistencia (id, nombre, asistencia, fecha, estado, justificacionSolicitud, justificacionRespuesta)
    VALUES (@reclamo, N'REC-CULM1-B1', CAST(@p + '63' AS UNIQUEIDENTIFIER), @hoy, @recP, 'CULM1 reclamo de prueba del segundo ambito', '');

COMMIT TRANSACTION;
PRINT CONCAT('CULM1_SEGUNDO_AMBITO aplicado: facultad=', @facultad, ' grupo=', @grupo);
GO
SET XACT_ABORT OFF;
GO
