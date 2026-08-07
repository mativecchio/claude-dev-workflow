# Sistema de medición, complejidad y partición de tareas

> Documento de diseño surgido de brainstorm. Define **qué medir**, **cómo capturarlo sin depender de la memoria del modelo**, **cómo estimar complejidad** y **cómo partir tareas grandes**.
> Estado: diseño acordado, pendiente de implementación.

---

## 0. Regla de fundamentación

**Ningún cambio se propone ni se aplica sin evidencia explícita.** Aplica a cambios en el código de un proyecto y a cambios en el propio workflow.

Toda sugerencia debe citar una de estas dos fuentes:

| Fuente | Forma aceptable de la cita |
|---|---|
| **Tarea en curso** | `archivo:línea` del codebase, sección concreta de `plan.md`, hallazgo de `review-findings.md`, o salida de un comando (test, grep, diff) |
| **Mediciones** | consulta concreta sobre `events.jsonl` — categoría de evento, cantidad de tickets involucrados, período |

Formulaciones prohibidas por sí solas: "sería mejor", "es buena práctica", "conviene", "suele pasar". Son admisibles **después** de la evidencia, nunca en su lugar.

Umbral mínimo para proponer un cambio al workflow a partir de datos: **3 tickets distintos** con el mismo patrón. Por debajo de eso es anécdota y se registra como observación, no como propuesta.

Cada cambio aplicado al workflow se asienta en `improvements.md` con su evidencia. Si no se puede escribir la evidencia, el cambio no se aplica.

---

## 1. Objetivo

Reducir la **cantidad de iteraciones necesarias para cerrar una tarea**.

Caso motivador: un ticket que requirió 7-8 vueltas hasta que analyze, implement, test y validate cerraron sin fallos. La hipótesis a validar con datos es que no fueron 8 defectos independientes, sino 1-2 defectos con **fuga larga** (originados temprano, detectados tarde) más su retrabajo en cascada.

Principio operativo: **instrumentar primero, diagnosticar después.** No se cambia el flujo por intuición. Se acumula evidencia y recién ahí se propone.

---

## 2. Métricas

### 2.1 Métrica principal

**Iteraciones hasta cierre**, desagregadas por ticket y por comando.

Una *iteración* es una **reentrada** a una etapa ya recorrida. Se cuentan por separado:
- `iterations.total` — reentradas de todas las etapas
- `iterations.by_stage` — `{"analyze": 2, "implement": 3, "validate": 3}`

### 2.2 Distancia de fuga

Cruda, la cuenta de iteraciones mezcla dos fenómenos opuestos:

- **Iteración barata** — una etapa detecta un defecto originado en esa misma etapa. El sistema funcionando.
- **Iteración cara** — el defecto se originó en `refine` y lo detectó `/wf-test`. Cuatro etapas construyeron sobre una premisa rota.

Orden de etapas para el cálculo:

| Etapa | Índice |
|---|---|
| refine | 1 |
| analyze | 2 |
| review-plan | 3 |
| implement | 4 |
| validate | 5 |
| test | 6 |
| mr-review | 7 |

`leak_distance = idx(stage_detected) - idx(stage_origin)`

Es directamente accionable: fuga alta desde `refine` → el problema es el DoD, no el modelo implementando. Fuga alta desde `analyze` → el análisis no está mapeando impacto. Son arreglos en archivos distintos.

### 2.3 Catálogo completo

Ordenado por relación valor/esfuerzo. Las marcadas **derivada** no dependen de que el modelo reporte con honestidad — se calculan de archivos y git.

| # | Métrica | Origen | Qué detecta |
|---|---|---|---|
| 1 | **Scope drift** *(derivada)* | `git diff --name-only` vs tabla de `plan.md` | "se hizo un cambio que no se pidió" |
| 2 | **Plan churn** *(derivada)* | ediciones a `plan.md` posteriores a la aprobación en `/wf-review-plan` | analyze no vio algo |
| 3 | **Detector: gate vs usuario** | campo `detected_by` en cada finding | salud de los gates — si sube la porción del usuario, los gates se degradan |
| 4 | **Error de calibración con signo** | `complexity_estimate` vs iteraciones reales | sesgo sistemático de subestimación (se corrige con constante, no rediseñando la rúbrica) |
| 5 | **Reincidencia por categoría** | `category` de findings entre tickets | problema sistémico → input fundamentado para `/wf-improve` |
| 6 | **Tickets abandonados** *(derivada)* | ticket sin eventos por N días y sin `mr_opened` | hoy invisibles; probablemente los peores casos |
| 7 | **Costo por etapa** *(derivada)* | turnos + tool calls por etapa | qué paso realmente cuesta |
| 8 | **Peso del MR** *(derivada)* | ver §6 | tamaño real de revisión |

