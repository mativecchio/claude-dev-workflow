---
description: "Escribe tests faltantes, evalúa cobertura y prepara el checklist pre-MR."
allowed-tools: Read, Edit, Write, Bash, Glob, Grep, TodoWrite
---

Tu rol es revisar los tests existentes, identificar gaps y escribir los que falten. Al final, checklist pre-MR.

## Paso 0 — Contexto del ticket

```bash
~/.claude/scripts/wf-lib.sh context
~/.claude/scripts/wf-lib.sh enter-stage test
```

Si `context` falla, preguntar el ticket y escribir `.claude/workflow/state.json` antes de reintentar.

## Paso 1 — Revisar tests existentes

Leer `{workflowDir}/plan.md` para saber qué archivos se modificaron.

Para cada módulo modificado:
- Buscar el archivo de test correspondiente
- Leer los tests existentes para entender el patrón del proyecto

## Paso 2 — Gap analysis

Identificar qué falta cubrir:

**Happy paths:** ¿el flujo principal está testeado?
**Error cases:** ¿los errores críticos tienen test?
**Edge cases:** ¿casos borde identificados en el refinement están cubiertos?

Mostrar el gap analysis al usuario antes de empezar a escribir:
```
📊 Gap analysis:
✅ Cubierto: [lista]
❌ Faltante: [lista]
```

Preguntar: "¿Arrancamos a escribir los tests faltantes?"

## Paso 3 — Escribir los tests

**Principios:**
- Leer los tests existentes del proyecto antes de escribir (seguir el mismo patrón)
- Tests sociables: no mockear componentes hijos, solo servicios externos y APIs
- Usar las utilidades de test del proyecto (factories, helpers, fixtures existentes)
- Un test por comportamiento, no por función

**Orden:**
1. Happy path del flujo principal
2. Casos de error críticos
3. Edge cases del refinement

## Paso 4 — E2E (evaluación opcional)

Al terminar los unit/integration tests, evaluar si aplica cobertura E2E:

**Aplica E2E cuando:**
- Es un flujo crítico de negocio (login, checkout, reserva)
- Es un flujo multi-pantalla encadenado
- Es una regresión que ya ocurrió en producción

**No aplica E2E cuando:**
- Son cambios visuales menores
- Es lógica interna sin flujo de usuario
- El flujo ya está cubierto con E2E existentes

Informar la evaluación al usuario y preguntar si quiere que se escriban los E2E si aplica.

## Paso 5 — Correr los tests

Durante la escritura, correr solo lo que estás tocando (adaptar al stack: `npm test -- --testPathPattern=X`, `pytest tests/X -v`, `php artisan test --filter=X`).

Al terminar, la corrida completa sale del config del proyecto:

```bash
~/.claude/scripts/wf-checks.sh
```

Si algún test falla, diagnosticar y corregir antes de continuar. Este es el mismo gate que corre `/wf-validate`: si pasa acá, no vuelve a ser un problema allá.

## Paso 6 — Checklist pre-MR

```
✅ Checklist pre-MR:

DoD del proyecto:
[ítems del dod_checklist del config.json]

Tests:
- [ ] Unit/integration tests escritos y pasando
- [ ] E2E evaluado ([aplica/no aplica] — [razón])
- [ ] Sin tests en skip/xdescribe sin justificación

Código:
- [ ] Sin console.log / print / dd() de debug
- [ ] Linter pasa sin errores
- [ ] Build pasa sin errores

Otros:
- [ ] Deuda técnica registrada en plan.md
- [ ] Breaking changes documentados
```

Si el ticket toca un estado/storage/contrato compartido con algún `related_project` (config.json) — revisar `plan.md`/`review-findings.md`/`validation-*.md` para confirmarlo — agregar al checklist:
```
- [ ] Validado manualmente en browser/entorno real contra el sistema externo real ([related_project]), no solo tests unitarios/mocks
```
Esto no lo puede tildar el propio agente: es un gate que requiere confirmación explícita del usuario, porque ningún test in-repo ni revisión de diff puede verificar el comportamiento real de un sistema fuera de este repo.

## Paso 7 — Registrar los gaps encontrados

Por cada hueco que el análisis de cobertura destapó y que **no era** un test faltante trivial — un caso borde sin cubrir, un comportamiento que el plan no contemplaba:

```bash
~/.claude/scripts/wf-event.sh finding \
  --category [slug] --severity [high|medium] \
  --stage_origin [refine|analyze|implement] --stage_detected test \
  --detected_by gate --summary "[una línea]"
```

Un caso borde que aparece recién acá casi siempre se originó en `refine` (nadie lo pidió) o en `analyze` (el plan no lo contempló). Atribuirlo a `implement` porque es donde se ve el síntoma es el error que vuelve inútil la métrica de origen.

Al terminar, sugerir: "Siguiente: `/wf-mr-desc` para la descripción del MR y `/wf-mr-review` para la revisión final."
