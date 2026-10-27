---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-26
---

# TEST_PLAN — HU010-HU011-consulta-reclamos-estudiante

Prueba: `test/test_consultas_reclamos_estudiante.sql` (registrada en `test_suite.sql`). Fixture dentro de una transacción con ROLLBACK.

| ID | Escenario | Esperado |
|---|---|---|
| E-01 | Estudiante A con 2 solicitudes (una con soporte ATTACHED) | 2 filas propias, soporte presente, `totalRegistros = 2` |
| E-02 | Orden y paginación (tamaño 1) | `fechaSolicitud DESC, nombreSolicitud, id`; página 2 devuelve la segunda |
| E-03 | Filtro `@codigoEstado = 'A'` | solo la aprobada |
| E-04 | Estudiante B | solo su solicitud (aislamiento) |
| E-05 | Docente titular y coordinador como ejecutores | 0 filas |
| E-06 | Página 0 / tamaño 0 | acotado a 1/10 (sin `PAG_001`, como R2) |
| E-07 | Parámetro `ARCHIVO.ESTADO_ADJUNTO` cambiado | `idArchivoSoporte` NULL |
| E-08a | `sys.dm_exec_describe_first_result_set_for_object` | mismas columnas y tipos que `usp_consultar_solicitudes_revision_docente` |
| E-08b | Ejecutor NULL (fuera de la transacción) | THROW `VAL_001` |

## RED_SNAPSHOT

| Campo | Valor |
|---|---|
| Base commit | `b8d07bf` |
| Commit RED | `e40edcf` (solo la prueba + registro en la suite) |
| Fallo esperado | SP `dbo.usp_consultar_solicitudes_revision_estudiante` inexistente |
| Comando | réplica del job `DB Quality Gate CI/CD` (`deploy_schema.ps1` + `prepare_lb004d_fixture.ps1` + `test_summary.ps1`) |
