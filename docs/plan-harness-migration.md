# Plan — Migración a capa de harness

> Estado: **propuesta, pendiente de review**. No implementar sin pasar por la revisión del plan.
> Regla aplicada: `docs/brainstorm-metricas-y-complejidad.md` §0 — cada ítem cita evidencia (`archivo:línea`) o se marca explícitamente como hipótesis.

---

## 1. Diagnóstico

### 1.1 Tesis

El sistema hoy impone sus reglas **escribiendo prosa en archivos `.md` que el modelo lee y obedece casi siempre**. Un harness impone reglas con **mecanismos que no se pueden saltear**: hooks, scripts, permisos, checks ejecutables.

El repo ya tiene una prueba de que el enfoque mecánico funciona: la telemetría se implementó como hook (`hooks/wf-telemetry.sh`) en vez de pedirle a cada comando que registre eventos, justamente porque §3.1 del brainstorm documenta que el mecanismo opt-in previo (`flow-history.json` vía `/wf-retro` Paso 4) nunca se ejecutó ni una vez.

Este plan aplica ese mismo criterio al resto del sistema.

### 1.2 Hallazgos verificados

Cada uno con su evidencia. Ordenados por severidad.

| # | Hallazgo | Evidencia | Impacto |
|---|---|---|---|
| H1 | La telemetría no observa el camino de entrada principal | `hooks/wf-telemetry.sh:172-186` solo matchea `/wf-<etapa>` tipeado; `/wf` cae en `*) exit 0`. `README.md`: "el punto de entrada es siempre `/wf`" | Toda etapa entrada por el orquestador es invisible. `events.jsonl` = 0 líneas desde el 07/08 |
| H2 | El repo no es la fuente de verdad | `wf-commit.md` y `wf-deploy.md` existen en `~/.claude/commands/`, no en `commands/`. `install.sh:24` copia solo repo→home. `wf-retro.md:83` y `wf-improve.md:113` editan `~/.claude/commands/` y delegan el copy-back al usuario | Ya se perdieron 2 comandos. Cada `/wf-retro` que aplica una mejora amplía la divergencia |
| H3 | Gate que evalúa contra un archivo estructuralmente vacío | `wf-review-plan.md:60` marca hallazgo si el plan no cruzó `flow-history.json`; `wf-analyze.md` paso 6 idem. El archivo está en `{"entries": []}` | Un gate que nunca puede aportar señal, pero sí ruido |
| H4 | `base_branch` hardcodeado a `develop` | `wf-refine.md:101,104` ejecutan `git checkout -b {branch} develop`. `config.json` no tiene campo de rama base (`wf-init.md` paso 5 no lo genera) | Rompe en cualquier repo sobre `main`. Los otros 3 comandos dicen "develop/main/master, según el proyecto" — o sea, se lo preguntan al modelo cada vez |
| H5 | `wf-jira` quedó en el esquema pre-multi-ticket | `wf-jira.md:31-33` lee `.claude/workflow/refinement-summary.md` y `plan.md` (paths planos), pero el esquema actual es `.claude/workflow/{ticketId}/` | Nunca encuentra el contexto; genera el ticket sin enriquecer |
| H6 | `wf.md` tiene los pasos fuera de orden | `wf.md`: "## Paso 1 — Argumentos especiales" aparece **antes** de "## Paso 0 — Verificar inicialización" | El chequeo de init se ejecuta después del ruteo, o no se ejecuta |
| H7 | `stage_index()` no cubre todas las etapas que el propio hook emite | `hooks/wf-telemetry.sh:97-107`: no hay case para `mr-desc` ni `retro`, ambos emitidos en `:180-182`. Caen en `*) echo 0` | `leak_distance` (§2.2) calcula mal para findings detectados en esas etapas |
| H8 | El config global es código muerto | `config/workflow.json` tiene `projects`/`preferences`; ningún comando ni hook lo lee (grep sin resultados fuera de `install.sh:36`) | Confusión: hay dos configs y solo uno se usa |
| H9 | De la capa semántica del brainstorm no se implementó nada | §3.3 lista 7 comandos que deben emitir eventos; ninguno lo hace. §5 (rúbrica), §6 (peso MR), §7 (trip wire) tampoco | El diseño de "detectar que el log está incompleto" (§3.1) no puede funcionar: no hay con qué cruzar |
| H10 | `improvements.md` no existe | §0 y §8 lo requieren como bitácora obligatoria; `install.sh` no lo crea | La regla de fundamentación no tiene dónde asentarse |
| H11 | El campo `stage` del ticket queda desactualizado desde el primer comando | Solo `wf-refine.md:25` y `wf.md:105` escriben `stage`. Ni `wf-review-plan`, ni `wf-implement`, ni `wf-validate`, ni `wf-test` lo actualizan al entrar | La máquina de estados solo existe si pasás siempre por `/wf`. Invocando los comandos directo —uso que el README presenta como válido— el stage queda congelado en el del refinement |
| H12 | El valor escrito en `stage` no es el que espera ningún consumidor | `wf-refine.md:25` escribe `"stage": "refinement"`; `hooks/wf-telemetry.sh:163`, la tabla de ruteo de `wf.md` Paso 3 y `stage_index()` usan `refine` | Toda comparación de stage falla hoy, en silencio |

