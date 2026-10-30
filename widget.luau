-- The desktop widget: a card on the desktop with the entities it is given, which Vitreus's desktop editor (a right press on the bare wallpaper) shows, hides, places and
-- resizes like the shell's own widgets. addon.toml's `[widget]` asks Vitreus for its tile in the editor; what Vitreus tells it and asks of it is in Vitreus's
-- addons/_template_drawer/addon.toml. In the editor the card is carried by its middle, its corner pulls it bigger or smaller, Entities ticks what it shows (of the
-- entities in config.json, up to eight) and Monitor sends it to the next monitor. Out of it, a tile's click switches it, and the wheel over a light dims it.
--
-- Kept in widget.json in the add-on's data folder:
--   shown     on the desktop (`widget_shown`: the editor's tile)
--   mon       the monitor's name ("": the first)
--   gx, gy    the cell of its top left corner on the desktop's 28 x 16 grid (the shell's widgets' grid); gw, gh how many cells it takes
--   items     the entities it shows, by id, in order
-- Where it is, for Settings > Theme > Pin widgets (`widget_place`): "mon|gx|gy|gw|gh". A monitor that is not plugged in is ignored: it stays on the one it is on.
--
-- What it is given (homeassistant.luau): `api.T` (the words), `api.cfg()` (the configuration as loaded), `api.tap(k)` (a tile's click, by its place in the
-- configuration, from 0), `api.bri(i, v)` (a light's brightness, by its place from 1, 0 to 1).
return function(api)
    local FILE = "widget.json"
    local GX, GY, MAX = 28, 16, 8
    local W = { shown = false, mon = "", gx = 1, gy = 1, gw = 7, gh = 4, items = {} }
    local function clampi(v, lo, hi) return math.max(lo, math.min(hi, math.floor((tonumber(v) or lo) + 0.5))) end

    local ok, saved = pcall(sys.ask, "files.read", FILE, "json")
    if ok and type(saved) == "table" then
        W.shown = saved.shown == true
        W.mon = type(saved.mon) == "string" and saved.mon or ""
        W.gw = clampi(saved.gw, 3, GX)
        W.gh = clampi(saved.gh, 2, GY)
        W.gx = clampi(saved.gx, 0, GX - W.gw)
        W.gy = clampi(saved.gy, 0, GY - W.gh)
        if type(saved.items) == "table" then
            for _, e in ipairs(saved.items) do if type(e) == "string" and #W.items < MAX then W.items[#W.items + 1] = e end end
        end
    end
    local function save() pcall(sys.call, "files.write", FILE, W) end

    -- The monitors, by the names of this scene's copies (`screen.K.name`).
    local function names()
        local out = {}
        for c = 0, 3 do
            local n = text["screen." .. c .. ".name"]
            if type(n) == "string" and n ~= "" then out[#out + 1] = { k = c, name = n } end
        end
        return out
    end
    local function copy_of(name)
        for _, m in ipairs(names()) do if m.name == name then return m.k end end
        return nil
    end

    -- Its place, to the scene and to whoever asks (`widget_place`).
    local function push()
        fact.widget_shown = W.shown
        fact.dw_gx, fact.dw_gy, fact.dw_gw, fact.dw_gh = W.gx, W.gy, W.gw, W.gh
        fact.dw_mon = (W.mon ~= "" and copy_of(W.mon)) or 0
        text.widget_place = W.mon .. "|" .. W.gx .. "|" .. W.gy .. "|" .. W.gw .. "|" .. W.gh
    end

    -- The tiles it shows (the panel's own rows, those of its entities, in its order) and the list to choose from (every entity in config.json).
    local rows_all = {}
    local by_row = {}             -- the widget's tile -> the entity's place in the configuration (from 0)
    local last = ""
    local function fill()
        local cfg = api.cfg()
        local items = cfg and cfg.items or {}
        local tiles, ents, map = {}, {}, {}
        for _, e in ipairs(W.items) do
            for i, it in ipairs(items) do
                if it.entity == e and rows_all[i] and #tiles < MAX then
                    local r = rows_all[i]
                    tiles[#tiles + 1] = { name = r.name, sub = r.sub, on = r.on, kind = r.kind, bri = r.bri, avail = r.avail, pk = r.pk, dk = r.dk, custom = r.custom, img = r.img }
                    map[#tiles] = i - 1
                    break
                end
            end
        end
        for i, it in ipairs(items) do
            if i > 24 then break end
            local on = false
            for _, e in ipairs(W.items) do if e == it.entity then on = true end end
            ents[#ents + 1] = { name = it.name, on = on }
        end
        by_row = map
        local sig = json.encode({ tiles, ents })
        if sig == last then return end
        last = sig
        model.dw_items = tiles
        model.dw_ents = ents
    end

    local function changed()
        save()
        push()
        fill()
    end

    -- From the desktop editor and Pin widgets (`pleamar --say`)
    on("fact:widget_shown", function(v) W.shown = v == true; changed() end)
    on("fact:widget_edit", function(v) if v ~= true then fact.dw_pick = false end end)
    on("text:widget_place", function(t)
        local mon, gx, gy, gw, gh = (t or ""):match("^([^|]*)|(%-?%d+)|(%-?%d+)|(%d+)|(%d+)$")
        if not mon then return end
        if mon == "" or copy_of(mon) then W.mon = mon end       -- (a monitor that is not plugged in: it stays where it is)
        W.gw = clampi(gw, 3, GX)
        W.gh = clampi(gh, 2, GY)
        W.gx = clampi(gx, 0, GX - W.gw)
        W.gy = clampi(gy, 0, GY - W.gh)
        changed()
    end)

    -- From the widget itself
    on("dw_move", function(v)
        v = math.floor(tonumber(v) or 0)
        W.gx = clampi(v // 100, 0, GX - W.gw)
        W.gy = clampi(v % 100, 0, GY - W.gh)
        changed()
    end)
    on("dw_size", function(v)
        v = math.floor(tonumber(v) or 0)
        W.gw = clampi(v // 100, 3, GX - W.gx)
        W.gh = clampi(v % 100, 2, GY - W.gy)
        changed()
    end)
    on("dw_mon_next", function()
        local ms = names()
        if #ms < 2 then return end
        local at = 0
        for k, m in ipairs(ms) do if m.name == W.mon or (W.mon == "" and m.k == 0) then at = k end end
        W.mon = ms[at % #ms + 1].name
        changed()
    end)
    on("dw_ent", function(k)
        local cfg = api.cfg()
        local it = cfg and cfg.items[(tonumber(k) or -1) + 1]
        if not it then return end
        for j, e in ipairs(W.items) do
            if e == it.entity then table.remove(W.items, j); changed() return end
        end
        if #W.items < MAX then W.items[#W.items + 1] = it.entity end
        changed()
    end)
    on("dw_tap", function(k)
        local i = by_row[(tonumber(k) or -1) + 1]
        if i then api.tap(i) end
    end)
    on("dw_bri", function(v)
        v = math.floor(tonumber(v) or 0)
        local i = by_row[v // 1000 + 1]
        if i then api.bri(i + 1, (v % 1000) / 100) end
    end)

    push()
    after(1500, push)          -- (the copies' monitor names are there once the scene is up)
    return {
        shown = function() return W.shown end,
        -- the panel's rows, each time they are worked out (homeassistant.luau's `show`)
        rows = function(rows)
            rows_all = rows
            fill()
        end,
    }
end
