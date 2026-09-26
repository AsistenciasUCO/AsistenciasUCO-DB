# Plan de Trabajo y Roadmap de Historias de Usuario — gestionasistenciadb 🚀

Este documento presenta la ruta de desarrollo del repositorio **`gestionasistenciadb`**, organizada de **menor a mayor complejidad de implementación** y estructurada en tres hitos de entrega (**50%**, **75%** y **100%**).

> [!IMPORTANT]
> **Paradigma Arquitectónico de Base de Datos:**
> 1. **100% Lógica de Negocio en Base de Datos:** Toda la lógica reside en Procedimientos Almacenados (`usp_*`), Vistas (`uv_*`), Funciones (`ufn_*`) y Triggers.
> 2. **Alineación con el Modelo de Datos Real:** Se removió la entidad descontinuada `Prerrequisito` (no existente en el esquema de 34 tablas) y se reajustaron las Historias HU025, HU073, HU074 y HU075 hacia las entidades reales (`SemestrePlanEstudio`, `Asignatura`, `PlanEstudio`).
> 3. **Cobertura Total:** Cubre las 174 Historias de Usuario (HU001 a HU174).

---

## 📊 Resumen General de los Hitos de Entrega

| Hito / Entrega | Cantidad HUs | Alcance Funcional en Base de Datos |
| :--- | :---: | :--- |
| 🎯 **Entrega al 50%** | **87 HUs** | Catálogos Semilla + Estructura Académica + Usuarios y Sincronización + Apertura de Grupos y Matrícula. |
| 🎯 **Entrega al 75%** | **43 HUs** | Ciclo de Vida de Sesiones de Clase + Toma Masiva/Individual de Asistencia + Validaciones + Históricos. |
| 🎯 **Entrega al 100%** | **44 HUs** | Flujo de Novedades y Justificaciones + Dashboards Directivos Jerárquicos + Triggers de Auditoría + Parámetros. |
| **TOTAL** | **174 HUs** | **Aplicación 100% Funcional con Lógica de Negocio Centralizada en BD.** |

---

## 🎯 1. Hito de Desarrollo: Entrega al 50% (Cimientos y Fundamentos)
* **Cantidad de Historias:** 87 HUs (HU001 a HU084 + HU170, HU171, HU173)
* **Alcance:** Infraestructura base, tablas maestras, vistas semillero, sincronización de usuarios e inscripción a grupos.