### 2.4 Sobre medir tiempo

**El reloj miente en sesiones interactivas.** Si `/wf-analyze` marca 4 horas, lo más probable es que la laptop haya estado cerrada.

Se registra `ts` en todos los eventos —es gratis y sirve para ordenar—, pero la métrica de *costo de etapa* es **turnos + tool calls + reentradas**, nunca minutos. Los minutos se guardan como dato secundario y se interpretan sólo en agregado, descartando outliers.

---

## 3. Captura de datos

### 3.1 Por qué dos capas

Precedente: `flow-history.json` está en `{"entries": []}`. El mecanismo existente (Paso 4 de `/wf-retro`, opt-in y manual al final del ciclo) **nunca se ejecutó ni una vez**. Repetir ese patrón produce otro archivo vacío.

| Capa | Captura | Fortaleza | Límite |
|---|---|---|---|
| **Hooks** | esqueleto mecánico: qué comando arrancó, cuándo, turnos, tool calls, reentradas | determinística, no se saltea, no miente sobre conteos | no entiende semántica |
| **Comandos `wf-*`** | campos semánticos: por qué se reentró, qué defecto fue, dónde se originó | es la información que importa | es una instrucción en un prompt; el modelo la puede saltear |

**La razón real de usar ambas:** es la única combinación que permite **detectar que el log está incompleto**. Si el hook registra una reentrada a `analyze` y no hay evento semántico que la explique, eso mismo es un dato — sabés que perdiste la causa. Con sólo la capa semántica nunca sabés si un ciclo limpio fue limpio de verdad o el modelo simplemente no logueó.

### 3.2 Hooks

| Hook | Función |
|---|---|
| `UserPromptSubmit` | detecta `/wf-*` en el prompt → emite `stage_start`; si la etapa ya figuraba recorrida en el state del ticket → emite `stage_reentry` |
| `Stop` | cierra el turno → incrementa `turns` de la etapa activa |
| `PostToolUse` (Write/Edit) | si el path es `plan.md` y el state del ticket está en `review-plan` o posterior → emite `plan_edit` (alimenta plan churn) |
| `PostToolUse` (cualquiera) | incrementa `tool_calls` de la etapa activa |

Los hooks appendean directo a `~/.claude/workflow/events.jsonl`. No leen ni bloquean nada del flujo.

### 3.3 Comandos

Cada comando `wf-*` appendea sus eventos semánticos en su último paso:

| Comando | Evento(s) |
|---|---|
| `wf-analyze` | `complexity_estimate` (§5), `split_suggested` si corresponde |
| `wf-review-plan` | `finding` × N (con `stage_origin`, `detected_by`) |
| `wf-implement` | `size_check` en cada checkpoint, `size_exceeded` si dispara |
| `wf-validate` | `finding` × N, `finding_decision` (implement/ignore/tech-debt) |
| `wf-test` | `finding` × N |
| `wf-mr-review` | `finding` × N, `mr_opened` con peso |
| `wf-retro` | `ticket_closed` con iteraciones reales |

---

## 4. Esquema de `events.jsonl`

Append-only. Una línea = un evento. JSONL para poder appendear desde un hook de shell sin parsear el archivo entero.

```json
{"ts":"2026-08-07T15:32:10Z","project":"bc-app","ticket":"BC-1234","subtask":null,"stage":"analyze","event":"stage_start","source":"hook","data":{}}
```

### Campos comunes

| Campo | Tipo | Notas |
|---|---|---|
| `ts` | ISO 8601 UTC | |
| `project` | string | nombre del directorio del proyecto |
| `ticket` | string | ej. `BC-1234` |
| `subtask` | string \| null | ej. `sub-1` |
| `stage` | string | `refine`\|`analyze`\|`review-plan`\|`implement`\|`validate`\|`test`\|`mr-review`\|`retro` |
| `event` | string | ver tabla siguiente |
| `source` | `hook` \| `command` | permite auditar cobertura del log |
| `data` | object | payload específico del evento |

### Tipos de evento

