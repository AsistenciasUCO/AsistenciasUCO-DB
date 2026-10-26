---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-26
---

# TEST_PLAN — HU104-HU105-HU109-HU119-HU145-lecturas-decano

Archivo: `test/test_consultas_decano_facultad.sql` (registrado en `test_suite.sql`).

| ID | Escenario |
|---|---|
| T-104-01 | Directorio solo de la facultad del decano, sin repetidos; decano ajeno y usuario sin ámbito no ven nada. |
| T-105-01 | Búsqueda por documento y ficha con la matrícula; el decano ajeno no la ve. |
| T-119-01 | Estructura con programa y plan; el decano ajeno ve solo su facultad sin programas. |
| T-145-01 | Cronograma con rango de un día y programa; el decano ajeno no ve sesiones. |
| T-PAG-01 | Página 0 y tamaño 0 se rechazan con `PAG_001`. |
