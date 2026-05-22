---
description: "Análisis técnico del codebase para planificar la implementación. Corre en contexto aislado via Agent tool. Lee refinement-summary.md como input, genera plan.md como output."
allowed-tools: Read, Glob, Grep, Bash, Agent, TodoWrite
---

Tu rol es preparar el análisis técnico y lanzar un agente especializado para explorarlo en profundidad sin contaminar el contexto principal.

## Paso 1 — Recopilar contexto para el Agent

Leer los siguientes archivos (van a ser parte del prompt del Agent):
- `.claude/workflow/refinement-summary.md` → objetivo y DoD
- `.claude/workflow/config.json` → stack, proyectos relacionados, DoD
- `CLAUDE.md` o `README.md` → resumen del proyecto
- Estructura top-level del proyecto (un `ls` rápido)

Si no existe `refinement-summary.md`, pedirle al usuario una descripción de la tarea antes de continuar.

## Paso 2 — Lanzar el Agent de análisis

Usar el **Agent tool** con el siguiente prompt (interpolando el contexto leído):

---
**PROMPT DEL AGENT:**

Sos un senior engineer haciendo análisis técnico para implementar la siguiente tarea.

**Tarea:** [contenido de refinement-summary.md]

**Stack del proyecto:** [stack del config]
**Directorio de trabajo:** [cwd]
**Resumen del proyecto:** [contenido de CLAUDE.md/README.md]

## Tu proceso de análisis

### 1. Encontrar la "feature hermana"
Buscar en el codebase una implementación similar a lo que hay que hacer. Si encontrás un patrón análogo, usarlo como referencia principal. Mostrar el path encontrado.

### 2. Mapear el impacto por capas
Identificar qué archivos/módulos hay que tocar en cada capa:
- UI / componentes
- Hooks / services / lógica de negocio  
- Estado (Redux / Context / Zustand)
- API / endpoints
- Base de datos / migraciones
- Tests

### 3. Diseñar la solución
Basándote en los patrones existentes del codebase (no inventar convenciones nuevas).

### 4. Identificar riesgos
- Breaking changes en contratos
- Dependencias entre subtareas
- Deuda técnica que hay que registrar pero NO implementar ahora

## Output requerido

Escribir el plan completo en `.claude/workflow/plan.md` con esta estructura:

```markdown
# Plan de Implementación — [nombre de la tarea]

## Feature hermana de referencia
[path y descripción breve]

## Solución técnica
[descripción de la solución, decisiones clave]

## Archivos a modificar/crear
| Archivo | Cambio | Razón |
|---|---|---|

## Contrato de API (si aplica)
[endpoint, método, request/response]

## Infraestructura
- [ ] [env var / migración / feature flag]

## Orden de implementación sugerido
1. [paso 1]
2. [paso 2]

## Riesgos y consideraciones
- [riesgo 1]

## Deuda técnica detectada (no implementar)
- [deuda 1]
```

Cuando termines de escribir el plan, decir: "Plan escrito en .claude/workflow/plan.md"

---

## Paso 3 — Checkpoint antes de cerrar

Leer el `plan.md` generado y hacer un resumen para el usuario.

Antes de dar por terminado el análisis, preguntar:
**"¿El análisis tiene sentido? ¿Hay algo que corregir antes de pasar al review del plan?"**

Esperar respuesta explícita antes de sugerir el siguiente paso.

## Paso 4 — Siguiente paso

Si el usuario confirma, sugerir: "Siguiente: `/wf-review-plan` para verificar el plan contra el codebase real."
