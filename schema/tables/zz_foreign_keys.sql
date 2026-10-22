USE [gestionasistenciadb];
GO

-- 1. Usuario -> TipoIdentificacion
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Usuario_TipoIdentificacion')
BEGIN
    ALTER TABLE [dbo].[Usuario] ADD CONSTRAINT [FK_Usuario_TipoIdentificacion] 
    FOREIGN KEY ([tipoIdIdentificacion]) REFERENCES [dbo].[TipoIdentificacion] ([id]);
END
GO

-- 2. Administrador -> Usuario
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Administrador_Usuario')
BEGIN
    ALTER TABLE [dbo].[Administrador] ADD CONSTRAINT [FK_Administrador_Usuario] 
    FOREIGN KEY ([usuario]) REFERENCES [dbo].[Usuario] ([id]);
END
GO

-- 3. Administrador -> Institucion
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Administrador_Institucion')
BEGIN
    ALTER TABLE [dbo].[Administrador] ADD CONSTRAINT [FK_Administrador_Institucion] 
    FOREIGN KEY ([institucion]) REFERENCES [dbo].[Institucion] ([id]);
END
GO

-- 4. Facultad -> Institucion
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Facultad_Institucion')
BEGIN
    ALTER TABLE [dbo].[Facultad] ADD CONSTRAINT [FK_Facultad_Institucion] 
    FOREIGN KEY ([institucion]) REFERENCES [dbo].[Institucion] ([id]);
END
GO

-- 5. Facultad -> Decano
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Facultad_Decano')
BEGIN
    ALTER TABLE [dbo].[Facultad] ADD CONSTRAINT [FK_Facultad_Decano] 
    FOREIGN KEY ([decano]) REFERENCES [dbo].[Decano] ([id]);
END
GO

-- 6. Decano -> Usuario
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Decano_Usuario')
BEGIN
    ALTER TABLE [dbo].[Decano] ADD CONSTRAINT [FK_Decano_Usuario] 
    FOREIGN KEY ([usuario]) REFERENCES [dbo].[Usuario] ([id]);
END
GO

-- 7. Coordinador -> Usuario
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Coordinador_Usuario')
BEGIN
    ALTER TABLE [dbo].[Coordinador] ADD CONSTRAINT [FK_Coordinador_Usuario] 
    FOREIGN KEY ([usuario]) REFERENCES [dbo].[Usuario] ([id]);
END
GO

-- 8. Docente -> Usuario
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Docente_Usuario')
BEGIN
    ALTER TABLE [dbo].[Docente] ADD CONSTRAINT [FK_Docente_Usuario] 
    FOREIGN KEY ([usuario]) REFERENCES [dbo].[Usuario] ([id]);
END
GO

-- 9. Estudiante -> Usuario
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Estudiante_Usuario')
BEGIN
    ALTER TABLE [dbo].[Estudiante] ADD CONSTRAINT [FK_Estudiante_Usuario] 
    FOREIGN KEY ([usuario]) REFERENCES [dbo].[Usuario] ([id]);
END
GO

-- 10. Programa -> Facultad
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Programa_Facultad')
BEGIN
    ALTER TABLE [dbo].[Programa] ADD CONSTRAINT [FK_Programa_Facultad] 
    FOREIGN KEY ([facultad]) REFERENCES [dbo].[Facultad] ([id]);
END
GO

-- 11. Programa -> TipoPrograma
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Programa_TipoPrograma')
BEGIN
    ALTER TABLE [dbo].[Programa] ADD CONSTRAINT [FK_Programa_TipoPrograma] 
    FOREIGN KEY ([tipoDePrograma]) REFERENCES [dbo].[TipoPrograma] ([id]);
END
GO

-- 12. Programa -> Coordinador
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Programa_Coordinador')
BEGIN
    ALTER TABLE [dbo].[Programa] ADD CONSTRAINT [FK_Programa_Coordinador] 
    FOREIGN KEY ([coordinador]) REFERENCES [dbo].[Coordinador] ([id]);
END
GO

-- 13. PlanEstudio -> Programa
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_PlanEstudio_Programa')
BEGIN
    ALTER TABLE [dbo].[PlanEstudio] ADD CONSTRAINT [FK_PlanEstudio_Programa] 
    FOREIGN KEY ([programa]) REFERENCES [dbo].[Programa] ([id]);
END
GO

-- 14. SemestrePlanEstudio -> PlanEstudio
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_SemestrePlanEstudio_PlanEstudio')
BEGIN
    ALTER TABLE [dbo].[SemestrePlanEstudio] ADD CONSTRAINT [FK_SemestrePlanEstudio_PlanEstudio] 
    FOREIGN KEY ([planEstudio]) REFERENCES [dbo].[PlanEstudio] ([id]);
