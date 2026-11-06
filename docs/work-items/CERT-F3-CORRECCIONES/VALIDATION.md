---
status: active
type: work-item
scope: db
owner: fullstack-team
last-reviewed: 2026-11-06
---

# VALIDATION — CERT-F3-CORRECCIONES

| Comando | Resultado |
|---|---|
| Seed 14 en la BD local, ejecutado dos veces | La 1.ª corrida inserta 2 filas de `EstudiantePrograma`; la 2.ª no inserta ninguna (idempotente) |
| Gate completo en un contenedor SQL Server 2022 limpio | `TOTAL_EXECUTED=442`, `PASSED=441`, `FAILED=0`, `CRITICAL_MISSING=0`, `DB GATE PASS` |
| Re-prueba en pantalla | HU006: el perfil muestra "Estudiante en Ingeniería de Sistemas". HU008: la oferta muestra el grupo con 28 de 30 cupos |
| Gate completo, corrida final (seed 14 y los 2 SP del decano con `MAX(numeroSemestre)`), en un contenedor limpio con el fixture LB-004D como el CI | `TOTAL_EXECUTED=442`, `PASSED=441`, `FAILED=0`, `SKIPPED=1` (permitido), `CRITICAL_MISSING=0`, `DB GATE PASS`. T-119-01 y T-112-01 pasan con la nueva comprobación de `totalSemestres` |
| Re-prueba en pantalla de los semestres | El decano ve "Plan 2024 · 8 semestres" en la estructura y 8 en "Programas y Créditos", igual que el coordinador |
| BD | Gate completo sobre la rama integrada con `origin/develop` (HU176B), en un contenedor limpio con el fixture LB-004D | `TOTAL_EXECUTED=446`, `PASSED=445`, `FAILED=0`, `SKIPPED=1` (permitido), `CRITICAL_MISSING=0`, `DB GATE PASS` |
