---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-26
---

# TEST_PLAN — HU096-HU097-HU098-periodos-academicos

Archivo: `test/test_usp_periodo_academico_gestion.sql` (registrado en `test_suite.sql`).

| ID | Escenario |
|---|---|
| T-096-01 | El administrador crea un período en su institución; `codigo` y `anio` se derivan de `fechaInicio`. |
| T-096-02 | Segundo semestre ⇒ código terminado en 2. |
| T-096-03 | Rechazos: id nulo, duplicado, fechas inválidas, COORDINADOR, DECANO, DOCENTE, administrador de institución inactiva y ejecutor nulo. |
| T-097-01 | El administrador modifica; `codigo` y `anio` se recalculan; conservar el nombre está permitido. |
| T-097-02 | Rechazos al modificar. |
| T-098-01 | Eliminar solo sin grupos; inexistente `PER_001`; DECANO rechazado. |
