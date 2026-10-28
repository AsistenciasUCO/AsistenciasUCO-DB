---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-27
---

# TEST_PLAN — HU094-HU095-directorio-docentes-coordinador

Matriz completa de las 3 capas: el `TEST_PLAN.md` del work item homónimo del backend. Casos de DB sobre SQL Server real, dentro de una transacción con ROLLBACK:

| ID | Escenario | Esperado |
|---|---|---|
| H-01 | Historial de D1 en P1 (vigente ×2, finalizado y próximo); un grupo en P2 y otro titular en P1 | 4 filas, por inicio del período descendente y asignatura; excluye P2 y el otro titular |
| H-02 | Estado del período, estadística y resumen | VIGENTE, FINALIZADO y PROXIMO; 2 activos y capacidad 30 en G1; resumen 4/3/2/3 en todas las filas |
| H-03 | Filtro por período, página 2 de tamaño 1; página 0 y tamaño 500 | G6, `totalRegistros` 2 y resumen 4; normaliza a 4 filas |
| H-04 | Docente vinculado sin grupos | 0 filas sin error |
| H-05 | Docente sin vínculo con P1, id inexistente, coordinador de P2 | `GEN_001` ×2; C2 solo ve el grupo de P2 |
| H-06 | Decano, docente nulo, ejecutor nulo | `KPI_001`, `VAL_001` y `VAL_001` |
| R-01 | Consolidado de P1 (CAT activo e inactivo, PLA activo, MTI con cuenta inactiva; un PLA en P2) | CAT 1/1, PLA 1/0, MTI 0/1, OCA 0/0; total 4 |
| R-02 | Coordinador de P2 | total 1 (PLA) |
| R-03 | Decano y ejecutor nulo | `KPI_001` y `VAL_001` |

**RED:** los dos archivos de prueba fallan sin los SP (objeto inexistente).