END
GO

-- 15. SemestrePlanEstudio -> Semestre
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_SemestrePlanEstudio_Semestre')
BEGIN
    ALTER TABLE [dbo].[SemestrePlanEstudio] ADD CONSTRAINT [FK_SemestrePlanEstudio_Semestre] 
    FOREIGN KEY ([semestre]) REFERENCES [dbo].[Semestre] ([id]);
END
GO

-- 16. Asignatura -> Area
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Asignatura_Area')
BEGIN
    ALTER TABLE [dbo].[Asignatura] ADD CONSTRAINT [FK_Asignatura_Area] 
    FOREIGN KEY ([area]) REFERENCES [dbo].[Area] ([id]);
END
GO

-- 17. Asignatura -> Componente
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Asignatura_Componente')
BEGIN
    ALTER TABLE [dbo].[Asignatura] ADD CONSTRAINT [FK_Asignatura_Componente] 
    FOREIGN KEY ([componente]) REFERENCES [dbo].[Componente] ([id]);
END
GO

-- 18. Asignatura -> SemestrePlanEstudio
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Asignatura_SemestrePlanEstudio')
BEGIN
    ALTER TABLE [dbo].[Asignatura] ADD CONSTRAINT [FK_Asignatura_SemestrePlanEstudio] 
    FOREIGN KEY ([semestrePlanEstudio]) REFERENCES [dbo].[SemestrePlanEstudio] ([id]);
END
GO

-- 19. Grupo -> Asignatura
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Grupo_Asignatura')
BEGIN
    ALTER TABLE [dbo].[Grupo] ADD CONSTRAINT [FK_Grupo_Asignatura] 
    FOREIGN KEY ([asignatura]) REFERENCES [dbo].[Asignatura] ([id]);
END
GO

-- 20. Grupo -> PeriodoAcademico
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Grupo_PeriodoAcademico')
BEGIN
    ALTER TABLE [dbo].[Grupo] ADD CONSTRAINT [FK_Grupo_PeriodoAcademico] 
    FOREIGN KEY ([periodoAcademico]) REFERENCES [dbo].[PeriodoAcademico] ([id]);
END
GO

-- 21. Grupo -> Docente
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Grupo_Docente')
BEGIN
    ALTER TABLE [dbo].[Grupo] ADD CONSTRAINT [FK_Grupo_Docente] 
    FOREIGN KEY ([docente]) REFERENCES [dbo].[Docente] ([id]);
END
GO

-- 22. EstudianteGrupo -> EstadoEstudianteGrupo
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_EstudianteGrupo_EstadoEstudianteGrupo')
BEGIN
    ALTER TABLE [dbo].[EstudianteGrupo] ADD CONSTRAINT [FK_EstudianteGrupo_EstadoEstudianteGrupo] 
    FOREIGN KEY ([estado]) REFERENCES [dbo].[EstadoEstudianteGrupo] ([id]);
END
GO

-- 23. EstudianteGrupo -> Estudiante
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_EstudianteGrupo_Estudiante')
BEGIN
    ALTER TABLE [dbo].[EstudianteGrupo] ADD CONSTRAINT [FK_EstudianteGrupo_Estudiante] 
    FOREIGN KEY ([estudiante]) REFERENCES [dbo].[Estudiante] ([id]);
END
GO

-- 24. EstudianteGrupo -> Grupo
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_EstudianteGrupo_Grupo')
BEGIN
    ALTER TABLE [dbo].[EstudianteGrupo] ADD CONSTRAINT [FK_EstudianteGrupo_Grupo] 
    FOREIGN KEY ([grupo]) REFERENCES [dbo].[Grupo] ([id]);
END
GO

-- 25. EstudiantePrograma -> Estudiante
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_EstudiantePrograma_Estudiante')
BEGIN
    ALTER TABLE [dbo].[EstudiantePrograma] ADD CONSTRAINT [FK_EstudiantePrograma_Estudiante] 
    FOREIGN KEY ([estudiante]) REFERENCES [dbo].[Estudiante] ([id]);
END
GO

-- 26. EstudiantePrograma -> Programa
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_EstudiantePrograma_Programa')
BEGIN
    ALTER TABLE [dbo].[EstudiantePrograma] ADD CONSTRAINT [FK_EstudiantePrograma_Programa] 
    FOREIGN KEY ([programa]) REFERENCES [dbo].[Programa] ([id]);
END
GO

