#!/bin/bash
#
# wf-voice.sh — voice for live demos, used by /wf-demo.
#
# Speaks narration into a call (Slack, Meet, Zoom...) through a virtual microphone that mixes
# the user's own mic with the voice, and hears the user's spoken commands, only those that start
# with a wake word ("Claude, seguí"). Linux with PipeWire only.
#
# Usage:
#   wf-voice.sh config            print the resolved settings
#   wf-voice.sh check             what is missing to run (tools, venv, voice, speech model)
#   wf-voice.sh setup             install Piper and faster-whisper in their own venv and download
#                                 the voice and the speech model (network: ask the user first)
#   wf-voice.sh route             create the virtual mic "Mic+Voz" (user's mic + voice) for the
#                                 call app, and send the voice to the local output too
#   wf-voice.sh say <text>        speak <text>
#   wf-voice.sh listen            one line per phrase that starts with the wake word:
#                                 `HEARD <what follows the wake word>`; `READY` once listening
#   wf-voice.sh status            what is running
#   wf-voice.sh stop              remove the virtual mic and stop listening
#
# Settings: ~/.claude/workflow/voice.json, every key optional:
#   voice          Piper voice           (default es_MX-ald-medium, male, Latin American)
#   length_scale   >1 slower, <1 faster  (default 1.0)
#   language       speech recognition    (default es)
#   whisper_model  faster-whisper model  (default small, ~460 MB; base is lighter and worse)
#   wake           regex of wake words   (default claude|clod|cloud|clau)
#   mic            capture node name     (default the system's default source)
# WF_VOICE_HOME moves the install (default ~/.local/share/wf-voice).

set -u

HOME_DIR="${WF_VOICE_HOME:-$HOME/.local/share/wf-voice}"
CONF="${WF_VOICE_CONF:-$HOME/.claude/workflow/voice.json}"
RUN="$HOME_DIR/run"
VENV="$HOME_DIR/venv"

cfg() {
  local v=""
  [ -f "$CONF" ] && command -v jq >/dev/null 2>&1 && v="$(jq -r --arg k "$1" '.[$k] // empty' "$CONF" 2>/dev/null)"
  printf '%s' "${v:-$2}"
}

VOICE="$(cfg voice es_MX-ald-medium)"
LENGTH="$(cfg length_scale 1.0)"
LANGUAGE="$(cfg language es)"
WHISPER="$(cfg whisper_model small)"
WAKE="$(cfg wake 'claude|clod|cloud|clau')"
MIC="$(cfg mic '')"

# es_MX-ald-medium → es/es_MX/ald/medium/es_MX-ald-medium
voice_path() {
  local locale="${VOICE%%-*}" rest="${VOICE#*-}"
  printf '%s/%s/%s/%s/%s' "${locale%%_*}" "$locale" "${rest%-*}" "${rest##*-}" "$VOICE"
}

# The id of the node called $1, empty when there is none.
node_id() {
  pw-dump 2>/dev/null | python3 -c "
import json, sys
for o in json.load(sys.stdin):
    if ((o.get('info') or {}).get('props') or {}).get('node.name') == sys.argv[1]:
        print(o['id']); break
" "$1"
}

default_mic() {
  wpctl inspect @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | sed -n 's/.*node\.name = "\(.*\)"/\1/p' | head -1
}

cmd_config() {
  printf 'home=%s\nvoice=%s\nlength_scale=%s\nlanguage=%s\nwhisper_model=%s\nwake=%s\nmic=%s\n' \
    "$HOME_DIR" "$VOICE" "$LENGTH" "$LANGUAGE" "$WHISPER" "$WAKE" "${MIC:-default}"
}

cmd_check() {
  local missing=0 t
  for t in pw-loopback pw-play pw-record pw-dump wpctl python3 jq; do
    command -v "$t" >/dev/null 2>&1 || { echo "MISSING tool $t"; missing=1; }
  done
  [ -x "$VENV/bin/piper" ] || { echo "MISSING piper (wf-voice.sh setup)"; missing=1; }
  [ -f "$HOME_DIR/voices/$VOICE.onnx" ] || { echo "MISSING voice $VOICE (wf-voice.sh setup)"; missing=1; }
  "$VENV/bin/python" -c 'import faster_whisper' 2>/dev/null || { echo "MISSING faster-whisper (wf-voice.sh setup)"; missing=1; }
  ls "$HOME_DIR/whisper/"*"$WHISPER"* >/dev/null 2>&1 || { echo "MISSING speech model $WHISPER (wf-voice.sh setup)"; missing=1; }
  [ "$missing" = 0 ] && echo "OK"
  return "$missing"
}

