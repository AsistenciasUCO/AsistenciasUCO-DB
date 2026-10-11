# PR (Draft) — MAINT-003K: consolidacion SQL (UTC-D06 + CC-003G-01), seed UTC y fixtures de desarrollo

**Base:** `develop`. **Head:** `feat/maint-003k-db-dev-consolidation`. **Draft — no hacer merge en esta tarea**; el merge será manual del usuario. Sin despliegue a produccion.

## Contenido (acumulado)

1. **UTC-D06-POST-FREEZE** (`6946a73`, `3842f70`): `Sesion.procedenciaTemporal`, trigger, bitacora, `uv_sesion_v2`, SP v2, clasificacion administrativa, generador UTC, roles de minimo privilegio.
2. **CC-003G-01** (`f64abb6`..`3f6afec`): `usp_sincronizar_usuario` y `usp_registrar_o_actualizar_plan_estudio` publicos (con `@idUsuarioEjecutor`), permisos `EXECUTE` por objeto, fixture Java IT.
3. **MAINT-003K (esta rama):**
   - `schema/seed/14_grupos_sesiones.sql`: las sesiones sembradas son instantes UTC exactos `DATETIME2(7)` con `procedenciaTemporal='UTC_V2'` (antes: relojes locales sin procedencia); un redeploy ya no crea fechas ambiguas ni reescribe historicos.
   - `schema/views/uv_estudiante_programa.sql`: una fila por `EstudiantePrograma` (antes se multiplicaba por grupo).
   - Tests: `UTC_D06_SEED_UTC` (reemplaza `UTC_D06_LEGACY_ROWS_NULL`) y `UV_ESTUDIANTE_PROGRAMA_NO_DUPLICATES` (RED -> GREEN).
   - Regresión de prioridad: `SESSION_ERROR_PRIORITY_CREATE_GROUP_BEFORE_DATES` y `SESSION_ERROR_PRIORITY_UPDATE_SESSION_BEFORE_DATES`; grupo/sesión conserva prioridad sobre fechas inválidas y no hay escrituras parciales.
   - `test/fixtures/dev`: fixtures sinteticos reproducibles 300/1000/5000 estudiantes (limpieza, carga, validacion, guardas de entorno). **No** forman parte de ningun despliegue.
   - Documentacion: `docs/work-items/MAINT-003K-DB-DEV-CONSOLIDATION/{PLAN,TEST_PLAN,VALIDATION}.md`.

## Despliegue (desarrollo local)

```powershell
.\deploy_schema.ps1 -ContainerName sql_server_asistencias -Password <sa>      # idempotente; ejecutar 2 veces no cambia nada
.\test_summary.ps1  -ContainerName sql_server_asistencias -Password <sa>      # gate del nuevo HEAD; no presupone conteos
.\test\fixtures\dev\deploy_dev_fixtures.ps1 -ContainerName sql_server_asistencias -Password <sa>   # opcional: datos de paginacion
```

Para una DB existente anterior a D06 el seed **no** reescribe sesiones historicas (siguen INDETERMINADAS); clasificarlas con `usp_clasificar_procedencia_sesion`
o, solo en desarrollo, reconstruir la DB desde Git. Orden de despliegue: DB primero, luego backend (`app.sesiones.v2.enabled=true` exige el contrato D06).

## Evidencia

`VALIDATION.md` de este work item: respaldo verificado, datos principales preservados, procedimientos corregidos aplicados
selectivamente y gate SQL final sobre `sql_server_asistencias`: 227 ejecutadas / 226 PASS / 0 FAILED / 1 skip permitido.
Backend certificado contra esta DB: Surefire 1502, Failsafe 196 (0 fallos/0 skips), JaCoCo 91,31 % lineas / 78,83 % ramas, E2E con JWT reales 28/28 en JVM UTC, Bogota y Berlin.

## Checks CI

En `af37ccc8...`, SonarCloud y DB Quality Gate fueron aprobados: 0,0 % de duplicación, 0 issues nuevos y
225 ejecutadas / 224 PASS / 0 FAILED / 1 skip permitido. En el nuevo HEAD, el gate local sobre el contenedor principal
pasó con 227 ejecutadas / 226 PASS / 0 FAILED / 1 skip permitido. El run remoto 23 (`38125366104`) sobre
`d9741b12b68f3737726e3d1ecd7f05c211a8b543` también terminó **success**: despliegue, gate SQL, SonarCloud y
post-checkout exitosos.

El contenedor local temporal `maint003k_cert_20261011` fue retirado sin volumen y no se creó ningún contenedor SQL nuevo.

## Riesgos / decisiones para el owner

- Fixture Java `prepare_java_integration_fixture.ps1` elige grupo con `ORDER BY g.id` (puede caer en un grupo fixture): inocuo, la validacion de fixtures cuenta solo filas `DE0000`.
- Cambio de `uv_estudiante_programa`: misma semantica de presencia y mismas columnas; revisar si el owner prefiere unir `uv_estudiante_identidad` (incluiria estudiantes sin matricula).
