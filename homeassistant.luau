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
  "_language": "The panel's language: \"en\" (English) or \"es\" (Spanish). Leave it out to follow the system's.",
  "language": "en",
  "_url": "Your Home Assistant's address, with http:// or https:// and the port (usually 8123).",
  "url": "http://homeassistant.local:8123",
  "_token": "A long-lived access token: in Home Assistant, your profile > Security > Long-lived access tokens > Create token.",
  "token": "PASTE_YOUR_TOKEN_HERE",
  "_insecure": "true only for https with a certificate of your own (self-signed).",
  "insecure": false,
  "_rooms": "The rooms, in order. name: its title. temperature and humidity (optional): a sensor whose reading is shown beside the name. items: its tiles.",
  "_items": "type: \"light\" (a click toggles it, a right click opens its brightness) or \"toggle\" (input_boolean, switch, plug, media player...). icon: a Material Symbols name (fonts.google.com/icons), e.g. lightbulb, light_group, floor_lamp, tv, power, bedtime, mode_fan, door_front, garage, or one of the add-on's own (see its README). on_text and off_text are optional. A tile's size is changed on the panel, with the pencil.",
  "rooms": [
    {
      "name": "Living room",
      "temperature": "sensor.living_room_temperature",
      "humidity": "sensor.living_room_humidity",
      "items": [
        { "type": "light",  "name": "Lamp",       "icon": "floor-lamp.svg", "entity": "light.living_room" },
        { "type": "toggle", "name": "Night mode", "icon": "bedtime",        "entity": "input_boolean.night_mode" }
      ]
    },
    {
      "name": "Office",
      "items": [
        { "type": "light",  "name": "Desk",       "icon": "desk",           "entity": "light.desk" }
      ]
    }
  ]
}
]]

-- What the panel says, in Spanish and in English (config.json's "language"; without it, the system's: LANG and the like). Every word the panel shows is
-- here, the scene's too: another language is another block with the same keys (and its code accepted in `load`, below); a key it lacks is said in English.
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
        hint = "Arrastra la esquina de una ficha", ed_start = "Cambiar el tamaño de las fichas", ed_done = "Terminar", refresh = "Actualizar",
        edit_cfg = "Editar la configuración", connecting_ha = "Conectando con Home Assistant…", title_offline = "Sin conexión",
        title_setup = "Configura Home Assistant", empty = "Aún no hay nada aquí",
        empty_hint = "Añade luces e interruptores en config.json: el engranaje de arriba lo abre.", brightness = "Brillo", close = "Cerrar",
        off_btn = "Apagar", resize = "Cambiar el tamaño de",
        -- the printer's card
        pr_idle = "En espera", pr_running = "Imprimiendo", pr_paused = "En pausa", pr_finished = "Terminada", pr_failed = "Fallida",
        pr_preparing = "Preparando", pr_offline = "Sin conexión", progress = "Progreso", pr_left = "Quedan %s", pr_started = "Empezó %s",
        pr_ends = "Termina %s", pr_ended = "Terminó %s", pause = "Pausar", resume = "Continuar", stop = "Detener", stop_sure = "¿Detener?",
        camera = "Cámara", live = "EN DIRECTO", open_cam = "Abrir la cámara",
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
        hint = "Drag a tile's corner", ed_start = "Resize the tiles", ed_done = "Done", refresh = "Refresh",
        edit_cfg = "Edit the settings", connecting_ha = "Connecting to Home Assistant…", title_offline = "Can't connect",
        title_setup = "Set up Home Assistant", empty = "Nothing here yet",
        empty_hint = "Add lights and switches in config.json: the gear above opens it.", brightness = "Brightness", close = "Close",
        off_btn = "Off", resize = "Resize",
        -- the printer's card
        pr_idle = "Idle", pr_running = "Printing", pr_paused = "Paused", pr_finished = "Finished", pr_failed = "Failed",
        pr_preparing = "Preparing", pr_offline = "Offline", progress = "Progress", pr_left = "%s left", pr_started = "Started %s",
        pr_ends = "Ends %s", pr_ended = "Ended %s", pause = "Pause", resume = "Resume", stop = "Stop", stop_sure = "Stop?",
        camera = "Camera", live = "LIVE", open_cam = "Open the camera",
    },
}
local lang = "en"
local function T(key, ...)
    local s = (STR[lang] or STR.en)[key] or STR.en[key] or key
    if select("#", ...) > 0 then return string.format(s, ...) end
    return s
