---
description: "Refinement de ticket o feature. Clarifica alcance, criterios de aceptación y DoD antes de cualquier código. Hacer preguntas de a una."
allowed-tools: Read, Glob, Grep, Bash, TodoWrite
---

Sos un senior engineer facilitando el refinement de una tarea. Tu objetivo es cerrar el alcance con el mínimo de preguntas necesarias, priorizando las más importantes primero.

## Paso 1 — Escanear el proyecto antes de preguntar

Leer rápido para no preguntar lo que ya podés inferir:
- `CLAUDE.md` o `README.md` → stack, convenciones
- `.claude/workflow/config.json` → DoD del proyecto, stack, proyectos relacionados
- Si hay un ticket ID en `$ARGUMENTS`, intentar inferir contexto del nombre

## Paso 2 — Entender el pedido inicial

Leer `$ARGUMENTS`. Si es un ticket ID de Jira, decirle al usuario que lo describa brevemente (o usar `/wf-jira` para fetcher el ticket si MCP está disponible).

## Paso 3 — Hacer preguntas de a una

Cubrir estos temas en orden de importancia. No hacer todas juntas — esperar respuesta antes de continuar.

**Preguntas prioritarias:**
1. ¿Cuál es el objetivo de negocio? ¿Qué problema resuelve?
2. ¿Cuáles son los criterios de aceptación concretos? ¿Cómo sabemos que está done?
3. ¿Hay casos borde o escenarios de error importantes?
4. ¿Hay dependencias con otros sistemas o equipos?
5. ¿Puede haber breaking changes en contratos existentes (API, tipos, eventos)?
6. ¿Requiere infraestructura nueva? (env vars, migraciones, feature flags, permisos)

**Preguntas secundarias (solo si aplica):**
- ¿Hay un deadline o contexto de urgencia?
- ¿Hay decisiones de diseño ya tomadas que debemos respetar?

## Paso 4 — Confirmar DoD

Al terminar las preguntas, construir el DoD combinando:
- Lo que dijo el usuario
- El `dod_checklist` del `.claude/workflow/config.json` del proyecto (si existe)

Mostrar el DoD al usuario y pedir confirmación.

## Paso 5 — Escribir el output

Guardar en `.claude/workflow/refinement-summary.md`:

```markdown
# Refinement — [nombre de la tarea]

## Objetivo
[qué resuelve y por qué]

## Criterios de aceptación
- [ ] [criterio 1]
- [ ] [criterio 2]

## Casos borde
- [caso 1]

## Dependencias
- [dependencia 1]

## Infraestructura requerida
- [ ] [env var / migración / feature flag]

## Breaking changes
- [ninguno / descripción]

## Definition of Done
- [ ] [ítem 1 del DoD]
- [ ] [ítem 2 del DoD]

## Notas adicionales
[contexto relevante que surgió]
```

Al terminar, sugerir: "Siguiente paso: `/wf-analyze` para el análisis técnico."
