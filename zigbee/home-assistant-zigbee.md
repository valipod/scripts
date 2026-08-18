# Home Assistant + Zigbee + Alexa + Google — Documentație completă

Setup funcțional pe DS920+ (10.0.0.20), coordinator SLZB-06U, expunere externă prin reverse proxy pe DS918+.

---

## 0. ABATERI DE LA DOCUMENTAȚIA OFICIALĂ

Ce e scris mai jos e ce a **funcționat efectiv**, nu ce spun ghidurile. Punctele astea au fost blocante — dacă urmezi documentația oficială, te oprești la fiecare.

### 0.1 Alexa: regiunea Lambda — cel mai costisitor punct

| Documentația oficială | Ce a funcționat |
|---|---|
| EU → un singur Lambda în `eu-west-1` | **Două** funcții identice: `eu-west-1` **și** `us-east-1` |
| Client ID `https://layla.amazon.com/` pentru EU | `https://pitangui.amazon.com/` (endpoint nord-american) |

Contul Amazon poate fi rutat prin America de Nord chiar dacă dispozitivele și utilizatorul sunt în Europa, iar limba e English (US).

**Simptomul exact:** skill linkat cu succes, account linking OK, `discover devices` nu găsește nimic — **și CloudWatch nu are niciun log stream**. Adică Alexa nu invocă Lambda niciodată. Nu e o eroare, e tăcere completă.

**Indiciul decisiv:** dacă la account linking `layla` dă „Invalid redirect uri" iar `pitangui` merge, contul e rutat prin NA. Atunci slotul *North America* din skill trebuie completat — iar Amazon îl validează prin regex și acceptă **exclusiv** ARN din `us-east-1`. De aici necesitatea celei de-a doua funcții.

Diagnosticul care economisește ore: **verifică întâi dacă există log stream în CloudWatch.** Absența lui separă „problemă între Alexa și Lambda" de „problemă în cod sau în HA". Fără asta se caută degeaba în configul HA.

### 0.2 Google: consola s-a mutat

Ghidurile vechi trimit la **Actions on Google console**. Procedura reală e în **Google Home Developer Console** (`console.home.google.com`), ca *Cloud-to-Cloud integration*.

### 0.3 Google: proiectul se creează în altă parte

Documentația spune „Create project" direct în consola Home. În realitate dă **„Project Name already exists"** la orice nume plauzibil — consola Home validează *numele afișat*, iar „Home Assistant" e luat de integrarea oficială Nabu Casa.

**Ce funcționează:** creezi proiectul în **Cloud Console** (`console.cloud.google.com/projectcreate`), unde sufixul numeric se generează automat, apoi îl aduci prin **Add to an existing project → Import**.

Dacă ai deja un proiect cu display name conflictual: IAM & Admin → Settings → schimbi *Project name*. Project ID-ul rămâne, deci nimic din configul ulterior nu se strică.

### 0.4 Google: „Client ID" nu e Project ID

Tooltip-ul Amazon/Google sugerează un identificator arbitrar. E de fapt URL-ul de redirect complet:

```
https://oauth-redirect.googleusercontent.com/r/<PROJECT_ID>
```

HA îl validează prin IndieAuth — originea trebuie să corespundă cu redirectul primit.

### 0.5 Template switches: schema veche nu mai merge

Toate ghidurile pentru Harmony folosesc `switch: - platform: template`. HA răspunde:

```
Configuring the template integration under the switch platform key is not supported
```

Corect e `template:` → `- switch:` → `- name:` cu `state:` (nu `switches:` cu `value_template:`).

### 0.6 Shelly Gen4 pe Zigbee: setările nu se aplică prin MQTT

Documentația Z2M sugerează că `switch_type_sw1` se setează prin publicare MQTT. În practică rămâne `unknown` și **nu are efect** — becul continuă să urmeze poziția intrării.

**Ce funcționează:** configurezi prin interfața web pe **WiFi** (Input mode + Output type), apoi dezactivezi WiFi și rămâi pe Zigbee. **Setările persistă în firmware**, independent de calea de comunicație. Verificat pe ambele module.

