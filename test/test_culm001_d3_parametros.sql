USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- CULM-001 D.3 (CONTRACT v2 §4.2, D3-01..D3-18 salvo D3-09 y D3-16, que ejecuta test/test_culm001_d3.ps1): HU168, edicion
-- de parametros por el administrador con lista blanca (CatalogoParametroEdicion), tipo, rango, reglas cruzadas, motivo,
-- concurrencia optimista (fechaModificacionEsperada) e historial (CambioParametro). Todo dentro de una transaccion que se
-- revierte; los objetos de D.3 se verifican primero (RED: fallan por objeto ausente).
PRINT 'TEST START: test_culm001_d3_parametros (CULM-001 D.3, HU168)';

IF OBJECT_ID(N'dbo.CatalogoParametroEdicion', N'U') IS NULL OR OBJECT_ID(N'dbo.CambioParametro', N'U') IS NULL
   OR OBJECT_ID(N'dbo.uv_parametro_edicion', N'V') IS NULL OR OBJECT_ID(N'dbo.uv_cambio_parametro', N'V') IS NULL
   OR OBJECT_ID(N'dbo.ufn_validar_valor_parametro', N'FN') IS NULL
   OR OBJECT_ID(N'dbo.usp_actualizar_parametro', N'P') IS NULL OR OBJECT_ID(N'dbo.usp_consultar_parametros_paginado', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_consultar_cambios_parametro_paginado', N'P') IS NULL
    THROW 57300, 'TEST FAILED CULM001_D3_00: faltan objetos de D.3 (CatalogoParametroEdicion, CambioParametro, uv_parametro_edicion, uv_cambio_parametro, ufn_validar_valor_parametro, usp_actualizar_parametro, usp_consultar_parametros_paginado, usp_consultar_cambios_parametro_paginado).', 1;
IF dbo.ufn_obtener_parametro('PARAMETROS', 'GRUPOS_NO_EDITABLES') <> N'RED,TIEMPO,GENERAL,REGISTRO,IDENTIDAD,RECLAMO,TOMA_ASISTENCIA,PARAMETROS,AUDITORIA,PAGINACION,MATRICULA'
   OR dbo.ufn_obtener_parametro('PARAMETROS', 'TIPOS_NUMERICOS') <> N'INT,DECIMAL'
   OR dbo.ufn_obtener_parametro('PARAMETROS', 'TIPOS_ENTEROS') <> N'INT'
   OR dbo.ufn_obtener_parametro_int(NULL, 'PARAMETROS', 'LONGITUD_MINIMA_MOTIVO') <> 10
    THROW 57301, 'TEST FAILED CULM001_D3_00: parametros PARAMETROS/GRUPOS_NO_EDITABLES, TIPOS_NUMERICOS, TIPOS_ENTEROS o LONGITUD_MINIMA_MOTIVO ausentes o distintos.', 1;
IF EXISTS (SELECT 1 FROM (VALUES ('PRM_001'), ('PRM_002'), ('PRM_003'), ('PRM_004'), ('PRM_005'), ('PRM_006'), ('PRM_007'), ('PRM_008'),
                                 ('PRM_009'), ('PRM_010'), ('PRM_011'), ('PRM_012')) c(codigo)
           WHERE NOT EXISTS (SELECT 1 FROM dbo.uv_mensaje_usuario u WHERE u.codigo = c.codigo)
              OR NOT EXISTS (SELECT 1 FROM dbo.uv_mensaje_tecnico t WHERE t.codigo = c.codigo))
    THROW 57302, 'TEST FAILED CULM001_D3_00: faltan mensajes PRM_001..PRM_012 (usuario y tecnico).', 1;
PRINT 'TEST_PASS:CULM001_D3_00_OBJETOS_Y_SEMILLAS';
GO

-- D3-15 (estatico): la lista blanca sembrada solo tiene filas coherentes
IF EXISTS (SELECT 1 FROM dbo.CatalogoParametroEdicion e INNER JOIN dbo.CatalogoParametro p ON p.id = e.parametro
           WHERE e.esEditable = 1 AND EXISTS (SELECT 1 FROM STRING_SPLIT(dbo.ufn_obtener_parametro('PARAMETROS', 'GRUPOS_NO_EDITABLES'), ',') g WHERE TRIM(g.value) = p.grupo))
    THROW 57303, 'TEST FAILED CULM001_D3_15: hay filas editables en un grupo protegido (PARAMETROS/GRUPOS_NO_EDITABLES).', 1;
IF EXISTS (SELECT 1 FROM dbo.CatalogoParametroEdicion e INNER JOIN dbo.CatalogoParametro p ON p.id = e.parametro
           WHERE e.esEditable = 1
             AND EXISTS (SELECT 1 FROM STRING_SPLIT(dbo.ufn_obtener_parametro('PARAMETROS', 'TIPOS_NUMERICOS'), ',') t WHERE TRIM(t.value) = p.tipoDato)
             AND (e.valorMinimo IS NULL OR e.valorMaximo IS NULL))
    THROW 57304, 'TEST FAILED CULM001_D3_15: una fila editable numerica no tiene rango.', 1;
IF EXISTS (SELECT 1 FROM dbo.CatalogoParametroEdicion e INNER JOIN dbo.CatalogoParametro p ON p.id = e.parametro
           WHERE e.esEditable = 1 AND dbo.ufn_validar_valor_parametro(p.tipoDato, p.valor, e.valorMinimo, e.valorMaximo, e.valoresPermitidos) IS NOT NULL)
    THROW 57305, 'TEST FAILED CULM001_D3_15: el valor actual de un parametro editable no cumple su propia regla.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.CatalogoParametroEdicion e INNER JOIN dbo.CatalogoParametro p ON p.id = e.parametro WHERE e.esEditable = 1 AND p.grupo = 'ASISTENCIA' AND p.clave = 'TOLERANCIA_MINUTOS' AND e.valorMinimo = 0 AND e.valorMaximo = 60)
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoParametroEdicion e INNER JOIN dbo.CatalogoParametro p ON p.id = e.parametro WHERE e.esEditable = 1 AND p.grupo = 'MATRICULA_QR' AND p.clave = 'HABILITADA' AND e.valoresPermitidos = N'true,false')
   OR EXISTS (SELECT 1 FROM dbo.CatalogoParametroEdicion e INNER JOIN dbo.CatalogoParametro p ON p.id = e.parametro WHERE e.esEditable = 1 AND p.grupo IN ('RED', 'TIEMPO'))
    THROW 57306, 'TEST FAILED CULM001_D3_15: la lista blanca inicial no incluye ASISTENCIA/TOLERANCIA_MINUTOS [0,60] o MATRICULA_QR/HABILITADA {true,false}.', 1;
