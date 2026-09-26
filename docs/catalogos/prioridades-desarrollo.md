# Prioridades de Desarrollo e Historias de Usuario: gestionasistenciadb 🚀

Este documento presenta la ruta de desarrollo organizada por fases lógicas, asociando cada Historia de Usuario (HU) con sus componentes técnicos, prioridad y estado actual.

---

## 🗺️ Matriz de Priorización de Historias de Usuario

| Fase | Sprint | HU ID | Rol | Descripción de la Historia | Componentes / Objetos BD | Prioridad | Estado |
| :--- | :---: | :--- | :--- | :--- | :--- | :---: | :---: |
| **Fase 1: Cimientos** | 1-2 | **HU050** | Sistema | Sincronización de cuentas de usuarios externos a internos. | `usp_sincronizar_usuario_interno` | Alta | **Completado** |
| | | **HU051** | Sistema | Registro automático de estudiantes en programas académicos. | `usp_registrar_estudiante_en_programa_interno` | Alta | **Completado** |
| | | **HU052** | Docente | Registro de docentes en grupos con validación de existencia. | `usp_registrar_docente_en_grupo_usuario_no_existente` | Alta | **Completado** |
| | | **HU053** | Estudiante | Registro e inscripción de estudiantes en grupos académicos. | `usp_registrar_estudiante_en_grupo_usuario_no_existente` | Alta | **Completado** |
| **Fase 2: Captura** | 3-4 | **HU027** | Docente | Registrar la asistencia de un estudiante a una sesión. | `usp_registrar_asistencia_estudiante_clase_especifica` | Crítica | **Siguiente** |
| | | **HU033** | Docente | Modificar la asistencia tomada a un alumno en particular. | `usp_registrar_asistencia_estudiante_clase_especifica` | Alta | Pendiente |
| | | **HU028** | Docente | Crear/Abrir una sesión de clase para toma de asistencia. | Tabla `Sesion`, triggers y validaciones de rango. | Alta | Pendiente |
| | | **HU029** | Docente | Consultar el listado de asistencia de una sesión completa. | Procedimientos de consulta de sesión. | Alta | Pendiente |
| | | **HU034** | Docente | Validar consistencia horaria al abrir clases. | `usp_validar_cruce_horario_docente_interno` | Media | Pendiente |
| **Fase 3: Consulta** | 5 | **HU001** | Estudiante | Ver detalles de inasistencias en tiempo real. | Vista `uv_asistencia`, funciones de cálculo de %. | Alta | Pendiente |
| | | **HU002** | Estudiante | Consultar el histórico consolidado de sus asistencias. | Vista `uv_estudiante_grupo` | Alta | Pendiente |
| | | **HU013** | Estudiante | Recibir alertas visuales al superar el límite de faltas. | Funciones de ausentismo. | Media | Pendiente |
| | | **HU066** | Coordinador | Identificar estudiantes con inasistencias reiteradas. | Vista `uv_estadistica_grupo` | Alta | Pendiente |
| | | **HU102** | Decano | Consultar reportes macro de deserción por ausentismo. | Vistas consolidadas a nivel Facultad/Programa. | Media | Pendiente |
| **Fase 4: Novedades** | 6-7 | **HU010** | Estudiante | Registrar una solicitud de revisión de asistencia por error. | Tabla `SolicitudRevisionAsistencia` | Alta | Pendiente |
| | | **HU014** | Estudiante | Adjuntar soportes/justificaciones médicas a una falta. | Tabla `SolicitudRevisionAsistencia` (campo soporte) | Media | Pendiente |
| | | **HU035** | Docente | Ver solicitudes de revisión pendientes de sus grupos. | SP de consulta de revisiones. | Alta | Pendiente |
| | | **HU037** | Docente | Aprobar/Rechazar justificaciones y actualizar asistencia. | SP de resolución de solicitud y trigger de auditoría. | Alta | Pendiente |

---

## 🎯 Criterios de Transición de Fases

1. **De Fase 1 a Fase 2 (Actual)**: Requiere que todos los procedimientos de sincronización masiva y enrolamiento estén al 100% operativos y probados. *(Cumplido)*.
2. **De Fase 2 a Fase 3**: Requiere que la inserción de asistencias sea consistente y pase todas las reglas de negocio (sin duplicados, sin cruces).
3. **De Fase 3 a Fase 4**: Requiere que los reportes muestren información fidedigna antes de abrir el flujo de correcciones/novedades.
