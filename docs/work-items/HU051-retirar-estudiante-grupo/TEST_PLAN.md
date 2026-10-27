---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-27
---

# TEST_PLAN — HU051-retirar-estudiante-grupo

Prueba: `test/test_usp_retirar_estudiante_grupo.sql` (registrada en `test_suite.sql`). Fixture dentro de una transacción con ROLLBACK; R-09 corre fuera porque el SP de lectura hace `THROW`.

| ID | Escenario | Esperado |
|---|---|---|
| R-01 | Titular retira a A (con una asistencia registrada) | `RET_005`; matrícula `I`; B sigue `A`; `cuposDisponibles` +1; asistencia intacta; `AuditoriaEvento` con motivo sin espacios extremos, grupo y estudiante |
| R-02 | Retirar de nuevo a A | `RET_002` |
| R-03 | Otro docente, coordinador del programa o el propio estudiante | `RET_001` ×3; A sigue `A` |
| R-04 | Motivo vacío, espacios, nulo, 501 caracteres | `RET_004` ×4 |
| R-05 | Período terminado ayer (hora local) / último día | `RET_003` / el último día sí permite |
| R-06 | Grupo inexistente | `RET_001` |
| R-07 | Ejecutor nulo | estado 0 sin cambios |
| R-08 | Destinatarios como titular / como otro docente | 3 filas (estudiante, docente, coordinador del programa) / 0 filas |
| R-09 | Destinatarios con ejecutor nulo | `THROW` |

## RED_SNAPSHOT

| Campo | Valor |
|---|---|
| Base commit | `6fd5413` |
| Commit RED | `64c63fe` (prueba + registro en la suite) |
| Fallo esperado | SP inexistentes |
| Comando | réplica del job `DB Quality Gate CI/CD` |
