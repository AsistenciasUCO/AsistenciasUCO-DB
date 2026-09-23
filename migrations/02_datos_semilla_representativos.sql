USE [gestionasistenciadb];
GO

SET NOCOUNT ON;

-- 1. Asegurar estado 'P' (Pendiente) en dbo.Estado
IF NOT EXISTS (SELECT 1 FROM dbo.Estado WHERE codigo = 'P')
BEGIN
    INSERT INTO dbo.Estado (id, nombre, codigo)
    VALUES ('90123456-0000-0000-0000-000000000001', 'pendiente', 'P');
END

-- Variables de catálogos
DECLARE @tipoDocCC UNIQUEIDENTIFIER;
SELECT TOP 1 @tipoDocCC = id FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = 'CC';

DECLARE @estadoActivoEstGrupo UNIQUEIDENTIFIER;
SELECT TOP 1 @estadoActivoEstGrupo = id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'A';

DECLARE @idGrupoArq UNIQUEIDENTIFIER = 'A1B2C3D4-E5F6-7A8B-9C0D-1E2F3A4B5C6D';
DECLARE @idPeriodo UNIQUEIDENTIFIER = 'F2A3B4C5-0000-0000-0000-000000000001';

-- 2. Crear Usuarios Estudiantes Adicionales si no existen
IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = 'E1F2A3B4-0000-0000-0000-000000000006')
BEGIN
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES ('E1F2A3B4-0000-0000-0000-000000000006', @tipoDocCC, '1017000006', 'Marin', 'Sanchez', 'Juan', 'Pablo', 'marin@uco.edu.co', 1, 1, 'Hash_123456');
    INSERT INTO dbo.Estudiante (id, usuario) VALUES ('F1A2B3C4-0000-0000-0000-000000000006', 'E1F2A3B4-0000-0000-0000-000000000006');
END

IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = 'E1F2A3B4-0000-0000-0000-000000000007')
BEGIN
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES ('E1F2A3B4-0000-0000-0000-000000000007', @tipoDocCC, '1017000007', 'Osorio', 'Giraldo', 'Valentina', '', 'valentina.osorio@uco.edu.co', 1, 1, 'Hash_123456');
    INSERT INTO dbo.Estudiante (id, usuario) VALUES ('F1A2B3C4-0000-0000-0000-000000000007', 'E1F2A3B4-0000-0000-0000-000000000007');
END

IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = 'E1F2A3B4-0000-0000-0000-000000000008')
BEGIN
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES ('E1F2A3B4-0000-0000-0000-000000000008', @tipoDocCC, '1017000008', 'Rios', 'Bedoya', 'Mateo', '', 'mateo.rios@uco.edu.co', 1, 1, 'Hash_123456');
    INSERT INTO dbo.Estudiante (id, usuario) VALUES ('F1A2B3C4-0000-0000-0000-000000000008', 'E1F2A3B4-0000-0000-0000-000000000008');
END

IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = 'E1F2A3B4-0000-0000-0000-000000000009')
BEGIN
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES ('E1F2A3B4-0000-0000-0000-000000000009', @tipoDocCC, '1017000009', 'Castrillon', 'Montoya', 'Sofia', '', 'sofia.castrillon@uco.edu.co', 1, 1, 'Hash_123456');
    INSERT INTO dbo.Estudiante (id, usuario) VALUES ('F1A2B3C4-0000-0000-0000-000000000009', 'E1F2A3B4-0000-0000-0000-000000000009');
END

IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = 'E1F2A3B4-0000-0000-0000-000000000010')
BEGIN
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES ('E1F2A3B4-0000-0000-0000-000000000010', @tipoDocCC, '1017000010', 'Arboleda', 'Valencia', 'Camilo', '', 'camilo.arboleda@uco.edu.co', 1, 1, 'Hash_123456');
    INSERT INTO dbo.Estudiante (id, usuario) VALUES ('F1A2B3C4-0000-0000-0000-000000000010', 'E1F2A3B4-0000-0000-0000-000000000010');
END

-- 3. Enrolar estudiantes en Grupo Arq Software
IF NOT EXISTS (SELECT 1 FROM dbo.EstudianteGrupo WHERE id = 'B1A2C3D4-0000-0000-0000-000000000003')
    INSERT INTO dbo.EstudianteGrupo (id, estudiante, grupo, estado) VALUES ('B1A2C3D4-0000-0000-0000-000000000003', 'F1A2B3C4-0000-0000-0000-000000000006', @idGrupoArq, @estadoActivoEstGrupo);

