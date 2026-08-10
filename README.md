# claude-workflow

Sistema de automatización del ciclo de desarrollo completo para Claude Code. Cubre desde el refinement de un ticket hasta la revisión del MR, con agentes especializados por stack tecnológico.

## Instalación

```bash
git clone <repo-url> ~/claude-workflow
chmod +x ~/claude-workflow/install.sh
~/claude-workflow/install.sh
```

Esto instala:
- Comandos `wf-*` en `~/.claude/commands/` (disponibles en cualquier proyecto)
- Agentes de lenguaje en `~/.claude/agents/`
- Config base en `~/.claude/workflow/`
- Referencia al sistema en `~/.claude/CLAUDE.md`

Para reinstalar después de cambios al repo:
```bash
~/claude-workflow/install.sh
```

---

## Modo de uso

### Flujo completo desde cero

El punto de entrada es siempre `/wf`. Detecta automáticamente en qué etapa estás a partir de lo que describís:

```
/wf tengo el ticket BC-1429, hay que agregar filtro por fecha en el listado de reservas
→ detecta: Refinement
→ ejecuta: /wf-refine

/wf el plan está listo, ya lo revisaron
→ detecta: Implementation
→ ejecuta: /wf-implement
```

### Uso directo por etapa

También podés invocar cada comando directamente si ya sabés qué necesitás:

| Comando | Cuándo usarlo |
|---|---|
| `/wf-refine` | Al arrancar una feature o ticket nuevo |
| `/wf-analyze` | Cuando necesitás el plan técnico |
| `/wf-review-plan` | Para verificar el plan antes de codear |
| `/wf-implement` | Para implementar (también sirve para bugs/debug) |
| `/wf-validate` | Post-implementación, antes de los tests (incluye validador de runtime vía MCP) |
| `/wf-test` | Para escribir tests y hacer el checklist pre-MR |
| `/wf-commit` | Para generar el mensaje de commit con contexto del ticket |
| `/wf-deploy` | Para commit+push, release branch y deploy |
| `/wf-mr-desc` | Para generar la descripción del MR |
| `/wf-mr-review` | Para hacer code review de un MR |
| `/wf-retro` | Al cerrar un ticket, para extraer aprendizajes |
| `/wf-jira` | Para generar o enriquecer un ticket de Jira |

### Flujo típico

```
/wf-refine   → define alcance y DoD
     ↓
/wf-analyze  → explora codebase, genera plan.md
     ↓
/wf-review-plan  → verifica plan → CHECKPOINT (aprobación explícita)
     ↓
/wf-implement    → implementa por grupos, con checkpoints
     ↓
/wf-validate     → (opcional) validation gate por categoría
     ↓
/wf-test         → tests + checklist pre-MR
     ↓
/wf-mr-desc  → descripción del MR
/wf-mr-review → code review
     ↓
/wf-retro    → (opcional) retrospectiva → mejora el workflow
```

### Validación de runtime

`/wf-validate` ofrece un validador `📱 Runtime` además de los que razonan sobre el diff. Levanta la app por MCP (`metro` para React Native, `claude-in-chrome` para web), navega a la pantalla afectada y observa estado, network y consola.

Es para lo que un diff no muestra: un orden entre efectos, un estado que queda inconsistente al volver a una pantalla, una request que se dispara dos veces. Requiere la app corriendo — si no hay MCP disponible, lo dice en vez de dar por validado lo que no observó.

### Code review

`/wf-mr-review` delega el pase genérico a `/code-review high` (bugs, simplificación, reuso, eficiencia) y se queda con lo que ningún reviewer genérico puede hacer: contraste contra el `plan.md` y los criterios de aceptación, contratos con `related_projects` verificados contra el código real del otro repo, y convenciones del proyecto.

### Modo debug

`/wf-implement` detecta automáticamente cuando hay un bug o error:

```
/wf-implement hay un error 500 en el endpoint de login cuando el email no existe
→ modo debug activado
→ diagnóstico primero, luego plan, luego checkpoint antes de tocar código
```

---

## Agentes de lenguaje

Los agentes son expertos de dominio que se invocan en demanda. No cargan contexto automáticamente — cero costo en proyectos que no los usan.

### React Native

