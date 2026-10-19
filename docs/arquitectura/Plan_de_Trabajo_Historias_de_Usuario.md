# Plan de Trabajo y Roadmap de Historias de Usuario — gestionasistenciadb 🚀

Este documento presenta la ruta de desarrollo secuencial y autosuficiente (**End-to-End**) del proyecto, estructurada para que cada funcionalidad pueda ser construida, operada y probada directamente desde el **Frontend** hacia el **Backend** y la **Base de Datos** sin necesidad de quemar datos por consola SQL.

> [!IMPORTANT]
> **Principio de Precedencia Causal y Secuencia Operativa:**
> 1. **Secuencia de Creación Real (Sin datos quemados):** Catálogos Semilla y Maestros → Estructura Organizacional (Facultades, Sedes) → Personas (Docentes, Coordinadores, Estudiantes) → Estructura Académica (Periodos, Programas, Planes, Asignaturas) → Oferta Horaria y Grupos → Matrícula → Sesiones de Clase → Toma de Asistencia → Novedades, Justificaciones y Cierre.
> 2. **100% Lógica de Negocio en Base de Datos:** Toda la lógica reside en Procedimientos Almacenados (`usp_*`), Vistas (`uv_*`), Funciones (`ufn_*`) y Triggers.
> 3. **Cobertura Total:** Cubre exactamente las 174 Historias de Usuario (HU001 a HU174) alineadas con el esquema relacional de 34 tablas.

---

## 📊 Resumen General de los Hitos de Entrega

| Hito / Entrega | Cantidad HUs | Alcance Funcional End-to-End (Front ↔ Back ↔ BD) |
| :--- | :---: | :--- |
| 🎯 **Entrega al 50%** | **87 HUs** | Catálogos Semilla + Parámetros + Sedes/Facultades (HU116) + Sincronización/Gestión de Docentes y Estudiantes + Periodos y Programas. |
| 🎯 **Entrega al 75%** | **43 HUs** | Planes de Estudio + Malla Curricular + Asignaturas + Apertura de Grupos + Horarios + Matrícula Inicial + Ciclo de Sesiones de Clase. |
| 🎯 **Entrega al 100%** | **44 HUs** | Validación de Grupos + Toma de Asistencia (Docente/QR/Autónoma) + Consultas + Novedades/Justificaciones + Auditoría + Cierre de Periodo. |
| **TOTAL** | **174 HUs** | **Flujo End-to-End 100% operativo desde la interfaz sin intervención manual en BD.** |

---

## 🎯 1. Hito de Desarrollo: Entrega al 50% (Cimientos, Catálogos, Estructura Raíz y Usuarios)
* **Cantidad de Historias:** 87 HUs
* **Objetivo End-to-End:** Disponer en el Frontend de todos los selectores maestros, registrar las Sedes/Facultades de la universidad, habilitar los usuarios del sistema (Docentes, Coordinadores, Estudiantes) y parametrizar los Periodos y Programas académicos.

### 1.1. Catálogos Semilla, Configuración y Parámetros del Sistema (28 HUs)
*Alimentan los formularios iniciales: Tipos de Identificación, Estados, Días, Causas de Inasistencia, Instituciones y Parámetros Globales.*

