# Reporte de Auditoría: Validación de Roles, Permisos RBAC y Custodia Jerárquica en Rama `develop`

> **Fecha:** 13 de Septiembre de 2026  
> **Repositorio:** `gestionasistenciadb`  
> **Rama Evaluada:** `develop` (Commit `12b9dba`)  
> **Estado de la Auditoría:** 🚨 **BRECHA DETECTADA - REQUIERE IMPLEMENTACIÓN ADITIVA**

---

## 1. Resumen Ejecutivo

Un análisis exhaustivo del código fuente en la rama **`develop`** (53 procedimientos almacenados: 24 públicos y 29 internos) confirma que **actualmente los procedimientos almacenados públicos carecen de validación activa de roles RBAC y de validación de límites jerárquicos de pertenencia (árbol de custodia)**.

Si bien existen dos procedimientos helpers internos en el repositorio (`usp_validar_permiso_rbac_usuario_interno.sql` y `usp_validar_titularidad_jerarquica_interno.sql`), **ninguno de los 24 procedimientos públicos de escritura los invoca ni recibe el parámetro `@usuarioEjecutorId`**.

---

## 2. Definición del Modelo Jerárquico y Reglas de Custodia Requeridas

De acuerdo con las reglas de negocio del sistema, la jerarquía de pertenencia y las fronteras de dominio están estructuradas en el siguiente árbol jerárquico:

```
[INSTITUCIÓN]
    │
    ├── [ADMINISTRADOR DE INSTITUCIÓN]
    │      └── Dominio: Decanos, Facultades, Periodos Académicos, Institución propia.
    │          (No puede alterar facultades/periodos de otra institución).
    │
    └── [FACULTAD] (1 Decano por Facultad)
           │
           ├── [DECANO]
           │      └── Dominio: Coordinadores y Programas Académicos de su Facultad.
           │          (No puede existir sin estar adscrito a su Facultad).
           │
           └── [PROGRAMA ACADÉMICO] (1 Coordinador por Programa)
                  │
                  ├── [COORDINADOR]
                  │      └── Dominio: Docentes en Grupos y Planes de Estudio de su Programa.
                  │          Aprueba solicitudes de registro de docentes en grupos.
                  │          (No puede existir sin estar adscrito a su Programa).
                  │
                  └── [GRUPO & PLAN DE ESTUDIO]
                         │
                         ├── [DOCENTE]
                         │      └── Dominio: Sesiones, Horarios, Estudiantes en Grupo, Asistencias
                         │          y Aprobar/Rechazar solicitudes de revisión de asistencia.
                         │          (No puede existir sin estar asociado a un Grupo).
                         │
                         └── [ESTUDIANTE]
                                └── Dominio: Registro en Grupo (pendiente aprobación por Docente),
                                    Marcar Asistencia Autónoma/Clase (pendiente aprobación por Docente),
                                    Radicar solicitudes de revisión de asistencia.
                                    (No puede crearse ni existir sin estar asociado a Programa y Grupo).
```

---

## 3. Matriz de Auditoría por Procedimiento Almacenado Público en `develop`

La siguiente tabla detalla la condición actual de los 24 procedimientos públicos en `develop` respecto a la validación de rol (RBAC) y de custodia jerárquica:

| Procedimiento Almacenado | Recibe `@usuarioEjecutorId` | Invoca RBAC (`usp_validar_permiso_rbac_usuario_interno`) | Invoca Jerarquía (`usp_validar_titularidad_jerarquica_interno`) | Estado Actual en `develop` |
| :--- | :---: | :---: | :---: | :--- |
| `usp_crear_facultad` | ❌ No | ❌ No | ❌ No | Sin validación de Admin de Institución |
| `usp_crear_periodo_academico` | ❌ No | ❌ No | ❌ No | Sin validación de Admin de Institución |
| `usp_crear_decano` | ❌ No | ❌ No | ❌ No | No valida pertenencia a Facultad del Admin |
| `usp_crear_programa_academico` | ❌ No | ❌ No | ❌ No | No valida que ejecutor sea Decano de la Facultad |
| `usp_crear_coordinador` | ❌ No | ❌ No | ❌ No | No valida pertenencia a Programa del Decano |
| `usp_crear_asignatura` | ❌ No | ❌ No | ❌ No | No valida que ejecutor sea Coordinador del Programa |
| `usp_actualizar_asignatura` | ❌ No | ❌ No | ❌ No | Sin validación de Coordinador |
| `usp_toggle_estado_asignatura` | ❌ No | ❌ No | ❌ No | Sin validación de Coordinador |
| `usp_crear_grupo` | ❌ No | ❌ No | ❌ No | No valida que ejecutor sea Coordinador del Programa |
| `usp_actualizar_grupo` | ❌ No | ❌ No | ❌ No | Sin validación de Coordinador |
| `usp_registrar_docente_en_grupo` | ❌ No | ❌ No | ❌ No | No valida flujo de registro / aprobación por Coordinador |
| `usp_registrar_estudiante_en_grupo` | ❌ No | ❌ No | ❌ No | No valida pre-asociación a Programa y Grupo |
| `usp_resolver_solicitud_matricula` | ❌ No | ❌ No | ❌ No | Sin validación de rol Coordinador / Docente |
| `usp_crear_sesion` | ❌ No | ❌ No | ❌ No | No valida que el ejecutor sea Docente del Grupo |
| `usp_actualizar_sesion` | ❌ No | ❌ No | ❌ No | No valida titularidad de Docente |
| `usp_cerrar_sesion` | ❌ No | ❌ No | ❌ No | No valida titularidad de Docente |
| `usp_generar_sesiones_grupo` | ❌ No | ❌ No | ❌ No | Sin validación de Docente / Coordinador |
| `usp_registrar_asistencia_estudiante` | ❌ No | ❌ No | ❌ No | No valida si es Estudiante adscrito al Grupo |
| `usp_registrar_asistencia_estudiante_autonomo` | ❌ No | ❌ No | ❌ No | No valida adscripción de Estudiante |
| `usp_registrar_asistencias_sesion` | ❌ No | ❌ No | ❌ No | No valida que el ejecutor sea Docente del Grupo |
| `usp_radicar_solicitud_revision_asistencia` | ❌ No | ❌ No | ❌ No | No valida que la asistencia pertenezca al Estudiante |
| `usp_resolver_solicitud_revision_asistencia` | ❌ No | ❌ No | ❌ No | No valida que la solicitud la resuelva el Docente del Grupo |
| `usp_ejecutar_cierre_masivo_periodo` | ❌ No | ❌ No | ❌ No | Sin validación de Administrador |
| `usp_obtener_mensaje_catalogo` | ❌ N/A | ❌ N/A | ❌ N/A | Procedimiento utilitario de lectura |

