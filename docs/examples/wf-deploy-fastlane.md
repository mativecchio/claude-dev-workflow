---
description: "Ejemplo de override por proyecto de /wf-deploy — React Native con fastlane y GitLab CI."
allowed-tools: Read, Bash, Glob
---

> **Ejemplo, no comando activo.** Esta es la versión específica de un proyecto
> React Native (fastlane, GitLab CI, `pnpm`, ramas `development`/`staging`/`master`).
> El comando genérico vive en `commands/wf-deploy.md` y detecta el toolchain en
> vez de asumirlo.
>
> Para usar esta versión en el proyecto que la necesita: copiarla a
> `.claude/commands/wf-deploy.md` en la raíz de ese proyecto. Claude Code prefiere
> el comando local sobre el global.

Tu rol es preparar el entorno git y guiar el deploy según la rama actual y el método disponible.

## Paso 0 — Parsear argumentos

Leer `$ARGUMENTS` y extraer:
- **TARGET** (`staging` | `production`) — si aparece alguna de estas palabras
- **METHOD** (`local` | `ci`) — si aparece alguna de estas palabras

Ejemplos:
- `/wf-deploy staging` → TARGET=staging, METHOD=auto-detectar
- `/wf-deploy local production` → METHOD=local, TARGET=production
- `/wf-deploy ci staging` → METHOD=ci, TARGET=staging
- `/wf-deploy` → ambos se determinan más adelante

## Paso 1 — Verificar estado git

```bash
git status --short
git log origin/$(git branch --show-current)..HEAD --oneline 2>/dev/null || echo "(sin remote tracking)"
git branch --show-current
```

Mostrar:
```
📦 Estado git:
  Rama actual: [nombre]
  Cambios sin commitear: [N archivos / ninguno]
  Commits sin pushear: [N / ninguno]
```

## Paso 2 — Detectar fase según rama

| Rama actual | Fase |
|---|---|
| Ticket branch (`MA-XXX`, `feature/*`, `fix/*`, cualquier nombre que no sea protegida) | **Fase 1** — preparar MR |
| `development` | **Fase 2a** — crear release branch para staging |
| `staging` | **Fase 2b** — crear release branch para production |
| `release/*` | **Fase 2** — deploy directo |
| `master` / `qa` | ⛔ Bloqueado — el script rechaza estas ramas |

---

## FASE 1 — Preparar MR (ticket branch)

### Commit + push si hay cambios pendientes

Si hay cambios sin commitear, mostrar archivos y preguntar: **"¿Commiteamos? ¿Qué archivos incluimos?"**

Una vez confirmados los archivos, invocar el skill `wf-commit` para generar el mensaje. Mostrar y pedir confirmación.

```bash
git add [archivos confirmados]   # nunca -A
git commit -m "[mensaje aprobado]"
```

Si hay commits sin pushear:
```bash
git push origin $(git branch --show-current)
```
Si el push falla por divergencia → mostrar error, pedir instrucciones. NO hacer force push.

### Informar y detener

```
✅ Rama lista: [nombre]
📋 MR: [URL del MR si está en el output del push, o indicar que lo creen en GitLab]

🔜 Próximo paso (después de que aprueben el MR):
   Si es feature → merge a development → /wf-deploy staging
   Si es fix sobre versión deployada → merge a staging → /wf-deploy production
```

Detener aquí. No continuar al deploy.

---

## FASE 2 — Deploy (release branch)

### Paso 2.1 — Determinar TARGET si no viene por argumento

- Si rama es `development` → TARGET=staging
- Si rama es `staging` → TARGET=production
- Si rama es `release/*` → preguntar TARGET si no fue pasado como argumento

### Paso 2.2 — Detectar método disponible

```bash
cat package.json 2>/dev/null | grep -E '"deploy:'
ls .gitlab-ci.yml .github/workflows/ 2>/dev/null
```

| Señal | Método |
|---|---|
| Scripts `deploy:*` en package.json + `Fastfile` | ✅ Local |
| `.gitlab-ci.yml` / `.github/workflows/` | ✅ CI |
| Ambos | Preguntar al usuario |

Si METHOD ya viene por argumento, saltear la pregunta.

### Paso 2.3 — Crear release branch (si estamos en development o staging)

Si la rama actual es `development` o `staging`:
```
📦 Estás en [rama]. Para deployar hay que crear un release branch.

¿Cuál será la versión? (ej: 1.3.1)
```
Esperar respuesta. Luego:
```bash
git checkout -b release/[version]
git push -u origin release/[version]
```

### Paso 2.4 — Ejecutar deploy

#### METHOD = local

Antes de correr los deploys, preguntar:
**"¿Qué versión usamos? (versionName y versionCode)"**

Mostrar los valores actuales como referencia:
```bash
grep -E "versionName|versionCode" android/app/build.gradle | grep -v suffix | head -2
```

Esperar respuesta. Resolver `VERSION_NAME` y `VERSION_CODE`.

**Android:**

Correr directamente (non-interactive gracias a los parámetros):
```bash
bundle exec fastlane android local_[TARGET] version_name:[VERSION_NAME] version_code:[VERSION_CODE] skip_confirm:true
```

Mostrar el output en tiempo real. Esperar a que termine.

**iOS** (después de que Android termine):
```bash
bundle exec fastlane ios local_[TARGET] version_name:[VERSION_NAME] version_code:[VERSION_CODE] skip_confirm:true
```

Mostrar el output. El 409 en MR es normal — iOS imprime la URL existente.

#### METHOD = ci

**GitLab CI:**
```
📋 Disparar el pipeline:
  1. GitLab → CI/CD → Pipelines → Run pipeline
  2. Branch: [rama actual]
  3. Variables:
       VERSION_CODE = [entero, mayor al último publicado]
       VERSION_NAME = [semver, ej: 1.3.1]
  4. Click "Run pipeline"
```
Preguntar: "¿Ya lo disparaste? Avisame cuando termine."

### Paso 2.5 — Resumen final

```
✅ Deploy completado

  Método: [local / CI]
  Target: [TARGET]
  Android: [resultado]
  iOS: [resultado / 409 normal]
  Rama: [release/x.y.z]
  MR release: [URL]
```

Si hubo errores → ayudar a diagnosticar.

---

## Referencia rápida

```
Flujo feature:
  MA-XXX → /wf-deploy           → commit+push+MR → merge a development
            → /wf-deploy staging → desde development → release/x.y.z → deploy staging → MR → staging

Flujo fix (versión ya deployada):
  fix/MA-XXX → /wf-deploy            → commit+push+MR → merge a staging
               → /wf-deploy production → desde staging → release/x.y.z → deploy production → MR → master
```

| Ambiente  | Android local                    | iOS local                    |
|-----------|----------------------------------|------------------------------|
| staging   | `pnpm deploy:android:staging`    | `pnpm deploy:ios:staging`    |
| production| `pnpm deploy:android:production` | `pnpm deploy:ios:production` |
