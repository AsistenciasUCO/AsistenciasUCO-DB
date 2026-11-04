---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-04
---

# VALIDATION — CAT-01-catalogos-solo-consulta

| Comando | Resultado |
|---|---|
| `migrations/11_catalogos_solo_consulta_up.sql` sobre el SQL Server local (2026-11-04) | exit 0; sin SP de escritura de catálogos base |
| `down` y luego `up` otra vez | exit 0: el rollback restaura los 14 SP y la migración los vuelve a eliminar (idempotente) |
| `test_consolidado_auditoria_catalogos.sql`, `test_runtime_grants_backend_inventory.sql`, `test_uv_area_contrato.sql`, `test_uv_tipo_programa_contrato.sql`, `test_subject_catalog.sql` en local | `TEST_PASS` (incluye T-153-01: sin SP de escritura y vistas con el seed) |
| `scripts/freeze-manifest.ps1 -Mode Verify` | exit 0 |
| Gate completo en un contenedor SQL Server 2022 limpio (réplica del job `DB Quality Gate CI/CD`) | `TOTAL_EXECUTED=432`, `PASSED=431`, `FAILED=0`, `SKIPPED=1` (permitido), `CRITICAL_MISSING=0`, `DB GATE PASS` |