PRINT 'TEST_PASS:CULM001_D3_15_LISTA_BLANCA_COHERENTE';
GO

DECLARE @admin UNIQUEIDENTIFIER = (SELECT TOP 1 a.usuario FROM dbo.Administrador a JOIN dbo.uv_usuario u ON u.id = a.usuario WHERE u.estaActivoUsuario = 1 ORDER BY a.id);
DECLARE @coord UNIQUEIDENTIFIER = (SELECT TOP 1 ci.idUsuario FROM dbo.uv_coordinador_identidad ci WHERE ci.estaActivoUsuario = 1 AND ci.estaActivoRolCoordinador = 1 ORDER BY ci.id);
DECLARE @pTol UNIQUEIDENTIFIER = (SELECT id FROM dbo.CatalogoParametro WHERE grupo = 'ASISTENCIA' AND clave = 'TOLERANCIA_MINUTOS');
DECLARE @pAdv UNIQUEIDENTIFIER = (SELECT id FROM dbo.CatalogoParametro WHERE grupo = 'ASISTENCIA' AND clave = 'UMBRAL_ALERTA_ADVERTENCIA');
DECLARE @pPer UNIQUEIDENTIFIER = (SELECT id FROM dbo.CatalogoParametro WHERE grupo = 'ASISTENCIA' AND clave = 'UMBRAL_ALERTA_PERDIDA');
DECLARE @pHab UNIQUEIDENTIFIER = (SELECT id FROM dbo.CatalogoParametro WHERE grupo = 'MATRICULA_QR' AND clave = 'HABILITADA');
DECLARE @pMin UNIQUEIDENTIFIER = (SELECT id FROM dbo.CatalogoParametro WHERE grupo = 'FESTIVOS' AND clave = 'MINIMO_POR_ANIO');
DECLARE @pMax UNIQUEIDENTIFIER = (SELECT id FROM dbo.CatalogoParametro WHERE grupo = 'FESTIVOS' AND clave = 'MAXIMO_POR_ANIO');
DECLARE @pDias UNIQUEIDENTIFIER = (SELECT id FROM dbo.CatalogoParametro WHERE grupo = 'ASISTENCIA' AND clave = 'DIAS_LIMITE_JUSTIFICACION');
DECLARE @pRed UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.CatalogoParametro WHERE grupo = 'RED' ORDER BY clave);
DECLARE @pSesion UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.CatalogoParametro WHERE grupo = 'SESION' ORDER BY clave);
IF @admin IS NULL OR @coord IS NULL OR @pTol IS NULL OR @pAdv IS NULL OR @pPer IS NULL OR @pHab IS NULL OR @pMin IS NULL OR @pMax IS NULL
   OR @pDias IS NULL OR @pRed IS NULL OR @pSesion IS NULL
    THROW 57310, 'TEST FAILED CULM001_D3: faltan fixtures del seed (administrador, coordinador, parametros de ASISTENCIA, MATRICULA_QR, FESTIVOS, RED y SESION).', 1;

CREATE TABLE #d3r (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(4000) NULL, mensajeTecnicoResultado NVARCHAR(4000) NULL,
    estadoResultado BIT NOT NULL, idParametro UNIQUEIDENTIFIER NULL, grupo VARCHAR(100) NULL, clave VARCHAR(100) NULL,
    valorAnterior NVARCHAR(4000) NULL, valorNuevo NVARCHAR(4000) NULL, fechaModificacion DATETIME NULL);
DECLARE @corr UNIQUEIDENTIFIER, @userMsg NVARCHAR(4000), @techMsg NVARCHAR(4000), @err NVARCHAR(4000), @f DATETIME, @f2 DATETIME;
DECLARE @tipoCC UNIQUEIDENTIFIER;

