USE [gestionasistenciadb];
GO

SET NOCOUNT ON;

-- Regla de John (2026-11-04): Perfil, TipoIdentificacion, TipoPrograma, Semestre, Componente, Area,
-- EstadoEstudianteGrupo, RazonCausa, Estado y Dia son catalogos de solo consulta (carga inicial por seed). Elimina de
-- las bases ya desplegadas los SP de escritura de TipoIdentificacion (HU153), TipoPrograma (HU154) y Area (HU151/HU152).
-- Al eliminarlos tambien se retiran sus GRANT EXECUTE. deploy_schema.ps1 no borra objetos. Idempotente. La columna
-- estado de Area y TipoPrograma se conserva (la fija el seed). Las consultas siguen por uv_area y uv_tipo_programa.
IF OBJECT_ID(N'dbo.usp_guardar_tipo_identificacion', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_guardar_tipo_identificacion];
GO
IF OBJECT_ID(N'dbo.usp_guardar_tipo_identificacion_interno', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_guardar_tipo_identificacion_interno];
GO
IF OBJECT_ID(N'dbo.usp_crear_area', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_crear_area];
GO
IF OBJECT_ID(N'dbo.usp_crear_area_interno', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_crear_area_interno];
GO
IF OBJECT_ID(N'dbo.usp_actualizar_area', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_actualizar_area];
GO
IF OBJECT_ID(N'dbo.usp_actualizar_area_interno', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_actualizar_area_interno];
GO
IF OBJECT_ID(N'dbo.usp_cambiar_estado_area', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_cambiar_estado_area];
GO
IF OBJECT_ID(N'dbo.usp_cambiar_estado_area_interno', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_cambiar_estado_area_interno];
GO
IF OBJECT_ID(N'dbo.usp_crear_tipo_programa', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_crear_tipo_programa];
GO
IF OBJECT_ID(N'dbo.usp_crear_tipo_programa_interno', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_crear_tipo_programa_interno];
GO
IF OBJECT_ID(N'dbo.usp_actualizar_tipo_programa', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_actualizar_tipo_programa];
GO
IF OBJECT_ID(N'dbo.usp_actualizar_tipo_programa_interno', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_actualizar_tipo_programa_interno];
GO
IF OBJECT_ID(N'dbo.usp_cambiar_estado_tipo_programa', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_cambiar_estado_tipo_programa];
GO
IF OBJECT_ID(N'dbo.usp_cambiar_estado_tipo_programa_interno', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_cambiar_estado_tipo_programa_interno];
GO
