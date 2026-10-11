---
status: EXECUTED_LOCAL_DEV
work_item: MAINT-003K-DB-DEV-CONSOLIDATION
---

# MAINT-003K-DB-DEV-CONSOLIDATION — Plan de pruebas

Todas las pruebas SQL viven en el gate `test_summary.ps1` (ids criticos obligatorios) o en `test/fixtures/dev/dev_pagination_validate.sql`.

| Requisito | Prueba (id) | Archivo | Resultado local |
|---|---|---|---|
| Seed 14 almacena UTC exacto con procedencia (no fechas locales ambiguas) | `UTC_D06_SEED_UTC` (reemplaza `UTC_D06_LEGACY_ROWS_NULL`, que afirmaba el seed ambiguo) | `test/test_utc_d06_procedencia_temporal.sql` | PASS |
| Los historicos NULL siguen intactos y se clasifican solo por SP | `UTC_D06_V1_CREATE_NULL`, `UTC_D06_CLASSIFICATION_REJECTS`, `UTC_D06_CLASSIFICATION_BY_ID` (sin cambios) | idem | PASS |
| `uv_estudiante_programa`: 1 `EstudiantePrograma` = 1 fila aunque el estudiante tenga 3 grupos; 5 columnas | `UV_ESTUDIANTE_PROGRAMA_NO_DUPLICATES` | `test/test_uv_estudiante_programa_no_duplicates.sql` | RED contra la vista anterior, PASS tras el despliegue |
| Contrato D06/CC-003G-01 completo (permisos, SP publicos, login minimo privilegio, carreras) | ids `UTC_D06_*`, `USER_SYNC_PUBLIC_*`, `PLAN_PUBLIC_*`, `CC003G01_*`, `GOLDEN_PATH_*` | sin cambios | PASS |
| Idempotencia del despliegue | 3 despliegues consecutivos: huella de modulos/columnas/indices/permisos/catalogos y conteos de filas identicos | `deploy_schema.ps1` | PASS |
| Fixtures: cardinalidad exacta 300/1000/5000, estados A/I/CVP/CI/F, contadores de grupo | `DEV_FIXTURE_SCENARIO_300/1000/5000` | `dev_pagination_validate.sql` | PASS |
| Orden estable `(nombreCompleto, id)`, concatenacion de paginas == lista completa, primera/ultima pagina, fuera de rango, filtro vacio, parejas de mismo nombre | idem | idem | PASS |
| Duplicados multigrupo (300 estudiantes en 3 grupos, 700 en 2) | `DEV_FIXTURE_MULTIGROUP_DUPLICATES` | idem | PASS |
| Sesiones fixture: UTC `DATETIME2(7)` con 100 ns (`.1234567`/`.7654321`) y marca `UTC_V2`; `uv_sesion_v2` las expone | dentro de `DEV_FIXTURE_SCENARIO_*` | idem | PASS |
| Asistencia fixture (solo matriculas A) y snapshot de horas en `DetalleAsistencia` | idem | idem | PASS |
| Integridad referencial de toda la DB | `DEV_FIXTURE_REFERENTIAL_INTEGRITY` (`DBCC CHECKCONSTRAINTS WITH ALL_CONSTRAINTS`) | idem | PASS |
| Idempotencia de fixtures | `deploy_dev_fixtures.ps1` ejecutado dos veces (limpieza -> carga -> validacion) | `deploy_dev_fixtures.ps1` | PASS |

Comando del gate: `.\test_summary.ps1 -ContainerName <contenedor> -Password <sa>` (precheck: DB `gestionasistenciadb` y Developer Edition).
Fixtures: `.\test\fixtures\dev\deploy_dev_fixtures.ps1 -ContainerName <contenedor> -Password <sa> [-Scenarios 300,1000,5000] [-CleanupOnly|-ValidateOnly]`.

## MAINT-003K-Sonar follow-up

| Requisito | Prueba (id) | Archivo | Resultado esperado |
|---|---|---|---|
| Validacion comun exitosa para docente activo y v1 | `SESSION_COMMON_VALIDATION_HAPPY_PATH` | `test/test_usp_validar_sesion_operacion_interno.sql` | `estadoResultado = 1`, sin transaccion abierta |
| Procedencia reservada rechazada | `SESSION_COMMON_VALIDATION_RESERVED_PROVENANCE` | idem | `estadoResultado = 0`, sin escritura |
| Ejecutor obligatorio | `SESSION_COMMON_VALIDATION_EXECUTOR_REQUIRED` | idem | `estadoResultado = 0` |
| Fechas obligatorias y orden temporal | `SESSION_COMMON_VALIDATION_START_REQUIRED`, `SESSION_COMMON_VALIDATION_DATE_ORDER` | idem | `estadoResultado = 0`, catalogo preservado |
| Contratos v1/v2 y flujo completo | ids existentes `SESSION_*`, `UTC_D06_*` | `test/test_usp_crear_actualizar_sesion.sql`, `test/test_utc_d06_procedencia_temporal.sql` | Sin regresiones de correlacion, RBAC, procedencia o cuatro columnas |

La suite aumenta en cinco identificadores obligatorios respecto de la evidencia anterior; por eso el resultado esperado
del gate pasa de `220/219/0/1` a `225/224/0/1` (ejecutadas/PASS/FAILED/SKIPPED), sujeto a la ejecucion real.
