---
description: "Genera la descripción del MR/PR orientada a revisores técnicos. Sin título al inicio, contexto primero, no repite el diff."
allowed-tools: Read, Bash, Glob, TodoWrite
---

Tu rol es generar una descripción de MR clara y útil para los revisores, basada en el contexto del plan y el diff real.

## Paso 0 — Identificar ticket activo

Leer `.claude/workflow/state.json` → campo `activeTicket`.
Si no existe o falta → preguntar: "¿Cuál es el número de ticket? (ej. BC-1234)"

`{ticketId}` = `activeTicket`
`{workflowDir}` = `.claude/workflow/{ticketId}`

**Registrar la entrada a la etapa:** escribir `"stage": "mr-desc"` en `{workflowDir}/state.json` y appendear `"mr-desc"` a `completed` si no estaba, preservando los demás campos.

## Paso 1 — Recopilar contexto

Leer:
- `{workflowDir}/plan.md` → solución técnica y decisiones tomadas
- `{workflowDir}/refinement-summary.md` → objetivo y criterios de aceptación
- `{workflowDir}/review-findings.md` → si hubo ajustes importantes al plan

Obtener el diff resumido (contra el merge-base con la base, no la base directo — `main..HEAD` se rompe si la base avanzó por fast-forward después de crear el branch):
```bash
BASE=develop  # o main/master, según el proyecto
MB=$(git merge-base HEAD "$BASE")
git diff "$MB"..HEAD --stat
git log --oneline "$MB"..HEAD
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

Mostrar la descripción generada al usuario. En vez de una pregunta abierta, ofrecer directamente las dos salidas y mostrar ya mismo cuáles son los pasos siguientes:

```
¿Ajustamos algo o seguimos?
a) Ajustar algo en la descripción
b) Está lista — siguiente: `/wf-mr-review` para la revisión final del MR
```

Si el usuario pide cambios (a), aplicarlos hasta que esté conforme y volver a ofrecer las mismas dos opciones. Si elige seguir (b), no repreguntar — pasar directo a sugerir `/wf-mr-review`.