BEGIN TRANSACTION;
BEGIN TRY
    -- Valores conocidos de partida (se revierten)
    UPDATE dbo.CatalogoParametro SET valor = N'15' WHERE id IN (@pTol, @pAdv);
    UPDATE dbo.CatalogoParametro SET valor = N'20' WHERE id = @pPer;
    UPDATE dbo.CatalogoParametro SET valor = N'15' WHERE id = @pMin;
    UPDATE dbo.CatalogoParametro SET valor = N'25' WHERE id = @pMax;
    UPDATE dbo.CatalogoParametro SET valor = N'true' WHERE id = @pHab;
    UPDATE dbo.CatalogoParametro SET valor = N'5' WHERE id = @pDias;
    SELECT @f = fechaModificacion FROM dbo.CatalogoParametro WHERE id = @pTol;

    -- ------------------------------------------------------------------------------------------------------------
    -- D3-01: cambio valido => 1, historial con idCorrelacion y ejecutor, fechaModificacion avanza
    -- ------------------------------------------------------------------------------------------------------------
    UPDATE dbo.CatalogoParametro SET fechaModificacion = DATEADD(DAY, -1, fechaModificacion) WHERE id = @pTol;
    SELECT @f = fechaModificacion FROM dbo.CatalogoParametro WHERE id = @pTol;
    SET @corr = NEWID();
    INSERT INTO #d3r EXEC dbo.usp_actualizar_parametro @idParametro = @pTol, @valor = N'20', @fechaModificacionEsperada = @f,
        @motivo = N'Ajuste de prueba D3-01', @idCorrelacion = @corr, @idUsuarioEjecutor = @admin;
    IF NOT EXISTS (SELECT 1 FROM #d3r WHERE estadoResultado = 1 AND idCorrelacion = @corr AND mensajeTecnicoResultado LIKE N'DBCODE=PRM[_]001|%'
                   AND idParametro = @pTol AND grupo = 'ASISTENCIA' AND clave = 'TOLERANCIA_MINUTOS' AND valorAnterior = N'15' AND valorNuevo = N'20' AND fechaModificacion > @f)
       OR (SELECT valor FROM dbo.CatalogoParametro WHERE id = @pTol) <> N'20'
       OR NOT EXISTS (SELECT 1 FROM dbo.CambioParametro WHERE parametro = @pTol AND valorAnterior = N'15' AND valorNuevo = N'20'
                      AND motivo = N'Ajuste de prueba D3-01' AND idUsuarioEjecutor = @admin AND idCorrelacion = @corr)
       OR (SELECT COUNT(*) FROM dbo.CambioParametro WHERE parametro = @pTol) <> 1
        THROW 57311, 'TEST FAILED CULM001_D3_01: un cambio valido debe actualizar el valor, registrar CambioParametro (anterior, nuevo, motivo, ejecutor, correlacion) y avanzar fechaModificacion.', 1;
    TRUNCATE TABLE #d3r;
    PRINT 'TEST_PASS:CULM001_D3_01_CAMBIO_VALIDO';

    -- D3-14: efecto inmediato en la lectura de parametros que usa el resto de la BD
    IF dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'TOLERANCIA_MINUTOS') <> 20
        THROW 57312, 'TEST FAILED CULM001_D3_14: el nuevo valor debe leerse de inmediato con ufn_obtener_parametro_int.', 1;
    SELECT @f = fechaModificacion FROM dbo.CatalogoParametro WHERE id = @pDias;
    SET @corr = NEWID();
    INSERT INTO #d3r EXEC dbo.usp_actualizar_parametro @idParametro = @pDias, @valor = N'9', @fechaModificacionEsperada = @f,
        @motivo = N'Ajuste de prueba D3-14', @idCorrelacion = @corr, @idUsuarioEjecutor = @admin;
    IF NOT EXISTS (SELECT 1 FROM #d3r WHERE estadoResultado = 1 AND valorNuevo = N'9')
       OR dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'DIAS_LIMITE_JUSTIFICACION') <> 9
        THROW 57313, 'TEST FAILED CULM001_D3_14: DIAS_LIMITE_JUSTIFICACION debe leerse con el valor nuevo.', 1;
    TRUNCATE TABLE #d3r;
    PRINT 'TEST_PASS:CULM001_D3_14_EFECTO_INMEDIATO';

    SELECT @f = fechaModificacion FROM dbo.CatalogoParametro WHERE id = @pTol;

    -- ------------------------------------------------------------------------------------------------------------
    -- D3-02 / D3-03: grupos protegidos y parametros sin fila editable => PRM_003, aun forzando esEditable = 1
    -- ------------------------------------------------------------------------------------------------------------
    INSERT INTO dbo.CatalogoParametroEdicion (parametro, esEditable, etiqueta, descripcion, categoriaVisual)
    VALUES (@pRed, 1, N'Forzado', N'Forzado por la prueba', N'Red');
    SELECT @f2 = fechaModificacion FROM dbo.CatalogoParametro WHERE id = @pRed;
    SET @corr = NEWID();
    INSERT INTO #d3r EXEC dbo.usp_actualizar_parametro @idParametro = @pRed, @valor = N'10.0.0.0/8', @fechaModificacionEsperada = @f2,
        @motivo = N'Intento sobre grupo RED', @idCorrelacion = @corr, @idUsuarioEjecutor = @admin;
    IF NOT EXISTS (SELECT 1 FROM #d3r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=PRM[_]003|%' AND idParametro IS NULL)
        THROW 57314, 'TEST FAILED CULM001_D3_02: un parametro de RED con esEditable = 1 forzado debe responder PRM_003.', 1;
    TRUNCATE TABLE #d3r;
    PRINT 'TEST_PASS:CULM001_D3_02_RED_PROTEGIDO';

    DECLARE @grupo VARCHAR(100), @idG UNIQUEIDENTIFIER, @fG DATETIME, @probados INT = 0, @rechazados INT = 0;
    DECLARE cg CURSOR LOCAL FAST_FORWARD FOR
        SELECT DISTINCT TRIM(g.value) FROM STRING_SPLIT(dbo.ufn_obtener_parametro('PARAMETROS', 'GRUPOS_NO_EDITABLES'), ',') g;
    OPEN cg; FETCH NEXT FROM cg INTO @grupo;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @idG = NULL;
        SELECT TOP 1 @idG = id, @fG = fechaModificacion FROM dbo.CatalogoParametro WHERE grupo = @grupo AND estaActivo = 1 ORDER BY clave;
        IF @idG IS NOT NULL
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM dbo.CatalogoParametroEdicion WHERE parametro = @idG)
                INSERT INTO dbo.CatalogoParametroEdicion (parametro, esEditable, etiqueta, descripcion, categoriaVisual) VALUES (@idG, 1, N'Forzado', N'Forzado por la prueba', @grupo);
            ELSE UPDATE dbo.CatalogoParametroEdicion SET esEditable = 1 WHERE parametro = @idG;
            SET @corr = NEWID();
            INSERT INTO #d3r EXEC dbo.usp_actualizar_parametro @idParametro = @idG, @valor = N'1', @fechaModificacionEsperada = @fG,
                @motivo = N'Intento sobre grupo protegido', @idCorrelacion = @corr, @idUsuarioEjecutor = @admin;
            SET @probados += 1;
            IF EXISTS (SELECT 1 FROM #d3r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=PRM[_]003|%') SET @rechazados += 1;
            TRUNCATE TABLE #d3r;
        END
        FETCH NEXT FROM cg INTO @grupo;
    END
    CLOSE cg; DEALLOCATE cg;
    IF @probados < 8 OR @probados <> @rechazados
        THROW 57315, 'TEST FAILED CULM001_D3_03: cada grupo de PARAMETROS/GRUPOS_NO_EDITABLES (TIEMPO, RED, ...) debe responder PRM_003 aun con esEditable = 1 forzado.', 1;
    -- Sin fila de edicion (grupo no listado ni en la lista blanca)
    SET @corr = NEWID();
    SELECT @fG = fechaModificacion FROM dbo.CatalogoParametro WHERE id = @pSesion;
    INSERT INTO #d3r EXEC dbo.usp_actualizar_parametro @idParametro = @pSesion, @valor = N'1', @fechaModificacionEsperada = @fG,
        @motivo = N'Intento sin fila editable', @idCorrelacion = @corr, @idUsuarioEjecutor = @admin;
    IF NOT EXISTS (SELECT 1 FROM #d3r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=PRM[_]003|%')
        THROW 57316, 'TEST FAILED CULM001_D3_03: un parametro sin fila editable debe responder PRM_003.', 1;
    TRUNCATE TABLE #d3r;
    -- Parametro inexistente (PRM_002)
    SET @corr = NEWID();
    INSERT INTO #d3r EXEC dbo.usp_actualizar_parametro @idParametro = @corr, @valor = N'1', @fechaModificacionEsperada = @f,
        @motivo = N'Parametro inexistente', @idCorrelacion = @corr, @idUsuarioEjecutor = @admin;
    IF NOT EXISTS (SELECT 1 FROM #d3r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=PRM[_]002|%')
        THROW 57317, 'TEST FAILED CULM001_D3_03: un parametro inexistente debe responder PRM_002.', 1;
    TRUNCATE TABLE #d3r;
    PRINT 'TEST_PASS:CULM001_D3_03_GRUPOS_NO_EDITABLES';

    -- ------------------------------------------------------------------------------------------------------------
    -- D3-04 tipos, D3-05 rango, D3-06 valores permitidos (sin escritura)
    -- ------------------------------------------------------------------------------------------------------------
    SELECT @f = fechaModificacion FROM dbo.CatalogoParametro WHERE id = @pTol;
    SET @corr = NEWID();
    INSERT INTO #d3r EXEC dbo.usp_actualizar_parametro @idParametro = @pTol, @valor = N'abc', @fechaModificacionEsperada = @f, @motivo = N'Tipo invalido de prueba', @idCorrelacion = @corr, @idUsuarioEjecutor = @admin;
    INSERT INTO #d3r EXEC dbo.usp_actualizar_parametro @idParametro = @pTol, @valor = N'7.5', @fechaModificacionEsperada = @f, @motivo = N'Tipo invalido de prueba', @idCorrelacion = @corr, @idUsuarioEjecutor = @admin;
    INSERT INTO #d3r EXEC dbo.usp_actualizar_parametro @idParametro = @pTol, @valor = N'   ', @fechaModificacionEsperada = @f, @motivo = N'Tipo invalido de prueba', @idCorrelacion = @corr, @idUsuarioEjecutor = @admin;
    SELECT @f2 = fechaModificacion FROM dbo.CatalogoParametro WHERE id = @pPer;
    INSERT INTO #d3r EXEC dbo.usp_actualizar_parametro @idParametro = @pPer, @valor = N'x', @fechaModificacionEsperada = @f2, @motivo = N'Tipo invalido de prueba', @idCorrelacion = @corr, @idUsuarioEjecutor = @admin;
    IF (SELECT COUNT(*) FROM #d3r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=PRM[_]004|%') <> 4
       OR (SELECT valor FROM dbo.CatalogoParametro WHERE id = @pTol) <> N'20'
        THROW 57320, 'TEST FAILED CULM001_D3_04: abc, 7.5 y vacio en INT y x en DECIMAL deben responder PRM_004 sin escribir.', 1;
    TRUNCATE TABLE #d3r;
    PRINT 'TEST_PASS:CULM001_D3_04_TIPOS';

    INSERT INTO #d3r EXEC dbo.usp_actualizar_parametro @idParametro = @pTol, @valor = N'61', @fechaModificacionEsperada = @f, @motivo = N'Fuera de rango de prueba', @idCorrelacion = @corr, @idUsuarioEjecutor = @admin;
    INSERT INTO #d3r EXEC dbo.usp_actualizar_parametro @idParametro = @pTol, @valor = N'-1', @fechaModificacionEsperada = @f, @motivo = N'Fuera de rango de prueba', @idCorrelacion = @corr, @idUsuarioEjecutor = @admin;
    IF (SELECT COUNT(*) FROM #d3r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=PRM[_]005|%' AND mensajeUsuarioResultado LIKE N'%0%60%') <> 2
        THROW 57321, 'TEST FAILED CULM001_D3_05: 61 y -1 fuera de [0, 60] deben responder PRM_005 con los limites en el mensaje.', 1;
    TRUNCATE TABLE #d3r;
    -- limites inclusivos: 0 y 60 son validos
    INSERT INTO #d3r EXEC dbo.usp_actualizar_parametro @idParametro = @pTol, @valor = N'60', @fechaModificacionEsperada = @f, @motivo = N'Limite superior de prueba', @idCorrelacion = @corr, @idUsuarioEjecutor = @admin;
    IF NOT EXISTS (SELECT 1 FROM #d3r WHERE estadoResultado = 1 AND valorNuevo = N'60') THROW 57322, 'TEST FAILED CULM001_D3_05: el limite superior 60 debe ser valido.', 1;
    SELECT @f = fechaModificacion FROM dbo.CatalogoParametro WHERE id = @pTol;
    TRUNCATE TABLE #d3r;
    PRINT 'TEST_PASS:CULM001_D3_05_RANGO';

    SELECT @f2 = fechaModificacion FROM dbo.CatalogoParametro WHERE id = @pHab;
    INSERT INTO #d3r EXEC dbo.usp_actualizar_parametro @idParametro = @pHab, @valor = N'maybe', @fechaModificacionEsperada = @f2, @motivo = N'Valor no permitido de prueba', @idCorrelacion = @corr, @idUsuarioEjecutor = @admin;
    INSERT INTO #d3r EXEC dbo.usp_actualizar_parametro @idParametro = @pHab, @valor = N'TRUE', @fechaModificacionEsperada = @f2, @motivo = N'Valor no permitido de prueba', @idCorrelacion = @corr, @idUsuarioEjecutor = @admin;
    IF (SELECT COUNT(*) FROM #d3r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=PRM[_]006|%' AND mensajeUsuarioResultado LIKE N'%true%false%') <> 2
        THROW 57323, 'TEST FAILED CULM001_D3_06: maybe y TRUE (la pertenencia es exacta) deben responder PRM_006 con la lista de valores.', 1;
    TRUNCATE TABLE #d3r;
    INSERT INTO #d3r EXEC dbo.usp_actualizar_parametro @idParametro = @pHab, @valor = N'false', @fechaModificacionEsperada = @f2, @motivo = N'Valor permitido de prueba', @idCorrelacion = @corr, @idUsuarioEjecutor = @admin;
    IF NOT EXISTS (SELECT 1 FROM #d3r WHERE estadoResultado = 1 AND valorNuevo = N'false' AND valorAnterior = N'true') THROW 57324, 'TEST FAILED CULM001_D3_06: false es un valor permitido.', 1;
    TRUNCATE TABLE #d3r;
    PRINT 'TEST_PASS:CULM001_D3_06_VALORES_PERMITIDOS';

    -- ------------------------------------------------------------------------------------------------------------
    -- D3-07: reglas cruzadas en las dos direcciones (estrictas)
    -- ------------------------------------------------------------------------------------------------------------
    SELECT @f = fechaModificacion FROM dbo.CatalogoParametro WHERE id = @pAdv;
    SELECT @f2 = fechaModificacion FROM dbo.CatalogoParametro WHERE id = @pPer;
    INSERT INTO #d3r EXEC dbo.usp_actualizar_parametro @idParametro = @pAdv, @valor = N'25', @fechaModificacionEsperada = @f, @motivo = N'Regla cruzada de prueba', @idCorrelacion = @corr, @idUsuarioEjecutor = @admin;
    INSERT INTO #d3r EXEC dbo.usp_actualizar_parametro @idParametro = @pAdv, @valor = N'20', @fechaModificacionEsperada = @f, @motivo = N'Regla cruzada de prueba', @idCorrelacion = @corr, @idUsuarioEjecutor = @admin;
    INSERT INTO #d3r EXEC dbo.usp_actualizar_parametro @idParametro = @pPer, @valor = N'10', @fechaModificacionEsperada = @f2, @motivo = N'Regla cruzada de prueba', @idCorrelacion = @corr, @idUsuarioEjecutor = @admin;
    INSERT INTO #d3r EXEC dbo.usp_actualizar_parametro @idParametro = @pPer, @valor = N'15', @fechaModificacionEsperada = @f2, @motivo = N'Regla cruzada de prueba', @idCorrelacion = @corr, @idUsuarioEjecutor = @admin;
    SELECT @f = fechaModificacion FROM dbo.CatalogoParametro WHERE id = @pMin;
    SELECT @f2 = fechaModificacion FROM dbo.CatalogoParametro WHERE id = @pMax;
    INSERT INTO #d3r EXEC dbo.usp_actualizar_parametro @idParametro = @pMin, @valor = N'26', @fechaModificacionEsperada = @f, @motivo = N'Regla cruzada de prueba', @idCorrelacion = @corr, @idUsuarioEjecutor = @admin;
    INSERT INTO #d3r EXEC dbo.usp_actualizar_parametro @idParametro = @pMax, @valor = N'14', @fechaModificacionEsperada = @f2, @motivo = N'Regla cruzada de prueba', @idCorrelacion = @corr, @idUsuarioEjecutor = @admin;
    IF (SELECT COUNT(*) FROM #d3r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=PRM[_]007|%') <> 6
       OR NOT EXISTS (SELECT 1 FROM #d3r WHERE mensajeTecnicoResultado LIKE N'DBCODE=PRM[_]007|%' AND mensajeUsuarioResultado LIKE N'%UMBRAL[_]ALERTA[_]ADVERTENCIA%UMBRAL[_]ALERTA[_]PERDIDA%')
       OR (SELECT valor FROM dbo.CatalogoParametro WHERE id = @pAdv) <> N'15' OR (SELECT valor FROM dbo.CatalogoParametro WHERE id = @pPer) <> N'20'
        THROW 57330, 'TEST FAILED CULM001_D3_07: ADVERTENCIA >= PERDIDA (y la inversa) y MINIMO >= MAXIMO (y la inversa) deben responder PRM_007 sin escribir.', 1;
    TRUNCATE TABLE #d3r;
    SELECT @f = fechaModificacion FROM dbo.CatalogoParametro WHERE id = @pAdv;
    INSERT INTO #d3r EXEC dbo.usp_actualizar_parametro @idParametro = @pAdv, @valor = N'19', @fechaModificacionEsperada = @f, @motivo = N'Regla cruzada valida', @idCorrelacion = @corr, @idUsuarioEjecutor = @admin;
    IF NOT EXISTS (SELECT 1 FROM #d3r WHERE estadoResultado = 1 AND valorNuevo = N'19')
        THROW 57331, 'TEST FAILED CULM001_D3_07: 19 < 20 es valido.', 1;
    TRUNCATE TABLE #d3r;
    PRINT 'TEST_PASS:CULM001_D3_07_REGLA_CRUZADA';

    -- ------------------------------------------------------------------------------------------------------------
    -- D3-08: version antigua o ausente => PRM_008; D3-10: motivo corto => PRM_009; D3-11: valor igual => PRM_011
    -- ------------------------------------------------------------------------------------------------------------
    SELECT @f = fechaModificacion FROM dbo.CatalogoParametro WHERE id = @pTol;
    SET @f2 = DATEADD(MINUTE, -5, @f);
    INSERT INTO #d3r EXEC dbo.usp_actualizar_parametro @idParametro = @pTol, @valor = N'30', @fechaModificacionEsperada = @f2, @motivo = N'Version antigua de prueba', @idCorrelacion = @corr, @idUsuarioEjecutor = @admin;
    INSERT INTO #d3r EXEC dbo.usp_actualizar_parametro @idParametro = @pTol, @valor = N'30', @fechaModificacionEsperada = NULL, @motivo = N'Version ausente de prueba', @idCorrelacion = @corr, @idUsuarioEjecutor = @admin;
    IF (SELECT COUNT(*) FROM #d3r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=PRM[_]008|%') <> 2
       OR (SELECT valor FROM dbo.CatalogoParametro WHERE id = @pTol) <> N'60'
        THROW 57340, 'TEST FAILED CULM001_D3_08: una fechaModificacionEsperada distinta o nula debe responder PRM_008 sin escribir.', 1;
    TRUNCATE TABLE #d3r;
    PRINT 'TEST_PASS:CULM001_D3_08_VERSION_ANTIGUA';

    INSERT INTO #d3r EXEC dbo.usp_actualizar_parametro @idParametro = @pTol, @valor = N'30', @fechaModificacionEsperada = @f, @motivo = N'123456789', @idCorrelacion = @corr, @idUsuarioEjecutor = @admin;
    INSERT INTO #d3r EXEC dbo.usp_actualizar_parametro @idParametro = @pTol, @valor = N'30', @fechaModificacionEsperada = @f, @motivo = N'   12345678   ', @idCorrelacion = @corr, @idUsuarioEjecutor = @admin;
    INSERT INTO #d3r EXEC dbo.usp_actualizar_parametro @idParametro = @pTol, @valor = N'30', @fechaModificacionEsperada = @f, @motivo = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @admin;
    IF (SELECT COUNT(*) FROM #d3r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=PRM[_]009|%' AND mensajeUsuarioResultado LIKE N'%10%') <> 3
       OR (SELECT valor FROM dbo.CatalogoParametro WHERE id = @pTol) <> N'60'
        THROW 57341, 'TEST FAILED CULM001_D3_10: un motivo de menos de 10 caracteres (tras recortar) o nulo debe responder PRM_009.', 1;
    TRUNCATE TABLE #d3r;
    PRINT 'TEST_PASS:CULM001_D3_10_MOTIVO_CORTO';

    DECLARE @historialAntes INT = (SELECT COUNT(*) FROM dbo.CambioParametro WHERE parametro = @pTol);
    INSERT INTO #d3r EXEC dbo.usp_actualizar_parametro @idParametro = @pTol, @valor = N'60', @fechaModificacionEsperada = @f, @motivo = N'Mismo valor de prueba', @idCorrelacion = @corr, @idUsuarioEjecutor = @admin;
    IF NOT EXISTS (SELECT 1 FROM #d3r WHERE estadoResultado = 1 AND mensajeTecnicoResultado LIKE N'DBCODE=PRM[_]011|%' AND valorAnterior = N'60' AND valorNuevo = N'60' AND fechaModificacion = @f)
       OR (SELECT COUNT(*) FROM dbo.CambioParametro WHERE parametro = @pTol) <> @historialAntes
       OR (SELECT fechaModificacion FROM dbo.CatalogoParametro WHERE id = @pTol) <> @f
        THROW 57342, 'TEST FAILED CULM001_D3_11: el mismo valor debe responder PRM_011 con exito, sin historial y sin cambiar fechaModificacion.', 1;
    TRUNCATE TABLE #d3r;
    PRINT 'TEST_PASS:CULM001_D3_11_VALOR_IGUAL';

    -- ------------------------------------------------------------------------------------------------------------
    -- D3-12: solo ADMINISTRADOR (RBAC) en comando y consultas; ejecutor y correlacion obligatorios
    -- ------------------------------------------------------------------------------------------------------------
    INSERT INTO #d3r EXEC dbo.usp_actualizar_parametro @idParametro = @pTol, @valor = N'30', @fechaModificacionEsperada = @f, @motivo = N'Coordinador no puede editar', @idCorrelacion = @corr, @idUsuarioEjecutor = @coord;
    INSERT INTO #d3r EXEC dbo.usp_actualizar_parametro @idParametro = @pTol, @valor = N'30', @fechaModificacionEsperada = @f, @motivo = N'Sin ejecutor no edita', @idCorrelacion = @corr, @idUsuarioEjecutor = NULL;
    INSERT INTO #d3r EXEC dbo.usp_actualizar_parametro @idParametro = @pTol, @valor = N'30', @fechaModificacionEsperada = @f, @motivo = N'Sin correlacion no edita', @idCorrelacion = NULL, @idUsuarioEjecutor = @admin;
    IF (SELECT COUNT(*) FROM #d3r WHERE estadoResultado = 0) <> 3
       OR NOT EXISTS (SELECT 1 FROM #d3r WHERE mensajeTecnicoResultado LIKE N'DBCODE=SEC[_]001|%')
       OR (SELECT valor FROM dbo.CatalogoParametro WHERE id = @pTol) <> N'60'
        THROW 57343, 'TEST FAILED CULM001_D3_12: coordinador, sin ejecutor o sin correlacion no pueden editar (SEC_001 y validaciones previas), sin escribir.', 1;
    TRUNCATE TABLE #d3r;
    SET @err = NULL;
    BEGIN TRY
        EXEC dbo.usp_consultar_parametros_paginado @idUsuarioEjecutor = @coord, @idCorrelacion = @corr, @numeroPagina = 1, @tamanoPagina = 10;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH;
    IF @@TRANCOUNT = 0 THROW 57344, 'TEST FAILED CULM001_D3_12: la consulta rechazada dejo la transaccion de la prueba cerrada.', 1;
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=SEC[_]001|%'
        THROW 57345, 'TEST FAILED CULM001_D3_12: el coordinador no puede consultar parametros (SEC_001 por THROW).', 1;
    PRINT 'TEST_PASS:CULM001_D3_12_RBAC';

    -- ------------------------------------------------------------------------------------------------------------
    -- D3-18: milisegundos .007 (redondeo de DATETIME): la misma fecha enviada de vuelta coincide
    -- ------------------------------------------------------------------------------------------------------------
    UPDATE dbo.CatalogoParametro SET fechaModificacion = '2026-11-07T15:04:05.007' WHERE id = @pMax;
    DECLARE @iso NVARCHAR(30) = (SELECT TOP 1 CONVERT(NVARCHAR(30), fechaModificacion, 126) FROM dbo.CatalogoParametro WHERE id = @pMax);
    IF @iso <> N'2026-11-07T15:04:05.007' THROW 57346, 'TEST FAILED CULM001_D3_18: la fecha de prueba no conserva los milisegundos .007.', 1;
    DECLARE @enviada DATETIME = CAST(CONCAT(@iso, N'Z') AS DATETIME2(3)); -- ida y vuelta por DATETIME2(3) UTC, como el backend
    INSERT INTO #d3r EXEC dbo.usp_actualizar_parametro @idParametro = @pMax, @valor = N'26', @fechaModificacionEsperada = @enviada, @motivo = N'Fecha con milisegundos de prueba', @idCorrelacion = @corr, @idUsuarioEjecutor = @admin;
    IF NOT EXISTS (SELECT 1 FROM #d3r WHERE estadoResultado = 1 AND valorNuevo = N'26')
        THROW 57347, 'TEST FAILED CULM001_D3_18: la fecha .007 enviada de vuelta debe coincidir con la almacenada.', 1;
    TRUNCATE TABLE #d3r;
    PRINT 'TEST_PASS:CULM001_D3_18_MILISEGUNDOS_007';

    -- ------------------------------------------------------------------------------------------------------------
    -- D3-13: consulta paginada de parametros: sin tecnicos con soloEditables, filtros y paginacion (PAG_001)
    -- ------------------------------------------------------------------------------------------------------------
    CREATE TABLE #d3p (id UNIQUEIDENTIFIER, grupo VARCHAR(100), clave VARCHAR(100), valor NVARCHAR(MAX), valorDefecto NVARCHAR(MAX), tipoDato VARCHAR(20),
        esEditable BIT, valorMinimo DECIMAL(19,4), valorMaximo DECIMAL(19,4), valoresPermitidos NVARCHAR(500), etiqueta NVARCHAR(120), descripcion NVARCHAR(500),
        unidad NVARCHAR(30), categoriaVisual NVARCHAR(60), orden SMALLINT, fechaModificacion DATETIME, fechaUltimoCambioUtc DATETIME2(7), nombreUltimoActor NVARCHAR(400),
        esGrupoProtegido BIT, totalRegistros INT);
    SET @corr = NEWID();
    INSERT INTO #d3p EXEC dbo.usp_consultar_parametros_paginado @idUsuarioEjecutor = @admin, @idCorrelacion = @corr, @numeroPagina = 1, @tamanoPagina = 100, @soloEditables = 1;
    IF NOT EXISTS (SELECT 1 FROM #d3p) OR EXISTS (SELECT 1 FROM #d3p WHERE esEditable = 0 OR esGrupoProtegido = 1 OR grupo IN ('RED', 'TIEMPO'))
       OR NOT EXISTS (SELECT 1 FROM #d3p WHERE id = @pTol AND etiqueta IS NOT NULL AND LEN(etiqueta) > 0 AND unidad = N'minutos' AND valorMinimo = 0 AND valorMaximo = 60 AND nombreUltimoActor IS NOT NULL AND fechaUltimoCambioUtc IS NOT NULL)
       OR (SELECT MIN(totalRegistros) FROM #d3p) <> (SELECT COUNT(*) FROM #d3p)
        THROW 57350, 'TEST FAILED CULM001_D3_13: soloEditables = 1 no debe devolver tecnicos ni protegidos; debe exponer etiqueta, unidad, rango y ultimo cambio.', 1;
    TRUNCATE TABLE #d3p;
    INSERT INTO #d3p EXEC dbo.usp_consultar_parametros_paginado @idUsuarioEjecutor = @admin, @idCorrelacion = @corr, @numeroPagina = 1, @tamanoPagina = 100, @soloEditables = 0;
    IF NOT EXISTS (SELECT 1 FROM #d3p WHERE grupo = 'RED' AND esEditable = 0 AND esGrupoProtegido = 1) OR NOT EXISTS (SELECT 1 FROM #d3p WHERE grupo = 'SESION' AND esEditable = 0)
        THROW 57351, 'TEST FAILED CULM001_D3_13: soloEditables = 0 debe listar tambien los tecnicos de solo lectura.', 1;
    TRUNCATE TABLE #d3p;
    INSERT INTO #d3p EXEC dbo.usp_consultar_parametros_paginado @idUsuarioEjecutor = @admin, @idCorrelacion = @corr, @numeroPagina = 1, @tamanoPagina = 100, @grupo = 'MATRICULA_QR', @soloEditables = 1;
    IF NOT EXISTS (SELECT 1 FROM #d3p) OR EXISTS (SELECT 1 FROM #d3p WHERE grupo <> 'MATRICULA_QR')
        THROW 57352, 'TEST FAILED CULM001_D3_13: el filtro por grupo solo devuelve ese grupo.', 1;
    TRUNCATE TABLE #d3p;
    INSERT INTO #d3p EXEC dbo.usp_consultar_parametros_paginado @idUsuarioEjecutor = @admin, @idCorrelacion = @corr, @numeroPagina = 1, @tamanoPagina = 100, @texto = N'TOLERANCIA_MINUTOS', @soloEditables = 1;
    IF NOT EXISTS (SELECT 1 FROM #d3p WHERE id = @pTol) OR EXISTS (SELECT 1 FROM #d3p WHERE grupo = 'FESTIVOS')
        THROW 57353, 'TEST FAILED CULM001_D3_13: el filtro de texto debe encontrar ASISTENCIA/TOLERANCIA_MINUTOS y no parametros ajenos.', 1;
    TRUNCATE TABLE #d3p;
    INSERT INTO #d3p EXEC dbo.usp_consultar_parametros_paginado @idUsuarioEjecutor = @admin, @idCorrelacion = @corr, @numeroPagina = 2, @tamanoPagina = 3, @soloEditables = 1;
    IF (SELECT COUNT(*) FROM #d3p) <> 3 OR (SELECT MIN(totalRegistros) FROM #d3p) <= 6
        THROW 57354, 'TEST FAILED CULM001_D3_13: la pagina 2 de tamano 3 devuelve 3 filas con totalRegistros mayor a 6.', 1;
    TRUNCATE TABLE #d3p;
    -- Paginacion invalida => PAG_001 (THROW)
    SET @err = NULL;
    BEGIN TRY
        INSERT INTO #d3p EXEC dbo.usp_consultar_parametros_paginado @idUsuarioEjecutor = @admin, @idCorrelacion = @corr, @numeroPagina = 1, @tamanoPagina = 101;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH;
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=PAG[_]001|%' OR EXISTS (SELECT 1 FROM #d3p)
        THROW 57355, 'TEST FAILED CULM001_D3_13: un tamano de pagina mayor a PAGINACION/TAMANO_MAXIMO debe responder PAG_001.', 1;
    IF @@TRANCOUNT = 0 THROW 57356, 'TEST FAILED CULM001_D3_13: el THROW de la consulta cerro la transaccion de la prueba.', 1;
    DROP TABLE #d3p;
    PRINT 'TEST_PASS:CULM001_D3_13_CONSULTA_PAGINADA';

    -- Historial paginado (diferible, ya implementado): del mas reciente al mas antiguo, con ejecutor y motivo
    CREATE TABLE #d3c (id UNIQUEIDENTIFIER, idParametro UNIQUEIDENTIFIER, grupo VARCHAR(100), clave VARCHAR(100), valorAnterior NVARCHAR(4000), valorNuevo NVARCHAR(4000),
        motivo NVARCHAR(500), idUsuarioEjecutor UNIQUEIDENTIFIER, nombreEjecutor NVARCHAR(400), idCorrelacion UNIQUEIDENTIFIER, fechaCambioUtc DATETIME2(7), totalRegistros INT);
    INSERT INTO #d3c EXEC dbo.usp_consultar_cambios_parametro_paginado @idUsuarioEjecutor = @admin, @idCorrelacion = @corr, @idParametro = @pTol, @numeroPagina = 1, @tamanoPagina = 10;
    IF (SELECT COUNT(*) FROM #d3c) < 2 OR NOT EXISTS (SELECT 1 FROM #d3c WHERE motivo = N'Ajuste de prueba D3-01' AND valorAnterior = N'15' AND valorNuevo = N'20' AND idUsuarioEjecutor = @admin AND nombreEjecutor IS NOT NULL)
       OR (SELECT TOP 1 valorNuevo FROM #d3c ORDER BY fechaCambioUtc DESC) <> N'60'
        THROW 57357, 'TEST FAILED CULM001_D3_13: el historial del parametro debe listar los cambios con motivo y ejecutor, del mas reciente al mas antiguo.', 1;
    DROP TABLE #d3c;
    PRINT 'TEST_PASS:CULM001_D3_13_HISTORIAL_PAGINADO';

    -- ------------------------------------------------------------------------------------------------------------
    -- D3-17: mas de una Institucion activa => PRM_012 en el comando y THROW en las consultas; sin escritura
    -- ------------------------------------------------------------------------------------------------------------
    INSERT INTO dbo.Institucion (id, nombre, estado) VALUES (NEWID(), N'CULM1 D3 segunda', 1);
    SELECT @f = fechaModificacion FROM dbo.CatalogoParametro WHERE id = @pTol;
    INSERT INTO #d3r EXEC dbo.usp_actualizar_parametro @idParametro = @pTol, @valor = N'30', @fechaModificacionEsperada = @f, @motivo = N'Dos instituciones activas', @idCorrelacion = @corr, @idUsuarioEjecutor = @admin;
    IF NOT EXISTS (SELECT 1 FROM #d3r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=PRM[_]012|%') OR (SELECT valor FROM dbo.CatalogoParametro WHERE id = @pTol) <> N'60'
        THROW 57360, 'TEST FAILED CULM001_D3_17: con dos instituciones activas el comando debe responder PRM_012 sin escribir.', 1;
    TRUNCATE TABLE #d3r;
    SET @err = NULL;
    CREATE TABLE #d3p2 (id UNIQUEIDENTIFIER, grupo VARCHAR(100), clave VARCHAR(100), valor NVARCHAR(MAX), valorDefecto NVARCHAR(MAX), tipoDato VARCHAR(20),
        esEditable BIT, valorMinimo DECIMAL(19,4), valorMaximo DECIMAL(19,4), valoresPermitidos NVARCHAR(500), etiqueta NVARCHAR(120), descripcion NVARCHAR(500),
        unidad NVARCHAR(30), categoriaVisual NVARCHAR(60), orden SMALLINT, fechaModificacion DATETIME, fechaUltimoCambioUtc DATETIME2(7), nombreUltimoActor NVARCHAR(400),
        esGrupoProtegido BIT, totalRegistros INT);
    BEGIN TRY
        INSERT INTO #d3p2 EXEC dbo.usp_consultar_parametros_paginado @idUsuarioEjecutor = @admin, @idCorrelacion = @corr, @numeroPagina = 1, @tamanoPagina = 10;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH;
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=PRM[_]012|%' OR EXISTS (SELECT 1 FROM #d3p2)
        THROW 57361, 'TEST FAILED CULM001_D3_17: con dos instituciones activas la consulta debe fallar con PRM_012 y sin filas.', 1;
    DROP TABLE #d3p2;
    PRINT 'TEST_PASS:CULM001_D3_17_DOS_INSTITUCIONES';

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    DECLARE @msg NVARCHAR(4000) = ERROR_MESSAGE(), @num INT = ERROR_NUMBER();
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    IF @num BETWEEN 57300 AND 57399 THROW 57399, @msg, 1;
    SET @msg = CONCAT(N'TEST FAILED CULM001_D3: error inesperado ', @num, N': ', @msg);
    THROW 57398, @msg, 1;
END CATCH;
IF @@TRANCOUNT <> 0 THROW 57397, 'TEST FAILED CULM001_D3: la prueba dejo una transaccion abierta.', 1;
PRINT 'TEST_PASS:CULM001_D3_TRANCOUNT_ZERO';
PRINT 'TEST END: test_culm001_d3_parametros';
GO

-- D3-SEG: permisos del rol runtime (EXECUTE en los 3 SP publicos, SELECT en las vistas) y sin acceso a las tablas
DECLARE @faltantes NVARCHAR(MAX) = (
    SELECT STRING_AGG(o.nombre, N',') FROM (VALUES (N'usp_actualizar_parametro'), (N'usp_consultar_parametros_paginado'), (N'usp_consultar_cambios_parametro_paginado')) o(nombre)
    WHERE NOT EXISTS (SELECT 1 FROM sys.database_permissions dp WHERE dp.major_id = OBJECT_ID(N'dbo.' + o.nombre) AND dp.permission_name = N'EXECUTE'
                      AND dp.state IN ('G', 'W') AND dp.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime')));
IF @faltantes IS NOT NULL
BEGIN
    DECLARE @fallo NVARCHAR(2048) = CONCAT(N'TEST FAILED CULM001_D3_SEG_01: SP publicos de D.3 sin EXECUTE: ', @faltantes);
    THROW 57370, @fallo, 1;
END
IF EXISTS (SELECT 1 FROM sys.database_permissions dp WHERE dp.major_id IN (OBJECT_ID(N'dbo.CatalogoParametroEdicion'), OBJECT_ID(N'dbo.CambioParametro'))
           AND dp.state IN ('G', 'W') AND dp.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime'))
    THROW 57371, 'TEST FAILED CULM001_D3_SEG_01: el rol runtime no debe tener permisos directos sobre CatalogoParametroEdicion ni CambioParametro.', 1;
PRINT 'TEST_PASS:CULM001_D3_SEG_01_PERMISOS';
GO
