USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT 'TEST START: test_titularidad_jerarquica';

-- @idUsuario del helper es Usuario.id. Los fixtures se descubren garantizando
-- Usuario.id <> Docente.id / Coordinador.id / Decano.id para que una implementacion que compare
-- el ID del rol contra Usuario.id NO pase por coincidencia de UUID.
DECLARE @grupo UNIQUEIDENTIFIER, @docenteRol UNIQUEIDENTIFIER, @docenteUsuario UNIQUEIDENTIFIER, @sesion UNIQUEIDENTIFIER;
SELECT TOP 1 @grupo = g.id, @docenteRol = di.id, @docenteUsuario = di.idUsuario, @sesion = s.id
FROM dbo.uv_grupo g
JOIN dbo.uv_docente_identidad di ON di.id = g.idDocente
JOIN dbo.uv_sesion s ON s.idGrupo = g.id
WHERE di.id <> di.idUsuario
ORDER BY g.id, s.id;
DECLARE @docenteOtroUsuario UNIQUEIDENTIFIER =
    (SELECT TOP 1 id FROM dbo.Usuario WHERE id <> @docenteUsuario AND id <> @docenteRol AND estado = 1 ORDER BY id);

DECLARE @programa UNIQUEIDENTIFIER, @coordinadorRol UNIQUEIDENTIFIER, @coordinadorUsuario UNIQUEIDENTIFIER;
SELECT TOP 1 @programa = p.id, @coordinadorRol = ci.id, @coordinadorUsuario = ci.idUsuario
FROM dbo.uv_programa p
JOIN dbo.uv_coordinador_identidad ci ON ci.id = p.idCoordinador
WHERE ci.id <> ci.idUsuario
ORDER BY p.id;
DECLARE @coordinadorOtroUsuario UNIQUEIDENTIFIER =
    (SELECT TOP 1 id FROM dbo.Usuario WHERE id <> @coordinadorUsuario AND id <> @coordinadorRol AND estado = 1 ORDER BY id);

DECLARE @facultad UNIQUEIDENTIFIER, @decanoRol UNIQUEIDENTIFIER, @decanoUsuario UNIQUEIDENTIFIER;
SELECT TOP 1 @facultad = f.id, @decanoRol = di.id, @decanoUsuario = di.idUsuario
FROM dbo.uv_facultad f
JOIN dbo.uv_decano_identidad di ON di.id = f.idDecano
WHERE di.id <> di.idUsuario
ORDER BY f.id;
DECLARE @decanoOtroUsuario UNIQUEIDENTIFIER =
    (SELECT TOP 1 id FROM dbo.Usuario WHERE id <> @decanoUsuario AND id <> @decanoRol AND estado = 1 ORDER BY id);

DECLARE @institucion UNIQUEIDENTIFIER, @adminUsuario UNIQUEIDENTIFIER;
SELECT TOP 1 @institucion = institucion, @adminUsuario = usuario FROM dbo.Administrador ORDER BY id;

IF @grupo IS NULL OR @sesion IS NULL OR @docenteOtroUsuario IS NULL
    THROW 52000, 'TEST FAILED: TITULARIDAD fixture docente/grupo/sesion missing (requiere Usuario.id <> Docente.id).', 1;
IF @programa IS NULL OR @coordinadorOtroUsuario IS NULL
    THROW 52001, 'TEST FAILED: TITULARIDAD fixture coordinador/programa missing (requiere Usuario.id <> Coordinador.id).', 1;
IF @facultad IS NULL OR @decanoOtroUsuario IS NULL
    THROW 52002, 'TEST FAILED: TITULARIDAD fixture decano/facultad missing (requiere Usuario.id <> Decano.id).', 1;