| HU ID | Actor | Título y Descripción | Nivel de Complejidad y Secuencia | Objeto BD Asociado |
| :--- | :--- | :--- | :--- | :--- |
| **HU021** | `Sistema` | **HU021 Consultar los días de la semana** | Nivel 1: Catálogos Semilla y Configuración (Baja) | Tablas Maestras / Catálogos (`uv_*`) |
| **HU022** | `Estudiante` | **HU022 Ver los tipos de identificación disponibles** | Nivel 1: Catálogos Semilla y Configuración (Baja) | Tablas Maestras / Catálogos (`uv_*`) |
| **HU023** | `Sistema` | **HU023 Ver los tipos de programa que ofrece la universidad** | Nivel 1: Catálogos Semilla y Configuración (Baja) | Tablas Maestras / Catálogos (`uv_*`) |
| **HU024** | `Sistema` | **HU024 Ver los diferentes tipos de estados que se usan** | Nivel 1: Catálogos Semilla y Configuración (Baja) | Tablas Maestras / Catálogos (`uv_*`) |
| **HU057** | `Docente` | **HU057 Ver los tipos de identificación disponibles** | Nivel 1: Catálogos Semilla y Configuración (Baja) | Tablas Maestras / Catálogos (`uv_*`) |
| **HU058** | `Sistema` | **HU058 Ver los tipos de programa que ofrece la universidad** | Nivel 1: Catálogos Semilla y Configuración (Baja) | Tablas Maestras / Catálogos (`uv_*`) |
| **HU059** | `Sistema` | **HU059 Ver los diferentes tipos de estados que se usan** | Nivel 1: Catálogos Semilla y Configuración (Baja) | Tablas Maestras / Catálogos (`uv_*`) |
| **HU099** | `Coordinador de programa` | **HU099 Ver los tipos de identificación disponibles** | Nivel 1: Catálogos Semilla y Configuración (Baja) | Tablas Maestras / Catálogos (`uv_*`) |
| **HU100** | `Sistema` | **HU100 Ver los tipos de programa que ofrece la universidad** | Nivel 1: Catálogos Semilla y Configuración (Baja) | Tablas Maestras / Catálogos (`uv_*`) |
| **HU101** | `Sistema` | **HU101 Ver los diferentes tipos de estados que se usan** | Nivel 1: Catálogos Semilla y Configuración (Baja) | Tablas Maestras / Catálogos (`uv_*`) |
| **HU130** | `Decano de facultad` | **HU130 Ver los tipos de identificación disponibles** | Nivel 1: Catálogos Semilla y Configuración (Baja) | Tablas Maestras / Catálogos (`uv_*`) |
| **HU131** | `Sistema` | **HU131 Ver los tipos de programa que ofrece la universidad** | Nivel 1: Catálogos Semilla y Configuración (Baja) | Tablas Maestras / Catálogos (`uv_*`) |
| **HU132** | `Sistema` | **HU132 Ver los diferentes tipos de estados que se usan** | Nivel 1: Catálogos Semilla y Configuración (Baja) | Tablas Maestras / Catálogos (`uv_*`) |
| **HU153** | `Universidad Católica de Oriente` | **HU153 Ver los tipos de identificación disponibles** | Nivel 1: Catálogos Semilla y Configuración (Baja) | Tablas Maestras / Catálogos (`uv_*`) |
| **HU154** | `Sistema` | **HU154 Ver los tipos de programa que ofrece la universidad** | Nivel 1: Catálogos Semilla y Configuración (Baja) | Tablas Maestras / Catálogos (`uv_*`) |
| **HU155** | `Sistema` | **HU155 Ver los diferentes tipos de estados que se usan** | Nivel 1: Catálogos Semilla y Configuración (Baja) | Tablas Maestras / Catálogos (`uv_*`) |
| **HU165** | `Administrador de plataforma` | **HU165 Ver los tipos de identificación disponibles** | Nivel 1: Catálogos Semilla y Configuración (Baja) | Tablas Maestras / Catálogos (`uv_*`) |
| **HU166** | `Sistema` | **HU166 Ver los tipos de programa que ofrece la universidad** | Nivel 1: Catálogos Semilla y Configuración (Baja) | Tablas Maestras / Catálogos (`uv_*`) |
| **HU167** | `Sistema` | **HU167 Ver los diferentes tipos de estados que se usan** | Nivel 1: Catálogos Semilla y Configuración (Baja) | Tablas Maestras / Catálogos (`uv_*`) |
| **HU005** | `Sistema` | **HU005 Ver los posibles motivos para justificar una ausencia o llegada tarde** | Nivel 1: Catálogos Semilla y Configuración (Baja) | Tablas Maestras / Catálogos (`uv_*`) |
| **HU016** | `Sistema` | **HU016 Ver los posibles motivos para justificar una ausencia o llegada tarde** | Nivel 1: Catálogos Semilla y Configuración (Baja) | Tablas Maestras / Catálogos (`uv_*`) |
| **HU042** | `Sistema` | **HU042 Ver los posibles motivos para justificar una ausencia o llegada tarde** | Nivel 1: Catálogos Semilla y Configuración (Baja) | Tablas Maestras / Catálogos (`uv_*`) |
| **HU161** | `Administrador de plataforma` | **HU161 Registrar una nueva institución colaboradora** | Nivel 1: Catálogos Semilla y Configuración (Baja) | Tablas Maestras / Catálogos (`uv_*`) |
| **HU162** | `Sistema` | **HU162 Cambiar los datos de una institución** | Nivel 1: Catálogos Semilla y Configuración (Baja) | Tablas Maestras / Catálogos (`uv_*`) |
| **HU163** | `Sistema` | **HU163 Ver la lista de instituciones registradas** | Nivel 1: Catálogos Semilla y Configuración (Baja) | Tablas Maestras / Catálogos (`uv_*`) |
| **HU164** | `Sistema` | **HU164 Marcar una institución como activa o inactiva** | Nivel 1: Catálogos Semilla y Configuración (Baja) | Tablas Maestras / Catálogos (`uv_*`) |
| **HU168** | `Administrador de plataforma` | **HU168 Configuración y consulta de Parámetros Generales del Sistema** | Nivel 1: Catálogos Semilla y Configuración (Baja) | Tablas Maestras / Catálogos (`uv_*`) |
| **HU169** | `Administrador de plataforma` | **HU169 Catálogo centralizado de mensajes técnicos y de usuario** | Nivel 1: Catálogos Semilla y Configuración (Baja) | Tablas Maestras / Catálogos (`uv_*`) |

### 1.2. Estructura Organizacional, Sedes y Espacios Físicos (15 HUs)
*Creación de la raíz institucional: Sedes, Facultades (HU116 con Decano obligatorio), Áreas de Conocimiento y Componentes.*

