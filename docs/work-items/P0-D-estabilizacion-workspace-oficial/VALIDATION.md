# P0-D — Validación DB

Fecha de revisión: 2026-10-18.

## Evidencia local

- git diff --check: PASS.
- El addendum de cierre HU116 incorpora cambios limitados en
  `schema/stored-procedures/usp_crear_facultad.sql`, `test/test_usp_crear_facultad.sql`,
  `test_suite.sql` y `test_summary.ps1`; no se modifican migraciones ni se
  introduce la fase de Blob Storage.
- Fallbacks de password en .github/workflows/ci.yml y
  run_local_env.ps1: retirados.
- Summary estático 225/225: retirado; el workflow consume los contadores
  reportados por test_summary.ps1.
- Cambios aplicados sobre `codex/reconcile-db-2026-10-18`, derivada de
  `origin/develop` en `e1ca79d80d28f53dd06f3cfa13fa1ec6b4835295`.

## Evidencia SQL local

- `scripts/freeze-manifest.ps1 -Mode Verify`: PASS.
- `deploy_schema.ps1` sobre SQL Server Developer aislado: PASS.
- `test_summary.ps1`: `TOTAL_EXPECTED=228`, `TOTAL_EXECUTED=231`,
  `PASSED=230`, `FAILED=0`, `SKIPPED=1`, `ALLOWED_SKIPPED=1`,
  `CRITICAL_MISSING=0`, `SQLCMD_EXIT_CODE=0`, `SQL_ERROR_COUNT=0` y
  `UNAUTHORIZED_SKIPS=0`.
- `DB GATE PASS`, `@@TRANCOUNT=0` y `NO_HARDCODED_DB_PASSWORD`: PASS.
- HU116: ejecutor nulo, RBAC no administrador, decano obligatorio,
  administrador válido y resultset canónico de cuatro columnas: PASS.

## Validaciones remotas pendientes

- Workflow remoto DB y SonarCloud: pendientes de push y ejecución del PR; el
  token Sonar permanece exclusivamente en GitHub Secrets.

## Dictamen

DB_CI=LOCAL_DB_GATE_PASS_REMOTE_CHECK_PENDING.

La evidencia local no sustituye los checks remotos; el merge queda bloqueado
hasta confirmar el análisis Sonar y su Quality Gate en GitHub.

## SECURITY_FINDING

CLAUDE.md contiene ejemplos de credenciales con forma de password en
