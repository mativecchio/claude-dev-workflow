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

📋 Config propuesto:

{
  "stack": "[stack detectado]",
  "related_projects": [],
  "dod_checklist": [
    "Tests escritos y pasando",
    "[ítems detectados del proyecto]"
  ],
  "tech_debt_log": "[path si existe docs/]"
}

¿Lo ajustamos o lo escribimos así?
```

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

Confirmar:
```
✅ Proyecto inicializado

Archivos creados:
- .claude/workflow/config.json
- .claude/workflow/improvement-log.md

Listo para usar. Arrancá con /wf cuando tengas una tarea.
```

## Nota si ya existe config

Si ya existe `.claude/workflow/config.json`, mostrar el contenido actual y preguntar:
**"Ya existe config. ¿Querés actualizarlo con lo que detecté o dejarlo como está?"**