| HU ID | Actor | Título y Descripción | Nivel de Complejidad y Secuencia | Objeto BD Asociado |
| :--- | :--- | :--- | :--- | :--- |
| **HU116** | `Decano de facultad` | **HU116 Agregar una nueva facultad** | Nivel 2: Estructura Organizacional (Baja-Media) | `usp_crear_facultad` / Tablas Maestras (`uv_*`) |
| **HU110** | `Sistema` | **HU110 Cambiar los datos de una facultad** | Nivel 2: Estructura Organizacional (Baja-Media) | `usp_crear_facultad` / Tablas Maestras (`uv_*`) |
| **HU111** | `Sistema` | **HU111 Marcar una facultad como activa o inactiva** | Nivel 2: Estructura Organizacional (Baja-Media) | `usp_crear_facultad` / Tablas Maestras (`uv_*`) |
| **HU117** | `Sistema` | **HU117 Cambiar los datos de una facultad** | Nivel 2: Estructura Organizacional (Baja-Media) | `usp_crear_facultad` / Tablas Maestras (`uv_*`) |
| **HU118** | `Sistema` | **HU118 Marcar una facultad como activa o inactiva** | Nivel 2: Estructura Organizacional (Baja-Media) | `usp_crear_facultad` / Tablas Maestras (`uv_*`) |
| **HU119** | `Sistema` | **HU119 Ver las facultades que tiene la universidad** | Nivel 2: Estructura Organizacional (Baja-Media) | `usp_crear_facultad` / Tablas Maestras (`uv_*`) |
| **HU088** | `Coordinador de programa` | **HU088 Ver las facultades que tiene la universidad** | Nivel 2: Estructura Organizacional (Baja-Media) | `usp_crear_facultad` / Tablas Maestras (`uv_*`) |
| **HU107** | `Sistema` | **HU107 Ver las facultades que tiene la universidad** | Nivel 2: Estructura Organizacional (Baja-Media) | `usp_crear_facultad` / Tablas Maestras (`uv_*`) |
| **HU109** | `Decano de facultad` | **HU109 Ver las facultades que tiene la universidad** | Nivel 2: Estructura Organizacional (Baja-Media) | `usp_crear_facultad` / Tablas Maestras (`uv_*`) |
| **HU150** | `Sistema` | **HU150 Ver las áreas de conocimiento** | Nivel 2: Estructura Organizacional (Baja-Media) | `usp_crear_facultad` / Tablas Maestras (`uv_*`) |
| **HU151** | `Sistema` | **HU151 Crear una nueva área de conocimiento** | Nivel 2: Estructura Organizacional (Baja-Media) | `usp_crear_facultad` / Tablas Maestras (`uv_*`) |
| **HU152** | `Sistema` | **HU152 Cambiar la información de un área de conocimiento** | Nivel 2: Estructura Organizacional (Baja-Media) | `usp_crear_facultad` / Tablas Maestras (`uv_*`) |
| **HU147** | `Universidad Católica de Oriente` | **HU147 Ver los componentes de formación** | Nivel 2: Estructura Organizacional (Baja-Media) | `usp_crear_facultad` / Tablas Maestras (`uv_*`) |
| **HU148** | `Sistema` | **HU148 Crear un nuevo componente de formación** | Nivel 2: Estructura Organizacional (Baja-Media) | `usp_crear_facultad` / Tablas Maestras (`uv_*`) |
| **HU149** | `Sistema` | **HU149 Cambiar la información de un componente** | Nivel 2: Estructura Organizacional (Baja-Media) | `usp_crear_facultad` / Tablas Maestras (`uv_*`) |

### 1.3. Gestión de Identidades, Usuarios y Sincronización Institucional (35 HUs)
*Sincronización y registro de los actores institucionales sobre la jerarquía de `Usuario` y roles vinculados (`Docente`, `Coordinador`, `Decano`, `Estudiante`), reemplazando la entidad heredada `Empleado`.*

