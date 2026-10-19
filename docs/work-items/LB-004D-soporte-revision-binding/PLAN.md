---
status: proposed
type: work-item
scope: database
owner: database-team
system: gestionasistenciadb
last-reviewed: 2026-10-19
---

# PLAN — LB-004D: vínculo durable soporte ↔ solicitud de revisión

## Identidad

- Base: `develop` `7d9c050` (merge del PR #37, P0-D). `DB_P0D_MERGED: YES`.
- Consumidor: backend `alejovh12/AsistenciasUCO` `develop` `e6c4df6` (PR #27, MinIO + ClamAV),
  handoff `docs/work-items/LB-004-stateless-serverless-readiness/DB_BINDING_HANDOFF.md`.
- Fase actual: **D0 — análisis contractual**. Sin cambios en `schema/`, `test/` ni `migrations/`.

## Entregables D0

| Documento | Contenido |
|---|---|
| [ADR-LB004D-001](ADR-LB004D-001.md) | Alternativas, decisión propuesta, hallazgos H-01…H-06, bloque de aprobación |
| [CONTRACT_PROPOSAL](CONTRACT_PROPOSAL.md) | Tablas, SP, estados, idempotencia, concurrencia, retención, permisos, preguntas Q1…Q10 |
| [INTERACTIONS](INTERACTIONS.md) | Secuencias de subida, radicación, descarga y reconciliación, con fallas y compensación |
| [TEST_MATRIX](TEST_MATRIX.md) | Pruebas SQL, backend, frontend y E2E |

## Alcance D1 (solo tras aprobación)

- Rutas permitidas: `schema/tables/ArchivoSoporte*.sql`, `schema/tables/zz_foreign_keys.sql`
  (aditivo), SP nuevos de la propuesta, `schema/seed/03_parametro.sql` y `04_mensaje.sql`
  (aditivo), `schema/security/rol_asistencias_runtime.sql` (grants aditivos), `deploy_schema.ps1`
  (orden), `test/test_lb004d_support_binding.sql`, `test_suite.sql`, manifest LB-004D, este work item.
- Rutas prohibidas: fuentes del manifest Golden Path, `usp_radicar_solicitud_revision_asistencia.sql`
  (v1), `usp_resolver_…`, `uv_*` existentes, `DB_BASELINE_CONTRACT.md`.
- Variable principal: `SUPPORT_BINDING_DURABLE`.
- Rollback: los objetos son nuevos; retirar grants, SP y tablas (en ese orden) devuelve el AS-IS.
  La v1 nunca deja de funcionar.

## Definition of Ready

```text
DOR: NOT_READY
BLOQUEO: aprobación del owner DB (ADR §7) y respuestas Q1–Q10
INDEPENDIENTE DEL BLOQUEO: nada en schema/test hasta la aprobación
```
