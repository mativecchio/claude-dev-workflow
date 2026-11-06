---
description: "Live demo of a change, step by step and only its main flows, narrated the way test-in-env's --explain --step does it (a banner on the page with the flow, the step and what to expect, a line in the chat per step, Go on / Repeat / Skip / Stop buttons on the banner) and with every finding or doubt told at once. Optionally aloud into a call, for someone who cannot see the screen (--voice), and driven by spoken commands that start with a wake word, such as 'Cristina, seguí' (--listen). Usage: /wf-demo [--voice] [--listen] [--run] [what to show], /wf-demo stop"
allowed-tools: Read, Bash, Monitor, mcp__claude-in-chrome__*
---

A demo of a change to someone who needs to understand it, often a PO, on a shared screen or only
through a call (Slack, Meet, Zoom...). It shows the change working, not a test battery: the main
flows, three to five steps each, nothing that matters left unsaid.

It is told the way the `roi:test-in-env` skill narrates a run with `--explain --step`
(booking-center-specs, `plugins/roi/skills/test-in-env/references/narration.md`): the same banner,
the same chat lines, the same buttons. What `/wf-demo` adds is the voice, and choosing only the main
flows.

**Options:**

| Option | Effect |
|---|---|
| (none) | Banner on the page and a line in the chat for each step; waits after each step |
| `--run` | Does not wait after each step: goes straight through, still narrating |
| `--voice` | Also says the narration aloud, into the call through a virtual microphone |
| `--listen` | Also takes spoken commands after a wake word ("Cristina, seguí"), with or without `--voice` |

**The voice is optional**, and so is listening. The words count as the flags: "con voz", "sin
voz", "quitá la voz", "escuchame". Mid-demo, set up what is asked then; what is dropped stops at
once (`wf-voice.sh stop`, or only stop speaking) and the demo goes on with the banner and the chat.

The voice, the virtual microphone and the listening are `~/.claude/scripts/wf-voice.sh` (Linux with
PipeWire); its settings are in `~/.claude/workflow/voice.json` and `wf-voice.sh config` prints them.

**Language:** the banner, the chat and the voice in the language the user writes in (for Spanish,
the variant their `CLAUDE.md` asks for). Never imitate a real person's voice, whatever is asked.

---

## `/wf-demo stop`

`wf-voice.sh stop`, stop the Monitor on `listen`, remove the banner
(`document.getElementById('roi-qa-banner')?.remove()`), and with `--voice` tell the user to pick
their usual microphone again in the call app.

---

## Step 1 — The steps

From what the user asked to show (`$ARGUMENTS`, the ticket, the MR, its spec): **only the main
flows**, each one a thing the audience will remember, three to five steps per flow. Edge cases,
errors and permissions only when asked. Number them as test-in-env numbers cases: `F-1`, `F-2`...

Prepare in silence what every step needs (data, the right user, a clean page) and **try it before
the demo**: what stalls on setup loses the audience. What needs the user — a login, a password,
data you may not change — is asked now, not mid-demo. Work in your own tab of the session's tab
group, never in the user's, and say which one.

Show the flows and their steps in the chat and **wait for the user's go**; never start on your own.

## Step 2 — The voice (`--voice`, `--listen`)

Skip it with neither flag.

1. `wf-voice.sh check`. For each `MISSING`:
   - a tool (`pw-loopback`, `jq`...): name the package and stop; system packages are the user's.
   - piper, faster-whisper, the voice or the speech model: `wf-voice.sh setup` downloads them. Ask
     first, naming what and how much: the Python packages from PyPI (~200 MB with their
     dependencies), the voice from Hugging Face `rhasspy/piper-voices` (60–110 MB) and the speech
     model from Hugging Face (`small` ~460 MB, `base` ~140 MB). Only after a yes. With `--listen`
     alone, only faster-whisper and the speech model.
2. `--voice`: `wf-voice.sh route`, and ask the user to pick **Mic+Voz** as the microphone in the
   call app. It carries their own mic and the voice; the voice also plays on their current output.
   Then `wf-voice.sh say "<a short sentence>"` and ask whether it reached the call and whether the
   voice is right. Adjust in `voice.json` what they ask (`length_scale`: >1 slower, <1 faster;
   "too slow" means a smaller value; `voice`: another Piper voice, which `setup` downloads after
   asking) and try again.
3. `--listen`: run `wf-voice.sh listen` under the **Monitor** tool, so every line wakes you.
   `READY` — tell the user it listens for the wake word. `HEARD <text>` — a command, the same as
   a button or a typed answer (Step 3). When it cannot start, say so and go on without it.

## Step 3 — Run it

### The banner

