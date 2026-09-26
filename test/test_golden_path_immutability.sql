USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT 'TEST START: test_golden_path_immutability';

-- DB-GP-001C: el hardening de uv_auth_* / SESSION_CONTEXT NO puede alterar el Golden Path.
-- Los shapes esperados salen de docs/contracts/DB_BASELINE_CONTRACT.md (seccion
-- "Golden Path Read Projections") y de las firmas congeladas del baseline. Cualquier cambio
-- en nombre, orden, tipo o nulabilidad requiere un nuevo work item / decision de contrato.

DECLARE @expectedViews TABLE (viewName SYSNAME NOT NULL, shape NVARCHAR(MAX) NOT NULL);
INSERT @expectedViews (viewName, shape) VALUES
    ('uv_horario_docente', N'id:uniqueidentifier:0,idDocente:uniqueidentifier:0,idGrupo:uniqueidentifier:0,codigoMateria:nvarchar:0,nombreMateria:nvarchar:0,seccion:nvarchar:0,dia:nvarchar:0,horaInicio:varchar:1,horaFin:varchar:1,totalEstudiantes:int:1'),
    ('uv_sesion', N'id:uniqueidentifier:0,nombre:nvarchar:0,numero:int:0,codigo:nvarchar:0,numeroSemana:int:0,idGrupo:uniqueidentifier:0,codigoGrupo:int:0,nombreGrupo:nvarchar:0,fechaHoraInicio:datetime2:0,fechaHoraFin:datetime2:0'),
    ('uv_estudiante_grupo', N'id:uniqueidentifier:0,idEstadoEstudiante:uniqueidentifier:0,nombreEstadoEstudiante:nvarchar:0,codigoEstadoEstudiante:nvarchar:0,idEstudiante:uniqueidentifier:0,nombreCompletoEstudiante:nvarchar:0,idGrupo:uniqueidentifier:0,codigoGrupo:int:0,nombreGrupo:nvarchar:0'),
    ('uv_asistencia', N'id:uniqueidentifier:0,idEstudianteGrupo:uniqueidentifier:0,idSesion:uniqueidentifier:0'),
    ('uv_detalle_asistencia', N'id:uniqueidentifier:0,codigo:int:0,idAsistencia:uniqueidentifier:0,asistio:bit:0,idRazonCausa:uniqueidentifier:0,nombreRazonCausa:nvarchar:0,codigoRazonCausa:nvarchar:0,fechaHoraInicio:datetime2:0,fechaHoraFin:datetime2:0');

DECLARE @viewDrift NVARCHAR(MAX) = (
    SELECT STRING_AGG(e.viewName, ',')
    FROM @expectedViews e
    OUTER APPLY (
        SELECT STRING_AGG(CONVERT(NVARCHAR(MAX), CONCAT(c.name, ':', t.name, ':', c.is_nullable)), ',') WITHIN GROUP (ORDER BY c.column_id) AS shape
        FROM sys.columns c
        JOIN sys.types t ON t.user_type_id = c.user_type_id
        WHERE c.object_id = OBJECT_ID(CONCAT('dbo.', e.viewName))
    ) a
    WHERE a.shape IS NULL OR a.shape <> e.shape
);
IF @viewDrift IS NOT NULL
BEGIN
    DECLARE @viewFailure NVARCHAR(2048) = CONCAT('TEST FAILED: GOLDEN_PATH_VIEW_SHAPES_FROZEN drift en: ', @viewDrift);
    THROW 52100, @viewFailure, 1;
END
PRINT 'TEST_PASS:GOLDEN_PATH_VIEW_SHAPES_FROZEN';

DECLARE @expectedProcedures TABLE (procedureName SYSNAME NOT NULL, signature NVARCHAR(MAX) NOT NULL);
INSERT @expectedProcedures (procedureName, signature) VALUES
    ('usp_crear_sesion', N'@idGrupo:uniqueidentifier,@nombre:nvarchar,@fechaHoraInicio:datetime2,@fechaHoraFin:datetime2,@idCorrelacion:uniqueidentifier,@idUsuarioEjecutor:uniqueidentifier'),
    ('usp_actualizar_sesion', N'@idSesion:uniqueidentifier,@nombre:nvarchar,@fechaHoraInicio:datetime2,@fechaHoraFin:datetime2,@idCorrelacion:uniqueidentifier,@idUsuarioEjecutor:uniqueidentifier'),
    ('usp_generar_sesiones_grupo', N'@idGrupo:uniqueidentifier,@idCorrelacion:uniqueidentifier,@idUsuarioEjecutor:uniqueidentifier'),
    ('usp_registrar_asistencias_sesion', N'@idSesion:uniqueidentifier,@asistenciaJSON:nvarchar,@idCorrelacion:uniqueidentifier,@idUsuarioEjecutor:uniqueidentifier');

DECLARE @procedureDrift NVARCHAR(MAX) = (
    SELECT STRING_AGG(e.procedureName, ',')
    FROM @expectedProcedures e
    OUTER APPLY (
        SELECT STRING_AGG(CONVERT(NVARCHAR(MAX), CONCAT(p.name, ':', t.name)), ',') WITHIN GROUP (ORDER BY p.parameter_id) AS signature
        FROM sys.parameters p
        JOIN sys.types t ON t.user_type_id = p.user_type_id
        WHERE p.object_id = OBJECT_ID(CONCAT('dbo.', e.procedureName))
    ) a
    WHERE a.signature IS NULL OR a.signature <> e.signature
);
IF @procedureDrift IS NOT NULL
BEGIN
    DECLARE @procedureFailure NVARCHAR(2048) = CONCAT('TEST FAILED: GOLDEN_PATH_SP_SIGNATURES_FROZEN drift en: ', @procedureDrift);
    THROW 52101, @procedureFailure, 1;
END
PRINT 'TEST_PASS:GOLDEN_PATH_SP_SIGNATURES_FROZEN';

-- Los SP de mutacion Golden Path conservan el resultset canonico de 4 columnas.
IF EXISTS (
    SELECT 1
    FROM @expectedProcedures e
    CROSS APPLY sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID(CONCAT('dbo.', e.procedureName)), NULL) d
    WHERE d.error_number IS NOT NULL
    GROUP BY e.procedureName
    UNION ALL
    SELECT 1
    FROM @expectedProcedures e
    CROSS APPLY sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID(CONCAT('dbo.', e.procedureName)), NULL) d
    GROUP BY e.procedureName
    HAVING COUNT(d.column_ordinal) <> 4
       OR MAX(CASE WHEN d.column_ordinal = 1 THEN d.name END) <> 'idCorrelacion'
       OR MAX(CASE WHEN d.column_ordinal = 2 THEN d.name END) <> 'mensajeUsuarioResultado'
       OR MAX(CASE WHEN d.column_ordinal = 3 THEN d.name END) <> 'mensajeTecnicoResultado'
       OR MAX(CASE WHEN d.column_ordinal = 4 THEN d.name END) <> 'estadoResultado'
)
    THROW 52102, 'TEST FAILED: GOLDEN_PATH_MUTATION_RESULTSET_FROZEN resultset canonico alterado.', 1;
PRINT 'TEST_PASS:GOLDEN_PATH_MUTATION_RESULTSET_FROZEN';

IF @@TRANCOUNT <> 0
    THROW 52103, 'TEST FAILED: test_golden_path_immutability dejo transacciones abiertas.', 1;

PRINT 'TEST END: test_golden_path_immutability';
GO