| HU ID | Actor | Título y Descripción | Nivel de Complejidad y Secuencia | Objeto BD Asociado |
| :--- | :--- | :--- | :--- | :--- |
| **HU170** | `Sistema` | **HU170 Sincronización masiva automática de usuarios institucionales externos a internos** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `usp_sincronizar_usuario` / Vistas (`uv_*`) |
| **HU089** | `Sistema` | **HU089 Ver la lista de personal docente y administrativo adscrito** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `Usuario`, `Coordinador`, `Docente` (`uv_*`) |
| **HU090** | `Sistema` | **HU090 Buscar la información de un usuario institucional en particular** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `Usuario`, `Docente`, `Coordinador` (`uv_*`) |
| **HU120** | `Sistema` | **HU120 Registrar nuevo usuario institucional (personal/administrativo) en la universidad** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `usp_sincronizar_usuario` / `Usuario` |
| **HU121** | `Sistema` | **HU121 Cambiar los datos de un usuario institucional** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `Usuario` / `usp_sincronizar_usuario` |
| **HU122** | `Sistema` | **HU122 Marcar a un usuario institucional como activo o inactivo** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `Usuario` / `usp_sincronizar_usuario` |
| **HU123** | `Sistema` | **HU123 Buscar la información de un usuario institucional en particular** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `Usuario` / Vistas (`uv_*`) |
| **HU124** | `Sistema` | **HU124 Ver la lista de todo el personal institucional de la universidad** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `Usuario`, `Decano`, `Coordinador`, `Docente` (`uv_*`) |
| **HU137** | `Sistema` | **HU137 Consultar censo y directorio del personal institucional de la universidad** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `Usuario`, `Docente`, `Coordinador`, `Decano` (`uv_*`) |
| **HU062** | `Sistema` | **HU062 Ver la lista de todos los profesores de la universidad** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `usp_sincronizar_usuario` / Vistas (`uv_*`) |
| **HU063** | `Sistema` | **HU063 Buscar la información de un profesor en particular** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `usp_sincronizar_usuario` / Vistas (`uv_*`) |
| **HU091** | `Sistema` | **HU091 Agregar un nuevo profesor a la universidad** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `usp_sincronizar_usuario` / Vistas (`uv_*`) |
| **HU092** | `Sistema` | **HU092 Cambiar los datos de un profesor** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `usp_sincronizar_usuario` / Vistas (`uv_*`) |
| **HU093** | `Sistema` | **HU093 Marcar a un profesor como activo o inactivo** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `usp_sincronizar_usuario` / Vistas (`uv_*`) |
| **HU094** | `Sistema` | **HU094 Buscar la información de un profesor en particular** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `usp_sincronizar_usuario` / Vistas (`uv_*`) |
| **HU095** | `Sistema` | **HU095 Ver la lista de todos los profesores de la universidad** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `usp_sincronizar_usuario` / Vistas (`uv_*`) |
| **HU125** | `Sistema` | **HU125 Agregar un nuevo profesor a la universidad** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `usp_sincronizar_usuario` / Vistas (`uv_*`) |
| **HU126** | `Sistema` | **HU126 Cambiar los datos de un profesor** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `usp_sincronizar_usuario` / Vistas (`uv_*`) |
| **HU127** | `Sistema` | **HU127 Marcar a un profesor como activo o inactivo** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `usp_sincronizar_usuario` / Vistas (`uv_*`) |
| **HU128** | `Sistema` | **HU128 Buscar la información de un profesor en particular** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `usp_sincronizar_usuario` / Vistas (`uv_*`) |
| **HU129** | `Sistema` | **HU129 Ver la lista de todos los profesores de la universidad** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `usp_sincronizar_usuario` / Vistas (`uv_*`) |
| **HU136** | `Sistema` | **HU136 Ver la lista de todos los profesores de la universidad** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `usp_sincronizar_usuario` / Vistas (`uv_*`) |
| **HU141** | `Sistema` | **HU141 Ver la lista de todos los profesores de la universidad** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `usp_sincronizar_usuario` / Vistas (`uv_*`) |
| **HU006** | `Sistema` | **HU006 Buscar la información de un estudiante en particular** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `usp_sincronizar_usuario` / Vistas (`uv_*`) |
| **HU068** | `Sistema` | **HU068 Ver la lista de todos los estudiantes de la universidad** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `usp_sincronizar_usuario` / Vistas (`uv_*`) |
| **HU069** | `Sistema` | **HU069 Buscar la información de un estudiante en particular** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `usp_sincronizar_usuario` / Vistas (`uv_*`) |
| **HU104** | `Sistema` | **HU104 Ver la lista de todos los estudiantes de la universidad** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `usp_sincronizar_usuario` / Vistas (`uv_*`) |
| **HU105** | `Sistema` | **HU105 Buscar la información de un estudiante en particular** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `usp_sincronizar_usuario` / Vistas (`uv_*`) |
| **HU135** | `Sistema` | **HU135 Ver la lista de todos los estudiantes de la universidad** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `usp_sincronizar_usuario` / Vistas (`uv_*`) |
| **HU140** | `Sistema` | **HU140 Ver la lista de todos los estudiantes de la universidad** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `usp_sincronizar_usuario` / Vistas (`uv_*`) |
| **HU156** | `Universidad Católica de Oriente` | **HU156 Inscribir a un nuevo estudiante en la universidad** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `usp_sincronizar_usuario` / Vistas (`uv_*`) |
| **HU157** | `Sistema` | **HU157 Buscar la información de un estudiante en particular** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `usp_sincronizar_usuario` / Vistas (`uv_*`) |
| **HU158** | `Sistema` | **HU158 Ver la lista de todos los estudiantes de la universidad** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `usp_sincronizar_usuario` / Vistas (`uv_*`) |
| **HU159** | `Sistema` | **HU159 Actualizar los datos de un estudiante** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `usp_sincronizar_usuario` / Vistas (`uv_*`) |
| **HU160** | `Sistema` | **HU160 Cambiar el estado de un estudiante** | Nivel 3: Gestión de Usuarios y Sincronización (Media) | `usp_sincronizar_usuario` / Vistas (`uv_*`) |

### 1.4. Periodos Académicos y Programas de la Universidad (9 HUs)
*Definición de los calendarios operativos y oferta de carreras universitarias adscritas a las facultades.*

| HU ID | Actor | Título y Descripción | Nivel de Complejidad y Secuencia | Objeto BD Asociado |
| :--- | :--- | :--- | :--- | :--- |
| **HU096** | `Coordinador de programa` | **HU096 Crear un nuevo periodo académico** | Nivel 4: Periodos y Programas Académicos (Media) | Vistas y SPs de Programa / Periodo |
| **HU097** | `Sistema` | **HU097 Modificar los datos de un periodo académico** | Nivel 4: Periodos y Programas Académicos (Media) | Vistas y SPs de Programa / Periodo |
| **HU098** | `Sistema` | **HU098 Eliminar un periodo académico** | Nivel 4: Periodos y Programas Académicos (Media) | Vistas y SPs de Programa / Periodo |
| **HU142** | `Sistema` | **HU142 Ver la información de los periodos académicos** | Nivel 4: Periodos y Programas Académicos (Media) | Vistas y SPs de Programa / Periodo |
| **HU072** | `Sistema` | **HU072 Ver la información de los programas académicos** | Nivel 4: Periodos y Programas Académicos (Media) | Vistas y SPs de Programa / Periodo |
| **HU076** | `Coordinador de programa` | **HU076 Agregar un nuevo programa académico** | Nivel 4: Periodos y Programas Académicos (Media) | Vistas y SPs de Programa / Periodo |
| **HU077** | `Sistema` | **HU077 Cambiar los datos de un programa académico** | Nivel 4: Periodos y Programas Académicos (Media) | Vistas y SPs de Programa / Periodo |
| **HU078** | `Sistema` | **HU078 Marcar un programa académico como activo o inactivo** | Nivel 4: Periodos y Programas Académicos (Media) | Vistas y SPs de Programa / Periodo |
| **HU108** | `Sistema` | **HU108 Ver la información de los programas académicos** | Nivel 4: Periodos y Programas Académicos (Media) | Vistas y SPs de Programa / Periodo |

---

## 🎯 2. Hito de Desarrollo: Entrega al 75% (Oferta Académica, Malla, Grupos, Horarios y Sesiones)
* **Cantidad de Historias:** 43 HUs
* **Objetivo End-to-End:** Estructurar los planes de estudio y asignaturas, abrir la oferta de grupos con sus horarios asignados a docentes, inscribir estudiantes y programar las sesiones de clase en el calendario.

