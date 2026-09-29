---
name: consulta-a-bd
description: >-
  Estándar obligatorio para todas las lecturas a la base de datos gestionasistenciadb, exigiendo el uso exclusivo de Vistas (uv_* / uv_auth_*) y prohibiendo consultas directas a tablas físicas.
---

# Estándar de Consulta a Base de Datos (`consulta-a-bd`)

## Regla Principal de Lectura de Datos

Esta documentación establece la directiva obligatoria de acceso a datos de lectura en la base de datos `gestionasistenciadb`.

### 🛡️ Regla Fundamental
> **1. Inmutabilidad de Nombres Preexistentes: Queda estrictamente prohibido cambiar o renombrar las tablas, vistas (`uv_*` / `uv_auth_*`), funciones (`ufn_*`) y procedimientos almacenados (`usp_*` / `*_interno`) que ya hayan sido creados en la base de datos.**
> **2. Acceso por Vistas: Todas las consultas de lectura (`SELECT`) a la base de datos deben realizarse exclusivamente por medio de la Capa de Vistas (`uv_*` o `uv_auth_*`). Queda estrictamente prohibido realizar consultas directas sobre las tablas físicas del Modelo Entidad-Relación (MER).**

---

## Directivas por Capa de Consumo

### 1. Consumo Externo (API Backend / Frontend)
* **Obligatoriedad de Vistas Autorizadas (`uv_auth_*`)**: Toda lectura solicitada por la API Backend o clientes externos debe consumir únicamente las vistas de la capa `uv_auth_*` (ej. `uv_auth_docente`, `uv_auth_grupo`, `uv_auth_sesion`, `uv_auth_asistencia`).
* **Seguridad y Roles**: Estas vistas aplican la doble validación de perfil (**RBAC**) y delimitación de custodia jerárquica basada en `SESSION_CONTEXT('idUsuarioEjecutor')`.

---

### 2. Consumo Interno (Procedimientos Almacenados `usp_*` y `*_interno`)
* **Obligatoriedad de Vistas Base (`uv_*`)**: Cuando un procedimiento almacenado público u orquestador (`usp_*`) o un procedimiento interno (`*_interno`) necesite consultar datos para validar reglas de negocio, cruces de horarios o cupos, debe consultar directamente sobre las **vistas base (`uv_*`)** (ej. `uv_docente`, `uv_estudiante_grupo`, `uv_sesion`).
* **Sin Riesgo de Regresión**: Las vistas base `uv_*` están libres de filtros de sesión, lo que garantiza que los procedimientos de negocio evalúen la totalidad de los datos sin silenciar registros durante transacciones reactivas.

---

## Excepciones Únicas Permitidas

La consulta directas a una tabla física (`SELECT ... FROM dbo.Tabla`) solo se permite en los siguientes escenarios puntuales:
1. **Comprobación de Existencia Pura en Transacciones Internas**: Clausulas de tipo `IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @idUsuario)` o similares dentro de procedimientos `*_interno` donde se requiera comprobar la presencia atómica de la PK en la tabla física antes de una inserción/actualización.
2. **Scripts de Mantenimiento y Semillas**: Scripts de despliegue (`schema/seed/`) o migraciones administradas directamente por el DBA.

---

## Ventajas Técnicas del Estándar

1. **Desacoplamiento Total**: Si el esquema físico en `schema/tables/` sufre algún ajuste interno, las vistas absorben el cambio sin romper las consultas de los procedimientos ni del Backend.
2. **Abstracción de Lógica Compuesta**: Las vistas encapsulan lógica recurrente como nombres completos (`nombreCompleto`), cálculo de cupos disponibles, concatenaciones de estado (`estaActivoTexto`) y joins jerárquicos.
3. **Optimización del Motor SQL**: SQL Server optimiza el plan de ejecución deduplicando joins sobre las vistas reutilizables en lugar de repetir subconsultas arbitrarias sobre tablas base.
