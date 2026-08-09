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
| `/wf-validate` | Post-implementación, antes de los tests |
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
  "related_projects": ["nombre-del-backend"],
  "dod_checklist": [
    "Tests escritos y pasando",
    "Sin console.log",
    "i18n keys agregadas",
    "Linter sin errores"
  ],
  "tech_debt_log": "docs/tech-debt.md"
}
```

Los comandos leen este archivo para adaptar el DoD, conocer proyectos relacionados y entender el stack.

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
├── tests/
│   └── test-install.sh ← valida install.sh contra un HOME sandbox
├── config/
│   └── workflow.json   ← template de config global (repo_path)
└── docs/
    ├── architecture.md ← diseño del sistema
    ├── brainstorm-metricas-y-complejidad.md
    ├── plan-harness-migration.md   ← migración a capa de harness (en curso)
    └── examples/       ← overrides por proyecto de referencia
```