-- 27. Horario -> Grupo
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Horario_Grupo')
BEGIN
    ALTER TABLE [dbo].[Horario] ADD CONSTRAINT [FK_Horario_Grupo] 
    FOREIGN KEY ([grupo]) REFERENCES [dbo].[Grupo] ([id]);
END
GO

-- 28. Horario -> Dia
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Horario_Dia')
BEGIN
    ALTER TABLE [dbo].[Horario] ADD CONSTRAINT [FK_Horario_Dia] 
    FOREIGN KEY ([dia]) REFERENCES [dbo].[Dia] ([id]);
END
GO

-- 29. Sesion -> Grupo
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Sesion_Grupo')
BEGIN
    ALTER TABLE [dbo].[Sesion] ADD CONSTRAINT [FK_Sesion_Grupo] 
    FOREIGN KEY ([grupo]) REFERENCES [dbo].[Grupo] ([id]);
END
GO

-- 30. Asistencia -> EstudianteGrupo
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Asistencia_EstudianteGrupo')
BEGIN
    ALTER TABLE [dbo].[Asistencia] ADD CONSTRAINT [FK_Asistencia_EstudianteGrupo] 
    FOREIGN KEY ([estudianteGrupo]) REFERENCES [dbo].[EstudianteGrupo] ([id]);
END
GO

-- 31. Asistencia -> Sesion
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Asistencia_Sesion')
BEGIN
    ALTER TABLE [dbo].[Asistencia] ADD CONSTRAINT [FK_Asistencia_Sesion] 
    FOREIGN KEY ([sesion]) REFERENCES [dbo].[Sesion] ([id]);
END
GO

-- 32. DetalleAsistencia -> Asistencia
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_DetalleAsistencia_Asistencia')
BEGIN
    ALTER TABLE [dbo].[DetalleAsistencia] ADD CONSTRAINT [FK_DetalleAsistencia_Asistencia] 
    FOREIGN KEY ([asistencia]) REFERENCES [dbo].[Asistencia] ([id]);
END
GO

-- 33. DetalleAsistencia -> RazonCausa
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_DetalleAsistencia_RazonCausa')
BEGIN
    ALTER TABLE [dbo].[DetalleAsistencia] ADD CONSTRAINT [FK_DetalleAsistencia_RazonCausa] 
    FOREIGN KEY ([razonCausa]) REFERENCES [dbo].[RazonCausa] ([id]);
END
GO

-- 34. SolicitudRevisionAsistencia -> Asistencia
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_SolicitudRevisionAsistencia_Asistencia')
BEGIN
    ALTER TABLE [dbo].[SolicitudRevisionAsistencia] ADD CONSTRAINT [FK_SolicitudRevisionAsistencia_Asistencia] 
    FOREIGN KEY ([asistencia]) REFERENCES [dbo].[Asistencia] ([id]);
END
GO

-- 35. SolicitudRevisionAsistencia -> Estado
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_SolicitudRevisionAsistencia_Estado')
BEGIN
    ALTER TABLE [dbo].[SolicitudRevisionAsistencia] ADD CONSTRAINT [FK_SolicitudRevisionAsistencia_Estado] 
    FOREIGN KEY ([estado]) REFERENCES [dbo].[Estado] ([id]);
END
GO

-- 36. ArchivoSoporte -> Usuario (LB-004D)
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_ArchivoSoporte_Usuario')
BEGIN
    ALTER TABLE [dbo].[ArchivoSoporte] ADD CONSTRAINT [FK_ArchivoSoporte_Usuario] 
    FOREIGN KEY ([usuarioPropietario]) REFERENCES [dbo].[Usuario] ([id]);
END
GO

-- 37. ArchivoSoporte -> SolicitudRevisionAsistencia (LB-004D, sin ON DELETE CASCADE)
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_ArchivoSoporte_SolicitudRevisionAsistencia')
BEGIN
    ALTER TABLE [dbo].[ArchivoSoporte] ADD CONSTRAINT [FK_ArchivoSoporte_SolicitudRevisionAsistencia] 
    FOREIGN KEY ([solicitudRevisionAsistencia]) REFERENCES [dbo].[SolicitudRevisionAsistencia] ([id]);
END
GO

-- HU077: Programa -> Modalidad / Jornada
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Programa_Modalidad')
BEGIN
    ALTER TABLE [dbo].[Programa] ADD CONSTRAINT [FK_Programa_Modalidad]
    FOREIGN KEY ([modalidad]) REFERENCES [dbo].[Modalidad] ([id]);
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Programa_Jornada')
BEGIN
    ALTER TABLE [dbo].[Programa] ADD CONSTRAINT [FK_Programa_Jornada]
    FOREIGN KEY ([jornada]) REFERENCES [dbo].[Jornada] ([id]);
END
GO
