-- The Home Assistant add-on's logic: it reads config.json from the scene's data folder (~/.local/share/pleamar/homeassistant/), asks Home
-- Assistant how the configured lights, switches and sensors are, lays the tiles out by room, and sends what the tiles and the slider ask for.
-- Everything goes through Home Assistant's REST API with curl. The token is written into a small curl config file in the same folder
-- (`auth.curl`, which curl reads with -K), so it never appears among curl's arguments, where any program could read it.
--
-- One request asks for every entity at once: a template (POST /api/template) that answers a JSON list, the state, brightness and unit of each.
-- It is asked every 3 s while the panel is open and every 30 s while it is shut, so the tiles are right the moment it opens.
--
-- The tiles' sizes (in cells: columns by rows) are chosen on the panel, in edit mode, and kept in layout.json, by entity.

local CONFIG = "config.json"
local AUTH = "auth.curl"
local LAYOUT = "layout.json"
local MAX_ITEMS, MAX_ROOMS = 32, 12
local TH, GAP, HEAD, RGAP = 74, 10, 38, 16      -- unscaled: a cell's height, the gap between cells, a room's head, the gap before the next room

local folder = ""
local cfg = nil             -- { url, insecure, rooms = { { name, temp, hum } }, items = { { kind, name, icon, entity, on_text, off_text, bad, room } } }
local est = {}              -- by entity: { st, bri, unit }, as the last answer said
local state = {}            -- by tile: { on, bri, avail, known }
local sizes = {}            -- by entity: { cs, rs }
local place = {}            -- by tile: { col, cs, rs, yu }; and `room_yu` by room
local room_yu = {}
local content = 0
local busy = false
local tick = 0
local hold_until = {}       -- by tile: until which tick (seconds) a poll must not overwrite what a click just changed
local open = false
local last_sig = ""

-- Icons of its own, for what Material Symbols has no good one for: white line drawings on Material's 24 grid, which the scene tints as it does
-- the font's. They are written into the data folder when it starts, beside config.json, and a tile names one by its file (`"icon": "tira-led.svg"`).
-- Any other .svg or .png put in that folder can be named the same way.
local ICONS = {
    ["tira-led.svg"] = [[<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="48" height="48" fill="none" stroke="#ffffff" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
<rect x="2.5" y="10" width="19" height="6" rx="3"/><circle cx="7" cy="13" r="1.15" fill="#ffffff" stroke="none"/><circle cx="10.33" cy="13" r="1.15" fill="#ffffff" stroke="none"/><circle cx="13.67" cy="13" r="1.15" fill="#ffffff" stroke="none"/><circle cx="17" cy="13" r="1.15" fill="#ffffff" stroke="none"/><path d="M12 4.5v2.2M7.2 5.6l1 1.6M16.8 5.6l-1 1.6"/>
</svg>]],
    ["farol-pared.svg"] = [[<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="48" height="48" fill="none" stroke="#ffffff" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
<rect x="3.5" y="8" width="2.6" height="11" rx="1.1"/><path d="M6.1 16.5H13"/><path d="M12.2 8.8 15.5 5.6l3.3 3.2z"/><path d="M15.5 5.6V3.9"/><rect x="12.9" y="8.8" width="5.2" height="7.7" rx="0.8"/><path d="M12 16.5h7"/><path d="M15.5 11.4v2.2"/>
</svg>]],
    ["lampara-pergola.svg"] = [[<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="48" height="48" fill="none" stroke="#ffffff" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
<path d="M12 2.5v5"/><path d="M6.5 13.5a5.5 5.5 0 0 1 11 0z"/><path d="M10.4 13.5a1.6 1.6 0 0 0 3.2 0"/><path d="M12 17.6v2.3M7.4 16.6l-1.3 1.7M16.6 16.6l1.3 1.7"/>
</svg>]],
    ["impresora-3d.svg"] = [[<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="48" height="48" fill="none" stroke="#ffffff" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
<rect x="3" y="3" width="18" height="18" rx="2.6"/><path d="M3 6.6h18"/><rect x="5.6" y="9" width="9.6" height="9.4" rx="1"/><path d="M7.6 16.4h5.6"/><rect x="9.3" y="13.6" width="2.2" height="2.8" rx="0.3" fill="#ffffff" stroke-width="1"/><path d="M9.4 10.9h2l-1 1.2z" fill="#ffffff" stroke-width="1"/><path d="M18.3 15.4l-1.55-1.5a.95.95 0 0 1 1.55-1.15.95.95 0 0 1 1.55 1.15z" fill="#ffffff" stroke-width="1.2"/>
</svg>]],
    ["reproductor.svg"] = [[<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="48" height="48" fill="none" stroke="#ffffff" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
<rect x="3" y="3" width="18" height="18" rx="4.6"/><path d="M9 8.4v6.1a1.6 1.6 0 0 0 1.6 1.6h.5"/><path d="M7.4 10.6h3.3"/><path d="M12.6 10.6l2 5.4 2-5.4"/>
</svg>]],
    ["lampara-pie.svg"] = [[<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="48" height="48" fill="none" stroke="#ffffff" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
<path d="M8.2 3.2h7.6l2.2 6.3H6z"/><path d="M12 9.5v10.3"/><path d="M8.3 20.6h7.4"/><path d="M14.6 9.5v1.8"/>
</svg>]],
    ["terrario.svg"] = [[<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="48" height="48" fill="none" stroke="#ffffff" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
<path d="M3.5 7.2h17"/><path d="M4.5 7.2v11.6a1.6 1.6 0 0 0 1.6 1.6h11.8a1.6 1.6 0 0 0 1.6-1.6V7.2"/><path d="M5.8 4.2h12.4"/><path d="M4.6 17h14.8"/><path d="M10 17v-4.6"/><path d="M10 13.6c0-2.3 1.6-3.4 3.6-3.4 0 2.2-1.6 3.4-3.6 3.4z"/><path d="M10 14.8c0-1.6-1-2.5-2.6-2.5 0 1.6 1 2.5 2.6 2.5z"/><path d="M15.2 17v-1.6"/>
</svg>]],
    ["calefactor.svg"] = [[<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="48" height="48" fill="none" stroke="#ffffff" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
<rect x="4" y="9" width="16" height="12" rx="2.4"/><circle cx="12" cy="15" r="3.6"/><path d="M12 15c-.3-1.9.8-3 2.4-2.6"/><g transform="rotate(120 12 15)"><path d="M12 15c-.3-1.9.8-3 2.4-2.6"/></g><g transform="rotate(240 12 15)"><path d="M12 15c-.3-1.9.8-3 2.4-2.6"/></g><path d="M8.5 6.6c-.8-.9.8-1.6 0-2.6M12 6.6c-.8-.9.8-1.6 0-2.6M15.5 6.6c-.8-.9.8-1.6 0-2.6"/>
</svg>]],
}

local EXAMPLE = [[{
  "_help": "Home Assistant add-on for Vitreus. Save this file and the panel reloads by itself.",
  "_language": "The panel's language: the name of a language file in this folder (English, Spanish, or one you add, such as French for French.json). English if left out.",
  "language": "English",
  "_url": "Your Home Assistant's address, with http:// or https:// and the port (usually 8123).",
  "url": "http://homeassistant.local:8123",
  "_token": "A long-lived access token: in Home Assistant, your profile > Security > Long-lived access tokens > Create token.",
  "token": "PASTE_YOUR_TOKEN_HERE",
  "_insecure": "true only for https with a certificate of your own (self-signed).",
  "insecure": false,
  "_rooms": "The rooms, in order. name: its title. temperature and humidity (optional): a sensor whose reading is shown beside the name. items: its tiles.",
  "_items": "type: \"light\" (a click toggles it, a right click opens its brightness) or \"toggle\" (input_boolean, switch, plug, media player...). icon: drawn in Vitreus's pencil, by name: lightbulb, floor_lamp, power, bedtime, mode_fan, tv, power_outlet, door_front, home (anything else is a bulb for a light, a power sign for a switch), or one of the add-on's own (led-strip.svg and the rest, see its README), or an .svg of yours. color: true on a light whose colour can change (an RGB bulb or LED strip): its right click card shows the colours too. tint: true draws that light's tile and card in its own colour instead of the accent. apple_tv: on an Apple TV's tile, { \"remote\": \"remote.living_room\" } gives it a card (right click) with what plays, its buttons and a remote. on_text and off_text are optional. A tile's size is changed on the panel, with the pencil.",
  "rooms": [
    {
      "name": "Living room",
      "temperature": "sensor.living_room_temperature",
      "humidity": "sensor.living_room_humidity",
      "items": [
        { "type": "light",  "name": "Lamp",       "icon": "floor-lamp.svg", "entity": "light.living_room" },
        { "type": "toggle", "name": "Night mode", "icon": "bedtime",        "entity": "input_boolean.night_mode" },
        { "type": "toggle", "name": "Apple TV",   "icon": "tv-box.svg",     "entity": "media_player.living_room", "apple_tv": { "remote": "remote.living_room" } }
      ]
    },
    {
      "name": "Office",
      "items": [
        { "type": "light",  "name": "Desk",       "icon": "desk",           "entity": "light.desk" },
        { "type": "light",  "name": "LED strip",  "icon": "led-strip.svg",  "entity": "light.led_strip", "color": true }
      ]
    }
  ]
}
]]

