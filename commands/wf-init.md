---
description: "Inicializa el workflow en el proyecto actual. Escanea el codebase, detecta stack y DoD automáticamente, y genera .claude/workflow/config.json. Correr una vez por proyecto desde la raíz."
allowed-tools: Read, Write, Bash, Glob, Grep
---

Inicializás el sistema de workflow para este proyecto. Tu objetivo es generar un `.claude/workflow/config.json` útil escaneando el proyecto — sin preguntar lo que podés inferir.

## Paso 1 — Detectar stack

Buscar los siguientes archivos en la raíz del proyecto:

**JavaScript / TypeScript:**
- `package.json` → leer `dependencies` y `devDependencies` para detectar:
  - React Native: `react-native` presente
  - React (web): `react` presente sin `react-native`
  - Next.js: `next` presente
  - Vue: `vue` presente
  - Testing: `jest`, `vitest`, `cypress`, `playwright`
  - State: `redux`, `zustand`, `jotai`, `mobx`

**Python:**
- `pyproject.toml` o `setup.py` → detectar FastAPI, Django, Flask, pytest
- `requirements.txt` → idem

**PHP:**
- `composer.json` → detectar Laravel, Symfony

**Múltiples stacks:** si hay `package.json` Y `composer.json`, es un proyecto full-stack — registrar ambos.

## Paso 2 — Detectar convenciones de calidad

Buscar:
- `.eslintrc*` o `eslint.config.*` → linter activo → agregar "Linter sin errores" al DoD
- `.prettierrc*` → formatter → agregar "Prettier pasa" al DoD
- `jest.config.*` o `vitest.config.*` → testing configurado
- `cypress/` o `e2e/` → E2E disponible
- `.github/workflows/` → leer el CI para entender qué se corre en cada PR
- `phpunit.xml` o `pest.config.php` → testing PHP
- `pytest.ini` o `pyproject.toml [tool.pytest]` → testing Python

## Paso 3 — Detectar proyectos relacionados

Buscar en:
- `.env` o `.env.example` → variables que apunten a otros servicios (API URLs, service names)
- `README.md` → menciones de otros repos o servicios
- `package.json` → workspaces si es un monorepo

## Paso 4 — Detectar estructura y patrones

Escanear estructura top-level para entender si hay:
- `docs/` → tech_debt_log probable en `docs/tech-debt.md`
- `src/i18n/` o `locales/` → i18n activo → agregar "i18n keys agregadas" al DoD
- `migrations/` → migraciones activas → agregar "Migraciones incluidas" al DoD

## Paso 5 — Construir el config propuesto

Generar el config con lo detectado y mostrárselo al usuario antes de escribir:

```
📦 Stack detectado: [stack]
🧪 Test runner: [jest/pytest/pest/none]
🔍 Linter: [eslint/none]
🌿 Rama base: [develop/main/master]

📋 Config propuesto:

{
  "stack": "[stack detectado]",
  "base_branch": "[rama base detectada]",
  "related_projects": [],
  "checks": {
    "lint": "[comando real del proyecto]",
    "types": "[comando real, si aplica]",
    "test": "[comando real]"
  },
  "dod_checklist": [
    "Tests escritos y pasando",
    "[ítems detectados del proyecto]"
  ],
  "tech_debt_log": "[path si existe docs/]"
}

¿Lo ajustamos o lo escribimos así?
```

**`base_branch`** — detectar con `git branch -a`: la que exista entre `develop`, `main`, `master`. Si hay varias, preguntar cuál es la de integración. Sin este campo, cada comando que necesita un diff tiene que adivinarla.

**`checks`** — el cambio de mayor impacto de este config. Son los comandos **reales** del proyecto, sacados de los scripts de `package.json`, del `Makefile`, o del CI: no inventar `npm run lint` si el script no existe. Verificar que cada uno corra antes de escribirlo.

Lo que entra acá deja de depender del criterio de un agente: `/wf-validate` los corre antes de gastar un Agent, y `/wf-test` los usa como corrida final. Un ítem del `dod_checklist` que se pueda expresar como comando debería vivir en `checks`, no en la lista de prosa.

Preguntar una sola cosa si algo no quedó claro:
- Si no se detectó el stack → "¿Qué stack es este proyecto?"
- Si hay proyectos relacionados que no pudo inferir → "¿Hay repos relacionados que usa este proyecto?"

## Paso 6 — Escribir los archivos

Si el usuario confirma (o ajusta):

1. Crear `.claude/workflow/` si no existe
2. Escribir `.claude/workflow/config.json`
3. Crear `.claude/workflow/improvement-log.md` vacío:
```markdown
# Improvement Log

_Registrar observaciones durante la sesión con `/wf-improve <observación>`_
```

4. **`AGENTS.md` en la raíz del proyecto.** `config.json` es específico de este sistema; `AGENTS.md` es el formato que leen otras herramientas (Cursor, Codex, Copilot). Preguntar antes de crearlo, y si ya existe, ofrecer actualizarlo en vez de pisarlo.

```markdown
# [Nombre del proyecto]

[Una línea: qué es.]

## Stack
[stack detectado]

## Comandos
- Instalar: `[comando]`
- Tests: `[comando de checks.test]`
- Lint: `[comando de checks.lint]`
- Types: `[comando de checks.types]`
- Build: `[comando]`

## Convenciones
[Lo que se detectó del proyecto: estructura de carpetas, patrón de tests,
manejo de estado, i18n. Solo lo verificado en el codebase, no lo supuesto.]

## Rama base
`[base_branch]`
```

Mantener `AGENTS.md` corto y verificado: los comandos tienen que ser los reales, los mismos de `checks`. Un `AGENTS.md` con comandos inventados es peor que no tenerlo.

Confirmar:
```
✅ Proyecto inicializado

Archivos creados:
- .claude/workflow/config.json
- .claude/workflow/improvement-log.md
- AGENTS.md [si se confirmó]

Listo para usar. Arrancá con /wf cuando tengas una tarea.
```

## Nota si ya existe config

Si ya existe `.claude/workflow/config.json`, mostrar el contenido actual y preguntar:
**"Ya existe config. ¿Querés actualizarlo con lo que detecté o dejarlo como está?"**
