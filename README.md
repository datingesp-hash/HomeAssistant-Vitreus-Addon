# Home Assistant for Vitreus

A [Vitreus](https://github.com/natepayn3/Vitreus) add-on that puts your Home Assistant lights and switches in a panel of the shell's own glass, grouped by room.

*[Leer en español](README.es.md)*

![The panel, by rooms, on the Island](docs/en/island.png)

- **Rooms**, each with its name and, if you give it sensors, its temperature and humidity.
- **A click** turns a tile on or off. **A right click** on a light opens a brightness slider (drag it, use the wheel, or pick off / 25 / 50 / 75 / 100 %).
- **3D printers**: a right click on a printer's tile opens a card with the print's cover or camera, its progress and times, and its buttons.
- **Tiles of any size**: the pencil puts the panel in edit mode, and the handle in each tile's corner pulls it wider (up to 4 columns) or taller (up to 3 rows). Sizes are kept.
- **On the Island**: drag the add-ons piece onto the bar (Settings > Bar > Island layout) and the panel drops from the bar like the shell's own panels.
- **Vitreus's look**: it takes the palette and the theme from the shell, and changes with them.
- **English or Spanish**: `"language"` in its settings, or the system's language if it is not set.
- Lights use `light.toggle` / `light.turn_on`; anything else (`input_boolean`, `switch`, `media_player`, scripts…) uses `homeassistant.toggle`.

| The panel | Edit mode | Brightness |
| --- | --- | --- |
| ![The panel](docs/en/panel.png) | ![Edit mode](docs/en/edit-mode.png) | ![Brightness](docs/en/brightness.png) |

## Install

```sh
git clone https://github.com/datingesp-hash/HomeAssistant-Vitreus-Addon ~/.config/pleamar/vitreus-addons/homeassistant
```

Then turn it on in **Settings > Add-ons**. To update it later:

```sh
git -C ~/.config/pleamar/vitreus-addons/homeassistant pull
```

It needs a Vitreus with add-ons, and `curl`.

## Set it up

The first time it runs it writes `~/.local/share/pleamar/homeassistant/config.json` with an example; the gear in the panel opens it in your editor (`$VISUAL`, then `$EDITOR`, then `nvim`), and the panel reloads when you save it. [`config.example.json`](config.example.json) is the same example.

- `language`: `"en"` (English) or `"es"` (Spanish). Without it, the panel follows the system's language (`LANG`).
- `url`: your Home Assistant's address, e.g. `http://homeassistant.local:8123`.
- `token`: a long-lived access token. In Home Assistant: your profile > Security > Long-lived access tokens > Create token.
- `insecure`: `true` only for https with a self-signed certificate.
- `rooms`: the rooms, in order. Each has:
  - `name`: shown as its title.
  - `temperature`, `humidity` (optional): a sensor entity; its reading is shown beside the name.
  - `items`: its tiles. Each has:
    - `type`: `"light"` (with brightness) or `"toggle"`.
    - `name`: what the tile says.
    - `icon`: a [Material Symbols](https://fonts.google.com/icons) name (`lightbulb`, `floor_lamp`, `tv`, `bedtime`, `mode_fan`…), or one of the add-on's own icons below, or any white `.svg` you put in `~/.local/share/pleamar/homeassistant/`.
    - `entity`: the entity id, e.g. `light.living_room`.
    - `on_text`, `off_text` (optional): the line under the name when it is on or off.

A plain `items` list at the top level (without rooms) works too: it is shown first, with no title.

### A 3D printer's card

Give a tile a `"printer"` block and a right click on it opens a card with the print: the model's cover (or the printer's camera), the job, its state, its progress, the time left, when it started and when it ends, and Pause / Resume / Stop (Stop asks again). A click on the tile still toggles its own entity (the printer's light, say), and while it prints the tile shows *Printing · 62 %* with a bar. Every entity is optional; leave out the ones your printer does not have.

```json
{ "type": "toggle", "name": "Printer", "icon": "3d-printer.svg", "entity": "light.p1p_chamber_light",
  "printer": {
    "task":      "sensor.p1p_task_name",
    "progress":  "sensor.p1p_print_progress",
    "remaining": "sensor.p1p_remaining_time",
    "status":    "sensor.p1p_print_status",
    "start":     "sensor.p1p_start_time",
    "end":       "sensor.p1p_end_time",
    "cover":     "image.p1p_cover_image",
    "camera":    "camera.p1p_camera",
    "pause":     "button.p1p_pause_printing",
    "resume":    "button.p1p_resume_printing",
    "stop":      "button.p1p_stop_printing"
  } }
```

![The printer's card](docs/en/printer.png)

These are the [Bambu Lab integration](https://github.com/greghesp/ha-bambulab)'s entities for a printer called P1P (their names follow Home Assistant's language and your printer's name: check yours in Settings > Devices & services > Entities). `status` understands `running`, `pause`, `finish`, `failed`, `prepare`, `idle` and `offline`; `remaining` is read in its own unit (minutes, hours or seconds). The camera shows a frame every two seconds inside the card; a click on it opens the live stream in your browser.

### The add-on's own icons

For what Material Symbols has no good icon for. They are drawn on Material's grid and tinted the same way. Each has an English and a Spanish name, and either works in `icon`:

![The add-on's icons](docs/en/icons.png)

| English | Spanish |
| --- | --- |
| `led-strip.svg` | `tira-led.svg` |
| `wall-lantern.svg` | `farol-pared.svg` |
| `pendant-lamp.svg` | `lampara-pergola.svg` |
| `floor-lamp.svg` | `lampara-pie.svg` |
| `3d-printer.svg` | `impresora-3d.svg` |
| `tv-box.svg` | `reproductor.svg` |
| `terrarium.svg` | `terrario.svg` |
| `fan-heater.svg` | `calefactor.svg` |

### A key to open it

On Hyprland (Lua config), in your `hyprland.lua`:

```lua
hl.unbind("SUPER + H")
hl.bind("SUPER + H", hl.dsp.exec_cmd("PATH=\"$HOME/.local/bin:$PATH\" pleamar --say vitreus \"emit ax_toggle\""))
```

`ax_toggle` opens the first add-on that has a panel.

## Translations

Every word the panel shows is in one table, `STR` at the top of `homeassistant.luau`, with an `es` and an `en` block. To add a language, copy the `en` block under a new code (`fr = { ... }`), translate the values, and set `"language": "fr"`. A key the new block lacks is shown in English. Pull requests with new languages are welcome.

## Privacy

The token is never put on curl's command line, where other programs could read it: the add-on writes it to `auth.curl` in its data folder and curl reads it from there with `-K`.

That folder (`~/.local/share/pleamar/homeassistant/`, which holds `config.json` and `auth.curl`, both with the token) is private: pleamar after 0.4.31 keeps a scene's data folder 0700 and the files it writes 0600 ([pleamar#107](https://github.com/k4ditano/pleamar/issues/107)). A folder made before is tightened too, since the add-on writes `auth.curl` every time it starts. With pleamar 0.4.31 or older, do it by hand:

```sh
chmod 700 ~/.local/share/pleamar/homeassistant
```

Either way this keeps the token from other users of the machine; programs running as you can still read it.

## Notes

- With two monitors of the same size, the panel shows on the one Vitreus opened it on (Vitreus tells the add-on the monitor's name; an older Vitreus that does not falls back to the monitor's size).
- Up to 12 rooms and 32 tiles.

## License

MIT, see [LICENSE](LICENSE). `addon-palette.plm` comes from Vitreus's add-on template (MIT, © natepayn3).