| HU ID | Actor | Título y Descripción | Nivel de Complejidad y Secuencia | Objeto BD Asociado |
| :--- | :--- | :--- | :--- | :--- |
| **HU001** | `Estudiante` | **HU001 Ver los detalles de las asistencias** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU002** | `Sistema` | **HU002 Consultar los registros de asistencia** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU003** | `Sistema` | **HU003 Ver la lista de estudiantes de un grupo o clase** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU004** | `Sistema` | **HU004 Ver el estado de un estudiante dentro de un grupo específico** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU005** | `Sistema` | **HU005 Ver los posibles motivos para justificar una ausencia o llegada tarde** | Nivel 1: Lectura de Catálogos Semilla (Baja) | `Vistas/Funciones de Lectura (`uv_*`)` |
| **HU006** | `Sistema` | **HU006 Buscar la información de un estudiante en particular** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `Procedimiento `usp_sincronizar_...`` |
| **HU007** | `Sistema` | **HU007 Buscar información sobre las materias** | Nivel 2: Estructura Académica Base (Baja-Media) | `Tablas Maestras y Vistas (`uv_*`)` |
| **HU008** | `Sistema` | **HU008 Ver la información de los grupos existentes** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU009** | `Estudiante` | **HU009 Consultar los registros de asistencia** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU010** | `Sistema` | **HU010 Registrar una nueva solicitud para que se revise una asistencia** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU011** | `Sistema` | **HU011 Adjuntar un archivo a solicitud de revisión** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU012** | `Sistema` | **HU012 Buscar y ver las solicitudes de revisión de asistencia pendientes o resueltas** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU013** | `Sistema` | **HU013 Ver los detalles de las asistencias** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU014** | `Estudiante` | **HU014 Registrar una nueva solicitud para que se revise una asistencia** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU015** | `Sistema` | **HU015 Adjuntar un archivo a solicitud de revisión** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU016** | `Sistema` | **HU016 Ver los posibles motivos para justificar una ausencia o llegada tarde** | Nivel 1: Lectura de Catálogos Semilla (Baja) | `Vistas/Funciones de Lectura (`uv_*`)` |
| **HU017** | `Sistema` | **HU017 Ver las sesiones de clase programadas** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU018** | `Estudiante` | **HU018 Ver información de los semestres** | Nivel 2: Estructura Académica Base (Baja-Media) | `Tablas Maestras y Vistas (`uv_*`)` |
| **HU019** | `Sistema` | **HU019 Ver los planes de estudio de las carreras** | Nivel 2: Estructura Académica Base (Baja-Media) | `Tablas Maestras y Vistas (`uv_*`)` |
| **HU020** | `Estudiante` | **HU020 Ver los horarios de las clases** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU021** | `Sistema` | **HU021 Consultar los días de la semana** | Nivel 1: Lectura de Catálogos Semilla (Baja) | `Vistas/Funciones de Lectura (`uv_*`)` |
| **HU022** | `Estudiante` | **HU022 Ver los tipos de identificación disponibles** | Nivel 1: Lectura de Catálogos Semilla (Baja) | `Vistas/Funciones de Lectura (`uv_*`)` |
| **HU023** | `Sistema` | **HU023 Ver los tipos de programa que ofrece la universidad** | Nivel 1: Lectura de Catálogos Semilla (Baja) | `Vistas/Funciones de Lectura (`uv_*`)` |
| **HU024** | `Sistema` | **HU024 Ver los diferentes tipos de estados que se usan** | Nivel 1: Lectura de Catálogos Semilla (Baja) | `Vistas/Funciones de Lectura (`uv_*`)` |
| **HU025** | `Estudiante` | **HU025 Consultar asignaturas asociadas por semestre en el plan de estudios** | Nivel 2: Estructura Académica Base (Baja-Media) | `Tablas Maestras y Vistas (`uv_*`)` |
| **HU026** | `Estudiante` | **HU026 Registrar estudiante en grupo** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU027** | `Docente` | **HU027 Registrar asistencia de un estudiante a una clase específica** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU028** | `Sistema` | **HU028 Registrar la asistencia de una sesión** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU029** | `Sistema` | **HU029 Registrar asistencia detallada para una sesión de un estudiante** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU030** | `Sistema` | **HU030 Ver las sesiones de clase programadas** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU031** | `Sistema` | **HU031 Ver la información de los grupos existentes** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU032** | `Sistema` | **HU032 Ver la lista de estudiantes de un grupo o clase** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU033** | `Docente` | **HU033 Registrar asistencia de un estudiante a una clase específica** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU034** | `Sistema` | **HU034 Registrar asistencia detallada para una sesión de un estudiante** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU035** | `Docente` | **HU035 Buscar y ver las solicitudes de revisión de asistencia pendientes o resueltas** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU036** | `Sistema` | **HU036 Cambiar el estado o la información de una solicitud de revisión** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU037** | `Sistema` | **HU037 Aprobar una solicitud de revisión de asistencia** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU038** | `Sistema` | **HU038 Avisar al interesado sobre la decisión de su solicitud de revisión** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU039** | `Sistema` | **HU039 Eliminar una solicitud de revisión de asistencia** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU040** | `Sistema` | **HU040 Consultar los registros de asistencia** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU041** | `Sistema` | **HU041 Ver los detalles de las asistencias** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU042** | `Sistema` | **HU042 Ver los posibles motivos para justificar una ausencia o llegada tarde** | Nivel 1: Lectura de Catálogos Semilla (Baja) | `Vistas/Funciones de Lectura (`uv_*`)` |
| **HU043** | `Docente` | **HU043 Crear un nuevo grupo para una materia** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU044** | `Sistema` | **HU044 Actualizar los datos de un grupo** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU045** | `Sistema` | **HU045 Programar una nueva sesión de clase para una materia** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU046** | `Sistema` | **HU046 Cambiar los datos de una sesión de clase** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU047** | `Sistema` | **HU047 Cancelar una sesión de clase** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU048** | `Sistema` | **HU048 Crear horarios para las clases** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU049** | `Sistema` | **HU049 Modificar los horarios existentes** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU050** | `Sistema` | **HU050 Inscribir un estudiante en un grupo o clase** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU051** | `Sistema` | **HU051 Retirar a un estudiante de un grupo o clase** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU052** | `Sistema` | **HU052 Ver la lista de estudiantes de un grupo o clase** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU053** | `Sistema` | **HU053 Aceptar la solicitud de un estudiante para unirse a un grupo** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU054** | `Sistema` | **HU054 Rechazar la solicitud de un estudiante para unirse a un grupo** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU055** | `Docente` | **v** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU056** | `Sistema` | **HU056 Borrar detalles de las asistencias** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU057** | `Docente` | **HU057 Ver los tipos de identificación disponibles** | Nivel 1: Lectura de Catálogos Semilla (Baja) | `Vistas/Funciones de Lectura (`uv_*`)` |
| **HU058** | `Sistema` | **HU058 Ver los tipos de programa que ofrece la universidad** | Nivel 1: Lectura de Catálogos Semilla (Baja) | `Vistas/Funciones de Lectura (`uv_*`)` |
| **HU059** | `Sistema` | **HU059 Ver los diferentes tipos de estados que se usan** | Nivel 1: Lectura de Catálogos Semilla (Baja) | `Vistas/Funciones de Lectura (`uv_*`)` |
| **HU060** | `Coordinador de programa` | **HU060 Consultar los registros de asistencia** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU061** | `Sistema` | **HU061 Ver los detalles de las asistencias** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU062** | `Sistema` | **HU062 Ver la lista de todos los profesores de la universidad** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `Procedimiento `usp_sincronizar_...`` |
| **HU063** | `Sistema` | **HU063 Buscar la información de un profesor en particular** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `Procedimiento `usp_sincronizar_...`` |
| **HU064** | `Sistema` | **HU064 Ver la información de los grupos existentes** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU065** | `Sistema` | **HU065 Ver las sesiones de clase programadas** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU066** | `Coordinador de programa` | **HU066 Consultar los registros de asistencia** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU067** | `Sistema` | **HU067 Ver los detalles de las asistencias** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU068** | `Sistema` | **HU068 Ver la lista de todos los estudiantes de la universidad** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `Procedimiento `usp_sincronizar_...`` |
| **HU069** | `Sistema` | **HU069 Buscar la información de un estudiante en particular** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `Procedimiento `usp_sincronizar_...`` |
| **HU070** | `Sistema` | **HU070 Calcular o hallar estado estudiante dentro de un grupo** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |
| **HU071** | `Sistema` | **HU071 Buscar información sobre las materias** | Nivel 2: Estructura Académica Base (Baja-Media) | `Tablas Maestras y Vistas (`uv_*`)` |
| **HU072** | `Sistema` | **HU072 Ver la información de los programas académicos** | Nivel 2: Estructura Académica Base (Baja-Media) | `Tablas Maestras y Vistas (`uv_*`)` |
| **HU073** | `Coordinador de programa` | **HU073 Consultar intensidad horaria y créditos de asignaturas del programa** | Nivel 2: Estructura Académica Base (Baja-Media) | `Tablas Maestras y Vistas (`uv_*`)` |
| **HU074** | `Coordinador de programa` | **HU074 Activar o inactivar asignaturas dentro del catálogo académico** | Nivel 2: Estructura Académica Base (Baja-Media) | `Tablas Maestras y Vistas (`uv_*`)` |
| **HU075** | `Coordinador de programa` | **HU075 Organizar la secuencia de semestres en el plan de estudios** | Nivel 2: Estructura Académica Base (Baja-Media) | `Tablas Maestras y Vistas (`uv_*`)` |
| **HU076** | `Coordinador de programa` | **HU076 Agregar un nuevo programa académico** | Nivel 2: Estructura Académica Base (Baja-Media) | `Tablas Maestras y Vistas (`uv_*`)` |
| **HU077** | `Sistema` | **HU077 Cambiar los datos de un programa académico** | Nivel 2: Estructura Académica Base (Baja-Media) | `Tablas Maestras y Vistas (`uv_*`)` |
| **HU078** | `Sistema` | **HU078 Marcar un programa académico como activo o inactivo** | Nivel 2: Estructura Académica Base (Baja-Media) | `Tablas Maestras y Vistas (`uv_*`)` |
| **HU079** | `Sistema` | **HU079 Crear un nuevo plan de estudios para una carrera** | Nivel 2: Estructura Académica Base (Baja-Media) | `Tablas Maestras y Vistas (`uv_*`)` |
| **HU080** | `Sistema` | **HU080 Cambiar la información de un plan de estudios** | Nivel 2: Estructura Académica Base (Baja-Media) | `Tablas Maestras y Vistas (`uv_*`)` |
| **HU081** | `Sistema` | **HU081 Marcar un plan de estudios como activo o inactivo** | Nivel 2: Estructura Académica Base (Baja-Media) | `Tablas Maestras y Vistas (`uv_*`)` |
| **HU082** | `Sistema` | **HU082 Añadir un semestre a un plan de estudios** | Nivel 2: Estructura Académica Base (Baja-Media) | `Tablas Maestras y Vistas (`uv_*`)` |
| **HU083** | `Sistema` | **HU083 Quitar un semestre de un plan de estudios** | Nivel 2: Estructura Académica Base (Baja-Media) | `Tablas Maestras y Vistas (`uv_*`)` |
| **HU084** | `Sistema` | **HU084 Ver qué semestres componen un plan de estudios específico** | Nivel 2: Estructura Académica Base (Baja-Media) | `Tablas Maestras y Vistas (`uv_*`)` |
| **HU170** | `Sistema` | **HU170 Sincronización masiva automática de usuarios externos a internos** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `Procedimiento `usp_sincronizar_...`` |
| **HU171** | `Sistema` | **HU171 Asignación e inscripción automática de estudiantes a programas académicos** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `Procedimiento `usp_sincronizar_...`` |
| **HU173** | `Sistema` | **HU173 Validación preventiva de cruce de horarios para docentes y estudiantes** | Nivel 4: Oferta Horaria y Grupos (Media) | `Procedimiento `usp_registrar_estudiante_en_grupo_...`` |