### 2.1. Planes de Estudio, Semestres y Catálogo de Asignaturas (23 HUs)
*Malla curricular por semestre, créditos, intensidades horarias y asignaturas por carrera.*

| HU ID | Actor | Título y Descripción | Nivel de Complejidad y Secuencia | Objeto BD Asociado |
| :--- | :--- | :--- | :--- | :--- |
| **HU112** | `Sistema` | **HU112 Ver la información de los programas académicos** | Nivel 5: Planes de Estudio y Asignaturas (Media) | Tablas Maestras y Vistas (`uv_*`) |
| **HU113** | `Sistema` | **HU113 Cambiar los datos de un programa académico** | Nivel 5: Planes de Estudio y Asignaturas (Media) | Tablas Maestras y Vistas (`uv_*`) |
| **HU114** | `Sistema` | **HU114 Marcar un programa académico como activo o inactivo** | Nivel 5: Planes de Estudio y Asignaturas (Media) | Tablas Maestras y Vistas (`uv_*`) |
| **HU019** | `Sistema` | **HU019 Ver los planes de estudio de las carreras** | Nivel 5: Planes de Estudio y Asignaturas (Media) | Tablas Maestras y Vistas (`uv_*`) |
| **HU079** | `Sistema` | **HU079 Crear un nuevo plan de estudios para una carrera** | Nivel 5: Planes de Estudio y Asignaturas (Media) | Tablas Maestras y Vistas (`uv_*`) |
| **HU080** | `Sistema` | **HU080 Cambiar la información de un plan de estudios** | Nivel 5: Planes de Estudio y Asignaturas (Media) | Tablas Maestras y Vistas (`uv_*`) |
| **HU081** | `Sistema` | **HU081 Marcar un plan de estudios como activo o inactivo** | Nivel 5: Planes de Estudio y Asignaturas (Media) | Tablas Maestras y Vistas (`uv_*`) |
| **HU115** | `Sistema` | **HU115 Ver los planes de estudio de las carreras** | Nivel 5: Planes de Estudio y Asignaturas (Media) | Tablas Maestras y Vistas (`uv_*`) |
| **HU018** | `Estudiante` | **HU018 Ver información de los semestres** | Nivel 5: Planes de Estudio y Asignaturas (Media) | Tablas Maestras y Vistas (`uv_*`) |
| **HU082** | `Sistema` | **HU082 Añadir un semestre a un plan de estudios** | Nivel 5: Planes de Estudio y Asignaturas (Media) | Tablas Maestras y Vistas (`uv_*`) |
| **HU083** | `Sistema` | **HU083 Quitar un semestre de un plan de estudios** | Nivel 5: Planes de Estudio y Asignaturas (Media) | Tablas Maestras y Vistas (`uv_*`) |
| **HU084** | `Sistema` | **HU084 Ver qué semestres componen un plan de estudios específico** | Nivel 5: Planes de Estudio y Asignaturas (Media) | Tablas Maestras y Vistas (`uv_*`) |
| **HU075** | `Coordinador de programa` | **HU075 Organizar la secuencia de semestres en el plan de estudios** | Nivel 5: Planes de Estudio y Asignaturas (Media) | Tablas Maestras y Vistas (`uv_*`) |
| **HU007** | `Sistema` | **HU007 Buscar información sobre las materias** | Nivel 5: Planes de Estudio y Asignaturas (Media) | Tablas Maestras y Vistas (`uv_*`) |
| **HU025** | `Estudiante` | **HU025 Consultar asignaturas asociadas por semestre en el plan de estudios** | Nivel 5: Planes de Estudio y Asignaturas (Media) | Tablas Maestras y Vistas (`uv_*`) |
| **HU071** | `Sistema` | **HU071 Buscar información sobre las materias** | Nivel 5: Planes de Estudio y Asignaturas (Media) | Tablas Maestras y Vistas (`uv_*`) |
| **HU073** | `Coordinador de programa` | **HU073 Consultar intensidad horaria y créditos de asignaturas del programa** | Nivel 5: Planes de Estudio y Asignaturas (Media) | Tablas Maestras y Vistas (`uv_*`) |
| **HU074** | `Coordinador de programa` | **HU074 Activar o inactivar asignaturas dentro del catálogo académico** | Nivel 5: Planes de Estudio y Asignaturas (Media) | Tablas Maestras y Vistas (`uv_*`) |
| **HU085** | `Sistema` | **HU085 Agregar una nueva materia al sistema** | Nivel 5: Planes de Estudio y Asignaturas (Media) | Tablas Maestras y Vistas (`uv_*`) |
| **HU086** | `Sistema` | **HU086 Buscar información sobre las materias** | Nivel 5: Planes de Estudio y Asignaturas (Media) | Tablas Maestras y Vistas (`uv_*`) |
| **HU087** | `Sistema` | **HU087 Cambiar los datos de una materia** | Nivel 5: Planes de Estudio y Asignaturas (Media) | Tablas Maestras y Vistas (`uv_*`) |
| **HU143** | `Sistema` | **HU143 Buscar información sobre las materias** | Nivel 5: Planes de Estudio y Asignaturas (Media) | Tablas Maestras y Vistas (`uv_*`) |
| **HU171** | `Sistema` | **HU171 Asignación e inscripción automática de estudiantes a programas académicos** | Nivel 5: Planes de Estudio y Asignaturas (Media) | Tablas Maestras y Vistas (`uv_*`) |

### 2.2. Oferta de Grupos, Horarios y Matrícula Estudiantil (13 HUs)
*Apertura de grupos para cada materia, asignación de horarios por día/aula y matrícula de estudiantes en el grupo.*