| Agente | Cuándo usar |
|---|---|
| `rn-architect` | Diseño de componentes, estructura, refactors |
| `rn-debugger` | Errores en hooks, sagas, componentes (JS/TS) |
| `rn-performance` | Re-renders, memoización, FlatList, selectors |
| `rn-testing` | Unit tests (slices), integration tests (sagas) |
| `rn-uiux` | Layout, estilos, accesibilidad, StyleSheet |
| `rn-bridge` | Crashes nativos (iOS/Android), NativeModules |

### React

| Agente | Cuándo usar |
|---|---|
| `react-architect` | Componentes, hooks, state management, Next.js |

### Compartidos

| Agente | Cuándo usar |
|---|---|
| `typescript-architect` | Tipos complejos, generics, Zod, narrowing |
| `backend-api` | Diseño de contratos REST, auth, responses |

### Python

| Agente | Cuándo usar |
|---|---|
| `python-architect` | FastAPI, Pydantic, async, estructura de proyecto |

### Laravel / PHP

| Agente | Cuándo usar |
|---|---|
| `laravel-architect` | Controllers, services, Eloquent, Form Requests |

**Árbol de decisión para RN:**
```
¿Es un crash con stack trace nativo (Swift/Kotlin)?  → rn-bridge
¿Es un error JS en hooks, sagas, o componentes?      → rn-debugger
¿Es un problema de estructura o diseño?              → rn-architect
¿Es lentitud o re-renders?                          → rn-performance
¿Es visual, layout, o estilos?                      → rn-uiux
¿Son tests?                                         → rn-testing
```

---

## Configuración por proyecto

Crear `.claude/workflow/config.json` en la raíz del proyecto:

```json
{
  "stack": "React Native + TypeScript",
  "base_branch": "develop",
  "related_projects": ["nombre-del-backend"],
  "checks": {
    "lint": "npm run lint",
    "types": "tsc --noEmit",
    "test": "npm test"
  },
  "dod_checklist": [
    "Tests escritos y pasando",
    "i18n keys agregadas"
  ],
  "tech_debt_log": "docs/tech-debt.md"
}
```

Los comandos leen este archivo para adaptar el DoD, conocer proyectos relacionados y entender el stack. `/wf-init` lo genera detectando todo esto del proyecto.

`/wf-init` también ofrece generar un **`AGENTS.md`** en la raíz. No es redundante con `config.json`: este último es el formato de este sistema, `AGENTS.md` es el que leen otras herramientas (Cursor, Codex, Copilot). Los comandos salen de `checks`, así que ambos archivos apuntan a los mismos comandos reales.

**`checks` vs `dod_checklist`.** Todo ítem del DoD que se pueda expresar como comando debería vivir en `checks`. `/wf-validate` los corre **antes** de lanzar un agente: si el linter falla, no tiene sentido gastar un agente opinando sobre lo mismo, y con posibilidad de falso positivo. `dod_checklist` queda para lo que realmente requiere criterio.

**`base_branch`.** Antes cada comando la resolvía por su cuenta y `/wf-refine` tenía `develop` hardcodeado, lo que rompía en cualquier repo sobre `main`.

Si un cambio toca estado compartido con un `related_project` (ej. un objeto en sessionStorage que también lee un repo externo), `wf-analyze` grepea el path local de ese proyecto para confirmar el comportamiento real en vez de asumirlo, y `wf-review-plan`/`wf-validate`/`wf-mr-review` bloquean el "APROBADO" si esa verificación no se hizo.

### Agentes con contexto de proyecto

Para sobrescribir un agente global con contexto específico del proyecto, crear `.claude/agents/rn-architect.md` (o el que corresponda) en el proyecto. Claude Code usará el local en lugar del global.

---

## Estado del workflow

Soporta múltiples tickets en paralelo. El estado raíz solo guarda cuál está activo; cada ticket tiene su propia carpeta:

```
.claude/workflow/
├── state.json                    ← { "activeTicket": "BC-XXXX" }
├── BC-XXXX/
│   ├── state.json                ← etapa actual, progreso, branch guardado
│   ├── refinement-summary.md     ← output de /wf-refine
│   ├── plan.md                   ← output de /wf-analyze
│   └── review-findings.md        ← output de /wf-review-plan
└── BC-YYYY/
    └── state.json
```

`/wf` sin argumentos muestra un dashboard con todos los tickets activos y su etapa:
```
📋 Tickets:
  BC-XXXX  [stage]   ✅ [completadas]   🎯 ← activo
  BC-YYYY  [stage]   ✅ [completadas]
```