---

## 🎯 2. Hito de Desarrollo: Entrega al 75% (Motor Transaccional de Asistencia)
* **Cantidad de Historias:** 43 HUs (HU085 a HU127)
* **Alcance:** Apertura/cierre de sesiones de clase, toma masiva e individual de asistencia, validaciones de fecha e históricos.

| HU ID | Actor | Título y Descripción | Nivel de Complejidad y Secuencia | Objeto BD Asociado |
| :--- | :--- | :--- | :--- | :--- |
| **HU085** | `Sistema` | **HU085 Agregar una nueva materia al sistema** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU086** | `Sistema` | **HU086 Buscar información sobre las materias** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU087** | `Sistema` | **HU087 Cambiar los datos de una materia** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU088** | `Coordinador de programa` | **HU088 Ver las facultades que tiene la universidad** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU089** | `Sistema` | **HU089 Ver la lista de todos los empleados de la universidad** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU090** | `Sistema` | **v** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU091** | `Sistema` | **HU091 Agregar un nuevo profesor a la universidad** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU092** | `Sistema` | **HU092 Cambiar los datos de un profesor** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU093** | `Sistema` | **HU093 Marcar a un profesor como activo o inactivo** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU094** | `Sistema` | **HU094 Buscar la información de un profesor en particular** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU095** | `Sistema` | **HU095 Ver la lista de todos los profesores de la universidad** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU096** | `Coordinador de programa` | **HU096 Crear un nuevo periodo académico** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU097** | `Sistema` | **HU097 Modificar los datos de un periodo académico** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU098** | `Sistema` | **HU098 Eliminar un periodo académico** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU099** | `Coordinador de programa` | **HU099 Ver los tipos de identificación disponibles** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU100** | `Sistema` | **HU100 Ver los tipos de programa que ofrece la universidad** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU101** | `Sistema` | **HU101 Ver los diferentes tipos de estados que se usan** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU102** | `Decano de facultad` | **HU102 Consultar los registros de asistencia** | Nivel 6: Toma y Consulta de Asistencia (Media-Alta) | `Procedimiento `usp_registrar_asistencia_...`` |
| **HU103** | `Sistema` | **HU103 Ver los detalles de las asistencias** | Nivel 6: Toma y Consulta de Asistencia (Media-Alta) | `Procedimiento `usp_registrar_asistencia_...`` |
| **HU104** | `Sistema` | **HU104 Ver la lista de todos los estudiantes de la universidad** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU105** | `Sistema` | **HU105 Buscar la información de un estudiante en particular** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU106** | `Sistema` | **HU106 Calcular o hallar estado estudiante dentro de un grupo** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU107** | `Sistema` | **HU107 Ver las facultades que tiene la universidad** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU108** | `Sistema` | **HU108 Ver la información de los programas académicos** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU109** | `Decano de facultad` | **HU109 Ver las facultades que tiene la universidad** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU110** | `Sistema` | **HU110 Cambiar los datos de una facultad** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU111** | `Sistema` | **HU111 Marcar una facultad como activa o inactiva** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU112** | `Sistema` | **HU112 Ver la información de los programas académicos** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU113** | `Sistema` | **HU113 Cambiar los datos de un programa académico** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU114** | `Sistema` | **HU114 Marcar un programa académico como activo o inactivo** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU115** | `Sistema` | **v** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU116** | `Decano de facultad` | **HU116 Agregar una nueva facultad** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU117** | `Sistema` | **HU117 Cambiar los datos de una facultad** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU118** | `Sistema` | **HU118 Marcar una facultad como activa o inactiva** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU119** | `Sistema` | **HU119 Ver las facultades que tiene la universidad** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU120** | `Sistema` | **HU120 Agregar un nuevo empleado a la universidad** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU121** | `Sistema` | **HU121 Cambiar los datos de un empleado** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU122** | `Sistema` | **HU122 Marcar a un empleado como activo o inactivo** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU123** | `Sistema` | **HU123 Buscar la información de un empleado en particular** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU124** | `Sistema` | **HU124 Ver la lista de todos los empleados de la universidad** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU125** | `Sistema` | **HU125 Agregar un nuevo profesor a la universidad** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU126** | `Sistema` | **HU126 Cambiar los datos de un profesor** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |
| **HU127** | `Sistema` | **HU127 Marcar a un profesor como activo o inactivo** | Nivel 6: Consultas y Vistas Transaccionales (Media-Alta) | `Vistas Transaccionales (`uv_*`)` |