IF NOT EXISTS (SELECT 1 FROM dbo.EstudianteGrupo WHERE id = 'B1A2C3D4-0000-0000-0000-000000000004')
    INSERT INTO dbo.EstudianteGrupo (id, estudiante, grupo, estado) VALUES ('B1A2C3D4-0000-0000-0000-000000000004', 'F1A2B3C4-0000-0000-0000-000000000007', @idGrupoArq, @estadoActivoEstGrupo);

IF NOT EXISTS (SELECT 1 FROM dbo.EstudianteGrupo WHERE id = 'B1A2C3D4-0000-0000-0000-000000000005')
    INSERT INTO dbo.EstudianteGrupo (id, estudiante, grupo, estado) VALUES ('B1A2C3D4-0000-0000-0000-000000000005', 'F1A2B3C4-0000-0000-0000-000000000008', @idGrupoArq, @estadoActivoEstGrupo);

IF NOT EXISTS (SELECT 1 FROM dbo.EstudianteGrupo WHERE id = 'B1A2C3D4-0000-0000-0000-000000000006')
    INSERT INTO dbo.EstudianteGrupo (id, estudiante, grupo, estado) VALUES ('B1A2C3D4-0000-0000-0000-000000000006', 'F1A2B3C4-0000-0000-0000-000000000009', @idGrupoArq, @estadoActivoEstGrupo);

IF NOT EXISTS (SELECT 1 FROM dbo.EstudianteGrupo WHERE id = 'B1A2C3D4-0000-0000-0000-000000000007')
    INSERT INTO dbo.EstudianteGrupo (id, estudiante, grupo, estado) VALUES ('B1A2C3D4-0000-0000-0000-000000000007', 'F1A2B3C4-0000-0000-0000-000000000010', @idGrupoArq, @estadoActivoEstGrupo);

-- Actualizar contador de estudiantes en Grupo
UPDATE dbo.Grupo SET cantidadEstudiantes = 7 WHERE id = @idGrupoArq;

-- 4. Insertar Sesiones 3 y 4 si no existen
DECLARE @idSesion1 UNIQUEIDENTIFIER = 'B2C3D4E5-F6A7-8B9C-0D1E-2F3A4B5C6D7E';
DECLARE @idSesion2 UNIQUEIDENTIFIER = 'C3D4E5F6-A7B8-9C0D-1E2F-3A4B5C6D7E8F';
DECLARE @idSesion3 UNIQUEIDENTIFIER = 'D4E5F6A7-B8C9-0D1E-2F3A-4B5C6D7E8F9A';
DECLARE @idSesion4 UNIQUEIDENTIFIER = 'E5F6A7B8-C9D0-1E2F-3A4B-5C6D7E8F9A0B';

IF NOT EXISTS (SELECT 1 FROM dbo.Sesion WHERE id = @idSesion3)
BEGIN
    INSERT INTO dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
    VALUES (@idSesion3, 'Microservicios y Event-Driven', 3, 'SES-03', 3, @idGrupoArq, '2026-09-01 08:00:00', '2026-09-01 10:00:00');
END

IF NOT EXISTS (SELECT 1 FROM dbo.Sesion WHERE id = @idSesion4)
BEGIN
    INSERT INTO dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
    VALUES (@idSesion4, 'Seguridad y OAuth2 en Backend', 4, 'SES-04', 4, @idGrupoArq, '2026-09-05 08:00:00', '2026-09-05 10:00:00');
END

-- 5. Insertar Asistencias y Detalles de Asistencia
DECLARE @idRazonAN UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001'; -- Asistencia normal
DECLARE @idRazonSJC UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000002'; -- Sin justa causa
DECLARE @idRazonEX UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000003'; -- Excusa / justificada

-- Asistencias Sesion 1 (Todos asistieron)
DECLARE @asistId UNIQUEIDENTIFIER;
DECLARE cur_est CURSOR FOR SELECT id FROM dbo.EstudianteGrupo WHERE grupo = @idGrupoArq;
DECLARE @egId UNIQUEIDENTIFIER;