Before each step, show or update the banner at the bottom of the page, exactly as test-in-env's
narration draws it (id `roi-qa-banner`, `pointer-events: none`, text set with `textContent`, shown
again after every full page load, `'top'` when it would cover what the step shows, never on a login
or another origin's page):

```js
((lines, position) => {
  let el = document.getElementById('roi-qa-banner');
  if (!el) {
    el = document.createElement('div');
    el.id = 'roi-qa-banner';
    el.setAttribute('aria-hidden', 'true');
    el.style.cssText = [
      'position:fixed', 'left:12px', 'right:12px', 'z-index:2147483647',
      'pointer-events:none', 'padding:8px 12px', 'border-radius:8px',
      'background:rgba(20,20,30,.88)', 'color:#fff',
      'font:13px/1.4 system-ui,sans-serif', 'box-shadow:0 2px 8px rgba(0,0,0,.3)',
    ].join(';');
    document.body.appendChild(el);
  }
  el.style.top = position === 'top' ? '12px' : '';
  el.style.bottom = position === 'top' ? '' : '12px';
  el.replaceChildren(...lines.map((text, i) => {
    const line = document.createElement('div');
    line.textContent = text;
    if (i === 0) line.style.fontWeight = '600';
    return line;
  }));
})(LINES, 'bottom')
```

`LINES`, three lines under about 90 characters each:

```text
F-1 · 1/3 · Pay part with a gift card
Step 2/4 · Apply the gift card code
Expected: the price stays, the card and the balance to pay appear below
```

The banner's text never counts as a result: check what the step shows outside it.

### The chat

Before the first flow, one line: how many flows and steps, and that the banner shows where the demo
is. Then, as test-in-env does:

```text
▶ F-1 (1/3) · Pay part with a gift card — the card is a payment, so the price stays
  1/4 Add an experience to the cart → ✅ cart with one line, 180 €
  2/4 Apply the gift card code → ✅ price 180 €, card −15 €, balance to pay 165 €
✅ F-1 shown
```

### The voice (`--voice`)

Say, with `wf-voice.sh say`, before each step what it does and what to watch for, and after it what
was seen. One idea per sentence, plain words, no ids, no codes, no URLs, numbers as people say them
("ciento ochenta euros"). The same sentence the banner and the chat show, said, not a second text.

### Findings and doubts

The moment something is not as expected — a control that does not appear, a wrong number, an error,
a step that cannot be done — say what was seen and that the demo pauses: on the banner, in the chat
(`❌` or `⏸` with the reason) and, with `--voice`, aloud. Then stop and wait for the user. Never carry
on silently.

### Waiting after each step (unless `--run`)

After each step's chat line, wait, leaving the page as it is. Offer the answers as buttons on the
banner — **Seguir**, **Repetir**, **Saltar**, **Parar** (or the user's language) — with
test-in-env's snippet: only the bar takes clicks, and `pointerdown`/`mousedown` are stopped so the
page keeps its focus and its open pickers.

```js
(() => {
  const el = document.getElementById('roi-qa-banner');
  if (!el) return 'no-banner';
  window.__roiQaAnswer = null;
  const bar = document.createElement('div');
  bar.style.cssText = 'display:flex;gap:8px;margin-top:6px;pointer-events:auto';
  for (const [label, value] of BUTTONS) {
    const b = document.createElement('button');
    b.type = 'button';
    b.textContent = label;
    b.style.cssText = 'cursor:pointer;border:0;border-radius:6px;padding:4px 12px;' +
      'color:#fff;background:#1e9e8a;font:600 12px system-ui';
    b.addEventListener('click', (e) => {
      e.stopPropagation();
      window.__roiQaAnswer = value;
      bar.textContent = '… ' + label;
    });
    bar.appendChild(b);
  }
  for (const type of ['pointerdown', 'mousedown']) {
    bar.addEventListener(type, (e) => { e.preventDefault(); e.stopPropagation(); });
  }
  el.appendChild(bar);
})()
```

`BUTTONS` = `[['Seguir', 'next'], ['Repetir', 'repeat'], ['Saltar', 'skip'], ['Parar', 'stop']]`.
Wait for the click in batches of three 25-second waits (the browser tool gives up on longer calls):

```js
await new Promise((resolve) => {
  const start = Date.now();
  const timer = setInterval(() => {
    if (window.__roiQaAnswer || Date.now() - start > 25000) {
      clearInterval(timer);
      resolve(window.__roiQaAnswer || 'waiting');
    }
  }, 250);
})
```

An answer comes from any of three places and they all count the same: the button, the chat, or —
with `--listen` — the voice (`HEARD`). A typed or spoken answer is read between batches, within
about a minute; say so once, at the first wait. Before asking again, read `window.__roiQaAnswer`:
a click made while you were not waiting is a valid answer.

| Answer | What to do |
|---|---|
| Go on ("seguí", "siguiente", "dale") | The next step |
| Repeat ("repetí") | The same step again, told again |
| Skip ("saltá") | Leave the flow (`⏸ skipped by the user`) and go to the next one |
| Stop ("pará", "terminá") | Step 4 |
| Pause ("pausa", "esperá") | Do nothing until another answer |
| A question | Answer in two or three sentences (aloud with `--voice`) and wait again |

## Step 4 — Close

Say a one-sentence summary of what was shown and of any finding (aloud with `--voice`), remove the
banner and, if voice or listening ran, `wf-voice.sh stop` and tell the user to pick their usual
microphone again. In the chat: what was shown, each finding with what to do about it, and anything
left changed for the demo (data, deploys, logins) with how to undo it.
