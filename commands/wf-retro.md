---
description: "Retrospectiva del ciclo de desarrollo completado. Analiza la sesión, extrae aprendizajes y propone mejoras al workflow. Guarda en flow-history.json."
allowed-tools: Read, Write, Edit, Bash, Glob, TodoRead
---

Tu rol es analizar cómo fue el ciclo de desarrollo, extraer aprendizajes y proponer mejoras concretas al sistema de workflow.

## Paso 1 — Recopilar datos de la sesión

Leer:
- `.claude/workflow/state.json` → etapas recorridas
- `.claude/workflow/plan.md` → qué se implementó y desvíos registrados
- `.claude/workflow/review-findings.md` → hallazgos del plan review
- `~/.claude/workflow/flow-history.json` → histórico de sesiones anteriores (si existe)

## Paso 2 — Análisis de la sesión

Evaluar:
- **Etapas completadas** y cuántas iteraciones requirió cada una
- **Retrabajo detectado**: etapas que se repitieron, correcciones mid-etapa
- **Fricción**: momentos donde el flujo se interrumpió o fue poco claro
- **Desvíos del plan**: qué cambió respecto al plan original y por qué
- **Deuda técnica registrada**: qué quedó pendiente

Si hay 3+ entries en `flow-history.json`, cruzar con el histórico:
- ¿Qué etapas siempre requieren múltiples iteraciones?
- ¿Hay anomalías recurrentes?
- ¿Hay hallazgos que se repiten en distintos tickets?

## Paso 3 — Informe de retrospectiva

Mostrar al usuario:

```
## Retrospectiva — [ticket/tarea]

### Resumen de la sesión
- Etapas recorridas: [lista]
- Retrabajo: [descripción o "ninguno"]
- Fricción detectada: [descripción o "ninguna"]

### Aprendizajes
1. [aprendizaje 1]
2. [aprendizaje 2]

### Patrones del histórico (si aplica)
- [patrón recurrente detectado]

### Mejoras propuestas al workflow
| Componente | Problema | Cambio propuesto |
|---|---|---|
| [wf-analyze] | [descripción] | [cambio concreto] |
```

## Paso 4 — Guardar en flow-history

Preguntar al usuario si quiere guardar esta sesión en el histórico.

Si acepta, agregar entry a `~/.claude/workflow/flow-history.json`:
```json
{
  "date": "[fecha ISO]",
  "project": "[nombre del proyecto]",
  "ticket": "[ID o descripción]",
  "stages_completed": ["[lista]"],
  "iterations": {"[etapa]": "[N]"},
  "key_findings": ["[hasta 3 hallazgos]"],
  "anomalies": ["[desvíos o fricción detectada]"]
}
```

## Paso 5 — Aplicar mejoras (con aprobación)

Si hay mejoras propuestas al workflow, preguntar:
**"¿Querés que aplique alguna de estas mejoras a los comandos del sistema?"**

Si el usuario acepta una mejora:
1. Identificar el archivo en `~/.claude/commands/wf-*.md` que corresponde
2. Mostrar el cambio propuesto antes de aplicarlo
3. Pedir confirmación final
4. Aplicar con Edit tool

Recordar al usuario que para persistir los cambios en el repo fuente: editar el archivo correspondiente en la carpeta de `claude-workflow` y hacer commit.
