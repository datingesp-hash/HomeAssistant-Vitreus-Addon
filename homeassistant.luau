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
  "_ayuda": "Configuración del addon de Home Assistant para Vitreus. Al guardar este archivo el panel se actualiza solo.",
  "_url": "La dirección de tu Home Assistant, con http:// o https:// y el puerto (normalmente 8123).",
  "url": "http://homeassistant.local:8123",
  "_token": "Un token de larga duración: en Home Assistant, tu perfil > Seguridad > Tokens de acceso de larga duración > Crear token.",
  "token": "PEGA_AQUI_TU_TOKEN",
  "_insecure": "Ponlo a true solo si usas https con un certificado propio (autofirmado).",
  "insecure": false,
  "_rooms": "Las habitaciones, en este orden. name: su nombre. temperature y humidity (opcionales): un sensor de Home Assistant cuya lectura sale junto al nombre. items: sus fichas.",
  "_items": "type: \"light\" (luz: clic enciende/apaga, clic derecho abre el brillo) o \"toggle\" (interruptor, input_boolean, enchufe...). icon: un nombre de Material Symbols (fonts.google.com/icons), por ejemplo lightbulb, light_group, floor_lamp, tv, power, bedtime, mode_fan, door_front, garage. on_text y off_text son opcionales. El tamaño de cada ficha se cambia en el panel, con el lápiz.",
  "rooms": [
    {
      "name": "Salón",
      "temperature": "sensor.salon_temperatura",
      "humidity": "sensor.salon_humedad",
      "items": [
        { "type": "light",  "name": "Salón",      "icon": "lightbulb", "entity": "light.salon" },
        { "type": "toggle", "name": "Modo noche", "icon": "bedtime",   "entity": "input_boolean.modo_noche", "on_text": "Activado", "off_text": "Desactivado" }
      ]
    },
    {
      "name": "Despacho",
      "items": [
        { "type": "light",  "name": "Escritorio", "icon": "desk",      "entity": "light.escritorio" }
      ]
    }
  ]
}
]]

local function set_state(n, status, msg)
    fact.hl_state = n
    text.hl_status = status
    text.hl_msg = msg or ""
end

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

local function show()
    local rows, heads = {}, {}
    if cfg then
        for i, it in ipairs(cfg.items) do
            local s = state[i] or { on = false, bri = 0, avail = false }
            local p = place[i] or { col = 0, cs = 1, rs = 1, yu = 0 }
            local sub
            if it.bad then
                sub = "Entidad no válida: " .. it.entity
            elseif not s.avail then
                sub = s.known and "No disponible" or "…"
            elseif it.kind == 0 then
                sub = s.on and ((it.on_text or "Encendida") .. " · " .. math.floor(s.bri * 100 + 0.5) .. " %") or (it.off_text or "Apagada")
            else
                sub = s.on and (it.on_text or "Activado") or (it.off_text or "Desactivado")
            end
            rows[#rows + 1] = { name = it.name, icon = it.file and "" or it.icon, img = it.file and (folder .. "/" .. it.file) or "", custom = it.file and 1 or 0, sub = sub, on = s.on and 1 or 0, kind = it.kind, bri = s.bri or 0,
                avail = (s.avail and not it.bad) and 1 or 0, col = p.col, cs = p.cs, rs = p.rs, yu = p.yu }
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
            local why = ({ [6] = "No se encuentra la dirección " .. cfg.url, [7] = "No se puede conectar con " .. cfg.url, [28] = "Home Assistant tarda demasiado en responder",
                [35] = "Fallo de https (¿certificado propio? prueba \"insecure\": true)", [60] = "Certificado https no válido (prueba \"insecure\": true)" })[code]
            done(false, nil, why or ("curl ha fallado (código " .. tostring(code) .. ")"))
            return
        end
        local body_out, status = out:match("^(.*)\n(%d+)%s*$")
        status = tonumber(status) or 0
        if status == 401 then done(false, nil, "Token incorrecto o caducado (401): crea uno nuevo en tu perfil de Home Assistant") return end
        if status == 404 then done(false, nil, "Home Assistant no reconoce la dirección (404): revisa la url") return end
        if status < 200 or status >= 300 then done(false, nil, "Home Assistant ha respondido con un error (" .. status .. ")") return end
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
    if #ids == 0 then
        set_state(1, "Conectado · sin fichas")
        show()
        return
    end
    local quoted = {}
    for k, e in ipairs(ids) do quoted[k] = '"' .. e .. '"' end
    -- The state, the brightness (0 to 255) and the unit of each entity, as a JSON list, in the order of `ids`.
    local tpl = "[{% for e in [" .. table.concat(quoted, ",") .. "] %}[{{ states(e) | tojson }},{{ (state_attr(e, 'brightness') or 0) | int }},{{ (state_attr(e, 'unit_of_measurement') or '') | tojson }}]{{ ',' if not loop.last }}{% endfor %}]"
    busy = true
    call("/api/template", json.encode({ template = tpl }), function(ok, out, err)
        busy = false
        if not ok then
            set_state(2, "Sin conexión", err)
            show()
            return
        end
        local okj, list = pcall(json.decode, out)
        if not okj or type(list) ~= "table" then
            set_state(2, "Respuesta extraña", "Home Assistant ha respondido algo que no se entiende")
            return
        end
        for k, e in ipairs(ids) do
            local row = list[k]
            if type(row) == "table" then est[e] = { st = tostring(row[1] or "unknown"), bri = tonumber(row[2]) or 0, unit = tostring(row[3] or "") } end
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
        set_state(1, "Conectado · " .. count .. " de " .. #cfg.items .. (#cfg.items == 1 and " ficha" or " fichas"))
        show()
    end)
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
    cfg = nil
    state = {}
    est = {}
    last_sig = ""
    if not ok or type(c) ~= "table" then
        set_state(3, "Sin configurar", "config.json no se puede leer: " .. tostring(c):gsub("^.-: ", ""))
        show()
        return
    end
    local url = type(c.url) == "string" and c.url:gsub("/+$", "") or ""
    local token = type(c.token) == "string" and c.token or ""
    if not url:match("^https?://.+") then
        set_state(3, "Sin configurar", "Pon la dirección de tu Home Assistant en \"url\" (por ejemplo http://192.168.1.10:8123).")
        show()
        return
    end
    if token == "" or token == "PEGA_AQUI_TU_TOKEN" or not token:match("^[%w%._%-]+$") then
        set_state(3, "Sin configurar", "Falta el token: créalo en tu perfil de Home Assistant (Seguridad > Tokens de acceso de larga duración) y pégalo en \"token\".")
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
                    file = type(it.icon) == "string" and it.icon:match("^[%w%._%-]+%.[sp][vn]g$") and it.icon or nil,
                    on_text = type(it.on_text) == "string" and it.on_text or nil,
                    off_text = type(it.off_text) == "string" and it.off_text or nil,
                    bad = not valid(entity),
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
                name = type(r.name) == "string" and r.name or ("Habitación " .. k),
                temp = valid(r.temperature) and r.temperature or nil,
                hum = valid(r.humidity) and r.humidity or nil,
            }
            add_items(r.items, k)
        end
    end
    cfg = { url = url, insecure = c.insecure == true, rooms = rooms, items = items }
    local wrote = pcall(sys.call, "files.write", AUTH, 'header = "Authorization: Bearer ' .. token .. '"\n')
    if not wrote then
        set_state(2, "Sin conexión", "No se puede escribir auth.curl en la carpeta del addon")
        return
    end
    set_state(0, "Conectando…")
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
        if not ok then set_state(2, "Sin conexión", err) end
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
        if not ok then set_state(2, "Sin conexión", err) end
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

