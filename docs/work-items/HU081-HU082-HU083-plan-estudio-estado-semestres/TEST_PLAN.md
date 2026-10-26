---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-26
---

# TEST_PLAN — HU081-HU082-HU083-plan-estudio-estado-semestres

Archivo: `test/test_usp_plan_estudio_estado_semestres.sql` (registrado en `test_suite.sql`).

| ID | Escenario |
|---|---|
| T-081-01 | Inactivar, idempotencia y reactivación del plan propio; `uv_plan_estudio` refleja el estado. |
| T-081-02 | Plan ajeno (`SEC_002`), ejecutor sin rol (`SEC_001`), plan inexistente (`PLA_002`) y parámetros obligatorios; ningún rechazo modifica el plan. |
| T-082-01 | Altas consecutivas desde un plan sin semestres. |
| T-082-02 | No supera el máximo del catálogo `dbo.Semestre` (`PLA_003`). |
| T-082-03 | Plan ajeno (`SEC_002`) y plan inexistente (`PLA_002`). |
| T-083-01 | Semestre intermedio (`PLA_005`), semestre ajeno al plan (`PLA_004`) y semestre con asignaturas, aunque inactivas (`PLA_006`). |
| T-083-02 | Quitar el último semestre vacío, ámbito y parámetros obligatorios. |
