---
status: active
type: normative
scope: database
owner: database-team
system: gestionasistenciadb
last-reviewed: 2026-10-12
---

# gestionasistenciadb - Entrada y Gobernanza para Agentes

Esta es la guía normativa obligatoria para cualquier agente de Inteligencia Artificial que opere en este repositorio.
Cualquier modificación o propuesta debe seguir estrictamente este flujo:
**AGENTS.md → Documento Contractual → Skill Correspondiente → Procedimiento/Esquema → Suite de Pruebas → Validación de Integridad**.

---

## 🏛️ 1. Principios Obligatorios de Base de Datos

1. **Invariabilidad del Baseline Contract:**
   - La fuente de verdad suprema es [`docs/contracts/DB_BASELINE_CONTRACT.md`](docs/contracts/DB_BASELINE_CONTRACT.md).
   - Ningún cambio puede modificar ni relajar objetos ya congelados sin un addendum o work-item contractual formal (`docs/work-items/`).
2. **Arquitectura Canónica de Procedimientos Almacenados:**
   - **Procedimientos Públicos (`usp_*`):** Son la interfaz consumida por la aplicación/API. Realizan validaciones perimetrales y control transaccional maestro. No llevan sufijo `_interno`.
   - **Procedimientos Internos (`usp_*_interno`):** Ejecutan la mutación o consulta atómica en la tabla. Solo deben ser invocados por procedimientos públicos o coordinadores.
   - Todo procedimiento debe respetar el estándar documentado en [`docs/arquitectura/transaccion-procedimiento.md`](docs/arquitectura/transaccion-procedimiento.md).
3. **Manejo Estricto de Transacciones:**
   - `SET XACT_ABORT ON;` obligatorio en procedimientos mutacionales.
   - Bloques `BEGIN TRY ... BEGIN TRANSACTION ... COMMIT ... END TRY BEGIN CATCH IF XACT_STATE() <> 0 ROLLBACK ... THROW / OUTPUT ... END CATCH`.
4. **Catálogos y Mensajes Estandarizados:**
   - Prohibido codificar mensajes o códigos de error "quemados" (*hardcoded*). Se debe consultar y reutilizar [`docs/catalogos/catalogo-mensajes.md`](docs/catalogos/catalogo-mensajes.md).
5. **No Breaking Changes hacia Backend y Frontend:**
   - No renombrar columnas, tablas o firmas de procedimientos existentes sin seguir el patrón *Expand & Contract*.
   - Toda salida de SP consumida por la API debe mantener la firma estipulada en [`docs/arquitectura/especificacion_sp_endpoints.md`](docs/arquitectura/especificacion_sp_endpoints.md).
6. **Seguridad y Least Privilege:**
   - El rol de ejecución de la aplicación (`rol_asistencias_runtime`) solo tiene permisos de `EXECUTE` en procedimientos públicos y `SELECT` en vistas públicas; nunca permisos directos sobre tablas base.
7. **Pruebas Automatizadas Obligatorias:**
   - Todo cambio o nuevo procedimiento debe contar con su correspondiente prueba unitaria/integración en [`test_suite.sql`](test_suite.sql) o dentro de `test/`.
   - Las pruebas se verifican mediante el script oficial [`test_summary.ps1`](test_summary.ps1).

---

## ⚖️ 2. Jerarquía de Precedencia (Orden de Autoridad)

En caso de discrepancia entre documentos, rige el siguiente orden descendente estricto:

1. 🥇 **Nivel 1 (Contratos de Congelamiento):**
   * [`docs/contracts/DB_BASELINE_CONTRACT.md`](docs/contracts/DB_BASELINE_CONTRACT.md) y sus manifiestos hash `.sha256`.
2. 🥈 **Nivel 2 (Work-Items Activos y Addendums):**
   * `docs/work-items/*/CONTRACT.md` y `docs/contracts/DB_DEVELOP_FREEZE_ADDENDUM.md`.
3. 🥉 **Nivel 3 (Arquitectura Canónica y Especificaciones):**
   * [`docs/arquitectura/transaccion-procedimiento.md`](docs/arquitectura/transaccion-procedimiento.md)
   * [`docs/arquitectura/backend_specification.md`](docs/arquitectura/backend_specification.md)
   * [`docs/arquitectura/especificacion_sp_endpoints.md`](docs/arquitectura/especificacion_sp_endpoints.md)
4. 🏅 **Nivel 4 (Catálogos Maestros):**
   * [`docs/catalogos/catalogo-mensajes.md`](docs/catalogos/catalogo-mensajes.md) y [`docs/catalogos/catalogo-parametros.md`](docs/catalogos/catalogo-parametros.md).
5. 🎖️ **Nivel 5 (Skills de Validación y Soporte):**
   * Habilidades operativas ubicadas en `.agents/skills/`.

---

## 🗺️ 3. Matriz de Enrutamiento para Agentes

Antes de responder o proponer código, el agente **DEBE cargar y consultar** los documentos y skills correspondientes a la tarea:

| Tipo de Solicitud | Documentos Mandatorios a Consultar | Skill Requerida (`.agents/skills/`) |
| :--- | :--- | :--- |
| **Crear o Modificar Procedimiento Interno** | • `docs/arquitectura/DOCUMENTACION_PROCEDIMIENTOS_INTERNOS.md`<br>• `docs/arquitectura/transaccion-procedimiento.md`<br>• `docs/catalogos/catalogo-mensajes.md` | `procedimientos-internos-condiciones` |
| **Crear o Modificar Procedimiento Público / Endpoint** | • `docs/arquitectura/DOCUMENTACION_PROCEDIMIENTOS_PUBLICOS.md`<br>• `docs/arquitectura/especificacion_sp_endpoints.md`<br>• `docs/contracts/DB_BASELINE_CONTRACT.md` | `procedimientos-externos-condiciones` |
| **Consultas Complejas o Creación de Vistas** | • `docs/arquitectura/transaccion-procedimiento.md`<br>• `docs/modelos/ModeloEntidadRelacion.md` | `vista-consulta-con-validaciones`<br>`consulta-a-bd` |
| **Alterar Tablas, Índices o Integridad Referencial** | • `docs/contracts/DB_BASELINE_CONTRACT.md`<br>• `docs/modelos/ModeloEntidadRelacion.md`<br>• `schema/tables/` | `consistencia-tablas` |
| **Gestión de Seguridad, Roles y Permisos (RBAC)** | • `schema/security/`<br>• `docs/catalogos/` | `modelo-jerarquico-rbac` |
| **Diseño y Ejecución de Pruebas Unitarias SQL** | • `test_suite.sql`<br>• `test/`<br>• `test_summary.ps1` | `cobertura-pruebas-objetos-bd` |

---

## 🔄 4. Ciclo de Vida para Cambios en Base de Datos

Todo desarrollo o ajuste en base de datos debe cumplir las 5 etapas:

1. **Planificación:** Determinar si el objeto está congelado en el baseline. Si lo está, formular work-item en `docs/work-items/`.
2. **Definición de Contrato:** Declarar firma de entrada, salida, tipos T-SQL y códigos de error esperados.
3. **Pruebas (TDD en SQL):** Escribir los escenarios en `test_suite.sql` o archivo específico en `test/` (Happy Path, Datos Inválidos, Violación de Unicidad, Concurrencia).
4. **Implementación:** Redactar el script en `schema/` respetando convenciones y el orden de despliegue de `deploy_schema.ps1`.
5. **Auditoría y Validación:** Ejecutar `test_summary.ps1` comprobando 100% de pruebas pasando y sin violaciones de seguridad.