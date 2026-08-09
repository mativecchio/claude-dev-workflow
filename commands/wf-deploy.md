---
description: "Deploy paso a paso: commit+push si hay cambios pendientes, detecta la fase según la rama y ejecuta el deploy con el método disponible (CI o local). Si el proyecto no tiene CI/CD ni modelo de ramas definido, lo señala y propone armarlo."
allowed-tools: Read, Bash, Glob, Grep
---

Tu rol es preparar el entorno git y guiar el deploy según la rama actual y el método disponible en **este** proyecto. No asumas ninguna herramienta concreta: todo se detecta o se lee del config.

## Paso 0 — Parsear argumentos

Leer `$ARGUMENTS` y extraer:
- **TARGET** — el ambiente destino, si aparece nombrado (`staging`, `production`, `qa`, el que use el proyecto)
- **METHOD** (`local` | `ci`) — si aparece alguna de esas palabras

Lo que no venga por argumento se determina más adelante.

## Paso 1 — Leer el modelo de ramas del proyecto

Leer `.claude/workflow/config.json`:

```json
"base_branch": "develop",
"deploy": {
  "branch_model": { "integration": "develop", "staging": "staging", "production": "master" },
  "release_branch_pattern": "release/{version}",
  "protected": ["master", "qa"],
  "commands": { "staging": "...", "production": "..." }
}
```

**Si no existe la clave `deploy`**, no inventarla: seguir con la detección del Paso 3 y aplicar el Paso 6 (diagnóstico de prácticas faltantes) antes de ejecutar nada.

## Paso 2 — Verificar estado git

```bash
git status --short
git branch --show-current
git log origin/$(git branch --show-current)..HEAD --oneline 2>/dev/null || echo "(sin remote tracking)"
```

Mostrar:
```
📦 Estado git:
  Rama actual: [nombre]
  Cambios sin commitear: [N archivos / ninguno]
  Commits sin pushear: [N / ninguno]
```

Si la rama actual está en `deploy.protected` → **detener**. No se deploya ni se commitea desde una rama protegida.

## Paso 3 — Detectar el método de deploy disponible

```bash
ls .gitlab-ci.yml .github/workflows/ .circleci/ azure-pipelines.yml 2>/dev/null
grep -oE '"deploy[^"]*"' package.json 2>/dev/null
ls Fastfile fastlane/Fastfile Makefile Dockerfile 2>/dev/null
```

| Señal encontrada | Método |
|---|---|
| Config de CI (`.gitlab-ci.yml`, `.github/workflows/`, etc.) | ✅ CI disponible |
| Scripts de deploy en `package.json`, `Makefile`, o `deploy.commands` en el config | ✅ Local disponible |
| Ambos | Preguntar al usuario cuál usar |
| **Ninguno** | Ir al Paso 6 antes de continuar |

Si METHOD vino por argumento, saltear la pregunta pero igual registrar qué se detectó.

## Paso 4 — Determinar la fase según la rama

| Rama actual | Fase |
|---|---|
| Rama de ticket (no figura en `branch_model` ni en `protected`) | **Fase 1** — preparar MR |
| Rama de integración (`branch_model.integration`) | **Fase 2** — crear release branch hacia el ambiente siguiente |
| Rama que matchea `release_branch_pattern` | **Fase 2** — deploy directo |
| Rama en `protected` | ⛔ Detenido en el Paso 2 |

---

### FASE 1 — Preparar el MR

**Commit y push si hay cambios pendientes.**

Si hay cambios sin commitear, mostrar los archivos y preguntar: **"¿Commiteamos? ¿Qué archivos incluimos?"**

Con los archivos confirmados, invocar `/wf-commit` para generar el mensaje. Mostrar y pedir confirmación.

```bash
git add [archivos confirmados]   # nunca -A
git commit -m "[mensaje aprobado]"
git push origin $(git branch --show-current)
```

Si el push falla por divergencia → mostrar el error y pedir instrucciones. **Nunca force push.**

**Informar y detener:**
```
✅ Rama lista: [nombre]
📋 MR: [URL si aparece en el output del push, o dónde crearlo]

🔜 Próximo paso: después de que aprueben el MR, mergear a [integration]
   y volver a correr /wf-deploy [target] desde ahí.
```

No continuar al deploy.

---

### FASE 2 — Deploy

**Determinar TARGET** si no vino por argumento: derivarlo de `branch_model` (rama de integración → ambiente siguiente). Si el modelo no lo define, preguntar.

**Crear la release branch** si estás en una rama de integración:
```
📦 Estás en [rama]. Para deployar hay que crear una release branch.
¿Qué versión? (ej: 1.3.1)
```
Luego, usando `release_branch_pattern`:
```bash
git checkout -b [patrón resuelto]
git push -u origin [patrón resuelto]
```

**Ejecutar el deploy:**

- **METHOD = local** → correr el comando de `deploy.commands[TARGET]`. Si el proyecto pide datos de versión (versionName/versionCode, tag, semver), preguntarlos **antes** de ejecutar y mostrar los valores actuales como referencia. Mostrar el output en tiempo real y esperar a que termine.
- **METHOD = ci** → mostrar los pasos concretos para disparar el pipeline (proveedor, rama, variables requeridas) y preguntar: "¿Ya lo disparaste? Avisame cuando termine."

**Resumen final:**
```
✅ Deploy completado
  Método: [local / CI]
  Target: [TARGET]
  Rama: [release branch]
  Resultado: [por plataforma/servicio]
```

Si hubo errores, ayudar a diagnosticar.

---

## Paso 6 — Diagnóstico de prácticas faltantes

Correr **siempre** que falte alguna de estas piezas. No bloquea el deploy, pero se informa antes de ejecutar nada — un deploy manual sin red de seguridad es una decisión, no un default.

| Falta | Qué señalar | Qué proponer |
|---|---|---|
| No hay config de CI | No hay forma de reproducir el deploy fuera de tu máquina, ni de auditarlo | Pipeline mínimo: instalar deps, correr los `checks` del config, buildear |
| Hay CI pero no corre los `checks` del `config.json` | El gate de calidad existe local pero no se aplica en el MR | Agregar lint/types/test al pipeline del MR |
| No hay `deploy.branch_model` en el config | El comando tiene que adivinar el modelo de ramas en cada corrida | Definirlo una vez en `.claude/workflow/config.json` |
| No hay ramas protegidas | Se puede pushear directo al ambiente productivo | Proteger las ramas de release en el remoto |
| No hay versionado en el release | No se puede saber qué está deployado ni volver atrás | Tags de versión, o `release_branch_pattern` con semver |
| No hay rollback documentado | Ante un incidente se improvisa | Documentar el procedimiento en el README |

Formato del aviso:

```
⚠️  Prácticas faltantes detectadas en este proyecto:

  [pieza faltante] → [qué riesgo concreto implica]
  [pieza faltante] → [qué riesgo concreto implica]

Propuesta: [la más importante de la tabla]

¿Seguimos con el deploy igual, o lo armamos primero?
```

Esperar respuesta. Si el usuario elige armarlo, la skill `infra-checklist` cubre el checklist completo de infraestructura.

Si el usuario elige seguir, continuar sin volver a preguntar — el aviso ya se dio.

---

## Nota sobre proyectos con toolchain propio

Un proyecto con un flujo de deploy muy específico (fastlane, Helm, Terraform, scripts internos) debería crear su propio `.claude/commands/wf-deploy.md`, que sobrescribe a este. Este comando es el genérico: detecta lo que hay, no asume herramientas.