| `event` | `data` |
|---|---|
| `stage_start` | `{}` |
| `stage_end` | `{turns, tool_calls, duration_s}` |
| `stage_reentry` | `{iteration_n, scope, reason?}` — `scope` es `ticket` (contador persistido en el `state.json` del ticket) o `session` (fallback, se pierde al cerrar la sesión) |
| `complexity_estimate` | ver §5 |
| `finding` | `{category, severity, stage_origin, stage_detected, detected_by, summary}` |
| `finding_decision` | `{finding_ref, decision}` — `implement`\|`ignore`\|`tech-debt` |
| `plan_edit` | `{lines_changed, post_approval: true}` |
| `scope_drift` | `{planned_files[], actual_files[], unplanned[], missing[]}` |
| `size_check` | `{weight_prod, weight_tests, threshold}` |
| `size_exceeded` | `{weight_prod, threshold, action}` — `carve`\|`continue` |
| `split_suggested` | `{reason, proposed_subtasks[]}` |
| `split_applied` | `{subtasks[]}` |
| `mr_opened` | `{branch, target, weight_prod, weight_tests}` |
| `ticket_closed` | `{iterations_total, iterations_by_stage, complexity_actual}` |
| `ticket_abandoned` | `{last_stage, days_idle}` |

`detected_by` es `gate` (lo encontró un comando del workflow) o `user` (lo encontraste vos). Es el input de la métrica 3.

---

## 5. Rúbrica de complejidad

### 5.1 Por qué rúbrica y no intuición

Pedirle al modelo "estimá complejidad del 1 al 13" produce 5 casi siempre. El puntaje sale de dimensiones que **`/wf-analyze` ya calcula** en sus pasos 1-5. No agrega trabajo de análisis: sólo formaliza lo que ya se produjo.

### 5.2 Dimensiones y pesos

| Dimensión | De dónde sale | Valores → puntos |
|---|---|---|
| **¿Hay feature hermana?** | paso 1 | encontrada `0` / parcial `3` / **ninguna `6`** |
| Archivos a tocar | tabla de `plan.md` | 1-3 `0` / 4-8 `2` / 9-15 `4` / >15 `6` |
| Capas cruzadas (0-6) | paso 2 | 0-1 `0` / 2-3 `2` / 4-5 `4` / 6 `5` |
| Proyectos externos tocados | paso 5 | 0 `0` / 1 `3` / 2+ `5` |
| Estado compartido / races | paso 4 | no `0` / sí `4` |
| Huecos en el DoD | `refinement-summary.md` | ninguno `0` / menores `2` / mayores `5` |
| Infra (migración, env var, feature flag) | sección Infraestructura | no `0` / sí `3` |

**Rango: 0-34.**

### 5.3 La apuesta sobre "feature hermana"

Esta dimensión lleva peso desproporcionado a propósito. Hipótesis explícita, a validar con datos:

> Cuando `/wf-analyze` no encuentra un patrón análogo en el codebase, el modelo no tiene qué copiar y empieza a inventar convenciones. Ahí es donde aparecen los "cambios que no se pidieron" y las cadenas largas de iteraciones.

Si a los 15-20 tickets la correlación entre `sister_feature: none` e iteraciones no aparece, **el peso se baja y se registra en `improvements.md` con la evidencia**. La rúbrica es una hipótesis, no un dogma.

### 5.4 Mapeo a puntos Fibonacci

| Puntaje crudo | Puntos |
|---|---|
| 0-4 | 1 |
| 5-8 | 2 |
| 9-13 | 3 |
| 14-19 | 5 |
| 20-26 | 8 |
| 27+ | 13 |

**Umbral de partición: ≥ 8 puntos → sugerir dividir.**

> ⚠️ Todos los números de §5.2 y §5.4 son **provisionales**. Se eligieron sin datos. Su único propósito hoy es generar pares (estimado, real) para calibrarlos después. Revisar a los 15-20 tickets cerrados.

### 5.5 Evento emitido

```json
{"event":"complexity_estimate","data":{
  "raw_score": 21,
  "points": 8,
  "dimensions": {
    "sister_feature": {"value":"none","pts":6},
    "files": {"value":11,"pts":4},
    "layers": {"value":4,"pts":4},
    "external_projects": {"value":1,"pts":3},
    "shared_state": {"value":true,"pts":4},
    "dod_gaps": {"value":"none","pts":0},
    "infra": {"value":false,"pts":0}
  },
  "split_recommended": true
}}
```

Se guarda además en `{workflowDir}/complexity.json` para que los comandos posteriores lo lean sin parsear el JSONL.

**Lo esencial: estimado y real se guardan juntos.** Sin el par, el puntaje es decorativo.

---

## 6. Peso del MR

### 6.1 Por qué no "líneas cambiadas"

Un rename masivo es riesgo cero de revisión. Un cambio de 40 líneas en lógica de estado compartido puede ser mortal. La métrica debe aproximar **carga cognitiva de revisión**.

### 6.2 Cálculo

```bash
git diff --ignore-all-space --find-renames --numstat <merge-base>..HEAD
```

