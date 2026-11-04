---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-04
---

# TEST_PLAN — HU061-HU147-HU153-HU172-consolidado-auditoria-catalogos

Archivo: `test/test_consolidado_auditoria_catalogos.sql` (registrado en `test_suite.sql`), dentro de una transacción revertida.

| ID | Escenario |
|---|---|
| T-061-01 | El coordinador solo ve su programa y los totales coinciden con el resumen por estudiante; el decano solo ve su facultad; el filtro por programa del administrador se aplica; un estudiante recibe `SEC_001`. |
| T-172-01 | Con dos eventos insertados: por defecto solo sale el de asistencia, con el nombre del usuario; con "todas", resultado y usuario sale el otro; un decano recibe `SEC_001`; un rango incompleto recibe `GEN_002`. |
| T-147-01 | Se listan BAS, INS y ESP con su código; un estudiante recibe `SEC_001`. |
| T-153-01 | El administrador crea; el código duplicado da `GEN_003`; un código con números da `GEN_002`; la edición cambia solo el nombre y conserva el código; un nombre de otro tipo da `GEN_003`; un id inexistente da `GEN_001`; un coordinador recibe `SEC_001`. |
| T-P5-01 | Crear con un componente o un área inexistentes da `GEN_001` y un semestre que no está en el plan da `PLA_004`, sin crear nada; crear con el nombre exacto del componente asigna ESP; actualizar aplica BAS; actualizar con un componente inexistente da `GEN_001` y conserva el actual. |
| T-ASI-01 | Créditos nulos o en cero dan `ASI_001` sin crear; un plan inexistente da `PLA_002`; un semestre del catálogo que no está en el plan da `PLA_004` sin ampliar la malla (si el seed tiene uno); el plan de otro programa da `SEC_002` (si el seed tiene otro programa; además lo cubre RA-05); actualizar con créditos negativos da `ASI_001` y conserva los créditos. |
| T-PAG-03 | La página 0 del consolidado da `PAG_001`. |
| (cierre) | `SESSION_CONTEXT` restaurado y la transacción del llamador sigue confirmable. |
| `test_subject_catalog.sql` | Crear asignatura con un área y un componente reales (P5) y un semestre del plan. |
| `test_rec2_rbac_asignatura.sql` RA-05 | Crear en el plan de otro programa da `SEC_002` sin insertar; el coordinador titular crea. |