cmd_setup() {
  set -e
  mkdir -p "$HOME_DIR/voices" "$HOME_DIR/whisper" "$RUN"
  [ -x "$VENV/bin/python" ] || python3 -m venv "$VENV"
  "$VENV/bin/pip" install -q --disable-pip-version-check piper-tts faster-whisper numpy
  local base="https://huggingface.co/rhasspy/piper-voices/resolve/main/$(voice_path)"
  [ -f "$HOME_DIR/voices/$VOICE.onnx" ] || curl -sSfL -o "$HOME_DIR/voices/$VOICE.onnx" "$base.onnx"
  [ -f "$HOME_DIR/voices/$VOICE.onnx.json" ] || curl -sSfL -o "$HOME_DIR/voices/$VOICE.onnx.json" "$base.onnx.json"
  "$VENV/bin/python" -c "
from faster_whisper import WhisperModel
WhisperModel('$WHISPER', device='cpu', compute_type='int8', download_root='$HOME_DIR/whisper')
"
  set +e
  cmd_check
}

start_bg() { # name, pw-loopback args...
  local name="$1"; shift
  setsid nohup pw-loopback "$@" >/dev/null 2>&1 &
  echo "$!" >> "$RUN/pids"
}

cmd_route() {
  mkdir -p "$RUN"
  if [ -n "$(node_id wfv_tts)" ]; then echo "ROUTED (already)"; return 0; fi
  local mic="${MIC:-$(default_mic)}"
  [ -n "$mic" ] || { echo "No microphone found: set \"mic\" in $CONF" >&2; return 1; }
  : > "$RUN/pids"
  # The call app's microphone: whatever reaches the sink wfv_voz.
  start_bg voz --capture-props='media.class=Audio/Sink node.name=wfv_voz node.description=Voz' \
               --playback-props='media.class=Audio/Source node.name=wfv_mic node.description=Mic+Voz'
  sleep 0.5
  # The user's own mic, into it.
  start_bg mic --capture-props="target.object=$mic node.name=wfv_mic_in" \
               --playback-props='target.object=wfv_voz node.name=wfv_mic_out'
  # The voice: its own sink, into the call and into whatever output is the default now,
  # so it follows the user taking the earbuds off.
  start_bg tts --capture-props='media.class=Audio/Sink node.name=wfv_tts node.description=TTS' \
               --playback-props='target.object=wfv_voz node.name=wfv_tts_call'
  sleep 0.5
  start_bg out --capture-props='stream.capture.sink=true target.object=wfv_tts node.name=wfv_tts_monitor' \
               --playback-props='node.name=wfv_tts_local'
  sleep 0.5
  [ -n "$(node_id wfv_mic)" ] && echo "ROUTED: pick \"Mic+Voz\" as the microphone in the call app" \
    || { echo "The virtual mic did not come up" >&2; return 1; }
}

