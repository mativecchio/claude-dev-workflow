---
description: "Genera la descripción del MR/PR orientada a revisores técnicos. Sin título al inicio, contexto primero, no repite el diff."
allowed-tools: Read, Bash, Glob, TodoWrite
---

Tu rol es generar una descripción de MR clara y útil para los revisores, basada en el contexto del plan y el diff real.

## Paso 1 — Recopilar contexto

Leer:
- `.claude/workflow/plan.md` → solución técnica y decisiones tomadas
- `.claude/workflow/refinement-summary.md` → objetivo y criterios de aceptación
- `.claude/workflow/review-findings.md` → si hubo ajustes importantes al plan

Obtener el diff resumido:
```bash
git diff main..HEAD --stat
git log --oneline main..HEAD
```

## Paso 2 — Generar la descripción

**Principios:**
- No empezar con el título
- Empezar con el contexto: por qué existe este MR
- No listar archivos modificados (los revisores pueden ver el diff)
- No repetir el diff ni el log de commits
- Agrupar los cambios por comportamiento/flujo, no por archivo
- Mencionar decisiones técnicas no obvias y su razón

**Estructura:**

```markdown
## Contexto
[Por qué existe este cambio. El problema que resuelve o la feature que agrega. 
2-4 líneas máximo.]

## Objetivo
[Qué hace este MR en una oración.]

## Cambios realizados
[Describir la solución agrupando por comportamiento, no por archivo.
Por ejemplo: "El flujo de X ahora hace Y cuando Z" en lugar de "Se modificó archivo.ts".]

### Decisiones técnicas
[Solo si hay algo no obvio: por qué se eligió este approach, trade-offs considerados.]

### Infraestructura (si aplica)
- [ ] Variables de entorno nuevas: `[NOMBRE]`
- [ ] Migraciones: [descripción]
- [ ] Feature flags: [descripción]

## Testing
[Qué se testeó y cómo. Mencionar casos edge cubiertos si son relevantes.]
```

## Paso 3 — Mostrar y ajustar

Mostrar la descripción generada al usuario y preguntar:
**"¿Querés ajustar algo antes de copiarla?"**

Si el usuario pide cambios, aplicarlos hasta que esté conforme.
