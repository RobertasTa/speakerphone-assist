# Speakerphone Assist

![Speakerphone Assist — robotinė ranka laiko kolonėlę, sujungtą su Home Assistant ženklu (iliustracija sukurta naudojant DI)](docs/banner.png)

**USB konferencinė kolonėlė kaip Home Assistant balso palydovas.** Pasakai žadinimo žodį, duodi komandą ir išgirsti
atsakymą. Oficiali Linux palydovo programa, teisingai prijungta ir suderinta, plius tai, ką sunku rasti užrašytą:
garsas Proxmox LXC konteineryje, PipeWire be udev ir savas žadinimo žodis.

🌐 [English](README.md) · **Lietuvių** · [Русский](README_ru.md)

> ℹ️ Sukurta naudojant DI: skriptus ir tekstus rašė Claude (Anthropic) kartu su Robertu, išbandyta su tikra įranga;
> iliustracija sukurta naudojant DI.

> Išbandyta 2026-10-10 su **EMEET Luna Plus** (A350 USB imtuvas) neprivilegijuotame **Proxmox LXC** konteineryje:
> „Okay Nabu" → signalas → *«Который час?»* („Kiek valandų?", klausta rusiškai) → atsakymą pasako kolonėlė.
> Žadinimo žodis atpažintas 3 kartus iš 3. Home Assistant įrenginį rado pats.

---

## Kodėl konferencinė kolonėlė

Konferencinė kolonėlė sukurta būtent tokiam darbui: mikrofonų masyvas, girdintis visą kambarį, aido slopinimas pačioje
įrangoje, garsus garsiakalbis ir vienas USB kištukas (arba mažas USB radijo imtuvas). Perki gatavą — nereikia
lituoti, ieškoti mikrofonų plokščių ar spausdinti korpuso.

## Kaip tai veikia

```
kolonėlė ──USB──► Linux (PipeWire) ──► Linux-Voice-Assistant ──ESPHome protokolas, prievadas 6053──► Home Assistant
    ▲                                                                                   (kalba → tekstas → ketinimas → balsas)
    └────────────────────────────── atsakymas balsu ◄──────────────────────────────────────────────┘
```

