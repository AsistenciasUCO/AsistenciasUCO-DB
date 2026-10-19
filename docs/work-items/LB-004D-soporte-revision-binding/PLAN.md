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

## Alcance D1 (ONE_TABLE) — implementado en rama, pendiente de aprobacion del owner DB

- Nuevos: `schema/tables/ArchivoSoporte.sql`, `schema/seed/15_lb004d_archivo_soporte.sql`,
  `schema/security/rol_asistencias_runtime_lb004d.sql`, cuatro SP (`usp_registrar_archivo_soporte`,
  `usp_radicar_solicitud_revision_asistencia_v2`, `usp_consultar_archivo_soporte_autorizado`,
  `usp_consultar_solicitudes_revision_docente`), `test/test_lb004d_support_binding.sql`,
  `test/test_lb004d_concurrency.ps1`, manifest `DB_LB004D_SUPPORT_BINDING_MANIFEST.sha256`.
- Extendidos (aditivo): `schema/tables/zz_foreign_keys.sql` (2 FK), `test/test_contract_closure.sql`
  (R1/R2 como `READ_QUERY_RESULTSET`), `test_suite.sql`, `test_summary.ps1` (ids criticos).
- No tocados: manifest Golden Path, `usp_radicar_solicitud_revision_asistencia.sql` (v1),
  `usp_resolver_...`, `uv_*`, `rol_asistencias_runtime.sql`, `03_parametro.sql`, `04_mensaje.sql`.
- Variable principal: `SUPPORT_BINDING_DURABLE`.
- Rollback: los objetos son nuevos; retirar grants, SP y tabla (en ese orden) devuelve el AS-IS.
  La v1 nunca deja de funcionar.

## Definition of Ready

```text
DOR: READY_FOR_OWNER_REVIEW (arquitectura ONE_TABLE decidida por el solicitante)
LB004D_CONTRACT_APPROVED: NO — falta la revision de John (firmas, grants, Q5, Q6, Q9)
INDEPENDIENTE DEL BLOQUEO: backend B1 y frontend F1 pueden construirse contra este contrato en ramas;
  no se fusiona nada sin la aprobacion del owner DB
```