on("hl_edit", function()
    local path = folder .. "/" .. CONFIG
    run("xdg-terminal-exec", { "nvim", path }, function(_, code)
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

-- Which monitor the panel is on. The scene has a copy on each monitor, and Vitreus says only the size of the panel's one, which does not tell
-- two monitors of the same size apart. So: the monitor Hyprland has focused (the pill was just clicked on it), and which copy is on that monitor,
-- read from what each copy writes (`hlmon NAME`, see homeassistant.plm), with `describe`. If any of that fails, by size as before (hl_mon -1).
local copies = {}           -- monitor name → copy number, as `describe` last said
local asked = 0             -- so that only the answer to the last question counts

local function learn_copies(done)
    run("pleamar", { "--say", "homeassistant", "describe" }, function(out, code)
        if code == 0 and out then
            local found, n = {}, 0
            local cur = 0
            for line in (out .. "\n"):gmatch("([^\n]*)\n") do
                if not line:match("^%s") then
                    cur = tonumber(line:match("%(screen (%d+)%)")) or 0
                else
                    local name = line:match("«hlmon (%S+)»")
                    if name then found[name] = cur; n = n + 1 end
                end
            end
            if n > 0 then copies = found end
        end
        done()
    end)
end

local function find_monitor()
    asked = asked + 1
    local mine = asked
    run("hyprctl", { "monitors", "-j" }, function(out, code)
        if mine ~= asked then return end
        local focused
        if code == 0 and out then
            local ok, list = pcall(json.decode, out)
            if ok and type(list) == "table" then
                for _, m in ipairs(list) do
                    if type(m) == "table" and m.focused == true then focused = m.name end
                end
            end
        end
        if not focused then fact.hl_mon = -1 return end
        local function pick()
            if mine ~= asked then return end
            local k = copies[focused]
            fact.hl_mon = k or -1
        end
        if copies[focused] ~= nil then pick() else learn_copies(pick) end
    end)
end

-- Vitreus tells the panel it is out again every two seconds while it is: only a real opening (shut before) works out the monitor again, or the
-- panel would blink at every reminder and follow the mouse to the other monitor.
on("fact:slot_open", function(v)
    local was = open
    open = v == true
    if open and not was then
        fact.hl_mon = -2
        find_monitor()
        poll()
    elseif not open and was then
        fact.hl_editing = false          -- (edit mode ends with the panel)
        fact.rz_i = -1
    end
end)

-- Monitors plugged in or out: which copy is on which is learnt again
learn_copies(function() end)
every(60000, function() learn_copies(function() end) end)

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
end)

load()
