USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- 14_culm001_a_correcciones_fase1_up.sql (CULM-001 paquete A.2, CONTRACT §8.2; DEC-028)
-- Correcciones criticas y altas de la Fase 1 en BD: ambito en SP del directorio y de las listas del grupo (A.2-1/2),
-- materias y horario solo con matricula A (A.2-11), solape de sesiones (A.2-10), retiro del reclamo propio (A.2-7),
-- estado del decano con efecto en el RBAC (A.2-8), busqueda por documento (A.2-15, DEC-027), semillas 33 y grants.
-- Se aplica DESPUES de 13_culm001_a_retiro_solicitudes_up.sql. deploy_schema.ps1 no borra objetos. Idempotente.
-- Orden (bloqueante 2 de REVIEW-3, inverso del down): primero la columna Decano.estado, despues las vistas filtradas.
-- Los cuerpos son copias exactas de schema/ (T-13 ampliado; lineas PARIDAD para test_migracion_13_culm001_a.ps1):
-- PARIDAD: usp_validar_solape_sesion_interno schema/stored-procedures/usp_validar_solape_sesion_interno.sql
-- PARIDAD: usp_crear_sesion_interno schema/stored-procedures/usp_crear_sesion_interno.sql
-- PARIDAD: usp_actualizar_sesion_interno schema/stored-procedures/usp_actualizar_sesion_interno.sql
-- PARIDAD: usp_resolver_facultad_decano_interno schema/stored-procedures/usp_resolver_facultad_decano_interno.sql
-- PARIDAD: usp_consultar_directorio_estudiantes_paginado schema/stored-procedures/usp_consultar_directorio_estudiantes_paginado.sql
-- PARIDAD: usp_consultar_estudiantes_grupo_ambito_paginado schema/stored-procedures/usp_consultar_estudiantes_grupo_ambito_paginado.sql
-- PARIDAD: usp_consultar_asistencias_grupo_ambito_paginado schema/stored-procedures/usp_consultar_asistencias_grupo_ambito_paginado.sql
-- PARIDAD: usp_consultar_materias_estudiante schema/stored-procedures/usp_consultar_materias_estudiante.sql
-- PARIDAD: usp_consultar_horario_estudiante schema/stored-procedures/usp_consultar_horario_estudiante.sql
-- PARIDAD: usp_retirar_solicitud_revision_asistencia schema/stored-procedures/usp_retirar_solicitud_revision_asistencia.sql
-- PARIDAD: usp_cambiar_estado_decano schema/stored-procedures/usp_cambiar_estado_decano.sql
-- PARIDAD: usp_buscar_estudiante_por_documento_grupo schema/stored-procedures/usp_buscar_estudiante_por_documento_grupo.sql
-- PARIDAD: uv_decano schema/views/uv_decano.sql
-- PARIDAD: uv_usuario_perfil schema/views/uv_usuario_perfil.sql
-- Rollback: 14_culm001_a_correcciones_fase1_down.sql.
-- ============================================================================

-- U14-1: columna Decano.estado (A2-C5).
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Decano]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Decano] (
    [id] uniqueidentifier NOT NULL,
    [usuario] uniqueidentifier NOT NULL
);

ALTER TABLE [dbo].[Decano] ADD CONSTRAINT [PK_Decano] PRIMARY KEY CLUSTERED ([id]);
END
GO

-- CULM-001 A.2-8 (A2-C5, F-ADM-002): estado propio del rol de decano, mismo patron que Coordinador (HU121/HU122).
-- Las filas existentes quedan activas.
IF COL_LENGTH('dbo.Decano', 'estado') IS NULL
BEGIN
    ALTER TABLE [dbo].[Decano] ADD [estado] bit NOT NULL CONSTRAINT [DF_Decano_estado] DEFAULT (1);
END
GO

-- U14-2: vistas filtradas por Decano.estado.
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER    VIEW [dbo].[uv_decano]
AS
SELECT		di.id,
			di.idUsuario,
			di.numeroIdentificacion,
			di.nombreCompleto,
			di.estaActivoUsuario,			
			idInstitucion = f.idInstitucion,
			nombreInstitucion = f.nombreInstitucion,
			idFacultad = f.id,
			nombreFacultad = f.nombreFacultad,
			idPerfil = p.id,
			codigoPerfil = p.codigo,
			nombrePerfil = p.nombre,
			-- CULM-001 A.2-8 (A2-C5): el estado propio del rol (Decano.estado) tambien cuenta.
			estaActivoDecano = IIF(di.estaActivoUsuario = 1 AND d.estado = 1 AND (f.id IS NULL OR f.estaActivaFacultad = 1), 1, 0),
			estaActivoTextoDecano = IIF(di.estaActivoUsuario = 1 AND d.estado = 1 AND (f.id IS NULL OR f.estaActivaFacultad = 1), 'SI', 'NO')

FROM		uv_decano_identidad di
INNER JOIN	Decano d
ON			d.id = di.id
LEFT JOIN   uv_facultad f 
ON			di.id = f.idDecano
CROSS JOIN	(SELECT TOP 1 id, codigo, nombre FROM uv_perfil WHERE codigo = 'DE') p
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER  VIEW [dbo].[uv_usuario_perfil]
AS
SELECT		idUsuario = a.usuario,
			idPerfil = p.id,
			codigoPerfil = p.codigo,
			nombrePerfil = p.nombre,
			estado = IIF(u.estado = 1, 1, 0)
FROM		Administrador a
INNER JOIN	Usuario u
ON			a.usuario = u.id
CROSS JOIN	(SELECT TOP 1 id, codigo, nombre FROM Perfil WHERE codigo = 'AD') p

UNION

SELECT		idUsuario = d.usuario,
			idPerfil = p.id,
			codigoPerfil = p.codigo,
			nombrePerfil = p.nombre,
			estado = IIF(u.estado = 1, 1, 0)
FROM		Decano d
INNER JOIN	Usuario u
ON			d.usuario = u.id
CROSS JOIN	(SELECT TOP 1 id, codigo, nombre FROM Perfil WHERE codigo = 'DE') p
-- CULM-001 A.2 (D1, como HU121/HU122): un rol de decano inactivo deja de figurar como perfil (RBAC y roles activos)
WHERE		d.estado = 1

UNION

SELECT		idUsuario = c.usuario,
			idPerfil = p.id,
			codigoPerfil = p.codigo,
			nombrePerfil = p.nombre,
			estado = IIF(u.estado = 1, 1, 0)
FROM		Coordinador c
INNER JOIN	Usuario u
ON			c.usuario = u.id
CROSS JOIN	(SELECT TOP 1 id, codigo, nombre FROM Perfil WHERE codigo = 'CD') p
-- HU121/HU122 (D1): un rol de coordinador inactivo deja de figurar como perfil (RBAC y roles activos)
WHERE		c.estado = 1

UNION

SELECT		idUsuario = d.usuario,
			idPerfil = p.id,
			codigoPerfil = p.codigo,
			nombrePerfil = p.nombre,
			estado = IIF(u.estado = 1, 1, 0)
FROM		Docente d
INNER JOIN	Usuario u
ON			d.usuario = u.id
CROSS JOIN	(SELECT TOP 1 id, codigo, nombre FROM Perfil WHERE codigo = 'DO') p

UNION

SELECT		idUsuario = e.usuario,
			idPerfil = p.id,
			codigoPerfil = p.codigo,
			nombrePerfil = p.nombre,
			estado = IIF(u.estado = 1, 1, 0)
FROM		Estudiante e
INNER JOIN	Usuario u
ON			e.usuario = u.id
CROSS JOIN	(SELECT TOP 1 id, codigo, nombre FROM Perfil WHERE codigo = 'ES') p
GO

-- U14-3: semillas 33 de A (parametros A.1 + A.2 y mensajes de A.2).
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 paquete A (numeracion 33 de A; idempotente).
-- A.1 (A-C4, N10): codigos de uv_estado_estudiante_grupo que leen los SP de matricula sin literales quemados:
--   MATRICULA/ESTADO_RETIRADA = I (matricula retirada por el docente, HU051; la reactivan la matricula manual y el QR).
--   MATRICULA/ESTADO_INSCRITA = A (unica matricula que cuenta como inscrita: oferta, materias, horario).
-- A.2 (A2-DB-5; valor = valor por defecto en codigo del backend, DEC-018; se administran en GET /admin/parametros):
--   ARCHIVOS/LIMITE_SUBIDAS_POR_MINUTO = 10, ASISTENCIA_QR/LIMITE_IP_POR_MINUTO = 20 y
--   ASISTENCIA_QR/LIMITE_ESTUDIANTE_POR_MINUTO = 5 (A.2-4, limites de intentos); RECLAMO/ESTADO_PENDIENTE = P y
--   RECLAMO/ESTADO_RETIRADO = X (A.2-7, retiro del reclamo propio; codigos de dbo.Estado).
MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    ('MATRICULA',     'ESTADO_RETIRADA',              N'I',  'STRING', N'I'),
    ('MATRICULA',     'ESTADO_INSCRITA',              N'A',  'STRING', N'A'),
    ('ARCHIVOS',      'LIMITE_SUBIDAS_POR_MINUTO',    N'10', 'INT',    N'10'),
    ('ASISTENCIA_QR', 'LIMITE_IP_POR_MINUTO',         N'20', 'INT',    N'20'),
    ('ASISTENCIA_QR', 'LIMITE_ESTUDIANTE_POR_MINUTO', N'5',  'INT',    N'5'),
    ('RECLAMO',       'ESTADO_PENDIENTE',             N'P',  'STRING', N'P'),
    ('RECLAMO',       'ESTADO_RETIRADO',              N'X',  'STRING', N'X')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET Target.tipoDato = Source.tipoDato, Target.valorDefecto = Source.valorDefecto, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

