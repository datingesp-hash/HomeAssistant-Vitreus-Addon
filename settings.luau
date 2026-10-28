-- The settings page (the gear): the add-on's settings and its entities, edited on the panel instead of in config.json. It lays the page out as rows the scene draws
-- (`st_rows`, `st_sws`, `st_chips`, `st_icons`, `st_ents`, each with its place, unscaled, from the top of the page's scrolling list), reads config.json and writes it
-- back (in a fixed order, its notes kept), and keeps the one text field the shell lends an add-on on the field being written in.
--
-- The field: the scene leaves no zone of its own over the field the pointer is on (`st_fa`), and this tells the shell where that field is (`axf_*`, from the top left
-- of the content, in pixels), so a click there goes to the shell, which takes the keys and sends back what is written (`field_q`), and Enter and Escape.
--
-- What it is given (homeassistant.luau): `api.T` (the words), `api.call` (Home Assistant's REST API), `api.folder()`, `api.cfg()` (the configuration as loaded),
-- `api.edit_json()` (config.json in an editor), `api.PENCIL` (icon names → the pencil's icons), `api.DEV` and `api.ALIAS` (the add-on's own icons).

return function(api)
    local T = api.T
    local U = 1.1                                    -- the scene's unit
    local TOP = 104                                  -- where the page's list starts, unscaled, from the top of the content
    local CONFIG = "config.json"

    -- ── config.json: read as it is, written back in a fixed order ──
    local function read_cfg()
        local ok, c = pcall(sys.ask, "files.read", CONFIG, "json")
        if ok and type(c) == "table" then return c end
        return nil
    end
    local ORDER = {
        top = { "_help", "_language", "language", "_url", "url", "_token", "token", "_insecure", "insecure", "_artwork_search", "artwork_search", "_rooms", "_items", "rooms", "items" },
        room = { "name", "temperature", "humidity", "items" },
        item = { "type", "name", "icon", "entity", "color", "tint", "on_text", "off_text", "apple_tv", "printer" },
        apple_tv = { "media_player", "remote" },
        printer = { "task", "progress", "remaining", "status", "start", "end", "cover", "camera", "pause", "resume", "stop" },
    }
    local function is_array(t)
        if type(t) ~= "table" then return false end
        local n = 0
        for _ in pairs(t) do n = n + 1 end
        return n == #t
    end
    local enc
    local function enc_obj(t, ind, order, child)
        local keys, seen = {}, {}
        for _, k in ipairs(order or {}) do if t[k] ~= nil then keys[#keys + 1] = k; seen[k] = true end end
        local rest = {}
        for k in pairs(t) do if not seen[k] then rest[#rest + 1] = tostring(k) end end
        table.sort(rest)
        for _, k in ipairs(rest) do keys[#keys + 1] = k end
        if #keys == 0 then return "{}" end
        local pad = string.rep("  ", ind + 1)
        local parts = {}
        for _, k in ipairs(keys) do
            parts[#parts + 1] = pad .. json.encode(k) .. ": " .. enc(t[k], ind + 1, child and child(k))
        end
        return "{\n" .. table.concat(parts, ",\n") .. "\n" .. string.rep("  ", ind) .. "}"
    end
    -- `kind`: what the value is ("top", "rooms", "room", "items", "item", "apple_tv", "printer"), for the order of its keys
    enc = function(v, ind, kind)
        if type(v) == "table" then
            if kind == "rooms" or kind == "items" or (is_array(v) and #v > 0) then
                if #v == 0 then return "[]" end
                local pad = string.rep("  ", ind + 1)
                local parts = {}
                for _, x in ipairs(v) do parts[#parts + 1] = pad .. enc(x, ind + 1, kind == "rooms" and "room" or (kind == "items" and "item" or nil)) end
                return "[\n" .. table.concat(parts, ",\n") .. "\n" .. string.rep("  ", ind) .. "]"
            end
            local child = nil
            if kind == "top" then child = function(k) return (k == "rooms" and "rooms") or (k == "items" and "items") or nil end
            elseif kind == "room" then child = function(k) return k == "items" and "items" or nil end
            elseif kind == "item" then child = function(k) return (k == "apple_tv" and "apple_tv") or (k == "printer" and "printer") or nil end end
            return enc_obj(v, ind, ORDER[kind], child)
        end
        return json.encode(v)
    end
    local function write_cfg(c)
        return pcall(sys.call, "files.write", CONFIG, enc(c, 0, "top") .. "\n")
    end

    -- ── Home Assistant's entities, for the suggestions under a field: asked when a page that needs them opens ──
    local ha = {}                                    -- { id, name, class }
    local ha_has = {}
    local function fetch_ha(done)
        local c = api.cfg()
        if not c or c.demo then ha, ha_has = {}, {}; if done then done() end return end
        local tpl = "[{% for s in states %}[{{ s.entity_id | tojson }},{{ s.name | tojson }},{{ (s.attributes.device_class or '') | tojson }}]{{ ',' if not loop.last }}{% endfor %}]"
        api.call("/api/template", json.encode({ template = tpl }), function(ok, out)
            if ok then
                local okj, list = pcall(json.decode, out)
                if okj and type(list) == "table" then
                    ha, ha_has = {}, {}
                    for _, r in ipairs(list) do
                        if type(r) == "table" and type(r[1]) == "string" then
                            ha[#ha + 1] = { id = r[1], name = tostring(r[2] or r[1]), class = tostring(r[3] or "") }
                            ha_has[r[1]] = ha[#ha]
                        end
                    end
                    table.sort(ha, function(a, b) return a.id < b.id end)
                end
            end
            if done then done() end
        end)
    end
    -- the suggestions for what is written: entities whose id or name holds it (a domain or a device class narrows them), the closest first
    local function suggest(q, domain, class)
        q = (q or ""):lower()
        if q == "" and not domain then return {} end
        local out, starts = {}, {}
        for _, e in ipairs(ha) do
            local okd = not domain or e.id:sub(1, #domain + 1) == domain .. "."
            local okc = not class or e.class == class or e.id:lower():find(class, 1, true)
            if okd and okc then
                local id, nm = e.id:lower(), e.name:lower()
                if q == "" or id:find(q, 1, true) or nm:find(q, 1, true) then
                    if id == q then return {} end              -- (written in full: nothing to suggest)
                    if id:find(q, 1, true) == 1 or nm:find(q, 1, true) == 1 then starts[#starts + 1] = e else out[#out + 1] = e end
                end
            end
        end
        local all = {}
        for _, e in ipairs(starts) do all[#all + 1] = e end
        for _, e in ipairs(out) do all[#all + 1] = e end
        local five = {}
        for i = 1, math.min(5, #all) do five[i] = all[i] end
        return five
    end
    -- Bambu Lab printers in Home Assistant: a printer's prefix (p1p, x1c…), from its progress sensor, and its entities by the names the integration gives them (in
    -- English or Spanish)
    local PR_FIND = {
        task = { "sensor", "task_name", "nombre_de_la_tarea" }, progress = { "sensor", "print_progress", "progreso_de_la_impresion" },
        remaining = { "sensor", "remaining_time", "tiempo_restante" }, status = { "sensor", "print_status", "estado_de_la_impresion" },
        start = { "sensor", "start_time", "tiempo_de_inicio" }, ["end"] = { "sensor", "end_time", "tiempo_de_finalizacion" },
        cover = { "image", "cover_image", "imagen_de_portada" }, camera = { "camera", "camera", "camara" },
        pause = { "button", "pause_printing", "pausar_la_impresion" }, resume = { "button", "resume_printing", "continuar_la_impresion" },
        stop = { "button", "stop_printing", "detener_la_impresion" },
    }
    local function printers()
        local out = {}
        for _, e in ipairs(ha) do
            local p = e.id:match("^sensor%.(.+)_print_progress$") or e.id:match("^sensor%.(.+)_progreso_de_la_impresion$")
            if p then out[#out + 1] = p end
        end
        return out
    end
    local function printer_block(p)
        local b = {}
        for key, f in pairs(PR_FIND) do
            for i = 2, 3 do
                local id = f[1] .. "." .. p .. "_" .. f[i]
                if ha_has[id] then b[key] = id; break end
            end
        end
        return b
    end

    -- ── the page ──
    local rows, sws, chips, icons, ents = {}, {}, {}, {}, {}
    local y = 0
    local fa = -1                                    -- the row the shell's field is on (0-based), and what it says
    local fq = ""
    local draft = nil                                -- the entity or room being edited
    local armed = nil                                -- a delete pressed once: the row's key
    local errmsg = nil
    local function width() return math.max(200, (tonumber(fact.slot_w) or 520) / U - 28) end
    local function lang_names()
        local names, seen = {}, {}
        local ok, list = pcall(sys.ask, "files.list")
        for _, n in ipairs(ok and type(list) == "table" and list or {}) do
            local nm = tostring(n):match("^(.+)%.json$")
            if nm and nm ~= "config" and nm ~= "layout" and not seen[nm] then seen[nm] = true; names[#names + 1] = nm end
        end
        for _, nm in ipairs({ "English", "Spanish" }) do if not seen[nm] then seen[nm] = true; names[#names + 1] = nm end end
        table.sort(names)
        return names
    end
    local OLD = { en = "English", es = "Spanish", english = "English", spanish = "Spanish" }

    local function section(label) rows[#rows + 1] = { kind = 0, label = label, y = y, h = 22 }; y = y + 26 end
    local function note(label)
        local lines = math.max(1, math.ceil(#label * 6.1 / width()))
        rows[#rows + 1] = { kind = 4, label = label, y = y, h = lines * 15 }
        y = y + lines * 15 + 8
    end
    local function field(key, label, val, ph, secret)
        rows[#rows + 1] = { kind = 1, key = key, label = label, val = val or "", ph = ph or "", secret = secret, y = y, h = 58 }
        y = y + 64
        return #rows
    end
    local function switch(key, label, on)
        sws[#sws + 1] = { key = key, label = label, on = on and 1 or 0, y = y }
        y = y + 44
    end
    local function chipset(key, options)               -- options: { label, sel, value }
        local x, w0 = 0, width()
        for _, o in ipairs(options) do
            local cw = math.floor(#o.label * 7.4 + 30)
            if x > 0 and x + cw > w0 then x = 0; y = y + 36 end
            chips[#chips + 1] = { key = key, label = o.label, x = x, y = y, w = cw, sel = o.sel and 1 or 0, value = o.value }
            x = x + cw + 8
        end
        y = y + 40
    end
    local function buttons(list)                       -- { label, tone, act }
        local w0, n = width(), #list
        local bw = (w0 - (n - 1) * 8) / n
        for i, b in ipairs(list) do
            rows[#rows + 1] = { kind = 6, label = b.label, tone = b.tone or 0, act = b.act, key = b.key, x = (i - 1) * (bw + 8), w = bw, y = y, h = 38 }
        end
        y = y + 46
    end
    local function sugs(list, key)
        for _, e in ipairs(list) do
            rows[#rows + 1] = { kind = 5, label = e.name, sub = e.id, key = key, pick = e, y = y, h = 42 }
            y = y + 42
        end
        if #list > 0 then y = y + 4 end
    end

    local function mask(v) return string.rep("•", math.min(utf8.len(v) or #v, 40)) end
    local function shown_val(r) return (r.secret and r.val ~= "") and mask(r.val) or r.val end
    local function push()
        local mr = {}
        for _, r in ipairs(rows) do
            mr[#mr + 1] = { kind = r.kind, label = r.label or "", val = shown_val(r), ph = r.ph or "", sub = r.sub or "", x = r.x or 0, y = r.y, w = r.w or 0, h = r.h or 0,
                on = (r.val or "") ~= "" and 1 or 0, tone = (r.key and armed == r.key) and 3 or (r.tone or 0) }
        end
        model.st_rows = mr
        local ms = {}
        for _, w in ipairs(sws) do ms[#ms + 1] = { label = w.label, y = w.y, on = w.on } end
        model.st_sws = ms
        local mc = {}
        for _, c in ipairs(chips) do mc[#mc + 1] = { label = c.label, x = c.x, y = c.y, w = c.w, sel = c.sel } end
        model.st_chips = mc
        local mi = {}
        for _, c in ipairs(icons) do mi[#mi + 1] = { pk = c.pk, dk = c.dk, x = c.x, y = c.y, sel = c.sel } end
        model.st_icons = mi
        local me = {}
        for _, e in ipairs(ents) do me[#me + 1] = { kind = e.kind, name = e.name, sub = e.sub or "", pk = e.pk or 0, y = e.y } end
        model.st_ents = me
        fact.st_content = y + 20
    end

    -- ── the shell's field ──
    local function say_shell(cmds)
        local args = { "--say", "vitreus" }
        for _, c in ipairs(cmds) do args[#args + 1] = c end
        run("pleamar", args, function() end)
    end
    local placed = false
    local function unplace()
        if placed then say_shell({ "fact axf_on false" }) end
        placed = false
        fa = -1
        fact.st_fa = -1
    end
    local function place()
        local r = rows[fa + 1]
        if not r or r.kind ~= 1 or fact.st_open ~= true then unplace() return end
        local W, H = tonumber(fact.slot_w) or 0, tonumber(fact.slot_h) or 0
        local sc = tonumber(fact.st_sc) or 0
        local w = (r.w and r.w > 0) and r.w or width()
        local l = (14 + (r.x or 0)) * U
        local t = (TOP + r.y + 18) * U - sc
        local h = 38 * U
        if t < TOP * U - 2 or t + h > H - 8 * U then          -- scrolled out of sight: no field there
            if placed then say_shell({ "fact axf_on false" }); placed = false end
            return
        end
        local rr = W - l - w * U
        say_shell({ "fact axf_l " .. string.format("%.1f", l), "fact axf_t " .. string.format("%.1f", t), "fact axf_r " .. string.format("%.1f", rr),
            "fact axf_h " .. string.format("%.1f", h), "text axf_q " .. fq, "fact axf_on true", "emit axf_set" })
        placed = true
        fact.st_fx = r.x or 0
        fact.st_fy = r.y
        fact.st_fw = w
    end
    local function show_fv()
        local r = rows[fa + 1]
        text.st_fv = (r and r.secret and fq ~= "") and mask(fq) or fq
        fact.st_fvon = fq ~= ""
    end

    -- ── the pages ──
    local build
    local function cfg_lang(c)
        local l = type(c.language) == "string" and c.language or "English"
        l = l:gsub("%.json$", "")
        return OLD[l:lower()] or l
    end
    local PNAMES = { [0] = "lightbulb", "floor_lamp", "power", "bedtime", "mode_fan", "tv", "power_outlet", "door_front", "home" }
    local DNAMES_EN = { [0] = "led-strip.svg", "wall-lantern.svg", "pendant-lamp.svg", "floor-lamp.svg", "3d-printer.svg", "tv-box.svg", "terrarium.svg", "fan-heater.svg" }
    local DNAMES_ES = { [0] = "tira-led.svg", "farol-pared.svg", "lampara-pergola.svg", "lampara-pie.svg", "impresora-3d.svg", "reproductor.svg", "terrario.svg", "calefactor.svg" }
    local DEV_NEAR = { [0] = 0, 1, 0, 1, 5, 5, 6, 4 }      -- the add-on's own icons, as the closest of the pencil's (the list draws only those)
    local function icon_of(name, kind)                  -- an icon's name → { pk, dk }
        if type(name) == "string" and name:match("%.[sp][vn]g$") then
            local f = api.ALIAS[name] or name
            local dk = api.DEV[f]
            if dk then return -1, dk end
            return -1, -1
        end
        local pk = api.PENCIL[name or ""]
        if pk == nil then pk = kind == "light" and 0 or 2 end
        return pk, -1
    end

    local function build_settings(c)
        section(T("st_sec_ha"))
        field("url", T("st_url"), type(c.url) == "string" and c.url or "", "http://homeassistant.local:8123")
        local tok = type(c.token) == "string" and c.token or ""
        if tok == "PASTE_YOUR_TOKEN_HERE" or tok == "PEGA_AQUI_TU_TOKEN" then tok = "" end
        field("token", T("st_token"), tok, T("st_token_ph"), true)
        note(T("st_token_note"))
        section(T("st_sec_panel"))
        note(T("st_lang"))
        local cur = cfg_lang(c)
        local opts = {}
        for _, nm in ipairs(lang_names()) do opts[#opts + 1] = { label = nm, sel = nm == cur, value = nm } end
        chipset("language", opts)
        switch("insecure", T("st_insecure"), c.insecure == true)
        switch("artwork_search", T("st_artwork"), c.artwork_search ~= false)
        y = y + 4
        buttons({ { label = T("st_open_json"), tone = 0, act = "json" } })
    end
    local function room_sub(r)
        local parts = {}
        local n = type(r.items) == "table" and #r.items or 0
        parts[#parts + 1] = string.format(T(n == 1 and "st_n_tile" or "st_n_tiles"), n)
        if type(r.temperature) == "string" and r.temperature ~= "" then parts[#parts + 1] = r.temperature end
        if type(r.humidity) == "string" and r.humidity ~= "" then parts[#parts + 1] = r.humidity end
        return table.concat(parts, " · ")
    end
    local function build_entities(c)
        buttons({ { label = T("st_add_ent"), tone = 1, act = "new_ent" }, { label = T("st_add_room"), tone = 0, act = "new_room" } })
        local function list_items(items, room)
            for i, it in ipairs(type(items) == "table" and items or {}) do
                if type(it) == "table" then
                    local pk, dk = icon_of(it.icon, it.type or ((it.entity or ""):match("^light%.") and "light" or "toggle"))
                    if pk < 0 then pk = dk >= 0 and DEV_NEAR[dk] or ((it.type == "light") and 0 or 2) end
                    ents[#ents + 1] = { kind = 1, name = tostring(it.name or it.entity or "?"), sub = tostring(it.entity or ""), pk = pk, y = y, room = room, idx = i }
                    y = y + 54
                end
            end
        end
        if type(c.items) == "table" and #c.items > 0 then
            ents[#ents + 1] = { kind = 0, name = T("st_no_room"), sub = string.format(T(#c.items == 1 and "st_n_tile" or "st_n_tiles"), #c.items), y = y, room = 0 }
            y = y + 46
            list_items(c.items, 0)
            y = y + 8
        end
        for k, r in ipairs(type(c.rooms) == "table" and c.rooms or {}) do
            if type(r) == "table" then
                ents[#ents + 1] = { kind = 0, name = tostring(r.name or T("room", k)), sub = room_sub(r), y = y, room = k }
                y = y + 46
                list_items(r.items, k)
                y = y + 8
            end
        end
    end
    local function build_entity(c)
        local d = draft
        local fe = field("entity", T("st_entity"), d.entity, T("st_entity_ph"))
        if fa == fe - 1 then sugs(suggest(fq, nil, nil), "entity") end
        field("name", T("st_name"), d.name, T("st_name_ph"))
        note(T("st_type"))
        chipset("type", { { label = T("st_light"), sel = d.type == "light", value = "light" }, { label = T("st_toggle"), sel = d.type ~= "light", value = "toggle" } })
        note(T("st_room"))
        local ro = {}
        if type(c.items) == "table" and #c.items > 0 then ro[#ro + 1] = { label = T("st_no_room"), sel = d.room == 0, value = 0 } end
        for k, r in ipairs(type(c.rooms) == "table" and c.rooms or {}) do
            if type(r) == "table" then ro[#ro + 1] = { label = tostring(r.name or T("room", k)), sel = d.room == k, value = k } end
        end
        if #ro == 0 then ro[1] = { label = T("st_no_room"), sel = true, value = 0 } end
        chipset("room", ro)
        note(T("st_icon"))
        local cols = math.max(1, math.floor((width() + 8) / 52))
        local pk, dk = icon_of(d.icon, d.type)
        local n = 0
        local function cell(p, q)
            icons[#icons + 1] = { pk = p, dk = q, x = (n % cols) * 52, y = y + math.floor(n / cols) * 52, sel = ((p >= 0 and p == pk and dk < 0) or (q >= 0 and q == dk)) and 1 or 0 }
            n = n + 1
        end
        for p = 0, 8 do cell(p, -1) end
        for q = 0, 7 do cell(-1, q) end
        y = y + math.ceil(n / cols) * 52 + 6
        if pk < 0 and dk < 0 then note(string.format(T("st_own_icon"), tostring(d.icon))) end
        if d.type == "light" then
            switch("color", T("st_color"), d.color)
            switch("tint", T("st_tint"), d.tint)
        end
        if (d.entity or ""):match("^media_player%.") or d.tv then
            switch("tv", T("st_tv"), d.tv)
            if d.tv then
                local fr = field("remote", T("st_remote"), d.remote, "remote." .. ((d.entity or ""):match("^media_player%.(.+)$") or "…"))
                if fa == fr - 1 then sugs(suggest(fq, "remote", nil), "remote") end
            end
        end
        switch("printer", T("st_printer"), d.printer_on)
        if d.printer_on then
            local ps = printers()
            if #ps > 0 then
                note(T("st_printer_pick"))
                local po = {}
                for _, p in ipairs(ps) do po[#po + 1] = { label = p, sel = d.printer_prefix == p, value = p } end
                chipset("printer", po)
            elseif d.printer then
                note(T("st_printer_keep"))
            else
                note(T("st_printer_none"))
            end
        end
        field("on_text", T("st_on_text"), d.on_text, d.type == "light" and T("light_on") or T("on"))
        field("off_text", T("st_off_text"), d.off_text, d.type == "light" and T("light_off") or T("off"))
        if errmsg then note(errmsg) end
        y = y + 4
        if d.idx then
            buttons({ { label = T("st_save"), tone = 1, act = "save_ent" }, { label = T("st_delete"), tone = 2, act = "del_ent", key = "del_ent" } })
        else
            buttons({ { label = T("st_add"), tone = 1, act = "save_ent" }, { label = T("st_cancel"), tone = 0, act = "back" } })
        end
    end
    local function build_room(c)
        local d = draft
        field("name", T("st_room_name"), d.name, T("st_room_name_ph"))
        local ft = field("temperature", T("st_temp"), d.temperature, "sensor.…")
        if fa == ft - 1 then sugs(suggest(fq, "sensor", "temperature"), "temperature") end
        local fh = field("humidity", T("st_hum"), d.humidity, "sensor.…")
        if fa == fh - 1 then sugs(suggest(fq, "sensor", "humidity"), "humidity") end
        if errmsg then note(errmsg) end
        y = y + 4
        if d.idx then
            local n = (type(c.rooms) == "table" and type(c.rooms[d.idx]) == "table" and type(c.rooms[d.idx].items) == "table") and #c.rooms[d.idx].items or 0
            buttons({ { label = T("st_up"), tone = 0, act = "room_up" }, { label = T("st_down"), tone = 0, act = "room_down" } })
            buttons({ { label = T("st_save"), tone = 1, act = "save_room" },
                { label = armed == "del_room" and string.format(T("st_delete_room_sure"), n) or T("st_delete"), tone = 2, act = "del_room", key = "del_room" } })
        else
            buttons({ { label = T("st_add"), tone = 1, act = "save_room" }, { label = T("st_cancel"), tone = 0, act = "back" } })
        end
    end

    build = function()
        rows, sws, chips, icons, ents = {}, {}, {}, {}, {}
        y = 6
        local c = read_cfg()
        text.t_st_settings = T("st_settings")
        text.t_st_entities = T("st_entities")
        text.t_st_back = T("st_back")
        if not c then
            note(T("st_broken"))
            buttons({ { label = T("st_open_json"), tone = 1, act = "json" } })
        elseif (tonumber(fact.st_page) or 0) == 1 and draft then
            text.st_title = draft.idx and T("st_edit_ent") or T("st_new_ent")
            build_entity(c)
        elseif (tonumber(fact.st_page) or 0) == 2 and draft then
            text.st_title = draft.idx and T("st_edit_room") or T("st_new_room")
            build_room(c)
        elseif (tonumber(fact.st_tab) or 0) == 1 then
            build_entities(c)
        else
            build_settings(c)
        end
        push()
    end

    -- ── what is written: kept on its row (and in the draft); the settings' own fields are saved at once ──
    local function commit()
        local r = rows[fa + 1]
        if not r or r.kind ~= 1 then return end
        r.val = fq
        if (tonumber(fact.st_page) or 0) == 0 then
            local c = read_cfg()
            if c and (r.key == "url" or r.key == "token") then
                local v = fq:gsub("^%s+", ""):gsub("%s+$", "")
                if r.key == "url" then v = v:gsub("/+$", "") end
                if c[r.key] ~= v then c[r.key] = v; write_cfg(c) end
            end
        elseif draft then
            draft[r.key] = fq
        end
    end
    local function go_field(i)                          -- the shell's field onto row i (0-based)
        if i == fa then place() return end
        if fa >= 0 then commit() end
        local r = rows[i + 1]
        if not r or r.kind ~= 1 then return end
        fa = i
        fq = r.val or ""
        fact.st_fa = i
        show_fv()
        place()
    end
    on("st_fld", function(i) go_field(math.floor(tonumber(i) or -1)) end)
    on("text:field_q", function(v)
        if fa < 0 then return end
        fq = tostring(v or "")
        show_fv()
        local r = rows[fa + 1]
        if r then
            r.val = fq
            if draft and (tonumber(fact.st_page) or 0) > 0 then draft[r.key] = fq end
            -- a field with suggestions: they follow what is written (the rows below it move, the field stays where it is)
            if r.key == "entity" or r.key == "remote" or r.key == "temperature" or r.key == "humidity" then
                local keep = fa
                build()
                fa = keep
                fact.st_fa = keep
            end
        end
    end)
    on("field_enter", function()
        local r = rows[fa + 1]
        if not r then return end
        -- Enter on a field with suggestions takes the first
        local nxt = rows[fa + 2]
        if nxt and nxt.kind == 5 and nxt.key == r.key then
            fq = nxt.pick.id
        end
        commit()
        if draft and r.key == "entity" and nxt and nxt.kind == 5 then
            if (draft.name or "") == "" then draft.name = nxt.pick.name end
            draft.type = fq:match("^light%.") and "light" or draft.type
        end
        local keep = fa
        build()
        fa = keep
        fact.st_fa = keep
        show_fv()
        say_shell({ "text axf_q " .. fq, "emit axf_set" })
    end)
    on("field_esc", function()
        local r = rows[fa + 1]
        if r then fq = r.val or ""; show_fv() end
    end)

    -- ── presses ──
    local function back()
        unplace()
        draft, armed, errmsg = nil, nil, nil
        fact.st_page = 0
        build()
    end
    local function open_entity(room, idx)
        local c = read_cfg() or {}
        local it = {}
        if idx then
            local list = room == 0 and c.items or (type(c.rooms) == "table" and type(c.rooms[room]) == "table" and c.rooms[room].items) or {}
            it = type(list) == "table" and list[idx] or {}
        end
        if type(it) ~= "table" then it = {} end
        local entity = type(it.entity) == "string" and it.entity or ""
        draft = {
            room = room, idx = idx, orig = it,
            entity = entity, name = type(it.name) == "string" and it.name or "",
            type = it.type == "light" and "light" or ((it.type == nil and entity:match("^light%.")) and "light" or (idx and "toggle" or "light")),
            icon = type(it.icon) == "string" and it.icon or nil,
            color = it.color == true, tint = it.tint == true,
            tv = type(it.apple_tv) == "table", remote = type(it.apple_tv) == "table" and type(it.apple_tv.remote) == "string" and it.apple_tv.remote or "",
            printer = type(it.printer) == "table" and it.printer or nil, printer_on = type(it.printer) == "table", printer_prefix = nil,
            on_text = type(it.on_text) == "string" and it.on_text or "", off_text = type(it.off_text) == "string" and it.off_text or "",
        }
        if not idx then
            -- a new one: into the first room there is
            draft.room = (type(c.rooms) == "table" and #c.rooms > 0) and 1 or 0
        end
        armed, errmsg = nil, nil
        unplace()
        fact.st_page = 1
        build()
        fetch_ha(function() if draft and (tonumber(fact.st_page) or 0) == 1 then build() end end)
    end
    local function open_room(idx)
        local c = read_cfg() or {}
        local r = idx and type(c.rooms) == "table" and c.rooms[idx] or {}
        if type(r) ~= "table" then r = {} end
        draft = { idx = idx, name = type(r.name) == "string" and r.name or "",
            temperature = type(r.temperature) == "string" and r.temperature or "", humidity = type(r.humidity) == "string" and r.humidity or "" }
        armed, errmsg = nil, nil
        unplace()
        fact.st_page = 2
        build()
        fetch_ha(function() if draft and (tonumber(fact.st_page) or 0) == 2 then build() end end)
    end
    local function valid(e) return type(e) == "string" and e:match("^[%a_]+%.[%w_]+$") ~= nil end
    local function save_entity()
        if fa >= 0 then commit() end
        local d = draft
        local c = read_cfg()
        if not c or not d then return end
        d.entity = (d.entity or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if not valid(d.entity) then errmsg = T("st_need_entity"); build() return end
        local it = {}
        for k, v in pairs(d.orig or {}) do it[k] = v end
        it.type = d.type
        it.name = (d.name ~= "" and d.name) or d.entity
        it.icon = d.icon or (d.type == "light" and "lightbulb" or "power")
        it.entity = d.entity
        it.color = (d.type == "light" and d.color) and true or nil
        it.tint = (d.type == "light" and d.tint) and true or nil
        it.on_text = d.on_text ~= "" and d.on_text or nil
        it.off_text = d.off_text ~= "" and d.off_text or nil
        if d.tv then
            local tv = type(it.apple_tv) == "table" and it.apple_tv or {}
            local copy = {}
            for k, v in pairs(tv) do copy[k] = v end
            copy.remote = valid(d.remote) and d.remote or nil
            it.apple_tv = copy
        else
            it.apple_tv = nil
        end
        if d.printer_on then
            if d.printer_prefix then it.printer = printer_block(d.printer_prefix)
            elseif d.printer then it.printer = d.printer
            else it.printer = nil end
        else
            it.printer = nil
        end
        -- out of where it was, into the room chosen (at the end, unless it stays in its room)
        local function list_of(room)
            if room == 0 then c.items = type(c.items) == "table" and c.items or {}; return c.items end
            c.rooms = type(c.rooms) == "table" and c.rooms or {}
            local r = c.rooms[room]
            if type(r) ~= "table" then return nil end
            r.items = type(r.items) == "table" and r.items or {}
            return r.items
        end
        local was = d.room_was ~= nil and d.room_was or d.room
        if d.idx and was ~= d.room then
            local src = list_of(was)
            if src then table.remove(src, d.idx) end
        end
        local dest = list_of(d.room) or list_of(0)
        if d.idx and was == d.room then dest[d.idx] = it else dest[#dest + 1] = it end
        if type(c.items) == "table" and #c.items == 0 then c.items = nil end
        write_cfg(c)
        back()
        fact.st_tab = 1
        build()
    end
    local function delete_entity()
        local d = draft
        local c = read_cfg()
        if not c or not d or not d.idx then return end
        local room = d.room_was ~= nil and d.room_was or d.room
        local list = room == 0 and c.items or (type(c.rooms) == "table" and type(c.rooms[room]) == "table" and c.rooms[room].items)
        if type(list) == "table" then table.remove(list, d.idx) end
        if type(c.items) == "table" and #c.items == 0 then c.items = nil end
        write_cfg(c)
        back()
    end
    local function save_room()
        if fa >= 0 then commit() end
        local d = draft
        local c = read_cfg()
        if not c or not d then return end
        local name = (d.name or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if name == "" then errmsg = T("st_need_name"); build() return end
        c.rooms = type(c.rooms) == "table" and c.rooms or {}
        local r = d.idx and c.rooms[d.idx] or { items = {} }
        r.name = name
        local t, h = (d.temperature or ""):gsub("%s", ""), (d.humidity or ""):gsub("%s", "")
        r.temperature = valid(t) and t or nil
        r.humidity = valid(h) and h or nil
        if not d.idx then c.rooms[#c.rooms + 1] = r end
        write_cfg(c)
        back()
    end
    local function move_room(dir)
        local d = draft
        local c = read_cfg()
        if not c or not d or not d.idx or type(c.rooms) ~= "table" then return end
        local j = d.idx + dir
        if j < 1 or j > #c.rooms then return end
        c.rooms[d.idx], c.rooms[j] = c.rooms[j], c.rooms[d.idx]
        d.idx = j
        write_cfg(c)
        build()
    end
    local function delete_room()
        local d = draft
        local c = read_cfg()
        if not c or not d or not d.idx or type(c.rooms) ~= "table" then return end
        table.remove(c.rooms, d.idx)
        write_cfg(c)
        back()
    end
    on("st_do", function(i)
        local r = rows[(math.floor(tonumber(i) or -1)) + 1]
        if not r then return end
        if r.kind == 5 then                              -- a suggestion: written into its field
            if fa >= 0 then
                fq = r.pick.id
                commit()
                if draft and r.key == "entity" then
                    if (draft.name or "") == "" then draft.name = r.pick.name end
                    if fq:match("^light%.") then draft.type = "light" elseif not fq:match("^light%.") and draft.type == "light" and not draft.idx then draft.type = "toggle" end
                    if fq:match("^media_player%.") then
                        draft.tv = true
                        local cand = "remote." .. fq:match("^media_player%.(.+)$")
                        if ha_has[cand] and (draft.remote or "") == "" then draft.remote = cand end
                    end
                end
                if draft then draft[r.key] = fq end
                unplace()
                build()
            end
            return
        end
        local act = r.act
        if act == "json" then api.edit_json()
        elseif act == "new_ent" then open_entity(nil, nil)
        elseif act == "new_room" then open_room(nil)
        elseif act == "back" then back()
        elseif act == "save_ent" then save_entity()
        elseif act == "save_room" then save_room()
        elseif act == "room_up" then move_room(-1)
        elseif act == "room_down" then move_room(1)
        elseif act == "del_ent" or act == "del_room" then
            if armed == act then
                armed = nil
                if act == "del_ent" then delete_entity() else delete_room() end
            else
                armed = act
                build()
                after(3000, function() if armed == act then armed = nil; build() end end)
            end
        end
    end)
    on("st_sw", function(i)
        local w = sws[(math.floor(tonumber(i) or -1)) + 1]
        if not w then return end
        if fa >= 0 then commit() end
        if (tonumber(fact.st_page) or 0) == 0 then
            local c = read_cfg()
            if not c then return end
            if w.key == "insecure" then c.insecure = not (c.insecure == true) or nil
            elseif w.key == "artwork_search" then c.artwork_search = (c.artwork_search == false) and nil or false end
            if c.insecure == nil then c.insecure = false end
            write_cfg(c)
        elseif draft then
            if w.key == "tv" then draft.tv = not draft.tv
            elseif w.key == "printer" then draft.printer_on = not draft.printer_on
            else draft[w.key] = not draft[w.key] end
        end
        unplace()
        build()
    end)
    on("st_chip", function(i)
        local ch = chips[(math.floor(tonumber(i) or -1)) + 1]
        if not ch then return end
        if fa >= 0 then commit() end
        if ch.key == "language" then
            local c = read_cfg()
            if c then c.language = ch.value; write_cfg(c) end
        elseif draft then
            if ch.key == "room" then
                if draft.idx and draft.room_was == nil then draft.room_was = draft.room end
                draft.room = ch.value
            elseif ch.key == "printer" then draft.printer_prefix = ch.value
            else draft[ch.key] = ch.value end
        end
        unplace()
        build()
    end)
    on("st_icon", function(i)
        local c = icons[(math.floor(tonumber(i) or -1)) + 1]
        if not c or not draft then return end
        if fa >= 0 then commit() end
        if c.pk >= 0 then draft.icon = PNAMES[c.pk]
        else draft.icon = ((api.lang() == "es") and DNAMES_ES or DNAMES_EN)[c.dk] end
        unplace()
        build()
    end)
    on("st_ent", function(i)
        local e = ents[(math.floor(tonumber(i) or -1)) + 1]
        if not e then return end
        if e.kind == 0 then
            if e.room and e.room > 0 then open_room(e.room) end
        else
            open_entity(e.room, e.idx)
        end
    end)
    on("st_back", function() if fa >= 0 then commit() end back() end)
    on("fact:st_tab", function() if fa >= 0 then commit() end unplace(); build() end)
    on("fact:st_open", function(v)
        if v == true then
            fact.st_page = 0
            draft, armed, errmsg = nil, nil, nil
            build()
        else
            if fa >= 0 then commit() end
            unplace()
            draft = nil
            fact.st_page = 0
        end
    end)
    local busy_place = false
    on("fact:st_sc", function()
        if fa < 0 or busy_place then return end
        busy_place = true
        after(120, function() busy_place = false; if fa >= 0 then place() end end)
    end)

    -- A tile carried to another place in edit mode (homeassistant.luau finds where): out of its room's list, into the other's, before the tile it was dropped on
    -- (in its own list, it takes that tile's place), or at the end. `room` 0 is the top level's items.
    local function move_item(fr, fi, tr, ti)
        local c = read_cfg()
        if not c then return end
        local function list_of(room)
            if room == 0 then return type(c.items) == "table" and c.items or nil end
            local r = type(c.rooms) == "table" and c.rooms[room] or nil
            if type(r) ~= "table" then return nil end
            r.items = type(r.items) == "table" and r.items or {}
            return r.items
        end
        local src, dst = list_of(fr), list_of(tr)
        if not src or not dst or type(src[fi]) ~= "table" then return end
        if src == dst and ti == fi then return end
        local it = table.remove(src, fi)
        if ti then
            ti = math.max(1, math.min(#dst + 1, ti))
            table.insert(dst, ti, it)
        else
            dst[#dst + 1] = it
        end
        if type(c.items) == "table" and #c.items == 0 then c.items = nil end
        write_cfg(c)
    end

    -- after config.json was read again (saved here or by hand): the page shows it, and the field stays where it is
    return {
        move_item = move_item,
        refresh = function()
            if fact.st_open ~= true then return end
            local keep = fa
            build()
            if keep >= 0 and rows[keep + 1] and rows[keep + 1].kind == 1 then fa = keep; fact.st_fa = keep end
        end,
        reopen = function() if fact.st_open == true and fa >= 0 then placed = false; place() end end,
        width_changed = function() if fact.st_open == true then build() end end,
    }
end