---

## 4. Brechas Específicas por Dominio Jerárquico

### 4.1. Dominio Administrador de Institución
* **Estado Requerido:** El Administrador gestiona Decanos, Facultades, Periodos Académicos e Institución. Debe estar amarrado a su Institución y solo operar sobre entidades de su Institución.
* **Brecha en `develop`:** `usp_crear_facultad`, `usp_crear_periodo_academico` y `usp_crear_decano` no verifican a qué institución pertenece la entidad creada respecto a la institución del Administrador ejecutor.

### 4.2. Dominio Decano de Facultad
* **Estado Requerido:** Debe existir **exactamente 1 Decano por Facultad**. El Decano no puede existir sin Facultad y tiene dominio exclusivo sobre los Coordinadores y Programas de su Facultad.
* **Brecha en `develop`:** `usp_crear_decano` permite registrar decanos desvinculados o actualizar cualquier facultad sin comprobar que el creador posea permisos de administración sobre dicha facultad. Tampoco restringe a 1 el número de decanos por facultad a nivel de regla de negocio previa.

### 4.3. Dominio Coordinador de Programa
* **Estado Requerido:** Debe existir **exactamente 1 Coordinador por Programa**. El Coordinador no puede existir sin Programa y tiene dominio sobre los Docentes en Grupo y Planes de Estudio de su Programa. Debe aprobar el registro de docentes en grupos.
* **Brecha en `develop`:** `usp_crear_coordinador`, `usp_crear_asignatura`, `usp_crear_grupo` y `usp_registrar_docente_en_grupo` no validan si el usuario ejecutor es el Coordinador titular del programa correspondiente.

### 4.4. Dominio Docente de Grupo y Sesión
* **Estado Requerido:** El Docente tiene dominio sobre las Sesiones, Horarios, Asistencias, Aprobar/Rechazar solicitudes de revisión de asistencia y aprobación de estudiantes en sus grupos. No puede existir sin adscripción a Grupo.
* **Brecha en `develop`:** `usp_registrar_asistencias_sesion`, `usp_actualizar_sesion`, `usp_cerrar_sesion` y `usp_resolver_solicitud_revision_asistencia` ejecutan inserciones/actualizaciones sin validar si quien las ejecuta es el Docente titular asignado al grupo.

### 4.5. Dominio Estudiante
* **Estado Requerido:** El Estudiante **no puede ser creado ni existir sin estar asociado a un Programa Académico y a un Grupo**. Sus marcas de asistencia y solicitudes de revisión de asistencia deben pertenecer estrictamente a sus sesiones/grupos matriculados y quedan sujetas a aprobación del Docente.
* **Brecha en `develop`:** `usp_registrar_estudiante_en_grupo` y `usp_registrar_asistencia_estudiante` no comprueban que el usuario ejecutor coincida con el estudiante o que el estudiante se encuentre previamente adscrito al programa y grupo en estado válido.

---

## 5. Plan de Acción Recomendado (Aditivo sin Alterar Estructura Existente)

Para subsanar las brechas identificadas respetando la directriz de **no eliminar líneas existentes ni alterar la estructura física de las tablas de `develop`**:

1. **Inclusión Aditiva del Parámetro `@usuarioEjecutorId`**:
   - Agregar `@usuarioEjecutorId UNIQUEIDENTIFIER = NULL` como parámetro opcional en los procedimientos públicos de escritura.
2. **Invocación Mandatoria de RBAC y CustodiaJerarquica**:
   - En el PASO 1.5 de cada SP público, ejecutar:
     ```sql
     EXEC dbo.usp_validar_permiso_rbac_usuario_interno
         @idUsuario = @usuarioEjecutorId,
         @codigoPerfilRequerido = 'ROL_REQUERIDO',
         ...
     ```
     ```sql
     EXEC dbo.usp_validar_titularidad_jerarquica_interno
         @idUsuario = @usuarioEjecutorId,
         @idEntidadPadre = @idEntidadPadre,
         @tipoEntidadPadre = 'TIPO',
         ...
     ```
3. **Mantenimiento de Pruebas Unitarias e Integración**:
   - Ejecutar `deploy_schema.ps1` y `test_summary.ps1` garantizando 100% de éxito en todos los escenarios.

---

*Reporte generado por Antigravity AI - Sistema de Auditoría de Base de Datos.*