-- A-C3 revisada: el estado X (retirada) de dbo.Estado se conserva (antes en el seed 22, borrado con HU053-HU055) porque
-- A.2-7 lo reutiliza para el reclamo retirado por el estudiante (A2-C4). El estado E (en espera) se retira.
MERGE INTO [dbo].[Estado] AS Target
USING (VALUES
    ('D6E2F3A4-5B6C-4D7E-9F80-A12B3C4D5E6F', 'retirada', 'X')
) AS Source (id, nombre, codigo)
ON (Target.id = TRY_CAST(Source.id AS UNIQUEIDENTIFIER) OR Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.nombre = Source.nombre, Target.codigo = Source.codigo
WHEN NOT MATCHED THEN
    INSERT (id, nombre, codigo)
    VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), Source.nombre, Source.codigo);
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 paquete A.2 (A2-DB-6; numeracion 33 de A; idempotente): mensajes de usuario y tecnicos.
-- Rango de sesion de A (DEC-031 §1): B ocupa SES_010..SES_016, A usa SES_017 en adelante y C usara SES_030 en adelante.
--   SES_017 solape de sesiones (A.2-10)       REV_006..REV_008 retiro del reclamo propio (A.2-7)
--   DEC_002/DEC_003 cambio de estado del decano (A.2-8)
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('SES_017', 'BUSINESS_ERROR', 'MEDIO', N'La sesión se cruza con otra sesión del grupo o del docente en ese horario.'),
    ('REV_006', 'BUSINESS_ERROR', 'MEDIO', N'La solicitud de revisión no existe.'),
    ('REV_007', 'BUSINESS_ERROR', 'MEDIO', N'Solo se puede retirar una solicitud de revisión pendiente.'),
    ('REV_008', 'SUCCESS',        'BAJO',  N'La solicitud de revisión fue retirada.'),
    ('DEC_002', 'BUSINESS_ERROR', 'ALTO',  N'No se puede desactivar al decano de una facultad con programas activos.'),
    ('DEC_003', 'SUCCESS',        'BAJO',  N'Se actualizó el estado del decano.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

MERGE INTO [dbo].[CatalogoMensajeTecnico] AS Target
USING (VALUES
    ('SES_017', 'BUSINESS_ERROR', 'MEDIO', N'Regla: la sesion se cruza con la sesion [{}] del mismo grupo o de otro grupo del mismo docente (inicio < fin y fin > inicio); sin escrituras.'),
    ('REV_006', 'BUSINESS_ERROR', 'MEDIO', N'Ambito: la solicitud de revision [{}] no existe o no es del estudiante ejecutor; sin escrituras.'),
    ('REV_007', 'BUSINESS_ERROR', 'MEDIO', N'Regla: la solicitud de revision [{}] no esta en el estado de RECLAMO/ESTADO_PENDIENTE; sin escrituras.'),
    ('REV_008', 'SUCCESS',        'BAJO',  N'Actualizacion: la solicitud de revision [{}] paso al estado de RECLAMO/ESTADO_RETIRADO.'),
    ('DEC_002', 'BUSINESS_ERROR', 'ALTO',  N'Regla: el decano [{}] dirige una facultad con el programa activo [{}]; no se desactiva.'),
    ('DEC_003', 'SUCCESS',        'BAJO',  N'Actualizacion: Decano.estado del decano [{}] actualizado (regla D1 aplicada a Usuario.estado).')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

-- U14-4: procedimientos (internos y publicos), copias exactas de schema/.
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_validar_solape_sesion_interno (CULM-001 A.2-10; F-DOC-017; CONTRACT §8.2.3 A2-DB-2)
--
-- Interno (DENY EXECUTE al runtime). Rechaza con SES_017 una sesion [@fechaHoraInicio, @fechaHoraFin) que se cruce con
-- otra sesion (s.fechaHoraInicio < @fechaHoraFin AND s.fechaHoraFin > @fechaHoraInicio; los bordes iguales NO solapan)
-- del MISMO grupo o de OTRO grupo del mismo docente (Grupo.docente del grupo), excluida @idSesionExcluir (la propia
-- sesion al actualizar). Lee con UPDLOCK, HOLDLOCK las sesiones de los grupos del docente para serializar creaciones
-- concurrentes: lo llaman usp_crear_sesion_interno y usp_actualizar_sesion_interno DENTRO de su transaccion, antes de
-- escribir. No escribe. Cuando B introduzca SesionCancelacion (DEC-016), debera excluir las sesiones canceladas.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_solape_sesion_interno]
(
    @idGrupo                 UNIQUEIDENTIFIER,
    @idSesionExcluir         UNIQUEIDENTIFIER = NULL,
    @fechaHoraInicio         DATETIME2,
    @fechaHoraFin            DATETIME2,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idDocente            UNIQUEIDENTIFIER;
    DECLARE @idSesionConflicto    UNIQUEIDENTIFIER;
BEGIN
    SET NOCOUNT ON;

    SELECT @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
           @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
           @estadoResultado = 1;

    BEGIN TRY
        -- PASO 1: correlacion obligatoria
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: sesion del mismo grupo o de otro grupo del mismo docente que se cruce (bordes iguales no solapan)
        IF @estadoResultado = 1 AND @fechaHoraInicio IS NOT NULL AND @fechaHoraFin IS NOT NULL
        BEGIN
            SELECT @idDocente = g.docente FROM dbo.Grupo g WHERE g.id = @idGrupo;

            SELECT TOP 1 @idSesionConflicto = s.id
            FROM dbo.Sesion s WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.Grupo g ON g.id = s.grupo
            WHERE (s.grupo = @idGrupo OR (@idDocente IS NOT NULL AND g.docente = @idDocente))
              AND s.fechaHoraInicio < @fechaHoraFin
              AND s.fechaHoraFin > @fechaHoraInicio
              AND (@idSesionExcluir IS NULL OR s.id <> @idSesionExcluir)
            ORDER BY s.fechaHoraInicio, s.id;

            IF @idSesionConflicto IS NOT NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_017',
                    @p_param1 = @idSesionConflicto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END
    END TRY
    BEGIN CATCH
        IF XACT_STATE() = -1
            THROW;
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- UTC-D06-POST-FREEZE: nucleo unico de creacion de sesion compartido por
--   * usp_crear_sesion    (v1, firma congelada DB-GP-001C) -> @procedenciaTemporal = NULL
--   * usp_crear_sesion_v2 (v2, instantes UTC confirmados)   -> @procedenciaTemporal = 'UTC_V2'
-- Las horas y la marca se escriben en el MISMO INSERT. Este SP no es publico: el rol runtime
-- tiene DENY EXECUTE directo y solo se alcanza por encadenamiento de propiedad desde los wrappers.
-- UTC_GENERADOR y UTC_OWNER NO se aceptan por esta via (generador y clasificacion propios).
-- CULM-001 A.2-10 (F-DOC-017): dentro de la transaccion y antes del INSERT, una sesion que se cruce con otra del grupo o
-- de otro grupo del mismo docente se rechaza con SES_017 (usp_validar_solape_sesion_interno); el rechazo no escribe.
CREATE OR ALTER PROCEDURE [dbo].[usp_crear_sesion_interno]
(
    @idGrupo                 UNIQUEIDENTIFIER,
    @nombre                  NVARCHAR(50),
    @fechaHoraInicio         DATETIME2,
    @fechaHoraFin            DATETIME2,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @procedenciaTemporal     NVARCHAR(24),
    @idCorrelacionResultado  UNIQUEIDENTIFIER OUTPUT,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto           UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @nombreDefecto            NVARCHAR(50)     = TRIM(@nombre);

    DECLARE @idNuevoSesion   UNIQUEIDENTIFIER = NEWID();
    DECLARE @numeroSiguiente INT = 1;
    DECLARE @codigoSesion    NVARCHAR(50);

    -- Ownership transaccional (propia o savepoint bajo transacción externa)
    DECLARE @transaccionPropia BIT = 0;
    DECLARE @savepointCreado   BIT = 0;

BEGIN
    SET NOCOUNT ON;
    SET @idCorrelacionResultado = @idCorrelacionDefecto;

    BEGIN TRY
        -- PASOS 0-1.6: procedencia, correlacion y seguridad antes de consultar el grupo.
        EXEC dbo.usp_validar_sesion_operacion_interno
            @idCorrelacion = @idCorrelacion,
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @procedenciaTemporal = @procedenciaTemporal,
            @fechaHoraInicio = @fechaHoraInicio,
            @fechaHoraFin = @fechaHoraFin,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT,
            @faseValidacion = 0;

        -- PASO 2: Validación de existencia del grupo académico
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_grupo_exista_por_id_interno
                @idGrupo = @idGrupoDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2.1: Titularidad del docente ejecutor sobre el grupo.
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @idEntidadPadre = @idGrupoDefecto,
                @tipoEntidadPadre = 'GRUPO',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2.5: conservar la prioridad contractual de entidad antes de fechas.
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_sesion_operacion_interno
                @idCorrelacion = @idCorrelacion,
                @idUsuarioEjecutor = @idUsuarioEjecutor,
                @procedenciaTemporal = @procedenciaTemporal,
                @fechaHoraInicio = @fechaHoraInicio,
                @fechaHoraFin = @fechaHoraFin,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT,
                @faseValidacion = 2;
        END

        -- PASO 3: Cálculo transaccional del correlativo de sesión e inserción
        -- (ownership transaccional: propia o savepoint bajo transacción externa)
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION usp_crear_sesion;
                SET @savepointCreado = 1;
            END

            -- PASO 2.8 (CULM-001 A.2-10): solape con sesiones del grupo o del docente, bajo bloqueo
            EXEC dbo.usp_validar_solape_sesion_interno
                @idGrupo = @idGrupoDefecto,
                @idSesionExcluir = NULL,
                @fechaHoraInicio = @fechaHoraInicio,
                @fechaHoraFin = @fechaHoraFin,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        IF @estadoResultado = 1
        BEGIN
            SELECT @numeroSiguiente = COALESCE(MAX(numero), 0) + 1
            FROM [dbo].[Sesion] WITH (UPDLOCK, HOLDLOCK)
            WHERE grupo = @idGrupoDefecto;

            SET @codigoSesion = CASE
                WHEN @numeroSiguiente < 100 THEN CONCAT('SES-', RIGHT('0' + CAST(@numeroSiguiente AS VARCHAR(10)), 2))
                ELSE CONCAT('SES-', CAST(@numeroSiguiente AS VARCHAR(10)))
            END;

            -- Horas y procedencia en la MISMA sentencia (UTC-D06).
            INSERT INTO dbo.Sesion (
                id, nombre, numero, codigo, numeroSemana, grupo,
                fechaHoraInicio, fechaHoraFin, procedenciaTemporal
            )
            VALUES (
                @idNuevoSesion,
                CASE WHEN @nombreDefecto IS NOT NULL AND @nombreDefecto <> '' THEN @nombreDefecto ELSE CONCAT('Sesión #', @numeroSiguiente) END,
                @numeroSiguiente,
                @codigoSesion,
                @numeroSiguiente,
                @idGrupoDefecto,
                @fechaHoraInicio,
                @fechaHoraFin,
                @procedenciaTemporal
            );
        END

        -- Cierre de la transaccion propia (el rechazo por solape no escribe)
        IF @transaccionPropia = 1
        BEGIN
            IF XACT_STATE() = 1
                COMMIT TRANSACTION;
            ELSE IF XACT_STATE() <> 0
                ROLLBACK TRANSACTION;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'Sesion', @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

    END TRY
    BEGIN CATCH
        -- BLOQUE CATCH: Captura centralizada de excepciones y reversión respetando ownership transaccional
        DECLARE @estadoTransaccionCatch INT = XACT_STATE();

        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION usp_crear_sesion;
        END

        -- Transacción externa condenada (XACT_STATE = -1) que no nos pertenece: propagar al propietario
        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
        BEGIN
            THROW;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SYS_001', @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- UTC-D06-POST-FREEZE: nucleo unico de actualizacion de sesion compartido por
--   * usp_actualizar_sesion    (v1, firma congelada DB-GP-001C) -> @procedenciaTemporal = NULL
--   * usp_actualizar_sesion_v2 (v2, instantes UTC confirmados)   -> @procedenciaTemporal = 'UTC_V2'
-- PUT completo de horas: horas y marca se escriben en el MISMO UPDATE. Una actualizacion v1 de una
-- sesion confirmada la vuelve INDETERMINADA aunque el valor temporal sea identico, porque v1 no
-- declara zona. Solo NULL o UTC_V2 se aceptan por esta via.
-- CULM-001 A.2-10 (F-DOC-017): si cambian fechaHoraInicio o fechaHoraFin respecto de la fila guardada (N6), la sesion no
-- puede cruzarse con otra del grupo o de otro grupo del mismo docente (SES_017, excluida ella misma); un cambio de solo
-- nombre no se valida, asi una sesion con un solape heredado puede seguir renombrandose. Transaccion propia o savepoint.
CREATE OR ALTER PROCEDURE [dbo].[usp_actualizar_sesion_interno]
(
    @idSesion                UNIQUEIDENTIFIER,
    @nombre                  NVARCHAR(50),
    @fechaHoraInicio         DATETIME2,
    @fechaHoraFin            DATETIME2,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @procedenciaTemporal     NVARCHAR(24),
    @idCorrelacionResultado  UNIQUEIDENTIFIER OUTPUT,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto          UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @nombreDefecto            NVARCHAR(50)     = TRIM(@nombre);

    DECLARE @idGrupoSesion UNIQUEIDENTIFIER;
    DECLARE @inicioActual  DATETIME2;
    DECLARE @finActual     DATETIME2;

    -- Ownership transaccional (propia o savepoint bajo transaccion externa)
    DECLARE @transaccionPropia      BIT = 0;
    DECLARE @savepointCreado        BIT = 0;
    DECLARE @estadoTransaccionCatch INT;

BEGIN
    SET NOCOUNT ON;
    SET @idCorrelacionResultado = @idCorrelacionDefecto;

    BEGIN TRY
        -- PASOS 0-1.6: procedencia, correlacion y seguridad antes de consultar la sesión.
        EXEC dbo.usp_validar_sesion_operacion_interno
            @idCorrelacion = @idCorrelacion,
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @procedenciaTemporal = @procedenciaTemporal,
            @fechaHoraInicio = @fechaHoraInicio,
            @fechaHoraFin = @fechaHoraFin,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT,
            @faseValidacion = 0;

        -- PASO 2: Validar existencia de la sesión con código semántico SES_001
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1
                @idGrupoSesion = grupo
            FROM [dbo].[Sesion]
            WHERE id = @idSesionDefecto;

            IF @idGrupoSesion IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_001',
                    @p_param1 = @idSesionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 3: Titularidad del docente ejecutor sobre la sesión.
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @idEntidadPadre = @idSesionDefecto,
                @tipoEntidadPadre = 'SESION',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: conservar la prioridad contractual de entidad antes de fechas.
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_sesion_operacion_interno
                @idCorrelacion = @idCorrelacion,
                @idUsuarioEjecutor = @idUsuarioEjecutor,
                @procedenciaTemporal = @procedenciaTemporal,
                @fechaHoraInicio = @fechaHoraInicio,
                @fechaHoraFin = @fechaHoraFin,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT,
                @faseValidacion = 2;
        END

        -- PASO 5 (CULM-001 A.2-10): transaccion y solape solo si cambia el horario guardado (N6)
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION usp_actualizar_sesion;
                SET @savepointCreado = 1;
            END

            SELECT @inicioActual = s.fechaHoraInicio, @finActual = s.fechaHoraFin
            FROM dbo.Sesion s WITH (UPDLOCK, HOLDLOCK)
            WHERE s.id = @idSesionDefecto;

            IF @inicioActual IS NULL OR @finActual IS NULL OR @inicioActual <> @fechaHoraInicio OR @finActual <> @fechaHoraFin
            BEGIN
                EXEC dbo.usp_validar_solape_sesion_interno
                    @idGrupo = @idGrupoSesion,
                    @idSesionExcluir = @idSesionDefecto,
                    @fechaHoraInicio = @fechaHoraInicio,
                    @fechaHoraFin = @fechaHoraFin,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
            END
        END

        IF @estadoResultado = 1
        BEGIN
            -- Horas y procedencia en la MISMA sentencia (UTC-D06).
            UPDATE dbo.Sesion
            SET nombre = CASE WHEN @nombreDefecto IS NOT NULL AND @nombreDefecto <> '' THEN @nombreDefecto ELSE nombre END,
                fechaHoraInicio = @fechaHoraInicio,
                fechaHoraFin = @fechaHoraFin,
                procedenciaTemporal = @procedenciaTemporal
            WHERE id = @idSesionDefecto;
        END

        -- Cierre de la transaccion propia (el rechazo por solape no escribe)
        IF @transaccionPropia = 1
        BEGIN
            IF XACT_STATE() = 1
                COMMIT TRANSACTION;
            ELSE IF XACT_STATE() <> 0
                ROLLBACK TRANSACTION;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'Sesion', @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

    END TRY
    BEGIN CATCH
        SET @estadoTransaccionCatch = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION usp_actualizar_sesion;
        END

        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
        BEGIN
            THROW;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SYS_001', @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_resolver_facultad_decano_interno]
-- HU102/HU103/HU106/HU144: valida correlacion y ejecutor y resuelve la facultad que dirige el decano (ambito).
-- Falla con THROW (DBCODE=...): CORR_001, VAL_001 (ejecutor nulo), KPI_003 (no es decano de una facultad), KPI_002 (umbral ausente).
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_resolver_facultad_decano_interno]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @validarUmbrales   BIT = 1,
    @idFacultad        UNIQUEIDENTIFIER OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @msgP1 NVARCHAR(500);
    SET @idFacultad = NULL;
    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 0 THROW 51000, @mensajeTecnicoResultado, 1;
    IF @idUsuarioEjecutor IS NULL OR @idUsuarioEjecutor = @guidVacio
    BEGIN
        SET @msgP1 = CAST(N'UsuarioEjecutor' AS NVARCHAR(500));
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001',
            @p_param1 = @msgP1,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    SELECT TOP 1 @idFacultad = f.id
    FROM dbo.uv_facultad f
    INNER JOIN dbo.uv_decano_identidad di ON di.id = f.idDecano
    WHERE di.idUsuario = @idUsuarioEjecutor
      -- CULM-001 A.2-8 (A2-T-12): un rol de decano desactivado (Decano.estado = 0) no resuelve facultad (KPI_003).
      AND EXISTS (SELECT 1 FROM dbo.Decano d WHERE d.id = di.id AND d.estado = 1)
    ORDER BY f.estaActivaFacultad DESC, f.nombreFacultad ASC, f.id ASC;

    IF @idFacultad IS NULL
    BEGIN
        SET @msgP1 = CAST(CONVERT(NVARCHAR(36), @idUsuarioEjecutor) AS NVARCHAR(500));
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'KPI_003',
            @p_param1 = @msgP1,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    IF @validarUmbrales = 1 AND dbo.ufn_clasificar_permanencia(0, N'A') IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'KPI_002',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END
END;
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_directorio_estudiantes_paginado (CULM-001 A.2-1; F-COO-001, F-COO-002, F-DOC-013; CONTRACT §8.2.1)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET + totalRegistros (THROW ante ejecutor nulo).
-- Directorio de estudiantes de GET /api/v1/estudiantes y /{id} con el AMBITO DENTRO DEL SP (union si el ejecutor
-- tiene varios roles; el ejecutor debe ser un usuario activo):
--   * ADMINISTRADOR: solo su institucion (DEC-031 §3): estudiantes con EstudiantePrograma en un programa de su
--     institucion o con EstudianteGrupo en un grupo de su institucion. Un estudiante sin ningun vinculo no tiene
--     institucion resoluble y no aparece (fail-closed).
--   * COORDINADOR activo: estudiantes con EstudiantePrograma en sus programas.
--   * DOCENTE: estudiantes con alguna matricula (en cualquier estado: padron historico) en sus grupos.
--   * Cualquier otro rol: ambito vacio.
-- Modo listado (@idEstudiante NULL): 12 columnas, orden primerApellido, primerNombre, numeroIdentificacion, id;
-- paginacion protegida (pagina >= 1, tamano 1..100). Los filtros solo restringen dentro del ambito: igualdad para tipo
-- y numero de documento, LIKE con escape de %, _ y \ sobre UPPER(nombreCompleto) y LOWER(correo), y EXISTS sobre
-- uv_estudiante para los academicos.
-- Modo detalle (@idEstudiante no nulo): las 11 columnas del estudiante mas 12 de contexto academico (institucion,
-- facultad, programa, plan, asignatura y grupo, con id y nombre) LIMITADAS AL AMBITO del ejecutor: una fila por
-- contexto visible o una sola con contexto NULL. Fuera de ambito: 0 filas (el backend responde 404). Solo lectura.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_directorio_estudiantes_paginado]
(
    @idUsuarioEjecutor    UNIQUEIDENTIFIER,
    @idCorrelacion        UNIQUEIDENTIFIER,
    @idEstudiante         UNIQUEIDENTIFIER = NULL,
    @idTipoIdentificacion UNIQUEIDENTIFIER = NULL,
    @numeroIdentificacion INT              = NULL,
    @nombre               NVARCHAR(100)    = NULL,
    @correo               NVARCHAR(100)    = NULL,
    @idInstitucion        UNIQUEIDENTIFIER = NULL,
    @idFacultad           UNIQUEIDENTIFIER = NULL,
    @idPrograma           UNIQUEIDENTIFIER = NULL,
    @idGrupo              UNIQUEIDENTIFIER = NULL,
    @activo               BIT              = NULL,
    @numeroPagina         INT              = 1,
    @tamanoPagina         INT              = 20
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 20, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;
    DECLARE @textoNombre NVARCHAR(100) = NULLIF(TRIM(@nombre), N'');
    DECLARE @textoCorreo NVARCHAR(100) = NULLIF(TRIM(@correo), N'');
    DECLARE @patronNombre NVARCHAR(320) = IIF(@textoNombre IS NULL, NULL,
        CONCAT(N'%', REPLACE(REPLACE(REPLACE(UPPER(@textoNombre), N'\', N'\\'), N'%', N'\%'), N'_', N'\_'), N'%'));
    DECLARE @patronCorreo NVARCHAR(320) = IIF(@textoCorreo IS NULL, NULL,
        CONCAT(N'%', REPLACE(REPLACE(REPLACE(LOWER(@textoCorreo), N'\', N'\\'), N'%', N'\%'), N'_', N'\_'), N'%'));
    DECLARE @filtroAcademico BIT = IIF(@idInstitucion IS NULL AND @idFacultad IS NULL AND @idPrograma IS NULL AND @idGrupo IS NULL, 0, 1);
    DECLARE @ejecutorActivo BIT = 0;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- PASO 1: correlacion obligatoria
    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    -- PASO 2: ejecutor obligatorio (VAL_001)
    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001', @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    SET @ejecutorActivo = IIF(EXISTS (SELECT 1 FROM dbo.Usuario u WHERE u.id = @idUsuarioEjecutor AND u.estado = 1), 1, 0);

    -- PASO 3: modo listado
    IF @idEstudiante IS NULL
    BEGIN
        ;WITH ambito AS (
            -- ADMINISTRADOR: matriculas en grupos de su institucion
            SELECT eg.estudiante AS idEstudiante
            FROM dbo.Administrador ad
            INNER JOIN dbo.Facultad f ON f.institucion = ad.institucion
            INNER JOIN dbo.Programa p ON p.facultad = f.id
            INNER JOIN dbo.PlanEstudio pe ON pe.programa = p.id
            INNER JOIN dbo.SemestrePlanEstudio spe ON spe.planEstudio = pe.id
            INNER JOIN dbo.Asignatura a ON a.semestrePlanEstudio = spe.id
            INNER JOIN dbo.Grupo g ON g.asignatura = a.id
            INNER JOIN dbo.EstudianteGrupo eg ON eg.grupo = g.id
            WHERE ad.usuario = @idUsuarioEjecutor AND @ejecutorActivo = 1
            UNION
            -- ADMINISTRADOR: inscripciones en programas de su institucion
            SELECT ep.estudiante
            FROM dbo.Administrador ad
            INNER JOIN dbo.Facultad f ON f.institucion = ad.institucion
            INNER JOIN dbo.Programa p ON p.facultad = f.id
            INNER JOIN dbo.EstudiantePrograma ep ON ep.programa = p.id
            WHERE ad.usuario = @idUsuarioEjecutor AND @ejecutorActivo = 1
            UNION
            -- COORDINADOR activo: inscripciones en sus programas
            SELECT ep.estudiante
            FROM dbo.Coordinador c
            INNER JOIN dbo.Programa p ON p.coordinador = c.id
            INNER JOIN dbo.EstudiantePrograma ep ON ep.programa = p.id
            WHERE c.usuario = @idUsuarioEjecutor AND c.estado = 1 AND @ejecutorActivo = 1
            UNION
            -- DOCENTE: matriculas (cualquier estado) en sus grupos
            SELECT eg.estudiante
            FROM dbo.Docente d
            INNER JOIN dbo.Grupo g ON g.docente = d.id
            INNER JOIN dbo.EstudianteGrupo eg ON eg.grupo = g.id
            WHERE d.usuario = @idUsuarioEjecutor AND @ejecutorActivo = 1
        )
        SELECT
            id                   = e.id,
            idUsuario            = u.id,
            tipoIdentificacionId = u.idTipoIdentificacion,
            numeroIdentificacion = u.numeroIdentificacion,
            primerApellido       = u.primerApellido,
            segundoApellido      = u.segundoApellido,
            primerNombre         = u.primerNombre,
            segundoNombre        = u.segundoNombre,
            nombreCompleto       = CAST(u.nombreCompleto AS NVARCHAR(400)),
            correo               = u.correo,
            estaActivoUsuario    = u.estaActivoUsuario,
            totalRegistros       = COUNT(*) OVER()
        FROM dbo.uv_estudiante_identidad e
        INNER JOIN dbo.uv_usuario u ON u.id = e.idUsuario
        WHERE e.id IN (SELECT amb.idEstudiante FROM ambito amb)
          AND (@idTipoIdentificacion IS NULL OR u.idTipoIdentificacion = @idTipoIdentificacion)
          AND (@numeroIdentificacion IS NULL OR u.numeroIdentificacion = @numeroIdentificacion)
          AND (@patronNombre IS NULL OR UPPER(u.nombreCompleto) LIKE @patronNombre ESCAPE N'\')
          AND (@patronCorreo IS NULL OR LOWER(u.correo) LIKE @patronCorreo ESCAPE N'\')
          AND (@activo IS NULL OR u.estaActivoUsuario = @activo)
          AND (@filtroAcademico = 0 OR EXISTS (
                SELECT 1 FROM dbo.uv_estudiante x
                WHERE x.id = e.id
                  AND (@idInstitucion IS NULL OR x.idInstitucion = @idInstitucion)
                  AND (@idFacultad IS NULL OR x.idFacultad = @idFacultad)
                  AND (@idPrograma IS NULL OR x.idPrograma = @idPrograma)
                  AND (@idGrupo IS NULL OR x.idGrupo = @idGrupo)))
        ORDER BY u.primerApellido ASC, u.primerNombre ASC, u.numeroIdentificacion ASC, e.id ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamano ROWS ONLY;
    END
    ELSE
    -- PASO 4: modo detalle (contextos limitados al ambito del ejecutor)
    BEGIN
        ;WITH ambito AS (
            SELECT eg.estudiante AS idEstudiante
            FROM dbo.Administrador ad
            INNER JOIN dbo.Facultad f ON f.institucion = ad.institucion
            INNER JOIN dbo.Programa p ON p.facultad = f.id
            INNER JOIN dbo.PlanEstudio pe ON pe.programa = p.id
            INNER JOIN dbo.SemestrePlanEstudio spe ON spe.planEstudio = pe.id
            INNER JOIN dbo.Asignatura a ON a.semestrePlanEstudio = spe.id
            INNER JOIN dbo.Grupo g ON g.asignatura = a.id
            INNER JOIN dbo.EstudianteGrupo eg ON eg.grupo = g.id
            WHERE ad.usuario = @idUsuarioEjecutor AND @ejecutorActivo = 1 AND eg.estudiante = @idEstudiante
            UNION
            SELECT ep.estudiante
            FROM dbo.Administrador ad
            INNER JOIN dbo.Facultad f ON f.institucion = ad.institucion
            INNER JOIN dbo.Programa p ON p.facultad = f.id
            INNER JOIN dbo.EstudiantePrograma ep ON ep.programa = p.id
            WHERE ad.usuario = @idUsuarioEjecutor AND @ejecutorActivo = 1 AND ep.estudiante = @idEstudiante
            UNION
            SELECT ep.estudiante
            FROM dbo.Coordinador c
            INNER JOIN dbo.Programa p ON p.coordinador = c.id
            INNER JOIN dbo.EstudiantePrograma ep ON ep.programa = p.id
            WHERE c.usuario = @idUsuarioEjecutor AND c.estado = 1 AND @ejecutorActivo = 1 AND ep.estudiante = @idEstudiante
            UNION
            SELECT eg.estudiante
            FROM dbo.Docente d
            INNER JOIN dbo.Grupo g ON g.docente = d.id
            INNER JOIN dbo.EstudianteGrupo eg ON eg.grupo = g.id
            WHERE d.usuario = @idUsuarioEjecutor AND @ejecutorActivo = 1 AND eg.estudiante = @idEstudiante
        ),
        contexto AS (
            SELECT DISTINCT
                x.idInstitucion, x.nombreInstitucion, x.idFacultad, x.nombreFacultad, x.idPrograma, x.nombrePrograma,
                x.idPlanEstudio, inpPlanEstudio = CAST(x.inpPlanEstudio AS NVARCHAR(20)), x.idAsignatura, x.nombreAsignatura,
                x.idGrupo, x.nombreGrupo
            FROM dbo.uv_estudiante x
            WHERE x.id = @idEstudiante
              AND @ejecutorActivo = 1
              AND (EXISTS (SELECT 1 FROM dbo.Administrador ad WHERE ad.usuario = @idUsuarioEjecutor AND ad.institucion = x.idInstitucion)
                   OR EXISTS (SELECT 1 FROM dbo.Coordinador c INNER JOIN dbo.Programa p ON p.coordinador = c.id
                              WHERE c.usuario = @idUsuarioEjecutor AND c.estado = 1 AND p.id = x.idPrograma)
                   OR EXISTS (SELECT 1 FROM dbo.Docente d INNER JOIN dbo.Grupo g ON g.docente = d.id
                              WHERE d.usuario = @idUsuarioEjecutor AND g.id = x.idGrupo))
        )
        SELECT
            id                   = e.id,
            idUsuario            = u.id,
            tipoIdentificacionId = u.idTipoIdentificacion,
            numeroIdentificacion = u.numeroIdentificacion,
            primerApellido       = u.primerApellido,
            segundoApellido      = u.segundoApellido,
            primerNombre         = u.primerNombre,
            segundoNombre        = u.segundoNombre,
            nombreCompleto       = CAST(u.nombreCompleto AS NVARCHAR(400)),
            correo               = u.correo,
            estaActivoUsuario    = u.estaActivoUsuario,
            idInstitucion        = c.idInstitucion,
            nombreInstitucion    = c.nombreInstitucion,
            idFacultad           = c.idFacultad,
            nombreFacultad       = c.nombreFacultad,
            idPrograma           = c.idPrograma,
            nombrePrograma       = c.nombrePrograma,
            idPlanEstudio        = c.idPlanEstudio,
            inpPlanEstudio       = c.inpPlanEstudio,
            idAsignatura         = c.idAsignatura,
            nombreAsignatura     = c.nombreAsignatura,
            idGrupo              = c.idGrupo,
            nombreGrupo          = c.nombreGrupo
        FROM dbo.uv_estudiante_identidad e
        INNER JOIN dbo.uv_usuario u ON u.id = e.idUsuario
        LEFT JOIN contexto c ON 1 = 1
        WHERE e.id = @idEstudiante
          AND e.id IN (SELECT amb.idEstudiante FROM ambito amb)
        ORDER BY c.nombreInstitucion, c.nombreFacultad, c.nombrePrograma, c.nombreAsignatura, c.nombreGrupo, c.idGrupo;
    END
END;
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_estudiantes_grupo_ambito_paginado (CULM-001 A.2-2; F-COO-003; CONTRACT §8.2.2)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET + totalRegistros (THROW ante ejecutor nulo o fuera de
-- ambito). Estudiantes del grupo de GET /api/v1/grupos/{grupoId}/estudiantes (WORM #3: columnas de EstudianteGrupoDTO),
-- en TODOS los estados (DR-007), orden nombreCompleto, id.
-- Ambito validado ANTES de leer filas (ejecutor activo):
--   * DOCENTE titular del grupo (Grupo.docente) y ADMINISTRADOR de la institucion del grupo: todos los estudiantes.
--   * COORDINADOR activo del programa del grupo (asignatura -> semestre -> plan -> programa): solo los estudiantes con
--     EstudiantePrograma en alguno de sus programas (DEC-031 §4; B2 completa la relacion N:M).
--   * Grupo inexistente o fuera de ambito: THROW 51000 con el mensaje tecnico de SEC_002 (DBCODE=SEC_002 -> 403).
-- @tamanoPagina NULL = todas las filas (A2-C3: el contrato WORM fija listas completas); con valor, 1..100. Solo lectura.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_estudiantes_grupo_ambito_paginado]
(
    @idGrupo           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @numeroPagina      INT = 1,
    @tamanoPagina      INT = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL, 2147483647, IIF(@tamanoPagina < 1, 1, IIF(@tamanoPagina > 100, 100, @tamanoPagina)));
    DECLARE @offset INT = IIF(@tamanoPagina IS NULL, 0, (@pagina - 1) * @tamano);
    DECLARE @ejecutorActivo BIT = 0;
    DECLARE @verTodos BIT = 0;
    DECLARE @esCoordinador BIT = 0;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- PASO 1: correlacion obligatoria
    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    -- PASO 2: ejecutor obligatorio (VAL_001)
    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001', @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    -- PASO 3: ambito del grupo, antes de leer filas
    IF @estadoResultado = 1
    BEGIN
        SET @ejecutorActivo = IIF(EXISTS (SELECT 1 FROM dbo.Usuario u WHERE u.id = @idUsuarioEjecutor AND u.estado = 1), 1, 0);

        SET @verTodos = IIF(@ejecutorActivo = 1 AND (
                EXISTS (SELECT 1 FROM dbo.Grupo g INNER JOIN dbo.Docente d ON d.id = g.docente
                        WHERE g.id = @idGrupo AND d.usuario = @idUsuarioEjecutor)
             OR EXISTS (SELECT 1 FROM dbo.Grupo g
                        INNER JOIN dbo.Asignatura a ON a.id = g.asignatura
                        INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = a.semestrePlanEstudio
                        INNER JOIN dbo.PlanEstudio pe ON pe.id = spe.planEstudio
                        INNER JOIN dbo.Programa p ON p.id = pe.programa
                        INNER JOIN dbo.Facultad f ON f.id = p.facultad
                        INNER JOIN dbo.Administrador ad ON ad.institucion = f.institucion
                        WHERE g.id = @idGrupo AND ad.usuario = @idUsuarioEjecutor)), 1, 0);

        SET @esCoordinador = IIF(@ejecutorActivo = 1 AND EXISTS (
                SELECT 1 FROM dbo.Grupo g
                INNER JOIN dbo.Asignatura a ON a.id = g.asignatura
                INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = a.semestrePlanEstudio
                INNER JOIN dbo.PlanEstudio pe ON pe.id = spe.planEstudio
                INNER JOIN dbo.Programa p ON p.id = pe.programa
                INNER JOIN dbo.Coordinador c ON c.id = p.coordinador
                WHERE g.id = @idGrupo AND c.usuario = @idUsuarioEjecutor AND c.estado = 1), 1, 0);

        IF @verTodos = 0 AND @esCoordinador = 0
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SEC_002',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    -- PASO 4: estudiantes del grupo en todos los estados (el coordinador, solo los de sus programas)
    SELECT
        id             = eg.id,
        idEstudiante   = eg.idEstudiante,
        documento      = CAST(ei.numeroIdentificacion AS NVARCHAR(20)),
        nombreCompleto = CAST(ei.nombreCompleto AS NVARCHAR(400)),
        correo         = u.correo,
        codigoEstado   = eg.codigoEstadoEstudiante,
        nombreEstado   = eg.nombreEstadoEstudiante,
        totalRegistros = COUNT(*) OVER()
    FROM dbo.uv_estudiante_grupo eg
    INNER JOIN dbo.uv_estudiante_identidad ei ON ei.id = eg.idEstudiante
    INNER JOIN dbo.uv_usuario u ON u.id = ei.idUsuario
    WHERE eg.idGrupo = @idGrupo
      AND (@verTodos = 1
           OR EXISTS (SELECT 1 FROM dbo.EstudiantePrograma ep
                      INNER JOIN dbo.Programa p ON p.id = ep.programa
                      INNER JOIN dbo.Coordinador c ON c.id = p.coordinador
                      WHERE ep.estudiante = eg.idEstudiante AND c.usuario = @idUsuarioEjecutor AND c.estado = 1))
    ORDER BY ei.nombreCompleto ASC, eg.id ASC
    OFFSET @offset ROWS
    FETCH NEXT @tamano ROWS ONLY;
END;
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_asistencias_grupo_ambito_paginado (CULM-001 A.2-2; F-COO-003; CONTRACT §8.2.2)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET + totalRegistros (THROW ante ejecutor nulo o fuera de
-- ambito). Asistencias del grupo de GET /api/v1/grupos/{grupoId}/asistencias (WORM #4: columnas de
-- AsistenciaConsultadaDTO). INNER JOIN desde uv_detalle_asistencia / uv_asistencia (vistas congeladas, solo lectura):
-- "ausencia = sin fila" (§E). Filtro opcional por sesion.
-- Ambito validado ANTES de leer filas (ejecutor activo): DOCENTE titular y ADMINISTRADOR de la institucion del grupo ven
-- todas; COORDINADOR activo del programa del grupo solo las de los estudiantes con EstudiantePrograma en sus programas
-- (DEC-031 §4). Grupo inexistente o fuera de ambito: THROW 51000 con DBCODE=SEC_002 (403).
-- @tamanoPagina NULL = todas las filas (A2-C3); con valor, 1..100. Solo lectura.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_asistencias_grupo_ambito_paginado]
(
    @idGrupo           UNIQUEIDENTIFIER,
    @idSesion          UNIQUEIDENTIFIER = NULL,
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @numeroPagina      INT = 1,
    @tamanoPagina      INT = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL, 2147483647, IIF(@tamanoPagina < 1, 1, IIF(@tamanoPagina > 100, 100, @tamanoPagina)));
    DECLARE @offset INT = IIF(@tamanoPagina IS NULL, 0, (@pagina - 1) * @tamano);
    DECLARE @ejecutorActivo BIT = 0;
    DECLARE @verTodos BIT = 0;
    DECLARE @esCoordinador BIT = 0;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- PASO 1: correlacion obligatoria
    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    -- PASO 2: ejecutor obligatorio (VAL_001)
    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001', @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    -- PASO 3: ambito del grupo, antes de leer filas
    IF @estadoResultado = 1
    BEGIN
        SET @ejecutorActivo = IIF(EXISTS (SELECT 1 FROM dbo.Usuario u WHERE u.id = @idUsuarioEjecutor AND u.estado = 1), 1, 0);

        SET @verTodos = IIF(@ejecutorActivo = 1 AND (
                EXISTS (SELECT 1 FROM dbo.Grupo g INNER JOIN dbo.Docente d ON d.id = g.docente
                        WHERE g.id = @idGrupo AND d.usuario = @idUsuarioEjecutor)
             OR EXISTS (SELECT 1 FROM dbo.Grupo g
                        INNER JOIN dbo.Asignatura a ON a.id = g.asignatura
                        INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = a.semestrePlanEstudio
                        INNER JOIN dbo.PlanEstudio pe ON pe.id = spe.planEstudio
                        INNER JOIN dbo.Programa p ON p.id = pe.programa
                        INNER JOIN dbo.Facultad f ON f.id = p.facultad
                        INNER JOIN dbo.Administrador ad ON ad.institucion = f.institucion
                        WHERE g.id = @idGrupo AND ad.usuario = @idUsuarioEjecutor)), 1, 0);

        SET @esCoordinador = IIF(@ejecutorActivo = 1 AND EXISTS (
                SELECT 1 FROM dbo.Grupo g
                INNER JOIN dbo.Asignatura a ON a.id = g.asignatura
                INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = a.semestrePlanEstudio
                INNER JOIN dbo.PlanEstudio pe ON pe.id = spe.planEstudio
                INNER JOIN dbo.Programa p ON p.id = pe.programa
                INNER JOIN dbo.Coordinador c ON c.id = p.coordinador
                WHERE g.id = @idGrupo AND c.usuario = @idUsuarioEjecutor AND c.estado = 1), 1, 0);

        IF @verTodos = 0 AND @esCoordinador = 0
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SEC_002',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    -- PASO 4: asistencias registradas del grupo (el coordinador, solo las de los estudiantes de sus programas)
    SELECT
        asistencia     = da.id,
        estudiante     = eg.idEstudiante,
        grupo          = eg.idGrupo,
        sesion         = a.idSesion,
        presente       = da.asistio,
        estado         = da.codigoRazonCausa,
        observacion    = CAST(N'' AS NVARCHAR(500)),
        totalRegistros = COUNT(*) OVER()
    FROM dbo.uv_detalle_asistencia da
    INNER JOIN dbo.uv_asistencia a ON a.id = da.idAsistencia
    INNER JOIN dbo.uv_estudiante_grupo eg ON eg.id = a.idEstudianteGrupo
    WHERE eg.idGrupo = @idGrupo
      AND (@idSesion IS NULL OR a.idSesion = @idSesion)
      AND (@verTodos = 1
           OR EXISTS (SELECT 1 FROM dbo.EstudiantePrograma ep
                      INNER JOIN dbo.Programa p ON p.id = ep.programa
                      INNER JOIN dbo.Coordinador c ON c.id = p.coordinador
                      WHERE ep.estudiante = eg.idEstudiante AND c.usuario = @idUsuarioEjecutor AND c.estado = 1))
    ORDER BY a.idSesion ASC, eg.idEstudiante ASC, da.id ASC
    OFFSET @offset ROWS
    FETCH NEXT @tamano ROWS ONLY;
END;
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_materias_estudiante (CULM-001 A.2-11; F-EST-S01, F-EST-020; CONTRACT §8.2.3 A2-DB-1)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW ante ejecutor nulo).
-- Materias del estudiante de GET /api/v1/estudiante/materias. El estudiante sale del ejecutor (Estudiante.usuario); sin
-- estudiante, 0 filas. Solo cuenta la matricula con el codigo del parametro MATRICULA/ESTADO_INSCRITA: las matriculas
-- retiradas, canceladas o finalizadas (I, CI, CVP, F) no aparecen. Columnas de MateriaEstudianteQueryRow
-- (idAsignatura, nombreAsignatura, idGrupo, nombreGrupo), orden nombreAsignatura, nombreGrupo. Solo lectura.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_materias_estudiante]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoInscrita NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- PASO 1: correlacion obligatoria
    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    -- PASO 2: ejecutor obligatorio (VAL_001)
    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001', @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    -- PASO 3: materias con matricula inscrita del estudiante del ejecutor
    SELECT DISTINCT
        idAsignatura     = a.id,
        nombreAsignatura = a.nombre,
        idGrupo          = g.id,
        nombreGrupo      = g.nombre
    FROM dbo.Estudiante e
    INNER JOIN dbo.uv_estudiante_grupo eg ON eg.idEstudiante = e.id
    INNER JOIN dbo.uv_grupo g ON g.id = eg.idGrupo
    INNER JOIN dbo.uv_asignatura a ON a.id = g.idAsignatura
    WHERE e.usuario = @idUsuarioEjecutor
      AND eg.codigoEstadoEstudiante = @codigoInscrita
    ORDER BY a.nombre ASC, g.nombre ASC;
END;
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_horario_estudiante (CULM-001 A.2-11; F-EST-S01, F-EST-020; CONTRACT §8.2.3 A2-DB-1)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW ante ejecutor nulo).
-- Horario del estudiante de GET /api/v1/estudiante/horario. El estudiante sale del ejecutor (Estudiante.usuario); sin
-- estudiante, 0 filas. Lee uv_horario_estudiante (que no filtra por estado de matricula, linea 24) y aplica aqui el
-- filtro: solo los grupos con matricula en el codigo de MATRICULA/ESTADO_INSCRITA. La vista no cambia.
-- Columnas de uv_horario_estudiante que lee HorarioEstudianteJpaRepository; orden dia, horaInicio, nombreMateria.
-- Horas academicas LOCALES. Solo lectura.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_horario_estudiante]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoInscrita NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- PASO 1: correlacion obligatoria
    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    -- PASO 2: ejecutor obligatorio (VAL_001)
    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001', @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    -- PASO 3: horario de los grupos con matricula inscrita del estudiante del ejecutor
    SELECT
        h.id,
        h.idEstudiante,
        h.idGrupo,
        h.codigoMateria,
        h.nombreMateria,
        h.grupo,
        h.dia,
        h.horaInicio,
        h.horaFin,
        h.docente
    FROM dbo.uv_horario_estudiante h
    INNER JOIN dbo.Estudiante e ON e.id = h.idEstudiante
    WHERE e.usuario = @idUsuarioEjecutor
      AND EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo eg
                  WHERE eg.idEstudiante = h.idEstudiante AND eg.idGrupo = h.idGrupo
                    AND eg.codigoEstadoEstudiante = @codigoInscrita)
    ORDER BY h.dia ASC, h.horaInicio ASC, h.nombreMateria ASC;
END;
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_retirar_solicitud_revision_asistencia (CULM-001 A.2-7; F-EST-003; CONTRACT §8.2.3 A2-DB-3)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con resultset canonico de 4 columnas.
-- El ESTUDIANTE retira su propio reclamo (solicitud de revision de asistencia) mientras esta pendiente:
--   * RBAC ESTUDIANTE (SEC_001). Ambito dentro del SP: el reclamo debe ser del ejecutor
--     (asistencia -> EstudianteGrupo -> Estudiante.usuario); inexistente o ajeno => REV_006 (no revela que existe).
--   * Bajo UPDLOCK, HOLDLOCK su estado debe ser el codigo de RECLAMO/ESTADO_PENDIENTE; si no (ya resuelto o retirado),
--     REV_007. Pasa al estado con el codigo de RECLAMO/ESTADO_RETIRADO (X "retirada", A2-C4). Exito REV_008.
--   * El soporte (ArchivoSoporte) se conserva (almacenamiento WORM y auditoria). Sin notificacion.
-- SET XACT_ABORT ON; transaccion propia o savepoint; un rechazo de negocio no escribe ni hace ROLLBACK.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_retirar_solicitud_revision_asistencia]
(
    @idSolicitudRevision UNIQUEIDENTIFIER,
    @idCorrelacion       UNIQUEIDENTIFIER,
    @idUsuarioEjecutor   UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoPendiente      NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('RECLAMO', 'ESTADO_PENDIENTE') AS NVARCHAR(10));
    DECLARE @codigoRetirado       NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('RECLAMO', 'ESTADO_RETIRADO') AS NVARCHAR(10));
    DECLARE @idEstadoRetirado     UNIQUEIDENTIFIER;
    DECLARE @idSolicitudBloqueada UNIQUEIDENTIFIER;
    DECLARE @codigoEstadoActual   NVARCHAR(10);

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
    DECLARE @codigoRechazo           VARCHAR(20) = NULL;

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;
    DECLARE @estadoTransaccionCatch     INT;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: correlacion y ejecutor obligatorios
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 2: RBAC ESTUDIANTE
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutor,
                @codigoPerfilRequerido = 'ESTUDIANTE',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: estados por catalogo (parametros RECLAMO/*)
        IF @estadoResultado = 1
        BEGIN
            SELECT @idEstadoRetirado = e.id FROM dbo.Estado e WHERE e.codigo = @codigoRetirado;
            IF @idEstadoRetirado IS NULL OR @codigoPendiente IS NULL OR @codigoPendiente = N''
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_001', @p_param1 = 'Estado de reclamo (RECLAMO/ESTADO_*)',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 4: transaccion, propiedad y estado bajo bloqueo
        IF @estadoResultado = 1
        BEGIN
            SET @conteoTransaccionesInicial = @@TRANCOUNT;
            IF @conteoTransaccionesInicial = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_retirar_solicitud_revision;
                SET @savepointCreado = 1;
            END

            SELECT @idSolicitudBloqueada = r.id, @codigoEstadoActual = est.codigo
            FROM dbo.SolicitudRevisionAsistencia r WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.Estado est ON est.id = r.estado
            INNER JOIN dbo.Asistencia a ON a.id = r.asistencia
            INNER JOIN dbo.EstudianteGrupo eg ON eg.id = a.estudianteGrupo
            INNER JOIN dbo.Estudiante e ON e.id = eg.estudiante
            WHERE r.id = @idSolicitudRevision
              AND e.usuario = @idUsuarioEjecutor;

            IF @idSolicitudBloqueada IS NULL
                SET @codigoRechazo = 'REV_006';
            ELSE IF @codigoEstadoActual <> @codigoPendiente
                SET @codigoRechazo = 'REV_007';
            ELSE
            BEGIN
                UPDATE dbo.SolicitudRevisionAsistencia
                SET estado = @idEstadoRetirado
                WHERE id = @idSolicitudBloqueada;

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'REV_008', @p_param1 = @idSolicitudBloqueada,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END

            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1
                    COMMIT TRANSACTION;
                ELSE IF XACT_STATE() = -1
                    ROLLBACK TRANSACTION;
            END
        END

        -- PASO 5: mensaje de rechazo por catalogo (sin escrituras)
        IF @estadoResultado = 1 AND @codigoRechazo IS NOT NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoRechazo, @p_param1 = @idSolicitudRevision,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
    END TRY
    BEGIN CATCH
        SET @estadoTransaccionCatch = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @@TRANCOUNT > 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
            ROLLBACK TRANSACTION sp_retirar_solicitud_revision;

        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
            THROW;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_cambiar_estado_decano (CULM-001 A.2-8; F-ADM-002; CONTRACT §8.2.3 A2-DB-4)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando canonico + idUsuario, personaSinRolesActivos y estaActivoDecano
-- (igual que usp_cambiar_estado_coordinador) para que el backend sincronice la cuenta de identidad.
-- El ADMINISTRADOR activa o desactiva el rol de decano (Decano.estado, A2-C5) de una facultad de SU institucion:
--   * RBAC ADMINISTRADOR (SEC_001). Ambito dentro del SP: la facultad del decano es de la institucion del
--     administrador; si no (o el decano no existe), DEC_001 (404).
--   * @estaActivo NULL invierte el estado actual (la ruta HTTP es un toggle). Idempotente.
--   * DEC_002 (409): no se desactiva al decano de una facultad con algun Programa activo (lectura con bloqueo).
--   * Regla D1: personaSinRolesActivos se calcula DESPUES de actualizar Decano.estado (uv_usuario_perfil ya filtrada);
--     Usuario.estado pasa a 0 solo si la persona no conserva otro rol activo y vuelve a 1 al reactivar.
-- SET XACT_ABORT ON; transaccion propia o savepoint; un rechazo de negocio no escribe ni hace ROLLBACK.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_cambiar_estado_decano]
(
    @idDecano          UNIQUEIDENTIFIER,
    @estaActivo        BIT = NULL,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
    DECLARE @idUsuarioDecano         UNIQUEIDENTIFIER = NULL;
    DECLARE @estadoActual            BIT = NULL;
    DECLARE @estadoDestino           BIT = NULL;
    DECLARE @personaSinRolesActivos  BIT = 0;
    DECLARE @nombrePrograma          NVARCHAR(200) = NULL;
    DECLARE @codigoRechazo           VARCHAR(20) = NULL;

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;
    DECLARE @mutacionRealizada          BIT = 0;
    DECLARE @estadoTransaccionCatch     INT;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: correlacion y ejecutor obligatorios
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 2: RBAC ADMINISTRADOR
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutor,
                @codigoPerfilRequerido = 'ADMINISTRADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: transaccion; decano de una facultad de la institucion del administrador (DEC_001), bajo bloqueo
        IF @estadoResultado = 1
        BEGIN
            SET @conteoTransaccionesInicial = @@TRANCOUNT;
            IF @conteoTransaccionesInicial = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_cambiar_estado_decano;
                SET @savepointCreado = 1;
            END

            SELECT @idUsuarioDecano = d.usuario, @estadoActual = d.estado
            FROM dbo.Decano d WITH (UPDLOCK, HOLDLOCK)
            WHERE d.id = @idDecano
              AND EXISTS (SELECT 1 FROM dbo.Facultad f
                          INNER JOIN dbo.Administrador ad ON ad.institucion = f.institucion
                          WHERE f.decano = d.id AND ad.usuario = @idUsuarioEjecutor);

            IF @idUsuarioDecano IS NULL
                SET @codigoRechazo = 'DEC_001';
            ELSE
            BEGIN
                SET @estadoDestino = IIF(@estaActivo IS NULL, IIF(@estadoActual = 1, 0, 1), @estaActivo);

                -- DEC_002: no se desactiva al decano de una facultad con algun programa activo
                IF @estadoDestino = 0
                BEGIN
                    SELECT TOP 1 @nombrePrograma = p.nombre
                    FROM dbo.Programa p WITH (UPDLOCK, HOLDLOCK)
                    INNER JOIN dbo.Facultad f ON f.id = p.facultad
                    WHERE f.decano = @idDecano AND p.estado = 1;

                    IF @nombrePrograma IS NOT NULL
                        SET @codigoRechazo = 'DEC_002';
                END

                IF @codigoRechazo IS NULL
                BEGIN
                    UPDATE dbo.Decano SET estado = @estadoDestino WHERE id = @idDecano AND estado <> @estadoDestino;
                    SET @mutacionRealizada = 1;

                    -- D1: despues del cambio (uv_usuario_perfil ya refleja Decano.estado)
                    IF @estadoDestino = 0
                        SET @personaSinRolesActivos = IIF(dbo.ufn_usuario_tiene_roles_activos(@idUsuarioDecano) = 0, 1, 0);

                    IF @estadoDestino = 1 OR @personaSinRolesActivos = 1
                    BEGIN
                        EXEC dbo.usp_cambiar_estado_usuario_interno
                            @idUsuario = @idUsuarioDecano,
                            @estaActivo = @estadoDestino,
                            @idCorrelacion = @idCorrelacionDefecto,
                            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                            @estadoResultado = @estadoResultado OUTPUT;
                    END

                    IF @estadoResultado = 1
                    BEGIN
                        EXEC dbo.usp_obtener_mensaje_catalogo
                            @p_codigo = 'DEC_003', @p_param1 = @idDecano,
                            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    END
                END
            END

            -- Cierre respetando el ownership (revierte solo si escribio y fallo despues)
            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1
                BEGIN
                    IF @estadoResultado = 1 OR @mutacionRealizada = 0
                        COMMIT TRANSACTION;
                    ELSE
                        ROLLBACK TRANSACTION;
                END
                ELSE IF XACT_STATE() = -1
                    ROLLBACK TRANSACTION;
            END
            ELSE IF @savepointCreado = 1 AND XACT_STATE() = 1 AND @estadoResultado = 0 AND @mutacionRealizada = 1
                ROLLBACK TRANSACTION sp_cambiar_estado_decano;
        END

        -- PASO 4: mensaje de rechazo por catalogo (sin escrituras)
        IF @estadoResultado = 1 AND @codigoRechazo IS NOT NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoRechazo, @p_param1 = @idDecano, @p_param2 = @nombrePrograma,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
    END TRY
    BEGIN CATCH
        SET @estadoTransaccionCatch = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @@TRANCOUNT > 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
            ROLLBACK TRANSACTION sp_cambiar_estado_decano;

        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
            THROW;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado,
        idUsuario               = IIF(@estadoResultado = 1, @idUsuarioDecano, NULL),
        personaSinRolesActivos  = IIF(@estadoResultado = 1, @personaSinRolesActivos, CAST(0 AS BIT)),
        estaActivoDecano        = IIF(@estadoResultado = 1, @estadoDestino, NULL);
END;
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_buscar_estudiante_por_documento_grupo (CULM-001 A.2-15; DEC-027; F-DOC-013; CONTRACT §8.2.3 A2-DB-9)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW ante ejecutor nulo, fuera de ambito o documento
-- invalido). Busqueda del estudiante a matricular a mano (GET /api/v1/grupos/{grupoId}/estudiantes/busqueda) y unica via
-- para resolver el estudiante de una matricula manual sin correo:
--   * Titularidad dentro del SP: el ejecutor debe ser el DOCENTE titular del grupo (Grupo.docente -> Docente.usuario);
--     si no, o el grupo no existe: THROW 51000 con DBCODE=SEC_002 (403).
--   * Documento nulo o @numeroIdentificacion <= 0: THROW 51000 con DBCODE=VAL_001 (400).
--   * Busqueda EXACTA por (Usuario.tipoIdIdentificacion, Usuario.numeroIdentificacion) de un usuario CON fila Estudiante
--     (un usuario que solo es docente, coordinador, decano o administrador da 0 filas). Sin LIKE y sin listar: 0 o 1 fila.
--   * Alcance institucional: solo devuelve al estudiante si no tiene vinculos (alta pendiente de matricula; excepcion
--     deliberada al fail-closed de DEC-031 §3, A2-C1) o si alguno de sus vinculos (EstudiantePrograma o EstudianteGrupo)
--     es de la institucion del grupo. Uno de otra institucion da 0 filas, igual que uno inexistente.
--   * Datos minimos: nombres, nombreCompleto, numeroIdentificacion, correoEnmascarado (primer caracter + '***' +
--     '@dominio'; el correo real nunca sale) y codigoEstadoMatriculaGrupo (su matricula en ESE grupo o NULL).
-- Solo lectura.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_buscar_estudiante_por_documento_grupo]
(
    @idGrupo              UNIQUEIDENTIFIER,
    @idTipoIdentificacion UNIQUEIDENTIFIER,
    @numeroIdentificacion INT,
    @idCorrelacion        UNIQUEIDENTIFIER,
    @idUsuarioEjecutor    UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idInstitucionGrupo   UNIQUEIDENTIFIER;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- PASO 1: correlacion obligatoria
    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    -- PASO 2: ejecutor obligatorio (VAL_001)
    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001', @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    -- PASO 3: titularidad del docente ejecutor sobre el grupo (SEC_002)
    IF @estadoResultado = 1
       AND NOT EXISTS (SELECT 1 FROM dbo.Grupo g
                       INNER JOIN dbo.Docente d ON d.id = g.docente
                       INNER JOIN dbo.Usuario u ON u.id = d.usuario
                       WHERE g.id = @idGrupo AND d.usuario = @idUsuarioEjecutor AND u.estado = 1)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SEC_002',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    -- PASO 4: documento obligatorio y positivo (VAL_001)
    IF @estadoResultado = 1 AND (@idTipoIdentificacion IS NULL OR @numeroIdentificacion IS NULL OR @numeroIdentificacion <= 0)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001', @p_param1 = 'numeroIdentificacion',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    -- PASO 5: institucion del grupo
    SELECT @idInstitucionGrupo = f.institucion
    FROM dbo.Grupo g
    INNER JOIN dbo.Asignatura a ON a.id = g.asignatura
    INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = a.semestrePlanEstudio
    INNER JOIN dbo.PlanEstudio pe ON pe.id = spe.planEstudio
    INNER JOIN dbo.Programa p ON p.id = pe.programa
    INNER JOIN dbo.Facultad f ON f.id = p.facultad
    WHERE g.id = @idGrupo;

    -- PASO 6: busqueda exacta de un estudiante, con alcance institucional y datos minimos
    SELECT TOP 1
        idEstudiante               = e.id,
        primerNombre               = u.primerNombre,
        segundoNombre              = u.segundoNombre,
        primerApellido             = u.primerApellido,
        segundoApellido            = u.segundoApellido,
        nombreCompleto             = CAST(CONCAT(LTRIM(RTRIM(CONCAT(u.primerNombre, N' ', u.segundoNombre))), N' ',
                                         LTRIM(RTRIM(CONCAT(u.primerApellido, N' ', u.segundoApellido)))) AS NVARCHAR(400)),
        numeroIdentificacion       = u.numeroIdentificacion,
        correoEnmascarado          = CAST(IIF(CHARINDEX(N'@', u.correo) > 1,
                                         CONCAT(LEFT(u.correo, 1), N'***', SUBSTRING(u.correo, CHARINDEX(N'@', u.correo), LEN(u.correo))),
                                         CONCAT(LEFT(u.correo, 1), N'***')) AS NVARCHAR(120)),
        codigoEstadoMatriculaGrupo = (SELECT TOP 1 es.codigo FROM dbo.EstudianteGrupo eg
                                      INNER JOIN dbo.uv_estado_estudiante_grupo es ON es.id = eg.estado
                                      WHERE eg.estudiante = e.id AND eg.grupo = @idGrupo
                                      ORDER BY eg.id)
    FROM dbo.Usuario u
    INNER JOIN dbo.Estudiante e ON e.usuario = u.id
    WHERE u.tipoIdIdentificacion = @idTipoIdentificacion
      AND u.numeroIdentificacion = @numeroIdentificacion
      AND (
            -- sin vinculos: alta pendiente de matricula (A2-C1)
            (NOT EXISTS (SELECT 1 FROM dbo.EstudiantePrograma ep WHERE ep.estudiante = e.id)
             AND NOT EXISTS (SELECT 1 FROM dbo.EstudianteGrupo eg WHERE eg.estudiante = e.id))
            -- algun vinculo en la institucion del grupo
            OR EXISTS (SELECT 1 FROM dbo.EstudiantePrograma ep
                       INNER JOIN dbo.Programa p ON p.id = ep.programa
                       INNER JOIN dbo.Facultad f ON f.id = p.facultad
                       WHERE ep.estudiante = e.id AND f.institucion = @idInstitucionGrupo)
            OR EXISTS (SELECT 1 FROM dbo.EstudianteGrupo eg
                       INNER JOIN dbo.Grupo g ON g.id = eg.grupo
                       INNER JOIN dbo.Asignatura a ON a.id = g.asignatura
                       INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = a.semestrePlanEstudio
                       INNER JOIN dbo.PlanEstudio pe ON pe.id = spe.planEstudio
                       INNER JOIN dbo.Programa p ON p.id = pe.programa
                       INNER JOIN dbo.Facultad f ON f.id = p.facultad
                       WHERE eg.estudiante = e.id AND f.institucion = @idInstitucionGrupo)
          )
    ORDER BY e.id;
END;
GO

-- U14-5: grants del runtime (SP publicos nuevos; DENY al interno de solape).
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 paquete A.2 (CONTRACT §8.2): EXECUTE del runtime sobre los SP PUBLICOS nuevos. Cada SP aplica su ambito
-- dentro (ADMINISTRADOR institucion, COORDINADOR programas, DOCENTE titularidad, ESTUDIANTE propietario). Ningun
-- GRANT a internos: usp_validar_solape_sesion_interno queda con DENY, como los demas nucleos *_sesion_interno, y
-- usp_internal_reactivar_matricula_retirada (A.1) sin permiso. Script aditivo e idempotente.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_consultar_directorio_estudiantes_paginado', N'P') IS NULL
    THROW 52301, 'CULM001_A_RUNTIME_GRANT: usp_consultar_directorio_estudiantes_paginado requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_estudiantes_grupo_ambito_paginado', N'P') IS NULL
    THROW 52302, 'CULM001_A_RUNTIME_GRANT: usp_consultar_estudiantes_grupo_ambito_paginado requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_asistencias_grupo_ambito_paginado', N'P') IS NULL
    THROW 52303, 'CULM001_A_RUNTIME_GRANT: usp_consultar_asistencias_grupo_ambito_paginado requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_materias_estudiante', N'P') IS NULL
    THROW 52304, 'CULM001_A_RUNTIME_GRANT: usp_consultar_materias_estudiante requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_horario_estudiante', N'P') IS NULL
    THROW 52305, 'CULM001_A_RUNTIME_GRANT: usp_consultar_horario_estudiante requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_retirar_solicitud_revision_asistencia', N'P') IS NULL
    THROW 52306, 'CULM001_A_RUNTIME_GRANT: usp_retirar_solicitud_revision_asistencia requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_cambiar_estado_decano', N'P') IS NULL
    THROW 52307, 'CULM001_A_RUNTIME_GRANT: usp_cambiar_estado_decano requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_buscar_estudiante_por_documento_grupo', N'P') IS NULL
    THROW 52308, 'CULM001_A_RUNTIME_GRANT: usp_buscar_estudiante_por_documento_grupo requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_validar_solape_sesion_interno', N'P') IS NULL
    THROW 52309, 'CULM001_A_RUNTIME_GRANT: usp_validar_solape_sesion_interno requerido ausente.', 1;
GO

GRANT EXECUTE ON [dbo].[usp_consultar_directorio_estudiantes_paginado] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_estudiantes_grupo_ambito_paginado] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_asistencias_grupo_ambito_paginado] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_materias_estudiante] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_horario_estudiante] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_retirar_solicitud_revision_asistencia] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_cambiar_estado_decano] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_buscar_estudiante_por_documento_grupo] TO [rol_asistencias_runtime];
DENY EXECUTE ON [dbo].[usp_validar_solape_sesion_interno] TO [rol_asistencias_runtime];
GO

-- U14-6: verificacion final.
USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
DECLARE @nuevos INT = (SELECT COUNT(*) FROM sys.procedures WHERE name IN (N'usp_validar_solape_sesion_interno', N'usp_consultar_directorio_estudiantes_paginado', N'usp_consultar_estudiantes_grupo_ambito_paginado', N'usp_consultar_asistencias_grupo_ambito_paginado', N'usp_consultar_materias_estudiante', N'usp_consultar_horario_estudiante', N'usp_retirar_solicitud_revision_asistencia', N'usp_cambiar_estado_decano', N'usp_buscar_estudiante_por_documento_grupo'));
DECLARE @grants INT = (SELECT COUNT(*) FROM sys.database_permissions dp INNER JOIN sys.procedures p ON p.object_id = dp.major_id
                       WHERE dp.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') AND dp.state = 'G'
                         AND p.name IN (N'usp_consultar_directorio_estudiantes_paginado', N'usp_consultar_estudiantes_grupo_ambito_paginado', N'usp_consultar_asistencias_grupo_ambito_paginado', N'usp_consultar_materias_estudiante', N'usp_consultar_horario_estudiante', N'usp_retirar_solicitud_revision_asistencia', N'usp_cambiar_estado_decano', N'usp_buscar_estudiante_por_documento_grupo'));
PRINT CONCAT('CULM001_A_UP14 sp_nuevos=', @nuevos, ' grants=', @grants, ' Decano.estado=', IIF(COL_LENGTH('dbo.Decano', 'estado') IS NULL, 'AUSENTE', 'presente'));
GO
