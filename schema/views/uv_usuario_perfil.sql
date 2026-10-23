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