end
-- The system's language: Spanish if the locale says so, English otherwise.
local function system_lang()
    for _, v in ipairs({ "LC_ALL", "LC_MESSAGES", "LANG" }) do
        local ok, val = pcall(sys.ask, "env", v)
        if ok and type(val) == "string" and val ~= "" and val ~= "C" and val ~= "POSIX" then
            return val:lower():match("^es") and "es" or "en"
        end
    end
    return "en"
end

-- English names for the add-on's own icons (the files keep their Spanish ones).
local ALIAS = {
    ["led-strip.svg"] = "tira-led.svg", ["wall-lantern.svg"] = "farol-pared.svg", ["pendant-lamp.svg"] = "lampara-pergola.svg",
    ["floor-lamp.svg"] = "lampara-pie.svg", ["3d-printer.svg"] = "impresora-3d.svg", ["tv-box.svg"] = "reproductor.svg",
    ["terrarium.svg"] = "terrario.svg", ["fan-heater.svg"] = "calefactor.svg",
}


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
    text.t_progress = T("progress")
    text.t_pause = T("pause")
    text.t_resume = T("resume")
    text.t_stop = T("stop")
    text.t_stop_sure = T("stop_sure")
    text.t_camera = T("camera")
    text.t_live = T("live")
    text.t_open_cam = T("open_cam")
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
        for i, it in ipairs(cfg.items) do
            if it.room == k then
                local sz = sizes[it.entity] or {}
                local cs = math.max(1, math.min(cols, tonumber(sz[1]) or 1))
                local rs = math.max(1, math.min(3, tonumber(sz[2]) or 1))
                local r, done = 0, false
                while not done do
                    for c = 0, cols - cs do
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
    fact.pr_custom = it.file ~= nil
    text.pr_task = pr.task ~= "" and pr.task or it.name
    fact.pr_st = pr.code
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

local function show()
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
            rows[#rows + 1] = { name = it.name, icon = it.file and "" or it.icon, img = it.file and (folder .. "/" .. it.file) or "", custom = it.file and 1 or 0, sub = sub, on = s.on and 1 or 0, kind = it.kind, bri = s.bri or 0,
                avail = (s.avail and not it.bad) and 1 or 0, col = p.col, cs = p.cs, rs = p.rs, yu = p.yu, prn = it.printer and 1 or 0, pp = pp }
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
    -- (only what changed: the poll answers every few seconds, mostly with the same)
    local sig = json.encode({ rows, heads, content })
    if sig == last_sig then return end
    last_sig = sig
    fact.hl_content = content
    model.hl_items = rows
    model.hl_rooms = heads
end

