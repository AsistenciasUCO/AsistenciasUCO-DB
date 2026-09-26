---
name: consistencia-tablas
description: >-
  Estándar de integridad de esquema físico y salvaguarda estructural para tablas de dominio en gestionasistenciadb. Requiere confirmación humana explícita antes de modificar tablas.
---

# Guía y Protocolo de Consistencia de Tablas de Dominio

## Propósito y Filosofía del Esquema Físico

El modelo de datos físico ubicado en la carpeta `schema/tables/` representa la estructura canónica y consolidada de las entidades de dominio de la base de datos `gestionasistenciadb`.

### Regla Principal de Invariabilidad Estructural
1. **Protección de Atributos Existentes**: Por norma general, **no se deben agregar nuevos atributos, alterar tipos de datos ni modificar la estructura de las tablas de dominio** de forma arbitraria.
2. **Solución en Capas de Lectura**: Las necesidades de consulta, agregación, cálculo o formato deben resolverse mediante las capas de vistas base (`uv_*`), vistas autorizadas (`uv_auth_*`) o lógica del Backend/API, preservando la integridad del Modelo Entidad-Relación (MER).

---

## Protocolo Obligatorio para Modificaciones en Tablas (`schema/tables/`)

Si un requisito de negocio crítico exige **estrictamente** realizar cambios en el esquema físico (ej. agregar un nuevo atributo, modificar llaves o constraints):

### ⚠️ Advertencia y Pausa Operativa (Requisito de Autorización Humana)
* **Prohibición de Modificación Directa Automática**: El asistente o desarrollador NO debe aplicar cambios DDL en los scripts de `schema/tables/*.sql` de forma autónoma.
* **Análisis de Impacto Previo**: Se debe presentar previamente un informe de impacto que evalúe:
  1. **Vistas Afectadas**: Identificar vistas base (`uv_*`) y vistas autorizadas (`uv_auth_*`) que consumen la tabla.
  2. **Procedimientos Afectados**: Identificar procedimientos almacenados públicos (`usp_*`) e internos (`*_interno`) involucrados en inserciones o actualizaciones sobre la tabla.
  3. **Impacto en Pruebas y Semillas**: Identificar datos de prueba (`schema/seed/`) y scripts de pruebas unitarias (`test/`).
* **Aprobación Humana Explícita**: Antes de ejecutar o modificar cualquier archivo de tabla, se debe solicitar y obtener la confirmación expresa del usuario humano.

---

## Flujo de Trabajo Ante un Cambio Autorizado

Una vez aprobada la modificación por el usuario:
1. Modificar únicamente la tabla correspondiente en `schema/tables/`.
2. Propagar los cambios en las vistas correspondientes (`uv_*` / `uv_auth_*`).
3. Actualizar los procedimientos almacenados que consuman o inserten la entidad.
4. Ajustar los scripts de prueba y semillas (`schema/seed/`).
5. Ejecutar la compilación y suite de pruebas (`deploy_schema.ps1` y `test_summary.ps1`) asegurando que el `DB GATE PASS` concluya con éxito (`Exit Code 0`).