| Tipo de cambio | Peso |
|---|---|
| Rename / archivo movido sin cambio de contenido | `1` |
| Reindentación, whitespace | `0` (vía `--ignore-all-space`) |
| Lockfiles, generados, snapshots | `0` |
| Código de producción | líneas reales |
| Tests | líneas reales, **contabilizadas aparte** |

Patrones excluidos (configurable en `config.json`):
`*.lock`, `package-lock.json`, `yarn.lock`, `*.snap`, `dist/`, `build/`, `*.generated.*`

### 6.3 Tests separados: por qué

Un MR de 300 donde 220 son tests no es un MR grande, es un MR bien cubierto. Sumarlos juntos hace que el sistema penalice exactamente el comportamiento que se quiere premiar.

**El umbral aplica sólo a `weight_prod`.**

### 6.4 Umbral

**300 puntos de peso de producción.** Provisional, igual que §5.4.

---

## 7. Partición de tareas

### 7.1 Dos puntos de decisión, no uno

Observación central del brainstorm:

> *A veces la tarea pasa a ser grande cuando la empezás a desarrollar y no podés evitarlo, porque no siempre sale todo en los primeros análisis.*

Esto invalida el diseño de decidir una sola vez. Si la partición se evalúa únicamente en analyze, el sistema captura sólo los casos fáciles — los que ya se veían venir. Los ciclos de 7-8 iteraciones no son de esos.

| Momento | Mecanismo | Naturaleza |
|---|---|---|
| **analyze** | rúbrica §5, umbral ≥8 puntos | a priori, barata, incompleta por definición |
| **implement** | trip wire §7.2 | a posteriori, sobre el diff real |

### 7.2 Trip wire

En cada checkpoint de grupo de archivos, `/wf-implement` recalcula `weight_prod` del diff acumulado. Si proyecta pasar el umbral:

**Comportamiento acordado: (c) + (a).**

- **(c) Registrar y seguir — default.** Appendea `size_exceeded`, lo muestra en pantalla, **no bloquea**.
- **(a) Cortar y stackear — opción ofrecida.** Cierra lo hecho como sub-MR contra la rama de integración y sigue en rama nueva. Requiere que lo hecho hasta ahí sea coherente y no rompa por sí solo.

Se descarta por ahora **(b) pausar y volver a analyze**: es la más limpia pero frena en seco y aplicaría una política dura basada en un umbral inventado sin datos.

**Razón del default:** es coherente con "instrumentar primero". Tras 15-20 tickets se sabrá si 300 era el número correcto, si el trip wire salta demasiado tarde para servir, y si partir realmente reduce iteraciones o sólo las reubica. El endurecimiento se hace con evidencia, conforme a §0.

### 7.3 El trip wire como instrumento de calibración

Cada disparo genera un par **(estimado, real)** con la causa concreta de la divergencia. No es sólo un control de tamaño: es el mecanismo que produce el dato que hoy falta para saber si la rúbrica sirve.

### 7.4 Unidad de partición: subtareas anidadas

Se elige **subtareas anidadas bajo un ticket padre**, no sub-tickets hermanos.

- Comparten `refinement-summary.md` y DoD del padre — el requerimiento no se fragmenta.
- Cada subtarea corre `analyze → implement → validate` por separado.
- Cada subtarea produce un MR chico contra la rama de integración.

Se parte donde duele —el ciclo analyze/implement/validate, donde se acumulan las iteraciones— sin fragmentar el requerimiento.

### 7.5 Modelo de branching

```
develop
  └── feature/BC-1234                    ← rama de integración
        ├── feature/BC-1234/sub-1        ← MR chico → rama de integración
        ├── feature/BC-1234/sub-2        ← MR chico → rama de integración
        └── feature/BC-1234/sub-3        ← MR chico → rama de integración
  ← un solo MR final: feature/BC-1234 → develop
```

Resuelve la tensión entre "MRs chicos se aprueban y mergean más rápido" y "el equipo espera un MR por ticket": develop ve un único merge, mientras cada pedazo se revisa chico y por separado.

---

## 8. Estructura de carpetas

### Por proyecto

```
.claude/workflow/
├── state.json                    # { "activeTicket": "BC-1234" }
├── config.json                   # stack, DoD, related_projects, exclusiones de peso, umbrales
└── BC-1234/
    ├── state.json                # stage, progreso, rama, iteraciones
    ├── refinement-summary.md     # compartido por todas las subtareas
    ├── plan.md                   # plan padre / índice de subtareas
    ├── design-decisions.md
    ├── complexity.json           # estimación §5.5
    ├── sub-1/
    │   ├── state.json
    │   ├── plan.md
    │   ├── review-findings.md
    │   └── complexity.json
    └── sub-2/
        └── ...
```

