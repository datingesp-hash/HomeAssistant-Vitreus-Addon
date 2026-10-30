-- The desktop widgets: a card on the desktop for each entity it is given, which Vitreus's desktop editor (a right press on the bare wallpaper) shows and places like the
-- shell's own widgets. addon.toml's `[widget]` (with `menu = true`) asks Vitreus for a tile in the editor; pressed, it opens a list of the entities in config.json over
-- the shelf (`widget_menu`), where a tick puts a card for that entity on the desktop and another takes it off. What Vitreus tells it and asks of it is in Vitreus's
-- addons/_template_drawer/addon.toml. In the editor a card is carried by its middle and its corner pulls it bigger or smaller, a cell at a time; its cross takes it
-- off. Out of it, a click switches the entity and the wheel over a light dims it.
--
-- Kept in widget.json in the add-on's data folder: { cards = { { entity, mon, gx, gy, gw, gh }, ... } }, up to eight:
--   entity    what it shows
--   mon       its monitor's name ("": the first)
--   gx, gy    the cell of its top left corner on the desktop's 28 x 16 grid (the shell's widgets' grid); gw, gh how many cells it takes
-- For Settings > Theme > Pin widgets (`widget_place`): the same, a card a line ("entity,mon,gx,gy,gw,gh", lines joined by ";"). A monitor that is not plugged in is
-- ignored: that card stays on the monitor it is on.
--
-- What it is given (homeassistant.luau): `api.T` (the words), `api.cfg()` (the configuration as loaded), `api.tap(k)` (an entity switched, by its place in the
-- configuration, from 0), `api.bri(i, v)` (a light's brightness, by its place from 1, 0 to 1).
return function(api)
    local FILE = "widget.json"
    local GX, GY, MAX = 28, 16, 8
    local MAXL = 32                -- the list's lines: rooms' names and entities
    local cards = {}
    local function clampi(v, lo, hi) return math.max(lo, math.min(hi, math.floor((tonumber(v) or lo) + 0.5))) end
    local function valid(e) return type(e) == "string" and e:match("^[%a_]+%.[%w_]+$") ~= nil end
    local function card(c)
        if type(c) ~= "table" or not valid(c.entity) then return nil end
        local n = { entity = c.entity, mon = type(c.mon) == "string" and c.mon:match("^[%w%-_.:]*$") and c.mon or "" }
        n.gw = clampi(c.gw, 2, GX)
        n.gh = clampi(c.gh, 2, GY)
        n.gx = clampi(c.gx, 0, GX - n.gw)
        n.gy = clampi(c.gy, 0, GY - n.gh)
        return n
    end

    local ok, saved = pcall(sys.ask, "files.read", FILE, "json")
    if ok and type(saved) == "table" and type(saved.cards) == "table" then
        for _, c in ipairs(saved.cards) do
            local n = card(c)
            if n and #cards < MAX then cards[#cards + 1] = n end
        end
    end
    local function save() pcall(sys.call, "files.write", FILE, { cards = cards }) end

    -- The monitors, by the names of this scene's copies (`screen.K.name`).
    local function copy_of(name)
        for c = 0, 3 do
            local n = text["screen." .. c .. ".name"]
            if type(n) == "string" and n ~= "" and n == name then return c end
        end
        return nil
    end
    local function plugged(name) return name == "" or copy_of(name) ~= nil end

    -- The cards, to the scene (the panel's own rows for their entities), and the list to choose from (every entity in config.json, ticked if it has a card).
    local rows_all = {}
    local by_card = {}             -- a card -> its entity's place in the configuration (from 0), or nil when config.json no longer has it
    local fresh = {}               -- cards just added: drawn where they are, not from a spring
    local last = ""
    local function fill()
        local cfg = api.cfg()
        local items = cfg and cfg.items or {}
        local out, map = {}, {}
        for k, c in ipairs(cards) do
            local row = { name = c.entity, sub = "", on = 0, kind = 1, bri = 0, avail = 0, pk = 2, dk = -1, custom = 0, img = "" }
            for i, it in ipairs(items) do
                if it.entity == c.entity then
                    map[k] = i - 1
                    local r = rows_all[i]
                    if r then row = { name = r.name, sub = r.sub, on = r.on, kind = r.kind, bri = r.bri, avail = r.avail, pk = r.pk, dk = r.dk, custom = r.custom, img = r.img } end
                    break
                end
            end
            row.gx, row.gy, row.gw, row.gh = c.gx, c.gy, c.gw, c.gh
            row.mon = (c.mon ~= "" and copy_of(c.mon)) or 0
            row.fresh = fresh[c] and 1 or 0
            out[k] = row
        end
        -- the list, by room: the room's name on a line of its own, then its entities two to a line (in config.json's order, which is the panel's)
        local ents, row, col, room = {}, -1, 1, nil
        local rooms = cfg and cfg.rooms or {}
        for i, it in ipairs(items) do
            if it.room ~= room then
                if #ents >= MAXL - 1 then break end
                room = it.room
                local r = rooms[room]
                row = row + 1
                ents[#ents + 1] = { name = ((r and r.name ~= "") and r.name or api.T("st_no_room")):upper(), on = false, head = true, k = -1, col = 0, row = row }
                col = 1
            end
            if #ents >= MAXL then break end
            if col == 1 then row = row + 1; col = 0 else col = 1 end
            local on = false
            for _, c in ipairs(cards) do if c.entity == it.entity then on = true end end
            ents[#ents + 1] = { name = it.name, on = on, head = false, k = i - 1, col = col, row = row }
        end
        fact.dw_mrows = row + 1
        by_card = map
        local sig = json.encode({ out, ents })
        if sig == last then return end
        last = sig
        model.dw_w = out
        model.dw_ents = ents
    end

    local function place()
        local lines = {}
        for _, c in ipairs(cards) do lines[#lines + 1] = table.concat({ c.entity, c.mon, c.gx, c.gy, c.gw, c.gh }, ",") end
        return table.concat(lines, ";")
    end
    local function changed()
        save()
        fact.widget_shown = #cards > 0
        text.widget_place = place()
        fill()
    end

    -- A new card: on the editor's monitor, 4 by 2 cells, in the first place from the top left that no other card there takes.
    local function free_spot(mon, w, h)
        local function clear(x, y)
            for _, c in ipairs(cards) do
                if c.mon == mon and x < c.gx + c.gw and c.gx < x + w and y < c.gy + c.gh and c.gy < y + h then return false end
            end
            return true
        end
        for y = 1, GY - h do
            for x = 1, GX - w do
                if clear(x, y) then return x, y end
            end
        end
        return 1, 1
    end

    -- From the desktop editor and Pin widgets (`pleamar --say`)
    on("widget_menu", function()
        fact.dw_mmon = copy_of(text.widget_mon_name or "") or 0
        fact.dw_menu = not (fact.dw_menu == true)
    end)
    on("fact:widget_shown", function(v)
        if v == false and #cards > 0 then cards = {}; changed() end      -- (Pin widgets: a theme without any)
    end)
    on("text:widget_place", function(t)
        if type(t) ~= "string" then return end
        local was = cards
        local out = {}
        for line in t:gmatch("[^;]+") do
            local e, mon, gx, gy, gw, gh = line:match("^([^,]+),([^,]*),(%-?%d+),(%-?%d+),(%d+),(%d+)$")
            local n = e and card({ entity = e, mon = mon, gx = gx, gy = gy, gw = gw, gh = gh })
            if n and #out < MAX then
                if not plugged(n.mon) then         -- a monitor that is not plugged in: the card stays on the one it is on
                    n.mon = ""
                    for _, c in ipairs(was) do if c.entity == n.entity then n.mon = c.mon end end
                end
                out[#out + 1] = n
            end
        end
        cards = out
        changed()
    end)

    -- From the cards and the list
    on("dw_ent", function(k)
        local cfg = api.cfg()
        local it = cfg and cfg.items[(tonumber(k) or -1) + 1]
        if not it or not valid(it.entity) then return end
        for j, c in ipairs(cards) do
            if c.entity == it.entity then table.remove(cards, j); changed() return end
        end
        if #cards >= MAX then return end
        local mon = text.widget_mon_name or ""
        if not plugged(mon) then mon = "" end
        local x, y = free_spot(mon, 4, 2)
        local c = { entity = it.entity, mon = mon, gx = x, gy = y, gw = 4, gh = 2 }
        cards[#cards + 1] = c
        fresh[c] = true
        changed()
        after(700, function() fresh[c] = nil; fill() end)
    end)
    on("dw_del", function(k)
        local j = (tonumber(k) or -1) + 1
        if cards[j] then table.remove(cards, j); changed() end
    end)
    -- let go of: the card's own place becomes the new one, and only then the scene lets go of it (so it never springs back on the way)
    on("dw_move", function(v)
        v = math.floor(tonumber(v) or 0)
        local c = cards[v // 10000 + 1]
        if c then
            c.gx = clampi((v % 10000) // 100, 0, GX - c.gw)
            c.gy = clampi(v % 100, 0, GY - c.gh)
            changed()
        end
        fact.dw_di = -1
    end)
    on("dw_size", function(v)
        v = math.floor(tonumber(v) or 0)
        local c = cards[v // 10000 + 1]
        if c then
            c.gw = clampi((v % 10000) // 100, 2, GX - c.gx)
            c.gh = clampi(v % 100, 2, GY - c.gy)
            changed()
        end
        fact.dw_ri = -1
    end)
    on("dw_tap", function(k)
        local i = by_card[(tonumber(k) or -1) + 1]
        if i then api.tap(i) end
    end)
    on("dw_bri", function(v)
        v = math.floor(tonumber(v) or 0)
        local i = by_card[v // 1000 + 1]
        if i then api.bri(i + 1, (v % 1000) / 100) end
    end)

    fact.widget_shown = #cards > 0
    text.widget_place = place()
    after(1500, fill)          -- (the copies' monitor names are there once the scene is up)
    return {
        shown = function() return #cards > 0 end,
        -- the panel's rows, each time they are worked out (homeassistant.luau's `show`)
        rows = function(rows)
            rows_all = rows
            fill()
        end,
    }
end
