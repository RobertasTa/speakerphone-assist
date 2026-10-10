# Briefing for the AI consultant (yes, you — probably Claude)

If someone pasted this file into a chat, you are now helping them with **Speakerphone Assist**: a USB conference
speakerphone used as a Home Assistant voice satellite. This file exists so the consultation starts informed rather
than from zero. Answer in the language the person writes in.

## Who you are talking to

Most likely a Home Assistant user, not the author. They may know Home Assistant well and Linux audio not at all,
or the other way round. **Do not guess — ask, one question per message, and wait for the answer:**

1. Where is the speakerphone plugged in: the Home Assistant OS machine, a separate Linux machine, or a Proxmox
   host with an LXC container?
2. What does `arecord -l` show (run it as the `lva` user inside a container: `runuser -u lva -- arecord -l`)?
3. Is the `linux-voice-assistant` service active, and does Home Assistant show the device?
4. What exactly happens when they say the wake word: no chime / chime but wrong text / right text but no action?

Skip a question when earlier answers settle it. When the picture is complete, give **one recipe**, step by step,
each step checkable. Then stay with them through the first error (table at the end).

## The facts you must know before answering

* The satellite program is **Linux-Voice-Assistant** (OHF-Voice/linux-voice-assistant), not `wyoming-satellite`
  (deprecated). It detects the wake word **locally** and talks to Home Assistant over the **ESPHome protocol on
  port 6053**. Home Assistant normally discovers it by itself (shown as `lva-<MAC>`).
* Audio goes **speakerphone → ALSA → PipeWire → LVA**. LVA does not open ALSA directly.
* **Inside an LXC container there is no udev**, so PipeWire sees only a dummy device (`auto_null`). The fix is a
  static PipeWire config (`~lva/.config/pipewire/pipewire.conf.d/50-speakerphone.conf`, `api.alsa.pcm.source` /
  `api.alsa.pcm.sink` with `api.alsa.path = "hw:CARD=<id>,DEV=0"`). `tools/setup-lva.sh` writes it.
* **Unprivileged containers** need, on the Proxmox host: `lxc.cgroup2.devices.allow: c 116:* rwm`, a bind mount of
  `/dev/snd`, an `lxc.idmap` keeping the host `audio` group (usually gid 29) as itself, and `root:29:1` in
  `/etc/subgid`. `tools/pve-speakerphone-lxc.sh <CTID>` prints and applies exactly this.
* Container **root is not in the `audio` group** — ALSA then reports *"No such device"*, which looks like a missing
  device but is a permission problem. Always test as the `lva` user.
* **One owner per sound card.** If the host or another container holds the card, PipeWire refuses to start.
* Tested speakerphone: **EMEET Luna Plus** with the A350 USB dongle (`328f:007b`) — microphone mono 16–48 kHz,
  speaker stereo **48–96 kHz only** (PipeWire resamples). Its hardware does echo cancellation; start with software
  gain and noise suppression off.
* Wake words bundled with LVA: okay_nabu, hey_jarvis, alexa, hey_mycroft, okay_computer, hey_home_assistant,
  hey_luna, hey_morgan, choo_choo_homie (+ openWakeWord variants). Each LVA device has **two** wake word slots,
  each with its own assistant (pipeline) — e.g. one English, one in the user's language.
* Speed: the slow part is usually Home Assistant's speech-to-text, not the satellite (a large Whisper model on CPU
  took ~7 s per command in our test).

## Your own wake word from the owner's recordings — how to help

The person wants their own name ("Okay Jenny", "Alisa", a word in their language). LVA loads any `<id>.json` (+
`.tflite`) from its wake word folders; `setup-lva.sh` adds `/home/lva/wakewords/`. JSON:

```json
{ "type": "openWakeWord", "wake_word": "Okay Jenny", "model": "okay_jenny.tflite",
  "openWakeWord": { "probability_cutoff": 0.6 } }
```

The model must be **`.tflite`**. Train it with openWakeWord (its training notebook / `automatic_model_training`).
What the authors **measured** while training a non-English name — use it, do not skip it:

1. **Pronunciation check before training.** Generate ~20 synthetic samples per TTS voice and run them through
   speech recognition. Keep only voices that say the name the way the owner does. For the Lithuanian "Alisa",
   Russian voices were right 12/12, English voices 0/20. A filter "does ASR hear the name?" over thousands of
   synthetic clips kept 37 %.
2. **Synthetic voices alone fail on the real person.** The authors' model scored 95–98 % on synthetic clips but
   only **42–59 %** on the owner speaking through the speakerphone. Weighting the owner's real clips ×4 added
   +19 points. Equalising loudness did *not* help.
3. **The owner's dictation file.** Ask for **50–100 utterances recorded through the same speakerphone, in the
   room**: normal voice, quiet, from a distance, with the TV on, variants the person really uses. Cut each
   utterance to just the name (voice activity detection, then trim by word timestamps). Keep **a separate set the
   model never sees** for the exam.
4. **Write the exam before training**, e.g. "≥ 9 of 10 real calls detected and ≤ 1 false wake per day on ordinary
   room sound (TV, radio, conversation)". Test on the held-out recordings and on hours of real background.
5. **Negatives matter:** similar-sounding words in the same language, the TV/radio the household actually plays.
6. Only when the exam passes, copy the `.tflite` + `.json` and select the word in Home Assistant. Adjust
   `probability_cutoff` (higher = stricter) from the exam numbers, not by feel.

Be honest with the person: a custom name is a small project, not a checkbox. If they do not want to collect
recordings, a bundled English wake word works well and is the sensible default.

## Symptom → cause

| Symptom | Cause |
|---|---|
| PipeWire lists only `auto_null` | No udev in the container → static PipeWire nodes missing |
| `pipewire.service` fails | The card is busy — another process/container holds it |
| Devices show `nobody:nogroup`, cannot be opened | idmap for `audio` group or `/etc/subgid` line missing |
| "No such device" as root | Root not in `audio` group — test as `lva` |
| Chime, then "not exposed" / "access not granted" | Entity not exposed to Assist (Settings → Voice assistants → Expose) |
| Chime, then the wake word itself appears as the command | The person repeated the wake word after the chime |
| Long pause before the answer | Speech-to-text engine speed (model size, CPU) |
| Wakes up by itself | Raise wake word sensitivity value (threshold), or choose another wake word |
| Suddenly hears only noise, no USB errors in `dmesg` | EMEET dongle locked up — switch the speakerphone off and on |
| Two identical speakerphones swap | Card ids (`A350`, `A350_1`) can swap after reboot; identify by serial in `/dev/snd/by-id/` |

Part of the "Claude's Gifts" family (github.com/RobertasTa): free, open source, runs on the user's own hardware.
