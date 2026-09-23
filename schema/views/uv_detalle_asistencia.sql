USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER  VIEW [dbo].[uv_detalle_asistencia]
AS
SELECT		id = da.id,
			codigo = da.codigo,
			idAsistencia = asi.id,
			asistio = da.asistio,
			idRazonCausa = rc.id,
			nombreRazonCausa = rc.nombre,
			codigoRazonCausa = rc.codigo,
			fechaHoraInicio = da.fechaHoraInicio,
			fechaHoraFin = da.fechaHoraFin

FROM		DetalleAsistencia da
INNER JOIN	uv_asistencia asi
ON			da.asistencia = asi.id
INNER JOIN	uv_razon_causa rc
ON			da.razonCausa = rc.id
GO