cmd_say() {
  local text="$*" target f
  [ -n "$text" ] || { echo "Usage: wf-voice.sh say <text>" >&2; return 1; }
  mkdir -p "$RUN"
  f="$(mktemp --suffix=.wav)"
  # Raw output: `-f` keeps a single sentence. A second of silence first, so a Bluetooth output
  # or a suspended sink wakes up before the words.
  printf '%s\n' "$text" \
    | "$VENV/bin/piper" -m "$HOME_DIR/voices/$VOICE.onnx" --length-scale "$LENGTH" --output-raw 2>/dev/null \
    | "$VENV/bin/python" -c '
import json, sys, wave
rate = json.load(open(sys.argv[2])).get("audio", {}).get("sample_rate", 22050)
pcm = sys.stdin.buffer.read()
with wave.open(sys.argv[1], "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate)
    w.writeframes(b"\0" * (rate * 2) + pcm)
' "$f" "$HOME_DIR/voices/$VOICE.onnx.json"
  # The listener ignores the room while this file exists: it would hear the voice itself.
  touch "$RUN/speaking"
  target="$(node_id wfv_tts)"
  if [ -n "$target" ]; then pw-play --target "$target" "$f"; else pw-play "$f"; fi
  rm -f "$f" "$RUN/speaking"
}

cmd_listen() {
  mkdir -p "$RUN"
  local mic="${MIC:-$(default_mic)}"
  echo "$$" > "$RUN/listen.pid"
  exec "$VENV/bin/python" -u - "$mic" "$WHISPER" "$LANGUAGE" "$WAKE" "$RUN/speaking" "$HOME_DIR/whisper" <<'PY'
import os, re, subprocess, sys, time
import numpy as np
from faster_whisper import WhisperModel

mic, model_name, language, wake, lock, root = sys.argv[1:7]
model = WhisperModel(model_name, device="cpu", compute_type="int8", download_root=root)
wake_re = re.compile(r"^\W*(?:%s)\w*\W*" % wake, re.I)
rate, chunk = 16000, 1600                     # 0.1 s
rec = subprocess.Popen(["pw-record", "--target", mic, "--rate", str(rate), "--channels", "1",
                        "--format", "s16", "-"], stdout=subprocess.PIPE)
noise, muted_until, voiced, quiet = 300.0, 0.0, [], 0
print("READY", flush=True)
while True:
    data = rec.stdout.read(chunk * 2)
    if not data:
        break
    now = time.time()
    if os.path.exists(lock):                  # our own voice is playing
        muted_until, voiced, quiet = now + 0.8, [], 0
        continue
    if now < muted_until:
        continue
    samples = np.frombuffer(data, dtype=np.int16)
    level = float(np.sqrt(np.mean(samples.astype(np.float32) ** 2)))
    if not voiced:
        noise = 0.95 * noise + 0.05 * min(level, noise * 2)
    loud = level > max(500.0, noise * 3)
    if loud or voiced:
        voiced.append(samples)
        quiet = 0 if loud else quiet + 1
    if voiced and (quiet >= 8 or len(voiced) >= 150):   # 0.8 s of quiet, or 15 s
        audio = np.concatenate(voiced).astype(np.float32) / 32768.0
        voiced, quiet = [], 0
        if len(audio) < rate * 0.4:
            continue
        segments, _ = model.transcribe(audio, language=language, beam_size=1,
                                       initial_prompt="Claude, seguí. Claude, pausa.")
        text = " ".join(s.text.strip() for s in segments).strip()
        m = wake_re.match(text)
        if m and text[m.end():].strip():
            print("HEARD " + text[m.end():].strip(), flush=True)
PY
}

cmd_status() {
  [ -n "$(node_id wfv_mic)" ] && echo "route: up (Mic+Voz)" || echo "route: down"
  if [ -f "$RUN/listen.pid" ] && kill -0 "$(cat "$RUN/listen.pid")" 2>/dev/null; then
    echo "listen: running"; else echo "listen: stopped"; fi
}

cmd_stop() {
  local p
  if [ -f "$RUN/listen.pid" ]; then kill "$(cat "$RUN/listen.pid")" 2>/dev/null; rm -f "$RUN/listen.pid"; fi
  if [ -f "$RUN/pids" ]; then
    while read -r p; do [ -n "$p" ] && kill "$p" 2>/dev/null; done < "$RUN/pids"
    rm -f "$RUN/pids"
  fi
  # setsid's child may outlive the recorded pid: catch the loopbacks by their node names.
  for p in $(pgrep -f '^pw-loopback .*node\.name=wfv_'); do kill "$p" 2>/dev/null; done
  rm -f "$RUN/speaking"
  echo "STOPPED"
}

case "${1:-}" in
  config) cmd_config ;;
  check)  cmd_check ;;
  setup)  cmd_setup ;;
  route)  cmd_route ;;
  say)    shift; cmd_say "$@" ;;
  listen) cmd_listen ;;
  status) cmd_status ;;
  stop)   cmd_stop ;;
  *) sed -n '3,30p' "$0" | sed 's/^# \{0,1\}//'; [ -n "${1:-}" ] && exit 1 ;;
esac