Sin partición, el ticket no tiene subcarpetas `sub-N/` y todo vive en la raíz de `BC-1234/` — idéntico al comportamiento actual.

`state.json` del ticket agrega:

```json
{
  "stage": "implement",
  "branch": "feature/BC-1234",
  "subtasks": ["sub-1", "sub-2"],
  "active_subtask": "sub-1",
  "iterations": {"analyze": 2, "implement": 3, "validate": 1}
}
```

### Global

```
~/.claude/workflow/
├── config.json
├── events.jsonl        # append-only, permanente — la verdad cruda
├── flow-history.json   # resúmenes compactados por ticket cerrado
└── improvements.md     # bitácora de cambios aplicados al workflow, con evidencia
```

---

## 9. Retención

Tres niveles con vidas distintas:

| Artefacto | Vida | Política |
|---|---|---|
| `events.jsonl` | **permanente** | append-only, nunca se poda |
| `{ticketId}/` en el proyecto | hasta el merge | al mergear se compacta a una entrada en `flow-history.json` y se borra la carpeta |
| `improvements.md` | **permanente** | sólo cambios aplicados al workflow, con su evidencia |

**Regla dura: la compactación nunca borra de `events.jsonl`.** Si dentro de seis meses surge una pregunta que hoy no se nos ocurre, hace falta el crudo. El archivo es de texto plano y unas pocas líneas por ticket — el costo de guardarlo para siempre es despreciable frente al costo de no poder responder.

Compactación sugerida al mergear:

```json
{
  "date": "2026-08-07",
  "project": "bc-app",
  "ticket": "BC-1234",
  "complexity_estimated": 8,
  "iterations_total": 5,
  "iterations_by_stage": {"analyze": 2, "implement": 2, "validate": 1},
  "leak_distances": [4, 1, 1],
  "detected_by": {"gate": 4, "user": 1},
  "scope_drift": {"unplanned": 2, "missing": 0},
  "mr_weight_prod": 240,
  "split": false
}
```

---

## 10. Cómo se usa la data

`/wf-retro` y `/wf-improve` pasan a consultar `events.jsonl` en lugar de razonar sobre la sesión suelta. Preguntas que el esquema responde:

1. ¿Qué etapa origina más defectos? → `group by stage_origin`
2. ¿Cuál es la fuga media por etapa de origen? → dónde poner el próximo gate
3. ¿Sube mi porcentaje de `detected_by: user`? → los gates se están degradando
4. ¿Subestimo sistemáticamente? → signo del error de calibración
5. ¿`sister_feature: none` correlaciona con más iteraciones? → validar §5.3
6. ¿Partir redujo iteraciones, o sólo las reubicó? → comparar tickets con y sin `split_applied`
7. ¿Qué categorías de finding se repiten en 3+ tickets? → candidatos fundamentados a cambio de workflow

Toda propuesta derivada de estas consultas debe cumplir §0: mínimo 3 tickets, cita de la consulta concreta, y asiento en `improvements.md`.

---

## 11. Orden de implementación sugerido

1. **Hooks + `events.jsonl`** — esqueleto mecánico. Valor inmediato, cero cambios en comandos.
2. **Rúbrica de complejidad en `/wf-analyze`** — empieza a generar el lado "estimado" del par.
3. **Peso del MR + trip wire (c) en `/wf-implement`** — genera el lado "real".
4. **Eventos semánticos en el resto de los comandos** — `finding`, `detected_by`, `stage_origin`.
5. **Subtareas y branching** — recién cuando haya datos que digan si el umbral de partición sirve.
6. **Consultas de análisis en `/wf-retro` y `/wf-improve`** — a los 15-20 tickets.

Los pasos 1-4 no cambian ninguna decisión del flujo: sólo observan. El paso 5 es el primero que altera cómo trabajás, y llega deliberadamente tarde.

---

## 12. Puntos abiertos

- **Umbrales de §5.4 y §6.4** — provisionales, sin base empírica. Calibrar a los 15-20 tickets.
- **Pesos de la rúbrica §5.2** — especialmente `sister_feature`; es una hipótesis explícita.
- **Detección de "abandonado"** — falta definir N días de inactividad.
- **`stage_origin` de un finding** — lo determina el modelo y es subjetivo. Riesgo de ruido; evaluar si conviene restringir a un enum corto de causas.
- **Multi-proyecto** — `events.jsonl` es global y mezcla proyectos. Sirve para patrones del workflow, pero las comparaciones de complejidad entre codebases distintos pueden no ser válidas.