-- What the panel says. Every word it shows is here, the scene's too, in English and in Spanish, the two that come with it. Each is also written into the
-- data folder as a JSON file (English.json, Spanish.json), where it can be edited; and any other file there with the same keys is another language
-- (French.json, say): config.json's "language" names the file to use, English if it names none. A key a file lacks is said in English.
local STR = {
    es = {
        connecting = "Conectando…", connected = "Conectado · %d de %d %s", tile = "ficha", tiles = "fichas", no_tiles = "Conectado · sin fichas",
        offline = "Sin conexión", odd = "Respuesta extraña", odd_msg = "Home Assistant ha respondido algo que no se entiende",
        not_set = "Sin configurar", unreadable = "config.json no se puede leer: %s",
        need_url = "Pon la dirección de tu Home Assistant en \"url\" (por ejemplo http://192.168.1.10:8123).",
        need_token = "Falta el token: créalo en tu perfil de Home Assistant (Seguridad > Tokens de acceso de larga duración) y pégalo en \"token\".",
        no_auth = "No se puede escribir auth.curl en la carpeta del addon",
        e6 = "No se encuentra la dirección %s", e7 = "No se puede conectar con %s", e28 = "Home Assistant tarda demasiado en responder",
        e35 = "Fallo de https (¿certificado propio? prueba \"insecure\": true)", e60 = "Certificado https no válido (prueba \"insecure\": true)",
        ecurl = "curl ha fallado (código %s)", e401 = "Token incorrecto o caducado (401): crea uno nuevo en tu perfil de Home Assistant",
        e404 = "Home Assistant no reconoce la dirección (404): revisa la url", ehttp = "Home Assistant ha respondido con un error (%s)",
        bad = "Entidad no válida: %s", unavailable = "No disponible", light_on = "Encendida", light_off = "Apagada", on = "Activado", off = "Desactivado",
        room = "Habitación %d",
        -- the scene's (homeassistant.plm takes them as the `t_*` texts)
        hint = "Arrastra una ficha para moverla, o su esquina para cambiar su tamaño", ed_start = "Cambiar el tamaño de las fichas", ed_done = "Terminar", refresh = "Actualizar",
        edit_cfg = "Editar la configuración", no_editor = "No hay editor de texto: instala uno o define $EDITOR. Ruta copiada: %s", connecting_ha = "Conectando con Home Assistant…", title_offline = "Sin conexión",
        title_setup = "Configura Home Assistant", empty = "Aún no hay nada aquí",
        empty_hint = "Añade luces e interruptores en config.json: el engranaje de arriba lo abre.", brightness = "Brillo", close = "Cerrar",
        off_btn = "Apagar", resize = "Cambiar el tamaño de", color = "Color",
        -- the printer's card
        pr_idle = "En espera", pr_running = "Imprimiendo", pr_paused = "En pausa", pr_finished = "Terminada", pr_failed = "Fallida",
        pr_preparing = "Preparando", pr_offline = "Sin conexión", progress = "Progreso", pr_left = "Quedan %s", pr_started = "Empezó %s",
        pr_ends = "Termina %s", pr_ended = "Terminó %s", pause = "Pausar", resume = "Continuar", stop = "Detener", stop_sure = "¿Detener?",
        camera = "Cámara", live = "EN DIRECTO", open_cam = "Abrir la cámara",
        -- an Apple TV's card
        -- the settings (the gear)
        st_settings = "Ajustes", st_entities = "Entidades", st_back = "Volver", st_sec_ha = "HOME ASSISTANT", st_sec_panel = "PANEL",
        st_url = "Dirección", st_token = "Token de acceso", st_token_ph = "Pega aquí un token de larga duración",
        st_token_note = "En Home Assistant: tu perfil > Seguridad > Tokens de acceso de larga duración > Crear token. Se guarda solo en tu carpeta privada.",
        st_lang = "Idioma", st_insecure = "Certificado propio (https)", st_artwork = "Buscar carátulas en internet", st_open_json = "Abrir config.json en el editor",
        st_add_ent = "+ Entidad", st_add_room = "+ Habitación", st_no_room = "Sin habitación", st_n_tile = "%d ficha", st_n_tiles = "%d fichas",
        st_new_ent = "Nueva entidad", st_edit_ent = "Editar entidad", st_new_room = "Nueva habitación", st_edit_room = "Editar habitación",
        st_entity = "Entidad de Home Assistant", st_entity_ph = "Escribe para buscar: salón, light.…", st_name = "Nombre", st_name_ph = "Cómo se llama en el panel",
        st_type = "Tipo", st_light = "Luz", st_toggle = "Interruptor", st_room = "Habitación", st_icon = "Icono",
        st_own_icon = "Usa un icono propio (%s): elige otro aquí para cambiarlo.",
        st_color = "Cambiar el color desde su tarjeta", st_tint = "Ficha del color de la luz", st_tv = "Tarjeta de reproductor y mando (Apple TV)",
        st_remote = "Mando (entidad remote.…)", st_printer = "Tarjeta de impresora 3D", st_printer_pick = "Impresora (Bambu Lab) encontrada en Home Assistant:",
        st_printer_keep = "Mantiene la impresora que ya tenía configurada.", st_printer_none = "No encuentro una impresora Bambu Lab en Home Assistant: su bloque \"printer\" se escribe a mano en config.json.",
        st_on_text = "Texto encendido (opcional)", st_off_text = "Texto apagado (opcional)",
        st_save = "Guardar", st_add = "Añadir", st_cancel = "Cancelar", st_delete = "Eliminar", st_up = "Subir", st_down = "Bajar",
        st_delete_room_sure = "¿Eliminar con sus %d fichas?", st_room_name = "Nombre de la habitación", st_room_name_ph = "Salón, Dormitorio…",
        st_temp = "Sensor de temperatura (opcional)", st_hum = "Sensor de humedad (opcional)",
        st_need_entity = "Falta la entidad, o no es válida (dominio.nombre, p. ej. light.salon).", st_need_name = "Falta el nombre de la habitación.",
        st_broken = "config.json tiene un error y no se puede leer aquí: ábrelo en el editor para arreglarlo.",
        demo = "Demostración", demo_title = "Modo demostración: todavía sin conectar",
        demo_hint = "Pon el token y la url de tu Home Assistant y tus entidades en config.json (el engranaje lo abre). Esto es un ejemplo para probar.",
        demo_task = "Barco de prueba", demo_tv = "Una película de ejemplo",
        tv_off = "Apagado", tv_on = "Encendido", tv_playing = "Reproduciendo", tv_paused = "En pausa", tv_nothing = "No se está reproduciendo nada",
        tab_media = "Reproducción", tab_remote = "Mando", kb_hint = "Teclado: flechas, Intro, Retroceso (atrás) y Espacio (reproducir/pausa)",
        power = "Encender o apagar", up = "Arriba", down = "Abajo", left = "Izquierda", right = "Derecha", select = "Seleccionar", back = "Atrás",
        home = "TV (inicio)", playpause = "Reproducir o pausar", volup = "Subir el volumen", voldown = "Bajar el volumen", mute = "Silenciar", prev = "Anterior", next = "Siguiente",
    },
    en = {
        connecting = "Connecting…", connected = "Connected · %d of %d %s", tile = "tile", tiles = "tiles", no_tiles = "Connected · no tiles",
        offline = "Can't connect", odd = "Odd answer", odd_msg = "Home Assistant answered something that can't be read",
        not_set = "Not set up", unreadable = "config.json can't be read: %s",
        need_url = "Put your Home Assistant's address in \"url\" (e.g. http://192.168.1.10:8123).",
        need_token = "The token is missing: make one in your Home Assistant profile (Security > Long-lived access tokens) and paste it in \"token\".",
        no_auth = "auth.curl can't be written in the add-on's folder",
        e6 = "Address not found: %s", e7 = "Can't connect to %s", e28 = "Home Assistant takes too long to answer",
        e35 = "https failed (a certificate of your own? try \"insecure\": true)", e60 = "Invalid https certificate (try \"insecure\": true)",
        ecurl = "curl failed (code %s)", e401 = "Wrong or expired token (401): make a new one in your Home Assistant profile",
        e404 = "Home Assistant doesn't know that address (404): check the url", ehttp = "Home Assistant answered with an error (%s)",
        bad = "Invalid entity: %s", unavailable = "Unavailable", light_on = "On", light_off = "Off", on = "On", off = "Off",
        room = "Room %d",
        -- the scene's (homeassistant.plm takes them as the `t_*` texts)
        hint = "Drag a tile to move it, or its corner to resize it", ed_start = "Resize the tiles", ed_done = "Done", refresh = "Refresh",
        edit_cfg = "Edit the settings", no_editor = "No text editor found: install one or set $EDITOR. Path copied: %s", connecting_ha = "Connecting to Home Assistant…", title_offline = "Can't connect",
        title_setup = "Set up Home Assistant", empty = "Nothing here yet",
        empty_hint = "Add lights and switches in config.json: the gear above opens it.", brightness = "Brightness", close = "Close",
        off_btn = "Off", resize = "Resize", color = "Colour",
        -- the printer's card
        pr_idle = "Idle", pr_running = "Printing", pr_paused = "Paused", pr_finished = "Finished", pr_failed = "Failed",
        pr_preparing = "Preparing", pr_offline = "Offline", progress = "Progress", pr_left = "%s left", pr_started = "Started %s",
        pr_ends = "Ends %s", pr_ended = "Ended %s", pause = "Pause", resume = "Resume", stop = "Stop", stop_sure = "Stop?",
        camera = "Camera", live = "LIVE", open_cam = "Open the camera",
        -- an Apple TV's card
        -- the settings (the gear)
        st_settings = "Settings", st_entities = "Entities", st_back = "Back", st_sec_ha = "HOME ASSISTANT", st_sec_panel = "PANEL",
        st_url = "Address", st_token = "Access token", st_token_ph = "Paste a long-lived access token",
        st_token_note = "In Home Assistant: your profile > Security > Long-lived access tokens > Create token. It is kept only in your private folder.",
        st_lang = "Language", st_insecure = "Self-signed certificate (https)", st_artwork = "Look up artwork online", st_open_json = "Open config.json in the editor",
        st_add_ent = "+ Entity", st_add_room = "+ Room", st_no_room = "No room", st_n_tile = "%d tile", st_n_tiles = "%d tiles",
        st_new_ent = "New entity", st_edit_ent = "Edit entity", st_new_room = "New room", st_edit_room = "Edit room",
        st_entity = "Home Assistant entity", st_entity_ph = "Type to search: living, light.…", st_name = "Name", st_name_ph = "What the panel calls it",
        st_type = "Kind", st_light = "Light", st_toggle = "Switch", st_room = "Room", st_icon = "Icon",
        st_own_icon = "Uses an icon of its own (%s): pick another here to change it.",
        st_color = "Change its colour from its card", st_tint = "Tile in the light's colour", st_tv = "Player card and remote (Apple TV)",
        st_remote = "Remote (remote.… entity)", st_printer = "3D printer card", st_printer_pick = "Printer (Bambu Lab) found in Home Assistant:",
        st_printer_keep = "Keeps the printer it already had.", st_printer_none = "No Bambu Lab printer found in Home Assistant: its \"printer\" block is written by hand in config.json.",
        st_on_text = "Text when on (optional)", st_off_text = "Text when off (optional)",
        st_save = "Save", st_add = "Add", st_cancel = "Cancel", st_delete = "Delete", st_up = "Move up", st_down = "Move down",
        st_delete_room_sure = "Delete with its %d tiles?", st_room_name = "Room name", st_room_name_ph = "Living room, Bedroom…",
        st_temp = "Temperature sensor (optional)", st_hum = "Humidity sensor (optional)",
        st_need_entity = "The entity is missing, or not valid (domain.name, e.g. light.living_room).", st_need_name = "The room needs a name.",
        st_broken = "config.json has an error and can't be read here: open it in the editor to fix it.",
        demo = "Demo", demo_title = "Demo mode: not connected yet",
        demo_hint = "Put your Home Assistant's token and url, and your entities, in config.json (the gear opens it). This is an example to try.",
        demo_task = "Test boat", demo_tv = "An example film",
        tv_off = "Off", tv_on = "On", tv_playing = "Playing", tv_paused = "Paused", tv_nothing = "Nothing playing",
        tab_media = "Now playing", tab_remote = "Remote", kb_hint = "Keyboard: arrows, Return, BackSpace (back) and Space (play/pause)",
        power = "Power", up = "Up", down = "Down", left = "Left", right = "Right", select = "Select", back = "Back",
        home = "TV (home)", playpause = "Play or pause", volup = "Volume up", voldown = "Volume down", mute = "Mute", prev = "Previous", next = "Next",
    },
}
local WORDS = {
    "connecting",
    "connected",
    "tile",
    "tiles",
    "no_tiles",
    "offline",
    "odd",
    "odd_msg",
    "not_set",
    "unreadable",
    "need_url",
    "need_token",
    "no_auth",
    "e6",
    "e7",
    "e28",
    "e35",
    "e60",
    "ecurl",
    "e401",
    "e404",
    "ehttp",
    "bad",
    "unavailable",
    "light_on",
    "light_off",
    "on",
    "off",
    "room",
    "hint",
    "ed_start",
    "ed_done",
    "refresh",
    "edit_cfg",
    "no_editor",
    "connecting_ha",
    "title_offline",
    "title_setup",
    "empty",
    "empty_hint",
    "brightness",
    "close",
    "off_btn",
    "resize",
    "color",
    "pr_idle",
    "pr_running",
    "pr_paused",
    "pr_finished",
    "pr_failed",
    "pr_preparing",
    "pr_offline",
    "progress",
    "pr_left",
    "pr_started",
    "pr_ends",
    "pr_ended",
    "pause",
    "resume",
    "stop",
    "stop_sure",
    "camera",
    "live",
    "open_cam",
    "st_settings",
    "st_entities",
    "st_back",
    "st_sec_ha",
    "st_sec_panel",
    "st_url",
    "st_token",
    "st_token_ph",
    "st_token_note",
    "st_lang",
    "st_insecure",
    "st_artwork",
    "st_open_json",
    "st_add_ent",
    "st_add_room",
    "st_no_room",
    "st_n_tile",
    "st_n_tiles",
    "st_new_ent",
    "st_edit_ent",
    "st_new_room",
    "st_edit_room",
    "st_entity",
    "st_entity_ph",
    "st_name",
    "st_name_ph",
    "st_type",
    "st_light",
    "st_toggle",
    "st_room",
    "st_icon",
    "st_own_icon",
    "st_color",
    "st_tint",
    "st_tv",
    "st_remote",
    "st_printer",
    "st_printer_pick",
    "st_printer_keep",
    "st_printer_none",
    "st_on_text",
    "st_off_text",
    "st_save",
    "st_add",
    "st_cancel",
    "st_delete",
    "st_up",
    "st_down",
    "st_delete_room_sure",
    "st_room_name",
    "st_room_name_ph",
    "st_temp",
    "st_hum",
    "st_need_entity",
    "st_need_name",
    "st_broken",
    "demo",
    "demo_title",
    "demo_hint",
    "demo_task",
    "demo_tv",
    "tv_off",
    "tv_on",
    "tv_playing",
    "tv_paused",
    "tv_nothing",
    "tab_media",
    "tab_remote",
    "kb_hint",
    "power",
    "up",
    "down",
    "left",
    "right",
    "select",
    "back",
    "home",
    "playpause",
    "volup",
    "voldown",
    "mute",
    "prev",
    "next",
}
local LANGS = { English = STR.en, Spanish = STR.es }          -- the ones that come with it, by their file's name
local lang = "en"            -- the language's code (its file's "_code"): which country's catalogue the Apple TV's artwork is looked up in
local words = STR.en         -- the words in use
local function T(key, ...)
    local s = words[key]
    if type(s) ~= "string" then s = STR.en[key] or key end
    if select("#", ...) > 0 then
        local ok, out = pcall(string.format, s, ...)      -- (a translation that lost a %s or a %d is said in English rather than not at all)
        if ok then return out end
        return string.format(STR.en[key] or key, ...)
    end
    return s