CREATE TABLE #casos (
    orden INT IDENTITY(1,1), etiqueta VARCHAR(60), tipo NVARCHAR(50),
    idEntidad UNIQUEIDENTIFIER, idUsuario UNIQUEIDENTIFIER, esperado BIT
);
INSERT #casos (etiqueta, tipo, idEntidad, idUsuario, esperado) VALUES
    ('GRUPO owner (Usuario.id)',             'GRUPO',       @grupo,       @docenteUsuario,          1),
    ('GRUPO non-owner',                      'GRUPO',       @grupo,       @docenteOtroUsuario,      0),
    ('GRUPO Docente.id NO es Usuario.id',    'GRUPO',       @grupo,       @docenteRol,              0),
    ('SESION owner (Usuario.id)',            'SESION',      @sesion,      @docenteUsuario,          1),
    ('SESION non-owner',                     'SESION',      @sesion,      @docenteOtroUsuario,      0),
    ('SESION Docente.id NO es Usuario.id',   'SESION',      @sesion,      @docenteRol,              0),
    ('PROGRAMA owner (Usuario.id)',          'PROGRAMA',    @programa,    @coordinadorUsuario,      1),
    ('PROGRAMA non-owner',                   'PROGRAMA',    @programa,    @coordinadorOtroUsuario,  0),
    ('PROGRAMA Coordinador.id NO es Usuario.id', 'PROGRAMA', @programa,   @coordinadorRol,          0),
    ('FACULTAD owner (Usuario.id)',          'FACULTAD',    @facultad,    @decanoUsuario,           1),
    ('FACULTAD non-owner',                   'FACULTAD',    @facultad,    @decanoOtroUsuario,       0),
    ('FACULTAD Decano.id NO es Usuario.id',  'FACULTAD',    @facultad,    @decanoRol,               0);

IF @institucion IS NOT NULL AND @adminUsuario IS NOT NULL
BEGIN
    INSERT #casos (etiqueta, tipo, idEntidad, idUsuario, esperado)
    VALUES ('INSTITUCION owner (Administrador.usuario)', 'INSTITUCION', @institucion, @adminUsuario, 1);
END

DECLARE @orden INT = 1, @maxOrden INT = (SELECT MAX(orden) FROM #casos);
DECLARE @etiqueta VARCHAR(60), @tipo NVARCHAR(50), @entidad UNIQUEIDENTIFIER, @usuario UNIQUEIDENTIFIER, @esperado BIT;
DECLARE @corr UNIQUEIDENTIFIER, @userMsg NVARCHAR(4000), @techMsg NVARCHAR(4000), @estado BIT, @failure NVARCHAR(2048);
WHILE @orden <= @maxOrden
BEGIN
    SELECT @etiqueta = etiqueta, @tipo = tipo, @entidad = idEntidad, @usuario = idUsuario, @esperado = esperado
    FROM #casos WHERE orden = @orden;
    SET @corr = NEWID();
    EXEC dbo.usp_validar_titularidad_jerarquica_interno
        @idUsuario = @usuario, @idEntidadPadre = @entidad, @tipoEntidadPadre = @tipo, @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT, @estadoResultado = @estado OUTPUT;
    IF @estado <> @esperado
    BEGIN
        SET @failure = CONCAT('TEST FAILED: TITULARIDAD ', @etiqueta, ' esperado=', @esperado, ' actual=', @estado);
        THROW 52004, @failure, 1;
    END
    SET @orden += 1;
END
DROP TABLE #casos;
IF @@TRANCOUNT <> 0 THROW 52005, 'TEST FAILED: TITULARIDAD dejo transaccion abierta.', 1;

PRINT 'TEST_PASS:TITULARIDAD_GRUPO_USUARIO_ID';
PRINT 'TEST_PASS:TITULARIDAD_SESION_USUARIO_ID';
PRINT 'TEST_PASS:TITULARIDAD_PROGRAMA_USUARIO_ID';
PRINT 'TEST_PASS:TITULARIDAD_FACULTAD_USUARIO_ID';
PRINT 'TEST END: test_titularidad_jerarquica';
GO