### 1.3 Nota sobre §0 y el alcance de este plan

§0 exige 3 tickets con el mismo patrón antes de proponer un cambio al workflow. **Hoy hay 0 eventos**, así que ninguna propuesta de *política de flujo* puede fundamentarse en datos todavía.

Por eso este plan se limita deliberadamente a dos clases de cambio, ambas admisibles bajo §0 vía la fuente "tarea en curso" (`archivo:línea`):

- **Correcciones** de comportamiento roto o divergente (H1-H8, H10).
- **Cambios de mecanismo sin cambio de política**: la regla que se aplica es la misma que ya está escrita en el `.md`; solo cambia *quién la hace cumplir*. Un gate que hoy es una instrucción y pasa a ser un hook no es una política nueva.

Todo lo que sí sería política nueva (umbrales, gates adicionales, partición de tareas) queda fuera de este plan y espera datos — es exactamente lo que §11 del brainstorm ordena en sus pasos 5-6.

**Una excepción declarada:** la Fase 3 agrega capacidades nuevas opt-in (validador de runtime, worktrees). No cambian ninguna regla existente ni se activan solas, pero tampoco están fundamentadas en datos. Se marcan como hipótesis y se dejan al final, separables del resto.

---

## 2. Inventario: prosa → mecanismo

El núcleo del plan. Cada fila es una regla que hoy vive como texto y puede vivir como mecanismo.