Pe Zigbee nu există deloc opțiunea *Edge* — doar toggle/momentary.

### 0.7 AWS: planul contului

Nemenționat nicăieri, dar critic: **Free plan (6 luni) închide contul automat** la expirare, deci skill-ul ar înceta să funcționeze. Alege **Paid** — e pay-as-you-go, iar Lambda are 1M cereri gratuite lunar (tu faci câteva mii).

### 0.8 Autentificare: username, nu email

Ambele integrări cer login în HA la account linking. Emailul dă „Invalid username or password", indiferent că e corect în alte contexte.

### 0.9 AWS: triggerul s-a consolidat

Ghidurile spun „alege *Alexa Smart Home* ca sursă". Acum se alege **Alexa**, apoi sub-opțiunea *Alexa Smart Home*. La Smart Home nu apare opțiunea *Skill ID verification* — Skill ID-ul e obligatoriu oricum.

### 0.10 Consolele nu confirmă salvările

Google Home Developer Console salvează frecvent fără confirmare și **fără să persiste** — mai ales la *scan configuration* pentru local fulfillment. **Dă refresh și verifică** după fiecare Save.

### 0.11 Google Assistant nu suportă româna

Toate numele expuse trebuie în engleză. Și `room:` din YAML e doar o sugestie la prima sincronizare, ignorată frecvent — atribuirea reală a camerei se face în aplicație.

---

## 1. ARHITECTURĂ

```
SLZB-06U (10.0.0.169:6638)
    ↓ Zigbee
Zigbee2MQTT (:8080)
    ↓ MQTT
Mosquitto (:1883)
    ↓
Home Assistant (:8123)
    ↓                    ↓
Alexa (Lambda)      Google (HomeGraph)
```

Toate cele trei containere rulează pe DS920+, în `/volume1/docker/zigbee/`.

**Componente fizice:**

| Dispozitiv | Adresă | Rol |
|---|---|---|
| DS920+ | 10.0.0.20 | HA / Z2M / Mosquitto |
| DS918+ | 10.0.0.10 | Reverse proxy (443 → 8123) |
| SLZB-06U | 10.0.0.169 | Coordinator Zigbee (CC2652P) |
| DS414j | 10.0.0.11 | Alimentare USB pentru SLZB |

---

## 2. STACK DOCKER

Director: `/volume1/docker/zigbee/` (lowercase, obligatoriu)

**Servicii:**
- `mosquitto` — eclipse-mosquitto, port 1883, `allow_anonymous`
- `zigbee2mqtt` — koenkk, port 8080, adapter `tcp://10.0.0.169:6638`, tip `zstack`
- `homeassistant` — ghcr.io stable, `network_mode: host`

**Comenzi uzuale:**

```bash
# Validare config
sudo docker exec homeassistant python -m homeassistant --script check_config -c /config

# Restart
sudo docker restart homeassistant

# Loguri
sudo docker logs --tail 100 homeassistant

# Status containere
sudo docker ps --format '{{.Names}}\t{{.Status}}'

# Contor reporniri automate
for c in $(sudo docker ps -q); do sudo docker inspect -f '{{.Name}} {{.RestartCount}} {{.State.StartedAt}}' $c; done
```

**Interfețe:**
- Z2M: `http://10.0.0.20:8080`
- HA: `http://10.0.0.20:8123`
- HA extern: `https://ha.valipod.synology.me`

---

## 3. COORDINATOR SLZB-06U

- **Cip:** CC2652P (matur, complet suportat). Evită 06MU (EFR32, experimental) și MR3U/P10 (instabil)
- **IP static:** 10.0.0.169, mod Zigbee Coordinator, port 6638, 115200 baud
- **Adresă:** `0x00124b0037e64a27`, firmware ZStack3x0
- **Amplasare:** central, sufragerie, alimentat USB de la DS414j + Ethernet
- **NU adăuga ZHA în HA** — conflict cu Z2M pe același coordinator
- Integrarea SMLIGHT în HA oferă doar senzori hardware (temperatură ~43-45°C)

### Verificare topologie mesh

