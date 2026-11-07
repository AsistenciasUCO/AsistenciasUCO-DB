USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.3 (CONTRACT v2 §4.2, [SUPUESTO-D-03], HU168): lista blanca inicial de parametros editables por el administrador,
-- con rango, valores permitidos, regla cruzada estricta y presentacion. MERGE por (grupo, clave) contra CatalogoParametro:
-- solo se siembran filas de parametros que existen (los de D.2 y D.5, ARCHIVOS/MAXIMO_SOPORTES_POR_RECLAMO y CARGA_MASIVA/*,
-- entran cuando esos paquetes siembran su parametro y se vuelve a desplegar). Los parametros que NO aparecen aqui (RED,
-- TIEMPO, URL y secretos de festivos, estados, lotes, URL base del frontend, codigos de razon, etc.) no tienen fila y por tanto
-- no son editables. Los grupos de PARAMETROS/GRUPOS_NO_EDITABLES tampoco lo son aunque tuvieran fila.
-- Re-desplegar actualiza la regla y la presentacion (son codigo), nunca el valor del parametro.
MERGE INTO [dbo].[CatalogoParametroEdicion] AS Target
USING (
    SELECT  p.id AS parametro, v.esEditable, v.valorMinimo, v.valorMaximo, v.valoresPermitidos, m.id AS parametroDebeSerMenorQue,
            v.etiqueta, v.descripcion, v.unidad, v.categoriaVisual, v.orden
    FROM (VALUES
        ('ASISTENCIA',    'TOLERANCIA_MINUTOS',                   CONVERT(BIT, 1), CONVERT(DECIMAL(19,4), 0),      CONVERT(DECIMAL(19,4), 60),      NULL,                 NULL, NULL,
            N'Tolerancia de apertura', N'Minutos antes del inicio de la sesión en que ya se puede registrar asistencia.', N'minutos', N'Asistencia', CONVERT(SMALLINT, 10)),
        ('ASISTENCIA',    'MARGEN_RETARDO_MINUTOS',               1, 0,      120,     NULL,                 NULL, NULL,
            N'Margen de retardo', N'Minutos después del fin de la sesión en que todavía se puede registrar asistencia.', N'minutos', N'Asistencia', 20),
        ('ASISTENCIA',    'DIAS_LIMITE_JUSTIFICACION',            1, 1,      30,      NULL,                 NULL, NULL,
            N'Plazo para justificar', N'Días calendario, desde el fin de la sesión, en que el estudiante puede radicar una excusa.', N'días', N'Asistencia', 30),
        ('ASISTENCIA',    'UMBRAL_ALERTA_ADVERTENCIA',            1, 1,      99,      NULL,                 'ASISTENCIA', 'UMBRAL_ALERTA_PERDIDA',
            N'Umbral de advertencia', N'Porcentaje de inasistencia desde el cual el estudiante queda en riesgo. Debe ser menor que el umbral de pérdida.', N'%', N'Asistencia', 40),
        ('ASISTENCIA',    'UMBRAL_ALERTA_PERDIDA',                1, 1,      100,     NULL,                 NULL, NULL,
            N'Umbral de pérdida', N'Porcentaje de inasistencia desde el cual el estudiante pierde la asignatura.', N'%', N'Asistencia', 50),
        ('MATRICULA_QR',  'HABILITADA',                           1, NULL,   NULL,    N'true,false',        NULL, NULL,
            N'Matrícula por QR habilitada', N'Permite o suspende la matrícula de estudiantes por código QR.', NULL, N'Matrícula por QR', 10),
        ('MATRICULA_QR',  'ROTACION_SEGUNDOS',                    1, 15,     300,     NULL,                 NULL, NULL,
            N'Rotación del código QR de matrícula', N'Cada cuántos segundos cambia el código QR de matrícula.', N'segundos', N'Matrícula por QR', 20),
        ('MATRICULA_QR',  'TOLERANCIA_SEGUNDOS',                  1, 0,      300,     NULL,                 NULL, NULL,
            N'Tolerancia del código QR de matrícula', N'Segundos en que el código anterior sigue siendo válido tras rotar.', N'segundos', N'Matrícula por QR', 30),
        ('MATRICULA_QR',  'DURACION_MAXIMA_MINUTOS',              1, 5,      240,     NULL,                 NULL, NULL,
            N'Duración máxima de la ventana de matrícula', N'Minutos máximos que puede estar abierta una ventana de matrícula por QR.', N'minutos', N'Matrícula por QR', 40),
        ('MATRICULA_QR',  'LIMITE_IP_POR_MINUTO',                 1, 5,      1000,    NULL,                 NULL, NULL,
            N'Límite por IP en matrícula', N'Solicitudes por minuto permitidas desde una misma IP al validar o usar el código de matrícula.', N'por minuto', N'Matrícula por QR', 50),
        ('MATRICULA_QR',  'LIMITE_REGISTROS_TOKEN_POR_MINUTO',    1, 1,      200,     NULL,                 NULL, NULL,
            N'Límite de registros por código', N'Matrículas por minuto permitidas con un mismo código QR.', N'por minuto', N'Matrícula por QR', 60),
        ('ASISTENCIA_QR', 'HABILITADA',                           1, NULL,   NULL,    N'true,false',        NULL, NULL,
            N'Asistencia por QR habilitada', N'Permite o suspende el registro de asistencia por código QR o PIN.', NULL, N'Asistencia por QR', 10),
        ('ASISTENCIA_QR', 'ROTACION_SEGUNDOS',                    1, 15,     300,     NULL,                 NULL, NULL,
            N'Rotación del código QR de asistencia', N'Cada cuántos segundos cambia el código QR de asistencia.', N'segundos', N'Asistencia por QR', 20),
        ('ASISTENCIA_QR', 'TOLERANCIA_SEGUNDOS',                  1, 0,      300,     NULL,                 NULL, NULL,
            N'Tolerancia del código QR de asistencia', N'Segundos en que el código anterior sigue siendo válido tras rotar.', N'segundos', N'Asistencia por QR', 30),
        ('ASISTENCIA_QR', 'LIMITE_IP_POR_MINUTO',                 1, 5,      1000,    NULL,                 NULL, NULL,
            N'Límite por IP en asistencia', N'Solicitudes por minuto permitidas desde una misma IP al registrar asistencia por QR.', N'por minuto', N'Asistencia por QR', 40),
        ('ASISTENCIA_QR', 'LIMITE_FALLIDOS_IP_POR_MINUTO',        1, 50,     5000,    NULL,                 NULL, NULL,
            N'Límite de intentos fallidos por IP', N'Intentos fallidos por minuto permitidos desde una misma IP antes de bloquearla.', N'por minuto', N'Asistencia por QR', 50),
        ('ASISTENCIA_QR', 'LIMITE_TOKEN_POR_MINUTO',              1, 10,     2000,    NULL,                 NULL, NULL,
            N'Límite por código de asistencia', N'Registros por minuto permitidos con un mismo código QR de asistencia.', N'por minuto', N'Asistencia por QR', 60),
        ('ASISTENCIA_QR', 'LIMITE_ESTUDIANTE_POR_MINUTO',         1, 1,      60,      NULL,                 NULL, NULL,
            N'Límite por estudiante', N'Intentos por minuto permitidos a un mismo estudiante al registrar asistencia por QR.', N'por minuto', N'Asistencia por QR', 70),
        ('FESTIVOS',      'HABILITADO',                           1, NULL,   NULL,    N'true,false',        NULL, NULL,
            N'Carga automática de festivos', N'Activa o suspende el job que carga los días festivos y cancela las sesiones de esos días.', NULL, N'Días festivos', 10),
        ('FESTIVOS',      'PROVEEDOR_PRINCIPAL',                  1, NULL,   NULL,    N'CALENDARIOS_NACIONALES,FERIADOS_IO,CALCULO_LOCAL', NULL, NULL,
            N'Proveedor principal de festivos', N'Fuente que se consulta primero para obtener los festivos del año.', NULL, N'Días festivos', 20),
        ('FESTIVOS',      'TIMEOUT_SEGUNDOS',                     1, 1,      60,      NULL,                 NULL, NULL,
            N'Tiempo de espera del proveedor', N'Segundos máximos de espera al consultar el proveedor de festivos.', N'segundos', N'Días festivos', 30),
        ('FESTIVOS',      'ANIOS_ADELANTE',                       1, 0,      3,       NULL,                 NULL, NULL,
            N'Años por adelantado', N'Cuántos años futuros se cargan además del año actual.', N'años', N'Días festivos', 40),
        ('FESTIVOS',      'MINIMO_POR_ANIO',                      1, 10,     30,      NULL,                 'FESTIVOS', 'MAXIMO_POR_ANIO',
            N'Mínimo de festivos por año', N'Cantidad mínima de festivos para considerar válida una carga anual. Debe ser menor que el máximo.', N'festivos', N'Días festivos', 50),
        ('FESTIVOS',      'MAXIMO_POR_ANIO',                      1, 10,     40,      NULL,                 NULL, NULL,
            N'Máximo de festivos por año', N'Cantidad máxima de festivos para considerar válida una carga anual.', N'festivos', N'Días festivos', 60),
        ('ARCHIVO',       'TAMANIO_MAXIMO_BYTES',                 1, 262144, 5242880, NULL,                 NULL, NULL,
            N'Tamaño máximo de un soporte', N'Bytes máximos de cada archivo de soporte de un reclamo. No supera el límite de carga del servidor.', N'bytes', N'Soportes', 10),
        ('ARCHIVOS',      'LIMITE_SUBIDAS_POR_MINUTO',            1, 1,      60,      NULL,                 NULL, NULL,
            N'Límite de subidas por minuto', N'Archivos por minuto que puede subir un mismo usuario.', N'por minuto', N'Soportes', 20),
        ('ARCHIVOS',      'MAXIMO_SOPORTES_POR_RECLAMO',          1, 1,      10,      NULL,                 NULL, NULL,
            N'Máximo de soportes por reclamo', N'Cantidad máxima de archivos de soporte en un mismo reclamo.', N'soportes', N'Soportes', 30),
        ('CARGA_MASIVA',  'MAXIMO_FILAS',                         1, 1,      500,     NULL,                 NULL, NULL,
            N'Máximo de filas por carga', N'Filas máximas de un archivo de carga masiva de cuentas.', N'filas', N'Carga masiva', 10),
        ('CARGA_MASIVA',  'LIMITE_POR_MINUTO',                    1, 1,      20,      NULL,                 NULL, NULL,
            N'Límite de cargas por minuto', N'Cargas masivas por minuto permitidas a un mismo usuario.', N'por minuto', N'Carga masiva', 20),
        ('CARGA_MASIVA',  'TAMANIO_MAXIMO_BYTES',                 1, 10240,  2097152, NULL,                 NULL, NULL,
            N'Tamaño máximo del archivo de carga', N'Bytes máximos del archivo CSV de una carga masiva.', N'bytes', N'Carga masiva', 30)
    ) AS v (grupo, clave, esEditable, valorMinimo, valorMaximo, valoresPermitidos, grupoMenor, claveMenor, etiqueta, descripcion, unidad, categoriaVisual, orden)
    INNER JOIN [dbo].[CatalogoParametro] p ON p.grupo = v.grupo AND p.clave = v.clave
    LEFT JOIN [dbo].[CatalogoParametro] m ON m.grupo = v.grupoMenor AND m.clave = v.claveMenor
) AS Source
ON (Target.parametro = Source.parametro)
WHEN MATCHED THEN
    UPDATE SET Target.esEditable = Source.esEditable, Target.valorMinimo = Source.valorMinimo, Target.valorMaximo = Source.valorMaximo,
               Target.valoresPermitidos = Source.valoresPermitidos, Target.parametroDebeSerMenorQue = Source.parametroDebeSerMenorQue,
               Target.etiqueta = Source.etiqueta, Target.descripcion = Source.descripcion, Target.unidad = Source.unidad,
               Target.categoriaVisual = Source.categoriaVisual, Target.orden = Source.orden
WHEN NOT MATCHED THEN
    INSERT (parametro, esEditable, valorMinimo, valorMaximo, valoresPermitidos, parametroDebeSerMenorQue, etiqueta, descripcion, unidad, categoriaVisual, orden)
    VALUES (Source.parametro, Source.esEditable, Source.valorMinimo, Source.valorMaximo, Source.valoresPermitidos, Source.parametroDebeSerMenorQue,
            Source.etiqueta, Source.descripcion, Source.unidad, Source.categoriaVisual, Source.orden);
GO