| HU ID | Actor | Título y Descripción | Nivel de Complejidad y Secuencia | Objeto BD Asociado |
| :--- | :--- | :--- | :--- | :--- |
| **HU008** | `Sistema` | **HU008 Ver la información de los grupos existentes** | Nivel 6: Oferta Horaria y Grupos (Media-Alta) | `usp_registrar_estudiante_en_grupo` / Grupos |
| **HU031** | `Sistema` | **HU031 Ver la información de los grupos existentes** | Nivel 6: Oferta Horaria y Grupos (Media-Alta) | `usp_registrar_estudiante_en_grupo` / Grupos |
| **HU043** | `Docente` | **HU043 Crear un nuevo grupo para una materia** | Nivel 6: Oferta Horaria y Grupos (Media-Alta) | `usp_registrar_estudiante_en_grupo` / Grupos |
| **HU044** | `Sistema` | **HU044 Actualizar los datos de un grupo** | Nivel 6: Oferta Horaria y Grupos (Media-Alta) | `usp_registrar_estudiante_en_grupo` / Grupos |
| **HU064** | `Sistema` | **HU064 Ver la información de los grupos existentes** | Nivel 6: Oferta Horaria y Grupos (Media-Alta) | `usp_registrar_estudiante_en_grupo` / Grupos |
| **HU144** | `Sistema` | **HU144 Ver la información de los grupos existentes** | Nivel 6: Oferta Horaria y Grupos (Media-Alta) | `usp_registrar_estudiante_en_grupo` / Grupos |
| **HU020** | `Estudiante` | **HU020 Ver los horarios de las clases** | Nivel 6: Oferta Horaria y Grupos (Media-Alta) | `usp_registrar_estudiante_en_grupo` / Grupos |
| **HU048** | `Sistema` | **HU048 Crear horarios para las clases** | Nivel 6: Oferta Horaria y Grupos (Media-Alta) | `usp_registrar_estudiante_en_grupo` / Grupos |
| **HU049** | `Sistema` | **HU049 Modificar los horarios existentes** | Nivel 6: Oferta Horaria y Grupos (Media-Alta) | `usp_registrar_estudiante_en_grupo` / Grupos |
| **HU173** | `Sistema` | **HU173 Validación preventiva de cruce de horarios para docentes y estudiantes** | Nivel 6: Oferta Horaria y Grupos (Media-Alta) | `usp_registrar_estudiante_en_grupo` / Grupos |
| **HU026** | `Estudiante` | **HU026 Registrar estudiante en grupo** | Nivel 6: Oferta Horaria y Grupos (Media-Alta) | `usp_registrar_estudiante_en_grupo` / Grupos |
| **HU050** | `Sistema` | **HU050 Inscribir un estudiante en un grupo o clase** | Nivel 6: Oferta Horaria y Grupos (Media-Alta) | `usp_registrar_estudiante_en_grupo` / Grupos |
| **HU051** | `Sistema` | **HU051 Retirar a un estudiante de un grupo o clase** | Nivel 6: Oferta Horaria y Grupos (Media-Alta) | `usp_registrar_estudiante_en_grupo` / Grupos |

### 2.3. Programación y Ciclo de Vida de Sesiones de Clase (7 HUs)
*Generación de sesiones de clase, cambios de fecha/hora, reprogramación y cancelación operativa.*

| HU ID | Actor | Título y Descripción | Nivel de Complejidad y Secuencia | Objeto BD Asociado |
| :--- | :--- | :--- | :--- | :--- |
| **HU017** | `Sistema` | **HU017 Ver las sesiones de clase programadas** | Nivel 7: Ciclo de Vida de Sesiones (Media-Alta) | `usp_programar_sesion` / Vistas de Sesión |
| **HU030** | `Sistema` | **HU030 Ver las sesiones de clase programadas** | Nivel 7: Ciclo de Vida de Sesiones (Media-Alta) | `usp_programar_sesion` / Vistas de Sesión |
| **HU045** | `Sistema` | **HU045 Programar una nueva sesión de clase para una materia** | Nivel 7: Ciclo de Vida de Sesiones (Media-Alta) | `usp_programar_sesion` / Vistas de Sesión |
| **HU046** | `Sistema` | **HU046 Cambiar los datos de una sesión de clase** | Nivel 7: Ciclo de Vida de Sesiones (Media-Alta) | `usp_programar_sesion` / Vistas de Sesión |
| **HU047** | `Sistema` | **HU047 Cancelar una sesión de clase** | Nivel 7: Ciclo de Vida de Sesiones (Media-Alta) | `usp_programar_sesion` / Vistas de Sesión |
| **HU065** | `Sistema` | **HU065 Ver las sesiones de clase programadas** | Nivel 7: Ciclo de Vida de Sesiones (Media-Alta) | `usp_programar_sesion` / Vistas de Sesión |
| **HU145** | `Sistema` | **HU145 Ver las sesiones de clase programadas** | Nivel 7: Ciclo de Vida de Sesiones (Media-Alta) | `usp_programar_sesion` / Vistas de Sesión |

---

## 🎯 3. Hito de Desarrollo: Entrega al 100% (Verificación de Grupos, Toma de Asistencia, Novedades y Cierre)
* **Cantidad de Historias:** 44 HUs
* **Objetivo End-to-End:** Ejecutar el flujo transaccional en tiempo real: toma de asistencia manual y por QR, cálculo de inasistencias y riesgos, gestión de reclamos con soportes, auditoría de cambios y cierre definitivo del semestre.

### 3.1. Gestión y Estado de Estudiantes en el Grupo (8 HUs)
*Listados de asistencia por clase, estados del estudiante (activo/retirado), aprobación de solicitudes de cupo.*

