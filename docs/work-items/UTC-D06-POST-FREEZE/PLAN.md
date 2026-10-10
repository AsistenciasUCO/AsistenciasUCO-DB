---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-10
---

# PLAN — UTC-D06-POST-FREEZE: remediation and certification

## Identity and objective

- Base: `feat/utc-d06-post-freeze` at `6946a73387f879d4f5168ece97435d33023bc529`.
- Objective: certify the additive UTC-D06 objects on an isolated SQL Server 2022 database, make the runtime role least-privilege, and provide reproducible integration fixtures without changing v1 or the primary database.
- Authorities: DB owner source, `DB_UTC_D06_POST_FREEZE_MANIFEST.sha256`, backend MAINT-003G audit (`3b633e7866449f11e5828a73c0e426db91fbba94`), and the frozen v1 contracts.

## AS-IS and evidence

| Fact | Evidence | Limit |
|---|---|---|
| D06 is additive and v1 wrappers remain present. | `schema/tables/Sesion.sql`, v1/v2 session wrappers and manifest. | Does not authorize historical conversion. |
| Runtime role has `GRANT EXECUTE ON SCHEMA::dbo`. | `schema/security/rol_asistencias_runtime.sql:28`. | Excessively broad; must be replaced by object grants. |
| Isolated SQL gate passes. | `test_summary.ps1` on `utc_d06_sqltest`, 2026-10-10: 179 executed, 178 passed, 1 allowed skip, exit 0. | It used an administrative login, so it does not certify runtime credentials. |
| Java expects two public providers absent in this DB branch. | Java `SqlStoredProcedureContractIT`; DB metadata and historical DB report. | See `CC-003G-01`; do not recreate either provider. |
| Review requests fall back to `A`. | `usp_radicar_solicitud_revision_asistencia` looks for `P`/`PEND`; `schema/seed/06_estado.sql` only had `A` and `R`. | Seed `P` idempotently; no provider signature changes. |

## Class and scope

- Change class: `INFRASTRUCTURE`.
- PRIMARY_VARIABLE: `RUNTIME_SQL_LEAST_PRIVILEGE`.
- ALLOWED_PATHS: `schema/security/rol_asistencias_runtime.sql`, `schema/seed/06_estado.sql`, `schema/stored-procedures/usp_resolver_solicitud_revision_asistencia.sql`, `test/test_utc_d06_*`, `test/test_attendance_review.sql`, `test/fixtures/maint_003g_attendance_fixture.sql`, `test/prepare_java_integration_fixture.ps1`, `test/verify_runtime_role_login.ps1`, `test_summary.ps1`, `docs/contracts/DB_UTC_D06_POST_FREEZE_MANIFEST.sha256`, `docs/work-items/UTC-D06-POST-FREEZE/**`.
- FORBIDDEN_PATHS: frozen v1 views/wrappers, table data migrations, historical-date conversion, primary DB configuration, login provisioning, and any public SP absent from the approved current DB contract.
- PROVIDER: isolated SQL Server 2022 Developer container `utc_d06_sqltest` only.
- SECURITY_IMPACT: removes schema-wide execute; proves required v1/v2 session calls with a non-administrative SQL login; direct DML remains denied.
- TEST_LEVEL_REQUIRED: SQL Server real gate plus login-based least-privilege test.
- ROLLBACK: reapply the prior role script only in the isolated test database; production rollback remains owner-controlled and must retain D06 columns/objects.

## Contract conflict

`CC-003G-01` — **CONTRACT_CONFLICT / blocked scope**: backend requires `dbo.usp_sincronizar_usuario` and `dbo.usp_registrar_o_actualizar_plan_estudio`; this owner branch does not expose them. Historical DB evidence records their removal because their former semantics were incompatible. Owner DB and backend/contracts must publish one approved provider contract before either source is changed. This blocks only those Java provider tests and their command paths.

## Definition of Ready

**READY (scoped)** for grants, runtime-login certification, isolated fixtures and documentation: sources, environment, rollback and tests are identified. **NOT_READY** for reintroducing the two missing public providers (`CC-003G-01`).