* **Linux-Voice-Assistant** (LVA) — oficiali Open Home Foundation palydovo programa (jos autoriai ją
  vis dar vadina *eksperimentine*)
  ([OHF-Voice/linux-voice-assistant](https://github.com/OHF-Voice/linux-voice-assistant)). Žadinimo žodį ji klausosi
  pačiame palydove, o su Home Assistant kalbasi ESPHome protokolu.
  Senesnis `wyoming-satellite` nebeprižiūrimas — naujų diegimų su juo nepradėkite.
* Visa kita daro Home Assistant jūsų Assist grandine (kalbos atpažinimas, pokalbis, balso sintezė).

## Pasirinkite kelią

| Jūsų įranga | Ką daryti |
|---|---|
| Kolonėlė įjungta į **Home Assistant OS** kompiuterį | Oficiali **Assist Satellite** programėlė iš [OHF-Voice/apps](https://github.com/OHF-Voice/apps). *Mes jos nebandėme.* |
| Paprastas **Linux** kompiuteris (mini PC, VM, 64 bitų Raspberry Pi) | Ten PipeWire kolonėlę randa pats — sekite [oficialų diegimo vadovą](https://github.com/OHF-Voice/linux-voice-assistant/blob/main/docs/install.md), o derinkite kaip žemiau. Mūsų `setup-lva.sh` sukurtas ir išbandytas konteineriams. |
| **Proxmox** su LXC konteineriu | 1–4 žingsniai žemiau. ✅ *Būtent tai mes išbandėme.* |

## Prieš pradedant

1. **Tik EMEET:** kolonėlei vardą duokite ir programinę įrangą atnaujinkite programa EMEETLINK **prieš** įjungdami
   imtuvą į serverį. Programa yra tik Windows ir macOS, ji jungiasi per USB laidą.
2. **Sužinokite kortos ID.** Įjunkite kolonėlę į Linux kompiuterį ir paleiskite `arecord -l`:
   `card 2: A350 [EMEET Adapter A350], device 0: USB Audio` → kortos ID yra **`A350`**.
3. **Viena korta — vienas šeimininkas.** Kolonėlės neturi naudoti niekas kitas (serveris, kitas konteineris, kita
   programa). Jei kas nors ją laiko, PipeWire nepasileis.

## Žingsnis po žingsnio (Proxmox LXC)

**1. Sukurkite konteinerį** — Ubuntu 24.04 šablonas, *unprivileged*, *nesting* įjungtas, 2 branduoliai, 2 GB RAM,
8 GB disko. Palikite jį **sustabdytą**.

**2. Proxmox serveryje** duokite konteineriui garso įrenginius:

```bash
./pve-speakerphone-lxc.sh 120            # bandymas: parodo garso kortas ir ką pridės
./pve-speakerphone-lxc.sh 120 --apply    # įrašo (prieš tai pasidaro seno konfigo kopiją)
```

Į `/etc/pve/lxc/120.conf` jis prideda tris dalykus — leidimą ALSA įrenginiams (`c 116:*`), `/dev/snd` prijungimą ir
**`audio` grupės atvaizdavimą (idmap)** — o į `/etc/subgid` atitinkamą eilutę `root:29:1`. Be atvaizdavimo
neprivilegijuotas konteineris mato įrenginius kaip `nobody:nogroup` ir negali jų atidaryti.

**3. Konteinerio viduje:**

```bash
./setup-lva.sh --card A350 --name svetaine
```

Jis įdiegia PipeWire ir LVA, sukuria naudotoją `lva`, **aprašo kolonėlę PipeWire'ui statiškai** (žr. „Gedimai" —
konteineriuose nėra udev) ir paleidžia servisą `linux-voice-assistant`.
Parinktys: `--wake hey_jarvis` (žadinimo žodis), `--user`, `--ref` (LVA versija).

**4. Home Assistant:** *Nustatymai → Įrenginiai ir paslaugos → Aptikta → **lva-‹MAC adresas›** (ESPHome) → Pridėti.*
Pridėtas įrenginys gauna vardą, kurį davėte su `--name`. Jei nieko neaptinka:
*Pridėti integraciją → ESPHome →* konteinerio IP, prievadas `6053`.

## Suderinimas Home Assistant

Viskas — įrenginio puslapyje, failų redaguoti nereikia.

| Nustatymas | Ką daro | Mūsų patarimas |
|---|---|---|
| **Asistentas** (×2) | Kuri Assist grandinė atsako | Du lizdai: vienas žadinimo žodis gali naudoti anglišką asistentą, kitas — kitos kalbos |
| **Žadinimo žodis** (×2) | Įmontuoti: Okay Nabu, Hey Jarvis, Alexa, Hey Mycroft, Okay Computer, Hey Home Assistant, **Hey Luna**, … | „Hey Luna" tinka EMEET Luna 🙂 |
| **Žadinimo žodžio jautrumas** | Atpažinimo slenkstis (didesnis = griežčiau) | Pabunda pati → didinkite. Jūsų negirdi → šiek tiek mažinkite |
| **Mikrofono garsumas / automatinis stiprinimas / triukšmo slopinimas** | Programinis apdorojimas prieš žadinimo žodį | Kolonėlė garsą jau išvalo — pradėkite su stiprinimu ir slopinimu **išjungtais** |
| **„Baigė kalbėti" aptikimas** | Kada nusprendžia, kad nustojote kalbėti | *relaxed*, jei nukerta; *aggressive* — greitesniems atsakymams |
| **Nutildymas**, **„galvojimo" garsas** | Mikrofonas išjungtas; garsas laukiant | — |

Trys dalykai, kurių tame puslapyje **nėra**, bet jie svarbūs:

* **Atidarykite įrenginius Assist'ui** (*Nustatymai → Balso asistentai → Atidaryti / Expose*). Kitaip palydovas jus
  supras puikiai, o Home Assistant atsakys, kad prieigos prie įrenginio neturi.
* **Lėčiausia vieta — kalbos atpažinimas, ne palydovas.** Mūsų bandyme didelis Whisper modelis procesoriuje vienai
  komandai užtruko ~7 s. Mažesnis modelis, GPU arba *Speech-to-Phrase* namų komandoms — ir atsakymas gerokai greitesnis.
  Lietuviškai: [LT_ausys](https://github.com/RobertasTa/lt-ausys) — apie 0,2 s komandai procesoriuje.
* **Po signalo sakykite tik komandą.** Pakartotas žadinimo žodis tampa komanda.

Garsiakalbio garsumas: medijos grotuvo garsumas Home Assistant ir aparatinis lygis `alsamixer -c <kortos ID>`
(valdiklis `PCM`). Mikrofono aparatinis lygis: valdiklis `Mic` (mūsų kolonėlėje 85 %).

## Savas žadinimo žodis („Okay Jenny", „Alisa", …)

LVA įkelia kiekvieną `*.json`, kurį randa savo žadinimo žodžių aplankuose; kiekvienas atsiranda Home Assistant
žadinimo žodžių sąraše. `setup-lva.sh` jūsų modeliams prideda aplanką `~lva/wakewords`. Du modelių tipai:

```json
{ "type": "openWakeWord", "wake_word": "Okay Jenny", "model": "okay_jenny.tflite",
  "openWakeWord": { "probability_cutoff": 0.6 } }
```

```json
{ "type": "micro", "wake_word": "Okay Jenny", "model": "okay_jenny.tflite",
  "micro": { "probability_cutoff": 0.85, "feature_step_size": 10, "sliding_window_size": 5 } }
```

Įdėkite `okay_jenny.json` ir `okay_jenny.tflite` į `/home/lva/wakewords/`, paleiskite
`systemctl restart linux-voice-assistant` ir pasirinkite žodį Home Assistant. Modelis turi būti **`.tflite`**.
openWakeWord mokymas (žemiau) duoda pirmojo tipo modelį; antrasis — microWakeWord modeliams.

**Kaip pasidaryti modelį.** [openWakeWord](https://github.com/dscripka/openWakeWord) mokymo užrašų knygelė sukuria
tūkstančius sintetinių balsų, sakančių jūsų frazę, ir išmoko mažą modelį (apie valandą su GPU arba Colab).
Ką išmatavome mokydami savo ne anglišką vardą:

* **Pirma patikrinkite tarimą.** Sugeneruokite kelis pavyzdžius ir praleiskite per kalbos atpažinimą. Ne angliškam
  vardui kitos kalbos balsai gali ištarti geriau: „Alisą" geriausias rusiškas balsas tarė teisingai 12 iš 12
  (kiti rusiški — daug prasčiau), angliški — 0 iš 20.
* **Vien sintetinių balsų neužtenka.** Mūsų modelis sintetinius pavyzdžius atpažino 95–98 %, o tikrą žmogų per
  kolonėlę — tik 43–59 %. Pridėkite 50–100 *savo* balso įrašų, padarytų **per tą pačią kolonėlę**.
* **Egzaminą užsirašykite prieš mokymą**, pvz., „ne mažiau kaip 9 iš 10 tikrų kreipinių, ne daugiau kaip 1 klaidingas
  pažadinimas per parą", ir tikrinkite įrašais, kurie mokyme *nedalyvavo*.

Prašote DI asistento pagalbos? Duokite jam [AI_CONSULTANT_BRIEF.md](AI_CONSULTANT_BRIEF.md) — ten šis metodas.

## Gedimai

| Požymis | Priežastis ir sprendimas |
|---|---|
| PipeWire rodo tik netikrą įrenginį (`auto_null`) | Konteineriuose nėra udev, todėl PipeWire kortos neranda. `setup-lva.sh` prideda statinius mazgus (`~lva/.config/pipewire/pipewire.conf.d/50-speakerphone.conf`). |
| PipeWire nepasileidžia | Dažniausiai korta užimta — ją laiko kas nors kitas. Žr. `journalctl --user -u pipewire`. |
| Įrenginiai konteineryje priklauso `nobody:nogroup` | Trūksta `audio` grupės atvaizdavimo arba `/etc/subgid` eilutės — paleiskite `pve-speakerphone-lxc.sh` dar kartą. |
| `arecord`/`aplay` kaip root konteineryje sako **„No such device"** | Įrenginys yra — konteinerio root nėra `audio` grupėje. Tikrinkite kaip `lva`: `runuser -u lva -- arecord -l`. |
| „Prieiga prie … nesuteikta" / „not exposed" | Atidarykite įrenginį Assist'ui (žr. aukščiau). |
| `Failed to load cookie file` | Nekenksminga. |
| Garsiakalbis nepriima 16 kHz | EMEET tai normalu (groja 48–96 kHz). PipeWire perskaičiuoja. |
| Staiga „girdi" tik triukšmą, USB klaidų nėra | EMEET imtuvas gali užstrigti neatsijungdamas. Išjunkite ir vėl įjunkite kolonėlę. |
| Kurčias po to, kai imtuvas dingo iš USB (`dmesg` rodo USB atsijungimą ir prisijungimą) | Tikėtina, kad garso serveris tebelaiko seną įrenginį. Perkraukite jį ir palydovą: `runuser -u lva -- env XDG_RUNTIME_DIR=/run/user/$(id -u lva) systemctl --user restart pipewire pipewire-pulse wireplumber && systemctl restart linux-voice-assistant`. Tai sutikome savo (ne LVA) kolonėlės sistemoje; su LVA neatkurta. |
| Dvi vienodos kolonėlės | Atskirkite pagal serijos numerį (`/dev/snd/by-id/`). Kortų ID (`A350`, `A350_1`) po perkrovimo gali susikeisti — paprasčiausia: viena kolonėlė vienam konteineriui. |

## Išbandyta su

| | |
|---|---|
| Kolonėlė | EMEET Luna Plus su A350 USB imtuvu (`328f:007b`): mikrofonas mono 16–48 kHz, garsiakalbis stereo 48–96 kHz |
| Serveris | Proxmox VE 9.2.6, neprivilegijuotas LXC, Ubuntu 24.04 |
| Programos | PipeWire 1.0.5, WirePlumber 0.4.17, Python 3.12, Linux-Voice-Assistant `b49fd8d` (2026-09-29) |
| Home Assistant | 2026.10.0 |
| Skriptai | `pve-speakerphone-lxc.sh` ir `setup-lva.sh` praeina iki galo švariame konteineryje — išbandyta su kompiuterio vidine garso korta, nes kolonėlė tuo metu buvo užimta; balso bandymas viršuje darytas tais pačiais žingsniais ranka (perduodant tik kolonėlės įrenginius, ne visą `/dev/snd`). `setup-lva.sh` galima leisti pakartotinai |

## Licencija

Šios saugyklos skriptai ir tekstai: **GPL-3.0-or-later**. Pats Linux-Voice-Assistant čia neįdėtas; diegimo skriptas
jį parsisiunčia iš jo paties saugyklos (Apache-2.0).
