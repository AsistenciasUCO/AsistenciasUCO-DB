---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-02
---

# TEST_PLAN — HU112-HU128-HU143-HU157-consultas-transversales

Archivo: `test/test_consultas_transversales_hu112_hu157.sql` (registrado en `test_suite.sql`). Fixtures del seed (estudiante matriculado, docente vinculado en su facultad, administrador de la institución); el decano ajeno (otra facultad de la misma institución) y el usuario sin ámbito se crean dentro de una transacción que se revierte.

| ID | Escenario |
|---|---|
| T-112-01 | El plan del programa trae la suma real de créditos y el número de asignaturas; solo programas de la facultad; el decano ajeno no ve nada. |
| T-128-01 | El filtro por programa trae al docente vinculado y solo docentes con vínculo activo en ese programa, sin repetidos; el decano ajeno no ve nada. |
| T-143-01 | El decano titular encuentra la asignatura por código y solo ve su facultad; el decano de otra facultad no la ve; el administrador ve la institución y su filtro por facultad se aplica. |
| T-157-01 | El administrador encuentra al estudiante por documento. |
| T-157-02 | Historial con la matrícula para el administrador; el del decano titular se limita a su facultad; el decano ajeno no ve nada; un usuario sin perfil ADMINISTRADOR/DECANO recibe `SEC_001`. |
| T-SEC-03 | Rechazo `SEC_001` del usuario sin el perfil exigido: administrador en las consultas del decano, usuario sin perfil en docentes y asignaturas, decano en el buscador del administrador. |
| T-PAG-02 | Página 0, tamaño 0 y página nula se rechazan con `PAG_001`; ejecutor nulo y estudiante nulo con `VAL_001`. |
| T-INT-01 | `usp_validar_consulta_paginada_interno` directo: éxito (desplazamiento y contexto fijado), `VAL_001` y `PAG_001` con la correlación en el mensaje técnico, `SEC_001`; al final el `SESSION_CONTEXT` queda restaurado y la transacción del llamador sigue confirmable. |
| (contrato) | `test_contract_closure.sql`: los 5 SP públicos quedan como READ_QUERY_RESULTSET. |