---

## 🎯 3. Hito de Desarrollo: Entrega al 100% (Novedades, Analítica y Cierre)
* **Cantidad de Historias:** 44 HUs (HU128 a HU169 + HU172, HU174)
* **Alcance:** Solicitudes de revisión con adjuntos, aprobación/rechazo docente en BD, reportes gerenciales para Coordinadores/Decanos, triggers de auditoría, catálogo de parámetros y cierre masivo de periodo.

| HU ID | Actor | Título y Descripción | Nivel de Complejidad y Secuencia | Objeto BD Asociado |
| :--- | :--- | :--- | :--- | :--- |
| **HU128** | `Sistema` | **HU128 Buscar la información de un profesor en particular** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU129** | `Sistema` | **HU129 Ver la lista de todos los profesores de la universidad** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU130** | `Decano de facultad` | **HU130 Ver los tipos de identificación disponibles** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU131** | `Sistema` | **HU131 Ver los tipos de programa que ofrece la universidad** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU132** | `Sistema` | **HU132 Ver los diferentes tipos de estados que se usan** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU133** | `Universidad Católica de Oriente` | **HU133 Consultar los registros de asistencia** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU134** | `Sistema` | **HU134 Ver los detalles de las asistencias** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU135** | `Sistema` | **HU135 Ver la lista de todos los estudiantes de la universidad** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU136** | `Sistema` | **HU136 Ver la lista de todos los profesores de la universidad** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU137** | `Sistema` | **HU137 Ver la lista de todos los empleados de la universidad** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU138** | `Universidad Católica de Oriente` | **HU138 Consultar los registros de asistencia** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU139** | `Sistema` | **HU139 Ver los detalles de las asistencias** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU140** | `Sistema` | **HU140 Ver la lista de todos los estudiantes de la universidad** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU141** | `Sistema` | **HU141 Ver la lista de todos los profesores de la universidad** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU142** | `Sistema` | **HU142 Ver la información de los periodos académicos** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU143** | `Sistema` | **HU143 Buscar información sobre las materias** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU144** | `Sistema` | **HU144 Ver la información de los grupos existentes** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU145** | `Sistema` | **HU145 Ver las sesiones de clase programadas** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU146** | `Sistema` | **HU146 Buscar y ver las solicitudes de revisión de asistencia pendientes o resueltas** | Nivel 7: Gestión de Novedades y Justificaciones (Alta) | `Procedimiento `usp_aprobar_solicitud_...`` |
| **HU147** | `Universidad Católica de Oriente` | **HU147 Ver los componentes de formación** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU148** | `Sistema` | **HU148 Crear un nuevo componente de formación** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU149** | `Sistema` | **HU149 Cambiar la información de un componente** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU150** | `Sistema` | **HU150 Ver las áreas de conocimiento** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU151** | `Sistema` | **HU151 Crear una nueva área de conocimiento** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU152** | `Sistema` | **HU152 Cambiar la información de un área de conocimiento** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU153** | `Universidad Católica de Oriente` | **HU153 Ver los tipos de identificación disponibles** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU154** | `Sistema` | **HU154 Ver los tipos de programa que ofrece la universidad** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU155** | `Sistema` | **HU155 Ver los diferentes tipos de estados que se usan** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU156** | `Universidad Católica de Oriente` | **HU156 Inscribir a un nuevo estudiante en la universidad** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU157** | `Sistema` | **HU157 Buscar la información de un estudiante en particular** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU158** | `Sistema` | **HU158 Ver la lista de todos los estudiantes de la universidad** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU159** | `Sistema` | **HU159 Actualizar los datos de un estudiante** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU160** | `Sistema` | **HU160 Cambiar el estado de un estudiante** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU161** | `Administrador de plataforma` | **HU161 Registrar una nueva institución colaboradora** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU162** | `Sistema` | **HU162 Cambiar los datos de una institución** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU163** | `Sistema` | **HU163 Ver la lista de instituciones registradas** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU164** | `Sistema` | **HU164 Marcar una institución como activa o inactiva** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU165** | `Administrador de plataforma` | **HU165 Ver los tipos de identificación disponibles** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU166** | `Sistema` | **HU166 Ver los tipos de programa que ofrece la universidad** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU167** | `Sistema` | **HU167 Ver los diferentes tipos de estados que se usan** | Nivel 8: Dashboards Gerenciales y Reportes Jerárquicos (Avanzada) | `Vistas Jerárquicas `uv_estadistica_grupo`` |
| **HU168** | `Administrador de plataforma` | **HU168 Configuración y consulta de Parámetros Generales del Sistema** | Nivel 8: Catálogos de Parámetros y Mensajes (Avanzada) | `Tablas `CatalogoParametro`, `CatalogoMensaje...`` |
| **HU169** | `Administrador de plataforma` | **HU169 Catálogo centralizado de mensajes técnicos y de usuario** | Nivel 8: Catálogos de Parámetros y Mensajes (Avanzada) | `Tablas `CatalogoParametro`, `CatalogoMensaje...`` |
| **HU172** | `Sistema / Auditor` | **HU172 Auditoría y trazabilidad de cambios en asistencias y justificaciones** | Nivel 8: Bitácora y Triggers de Auditoría (Alta-Avanzada) | `Triggers de Auditoría y Bitácora` |
| **HU174** | `Sistema` | **HU174 Cierre masivo automático de periodo académico y consolidación de faltas** | Nivel 8: Cierre Masivo de Periodo Académico (Alta-Avanzada) | `Procedimiento de Cierre Operativo` |