| HU ID | Actor | Título y Descripción | Nivel de Complejidad y Secuencia | Objeto BD Asociado |
| :--- | :--- | :--- | :--- | :--- |
| **HU053** | `Sistema` | **HU053 Aceptar la solicitud de un estudiante para unirse a un grupo** | Nivel 8: Monitoreo y Estados de Grupo (Media-Alta) | `uv_estudiantes_grupo` / Procedimientos |
| **HU054** | `Sistema` | **HU054 Rechazar la solicitud de un estudiante para unirse a un grupo** | Nivel 8: Monitoreo y Estados de Grupo (Media-Alta) | `uv_estudiantes_grupo` / Procedimientos |
| **HU003** | `Sistema` | **HU003 Ver la lista de estudiantes de un grupo o clase** | Nivel 8: Monitoreo y Estados de Grupo (Media-Alta) | `uv_estudiantes_grupo` / Procedimientos |
| **HU004** | `Sistema` | **HU004 Ver el estado de un estudiante dentro de un grupo específico** | Nivel 8: Monitoreo y Estados de Grupo (Media-Alta) | `uv_estudiantes_grupo` / Procedimientos |
| **HU032** | `Sistema` | **HU032 Ver la lista de estudiantes de un grupo o clase** | Nivel 8: Monitoreo y Estados de Grupo (Media-Alta) | `uv_estudiantes_grupo` / Procedimientos |
| **HU052** | `Sistema` | **HU052 Ver la lista de estudiantes de un grupo o clase** | Nivel 8: Monitoreo y Estados de Grupo (Media-Alta) | `uv_estudiantes_grupo` / Procedimientos |
| **HU070** | `Sistema` | **HU070 Calcular o hallar estado estudiante dentro de un grupo** | Nivel 8: Monitoreo y Estados de Grupo (Media-Alta) | `uv_estudiantes_grupo` / Procedimientos |
| **HU106** | `Sistema` | **HU106 Calcular o hallar estado estudiante dentro de un grupo** | Nivel 8: Monitoreo y Estados de Grupo (Media-Alta) | `uv_estudiantes_grupo` / Procedimientos |

### 3.2. Captura, Registro y Consulta de Asistencias (23 HUs)
*Registro de asistencia docente (individual/masivo), registro autónomo estudiantil (código QR), consultas e históricos por rol.*

| HU ID | Actor | Título y Descripción | Nivel de Complejidad y Secuencia | Objeto BD Asociado |
| :--- | :--- | :--- | :--- | :--- |
| **HU027** | `Docente` | **HU027 Registrar asistencia de un estudiante a una clase específica** | Nivel 9: Motor Transaccional de Asistencia (Alta) | `usp_registrar_asistencia` / `uv_asistencias` |
| **HU028** | `Sistema` | **HU028 Registrar la asistencia de una sesión** | Nivel 9: Motor Transaccional de Asistencia (Alta) | `usp_registrar_asistencia` / `uv_asistencias` |
| **HU029** | `Sistema` | **HU029 Registrar asistencia detallada para una sesión de un estudiante** | Nivel 9: Motor Transaccional de Asistencia (Alta) | `usp_registrar_asistencia` / `uv_asistencias` |
| **HU033** | `Docente` | **HU033 Registrar asistencia de un estudiante a una clase específica** | Nivel 9: Motor Transaccional de Asistencia (Alta) | `usp_registrar_asistencia` / `uv_asistencias` |
| **HU034** | `Sistema` | **HU034 Registrar asistencia detallada para una sesión de un estudiante** | Nivel 9: Motor Transaccional de Asistencia (Alta) | `usp_registrar_asistencia` / `uv_asistencias` |
| **HU001** | `Estudiante` | **HU001 Ver los detalles de las asistencias** | Nivel 9: Motor Transaccional de Asistencia (Alta) | `usp_registrar_asistencia` / `uv_asistencias` |
| **HU002** | `Sistema` | **HU002 Consultar los registros de asistencia** | Nivel 9: Motor Transaccional de Asistencia (Alta) | `usp_registrar_asistencia` / `uv_asistencias` |
| **HU009** | `Estudiante` | **HU009 Consultar los registros de asistencia** | Nivel 9: Motor Transaccional de Asistencia (Alta) | `usp_registrar_asistencia` / `uv_asistencias` |
| **HU013** | `Sistema` | **HU013 Ver los detalles de las asistencias** | Nivel 9: Motor Transaccional de Asistencia (Alta) | `usp_registrar_asistencia` / `uv_asistencias` |
| **HU040** | `Sistema` | **HU040 Consultar los registros de asistencia** | Nivel 9: Motor Transaccional de Asistencia (Alta) | `usp_registrar_asistencia` / `uv_asistencias` |
| **HU041** | `Sistema` | **HU041 Ver los detalles de las asistencias** | Nivel 9: Motor Transaccional de Asistencia (Alta) | `usp_registrar_asistencia` / `uv_asistencias` |
| **HU055** | `Docente` | **HU055 Cambiar los detalles de las asistencias** | Nivel 9: Motor Transaccional de Asistencia (Alta) | `usp_registrar_asistencia` / `uv_asistencias` |
| **HU056** | `Sistema` | **HU056 Borrar detalles de las asistencias** | Nivel 9: Motor Transaccional de Asistencia (Alta) | `usp_registrar_asistencia` / `uv_asistencias` |
| **HU060** | `Coordinador de programa` | **HU060 Consultar los registros de asistencia** | Nivel 9: Motor Transaccional de Asistencia (Alta) | `usp_registrar_asistencia` / `uv_asistencias` |
| **HU061** | `Sistema` | **HU061 Ver los detalles de las asistencias** | Nivel 9: Motor Transaccional de Asistencia (Alta) | `usp_registrar_asistencia` / `uv_asistencias` |
| **HU066** | `Coordinador de programa` | **HU066 Consultar los registros de asistencia** | Nivel 9: Motor Transaccional de Asistencia (Alta) | `usp_registrar_asistencia` / `uv_asistencias` |
| **HU067** | `Sistema` | **HU067 Ver los detalles de las asistencias** | Nivel 9: Motor Transaccional de Asistencia (Alta) | `usp_registrar_asistencia` / `uv_asistencias` |
| **HU102** | `Decano de facultad` | **HU102 Consultar los registros de asistencia** | Nivel 9: Motor Transaccional de Asistencia (Alta) | `usp_registrar_asistencia` / `uv_asistencias` |
| **HU103** | `Sistema` | **HU103 Ver los detalles de las asistencias** | Nivel 9: Motor Transaccional de Asistencia (Alta) | `usp_registrar_asistencia` / `uv_asistencias` |
| **HU133** | `Universidad Católica de Oriente` | **HU133 Consultar los registros de asistencia** | Nivel 9: Motor Transaccional de Asistencia (Alta) | `usp_registrar_asistencia` / `uv_asistencias` |
| **HU134** | `Sistema` | **HU134 Ver los detalles de las asistencias** | Nivel 9: Motor Transaccional de Asistencia (Alta) | `usp_registrar_asistencia` / `uv_asistencias` |
| **HU138** | `Universidad Católica de Oriente` | **HU138 Consultar los registros de asistencia** | Nivel 9: Motor Transaccional de Asistencia (Alta) | `usp_registrar_asistencia` / `uv_asistencias` |
| **HU139** | `Sistema` | **HU139 Ver los detalles de las asistencias** | Nivel 9: Motor Transaccional de Asistencia (Alta) | `usp_registrar_asistencia` / `uv_asistencias` |