Z2M → **Network** → Type: `Display data/map`, Enable routes bifat → **Load** → Display type: Map.

Valorile LQI din **Dashboard** nu sunt de încredere pentru calitatea legăturii curente — pot fi valori vechi de pe căi secundare. Harta din Network arată LQI-ul real per segment, plus părintele fiecărui nod.

O rețea „plată" (toate nodurile direct la coordinator) e normală într-un spațiu mic — Zigbee alege calea cu cel mai mic cost, iar un salt direct bun bate două salturi prin repetoare. Routerele intră în joc doar când legătura directă se degradează.

---

## 4. CONFIGURATION.YAML

Cale: `/volume1/docker/zigbee/homeassistant/config/configuration.yaml`

```yaml
default_config:

http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 10.0.0.10
    - 127.0.0.1

alexa:
  smart_home:
    filter:
      include_entities:
        - light.ikea_sufragerie
        - light.ikea_balcon
        - light.ikea_birou
        - switch.shelly_valentinul_meu
        - switch.shelly_bedroom
        - switch.tv
        - switch.movies
        - switch.computer
    entity_config:
      light.ikea_sufragerie:
        name: Living Room Light
      light.ikea_balcon:
        name: Balcony Light
      light.ikea_birou:
        name: Desk Light
      switch.shelly_valentinul_meu:
        name: Valentin Light
      switch.shelly_bedroom:
        name: Bedroom Light
      switch.tv:
        name: TV
      switch.movies:
        name: Movies
      switch.computer:
        name: Computer

google_assistant:
  project_id: home-assistant-valipod
  service_account: !include SERVICE_ACCOUNT.json
  report_state: true
  exposed_domains:
    - light
  entity_config:
    switch.shelly_valentinul_meu:
      expose: true
      name: Shelly Valentin
      room: Valentin
    switch.shelly_bedroom:
      expose: true
      name: Shelly Bedroom
      room: Bedroom
    light.ikea_sufragerie:
      name: Living Room Light
      room: Living Room
    light.ikea_balcon:
      name: Balcony Light
      room: Bedroom
    light.ikea_birou:
      name: Desk Light
      room: Valentin
    switch.tv:
      expose: true
      name: TV
      room: Living Room
    switch.movies:
      expose: true
      name: Movies
      room: Living Room
    switch.computer:
      expose: true
      name: Computer
      room: Living Room

template:
  - switch:
      - name: TV
        unique_id: harmony_tv
        state: "{{ is_state_attr('remote.panasonic', 'current_activity', 'TV') }}"
        turn_on:
          action: remote.turn_on
          target:
            entity_id: remote.panasonic
          data:
            activity: TV
        turn_off:
          action: remote.turn_off
          target:
            entity_id: remote.panasonic
      - name: Movies
        unique_id: harmony_movies
        state: "{{ is_state_attr('remote.panasonic', 'current_activity', 'Filme') }}"
        turn_on:
          action: remote.turn_on
          target:
            entity_id: remote.panasonic
          data:
            activity: Filme
        turn_off:
          action: remote.turn_off
          target:
            entity_id: remote.panasonic
      - name: Computer
        unique_id: harmony_computer
        state: "{{ is_state_attr('remote.panasonic', 'current_activity', 'Computer') }}"
        turn_on:
          action: remote.turn_on
          target:
            entity_id: remote.panasonic
          data:
            activity: Computer
        turn_off:
          action: remote.turn_off
          target:
            entity_id: remote.panasonic

frontend:
  themes: !include_dir_merge_named themes
automation: !include automations.yaml
script: !include scripts.yaml
scene: !include scenes.yaml
```

### Diferență critică între cele două filtre

| | Alexa | Google |
|---|---|---|
| Mecanism | `include_entities` — **listă strictă** | `exposed_domains` — **permisiv pe domeniu** |
| Entitate absentă din listă | nu ajunge deloc | ajunge, cu nume implicit |
| `entity_config` | doar redenumește ce a trecut de filtru | idem |

