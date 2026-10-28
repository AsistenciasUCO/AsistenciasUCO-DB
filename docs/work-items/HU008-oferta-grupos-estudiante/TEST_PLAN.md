---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-27
---

# TEST_PLAN — HU008-oferta-grupos-estudiante

La matriz completa de las 3 capas está en el `TEST_PLAN.md` del work item homónimo del backend. Estos son los casos de base de datos, sobre SQL Server real y dentro de una transacción con ROLLBACK:

| ID | Escenario | Esperado |
|---|---|---|
| O-01 | E1 en P1. P1 tiene ESP vigentes (G1, G5), ESP próxima (G2), ESP finalizada (G3) y BAS (G7). P2 tiene INS (G4) y ESP (G6). | 5 filas (G1, G5, G7, G2, G4), en orden por asignatura, inicio del período y código. G4 con `codigoComponente` INS y G7 con BAS. G3 y G6 quedan fuera. |
| O-02 | Cupos, horario y relación del estudiante con cada grupo | G1: cupos 1 (no cuenta la matrícula inactiva), horario ordenado de lunes a martes y docente. G5: matriculado y 0 cupos. G2: PROXIMO con solicitud P. |
| O-03 | Búsqueda, paginación y comodines | La búsqueda "calculo" devuelve G2. La página 2 de tamaño 1 devuelve G5 con total 5. "100%_" devuelve 0 filas. |
| O-05 | `OFERTA.INCLUIR_TRANSVERSALES = 0` | Solo las 3 ESP de su programa |
| O-04 | Ejecutor docente; ejecutor nulo | 0 filas; `VAL_001` |
| RI-01 | Aceptar una solicitud (HU053) en un grupo ESP | Matrícula A y fila `EstudiantePrograma` |
| RI-02 / RI-03 | Aceptar en un grupo INS o BAS | Matrícula A **sin** fila `EstudiantePrograma` |
| S-01..S-12 | Suite de HU053-055 | Sigue en verde |

**RED:** sin el SP, O-* falla por objeto inexistente. Sin el `JOIN`, RI-02 y RI-03 fallan porque se crea la fila del programa.