### 3.3. Novedades, Justificaciones, Auditoría y Cierre de Periodo (13 HUs)
*Módulo de revisión de faltas con evidencias documentales, aprobación/rechazo docente, bitácora de auditoría y consolidación de faltas.*

| HU ID | Actor | Título y Descripción | Nivel de Complejidad y Secuencia | Objeto BD Asociado |
| :--- | :--- | :--- | :--- | :--- |
| **HU010** | `Sistema` | **HU010 Registrar una nueva solicitud para que se revise una asistencia** | Nivel 10: Novedades, Justificaciones y Cierre (Avanzada) | `usp_aprobar_solicitud` / Triggers / Cierre |
| **HU011** | `Sistema` | **HU011 Adjuntar un archivo a solicitud de revisión** | Nivel 10: Novedades, Justificaciones y Cierre (Avanzada) | `usp_aprobar_solicitud` / Triggers / Cierre |
| **HU012** | `Sistema` | **HU012 Buscar y ver las solicitudes de revisión de asistencia pendientes o resueltas** | Nivel 10: Novedades, Justificaciones y Cierre (Avanzada) | `usp_aprobar_solicitud` / Triggers / Cierre |
| **HU014** | `Estudiante` | **HU014 Registrar una nueva solicitud para que se revise una asistencia** | Nivel 10: Novedades, Justificaciones y Cierre (Avanzada) | `usp_aprobar_solicitud` / Triggers / Cierre |
| **HU015** | `Sistema` | **HU015 Adjuntar un archivo a solicitud de revisión** | Nivel 10: Novedades, Justificaciones y Cierre (Avanzada) | `usp_aprobar_solicitud` / Triggers / Cierre |
| **HU035** | `Docente` | **HU035 Buscar y ver las solicitudes de revisión de asistencia pendientes o resueltas** | Nivel 10: Novedades, Justificaciones y Cierre (Avanzada) | `usp_aprobar_solicitud` / Triggers / Cierre |
| **HU036** | `Sistema` | **HU036 Cambiar el estado o la información de una solicitud de revisión** | Nivel 10: Novedades, Justificaciones y Cierre (Avanzada) | `usp_aprobar_solicitud` / Triggers / Cierre |
| **HU037** | `Sistema` | **HU037 Aprobar una solicitud de revisión de asistencia** | Nivel 10: Novedades, Justificaciones y Cierre (Avanzada) | `usp_aprobar_solicitud` / Triggers / Cierre |
| **HU038** | `Sistema` | **HU038 Avisar al interesado sobre la decisión de su solicitud de revisión** | Nivel 10: Novedades, Justificaciones y Cierre (Avanzada) | `usp_aprobar_solicitud` / Triggers / Cierre |
| **HU039** | `Sistema` | **HU039 Eliminar una solicitud de revisión de asistencia** | Nivel 10: Novedades, Justificaciones y Cierre (Avanzada) | `usp_aprobar_solicitud` / Triggers / Cierre |
| **HU146** | `Sistema` | **HU146 Buscar y ver las solicitudes de revisión de asistencia pendientes o resueltas** | Nivel 10: Novedades, Justificaciones y Cierre (Avanzada) | `usp_aprobar_solicitud` / Triggers / Cierre |
| **HU172** | `Sistema / Auditor` | **HU172 Auditoría y trazabilidad de cambios en asistencias y justificaciones** | Nivel 10: Novedades, Justificaciones y Cierre (Avanzada) | `usp_aprobar_solicitud` / Triggers / Cierre |
| **HU174** | `Sistema` | **HU174 Cierre masivo automático de periodo académico y consolidación de faltas** | Nivel 10: Novedades, Justificaciones y Cierre (Avanzada) | `usp_aprobar_solicitud` / Triggers / Cierre |