Consecință: la Alexa, orice entitate nouă trebuie adăugată **și** în `include_entities`. La Google, `switch.*` nu e în `exposed_domains`, deci fiecare switch are nevoie de `expose: true`.

---

## 5. EXPUNERE EXTERNĂ

Reverse proxy pe DS918+: `ha.valipod.synology.me:443` → `http://10.0.0.20:8123`

- **WebSocket Custom Headers obligatorii**, altfel ecran alb:
  - `Upgrade` = `$http_upgrade`
  - `Connection` = `$connection_upgrade`
- HSTS OFF
- Wildcard `*.valipod.synology.me` (Let's Encrypt) acoperă certul automat
- Coexistă cu WordPress pe 443 prin SNI

**IMPORTANT pentru local fulfillment:** HA **nu** trebuie să aibă `ssl_certificate` în blocul `http:`. Difuzoarele Google se conectează direct la `10.0.0.20:8123` pe HTTP simplu. SSL-ul se face exclusiv în reverse proxy.

**Test endpoint (din exterior):**
```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://ha.valipod.synology.me/api/google_assistant
```
`405` (Method Not Allowed la GET) = corect. `404` = integrarea nu s-a încărcat. `502` sau pagină de login = problemă la reverse proxy.

---

## 6. GOOGLE ASSISTANT

### 6.1 Proiect Cloud

Proiectul se creează în **Cloud Console**, nu în Home Developer Console.

1. `console.cloud.google.com/projectcreate`
2. Nume: **NU** „Home Assistant" — numele afișat e validat ca unic în consola Home, iar acela e luat de integrarea oficială Nabu Casa. Folosește ceva ca `HA Valipod`.
3. Notează **Project ID** (ex. `home-assistant-valipod`) — intră în `configuration.yaml` și în URL-ul OAuth

Dacă ai deja proiectul cu nume greșit: Cloud Console → **IAM & Admin → Settings** → schimbă *Project name*. ID-ul rămâne neschimbat.

### 6.2 Import în Home Developer Console

1. `console.home.google.com/projects` → **Add to an existing project** → selectează → **Import project**
2. **Add a Cloud-to-Cloud integration** → *Next: Develop* → *Next: Setup*

### 6.3 Setup & configuration

- **Integration name:** orice (apare în Google Home ca `[test] <nume>`)
- **Device type:** selectează tot
- **App icon:** PNG transparent **144×144 px**, numele fișierului trebuie să fie exact `<project-id>.png`

**Account Linking:**

| Câmp | Valoare |
|---|---|
| OAuth Client ID | `https://oauth-redirect.googleusercontent.com/r/home-assistant-valipod` |
| Client secret | orice șir fără caractere speciale (HA nu-l citește) |
| Authorization URL | `https://ha.valipod.synology.me/auth/authorize` |
| Token URL | `https://ha.valipod.synology.me/auth/token` |
| Cloud fulfillment URL | `https://ha.valipod.synology.me/api/google_assistant` |
| Scopes | `email`, `name` |
| HTTP basic auth header | **nebifat** |

Client ID **nu** e Project ID-ul — e URL-ul de redirect pe care Google îl trimite ca `client_id`, iar HA îl validează (IndieAuth).

Statusul rămâne **Draft** — corect și final pentru uz personal, nu se publică.

### 6.4 Service account + HomeGraph

1. Cloud Console → **IAM & Admin → Service Accounts → Create**
2. Rol: **Service Account Token Creator**
3. Tab **Keys → Add key → JSON** (ignoră avertismentul despre workload identity federation — nu se aplică unui container pe Synology)
4. Redenumește `SERVICE_ACCOUNT.json`, pune în folderul de config:
   ```bash
   chmod 600 /volume1/docker/zigbee/homeassistant/config/SERVICE_ACCOUNT.json
   ```
5. Caută **HomeGraph API** în Cloud Console → **Enable** (fără asta, `requestSync` dă 403)

### 6.5 Linkare

Google Home app → **Devices** → **+ Add** → **Works with Google Home** → caută `[test] <nume>`

- Loghează-te cu **username**, nu email
- Dacă HA e pe home screen-ul telefonului, șterge-l întâi — altfel se deschide PWA-ul și redirectul nu se întoarce
- Contul Google din telefon trebuie să fie cel din Developer Console

Sincronizare ulterioară: *„Hey Google, sync my devices"*

### 6.6 Local fulfillment

**Prerechizite:** difuzoarele Google pe același VLAN cu HA (mDNS nu trece între VLAN-uri), fără `ssl_certificate` în `http:`.

1. Descarcă `app.js`:
   ```bash
   wget https://github.com/NabuCasa/home-assistant-google-assistant-local-sdk/releases/latest/download/app.js
   ```
2. Developer Console → **Cloud-to-cloud → Develop → Edit** → derulează la **Local fulfillment**, pornește toggle-ul
3. Upload **același** `app.js` la ambele: *JavaScript targeting Node* și *JavaScript targeting Chrome*
4. Bifează **Support local queries**
5. **Add scan configuration** → protocol **mDNS**:
   - Device name: `_home-assistant._tcp.local`
   - **Add field** → *Name* → valoare (regex): `.*\._home-assistant\._tcp\.local`
6. **Save**, apoi **refresh la pagină** și verifică că a rămas — prima salvare eșuează frecvent fără mesaj clar
7. Restart HA, apoi restart fizic la difuzoarele Google (scoase din priză 10 s). Alternativ ~30 min de așteptare.

**Verificare că HA se anunță:**
```bash
avahi-browse -rt _home-assistant._tcp
```
Trebuie să apară hostname, `10.0.0.20`, port `8123`.

Câștigul real e ~200-500 ms. Recunoașterea vocală rămâne în cloud indiferent de setare.

---

## 7. ALEXA

Mai complex decât Google: cere cont AWS și funcție Lambda.

### 7.1 Skill

1. `developer.amazon.com` → verificare identitate → **Alexa Skills Kit** → **Create skill**
2. Nume: `Home Assistant`, limbă **English (US)**
3. Model: **Smart Home**. Hosting: **Provision your own**
4. Notează **Skill ID**: `amzn1.ask.skill.xxxxxxxx-...`

### 7.2 Cont AWS

Alege **Paid plan**, nu Free. Free plan închide contul automat după 6 luni, iar skill-ul ar înceta să funcționeze. Paid = pay-as-you-go; Lambda are 1M cereri gratuite lunar, tu faci câteva mii.

### 7.3 Funcție Lambda

**Se creează DOUĂ funcții identice**, în `eu-west-1` (Ireland) și `us-east-1` (N. Virginia). Vezi 7.5 pentru motiv.

Pentru fiecare regiune:

1. Lambda → **Create function** → Author from scratch
2. Name `HomeAssistant`, Runtime Python 3.14, arhitectură x86_64 (default, sub *Additional settings*)
3. Rolul IAM se generează automat — corect așa

**Cod** (`lambda_function.py`, apoi **Deploy**):

```python
import json
import logging
import os
import urllib3

_debug = bool(os.environ.get("DEBUG"))

_logger = logging.getLogger("HomeAssistant-SmartHome")
_logger.setLevel(logging.DEBUG if _debug else logging.INFO)


def lambda_handler(event, context):
    """Handle incoming Alexa directive."""
    _logger.debug("Event: %s", event)

    base_url = os.environ.get("BASE_URL")
    assert base_url is not None, "Please set BASE_URL environment variable"
    base_url = base_url.strip("/")

    directive = event.get("directive")
    assert directive is not None, "Malformatted request - missing directive"
    assert directive.get("header", {}).get("payloadVersion") == "3", "Only support payloadVersion == 3"

    scope = directive.get("endpoint", {}).get("scope")
    if scope is None:
        scope = directive.get("payload", {}).get("grantee")
    if scope is None:
        scope = directive.get("payload", {}).get("scope")

    assert scope is not None, "Malformatted request - missing endpoint.scope"
    assert scope.get("type") == "BearerToken", "Only support BearerToken"

    token = scope.get("token")
    if token is None and _debug:
        token = os.environ.get("LONG_LIVED_ACCESS_TOKEN")

    verify_ssl = not bool(os.environ.get("NOT_VERIFY_SSL"))

    http = urllib3.PoolManager(
        cert_reqs="CERT_REQUIRED" if verify_ssl else "CERT_NONE",
        timeout=urllib3.Timeout(connect=2.0, read=10.0),
    )

    response = http.request(
        "POST",
        f"{base_url}/api/alexa/smart_home",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        body=json.dumps(event).encode("utf-8"),
    )
    if response.status >= 400:
        return {
            "event": {
                "payload": {
                    "type": "INVALID_AUTHORIZATION_CREDENTIAL"
                    if response.status in (401, 403)
                    else "INTERNAL_ERROR",
                    "message": response.data.decode("utf-8"),
                }
            }
        }
    return json.loads(response.data.decode("utf-8"))
```

**Variabilă de mediu:** Configuration → Environment variables → `BASE_URL` = `https://ha.valipod.synology.me` (fără slash final)

**Trigger:** Configuration → Triggers → Add trigger → source **Alexa** → product **Alexa Smart Home** → Skill ID

### 7.4 Endpoint-uri în skill

Build → **Smart Home**:

- Payload version: **v3**
- **Default endpoint:** ARN eu-west-1
- **Europe, India:** ARN eu-west-1
- **North America:** ARN us-east-1

⚠️ Amazon validează prin regex: slotul North America acceptă **exclusiv** ARN din `us-east-1`. De aceea trebuie a doua funcție Lambda.

### 7.5 De ce două regiuni

Contul Amazon poate fi rutat prin America de Nord chiar dacă dispozitivele sunt în Europa. Simptom: skill-ul e linkat corect, dar `discover devices` nu găsește nimic **și CloudWatch nu are niciun log stream** — adică Alexa nu invocă Lambda deloc.

Indiciu decisiv: dacă la account linking funcționează `pitangui.amazon.com` și nu `layla.amazon.com`, contul e rutat prin NA.

### 7.6 Account Linking

| Câmp | Valoare |
|---|---|
| Web Authorization URI | `https://ha.valipod.synology.me/auth/authorize` |
| Access Token URI | `https://ha.valipod.synology.me/auth/token` |
| Client ID | `https://pitangui.amazon.com/` (NA) sau `https://layla.amazon.com/` (EU) — **cu slash final** |
| Secret | orice |
| Authentication Scheme | **Credentials in request body** |
| Scope | `smart_home` |

Eroarea **„Invalid redirect uri"** înseamnă că user/parola au fost corecte, dar domeniul din Client ID nu corespunde cu ce a trimis Amazon. Schimbă între `pitangui` și `layla`.

Eroarea **„Invalid username or password"** e altceva — userul nu există. Folosește **username**, nu email.

### 7.7 Linkare și descoperire

Aplicația Alexa → **More → Skills & Games → Your Skills → tab Dev** → `Home Assistant` → **Enable** → login → autorizare.

Apoi: *„Alexa, discover devices"*

După orice modificare de endpoint în skill: **disable + enable** skill-ul, nu doar re-discover.

---

## 8. SHELLY 1 MINI GEN4 (S4SW-001X8EU)

Chip ESP32-C6. Default = Matter.

### Comutare mod
- **5 apăsări rapide** pe butonul fizic = comută în/din Zigbee
- **3 apăsări** = redeschide fereastra de inclusion
- Alternativ, din interfața web: meniul **Zigbee** → *Start pairing* / *Enable*

### Configurare intrare/ieșire

Setările **NU** sunt accesibile pe Zigbee — pe Zigbee, Z2M expune doar `switch_type_sw1` (toggle/momentary), fără Edge, iar valoarea rămâne adesea `unknown`.

**Procedura corectă:** configurează pe WiFi → apoi treci pe Zigbee. **Setările persistă în firmware**, independent de calea de comunicație.

Interfața web locală: `http://<ip-shelly>` → **Home** → click pe **Input (0)** → *Input/Output settings*

| Tip întrerupător perete | Input mode | Output type |
|---|---|---|
| Clasic (rămâne în poziție) | Switch | **Edge** |
| Momentan (cu revenire) | Button | **Momentary** |

`Action on power on` = **Restore last known state**

*Momentary* apare gri cât timp Input mode e pe *Switch* — întâi schimbi modul.

**De ce Edge:** pe `toggle`, becul urmează poziția întrerupătorului, deci apare problema „două cicluri la aprindere" când starea se desincronizează după o comandă vocală. Edge comută la fiecare schimbare de stare, indiferent de poziție.

Cu buton momentan problema nici nu există — fiecare apăsare e un toggle.

### Cablaj — Shelly în tavan (recomandat)

Soluția care nu cere nul în doza întrerupătorului. Necesită două fire între perete și tavan.

**În doză (perete):**
- Wago: Fază + Traveler 1 + borna **L** a butonului
- Borna **NO** a butonului → Traveler 2
- Cealaltă bornă → liberă, izolată

**În tavan:**
- Traveler 1 → **L** *și* **I** (punte între ele — fără ea releul n-are ce comuta)
- Traveler 2 → **SW**
- Nul → **N** pe Shelly *și* spre bec
- **O** → spre bec

Întrerupătorul nu mai taie nimic, doar semnalizează. Shelly rămâne alimentat permanent, becul răspunde și la buton, și la voce.

### Identificare bornă NO (Legrand momentan)

Pe schema imprimată: linia **continuă** = contact în repaus (NC), linia **punctată** = poziția la acționare (NO).

Verificare cu multimetru pe continuitate (`•))`), sonde în `V/Ω` și `COM`, întrerupătorul demontat:
- L–bornă, buton nepresat: **tăcere** = NO ✓ / **piuie** = NC
- Cu butonul apăsat, pe NO trebuie să piuie

### Aluminiu

Toată instalația pe Al: **Wago Al/Cu + pastă antioxidantă obligatoriu**. Niciodată Al direct în bornele Shelly.

---

## 9. HARMONY HUB

Skill-ul Alexa oficial Logitech a încetat să funcționeze (degradare servicii cloud). Integrarea HA rămâne **locală** și funcțională.

Soluția: template switches pentru fiecare activitate (vezi secțiunea 4), expuse apoi ca orice switch.

- `remote.*` nu e un domeniu pe care Alexa/Google îl înțeleg direct
- `name:` (expus vocal) poate diferi de `activity:` (trimis la hub) — ex. „Movies" vocal → „Filme" pe telecomandă
- Pornind o activitate, celelalte trec automat pe off — hub-ul rulează una singură

Verifică portul: `nc -zv 10.0.0.31 8088`

---

## 10. VERIFICĂRI ȘI DIAGNOSTIC

### Test discovery Alexa direct din HA

Ocolește complet Amazon și Lambda:

```bash
curl -sS -X POST https://ha.valipod.synology.me/api/alexa/smart_home \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"directive":{"header":{"namespace":"Alexa.Discovery","name":"Discover","payloadVersion":"3","messageId":"t1"},"payload":{"scope":{"type":"BearerToken","token":"x"}}}}' \
  | tr ',' '\n' | grep friendlyName
```

Token: HA → Profil → **Security** → *Long-lived access tokens* → Create. Șterge-l după test.

Dacă apar toate dispozitivele → HA e corect, problema e la Amazon. Dacă lipsesc → filtru sau entity_id greșit.

### Test invocare Lambda

CloudWatch → `/aws/lambda/HomeAssistant` → Log streams.

**Absența oricărui log stream** după `discover devices` = Alexa nu ajunge la Lambda. Problema e între skill și funcție (endpoint, regiune, trigger), nu în cod sau HA.

Test izolat al funcției: Lambda → tab **Test** → event JSON cu directivă `Alexa.Discovery`.

### Test conectivitate container

```bash
sudo docker exec homeassistant curl -sS -o /dev/null -w '%{http_code}\n' --max-time 8 https://homegraph.googleapis.com
```

`404` = iese la internet corect. Timeout / eroare DNS = problemă de rețea.

### Monitorizare cădere intermitentă

```bash
nohup bash -c 'while true; do printf "%s " "$(date +%H:%M:%S)"; curl -sS -o /dev/null -w "%{http_code} %{time_total}\n" --max-time 8 https://alerts.home-assistant.io 2>&1 | tr -d "\n"; echo; sleep 30; done' > /volume1/Media/nettest.log 2>&1 &

# după câteva ore
grep -v " 200 " /volume1/Media/nettest.log
```

---

## 11. CAPCANE ȘI LECȚII

### entity_id ≠ friendly_name

**Cea mai frecventă sursă de eșec.** Un bec împerecheat înainte de a primi nume în Z2M capătă entity_id după adresa IEEE: `light.0x0c4314fffe17e304`, deși friendly_name arată „Bec Ikea Birou".

Verifică **întotdeauna** în HA → **Developer Tools → States**, filtru `light.` sau `switch.`

Redenumire: Settings → Devices & Services → **Entities** → click pe entitate → rotița de setări → câmp **Entity ID**

Simptome: Google răspunde „one or more devices aren't available", Alexa nu găsește nimic.

### YAML: spații, nu taburi

```
found character '\t' that cannot start any token
```

```bash
sudo sed -i 's/\t/  /g' /volume1/docker/zigbee/homeassistant/config/configuration.yaml
```

Prevenție, în `~/.vimrc`:
```vim
autocmd FileType yaml setlocal expandtab tabstop=2 shiftwidth=2 softtabstop=2
```

### Schema nouă pentru template switches

```
ERROR: Configuring the template integration under the switch platform key
is not supported, it must be configured under its own template key instead
```

Corect: `template:` → `- switch:` → `- name:` cu `state:` (nu `switches:` cu `value_template:`).

### curl cu paranteze drepte

```
curl: (3) bad range in URL position 60
```

curl interpretează `[` `]` ca globbing. Folosește **`-g`** (`--globoff`), sau encodează `%5B` / `%5D`.

⚠️ `-s` ascunde eroarea și pare că API-ul returnează array gol. Folosește `-sS`.

### Login: username, nu email

Ambele integrări cer autentificare în HA. Emailul dă „Invalid username or password".

### Google Assistant nu suportă româna

Toate numele expuse trebuie în engleză. `room:` din YAML e doar o **sugestie** la prima sincronizare — Google o ignoră frecvent. Atribuirea reală se face în aplicație (dispozitivul ajunge în „Linked to you" până atunci).

### Reguli de rețea

- **mDNS nu trece între VLAN-uri** — dispozitivele se adaugă manual, după IP
- Prin site-to-site VPN, un Shelly pe WiFi la locația 2 se adaugă manual prin IP din HA la locația 1 (descoperirea automată nu funcționează). Dă-i IP fix prin rezervare DHCP.
- Zigbee nu traversează tunelul — cere coordinator separat

### Duplicate Shelly în HA

Un Shelly poate fi simultan pe Zigbee și WiFi, generând două entități funcționale care comandă același releu. Verifică în Z2M → dispozitiv → *Wifi Status*, și în UniFi dacă apare online.

Valorile din Z2M (IP, wifi status) pot fi **înghețate** de la ultimul raport — nu reflectă starea curentă după dezactivarea WiFi.

### Salvările din consolele Google/Amazon

Consola Google Home confirmă rar salvarea. **Dă refresh și verifică** că setările au rămas — prima salvare eșuează frecvent, mai ales la scan configuration.

---

## 12. PENDING

- [ ] Instabilitate rețea container: `ClientConnectorDNSError` și „Network unreachable" intermitente pe met.no, alerts.home-assistant.io, HomeGraph. Containerele **nu** repornesc singure (RestartCount 0), deci nu e crash. DNS-ul NAS-ului e doar 10.0.0.1, listat de două ori — fără redundanță.
- [ ] Harmony Hub: websocket timeout repetat (`No PONG received after 15.0 seconds`), deși portul 8088 e deschis
- [ ] Curățare entități orfane: SHIELD (Cast, deep sleep permanent)
- [ ] Al doilea Shelly: trecut pe Zigbee cu Edge configurat prin WiFi ✓
