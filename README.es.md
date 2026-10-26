# Home Assistant para Vitreus

Un addon de [Vitreus](https://github.com/natepayn3/Vitreus) que pone tus luces e interruptores de Home Assistant en un panel con el cristal de la propia shell, separados por habitaciones.

*[Read in English](README.md)*

![El panel, por habitaciones, en la isla](docs/es/island.png)

- **Habitaciones**, cada una con su nombre y, si le pones sensores, su temperatura y humedad.
- **Clic** en una ficha: enciende o apaga. **Clic derecho** en una luz: abre el control de brillo (arrastra, usa la rueda o pulsa Apagar / 25 / 50 / 75 / 100 %).
- **Fichas del tamaño que quieras**: el lápiz pone el panel en modo edición, y el tirador de la esquina de cada ficha la hace más ancha (hasta 4 columnas) o más alta (hasta 3 filas). Los tamaños se guardan.
- **En la isla**: arrastra la pieza de add-ons a la barra (Ajustes > Bar > Island layout) y el panel se despliega desde la barra como los paneles de la shell.
- **Estética de Vitreus**: toma la paleta y el tema de la shell, y cambia con ellos.
- **En español o en inglés**: `"language"` en su configuración, o el idioma del sistema si no lo pones.

| El panel | Modo edición | Brillo |
| --- | --- | --- |
| ![El panel](docs/es/panel.png) | ![Modo edición](docs/es/edit-mode.png) | ![Brillo](docs/es/brightness.png) |

## Instalar

```sh
git clone https://github.com/datingesp-hash/HomeAssistant-Vitreus-Addon ~/.config/pleamar/vitreus-addons/homeassistant
```

Después, actívalo en **Ajustes > Add-ons**. Para actualizarlo más adelante:

```sh
git -C ~/.config/pleamar/vitreus-addons/homeassistant pull
```

Necesita un Vitreus con add-ons, y `curl`.

## Configurar

La primera vez crea `~/.local/share/pleamar/homeassistant/config.json` con un ejemplo. El engranaje del panel lo abre en tu editor (`$VISUAL`, si no `$EDITOR`, si no `nvim`), y al guardarlo el panel se actualiza solo. [`config.example.json`](config.example.json) es el mismo ejemplo.

- `language`: `"es"` (español) o `"en"` (inglés). Si no lo pones, el panel usa el idioma del sistema (`LANG`).
- `url`: la dirección de tu Home Assistant, p. ej. `http://homeassistant.local:8123`.
- `token`: un token de larga duración. En Home Assistant: tu perfil > Seguridad > Tokens de acceso de larga duración > Crear token.
- `insecure`: `true` solo si usas https con un certificado propio.
- `rooms`: las habitaciones, en orden. Cada una lleva:
  - `name`: su nombre, que sale como título.
  - `temperature`, `humidity` (opcionales): un sensor; su lectura sale junto al nombre.
  - `items`: sus fichas. Cada ficha lleva:
    - `type`: `"light"` (con brillo) o `"toggle"`.
    - `name`: el nombre de la ficha.
    - `icon`: un nombre de [Material Symbols](https://fonts.google.com/icons) (`lightbulb`, `floor_lamp`, `tv`, `bedtime`, `mode_fan`…), uno de los iconos propios del addon (abajo), o cualquier `.svg` blanco que pongas en `~/.local/share/pleamar/homeassistant/`.
    - `entity`: la entidad, p. ej. `light.salon`.
    - `on_text`, `off_text` (opcionales): el texto de debajo cuando está encendido o apagado.

Un `items` suelto fuera de `rooms` también vale: sale arriba, sin título.

### Los iconos propios del addon

Para lo que Material Symbols no tiene un buen icono. Están dibujados sobre la cuadrícula de Material y se tiñen igual. Cada uno tiene un nombre en español y otro en inglés, y los dos valen en `icon`:

![Los iconos del addon](docs/es/icons.png)

| Español | Inglés |
| --- | --- |
| `tira-led.svg` | `led-strip.svg` |
| `farol-pared.svg` | `wall-lantern.svg` |
| `lampara-pergola.svg` | `pendant-lamp.svg` |
| `lampara-pie.svg` | `floor-lamp.svg` |
| `impresora-3d.svg` | `3d-printer.svg` |
| `reproductor.svg` | `tv-box.svg` |
| `terrario.svg` | `terrarium.svg` |
| `calefactor.svg` | `fan-heater.svg` |

### Un atajo para abrirlo

En Hyprland (configuración en Lua), en tu `hyprland.lua`:

```lua
hl.unbind("SUPER + H")
hl.bind("SUPER + H", hl.dsp.exec_cmd("PATH=\"$HOME/.local/bin:$PATH\" pleamar --say vitreus \"emit ax_toggle\""))
```

`ax_toggle` abre el primer addon que tenga panel.

## Traducciones

Todo lo que dice el panel está en una sola tabla, `STR`, al principio de `homeassistant.luau`, con un bloque `es` y otro `en`. Para añadir un idioma, copia el bloque `en` con un código nuevo (`fr = { ... }`), traduce los textos y pon `"language": "fr"`. Lo que falte en el bloque nuevo sale en inglés. Los pull requests con idiomas nuevos son bienvenidos.

## Privacidad

El token nunca va en la línea de comandos de curl, donde otros programas podrían leerlo: el addon lo escribe en `auth.curl`, en su carpeta de datos, y curl lo lee de ahí con `-K`.

Esa carpeta (`~/.local/share/pleamar/homeassistant/`, donde están `config.json` y `auth.curl`, los dos con el token) es privada: pleamar, a partir de la versión siguiente a la 0.4.31, crea la carpeta de datos de cada escena con permisos 0700 y los archivos que escribe con 0600 ([pleamar#107](https://github.com/k4ditano/pleamar/issues/107)). Una carpeta creada antes también se cierra, porque el addon escribe `auth.curl` cada vez que arranca. Con pleamar 0.4.31 o anterior, hazlo a mano:

```sh
chmod 700 ~/.local/share/pleamar/homeassistant
```

En los dos casos esto protege el token de otros usuarios del equipo; los programas que se ejecutan con tu usuario pueden seguir leyéndolo.

## Notas

- Con dos monitores del mismo tamaño, el panel sale en el que Vitreus lo abre (Vitreus le dice al addon el nombre del monitor; con un Vitreus antiguo que no lo hace, se guía por el tamaño del monitor).
- Hasta 12 habitaciones y 32 fichas.

## Licencia

MIT, ver [LICENSE](LICENSE). `addon-palette.plm` viene de la plantilla de add-ons de Vitreus (MIT, © natepayn3).
