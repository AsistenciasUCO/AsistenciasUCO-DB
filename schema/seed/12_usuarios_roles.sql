USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- 1. Sembrado Idempotente: Usuarios (Decano, Coordinador, Docente, Estudiantes)
DECLARE @TipoCC UNIQUEIDENTIFIER;
SELECT TOP 1 @TipoCC = id FROM [dbo].[TipoIdentificacion] WHERE tipoIdentificacion = 'CC';

MERGE INTO [dbo].[Usuario] AS Target
USING (VALUES
    ('E1F2A3B4-0000-0000-0000-000000000001', @TipoCC, 1017000001, 'Gomez', 'Perez', 'Juan', 'Carlos', 'decano.ingenieria@uco.edu.co', 1, 1, 'HashBackend_AbCdEf1234567890'),
    ('E1F2A3B4-0000-0000-0000-000000000002', @TipoCC, 1017000002, 'Lopez', 'Martinez', 'Andres', 'Felipe', 'coordinador.sistemas@uco.edu.co', 1, 1, 'HashBackend_AbCdEf1234567890'),
    ('E1F2A3B4-0000-0000-0000-000000000003', @TipoCC, 1017112233, 'Rostagno', 'Valencia', 'Maria', 'Elena', 'maria.rostagno@uco.edu.co', 1, 1, 'HashBackend_AbCdEf1234567890'),
    ('E1F2A3B4-0000-0000-0000-000000000004', @TipoCC, 1017223344, 'Zapata', 'Gomez', 'Carlos', 'Andres', 'carlos.zapata@uco.edu.co', 1, 1, 'HashBackend_AbCdEf1234567890'),
    ('E1F2A3B4-0000-0000-0000-000000000005', @TipoCC, 1017334455, 'Gomez', 'Rios', 'Ana', 'Sofia', 'ana.gomez@uco.edu.co', 1, 1, 'HashBackend_AbCdEf1234567890'),
    ('E1F2A3B4-0000-0000-0000-000000000006', @TipoCC, 1017445566, 'Admin', 'UCO', 'Sistema', 'QA', 'admin.sistema@uco.edu.co', 1, 1, 'HashBackend_AbCdEf1234567890')
) AS Source (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
ON (Target.id = TRY_CAST(Source.id AS UNIQUEIDENTIFIER) OR Target.correo = Source.correo)
WHEN MATCHED THEN
    UPDATE SET 
        Target.tipoIdIdentificacion = Source.tipoIdIdentificacion,
        Target.numeroIdentificacion = Source.numeroIdentificacion,
        Target.primerNombre = Source.primerNombre,
        Target.segundoNombre = Source.segundoNombre,
        Target.primerApellido = Source.primerApellido,
        Target.segundoApellido = Source.segundoApellido,
        Target.correo = Source.correo,
        Target.correoConfirmado = Source.correoConfirmado,
        Target.estado = Source.estado,
        Target.password = Source.password
WHEN NOT MATCHED THEN
    INSERT (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), Source.tipoIdIdentificacion, Source.numeroIdentificacion, Source.primerApellido, Source.segundoApellido, Source.primerNombre, Source.segundoNombre, Source.correo, Source.correoConfirmado, Source.estado, Source.password);
GO

-- 1.1 Sembrado Idempotente: Administrador
MERGE INTO [dbo].[Administrador] AS Target
USING (VALUES
    ('F1A2B3C4-0000-0000-0000-000000000006', 'E1F2A3B4-0000-0000-0000-000000000006', 'B1C2D3E4-0000-0000-0000-000000000001')
) AS Source (id, usuario, institucion)
ON (Target.id = TRY_CAST(Source.id AS UNIQUEIDENTIFIER) OR Target.usuario = TRY_CAST(Source.usuario AS UNIQUEIDENTIFIER))
WHEN MATCHED THEN
    UPDATE SET
        Target.usuario = TRY_CAST(Source.usuario AS UNIQUEIDENTIFIER),
        Target.institucion = TRY_CAST(Source.institucion AS UNIQUEIDENTIFIER)
WHEN NOT MATCHED THEN
    INSERT (id, usuario, institucion)
    VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), TRY_CAST(Source.usuario AS UNIQUEIDENTIFIER), TRY_CAST(Source.institucion AS UNIQUEIDENTIFIER));
GO

-- 2. Sembrado Idempotente: Decano
MERGE INTO [dbo].[Decano] AS Target
USING (VALUES
    ('F1A2B3C4-0000-0000-0000-000000000001', 'E1F2A3B4-0000-0000-0000-000000000001')
) AS Source (id, usuario)
ON (Target.id = TRY_CAST(Source.id AS UNIQUEIDENTIFIER) OR Target.usuario = TRY_CAST(Source.usuario AS UNIQUEIDENTIFIER))
WHEN MATCHED THEN
    UPDATE SET Target.usuario = TRY_CAST(Source.usuario AS UNIQUEIDENTIFIER)
WHEN NOT MATCHED THEN
    INSERT (id, usuario)
    VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), TRY_CAST(Source.usuario AS UNIQUEIDENTIFIER));
GO

-- 3. Sembrado Idempotente: Coordinador
MERGE INTO [dbo].[Coordinador] AS Target
USING (VALUES
    ('F1A2B3C4-0000-0000-0000-000000000002', 'E1F2A3B4-0000-0000-0000-000000000002')
) AS Source (id, usuario)
ON (Target.id = TRY_CAST(Source.id AS UNIQUEIDENTIFIER) OR Target.usuario = TRY_CAST(Source.usuario AS UNIQUEIDENTIFIER))
WHEN MATCHED THEN
    UPDATE SET Target.usuario = TRY_CAST(Source.usuario AS UNIQUEIDENTIFIER)
WHEN NOT MATCHED THEN
    INSERT (id, usuario)
    VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), TRY_CAST(Source.usuario AS UNIQUEIDENTIFIER));
GO

-- 4. Sembrado Idempotente: Docente
MERGE INTO [dbo].[Docente] AS Target
USING (VALUES
    ('F1A2B3C4-0000-0000-0000-000000000003', 'E1F2A3B4-0000-0000-0000-000000000003')
) AS Source (id, usuario)
ON (Target.id = TRY_CAST(Source.id AS UNIQUEIDENTIFIER) OR Target.usuario = TRY_CAST(Source.usuario AS UNIQUEIDENTIFIER))
WHEN MATCHED THEN
    UPDATE SET Target.usuario = TRY_CAST(Source.usuario AS UNIQUEIDENTIFIER)
WHEN NOT MATCHED THEN
    INSERT (id, usuario)
    VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), TRY_CAST(Source.usuario AS UNIQUEIDENTIFIER));
GO

-- 5. Sembrado Idempotente: Estudiantes
MERGE INTO [dbo].[Estudiante] AS Target
USING (VALUES
    ('F1A2B3C4-0000-0000-0000-000000000004', 'E1F2A3B4-0000-0000-0000-000000000004'),
    ('F1A2B3C4-0000-0000-0000-000000000005', 'E1F2A3B4-0000-0000-0000-000000000005')
) AS Source (id, usuario)
ON (Target.id = TRY_CAST(Source.id AS UNIQUEIDENTIFIER) OR Target.usuario = TRY_CAST(Source.usuario AS UNIQUEIDENTIFIER))
WHEN MATCHED THEN
    UPDATE SET Target.usuario = TRY_CAST(Source.usuario AS UNIQUEIDENTIFIER)
WHEN NOT MATCHED THEN
    INSERT (id, usuario)
    VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), TRY_CAST(Source.usuario AS UNIQUEIDENTIFIER));
GO