end
-- A language as the JSON file it is kept in: the keys in WORDS' order, one a line, with a note on top, so it reads (and translates) top to bottom.
local function lang_json(name, code, t)
    local lines = { "{",
        '  "_about": ' .. json.encode("The Home Assistant add-on's words in " .. name .. ". Edit the texts on the right, keeping %s and %d where they are (a number or a name goes there). To add a language, copy this file as French.json (say), translate it, change _code to the language's two letters, and put \"language\": \"French\" in config.json. A text it lacks is said in English.") .. ",",
        '  "_code": ' .. json.encode(code) .. "," }
    for k, key in ipairs(WORDS) do
        lines[#lines + 1] = "  " .. json.encode(key) .. ": " .. json.encode(t[key] or STR.en[key] or "") .. (k < #WORDS and "," or "")
    end
    lines[#lines + 1] = "}"
    return table.concat(lines, "\n") .. "\n"
end
-- English.json and Spanish.json in the data folder: written when they are not there, and given any text a newer version of the add-on added (what was
-- edited in them is kept).
local function lang_files()
    for name, t in pairs(LANGS) do
        local file = name .. ".json"
        local ok, have = pcall(sys.ask, "files.read", file, "json")
        if not ok or type(have) ~= "table" then
            pcall(sys.call, "files.write", file, lang_json(name, t == STR.es and "es" or "en", t))
        else
            local missing = false
            for _, key in ipairs(WORDS) do if have[key] == nil then missing = true; break end end
            if missing then
                local merged = {}
                for _, key in ipairs(WORDS) do merged[key] = have[key] ~= nil and have[key] or t[key] end
                pcall(sys.call, "files.write", file, lang_json(name, type(have._code) == "string" and have._code or (t == STR.es and "es" or "en"), merged))
            end
        end
    end
end
-- config.json's "language": a file's name ("French" or "French.json"), or the old codes and names of the two that come with it. English when it names none
-- or the file cannot be read.
local OLD = { en = "English", es = "Spanish", english = "English", spanish = "Spanish", ["inglés"] = "English", ingles = "English", ["español"] = "Spanish", espanol = "Spanish" }
local lang_watched, lang_reload = {}, nil
local function use_lang(want)
    want = type(want) == "string" and want:gsub("%.json$", ""):gsub("^%s+", ""):gsub("%s+$", "") or ""
    local name = OLD[want:lower()] or want
    if name == "" or not name:match("^[%w _%-%(%)]+$") then name = "English" end
    local file = name .. ".json"
    local ok, t = pcall(sys.ask, "files.read", file, "json")
    if not ok or type(t) ~= "table" then
        local other = name:sub(1, 1):upper() .. name:sub(2):lower() .. ".json"
        local ok2, t2 = pcall(sys.ask, "files.read", other, "json")
        if ok2 and type(t2) == "table" then ok, t, file = ok2, t2, other end
    end
    if not ok or type(t) ~= "table" then t = LANGS[name] or STR.en end
    -- the file in use, saved: read again (each is watched once; an edit to it shows at once)
    if not lang_watched[file] then
        lang_watched[file] = true
        sys.watch("files:" .. file, function() after(150, function() if lang_reload then lang_reload() end end) end)
    end
    words = t
    local code = type(t._code) == "string" and t._code:lower() or (t == STR.es and "es" or "en")
    lang = code:match("^%a%a$") and code or "en"
end

-- English names for the add-on's own icons (the files keep their Spanish ones).
local ALIAS = {
    ["led-strip.svg"] = "tira-led.svg", ["wall-lantern.svg"] = "farol-pared.svg", ["pendant-lamp.svg"] = "lampara-pergola.svg",
    ["floor-lamp.svg"] = "lampara-pie.svg", ["3d-printer.svg"] = "impresora-3d.svg", ["tv-box.svg"] = "reproductor.svg",
    ["terrarium.svg"] = "terrario.svg", ["fan-heater.svg"] = "calefactor.svg",
}


-- The icons. A tile is drawn with the pencil's icons (addon-pencil.plm's PIcon, as Vitreus's own add-ons are), chosen by the Material Symbols name its "icon"
-- gives: these names, and anything else as a bulb (a light) or a power sign (a switch). An .svg or .png of its own is drawn as it is (the add-on's own, in pencil).
local PENCIL = {
    lightbulb = 0, light = 0, bulb = 0, emoji_objects = 0, wb_incandescent = 0, light_group = 0, highlight = 0,
    desk = 1, floor_lamp = 1, table_lamp = 1, lamp = 1, wall_lamp = 1, lamps = 1,
    power = 2, power_settings_new = 2, toggle_on = 2, bolt = 2, settings_power = 2,
    bedtime = 3, nightlight = 3, dark_mode = 3, moon = 3, mode_night = 3,
    mode_fan = 4, fan = 4, toys_fan = 4, air = 4, heat = 4, ac_unit = 4, mode_heat = 4,
    tv = 5, desktop_windows = 5, monitor = 5, computer = 5, live_tv = 5, connected_tv = 5, tv_gen = 5, laptop = 5, cast = 5, print = 5,
    power_outlet = 6, outlet = 6, plug = 6, electrical_services = 6, outlet_power = 6, charger = 6,
    door_front = 7, door = 7, garage = 7, door_back = 7, door_sliding = 7, garage_home = 7,
    house = 8, home = 8, cottage = 8, home_iot_device = 8, cabin = 8,
}
-- The add-on's own icons (its .svg files) are drawn in pencil too, from ha-icons.plm's HDev; any other .svg or .png is drawn as it is.
local DEV = { ["tira-led.svg"] = 0, ["farol-pared.svg"] = 1, ["lampara-pergola.svg"] = 2, ["lampara-pie.svg"] = 3, ["impresora-3d.svg"] = 4,
    ["reproductor.svg"] = 5, ["terrario.svg"] = 6, ["calefactor.svg"] = 7 }
local function dev_k(it)
    if not it.file then return -1 end
    return DEV[it.file] or -1
end
local function own_pic(it) return it.file ~= nil and dev_k(it) < 0 end      -- a picture of its own, drawn as it is
local function pencil_k(it)
    if it.file then return -1 end
    return PENCIL[it.icon] or (it.kind == 0 and 0 or 2)
end

local function set_state(n, status, msg)
    fact.hl_state = n
    text.hl_status = status
    text.hl_msg = msg or ""
    text.t_title = n == 2 and T("title_offline") or (n == 3 and T("title_setup") or "")
end

-- The scene's words, in the language now in use.
local function scene_words()
    text.t_hint = T("hint")
    text.t_ed = fact.hl_editing == true and T("ed_done") or T("ed_start")
    text.t_refresh = T("refresh")
    text.t_edit_cfg = T("edit_cfg")
    text.t_connecting = T("connecting_ha")
    text.t_empty = T("empty")
    text.t_empty_hint = T("empty_hint")
    text.t_brightness = T("brightness")
    text.t_close = T("close")
    text.t_off = T("off_btn")
    text.t_resize = T("resize")
    text.t_color = T("color")
    text.t_progress = T("progress")
    text.t_pause = T("pause")
    text.t_resume = T("resume")
    text.t_stop = T("stop")
    text.t_stop_sure = T("stop_sure")
    text.t_camera = T("camera")
    text.t_live = T("live")
    text.t_open_cam = T("open_cam")
    text.t_b1 = fact.pr_arm == true and T("stop_sure") or T("stop")
    text.t_b2 = T("camera")
    text.t_demo_title = T("demo_title")
    text.t_demo_hint = T("demo_hint")
    text.t_tab0 = T("tab_media")
    text.t_tab1 = T("tab_remote")
    text.t_kb = T("kb_hint")
    text.t_power = T("power")
    for _, k in ipairs({ "up", "down", "left", "right", "select", "back", "home", "playpause", "volup", "voldown", "mute", "prev", "next" }) do
        text["t_" .. k] = T(k)
    end
end
on("fact:hl_editing", function() text.t_ed = fact.hl_editing == true and T("ed_done") or T("ed_start") end)

-- an entity id is a domain, a dot and a name: anything else could break the template it is written into
local function valid(e) return type(e) == "string" and e:match("^[%a_]+%.[%w_]+$") ~= nil end

local function decimal(v, places)
    local s = string.format("%." .. places .. "f", v)
    return (s:gsub("%.", ","))
end

-- How many columns fit: the scene's rule (170 apiece and 10 between, 14 at each side, all times 1.1), up to four.
local function columns()
    local w = tonumber(fact.slot_w) or 0
    if w <= 0 then w = 520 end
    local u = 1.1
    return math.max(1, math.min(4, math.floor((w - 2 * 14 * u + 10 * u) / (170 * u + 10 * u))))
end

-- Lay the tiles out: room by room, each under its head (a room with no name has none), each tile in the first place it fits, left to right and
-- top to bottom, so a small one fills the hole a big one left.
local function layout()
    place, room_yu = {}, {}
    content = 0
    if not cfg then return end
    local cols = columns()
    local y = 0
    for k, room in ipairs(cfg.rooms) do
        if room.name ~= "" then
            room_yu[k] = y
            y = y + HEAD
        end
        local occ = {}
        local function free(r, c, cs, rs)
            for rr = r, r + rs - 1 do
                for cc = c, c + cs - 1 do
                    if occ[rr] and occ[rr][cc] then return false end
                end
            end
            return true
        end
        local rows = 0
        local halves = cols * 2          -- (in half columns: a tile takes one, the icon alone, or two, a column, or more; its size is kept in columns, 0.5 for a half)
        for i, it in ipairs(cfg.items) do
            if it.room == k then
                local sz = sizes[it.entity] or {}
                local cs = math.max(1, math.min(halves, math.floor((tonumber(sz[1]) or 1) * 2 + 0.5)))
                local rs = math.max(1, math.min(3, tonumber(sz[2]) or 1))
                local r, done = 0, false
                while not done do
                    for c = 0, halves - cs do
                        if free(r, c, cs, rs) then
                            for rr = r, r + rs - 1 do
                                occ[rr] = occ[rr] or {}
                                for cc = c, c + cs - 1 do occ[rr][cc] = true end
                            end
                            place[i] = { col = c, cs = cs, rs = rs, yu = y + r * (TH + GAP) }
                            rows = math.max(rows, r + rs)
                            done = true
                            break
                        end
                    end
                    r = r + 1
                end
            end
        end
        y = y + math.max(0, rows * (TH + GAP) - GAP)
        if k < #cfg.rooms then y = y + RGAP end
    end
    content = y
    fact.hl_cols = cols
end

-- A printer (a tile with "printer" in config.json: the entities of its job, its state, its progress, its times, its cover, its camera and its buttons). What
-- its sensors say is read once here, for the tile (its line and its bar while it prints) and for the card a right click opens.
local PR_KEYS = { "task", "progress", "remaining", "status", "start", "end", "cover", "camera", "pause", "resume", "stop" }
local PR_POLL = { "task", "progress", "remaining", "status", "start", "end", "cover", "camera" }      -- (the buttons have nothing to read)
local PR_STATE = { running = 1, printing = 1, pause = 2, paused = 2, finish = 3, finished = 3, failed = 4, error = 4,
    prepare = 5, preparing = 5, init = 5, slicing = 5, idle = 0, offline = 6, unavailable = 6, unknown = 6 }
local PR_LABEL = { [0] = "pr_idle", "pr_running", "pr_paused", "pr_finished", "pr_failed", "pr_preparing", "pr_offline" }
local function pr_read(it)
    local P = it.printer
    local function e(k) return P[k] and est[P[k]] or nil end
    local s = e("status")
    local code = s and (PR_STATE[(s.st or ""):lower()] or 0) or 0
    local prog = e("progress") and tonumber(e("progress").st) or nil
    local left
    local re = e("remaining")
    local v = re and tonumber(re.st)
    if v then
        local unit = (re.unit or ""):lower()
        left = unit == "h" and v * 60 or (unit == "s" and v / 60 or (unit == "d" and v * 1440 or v))       -- in minutes (Bambu Lab's is in minutes or hours)
    end
    local task = e("task") and e("task").st or ""
    if task == "unknown" or task == "unavailable" then task = "" end
    return { code = code, has_status = s ~= nil, prog = prog, left = left, task = task,
        start = e("start") and e("start").tm or "", ends = e("end") and e("end").tm or "" }
end
local function duration(mins)
    mins = math.floor(mins + 0.5)
    if mins < 1 then return "< 1 min" end
    local h, m = math.floor(mins / 60), mins % 60
    if h == 0 then return m .. " min" end
    if m == 0 then return h .. " h" end
    return h .. " h " .. m .. " min"
end

-- The card's picture: the model's cover, or a frame of the camera, fetched with curl into the data folder (two files in turn, so the one on screen is never
-- half written) and shown with a version, so the same name is read again.
local pr_pic_n, pr_shown, pr_busy = 0, "", false
local function pr_item()
    local it = cfg and cfg.items[(tonumber(fact.pr_i) or -1) + 1]
    return it and it.printer and it or nil
end
local function pr_fetch(pic)
    if pr_busy or not cfg or not pic or pic == "" then return end
    pr_busy = true
    pr_pic_n = pr_pic_n + 1
    local n = pr_pic_n
    local path = folder .. "/printer-" .. (n % 2) .. ".img"
    local args = { "-s", "-f", "-K", folder .. "/" .. AUTH, "--max-time", "8", "-o", path }
    if cfg.insecure then args[#args + 1] = "-k" end
    args[#args + 1] = cfg.url .. pic
    run("curl", args, function(_, code)
        pr_busy = false
        if code == 0 then
            model.pr_pic = { { img = path .. "?" .. n } }
            fact.pr_has_pic = true
        end
    end)
end
local function pr_fill()
    local it = pr_item()
    if not it or fact.pr_open ~= true then return end
    local P = it.printer
    local pr = pr_read(it)
    text.pr_icon = it.file and "" or it.icon
    fact.pr_custom = own_pic(it)
    text.pr_task = pr.task ~= "" and pr.task or it.name
    fact.pr_st = pr.code
    text.t_b0 = pr.code == 2 and T("resume") or T("pause")
    text.pr_status = pr.has_status and T(PR_LABEL[pr.code] or "pr_idle") or ""
    fact.pr_prog = math.max(0, math.min(1, (pr.prog or 0) / 100))
    text.pr_pct = pr.prog and (math.floor(pr.prog + 0.5) .. " %") or "—"
    local running = pr.code == 1 or pr.code == 2 or pr.code == 5
    text.pr_left = (running and pr.left) and T("pr_left", duration(pr.left)) or "—"
    text.pr_start = pr.start ~= "" and T("pr_started", pr.start) or "—"
    text.pr_end = pr.ends ~= "" and T(running and "pr_ends" or "pr_ended", pr.ends) or "—"
    fact.pr_has_cam = P.camera ~= nil
    fact.pr_has_btn = P.pause ~= nil or P.resume ~= nil or P.stop ~= nil
    if fact.pr_cam ~= true then
        -- the cover: fetched again only when it changes (its state is when it last did; its address carries a token that changes by itself)
        local ce = P.cover and est[P.cover]
        if ce and ce.pic ~= "" then
            local key = ce.st .. (ce.pic:gsub("token=[^&]*", ""))
            if key ~= pr_shown then pr_shown = key; pr_fetch(ce.pic) end
        elseif pr_shown ~= "none" then
            pr_shown = "none"
            fact.pr_has_pic = false
        end
    end
end

local show, call          -- (both further down; the Apple TV's poll, here, uses them)
local st                  -- the settings page (settings.luau), once it is loaded
-- An Apple TV (or any media player given "apple_tv"): what it plays, asked in a template of its own (a few more attributes than the tiles' one), when it is
-- polled. Its position is counted on here between answers (`at`: the tick it came at), so the bar moves every second without asking.
local tvs = {}              -- by media player: { st, title, artist, series, app, dur, pos, el, pic, at }
local TV_CODE = { off = 0, standby = 0, unavailable = 0, unknown = 0, idle = 1, on = 1, playing = 2, buffering = 2, paused = 3 }
local TV_LABEL = { [0] = "tv_off", "tv_on", "tv_playing", "tv_paused" }
local tv_busy, tv_pic_n, tv_shown, tv_pbusy, tv_retry = false, 0, "", false, nil
local function tv_code(t) return t and (TV_CODE[t.st] or 1) or 0 end
local function tv_now(t)                -- where it is now, in seconds (-1: it does not say)
    if not t or t.dur <= 0 or t.pos < 0 then return -1 end
    local p = t.pos
    if tv_code(t) == 2 then p = p + t.el + (tick - t.at) end
    return math.max(0, math.min(t.dur, p))
end
local function clock(sec)
    sec = math.floor(sec + 0.5)
    local h, m, x = math.floor(sec / 3600), math.floor(sec / 60) % 60, sec % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, x) end
    return string.format("%d:%02d", m, x)
end
local function tv_item()
    local it = cfg and cfg.items[(tonumber(fact.tv_i) or -1) + 1]
    return it and it.tv and it or nil
end
local function tv_fetch(pic)
    if tv_pbusy or not cfg or not pic or pic == "" then return end
    tv_pbusy = true
    tv_pic_n = tv_pic_n + 1
    local n = tv_pic_n
    local path = folder .. "/tv-" .. (n % 2) .. ".img"
    local args = { "-s", "-f", "-K", folder .. "/" .. AUTH, "--max-time", "20", "-o", path }
    if cfg.insecure then args[#args + 1] = "-k" end
    args[#args + 1] = cfg.url .. pic
    run("curl", args, function(_, code)
        tv_pbusy = false
        if code == 0 then
            model.tv_pic = { { img = path .. "?" .. n } }
            fact.tv_has_appic = false
            fact.tv_has_pic = true
        else
            tv_retry = tick + 15          -- (asked again a little later, not every second)
        end
    end)
end
-- Artwork where Home Assistant has none (many apps give the Apple TV none): looked up by what plays, in the free public catalogue that knows that kind of thing
-- best (none needs an account or a key), chosen by the app and by what it says it plays:
--   music (Spotify, Music…, or a song with its artist)  Deezer, by artist and title: the album's cover; then Apple's iTunes catalogue
--   a series, from an anime app (Crunchyroll…)          AniList, by the series' name: its cover
--   a series, from any other app                        TVmaze, by the series' name: its poster; then iTunes
--   only a title                                        iTunes, a film with exactly that title; then TVmaze, a series with exactly that name
--   none of that found                                  the app's own icon (iTunes), over its name
-- A match must carry the name it was asked for, so a near miss shows the app's icon rather than somebody else's poster. Only the series, the title, the artist
-- and the app's name are sent, never anything of Home Assistant's; `"artwork_search": false` in config.json turns it off. What is found is kept (in memory,
-- and its picture in the data folder), so each thing is asked once.
local ITUNES = "https://itunes.apple.com/search"
local DEEZER = "https://api.deezer.com/search"
local TVMAZE = "https://api.tvmaze.com/singlesearch/shows"
local ANILIST = "https://graphql.anilist.co"
local MUSIC_APPS = { spotify = true, ["música"] = true, music = true, applemusic = true, deezer = true, tidal = true, amazonmusic = true, youtubemusic = true }
local ANIME_APPS = { crunchyroll = true, hidive = true, animelab = true, funimation = true, adn = true }
local art = {}               -- by what plays ("app|series|artist|title") and by app ("app:Netflix"): { kind = 1 artwork · 2 an app's icon, path }, or false: none
local art_busy = {}
local function urlenc(x) return (x:gsub("[^%w%-_%.~]", function(c) return string.format("%%%02X", string.byte(c)) end)) end
local function norm(x) return (tostring(x or ""):lower():gsub("[^%w]", "")) end
local function hash(x)
    local h = 5381
    for i = 1, #x do h = (h * 33 + x:byte(i)) % 4294967296 end
    return string.format("%08x", h)
end
local function same(a, b) a, b = norm(a), norm(b) return #b >= 2 and a == b end
local function starts(a, b) a, b = norm(a), norm(b) return #b >= 3 and a:sub(1, #b) == b end
-- a JSON answer from a public catalogue (`body`: POSTed as JSON). `done(table or nil)`.
local function web(url, body, done)
    local args = { "-s", "-f", "-L", "--max-time", "10" }
    local opts = nil
    if body then
        for _, x in ipairs({ "-X", "POST", "-H", "Content-Type: application/json", "-H", "Accept: application/json", "--data-binary", "@-" }) do args[#args + 1] = x end
        opts = { input = body }
    end
    args[#args + 1] = url
    run("curl", args, function(out, code)
        local ok, j = pcall(json.decode, code == 0 and out or "")
        done(ok and type(j) == "table" and j or nil)
    end, opts)
end
local function https(u) return type(u) == "string" and u:match("^https://") and u or nil end
local function big(u, size) return (tostring(u or ""):gsub("%d+x%d+bb", size .. "x" .. size .. "bb")) end
local function itunes(media, entity, term, choose, done)
    web(ITUNES .. "?media=" .. media .. "&entity=" .. entity .. "&limit=8&country=" .. (lang == "en" and "us" or lang) .. "&term=" .. urlenc(term), nil, function(j)
        for _, r in ipairs(j and type(j.results) == "table" and j.results or {}) do
            local u = type(r) == "table" and https(choose(r))
            if u then done(u) return end
        end
        done(nil)
    end)
end
-- the sources, each `done(url or nil)`
local function from_deezer(artist, title, done)
    web(DEEZER .. "?limit=8&q=" .. urlenc('artist:"' .. artist .. '" track:"' .. title .. '"'), nil, function(j)
        for _, r in ipairs(j and type(j.data) == "table" and j.data or {}) do
            if type(r) == "table" and type(r.artist) == "table" and type(r.album) == "table" and (same(r.artist.name, artist) or starts(artist, r.artist.name)) then
                local u = https(r.album.cover_xl or r.album.cover_big)
                if u then done(u) return end
            end
        end
        done(nil)
    end)
end
local function from_itunes_song(artist, title, done)
    itunes("music", "song", artist .. " " .. title, function(r)
        return (same(r.artistName, artist) or starts(r.artistName, artist)) and starts(r.trackName, title) and big(r.artworkUrl100, 600) or nil
    end, done)
end
local function from_anilist(series, done)
    local q = 'query ($s: String) { Page(perPage: 5) { media(search: $s, type: ANIME) { title { romaji english native } synonyms coverImage { extraLarge large } } } }'
    web(ANILIST, json.encode({ query = q, variables = { s = series } }), function(j)
        local list = j and type(j.data) == "table" and type(j.data.Page) == "table" and j.data.Page.media or {}
        for _, m in ipairs(type(list) == "table" and list or {}) do
            local t = type(m) == "table" and m.title or {}
            local hit = same(t.romaji, series) or same(t.english, series) or same(t.native, series) or starts(t.english, series) or starts(t.romaji, series)
            for _, syn in ipairs(type(m.synonyms) == "table" and m.synonyms or {}) do hit = hit or same(syn, series) end
            if hit and type(m.coverImage) == "table" then
                local u = https(m.coverImage.extraLarge or m.coverImage.large)
                if u then done(u) return end
            end
        end
        done(nil)
    end)
end
local function from_tvmaze(name, exact, done)
    web(TVMAZE .. "?q=" .. urlenc(name), nil, function(j)
        local ok = j and (same(j.name, name) or (not exact and starts(j.name, name)))
        done(ok and type(j.image) == "table" and https(j.image.original or j.image.medium) or nil)
    end)
end
local function from_itunes_season(name, done)
    itunes("tvShow", "tvSeason", name, function(r) return starts(r.collectionName, name) and big(r.artworkUrl100, 600) or nil end, done)
end
local function from_itunes_movie(title, done)
    itunes("movie", "movie", title, function(r) return same(r.trackName, title) and #norm(title) >= 3 and big(r.artworkUrl100, 600) or nil end, done)
end
-- tries each source in turn until one finds it
local function first(tries, done)
    local k = 0
    local function step(u)
        if u then done(u) return end
        k = k + 1
        if tries[k] then tries[k](step) else done(nil) end
    end
    step(nil)
end
local function art_get(url, kind, done)
    local path = folder .. "/art-" .. hash(url) .. ".img"
    run("curl", { "-s", "-f", "-L", "--max-time", "15", "-o", path, url }, function(_, code)
        done(code == 0 and { kind = kind, path = path } or false)
    end)
end
local function big(u, size) return (tostring(u or ""):gsub("%d+x%d+bb", size .. "x" .. size .. "bb")) end
-- the app's icon, once per app
local function art_app(app, done)
    local key = "app:" .. app
    if art[key] ~= nil then done(art[key]) return end
    itunes("software", "software", app, function(r)
        local n = norm(r.trackName)
        return #n > 0 and #norm(app) > 0 and (n:find(norm(app), 1, true) or norm(app):find(n, 1, true)) and big(r.artworkUrl512 or r.artworkUrl100, 512) or nil
    end, function(u)
        if not u then art[key] = false; done(false) return end
        art_get(u, 2, function(a) art[key] = a; done(a) end)
    end)
end
local function art_find(t, done)
    local series, title, artist, app = t.series or "", t.title or "", t.artist or "", t.app or ""
    local music = MUSIC_APPS[norm(app)] or MUSIC_APPS[(app:lower():gsub("%s", ""))] or t.ctype == "music"
    local anime = ANIME_APPS[norm(app)]
    local tries = {}
    local function add(f) tries[#tries + 1] = f end
    if music and artist ~= "" and title ~= "" then
        add(function(k) from_deezer(artist, title, k) end)
        add(function(k) from_itunes_song(artist, title, k) end)
    elseif series ~= "" then
        if anime then add(function(k) from_anilist(series, k) end) end
        add(function(k) from_tvmaze(series, false, k) end)
        if not anime then add(function(k) from_anilist(series, k) end) end
        add(function(k) from_itunes_season(series, k) end)
    elseif title ~= "" and not music then
        if anime then add(function(k) from_anilist(title, k) end) end
        add(function(k) from_itunes_movie(title, k) end)
        add(function(k) from_tvmaze(title, true, k) end)
    end
    first(tries, function(u)
        local function by_app() if app ~= "" then art_app(app, done) else done(false) end end
        if not u then by_app() return end
        art_get(u, 1, function(a) if a then done(a) else by_app() end end)
    end)
end
local art_shown = ""
local function art_show(a)
    if not a then
        if art_shown ~= "" then art_shown = ""; fact.tv_has_pic = false; fact.tv_has_appic = false end
        return
    end
    if art_shown == a.path then return end
    art_shown = a.path
    if a.kind == 1 then
        model.tv_pic = { { img = a.path } }
        fact.tv_has_appic = false
        fact.tv_has_pic = true
    else
        model.tv_appic = { { img = a.path } }
        fact.tv_has_pic = false
        fact.tv_has_appic = true
    end
end
local function tv_fill()
    local it = tv_item()
    if not it or fact.tv_open ~= true then return end
    local t = it.tv.media and tvs[it.tv.media]
    local code = tv_code(t)
    text.tv_name = it.name
    text.tv_icon = it.file and "" or it.icon
    fact.tv_custom = own_pic(it)
    fact.tv_has_rm = it.tv.remote ~= nil
    fact.tv_st = code
    local app = t and t.app or ""
    text.tv_app = code > 0 and app or ""
    fact.tv_app_on = code > 0 and app ~= ""
    text.tv_status = T(TV_LABEL[code]) .. ((code > 0 and app ~= "") and (" · " .. app) or "")
    local title = t and t.title or ""
    text.tv_title = title ~= "" and title or (code > 0 and app ~= "" and app or T("tv_nothing"))
    local sub = title ~= "" and ((t.series ~= "" and t.series) or t.artist or "") or ""
    text.tv_sub = sub ~= title and sub or ""
    local p = tv_now(t)
    fact.tv_has_prog = p >= 0 and code >= 2
    if p >= 0 then
        fact.tv_prog = p / t.dur
        text.tv_pos = clock(p)
        text.tv_rem = "-" .. clock(t.dur - p)
    end
    -- the artwork: fetched again when it changes (its address carries a token that changes by itself)
    local pic = (t and code > 0) and t.pic or ""
    if pic ~= "" then
        if art_shown ~= "" then art_shown = ""; fact.tv_has_appic = false end
        local key = (pic:gsub("token=[^&]*", ""))
        if key ~= tv_shown or (tv_retry and tick >= tv_retry) then tv_shown = key; tv_retry = nil; tv_fetch(pic) end
        return
    end
    if tv_shown ~= "none" then
        tv_shown = "none"
        fact.tv_has_pic = false
    end
    -- none from Home Assistant: the one looked up (or being looked up) for what plays
    if code == 0 or not cfg.art_search or (title == "" and app == "") then art_show(false) return end
    local key = app .. "|" .. (t.series or "") .. "|" .. (t.artist or "") .. "|" .. title
    if art[key] ~= nil then art_show(art[key]) return end
    if art_busy[key] then return end
    art_busy[key] = true
    art_find(t, function(a)
        art[key] = a or false
        art_busy[key] = nil
        tv_fill()
    end)
end
local function tv_poll()
    if tv_busy or not cfg or cfg.demo then return end
    local ids, seen = {}, {}
    for _, it in ipairs(cfg.items) do
        local m = it.tv and it.tv.media
        if m and not seen[m] then seen[m] = true; ids[#ids + 1] = m end
    end
    if #ids == 0 then return end
    local quoted = {}
    for k, e in ipairs(ids) do quoted[k] = '"' .. e .. '"' end
    -- the state, the title, the artist, the series, the app, the length, the position and how long ago it was told (seconds), the artwork, the volume and
    -- what kind of thing it is (music, video…)
    local tpl = "[{% for e in [" .. table.concat(quoted, ",") .. "] %}{% set u = state_attr(e, 'media_position_updated_at') %}[{{ states(e) | tojson }},{{ (state_attr(e, 'media_title') or '') | tojson }},{{ (state_attr(e, 'media_artist') or state_attr(e, 'media_album_artist') or '') | tojson }},{{ (state_attr(e, 'media_series_title') or '') | tojson }},{{ (state_attr(e, 'app_name') or state_attr(e, 'source') or '') | tojson }},{{ state_attr(e, 'media_duration') | float(0) }},{{ state_attr(e, 'media_position') | float(-1) }},{{ ((as_timestamp(now()) - as_timestamp(u, as_timestamp(now()))) | round(1)) if u else 0 }},{{ (state_attr(e, 'entity_picture') or '') | tojson }},{{ state_attr(e, 'volume_level') | float(-1) }},{{ (state_attr(e, 'media_content_type') or '') | tojson }}]{{ ',' if not loop.last }}{% endfor %}]"
    tv_busy = true
    call("/api/template", json.encode({ template = tpl }), function(ok, out)
        tv_busy = false
        if not ok then return end
        local okj, list = pcall(json.decode, out)
        if not okj or type(list) ~= "table" then return end
        for k, e in ipairs(ids) do
            local r = list[k]
            if type(r) == "table" then
                tvs[e] = { st = tostring(r[1] or "unknown"), title = tostring(r[2] or ""), artist = tostring(r[3] or ""), series = tostring(r[4] or ""),
                    app = tostring(r[5] or ""), dur = tonumber(r[6]) or 0, pos = tonumber(r[7]) or -1, el = tonumber(r[8]) or 0, pic = tostring(r[9] or ""), vol = tonumber(r[10]) or -1, ctype = tostring(r[11] or ""), at = tick,
                    unmute = tvs[e] and tvs[e].unmute or nil }
            end
        end
        show()
    end)
end

show = function()
    local rows, heads = {}, {}
    if cfg then
        for i, it in ipairs(cfg.items) do
            local s = state[i] or { on = false, bri = 0, avail = false }
            local p = place[i] or { col = 0, cs = 1, rs = 1, yu = 0 }
            local sub
            if it.bad then
                sub = T("bad", it.entity)
            elseif not s.avail then
                sub = s.known and T("unavailable") or "…"
            elseif it.kind == 0 then
                sub = s.on and ((it.on_text or T("light_on")) .. " · " .. math.floor(s.bri * 100 + 0.5) .. " %") or (it.off_text or T("light_off"))
            else
                sub = s.on and (it.on_text or T("on")) or (it.off_text or T("off"))
            end
            local pp = -1
            if it.printer then
                local pr = pr_read(it)
                if pr.code == 1 or pr.code == 2 or pr.code == 5 then       -- printing, paused or getting ready: that, and how far, instead of the light's line
                    sub = T(PR_LABEL[pr.code]) .. (pr.prog and (" · " .. math.floor(pr.prog + 0.5) .. " %") or "")
                    pp = pr.prog and math.max(0, math.min(1, pr.prog / 100)) or -1
                end
            end
            if it.tv and it.tv.media and not it.bad then
                local t = tvs[it.tv.media]
                local code = tv_code(t)
                if code >= 2 then          -- playing or paused: that, and what (or in which app), instead of the tile's line
                    local what = (t.title ~= "" and t.title) or t.app
                    sub = T(TV_LABEL[code]) .. (what ~= "" and (" · " .. what) or "")
                end
            end
            rows[#rows + 1] = { name = it.name, icon = it.file and "" or it.icon, img = it.file and (folder .. "/" .. it.file) or "", custom = own_pic(it) and 1 or 0, dk = dev_k(it), sub = sub, on = s.on and 1 or 0, kind = it.kind, bri = s.bri or 0,
                avail = (s.avail and not it.bad) and 1 or 0, col = p.col, cs = p.cs, rs = p.rs, yu = p.yu, prn = it.printer and 1 or 0, pp = pp,
                cc = it.color and 1 or 0, ct = it.tint and 1 or 0, hk = ((it.color or it.tint) and s.hs) and 1 or 0, hu = s.hs and s.hs.h or 0, sa = s.hs and s.hs.s or 0,
                tvr = it.tv and 1 or 0, pk = pencil_k(it) }
        end
        for k, room in ipairs(cfg.rooms) do
            if room.name ~= "" then
                local t, h = "", ""
                local te = room.temp and est[room.temp]
                local he = room.hum and est[room.hum]
                local tv = te and tonumber(te.st)
                local hv = he and tonumber(he.st)
                if tv then t = decimal(tv, 1) .. " " .. ((te.unit ~= "" and te.unit) or "°C") end
                if hv then h = decimal(hv, 0) .. " %" end
                heads[#heads + 1] = { name = room.name, temp = t, hum = h, has_t = t ~= "" and 1 or 0, has_h = h ~= "" and 1 or 0, yu = room_yu[k] or 0 }
            end
        end
    end
    pr_fill()
    tv_fill()
    -- (only what changed: the poll answers every few seconds, mostly with the same)
    local sig = json.encode({ rows, heads, content })
    if sig == last_sig then return end
    last_sig = sig
    fact.hl_content = content
    model.hl_items = rows
    model.hl_rooms = heads
end

-- curl, with the token from auth.curl. `body`: a JSON text to POST (on curl's input), or nil for a GET. `done(ok, out, err)`.
call = function(path, body, done)
    if not cfg then return end
    if cfg.demo then done(true, "[]", nil) return end          -- (the demo asks nothing of anybody: what was pressed has already changed here)
    local args = { "-s", "-K", folder .. "/" .. AUTH, "--max-time", "6", "-w", "\n%{http_code}" }
    if cfg.insecure then args[#args + 1] = "-k" end
    local opts = nil
    if body then
        for _, a in ipairs({ "-X", "POST", "-H", "Content-Type: application/json", "--data-binary", "@-" }) do args[#args + 1] = a end
        opts = { input = body }
    end
    args[#args + 1] = cfg.url .. path
    run("curl", args, function(out, code)
        out = out or ""
        if code ~= 0 then
            local why = ({ [6] = T("e6", cfg.url), [7] = T("e7", cfg.url), [28] = T("e28"), [35] = T("e35"), [60] = T("e60") })[code]
            done(false, nil, why or T("ecurl", tostring(code)))
            return
        end
        local body_out, status = out:match("^(.*)\n(%d+)%s*$")
        status = tonumber(status) or 0
        if status == 401 then done(false, nil, T("e401")) return end
        if status == 404 then done(false, nil, T("e404")) return end
        if status < 200 or status >= 300 then done(false, nil, T("ehttp", tostring(status))) return end
        done(true, body_out or "", nil)
    end, opts)
end

local function poll()
    if busy or not cfg then return end
    if cfg.demo then set_state(1, T("demo")); show(); return end
    -- every entity once: the tiles' and the rooms' sensors
    local ids, seen = {}, {}
    local function want(e)
        if valid(e) and not seen[e] then seen[e] = true; ids[#ids + 1] = e end
    end
    for _, it in ipairs(cfg.items) do if not it.bad then want(it.entity) end end
    for _, room in ipairs(cfg.rooms) do want(room.temp); want(room.hum) end
    for _, it in ipairs(cfg.items) do
        if it.printer then for _, k in ipairs(PR_POLL) do want(it.printer[k]) end end
    end
    tv_poll()
    if #ids == 0 then
        set_state(1, T("no_tiles"))
        show()
        return
    end
    local quoted = {}
    for k, e in ipairs(ids) do quoted[k] = '"' .. e .. '"' end
    -- The state, the brightness (0 to 255), the unit, the picture's address (an image's or a camera's), the colour (hue and saturation, a light's) and, for a time, when it is (HH:MM, or dd/mm HH:MM
    -- another day, in Home Assistant's time zone) of each entity, as a JSON list, in the order of `ids`.
    local tpl = "[{% for e in [" .. table.concat(quoted, ",") .. "] %}{% set ts = as_timestamp(states(e), none) %}[{{ states(e) | tojson }},{{ (state_attr(e, 'brightness') or 0) | int }},{{ (state_attr(e, 'unit_of_measurement') or '') | tojson }},{{ (state_attr(e, 'entity_picture') or '') | tojson }},{{ (state_attr(e, 'hs_color') or []) | list | tojson }},{% if ts is not none %}{{ (ts | timestamp_custom('%H:%M') if (ts | timestamp_custom('%Y%m%d')) == now().strftime('%Y%m%d') else ts | timestamp_custom('%d/%m %H:%M')) | tojson }}{% else %}\"\"{% endif %}]{{ ',' if not loop.last }}{% endfor %}]"
    busy = true
    call("/api/template", json.encode({ template = tpl }), function(ok, out, err)
        busy = false
        if not ok then
            set_state(2, T("offline"), err)
            show()
            return
        end
        local okj, list = pcall(json.decode, out)
        if not okj or type(list) ~= "table" then
            set_state(2, T("odd"), T("odd_msg"))
            return
        end
        for k, e in ipairs(ids) do
            local row = list[k]
            if type(row) == "table" then est[e] = { st = tostring(row[1] or "unknown"), bri = tonumber(row[2]) or 0, unit = tostring(row[3] or ""), pic = tostring(row[4] or ""), hs = row[5], tm = tostring(row[6] or "") } end
        end
        local count = 0
        for i, it in ipairs(cfg.items) do
            local e = not it.bad and est[it.entity]
            if e and not (hold_until[i] and tick < hold_until[i]) then
                local st = e.st
                local s = state[i] or {}
                s.known = true
                s.avail = st ~= "unavailable" and st ~= "unknown"
                s.on = st == "on" or st == "open" or st == "playing" or st == "paused" or st == "idle" or st == "buffering" or st == "home"
                if it.kind == 0 then s.bri = s.on and math.max(0.01, e.bri / 255) or 0 end
                -- its colour, when it says one (a light that is off says none: the last one is kept)
                local hs = e.hs
                if (it.color or it.tint) and type(hs) == "table" and tonumber(hs[1]) and tonumber(hs[2]) then
                    s.hs = { h = (tonumber(hs[1]) % 360) / 360, s = math.max(0, math.min(1, tonumber(hs[2]) / 100)) }
                end
                state[i] = s
            end
            if state[i] and state[i].avail then count = count + 1 end
        end
        set_state(1, T("connected", count, #cfg.items, #cfg.items == 1 and T("tile") or T("tiles")))
        show()
    end)
end

-- A tile's "printer": the entities it names (any of PR_KEYS), the ones that are valid ids. None: no printer.
local function parse_printer(p)
    if type(p) ~= "table" then return nil end
    local out, any = {}, false
    for _, k in ipairs(PR_KEYS) do
        if valid(p[k]) then out[k] = p[k]; any = true end
    end
    return any and out or nil
end

-- A tile's "apple_tv": its media player (the tile's own entity if it is one) and, for the remote, its remote entity. Neither: no card.
local function parse_tv(t, entity)
    if type(t) ~= "table" then return nil end
    local media = valid(t.media_player) and t.media_player or (valid(entity) and entity:match("^media_player%.") and entity or nil)
    local remote = valid(t.remote) and t.remote:match("^remote%.") and t.remote or nil
    if not media and not remote then return nil end
    return { media = media, remote = remote }
end

local function load()
    folder = sys.ask("files.folder") or ""
    for name, svg in pairs(ICONS) do
        local okr, have = pcall(sys.ask, "files.read", name)
        if not okr or have ~= svg .. "\n" and have ~= svg then pcall(sys.call, "files.write", name, svg .. "\n") end
    end
    if not sys.ask("files.exists", CONFIG) then
        pcall(sys.call, "files.write", CONFIG, EXAMPLE)
    end
    local okl, saved = pcall(sys.ask, "files.read", LAYOUT, "json")
    sizes = {}
    if okl and type(saved) == "table" and type(saved.sizes) == "table" then
        for e, sz in pairs(saved.sizes) do
            if type(sz) == "table" then sizes[e] = { tonumber(sz[1]) or 1, tonumber(sz[2]) or 1 } end
        end
    end
    local ok, c = pcall(sys.ask, "files.read", CONFIG, "json")
    lang_files()
    use_lang(ok and type(c) == "table" and c.language or nil)
    scene_words()
    cfg = nil
    state = {}
    est = {}
    tvs = {}
    last_sig = ""
    if not ok or type(c) ~= "table" then
        set_state(3, T("not_set"), T("unreadable", (tostring(c):gsub("^.-: ", ""))))
        show()
        return
    end
    local url = type(c.url) == "string" and c.url:gsub("/+$", "") or ""
    local token = type(c.token) == "string" and c.token or ""
    local demo = token == "" or token == "PEGA_AQUI_TU_TOKEN" or token == "PASTE_YOUR_TOKEN_HERE"
    fact.hl_demo = demo
    if not demo and not url:match("^https?://.+") then
        set_state(3, T("not_set"), T("need_url"))
        show()
        return
    end
    if not demo and not token:match("^[%w%._%-]+$") then
        set_state(3, T("not_set"), T("need_token"))
        show()
        return
    end
    local rooms, items = {}, {}
    local function add_items(list, k, croom)
        for n, it in ipairs(type(list) == "table" and list or {}) do
            if type(it) == "table" and type(it.entity) == "string" and #items < MAX_ITEMS then
                local entity = it.entity
                local kind = (it.type == "light" or (it.type == nil and entity:match("^light%."))) and 0 or 1
                items[#items + 1] = {
                    kind = kind,
                    entity = entity,
                    name = type(it.name) == "string" and it.name or entity,
                    icon = type(it.icon) == "string" and it.icon ~= "" and it.icon or (kind == 0 and "lightbulb" or "toggle_on"),
                    -- an icon of its own: a file in the data folder (only a plain name: the folder is all a scene may read)
                    file = type(it.icon) == "string" and it.icon:match("^[%w%._%-]+%.[sp][vn]g$") and (ALIAS[it.icon] or it.icon) or nil,
                    on_text = type(it.on_text) == "string" and it.on_text or nil,
                    off_text = type(it.off_text) == "string" and it.off_text or nil,
                    bad = not valid(entity),
                    printer = parse_printer(it.printer),
                    color = kind == 0 and it.color == true,          -- its colour is chosen in the card too
                    tint = kind == 0 and it.tint == true,            -- its tile and card are drawn in its own colour, not the accent
                    tv = parse_tv(it.apple_tv, entity),
                    room = k,
                    croom = croom, cidx = n,         -- where it is in config.json: the room there (0: the top level's items) and its place in it
                }
            end
        end
    end
    -- the tiles at the top level (a config.json from before rooms, or tiles that belong to none): a room with no name, first
    if type(c.items) == "table" and #c.items > 0 then
        rooms[1] = { name = "", croom = 0 }
        add_items(c.items, 1, 0)
    end
    for cr, r in ipairs(type(c.rooms) == "table" and c.rooms or {}) do
        if type(r) == "table" and #rooms < MAX_ROOMS then
            local k = #rooms + 1
            rooms[k] = {
                name = type(r.name) == "string" and r.name or T("room", k),
                temp = valid(r.temperature) and r.temperature or nil,
                hum = valid(r.humidity) and r.humidity or nil,
                croom = cr,
            }
            add_items(r.items, k, cr)
        end
    end
    cfg = { url = url, insecure = c.insecure == true, rooms = rooms, items = items, art_search = c.artwork_search ~= false and not demo, demo = demo }
    if demo then
        -- The demo: config.json's own rooms (the example's, the first time), every tile working here and nowhere else: lights on and off at different levels, a colour
        -- on the ones that have one, a print half way, and something playing on a player.
        for i, it in ipairs(items) do
            state[i] = { known = true, avail = true, on = i % 3 ~= 0 or it.tv ~= nil, bri = 0.35 + 0.15 * (i % 4), hs = (it.color or it.tint) and { h = 0.76, s = 0.8 } or nil }
            if not state[i].on then state[i].bri = 0 end
            if it.printer then
                local P = it.printer
                if P.status then est[P.status] = { st = "running", unit = "", pic = "", tm = "" } end
                if P.progress then est[P.progress] = { st = "62", unit = "%", pic = "", tm = "" } end
                if P.remaining then est[P.remaining] = { st = "83", unit = "min", pic = "", tm = "" } end
                if P.task then est[P.task] = { st = T("demo_task"), unit = "", pic = "", tm = "" } end
                if P.start then est[P.start] = { st = "", unit = "", pic = "", tm = "14:02" } end
                if P["end"] then est[P["end"]] = { st = "", unit = "", pic = "", tm = "16:30" } end
            end
            if it.tv and it.tv.media then
                tvs[it.tv.media] = { st = "playing", title = T("demo_tv"), artist = "", series = "", app = "TV", dur = 5400, pos = 1500, el = 0, pic = "", vol = 0.5, ctype = "movie", at = tick }
            end
        end
        set_state(1, T("demo"))
        layout()
        show()
        return
    end
    local wrote = pcall(sys.call, "files.write", AUTH, 'header = "Authorization: Bearer ' .. token .. '"\n')
    if not wrote then
        set_state(2, T("offline"), T("no_auth"))
        return
    end
    set_state(0, T("connecting"))
    layout()
    show()
    poll()
end

-- What the tiles and the slider ask for
on("hl_tap", function(k)
    local i = (tonumber(k) or -1) + 1
    local it = cfg and cfg.items[i]
    local s = state[i]
    if not it or it.bad or not s or not s.avail then return end
    s.on = not s.on
    if it.kind == 0 and s.on and (s.bri or 0) <= 0 then s.bri = 1 end
    hold_until[i] = tick + 3
    show()
    local service = it.kind == 0 and "/api/services/light/toggle" or "/api/services/homeassistant/toggle"
    call(service, json.encode({ entity_id = it.entity }), function(ok, _, err)
        if not ok then set_state(2, T("offline"), err) end
        hold_until[i] = nil
        after(700, poll)
    end)
end)

on("hl_bri", function(v)
    local i = (tonumber(fact.sl_i) or -1) + 1
    local it = cfg and cfg.items[i]
    if not it or it.kind ~= 0 or it.bad then return end
    local pct = math.floor(math.max(0, math.min(1, tonumber(v) or 0)) * 100 + 0.5)
    local s = state[i] or {}
    s.on = pct > 0
    s.bri = pct / 100
    state[i] = s
    hold_until[i] = tick + 3
    show()
    local service, body = "/api/services/light/turn_on", { entity_id = it.entity, brightness_pct = pct }
    if pct == 0 then service, body = "/api/services/light/turn_off", { entity_id = it.entity } end
    call(service, json.encode(body), function(ok, _, err)
        if not ok then set_state(2, T("offline"), err) end
        after(900, function() hold_until[i] = nil; poll() end)
    end)
end)

-- A colour chosen in the card: hue in degrees times 1000 plus saturation in percent. Home Assistant takes it as hs_color; a light that is off is turned
-- on with it, at full brightness.
on("hl_color", function(v)
    local i = (tonumber(fact.sl_i) or -1) + 1
    local it = cfg and cfg.items[i]
    if not it or not it.color or it.bad then return end
    v = math.floor(tonumber(v) or 0)
    local h, sat = math.floor(v / 1000) % 361, math.max(0, math.min(100, v % 1000))
    local s = state[i] or {}
    local body = { entity_id = it.entity, hs_color = { h, sat } }
    if not s.on or (s.bri or 0) <= 0 then body.brightness_pct = 100; s.bri = 1 end
    s.on = true
    s.hs = { h = (h % 360) / 360, s = sat / 100 }
    state[i] = s
    hold_until[i] = tick + 3
    show()
    call("/api/services/light/turn_on", json.encode(body), function(ok, _, err)
        if not ok then set_state(2, T("offline"), err) end
        after(900, function() hold_until[i] = nil; poll() end)
    end)
end)

-- A size as it is shown while it is pulled: columns (½ for half of one) × rows
function size_words(hs, rs)
    local whole, half = math.floor(hs / 2), hs % 2 == 1
    return ((whole > 0 and tostring(whole) or "") .. (half and "½" or "")) .. " × " .. tostring(rs)
end
on("fact:rz_i", function(v)
    local i = (tonumber(v) or -1) + 1
    local p = place[i]
    if p then text.t_rz = size_words(p.cs, p.rs) end
end)

-- A tile carried to another place in edit mode: it takes the place of the tile it was dropped on (into that one's room), or goes to the end of the room it
-- was dropped in. config.json is written (settings.luau keeps it in order) and read again.
on("hl_move", function(code)
    code = math.floor(tonumber(code) or -1)
    if code < 0 or not cfg then return end
    local i = math.floor(code / 10000000) + 1
    local px, py = math.floor(code % 10000000 / 10000), code % 10000
    local it = cfg.items[i]
    if not it or not st then return end
    local cols = columns()
    local W = (tonumber(fact.slot_w) or 520) / 1.1
    local tw = (W - 28 - (cols - 1) * GAP) / cols
    local hw = (tw - GAP) / 2
    local target = nil
    for j, p in pairs(place) do
        local x0, y0 = 14 + p.col * (hw + GAP), p.yu
        local w, h = p.cs * hw + (p.cs - 1) * GAP, p.rs * TH + (p.rs - 1) * GAP
        if j ~= i and px >= x0 and px <= x0 + w and py >= y0 and py <= y0 + h then target = j; break end
    end
    if target then
        local to = cfg.items[target]
        st.move_item(it.croom, it.cidx, to.croom, to.cidx)
        return
    end
    -- no tile there: the room it was dropped in (the last whose head is above it)
    local room = nil
    for k = 1, #cfg.rooms do
        local top = room_yu[k] or 0
        if py >= top then room = k end
    end
    if room and cfg.rooms[room] then st.move_item(it.croom, it.cidx, cfg.rooms[room].croom, nil) end
end)

-- A tile pulled to a new size in edit mode: the others make room at once, and it is kept
local save_due = false
on("hl_resize", function(k)
    local it = cfg and cfg.items[(tonumber(k) or -1) + 1]
    if not it then return end
    local hs = math.max(1, math.min(8, math.floor((tonumber(fact.rz_w) or 2) + 0.5)))       -- in half columns
    local rs = math.max(1, math.min(3, math.floor((tonumber(fact.rz_h) or 1) + 0.5)))
    sizes[it.entity] = { hs / 2, rs }
    text.t_rz = size_words(hs, rs)
    layout()
    show()
    if not save_due then
        save_due = true
        after(800, function()
            save_due = false
            local out = {}
            for e, sz in pairs(sizes) do out[e] = { sz[1], sz[2] } end
            pcall(sys.call, "files.write", LAYOUT, { sizes = out })
        end)
    end
end)

-- The printer's card: opened (or on another printer), the camera switched, a button pressed
local function pr_reset()
    pr_shown = ""
    fact.pr_has_pic = false
    model.pr_pic = {}
    pr_fill()
end
on("fact:pr_arm", function(v) text.t_b1 = v == true and T("stop_sure") or T("stop") end)       -- (Stop pressed once asks; the scene disarms it)
on("fact:pr_open", function(v) if v == true then pr_reset(); poll() end end)
on("fact:pr_i", function() if fact.pr_open == true then pr_reset() end end)
on("fact:pr_cam", function(v)
    local it = pr_item()
    if not it then return end
    if v == true then
        local ce = it.printer.camera and est[it.printer.camera]
        if ce then pr_fetch(ce.pic) end
    else
        pr_shown = ""          -- (back to the cover)
        pr_fill()
    end
end)
on("pr_act", function(a)
    a = tonumber(a) or -1
    local it = pr_item()
    if not it then return end
    local P = it.printer
    if a == 4 then            -- the camera, full size: its stream, in the browser (the address carries the camera's own short-lived token)
        local ce = P.camera and est[P.camera]
        if ce and ce.pic ~= "" then run("xdg-open", { cfg.url .. (ce.pic:gsub("/api/camera_proxy/", "/api/camera_proxy_stream/")) }, function() end) end
        return
    end
    local target = ({ [0] = P.pause, [1] = P.resume, [2] = P.stop })[a]
    if not target then return end
    call("/api/services/button/press", json.encode({ entity_id = target }), function(ok, _, err)
        if not ok then set_state(2, T("offline"), err) end
        after(1500, poll)
    end)
end)

-- The slider asks which light it is on: its name and icon
-- The Apple TV's card: opened, and its buttons. The remote's go to the remote entity (remote.send_command, as the Apple TV integration takes them); the
-- transport and the power to the media player.
local tv_muted = false
local TV_REMOTE = { [0] = "up", "down", "left", "right", "select", "menu", "home", "play_pause", "volume_up", "volume_down" }
on("fact:tv_open", function(v) if v == true then tv_shown = ""; art_shown = ""; fact.tv_has_pic = false; fact.tv_has_appic = false; model.tv_pic = {}; tv_fill(); tv_poll() end end)
on("fact:tv_i", function() if fact.tv_open == true then tv_shown = ""; art_shown = ""; tv_fill() end end)
on("tv_cmd", function(c)
    c = tonumber(c) or -1
    local it = tv_item()
    if not it then return end
    local media, remote = it.tv.media, it.tv.remote
    local t = media and tvs[media]
    local svc, body
    if c == 10 then                                       -- power: on if it is off, off if not
        local was = tv_code(t)
        if media then
            svc, body = "/api/services/media_player/" .. (was == 0 and "turn_on" or "turn_off"), { entity_id = media }
        elseif remote then
            svc, body = "/api/services/remote/" .. (was == 0 and "turn_on" or "turn_off"), { entity_id = remote }
        end
        if t then t.st = was == 0 and "idle" or "off" end
    elseif c == 17 and media then                         -- mute: to nothing and back by its volume when it says one, else the player's own mute
        if t and t.vol >= 0 then
            local back = t.vol > 0.001
            if back then t.unmute = t.vol end
            local to = back and 0 or (t.unmute or 0.3)
            svc, body = "/api/services/media_player/volume_set", { entity_id = media, volume_level = to }
            t.vol = to
        else
            tv_muted = not tv_muted
            svc, body = "/api/services/media_player/volume_mute", { entity_id = media, is_volume_muted = tv_muted }
        end
    elseif (c == 11 or c == 12) and media then             -- previous, next
        svc, body = "/api/services/media_player/" .. (c == 11 and "media_previous_track" or "media_next_track"), { entity_id = media }
    elseif c == 15 and remote then                        -- the middle held: a long press
        svc, body = "/api/services/remote/send_command", { entity_id = remote, command = "select", hold_secs = 1 }
    elseif c == 16 and remote then                        -- TV held: the control centre
        svc, body = "/api/services/remote/send_command", { entity_id = remote, command = "home_hold" }
    elseif TV_REMOTE[c] and remote then
        svc, body = "/api/services/remote/send_command", { entity_id = remote, command = TV_REMOTE[c] }
    elseif media and (c == 7 or c == 8 or c == 9) then     -- no remote: the media player's own
        svc = "/api/services/media_player/" .. ({ [7] = "media_play_pause", [8] = "volume_up", [9] = "volume_down" })[c]
        body = { entity_id = media }
    end
    if not svc then return end
    if c == 7 and t then                                  -- play/pause: at once on the card, Home Assistant confirms it
        local code = tv_code(t)
        if code == 2 then t.pos = tv_now(t); t.el = 0; t.at = tick; t.st = "paused"
        elseif code == 3 then t.st = "playing"; t.at = tick; t.el = 0 end
    end
    tv_fill()
    call(svc, json.encode(body), function(ok, _, err)
        if not ok then set_state(2, T("offline"), err) end
        after(c <= 6 and 1500 or 800, tv_poll)
    end)
end)

on("fact:sl_i", function(v)
    local it = cfg and cfg.items[(tonumber(v) or -1) + 1]
    if it then
        text.sl_name = it.name
        text.sl_icon = it.file and "" or it.icon
        fact.sl_custom = own_pic(it)
    end
end)

on("hl_refresh", function()
    load()
end)

-- The gear: config.json in the user's editor. Vitreus's `vitreus-edit` finds it the same way for every add-on ($VISUAL / $EDITOR, the desktop's
-- text editor, the usual ones, a terminal one in a terminal) and exits with 3 when there is none: then the head says so for a few seconds, and the
-- file's path goes to the clipboard, so the gear never seems to do nothing. A Vitreus too old to have it (the command is not found) gets the
-- add-on's own way below.
local noed_gen = 0
local function own_editor(path)
    local editor = "nvim"
    for _, v in ipairs({ "VISUAL", "EDITOR" }) do
        local ok, val = pcall(sys.ask, "env", v)
        if ok and type(val) == "string" and val:match("%S") then editor = val; break end
    end
    local args = {}
    for word in editor:gmatch("%S+") do args[#args + 1] = word end
    args[#args + 1] = path
    run("xdg-terminal-exec", args, function(_, code)
        if code ~= 0 then run("xdg-open", { path }, function() end) end
    end)
end
local function edit_json()
    local path = folder .. "/" .. CONFIG
    run("vitreus-edit", { path }, function(_, code)
        if code == 3 then
            noed_gen = noed_gen + 1
            local mine = noed_gen
            run("wl-copy", { path }, function() end)
            local home = (select(2, pcall(sys.ask, "env", "HOME"))) or ""
            local short = (type(home) == "string" and home ~= "" and path:sub(1, #home) == home) and ("~" .. path:sub(#home + 1)) or path
            text.t_noed = T("no_editor", short)
            fact.hl_noed = true
            after(8000, function() if mine == noed_gen then fact.hl_noed = false end end)
        elseif code ~= 0 then
            own_editor(path)
        end
    end)
end
on("hl_edit", edit_json)

-- The panel resized: as many columns as now fit
local last_w = -1
on("fact:slot_w", function(v)
    if not cfg or tonumber(v) == last_w then return end
    last_w = tonumber(v) or -1
    layout()
    show()
    if st then st.width_changed() end
end)

-- Which monitor the panel is on: Vitreus sends its name (`slot_mon`) before `slot_open`, and the copy of this scene whose monitor has that name
-- (`screen.K.name`) is the one that draws (`hl_mon`). No copy with that name (an older Vitreus sends none): -1, and the scene goes by the size.
local function find_monitor()
    local name = text.slot_mon or ""
    local k = -1
    if name ~= "" then
        for c = 0, 3 do
            if text["screen." .. c .. ".name"] == name then k = c; break end
        end
    end
    if fact.hl_mon ~= k then fact.hl_mon = k end
end
on("text:slot_mon", find_monitor)

-- Vitreus tells the panel it is out again every two seconds while it is: only a real opening (shut before) asks Home Assistant at once and ends
-- edit mode on the way out.
on("fact:slot_open", function(v)
    local was = open
    open = v == true
    find_monitor()
    if open and not was then
        poll()
        if st then st.reopen() end          -- (the shell forgets a field when the panel shuts: the settings' one is placed again)
    elseif not open and was then
        fact.hl_editing = false          -- (edit mode ends with the panel)
        fact.rz_i = -1
        text.t_ed = T("ed_start")
    end
end)

-- config.json saved: read it again
-- The settings page (the gear): settings.luau
st = require("settings")({
    T = T, call = function(...) return call(...) end, folder = function() return folder end, cfg = function() return cfg end,
    edit_json = edit_json, PENCIL = PENCIL, DEV = DEV, ALIAS = ALIAS, lang = function() return lang end,
})

lang_reload = function() load(); if st then st.refresh() end end
sys.watch("files:" .. CONFIG, function()
    after(150, function() load(); if st then st.refresh() end end)
end)

every(1000, function()
    tick = tick + 1
    local period = open and 3 or 30
    if fact.hl_state == 2 then period = 10 end
    if fact.hl_state == 3 then return end
    if tick % period == 0 then poll() end
    if open and fact.tv_open == true then tv_fill() end
    if open and fact.pr_open == true and fact.pr_cam == true and tick % 2 == 0 then
        local it = pr_item()
        local ce = it and it.printer.camera and est[it.printer.camera]
        if ce then pr_fetch(ce.pic) end
    end
end)

load()
