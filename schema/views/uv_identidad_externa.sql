USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SEC-BASELINE-017: lectura del vinculo (emisor, sujeto) -> Usuario.id. Expone solo lo necesario para resolver la
-- identidad en peticiones posteriores; no incluye contrasenas ni datos personales.
CREATE OR ALTER VIEW [dbo].[uv_identidad_externa]
AS
SELECT		ie.id,
			idUsuario = ie.usuario,
			emisor = ie.emisor,
			sujeto = ie.sujeto,
			correoVinculacion = ie.correoVinculacion,
			estaVigenteIdentidad = ie.estado,
			fechaVinculacion = ie.fechaVinculacion,
			fechaRevocacion = ie.fechaRevocacion
FROM		IdentidadExterna ie
GO
