---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-27
---

# TEST_PLAN — HU053-HU054-HU055-solicitudes-ingreso-grupo

Prueba: `test/test_solicitud_ingreso_grupo.sql` (registrada en `test_suite.sql`). Crea 4 estudiantes de prueba dentro de una transacción con ROLLBACK, deja el período vigente y un solo cupo libre; S-12 corre fuera porque las consultas hacen `THROW`.

| ID | Escenario | Esperado |
|---|---|---|
| S-01 | A solicita | `SIG_006`, P |
| S-02 | Duplicada, ya matriculado, no estudiante, grupo inexistente, período terminado | `SIG_005`, `SIG_004`, `SIG_001`, `SIG_002`, `SIG_003` |
| S-03 | B, C y D solicitan | 3 éxitos |
| S-04 | Otro docente, acción inválida, rechazo sin motivo | `SIG_007`, `SIG_009`, `SIG_010` |
| S-05 | Aceptar A con el único cupo | `SIG_011`, A, matrícula activa enlazada, cupo 0 |
| S-06 | Aceptar B y D sin cupo; reintentar B | `SIG_012` (E); `SIG_013` |
| S-07 | Rechazar C con motivo; resolver de nuevo | `SIG_014` (R, motivo recortado); `SIG_008` |
| S-08 | Se libera cupo (retiro HU051) y el docente acepta a D (no a B, que llegó antes) | D matriculado; B sigue E |
| S-09 | Bandeja (orden, `posicionEspera`, cupo, filtro, ámbito) y mis solicitudes | según contrato |
| S-10 | Retiro ajeno, propio, dos veces; nueva solicitud tras retirar | `SIG_007`, `SIG_015` (X), `SIG_008`, `SIG_006` |
| S-11 | Destinatarios: docente y propio estudiante; terceros | 2+2 filas; 0 filas |
| S-12 | Consultas con ejecutor nulo | `THROW` ×3 |

Limitación: sin prueba automática de dos sesiones concurrentes (ver TEST_PLAN del backend).

## RED_SNAPSHOT

| Campo | Valor |
|---|---|
| Base commit | `a01a3de` |
| Commit RED | `c9c6b9a` (prueba + registro en la suite) |
| Fallo esperado | tabla y SP inexistentes |
| Comando | réplica del job `DB Quality Gate CI/CD` |
