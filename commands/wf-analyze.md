---
description: "Análisis técnico del codebase para planificar la implementación. Corre en contexto aislado via Agent tool. Lee refinement-summary.md como input, genera plan.md como output."
allowed-tools: Read, Glob, Grep, Bash, Agent, TodoWrite
---

Tu rol es preparar el análisis técnico y lanzar un agente especializado para explorarlo en profundidad sin contaminar el contexto principal.

## Paso 0 — Contexto del ticket

```bash
~/.claude/scripts/wf-lib.sh context          # ticket, dir, base, stage, branch
~/.claude/scripts/wf-lib.sh enter-stage analyze
```

`context` crea el directorio del ticket y devuelve `{ticketId}` y `{workflowDir}`. `enter-stage` registra la entrada preservando `branch`, `notes`, `iterations` y `subtasks`, y valida el nombre de la etapa contra el vocabulario único del sistema.

Si `context` falla no hay ticket activo: preguntar "¿Cuál es el número de ticket? (ej. BC-1234)", escribir `{ "activeTicket": "BC-XXXX" }` en `.claude/workflow/state.json` y reintentar.

## Paso 1 — Recopilar contexto para el Agent

Leer los siguientes archivos (van a ser parte del prompt del Agent):
- `{workflowDir}/refinement-summary.md` → objetivo y DoD
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
- Si hay 2+ efectos/observers que leen y escriben el mismo storage/estado compartido, documentar el orden de ejecución esperado y los posibles casos de carrera entre ellos

### 5. Verificar contratos con proyectos relacionados (si aplica)
Si el plan toca un estado, storage, o contrato que también lee/escribe otro proyecto listado en `related_projects` (config.json) — ej. sessionStorage compartido, un campo que otro repo también persiste, un endpoint consumido por otro front — **no asumir el comportamiento**: si ese proyecto tiene un `path` local, usar Grep/Read para inspeccionar su código fuente real (cómo escribe/lee esa estructura: merge o replace, qué tipos, qué formato) antes de diseñar la solución. Tratar el proyecto externo como caja negra solo si su `path` no existe en disco o no es accesible. Registrar en el plan qué se confirmó así (con archivo:línea del repo externo) o qué quedó como riesgo sin verificar.

Antes de asumir un riesgo como "no se puede confirmar, es un repo externo", correr algo como:
```bash
grep -rln "<clave o símbolo relevante>" <path del related_project>
```

### 6. Cruzar con el histórico de sesiones
Leer `~/.claude/workflow/flow-history.json`. **Si el array `entries` está vacío, saltear este paso sin comentario** — es el estado normal hasta que la Fase 4 de `docs/plan-harness-migration.md` empiece a poblarlo, y no significa nada sobre este ticket.

Si hay entries, buscar aquellas cuyo `key_findings`/`anomalies` mencionen los mismos `related_projects` o el mismo tipo de integración que este ticket toca. Si hay coincidencias, citarlas explícitamente en el plan (sección de riesgos) — son bugs ya conocidos en ese punto de integración, no hace falta redescubrirlos.

## Output requerido

Escribir DOS archivos en `{workflowDir}/`:

**`plan.md`** — solo lo que el implementador necesita saber:
```markdown
# Plan de Implementación — [nombre de la tarea]

## Feature hermana de referencia
[path y descripción breve]

## Archivos a modificar/crear
| Archivo | Cambio | Razón |
|---|---|---|

## Contrato de API (si aplica)
[endpoint, método, request/response]

## Contratos con proyectos relacionados (si aplica)
[qué se verificó contra el código fuente real de cada related_project tocado, con archivo:línea — o "sin contratos compartidos" si no aplica]

## Infraestructura
- [ ] [env var / migración / feature flag]

## Orden de implementación sugerido
1. [paso 1]
2. [paso 2]

## Riesgos y dependencias
- [riesgo 1]

## Deuda técnica detectada (no implementar)
- [deuda 1]
```

**`design-decisions.md`** — contexto para el reviewer del MR:
```markdown
# Decisiones de Diseño — [nombre de la tarea]

## [Decisión 1]
**Alternativas consideradas:** [A, B, C]
**Elegida:** [A]
**Por qué:** [razón]

## [Decisión 2]
...
```

Cuando termines, decir: "Plan escrito en {workflowDir}/plan.md y design-decisions.md"

---

## Paso 3 — Checkpoint antes de cerrar

Leer el `plan.md` generado y hacer un resumen para el usuario.

Antes de dar por terminado el análisis, preguntar:
**"¿El análisis tiene sentido? ¿Hay algo que corregir antes de pasar al review del plan?"**

Esperar respuesta explícita antes de sugerir el siguiente paso.

## Paso 3.5 — Registrar la estimación de complejidad

Puntuar el plan con la rúbrica de `docs/brainstorm-metricas-y-complejidad.md` §5.2. **No es trabajo de análisis nuevo:** las siete dimensiones ya se resolvieron en los pasos 1-5 del Agent, esto sólo las formaliza.

| Dimensión | Valores → puntos |
|---|---|
| Feature hermana | encontrada `0` / parcial `3` / ninguna `6` |
| Archivos a tocar | 1-3 `0` / 4-8 `2` / 9-15 `4` / >15 `6` |
| Capas cruzadas | 0-1 `0` / 2-3 `2` / 4-5 `4` / 6 `5` |
| Proyectos externos | 0 `0` / 1 `3` / 2+ `5` |
| Estado compartido / races | no `0` / sí `4` |
| Huecos en el DoD | ninguno `0` / menores `2` / mayores `5` |
| Infra (migración, env var, flag) | no `0` / sí `3` |

Mapeo a puntos: 0-4→`1`, 5-8→`2`, 9-13→`3`, 14-19→`5`, 20-26→`8`, 27+→`13`.

```bash
~/.claude/scripts/wf-event.sh complexity_estimate \
  --raw_score [suma] --points [fibonacci] \
  --split_recommended [true si points >= 8] \
  --dimensions '{"sister_feature":{"value":"none","pts":6},"files":{"value":11,"pts":4},"layers":{"value":4,"pts":4},"external_projects":{"value":1,"pts":3},"shared_state":{"value":true,"pts":4},"dod_gaps":{"value":"none","pts":0},"infra":{"value":false,"pts":0}}'
```

Guardar lo mismo en `{workflowDir}/complexity.json` para que `/wf-retro` cierre el par (estimado, real) sin releer el JSONL.

Mostrar el puntaje al usuario. **Si da ≥ 8, decirlo**: es el umbral donde el ticket es candidato a partirse. No partir automáticamente — sólo señalarlo.

> Los umbrales son provisionales y se eligieron sin datos (§5.4). Hoy su único propósito es generar el lado "estimado" del par, para calibrarlos a los 15-20 tickets. No tratarlos como verdad.

## Paso 4 — Siguiente paso

Si el usuario confirma, sugerir: "Siguiente: `/wf-review-plan` para verificar el plan contra el codebase real."