Para cambiar de ticket activo:
```
/wf BC-YYYY
```

Para empezar de cero (borra `state.json` raíz):
```
/wf reset
```

**Ticket retroactivo:** si activás un ticket que ya tiene commits de código en el branch pero no `plan.md` (ticket armado después de implementar), `/wf` ofrece saltear refine/analyze/review-plan en vez de forzar el flujo completo — pide confirmación y arranca directo en `implement`/`validate`.

**Branch mismatch:** si el branch actual no corresponde al ticket activo, `/wf` no solo avisa — ofrece `git checkout` al branch guardado de una sesión previa, o crear uno nuevo (`{ticketId}-{slug}` desde la rama base), con confirmación antes de ejecutar.

---

## Mejora continua

El sistema se mejora a sí mismo vía `/wf-retro` y `/wf-improve`:

1. Analiza la sesión (retrabajo, fricción, iteraciones)
2. Cruza con el histórico en `~/.claude/workflow/flow-history.json`
3. Propone cambios concretos a los comandos
4. Aplica los cambios con tu aprobación

### Qué dicen los datos

Los comandos registran eventos semánticos vía `wf-event.sh` a medida que corren: qué defecto apareció, en qué etapa se originó, quién lo detectó, qué se decidió. `wf-stats.sh` los consulta:

```bash
~/.claude/scripts/wf-stats.sh              # resumen
~/.claude/scripts/wf-stats.sh origins      # ¿qué etapa origina más defectos?
~/.claude/scripts/wf-stats.sh leak         # ¿cuánto tarda en detectarse cada uno?
~/.claude/scripts/wf-stats.sh detection    # ¿los gates se están degradando?
~/.claude/scripts/wf-stats.sh categories   # ¿qué se repite en 3+ tickets?
~/.claude/scripts/wf-stats.sh coverage     # ¿el log está perdiendo causas?
```

Dos cosas que el script hace a propósito: **siempre muestra el tamaño de la muestra**, y **se niega a concluir por debajo de 3 tickets** — imprime los números con un aviso explícito en vez de una conclusión. Un porcentaje sobre 2 tickets es ruido, y presentarlo pelado invita a actuar sobre él.

`coverage` es el que audita el propio log: una reentrada registrada por el hook sin ningún `finding` que la explique significa que se perdió la causa. Ese número es la razón de tener dos capas de captura.

**Esperá a tener datos.** Al momento de escribir esto `events.jsonl` está vacío — la telemetría se llena sola a medida que corrés etapas. Conectar `/wf-retro` a consultas sobre un archivo vacío daría peor resultado que su análisis actual de la sesión.

**El repo es la fuente de verdad.** Los cambios se aplican sobre `{repo_path}/commands/`, se asientan con su evidencia en `~/.claude/workflow/improvements.md`, y recién ahí se reinstalan. `repo_path` lo escribe `install.sh` en el config global.

Nunca editar `~/.claude/commands/` directo: es un destino de instalación y todo cambio hecho ahí se pierde en la próxima corrida de `install.sh`.

Para verificar que el repo y lo instalado coinciden:
```bash
~/claude-workflow/install.sh --check
```

---

## Estructura del repo

```
claude-workflow/
├── README.md
├── install.sh          ← instala; `--check` reporta divergencias sin escribir
├── commands/           ← 15 comandos wf-*
├── hooks/
│   └── wf-telemetry.sh ← captura mecánica del ciclo → events.jsonl
├── agents/
│   ├── react-native/   ← rn-architect, rn-debugger, rn-performance, rn-testing, rn-uiux, rn-bridge
│   ├── react/          ← react-architect
│   ├── python/         ← python-architect
│   ├── laravel/        ← laravel-architect
│   └── shared/         ← typescript-architect, backend-api
├── scripts/            ← wf-lib, wf-diff, wf-checks, wf-event, wf-stats
├── tests/
│   ├── test-install.sh ← valida install.sh contra un HOME sandbox
│   ├── test-scripts.sh ← valida los scripts y el gate contra un repo temporal
│   └── test-events.sh  ← valida wf-event y las 7 consultas de wf-stats
├── config/
│   └── workflow.json   ← template de config global (repo_path)
└── docs/
    ├── architecture.md ← diseño del sistema
    ├── brainstorm-metricas-y-complejidad.md
    ├── plan-harness-migration.md   ← migración a capa de harness (en curso)
    └── examples/       ← overrides por proyecto de referencia
```
