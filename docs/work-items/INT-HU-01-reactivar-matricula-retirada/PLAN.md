---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-28
---

# PLAN — INT-HU-01: reactivar la matrícula retirada al aceptar una solicitud de ingreso

## Hallazgo

Alejo lo registró en el work item `INTEGRACION-DEVELOP-20261027` del backend, verificado contra SQL Server real.

1. Tras el retiro del docente (HU051), la matrícula del estudiante queda en `I`.
2. HU053 le permite volver a solicitar el ingreso, porque solo bloquea a quien tiene matrícula `A`.
3. Al aceptar la solicitud (HU055), `usp_registrar_estudiante_en_grupo_interno` → `usp_validar_registro_estudiante_en_grupo_interno` rechaza cualquier fila previa del estudiante en el grupo. El resultado es **409 `ERR_MATRICULA_DUPLICADA`**.
4. La solicitud queda pendiente para siempre, salvo que el docente la rechace.

## Decisión de John (2026-10-28)

**Opción a:** al aceptar, se **reactiva** la matrícula retirada (`I` → `A`) en lugar de crear otra.

## Cambio (mínimo, sin tablas nuevas ni objetos congelados)

`usp_resolver_solicitud_ingreso_grupo`, rama ACEPTAR con cupo:

- Si existe una matrícula `I` del estudiante en el grupo:
  - se actualiza a `A`, bajo `UPDLOCK, HOLDLOCK`;
  - se enlaza esa matrícula en `SolicitudIngresoGrupo.estudianteGrupo`;
  - la solicitud queda `A` (`SIG_011`).
- Si no existe, se sigue el camino anterior (`usp_registrar_estudiante_en_grupo_interno`).
- Se mantienen las reglas de antes:
  - **cupo:** se verifica primero bajo `UPDLOCK`; sin cupo la solicitud pasa a lista de espera;
  - **matrícula `A` duplicada:** sigue bloqueada con `SIG_004`;
  - **regla HU008:** solo una asignatura ESP crea `EstudiantePrograma`, y solo si no existe ya.
- **Asistencias:** las históricas de la matrícula se conservan.
- **Backend y frontend:** no cambian. La respuesta sigue siendo `SIG_011` / estado `ACEPTADA`.

### Límite conocido

- **Validaciones que se omiten en la reactivación:** como la matrícula ya existía en el mismo grupo, no se vuelven a ejecutar las validaciones del interno (cruce de horario). Si después del retiro el estudiante se matriculó en otro grupo con horario cruzado, la reactivación no lo detecta. Queda para MV-008.
- **Estados no reactivados:** las matrículas en otros estados (finalizada, cancelada por inasistencia o por voluntad propia) no se reactivan y conservan el comportamiento anterior.

## Pruebas

`test/test_int_hu01_reactivar_matricula_retirada.sql`:

| ID | Caso | Resultado esperado |
|---|---|---|
| RM-01 | Retirado → solicita → acepta | `SIG_011`; la misma matrícula pasa a `A` y queda enlazada; una sola fila |
| RM-02 | El cupo se respeta | Otra aceptación queda en lista de espera (`E`) |
| RM-03 | Matrícula activa | Sigue bloqueando una nueva solicitud (`SIG_004`) |

Regresión: `S-01..S-12` (HU053-HU055), `R-01..R-09` (HU051) y `RI-01..RI-03` (HU008).

## Rollback

Revertir el commit: se elimina el bloque `ELSE IF EXISTS (... 'I')` del SP. No hay cambios de datos.

## Validación

Réplica del job `DB Quality Gate CI/CD` sobre SQL Server 2022 limpio (2026-10-28): `TEST_PASS:INT_HU01_RM01..RM03`, regresión S-01..S-12, R-*, RI-01..03; `TOTAL_EXECUTED=361`, `FAILED=0`, `DB GATE PASS`; `freeze-manifest -Mode Verify` = 0.
Re-ejecutada tras integrar `origin/develop` (HU006, #58): `TOTAL_EXECUTED=364`, `FAILED=0`, `CRITICAL_MISSING=0`, `DB GATE PASS` (incluye `TEST_PASS:HU006_*` e `INT_HU01_RM01..RM03`).

> **Retirado en CULM-001 A (2026-11-07):** las solicitudes de ingreso (HU053-HU055) se descartaron; la reactivacion de la matricula retirada vive en `usp_internal_reactivar_matricula_retirada` (DEC-009). Ver `docs/arquitectura/DOCUMENTACION_PROCEDIMIENTOS_PUBLICOS.md`, addendum CULM-001 A.
