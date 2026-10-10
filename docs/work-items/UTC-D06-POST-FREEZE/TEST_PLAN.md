# TEST_PLAN — UTC-D06-POST-FREEZE: remediation and certification

| ID | Requirement | Scenario | Observable | Expected | Level |
|---|---|---|---|---|---|
| D06-RBAC-01 | Runtime has only required execution rights. | Authenticate using temporary non-admin SQL login. | Every existing runtime procedure reports `HAS_PERMS_BY_NAME(..., EXECUTE)=1`. | Explicit object grants only. | SQL integration |
| D06-RBAC-02 | Runtime cannot mutate session tables directly. | Same login issues direct `UPDATE` including a reasserted provenance value. | SQL denial and unchanged row. | Denied; no partial write. | SQL integration |
| D06-RBAC-03 | Runtime cannot classify UTC owner values. | Same login calls classifier/internal procedures. | SQL denial. | Denied. | SQL integration |
| D06-RBAC-04 | No broad execute privilege. | Inspect role permissions. | `sys.database_permissions`. | No `EXECUTE` grant on `SCHEMA::dbo`; object grants only. | SQL integration |
| D06-FIX-01 | Java parity fixture is reproducible. | Isolated fixture discovers an existing eligible group, creates a named session through the public SP and two attendance details through the public batch SP. | `uv_asistencia`/`uv_detalle_asistencia` have the required shapes. | A session-specific row, null-session read case, and multi-row case exist. | SQL/Java integration |
| D06-V1-01 | Frozen v1 stays compatible. | Full DB gate. | v1 signature/view assertions. | Pass unchanged. | SQL integration |
| REV-01 | A new review is pending. | Radicate then reject as non-owner. | `dbo.Estado` and persisted request. | `P`, no unauthorized transition. | SQL integration |

## Integration requirement

- REAL_PROVIDER_REQUIRED: YES.
- ENVIRONMENT: `utc_d06_sqltest`, SQL Server 2022 Developer, never the primary database.
- MOCK_SUFFICIENT: NO.
- Cleanup: runtime login/user and every fixture row are removed by the test; data changes run only in the isolated database.

## Existing RED evidence

The Java Failsafe report at backend commit `30fcd5e7` shows six attendance-query fixture failures and two review-state fixture failures. They are reproducibility defects, not justification for weakened assertions. The missing provider failures are separately blocked by `CC-003G-01`.
