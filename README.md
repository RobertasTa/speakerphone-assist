# Speakerphone Assist

![Speakerphone Assist — a robotic hand holds a speakerphone linked to the Home Assistant icon (illustration created with AI)](docs/banner.png)

**Use a USB conference speakerphone as a Home Assistant voice satellite** — say a wake word, give a command,
hear the answer. The official Linux satellite software, connected and tuned the right way, with the parts
that are hard to find written down: Proxmox LXC audio, PipeWire without udev, and your own wake word.

🌐 **English** · [Lietuvių](README_lt.md) · [Русский](README_ru.md)

> ℹ️ Made with AI: the scripts and texts were written by Claude (Anthropic) together with Robertas and tested on
> real hardware; the illustration was created with AI.

> Tested on 2026-10-10 with an **EMEET Luna Plus** (A350 USB dongle) in an unprivileged **Proxmox LXC** container:
> "Okay Nabu" → chime → *«Который час?»* ("What time is it?", asked in Russian) → the answer is spoken by the speakerphone.
> Wake word detected 3 times out of 3. Home Assistant found the device on its own.

---

## Why a conference speakerphone

A speakerphone is made for exactly this job: a microphone array that hears a whole room, echo cancellation in
hardware, a loud speaker and a single USB plug (or a small USB radio dongle). You buy it ready-made — no
soldering, no microphone boards, no 3D-printed case.

## How it works

```
speakerphone ──USB──► Linux (PipeWire) ──► Linux-Voice-Assistant ──ESPHome protocol, port 6053──► Home Assistant
     ▲                                                                                     (speech-to-text → intent → text-to-speech)
     └──────────────────────────────── spoken answer ◄─────────────────────────────────────────────┘
```