| Regla | Hoy | Propuesto | Fase |
|---|---|---|---|
| "Leé `activeTicket` de `state.json`" | Prosa idéntica repetida en 10 comandos (`wf-analyze.md:12`, `wf-review-plan.md:12`, `wf-validate.md:12`, `wf-implement.md:38`, `wf-test.md:12`, `wf-mr-desc.md:12`, `wf-mr-review.md:12`, `wf-retro.md:12`, `wf-improve.md:20`, `wf-refine.md:12`) | `scripts/wf-lib.sh` → `wf_ticket`, `wf_dir` | 2 |
| "Diffeá contra merge-base, no contra la base" | Párrafo explicativo repetido en 4 comandos (`wf-validate.md:36`, `wf-mr-review.md:18`, `wf-mr-desc.md:24`, + `wf-implement` implícito) | `scripts/wf-diff.sh` | 2 |
| "La rama base es develop/main/master según el proyecto" | Se le pregunta al modelo cada vez; hardcodeado en `wf-refine.md:104` | `base_branch` en `config.json` + `wf_base` en `wf-lib.sh` | 2 |
| "Al iniciar una etapa, actualizar `stage` en el state del ticket" | Solo lo hace `/wf` Paso 5; los comandos invocados directo no (H11) | `wf_enter_stage <stage>` en `wf-lib.sh`, invocada por cada comando en su primera línea | 2 |
| "NUNCA pasar a implementación sin respuesta explícita" | `wf-review-plan.md:96` — instrucción en mayúsculas | Hook `PreToolUse` que rechaza `Edit`/`Write` si `stage == review-plan` y `approved != true`. **Depende de H11/H12** | 2 |
| DoD checklist | Lista de strings en prosa (`config.json` → `dod_checklist`), evaluada por criterio del modelo | `checks` ejecutables en `config.json`, corridos antes de invocar cualquier agente | 2 |
| "Verificá el contrato del related_project antes de aprobar" | Prosa en 4 comandos; imposible de verificar a posteriori | Artefacto obligatorio `{workflowDir}/contract-verification.md`; el gate chequea existencia, no intención | 2 |
| "No toques archivos fuera del plan" | No existe como regla; solo se mide como `scope_drift` a posteriori (§2.3 #1) | Fuera de alcance — sería política nueva | — |

---

## 3. Fases

Cada fase es independiente y entregable por separado. El orden importa: la Fase 0 es prerequisito de todo lo demás, porque sin ella cualquier cambio se pierde en la próxima divergencia.

### Fase 0 — Cerrar el circuito de instalación

**Problema:** H2. El repo no es la fuente de verdad.

1. Adoptar `wf-commit.md` al repo tal cual. **Nota:** arrastra el mismo bug de paths planos que H5 (`.claude/workflow/plan.md` en vez de `{ticketId}/`); se adopta con el bug y se corrige en la Fase 1, para no mezclar adopción con corrección.
2. Adoptar `wf-deploy.md` en **versión genérica**: detecta método (CI vs local) y modelo de ramas desde `config.json` en vez de asumir fastlane/GitLab. Cuando el proyecto no tiene CI/CD, ni ramas de release definidas, ni scripts de deploy, el comando **lo señala y propone armarlo** en vez de seguir como si existiera. La versión actual atada a fastlane queda como override en `.claude/commands/` del proyecto que la usa.
3. `install.sh`: agregar modo `--check` que compare repo vs instalado y liste divergencias sin escribir.
4. `install.sh`: crear `~/.claude/workflow/improvements.md` si no existe (H10).
5. `wf-retro.md` Paso 5 y `wf-improve.md` Paso 4: cambiar el target de edición de `~/.claude/commands/wf-*.md` a `$WF_REPO/commands/wf-*.md` + correr `install.sh` al terminar. Resolver `$WF_REPO` desde `repo_path` en `~/.claude/workflow/config.json` (que pasa a tener un uso real — H8).
6. Eliminar `projects`/`preferences` de `config/workflow.json` (código muerto) y dejar `{ "repo_path": "..." }`.
7. `install.sh`: **mergear** `repo_path` en el config global existente con `jq`, no preservarlo intacto. El bloque actual (`install.sh:34-40`) hace skip si el archivo ya existe, así que una instalación previa —como la de este usuario, de mayo— nunca recibiría la key.

**Criterio de aceptación:** después de un `/wf-retro` que aplique una mejora, `install.sh --check` no reporta divergencias.

---

### Fase 1 — Corregir lo roto

Correcciones puntuales, sin cambio de arquitectura.

1. **H12 primero** — unificar el vocabulario de etapas en `refine` (valor que ya usan el hook, `stage_index()` y la tabla de ruteo). Corregir `wf-refine.md:25`. Es prerequisito de H11 y del gate de la Fase 2: no tiene sentido construir sobre un campo cuyo vocabulario no está unificado.
2. **H11** — cada comando de etapa escribe su `stage` al entrar. Se implementa en la Fase 2 vía `wf_enter_stage`, pero la corrección puntual va acá porque el gate depende de ella.
3. **H1 — empezar por un experimento, no por un diseño.** El ruteo por `/wf` no se detecta desde `UserPromptSubmit`: el prompt dice `/wf analizá esto`, no la etapa. Había tres candidatos, y **ninguno estaba verificado**:
   - (a) Que `/wf` escriba `stage` antes de rutear y el hook lo derive de ahí — depende de que el modelo escriba, que es lo que queremos evitar.
   - (b) `PreToolUse` sobre el `Read` de `~/.claude/commands/wf-*.md` (`wf.md:79`) — **descartada como "mecánica"**: también depende de que el modelo ejecute un `Read` que le indicaron por prosa.
   - (c) `PostToolUse` filtrando `tool_name: "Skill"` — en este harness los `wf-*` se exponen como skills, así que el ruteo puede resolverse por ahí y (b) no dispararía nunca.

   **Procedimiento:** instalar un hook temporal de logging que vuelque el JSON crudo de `PostToolUse` y `UserPromptSubmit` a un archivo, correr `/wf` una vez, inspeccionar qué llega realmente. Decidir con ese dato. Sin el experimento, cualquiera de las tres es una apuesta.
4. **H7** — agregar `mr-desc` y `retro` a `stage_index()`, o excluirlos explícitamente del cálculo de fuga con un comentario.
5. **H5** — `wf-jira.md:31-33` y `wf-commit.md` Paso 1: migrar a `{workflowDir}/`, con el Paso 0 estándar.
6. **H6** — `wf.md`: mover "Paso 0" antes de "Paso 1".
7. **H3** — `wf-analyze.md` paso 6 y `wf-review-plan.md:60`: degradar el cruce con `flow-history.json` de "marcarlo como hallazgo" a "si el archivo tiene entries, cruzarlo". Reactivar el gate cuando la Fase 4 lo llene.

---

### Fase 2 — Migración prosa → mecanismo

El núcleo. Implementa la tabla de §2.

1. **`scripts/wf-lib.sh`** — funciones sourceables:
   - `wf_ticket` → activeTicket, o falla con mensaje claro
   - `wf_dir` → `.claude/workflow/{ticketId}`
   - `wf_base` → `base_branch` del config, con fallback detectando `develop`/`main`/`master` en el repo
   - `wf_config <key>` → lectura tipada del config
   - `wf_enter_stage <stage>` → escribe `stage` y appendea a `completed` en el state del ticket (H11). Vocabulario único, el de `stage_index()`
2. **`scripts/wf-diff.sh`** — encapsula el merge-base; soporta el caso "sin commits, todo en working tree" que hoy está descrito en prosa en `wf-validate.md:48`.
3. **`scripts/wf-checks.sh`** — corre los `checks` del config y devuelve JSON con resultados. Nuevo campo en `config.json`:
   ```json
   "base_branch": "develop",
   "checks": {
     "lint":  "npm run lint",
     "types": "tsc --noEmit",
     "test":  "npm test"
   }
   ```
   `wf-init.md` pasa a detectarlos y generarlos (hoy detecta el linter en el Paso 2 pero solo para escribir un string de prosa en el DoD).
4. **`hooks/wf-gate.sh`** (`PreToolUse`) — bloquea `Edit`/`Write` sobre archivos de código cuando el ticket activo está en `stage: review-plan` sin `approved: true`. Excluye `.claude/workflow/**` y `docs/**`.
   - `wf-review-plan.md` Paso 3 escribe `approved: true` en el state del ticket cuando el usuario confirma.
   - El hook **sí puede bloquear** — es la única excepción al principio "nunca bloquea" del hook de telemetría, y es deliberada: acá bloquear es la función, no un efecto secundario. Escape hatch: `WF_GATE=off`.
   - **Contención del radio de explosión (obligatoria).** Los hooks se registran en `~/.claude/settings.json`, o sea que corren en *todos* los proyectos, tengan workflow o no. Requisitos no negociables:
     1. Salida temprana (exit 0) si el repo no tiene `.claude/workflow/state.json`.
     2. Fail-open ante cualquier error —`jq` ausente, JSON corrupto, git ausente—; el único camino que bloquea es la condición explícita evaluada con éxito.
     3. **Una semana en modo logging-only antes de activar el bloqueo.** Registra qué *habría* bloqueado en `events.jsonl` sin impedir nada. Requisito, no sugerencia: es el primer hook del sistema capaz de frenar trabajo, y rompe deliberadamente el principio "nunca interrumpe" de `wf-telemetry.sh`.
5. **Reescribir los 8 "Paso 0"** (13 líneas cada uno) como una línea que invoca `wf-lib.sh`, y los 4 bloques de merge-base (12 líneas) como una llamada a `wf-diff.sh`. `wf-refine` y `wf-improve` tienen variantes propias del Paso 0 y se migran aparte.
6. **`wf-validate.md` Paso 2.5** — correr `wf-checks.sh` antes de lanzar el Agent. Si falla algo mecánico, devolver eso y no gastar el agente.

**Ahorro estimado:** ~150 líneas de prosa repetida (8 × 13 + 4 × 12).

**Resultado real: +119 / −102, neto +17 líneas.** La estimación no se cumplió. Lo que se borró de prosa repetida se consumió explicando qué hace cada script y por qué (más el `approved` del gate y los campos nuevos de `wf-init`, que son capacidad nueva, no reemplazo).

La conclusión importante no es el número sino qué justifica la fase: **no era el conteo de líneas.** Es que la regla pasa a existir en un solo lugar y deja de depender de que el modelo la interprete igual las 8 veces. `wf_base` es el caso claro: antes era prosa distinta en 4 archivos, uno de ellos con `develop` hardcodeado (H4); ahora es una función con fallback verificado por test. El conteo de líneas era una métrica conveniente, no la razón.

**Verificación:** `tests/test-scripts.sh` — 34 checks contra un repo git temporal, incluyendo el caso que motivó `wf-diff` (base que avanza después de crear el branch) y los seis caminos de fail-open del gate.

---

### Fase 3 — Capacidades nuevas (opt-in, marcadas como hipótesis)

> Ninguna de estas está fundamentada en datos. Son apuestas explícitas, separables del resto del plan. Si el review las rechaza, las Fases 0/1/2/4 siguen siendo válidas.

1. **Validador de runtime** — nuevo ítem `7. 📱 Runtime` en el picker de `wf-validate.md` Paso 1. Para cambios de UI/navegación: levantar la app vía MCP de Metro, navegar a la pantalla afectada, leer estado y network, screenshot. Hipótesis: las races que §"orden de ejecución esperado" de `wf-analyze` intenta cubrir preguntándole al usuario se detectan mejor observando el runtime que razonando sobre el diff.
2. ~~**Un worktree por ticket**~~ — **movido fuera de este plan.** Choca con el dashboard multi-ticket: `wf.md` Paso 2 escanea `.claude/workflow/*/state.json` para listar todos los tickets, y con un worktree por ticket cada uno ve solo su propia carpeta. No es un detalle de implementación — obliga a decidir si el estado se muda a `~/.claude/workflow/{proyecto}/`, lo que toca también las Fases 2 y 4. Requiere su propio plan.
3. **Routing de modelo por etapa** — `model: sonnet` en las invocaciones de Agent de `wf-mr-desc`, `wf-jira`, `wf-commit`; Opus en `analyze`/`review-plan`/`validate`/`mr-review`.
4. **Delegar el review genérico** — `wf-mr-review.md` pasa a armar contexto + invocar `/code-review`, y conserva como propio solo el chequeo de contratos con `related_projects`, que ningún reviewer genérico hace.
5. **`AGENTS.md`** — `wf-init` genera también `AGENTS.md` con stack y convenciones, además de `config.json`.

---

### Fase 4 — Cerrar el loop de datos

Implementa §11 pasos 2-4 y 6 del brainstorm, que quedaron pendientes (H9).

1. Eventos semánticos en los comandos (§3.3): `finding` con `stage_origin`/`detected_by`, `finding_decision`, `complexity_estimate`.
2. **`scripts/wf-stats.sh`** — responde las 7 preguntas de §10 sobre `events.jsonl`. Sin esto, la telemetría solo acumula.
3. `wf-improve` y `wf-retro` pasan a consultar `wf-stats.sh` en vez de razonar sobre la sesión suelta.
4. Reactivar el gate de `flow-history.json` degradado en Fase 1.

**Prerequisito:** Fase 1 punto 1 (H1). Sin observar el camino `/wf`, cualquier estadística está sesgada hacia el uso directo de los comandos.

---

## 4. Orden y dependencias

```
Fase 0 (circuito de instalación)
   └── prerequisito de todo: sin esto, los cambios se pierden
        │
        ├── Fase 1 (correcciones)
        │      └── H1 ── prerequisito de ── Fase 4
        │
        ├── Fase 2 (prosa → mecanismo)   ← núcleo del cambio
        │
        └── Fase 3 (capacidades nuevas)  ← independiente, descartable
```

## 5. Qué queda explícitamente afuera

| Ítem | Por qué |
|---|---|
| Umbrales de complejidad (§5.4) y peso de MR (§6.4) | Provisionales por diseño; §12 los deja para 15-20 tickets |
| Partición en subtareas (§7) | §11 paso 5: "el primero que altera cómo trabajás, y llega deliberadamente tarde" |
| Trip wire de tamaño (§7.2) | Depende de umbrales sin calibrar |
| Regla "no toques archivos fuera del plan" | Sería política nueva sin evidencia |
| Worktree por ticket | Obliga a mover el estado fuera del repo para no romper el dashboard multi-ticket. Plan propio |

## 6. Riesgos

| Riesgo | Mitigación |
|---|---|
| **`wf-gate.sh` bloquea trabajo en proyectos ajenos al workflow.** Los hooks son globales (`~/.claude/settings.json`): corren en todos los repos que abras. Un bug bloquea `Edit`/`Write` en todos, no solo acá | Los tres requisitos de la Fase 2 punto 4: salida temprana sin `state.json`, fail-open ante cualquier error, y semana obligatoria de logging-only. **Este es el riesgo más alto del plan** |
| El gate bloquea trabajo legítimo (ej. tocar código durante `review-plan` para verificar una hipótesis) | Escape hatch `WF_GATE=off`; excluir `.claude/workflow/**` y `docs/**` |
| El gate se construye sobre `stage`, un campo hoy desactualizado (H11) y con vocabulario roto (H12) | H12 y H11 son prerequisitos explícitos, en la Fase 1, antes de escribir una línea del gate |
| Los scripts se rompen en un proyecto sin `jq` o sin git | Mismo principio que `wf-telemetry.sh`: degradar a fallback, nunca romper. Excepto `wf-gate.sh`, donde fallar **abierto** es lo correcto — bloquear por error es peor que no bloquear |
| Fase 2 toca los comandos a la vez → regresión difícil de aislar | Migrar comando por comando, verificando con `install.sh --check` y el smoke test entre cada uno |
| El experimento de H1 no concluye nada (ninguno de los tres hooks captura el ruteo) | Aceptable: significaría que el ruteo por `/wf` no es observable con los hooks disponibles, y la Fase 4 se limita al uso directo de comandos, documentando el sesgo en vez de ocultarlo |
