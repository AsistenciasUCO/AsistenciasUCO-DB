# PR (Draft) — CC-003G-01: proveedores publicos `usp_sincronizar_usuario` y `usp_registrar_o_actualizar_plan_estudio`

**Base sugerida:** `feat/utc-d06-post-freeze` (apilado; no toca archivos de D06 ni su manifiesto). **Head:** `feat/cc-003g-01-public-user-plan-providers`.
**No hacer merge ni desplegar** hasta aprobacion del owner DB y de seguridad.

## Que cambia
- Dos SP publicos que el backend ya invoca y que no existian en la DB publicada (eliminados en `daeac11`).
- `usp_registrar_o_actualizar_plan_estudio` agrega `@idUsuarioEjecutor` (obligatorio, fail-closed): COORDINADOR activo y titular del programa, revalidado en DB.
- `schema/security/rol_asistencias_runtime_cc003g01.sql`: `EXECUTE` solo a los dos SP; `DENY` del nucleo interno y del DML directo.
- Tests SQL (exito, rechazo, duplicados, rollback, idempotencia, carreras, login de minimo privilegio) integrados en `test_summary.ps1`.
- Fixture de datos para Java ITs que elimina 3 skips dependientes de datos (no es seed de despliegue).

## Evidencia
Ver `docs/work-items/CC-003G-01-public-user-plan-providers/VALIDATION.md`: gate SQL 219 ejecutadas / 218 PASS / 0 FAILED / 1 skip permitido en un despliegue limpio.

## Riesgos / decisiones para el owner
Ver `CONTRACT.md` (semantica elegida, limitaciones: barrido de unicidad sin indices, programa activo no validado, password ignorado en reintento).

## Coordinacion con backend
PR backend `jose-valencia/maint-003h-provider-contract-impl` (envia `idUsuarioEjecutor`). Orden de despliegue: DB primero, luego backend.