* **Linux-Voice-Assistant** (LVA) is the official satellite program from the Open Home Foundation, still marked
  *experimental* by its authors
  ([OHF-Voice/linux-voice-assistant](https://github.com/OHF-Voice/linux-voice-assistant)). It listens for the wake
  word on the satellite itself and talks to Home Assistant over the ESPHome protocol.
  The older `wyoming-satellite` is deprecated — do not start new installs with it.
* Home Assistant does the rest with your Assist pipeline (speech-to-text, conversation, text-to-speech).

## Choose your path

| Your setup | What to do |
|---|---|
| Speakerphone plugged into the **Home Assistant OS** machine | Use the official **Assist Satellite** app from [OHF-Voice/apps](https://github.com/OHF-Voice/apps). *Not tested by us.* |
| A normal **Linux** machine (mini PC, VM, 64-bit Raspberry Pi) | PipeWire finds the speakerphone by itself there — follow the [official install guide](https://github.com/OHF-Voice/linux-voice-assistant/blob/main/docs/install.md), then tune it as below. Our `setup-lva.sh` is made and tested for containers. |
| **Proxmox** with an LXC container | Steps 1–4 below. ✅ *This is what we tested.* |

## Before you start

1. **EMEET only:** name the speakerphone and update its firmware with the EMEETLINK app **before** you plug the
   dongle into the server. The app exists only for Windows and macOS and works over the USB cable.
2. **Find your card id.** Plug the speakerphone into the Linux machine and run `arecord -l`:
   `card 2: A350 [EMEET Adapter A350], device 0: USB Audio` → the card id is **`A350`**.
3. **One owner per card.** The speakerphone must not be used by anything else (the host, another container,
   another program). If something holds it, PipeWire will not start.

## Step by step (Proxmox LXC)

**1. Create a container** — Ubuntu 24.04 template, *unprivileged*, *nesting* on, 2 cores, 2 GB RAM, 8 GB disk.
Leave it **stopped**.

**2. On the Proxmox host**, give the container the sound devices:

```bash
./pve-speakerphone-lxc.sh 120            # dry run: lists your sound cards and shows what will be added
./pve-speakerphone-lxc.sh 120 --apply    # writes it (backs up the old config first)
```

It adds three things to `/etc/pve/lxc/120.conf` — access to ALSA devices (`c 116:*`), a bind mount of `/dev/snd`
and an **idmap for the `audio` group** — and the matching `root:29:1` line to `/etc/subgid`. Without the idmap an
unprivileged container sees the devices as `nobody:nogroup` and cannot open them.

**3. Inside the container:**

```bash
./setup-lva.sh --card A350 --name living-room
```

It installs PipeWire and LVA, creates the user `lva`, **describes the speakerphone to PipeWire statically**
(see Troubleshooting — containers have no udev) and starts the `linux-voice-assistant` service.
Options: `--wake hey_jarvis` (wake word), `--user`, `--ref` (LVA version).

**4. In Home Assistant:** *Settings → Devices & services → Discovered → **lva-‹MAC address›** (ESPHome) → Add.*
After adding, the device carries the name you gave with `--name`. If nothing is discovered:
*Add integration → ESPHome →* the container's IP, port `6053`.

## Tune it in Home Assistant

Everything is on the device page — no files to edit.

| Setting | What it does | Our advice |
|---|---|---|
| **Assistant** (×2) | Which Assist pipeline answers | Two slots: one wake word can use an English assistant, the other a different language |
| **Wake word** (×2) | Bundled: Okay Nabu, Hey Jarvis, Alexa, Hey Mycroft, Okay Computer, Hey Home Assistant, **Hey Luna**, … | "Hey Luna" suits an EMEET Luna 🙂 |
| **Wake word sensitivity** | The detection threshold (higher = stricter) | Wakes up by itself → raise it. Misses you → lower it a little |
| **Mic volume / auto gain / noise suppression** | Software processing before the wake word | A speakerphone already cleans the sound — start with gain and suppression **off** |
| **Finished speaking detection** | When it decides you have stopped talking | *relaxed* if it cuts you off, *aggressive* for faster answers |
| **Mute**, **thinking sound** | Microphone off; a sound while waiting | — |

Three things that are **not** on that page but matter:

* **Expose your devices to Assist** (*Settings → Voice assistants → Expose*). Otherwise the satellite understands
  you perfectly and Home Assistant answers that it has no access to the device.
* **Speech-to-text speed is the bottleneck, not the satellite.** In our test a large Whisper model on a CPU took
  ~7 s per command. A smaller model, a GPU or *Speech-to-Phrase* for home commands makes it much faster.
* **After the chime, say only the command.** Repeating the wake word turns it into the command.

Speaker volume: the media player volume in Home Assistant, and the hardware level with `alsamixer -c <card id>`
(control `PCM`). Microphone hardware level: control `Mic` (85 % on our unit).

## Your own wake word ("Okay Jenny", "Alisa", …)

LVA loads every `*.json` it finds in its wake word folders; each one appears in the Home Assistant wake word list.
`setup-lva.sh` adds the folder `~lva/wakewords` for your own models. Two model types:

```json
{ "type": "openWakeWord", "wake_word": "Okay Jenny", "model": "okay_jenny.tflite",
  "openWakeWord": { "probability_cutoff": 0.6 } }
```

```json
{ "type": "micro", "wake_word": "Okay Jenny", "model": "okay_jenny.tflite",
  "micro": { "probability_cutoff": 0.85, "feature_step_size": 10, "sliding_window_size": 5 } }
```

Put `okay_jenny.json` and `okay_jenny.tflite` into `/home/lva/wakewords/`, run
`systemctl restart linux-voice-assistant` and choose it in Home Assistant. The model must be **`.tflite`**.
openWakeWord training (below) gives you the first kind; the second is for microWakeWord models.

**Making the model.** The [openWakeWord](https://github.com/dscripka/openWakeWord) training notebook creates
thousands of synthetic voices saying your phrase and trains a small model (about an hour on a GPU or in Colab).
What we measured while training our own non-English name:

* **Check the pronunciation first.** Generate a few samples and run them through speech recognition. For a
  non-English name, voices of another language may say it better: for "Alisa" the best Russian voice was right 12/12
  (other Russian voices far less), English ones 0/20.
* **Synthetic voices alone are not enough.** Our model recognised synthetic samples 95–98 % of the time, but a
  real person through the speakerphone only 43–59 %. Add 50–100 recordings of *your own* voice made **through the
  same speakerphone**.
* **Write the exam before training:** for example "at least 9 of 10 real calls, at most 1 false wake a day", and test
  on recordings that were *not* used for training.

Asking an AI assistant for help? Give it [AI_CONSULTANT_BRIEF.md](AI_CONSULTANT_BRIEF.md) — it contains this method.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| PipeWire shows only a dummy device (`auto_null`) | Containers have no udev, so PipeWire cannot discover the card. `setup-lva.sh` adds static nodes (`~lva/.config/pipewire/pipewire.conf.d/50-speakerphone.conf`). |
| PipeWire does not start | Most often the card is busy — something else has it open. Check `journalctl --user -u pipewire`. |
| Devices inside the container belong to `nobody:nogroup` | The `audio` group idmap or the `/etc/subgid` line is missing — run `pve-speakerphone-lxc.sh` again. |
| `arecord`/`aplay` as root inside the container says **"No such device"** | Not a missing device — container root is not in the `audio` group. Test as the `lva` user: `runuser -u lva -- arecord -l`. |
| "Access to … is not granted" / "not exposed" | Expose the device to Assist (see above). |
| `Failed to load cookie file` | Harmless. |
| The speaker refuses 16 kHz | Normal for EMEET (plays 48–96 kHz). PipeWire resamples. |
| It suddenly "hears" only noise, no USB errors | The EMEET dongle can lock up without disconnecting. Switch the speakerphone off and on. |
| Two identical speakerphones | Tell them apart by serial number (`/dev/snd/by-id/`). Card ids (`A350`, `A350_1`) may swap after a reboot — one speakerphone per container is the simplest setup. |

## Tested with

| | |
|---|---|
| Speakerphone | EMEET Luna Plus with A350 USB dongle (`328f:007b`): microphone mono 16–48 kHz, speaker stereo 48–96 kHz |
| Host | Proxmox VE 9.2.6, unprivileged LXC, Ubuntu 24.04 |
| Software | PipeWire 1.0.5, WirePlumber 0.4.17, Python 3.12, Linux-Voice-Assistant `b49fd8d` (2026-09-29) |
| Home Assistant | 2026.10.0 |
| Scripts | `pve-speakerphone-lxc.sh` and `setup-lva.sh` run end-to-end on a fresh container; `setup-lva.sh` is safe to run again |

## License

The scripts and texts in this repository: **GPL-3.0-or-later**. Linux-Voice-Assistant itself is not included; the
setup script downloads it from its own repository (Apache-2.0).
