---
name: vista-consulta-con-validaciones
description: >-
  Estándar canónico y especificación para la creación de Vistas Autorizadas (uv_auth_*) consumidas por el Frontend/API con doble validación de Rol (RBAC) y Autorización por Dominio.
---

# Estándar de Vistas de Consulta con Validaciones (`uv_auth_*`)

## Propósito de la Capa de Vistas Autorizadas

Esta documentación define el estándar obligatorio para todas las vistas de consulta destinadas a ser consumidas directamente por la API Backend y la interfaz de usuario (Frontend). 

Garantiza que toda información leída por la aplicación cumpla con el modelo de seguridad a nivel de datos (**Data-Level Security / RBAC**) sin alterar las vistas base (`uv_*`) consumidas por la lógica transaccional interna (`*_interno`).

---

## Reglas Estructurales Obligatorias

### 1. Inmutabilidad de Nombres Preexistentes
* **Prohibición de Renombrado**: Queda **estrictamente prohibido modificar los nombres de las vistas autorizadas, vistas base, tablas, funciones o procedimientos almacenados ya creados**. La nomenclatura de todos los objetos existentes es inalterable.

### 2. Convención de Nomenclatura y Prefijo `uv_auth_*`
* Toda vista expuesta al consumo externo (Frontend / API) que requiera control de acceso debe iniciar obligatoriamente con el prefijo `uv_auth_` seguido del nombre de la entidad en singular (ej. `uv_auth_institucion`, `uv_auth_facultad`, `uv_auth_decano`, `uv_auth_programa`, `uv_auth_coordinador`, `uv_auth_docente`, `uv_auth_estudiante`, `uv_auth_grupo`, `uv_auth_sesion`, `uv_auth_asistencia`, `uv_auth_solicitud_revision_asistencia`, `uv_auth_periodo_academico`).

### 2. Doble Validación Obligatoria: Rol (RBAC) + Autorización por Ámbito
Toda vista `uv_auth_*` debe incorporar obligatoriamente la combinación de dos niveles de validación:
1. **Validación de Rol (Perfil Activo)**: Determina qué perfil tiene el usuario en la sesión (`ADMINISTRADOR`, `DECANO`, `COORDINADOR`, `DOCENTE`, `ESTUDIANTE`) evaluado a través de `dbo.ufn_obtener_usuario_ejecutor_contexto()`.
2. **Validación de Autorización de Ámbito (Custodia Jerárquica)**: Restringe el universo de filas devueltas al dominio autorizado según el rol:
   * **`ADMINISTRADOR` (`AD`)**: Acceso delimitado a los datos de la **Institución** a la que pertenece el administrador (`a.institucion = entidad.idInstitucion`).
   * **`DECANO` (`DE`)**: Acceso delimitado a los datos de la **Facultad** que tiene asignada a su cargo (`f.decano = d.id`).
   * **`COORDINADOR` (`CD`)**: Acceso delimitado a los datos del **Programa Académico** coordinado (`pr.coordinador = c.id`).
   * **`DOCENTE` (`DO`)**: Acceso delimitado a los **Grupos, Asignaturas y Sesiones** donde figura como docente titular (`g.docente = doc.id`).
   * **`ESTUDIANTE` (`ES`)**: Acceso delimitado a sus datos de identidad propios y a los **Grupos y Asistencias** donde está matriculado (`eg.estudiante = e.id`).

### 3. Comportamiento por Defecto (Contexto `NULL`)
* Si `dbo.ufn_obtener_usuario_ejecutor_contexto()` retorna `NULL` (ej. scripts de mantenimiento, tareas de fondo o administración global sin sesión iniciada), la vista `uv_auth_*` debe retornar la totalidad de las filas por defecto (`dbo.ufn_obtener_usuario_ejecutor_contexto() IS NULL OR EXISTS (...)`), evitando el bloqueo del motor.

### 4. Desacoplamiento Total de las Vistas Base (`uv_*`)
* Las vistas base `uv_*` permanecen **100% libres de filtros de autorización** para que los procedimientos almacenados internos (`*_interno`) ejecuten validaciones relacionales y transacciones reactivas sin riesgos de silenciar registros.

---

## Estructura Canónica de una Vista Autorizada (`uv_auth_*`)

```sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW [dbo].[uv_auth_entidad]
AS
SELECT  e.id,
        e.nombre,
        e.idInstitucion,
        e.idFacultad
FROM    dbo.uv_entidad e
WHERE   dbo.ufn_obtener_usuario_ejecutor_contexto() IS NULL
   -- 1. Validación de Ámbito Administrador
   OR   EXISTS (
            SELECT 1 FROM dbo.Administrador a 
            WHERE a.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() 
              AND a.institucion = e.idInstitucion
        )
   -- 2. Validación de Ámbito Decano
   OR   EXISTS (
            SELECT 1 FROM dbo.Decano d 
            INNER JOIN dbo.Facultad f ON d.id = f.decano 
            WHERE d.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() 
              AND f.id = e.idFacultad
        )
   -- 3. Validación de Pertenece al Usuario Propio
   OR   e.idUsuario = dbo.ufn_obtener_usuario_ejecutor_contexto();
GO
```

### Composición entre Vistas Autorizadas
Para entidades dependientes (ej. Sesiones, Asistencias, Solicitudes de Revisión), las vistas autorizadas deben componerse sobre otras vistas `uv_auth_*` existentes (ej. `uv_auth_sesion` sobre `uv_auth_grupo`), garantizando la propagación heredada de las reglas de seguridad sin duplicar código.