OPEN cur_est;
FETCH NEXT FROM cur_est INTO @egId;
WHILE @@FETCH_STATUS = 0
BEGIN
    -- Sesión 1
    IF NOT EXISTS (SELECT 1 FROM dbo.Asistencia WHERE estudianteGrupo = @egId AND sesion = @idSesion1)
    BEGIN
        SET @asistId = NEWID();
        INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion) VALUES (@asistId, @egId, @idSesion1);
        INSERT INTO dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin)
        VALUES (NEWID(), 1, @asistId, 1, @idRazonAN, '2026-08-25 08:00:00', '2026-08-25 10:00:00');
    END

    -- Sesión 2 (Carlos Zapata faltó)
    IF NOT EXISTS (SELECT 1 FROM dbo.Asistencia WHERE estudianteGrupo = @egId AND sesion = @idSesion2)
    BEGIN
        SET @asistId = NEWID();
        INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion) VALUES (@asistId, @egId, @idSesion2);

        IF @egId = 'B1A2C3D4-0000-0000-0000-000000000001' -- Carlos Zapata
        BEGIN
            INSERT INTO dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin)
            VALUES (NEWID(), 2, @asistId, 0, @idRazonSJC, '2026-08-27 08:00:00', '2026-08-27 10:00:00');
        END
        ELSE
        BEGIN
            INSERT INTO dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin)
            VALUES (NEWID(), 2, @asistId, 1, @idRazonAN, '2026-08-27 08:00:00', '2026-08-27 10:00:00');
        END
    END

    -- Sesión 3 (Carlos Zapata y Mateo Rios faltaron)
    IF NOT EXISTS (SELECT 1 FROM dbo.Asistencia WHERE estudianteGrupo = @egId AND sesion = @idSesion3)
    BEGIN
        SET @asistId = NEWID();
        INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion) VALUES (@asistId, @egId, @idSesion3);

        IF @egId IN ('B1A2C3D4-0000-0000-0000-000000000001', 'B1A2C3D4-0000-0000-0000-000000000005')
        BEGIN
            INSERT INTO dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin)
            VALUES (NEWID(), 3, @asistId, 0, @idRazonSJC, '2026-09-01 08:00:00', '2026-09-01 10:00:00');
        END
        ELSE
        BEGIN
            INSERT INTO dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin)
            VALUES (NEWID(), 3, @asistId, 1, @idRazonAN, '2026-09-01 08:00:00', '2026-09-01 10:00:00');
        END
    END

    FETCH NEXT FROM cur_est INTO @egId;
END;
CLOSE cur_est;
DEALLOCATE cur_est;

-- 6. Insertar Solicitud de Revisión de Asistencia de prueba para Carlos Zapata
DECLARE @asistenciaSesion2Carlos UNIQUEIDENTIFIER;
SELECT TOP 1 @asistenciaSesion2Carlos = a.id
FROM dbo.Asistencia a
WHERE a.estudianteGrupo = 'B1A2C3D4-0000-0000-0000-000000000001' AND a.sesion = @idSesion2;

IF @asistenciaSesion2Carlos IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia WHERE asistencia = @asistenciaSesion2Carlos)
BEGIN
    INSERT INTO dbo.SolicitudRevisionAsistencia (
        id, nombre, asistencia, fecha, estado, justificacionSolicitud, justificacionRespuesta,
        categoria, soporteAdjuntoNombre, soporteAdjuntoUrl, fechaRespuesta
    ) VALUES (
        '90123456-0000-0000-0000-000000000011',
        'REC-001',
        @asistenciaSesion2Carlos,
        '2026-08-28',
        '90123456-0000-0000-0000-000000000001', -- Pendiente 'P'
        'Estuve en urgencias por cuadro viral agudo.',
        '',
        'Médico / Salud',
        'incapacidad_medica_sura.pdf',
        '/api/v1/archivos/incapacidad_medica_sura.pdf',
        NULL
    );
END

-- 7. Insertar Solicitud de Matrícula de prueba para Mateo Ríos (si la tabla estuviese disponible)
IF OBJECT_ID('dbo.SolicitudMatricula', 'U') IS NOT NULL
BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.SolicitudMatricula WHERE id = '90123456-0000-0000-0000-000000000021')
    BEGIN
        INSERT INTO dbo.SolicitudMatricula (
            id, estudiante, grupo, fechaSolicitud, motivo, estado, respuestaCoordinador, fechaRespuesta
        ) VALUES (
            '90123456-0000-0000-0000-000000000021',
            'F1A2B3C4-0000-0000-0000-000000000008', -- Mateo Rios
            @idGrupoArq,
            '2026-09-02',
            'Solicitud de inscripción por cupo extemporáneo para culminación de créditos.',
            'PENDIENTE',
            '',
            NULL
        );
    END
END

PRINT 'Datos semilla representativos insertados exitosamente.';
GO