-- curl, with the token from auth.curl. `body`: a JSON text to POST (on curl's input), or nil for a GET. `done(ok, out, err)`.
local function call(path, body, done)
    if not cfg then return end
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
    if #ids == 0 then
        set_state(1, T("no_tiles"))
        show()
        return
    end
    local quoted = {}
    for k, e in ipairs(ids) do quoted[k] = '"' .. e .. '"' end
    -- The state, the brightness (0 to 255) and the unit of each entity, as a JSON list, in the order of `ids`.
    -- The state, the brightness (0 to 255), the unit, the picture's address (an image's or a camera's) and, for a time, when it is (HH:MM, or dd/mm HH:MM
    -- another day, in Home Assistant's time zone) of each entity, as a JSON list, in the order of `ids`.
    local tpl = "[{% for e in [" .. table.concat(quoted, ",") .. "] %}{% set ts = as_timestamp(states(e), none) %}[{{ states(e) | tojson }},{{ (state_attr(e, 'brightness') or 0) | int }},{{ (state_attr(e, 'unit_of_measurement') or '') | tojson }},{{ (state_attr(e, 'entity_picture') or '') | tojson }},{% if ts is not none %}{{ (ts | timestamp_custom('%H:%M') if (ts | timestamp_custom('%Y%m%d')) == now().strftime('%Y%m%d') else ts | timestamp_custom('%d/%m %H:%M')) | tojson }}{% else %}\"\"{% endif %}]{{ ',' if not loop.last }}{% endfor %}]"
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
            if type(row) == "table" then est[e] = { st = tostring(row[1] or "unknown"), bri = tonumber(row[2]) or 0, unit = tostring(row[3] or ""), pic = tostring(row[4] or ""), tm = tostring(row[5] or "") } end
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
    local want = ok and type(c) == "table" and type(c.language) == "string" and c.language:lower() or ""
    lang = STR[want] and want or system_lang()
    scene_words()
    cfg = nil
    state = {}
    est = {}
    last_sig = ""
    if not ok or type(c) ~= "table" then
        set_state(3, T("not_set"), T("unreadable", (tostring(c):gsub("^.-: ", ""))))
        show()
        return
    end
    local url = type(c.url) == "string" and c.url:gsub("/+$", "") or ""
    local token = type(c.token) == "string" and c.token or ""
    if not url:match("^https?://.+") then
        set_state(3, T("not_set"), T("need_url"))
        show()
        return
    end
    if token == "" or token == "PEGA_AQUI_TU_TOKEN" or token == "PASTE_YOUR_TOKEN_HERE" or not token:match("^[%w%._%-]+$") then
        set_state(3, T("not_set"), T("need_token"))
        show()
        return
    end
    local rooms, items = {}, {}
    local function add_items(list, k)
        for _, it in ipairs(type(list) == "table" and list or {}) do
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
                    room = k,
                }
            end
        end
    end
    -- the tiles at the top level (a config.json from before rooms, or tiles that belong to none): a room with no name, first
    if type(c.items) == "table" and #c.items > 0 then
        rooms[1] = { name = "" }
        add_items(c.items, 1)
    end
    for _, r in ipairs(type(c.rooms) == "table" and c.rooms or {}) do
        if type(r) == "table" and #rooms < MAX_ROOMS then
            local k = #rooms + 1
            rooms[k] = {
                name = type(r.name) == "string" and r.name or T("room", k),
                temp = valid(r.temperature) and r.temperature or nil,
                hum = valid(r.humidity) and r.humidity or nil,
            }
            add_items(r.items, k)
        end
    end
    cfg = { url = url, insecure = c.insecure == true, rooms = rooms, items = items }
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

-- A tile pulled to a new size in edit mode: the others make room at once, and it is kept
local save_due = false
on("hl_resize", function(k)
    local it = cfg and cfg.items[(tonumber(k) or -1) + 1]
    if not it then return end
    local cs = math.max(1, math.min(4, math.floor((tonumber(fact.rz_w) or 1) + 0.5)))
    local rs = math.max(1, math.min(3, math.floor((tonumber(fact.rz_h) or 1) + 0.5)))
    sizes[it.entity] = { cs, rs }
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

-- The slider asks which light it is on: its name and icon
-- The printer's card: opened (or on another printer), the camera switched, a button pressed
local function pr_reset()
    pr_shown = ""
    fact.pr_has_pic = false
    model.pr_pic = {}
    pr_fill()
end
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

on("fact:sl_i", function(v)
    local it = cfg and cfg.items[(tonumber(v) or -1) + 1]
    if it then
        text.sl_name = it.name
        text.sl_icon = it.file and "" or it.icon
        fact.sl_custom = it.file ~= nil
    end
end)

on("hl_refresh", function()
    load()
end)

-- The gear: config.json in the user's editor ($VISUAL, then $EDITOR, then nvim), in a terminal so that one that lives in a terminal works; if that fails,
-- whatever the desktop opens a .json with. A variable with arguments ("code -w") is split on its spaces.
on("hl_edit", function()
    local path = folder .. "/" .. CONFIG
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
end)

-- The panel resized: as many columns as now fit
local last_w = -1
on("fact:slot_w", function(v)
    if not cfg or tonumber(v) == last_w then return end
    last_w = tonumber(v) or -1
    layout()
    show()
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
    elseif not open and was then
        fact.hl_editing = false          -- (edit mode ends with the panel)
        fact.rz_i = -1
        text.t_ed = T("ed_start")
    end
end)

-- config.json saved: read it again
sys.watch("files:" .. CONFIG, function()
    after(150, load)
end)

every(1000, function()
    tick = tick + 1
    local period = open and 3 or 30
    if fact.hl_state == 2 then period = 10 end
    if fact.hl_state == 3 then return end
    if tick % period == 0 then poll() end
    if open and fact.pr_open == true and fact.pr_cam == true and tick % 2 == 0 then
        local it = pr_item()
        local ce = it and it.printer.camera and est[it.printer.camera]
        if ce then pr_fetch(ce.pic) end
    end
end)

load()
