---
description: "Retrospectiva del ciclo de desarrollo completado. Analiza la sesión, extrae aprendizajes y propone mejoras al workflow. Guarda en flow-history.json."
allowed-tools: Read, Write, Edit, Bash, Glob, TodoRead
---

Tu rol es analizar cómo fue el ciclo de desarrollo, extraer aprendizajes y proponer mejoras concretas al sistema de workflow.

## Paso 0 — Contexto del ticket

```bash
~/.claude/scripts/wf-lib.sh context
~/.claude/scripts/wf-lib.sh enter-stage retro
```

Si `context` falla, preguntar el ticket y escribir `.claude/workflow/state.json` antes de reintentar.

## Paso 1 — Recopilar datos de la sesión

Leer:
- `{workflowDir}/state.json` → etapas recorridas
- `{workflowDir}/plan.md` → qué se implementó y desvíos registrados
- `{workflowDir}/review-findings.md` → hallazgos del plan review
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

1. **Resolver el repo fuente.** Leer `repo_path` de `~/.claude/workflow/config.json`.
   - Si existe y el directorio está presente → `{repoPath}` es el target de edición.
   - Si no → avisar: "No hay `repo_path` en el config global. Correr `install.sh` del repo para configurarlo." y editar `~/.claude/commands/` solo como fallback, dejando constancia de que el cambio se va a perder en la próxima instalación.
2. Identificar el archivo en **`{repoPath}/commands/wf-*.md`** — nunca en `~/.claude/commands/`, que es un destino de instalación, no la fuente.
3. Mostrar el cambio propuesto antes de aplicarlo.
4. Pedir confirmación final.
5. Aplicar con Edit tool sobre el archivo del repo.
6. **Asentar la evidencia** en `~/.claude/workflow/improvements.md` (formato en el encabezado del archivo). Regla §0 del brainstorm: si no se puede escribir la evidencia —`archivo:línea` o la consulta concreta sobre `events.jsonl`— el cambio no se aplica.
7. **Reinstalar** para que el cambio tome efecto:
   ```bash
   "{repoPath}/install.sh"
   ```
8. Verificar que quedó sincronizado:
   ```bash
   "{repoPath}/install.sh" --check
   ```

Recordar al usuario que el cambio quedó en el working tree del repo, sin commitear.
