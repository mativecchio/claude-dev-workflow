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

### Agentes con contexto de proyecto

Para sobrescribir un agente global con contexto específico del proyecto, crear `.claude/agents/rn-architect.md` (o el que corresponda) en el proyecto. Claude Code usará el local en lugar del global.

---

## Estado del workflow

El workflow activo se persiste en `.claude/workflow/` dentro del proyecto:

```
.claude/workflow/
├── state.json              ← etapa actual, progreso
├── refinement-summary.md   ← output de /wf-refine
├── plan.md                 ← output de /wf-analyze
└── review-findings.md      ← output de /wf-review-plan
```

Para retomar un workflow después de cerrar Claude:
```
/wf resume
```

Para empezar de cero:
```
/wf reset
```

---

## Mejora continua

El sistema se mejora a sí mismo vía `/wf-retro`:

1. Analiza la sesión (retrabajo, fricción, iteraciones)
2. Cruza con el histórico en `~/.claude/workflow/flow-history.json`
3. Propone cambios concretos a los comandos
4. Aplica los cambios con tu aprobación

Los cambios se aplican en `~/.claude/commands/`. Para persistirlos en el repo fuente, editar el archivo correspondiente en `~/claude-workflow/commands/` y hacer commit.

---

## Estructura del repo

```
claude-workflow/
├── README.md
├── install.sh
├── commands/           ← 11 comandos wf-*
├── agents/
│   ├── react-native/   ← rn-architect, rn-debugger, rn-performance, rn-testing, rn-uiux, rn-bridge
│   ├── react/          ← react-architect
│   ├── python/         ← python-architect
│   ├── laravel/        ← laravel-architect
│   └── shared/         ← typescript-architect, backend-api
├── config/
│   └── workflow.json   ← template de config global
└── docs/
    └── architecture.md ← diseño del sistema
```
