-- Hyprland (Lua). Migrado desde hyprland.conf.
-- Referencia: https://wiki.hypr.land/Configuring/Start/

local mod = "SUPER"

------------------
---- MONITORES ----
------------------
hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@75", position = "0x0", scale = 1 })
hl.monitor({ output = "",         mode = "preferred",        position = "auto", scale = 1 })

-----------------
---- AUTOSTART ----
-----------------
hl.on("hyprland.start", function()
    hl.exec_cmd("waybar")
    hl.exec_cmd("mako")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("swaybg -m fill -i /home/m1ke/Pictures/wallpapers/nuevo.png")
    hl.exec_cmd("/usr/lib/polkit-kde-authentication-agent-1")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
end)

--------------------------
---- ENTORNO (NVIDIA) ----
--------------------------
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("GBM_BACKEND", "nvidia-drm")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("WLR_NO_HARDWARE_CURSORS", "1")
hl.env("XCURSOR_SIZE", "24")
hl.env("XCURSOR_THEME", "Bibata-Modern-Ice")

---------------------
---- LOOK AND FEEL ----
---------------------
hl.config({
    general = {
        gaps_in  = 4,
        gaps_out = 8,
        border_size = 2,
        resize_on_border = true,
        extend_border_grab_area = 15,
        col = {
            active_border   = { colors = { "rgba(ffffffee)", "rgba(8c8c8cee)" }, angle = 45 },
            inactive_border = "rgba(323232aa)",
        },
        layout = "dwindle",
    },

    decoration = {
        rounding = 10,
        active_opacity   = 1.0,
        inactive_opacity = 0.97,
        blur = {
            enabled = true,
            size = 8,
            passes = 3,
            vibrancy = 0.2,
            ignore_opacity = true,
            new_optimizations = true,
        },
        shadow = {
            enabled = true,
            range = 18,
            render_power = 3,
            color = 0x88000000,
        },
    },

    animations = { enabled = true },

    dwindle = { preserve_split = true },

    misc = {
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        force_default_wallpaper  = 0,
    },

    input = {
        kb_layout = "es",
        follow_mouse = 1,
        touchpad = { natural_scroll = false },
    },
})

-- Animaciones rápidas (curva "snap")
hl.curve("snap", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.0 } } })
hl.animation({ leaf = "windows",    enabled = true, speed = 1.5, bezier = "snap", style = "popin 90%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.5, bezier = "snap", style = "popin 90%" })
hl.animation({ leaf = "fade",       enabled = true, speed = 1,   bezier = "snap" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 1.5, bezier = "snap", style = "slide" })
hl.animation({ leaf = "border",     enabled = true, speed = 2,   bezier = "snap" })
hl.animation({ leaf = "layers",     enabled = true, speed = 1.5, bezier = "snap", style = "fade" })

-- Blur también en la barra y el lanzador
hl.layer_rule({ name = "blur-waybar", match = { namespace = "waybar" }, blur = true })
hl.layer_rule({ name = "blur-rofi",   match = { namespace = "rofi" },   blur = true })

-------------------
---- ATAJOS ----
-------------------
local function bind(keys, dispatcher, opts) return hl.bind(keys, dispatcher, opts) end
local function run(cmd) return hl.dsp.exec_cmd(cmd) end

-- Aplicaciones
bind(mod .. " + Return",   run("kitty"))
bind("CTRL + ALT + T",     run("kitty"))
bind(mod .. " + E",        run("nautilus"))
bind(mod .. " + D",        run("rofi -show drun"))
bind("ALT + SPACE",        run("rofi -show drun"))
bind(mod .. " + Tab",      run("rofi -show window"))
bind(mod .. " + R",        run("rofi -show run"))

-- Menús y utilidades
bind(mod .. " + L",            run("hyprlock"))
bind(mod .. " + SHIFT + V",    run("~/.local/bin/rofi-clipboard"))
bind(mod .. " + period",       run("rofi -modi emoji -show emoji"))
bind(mod .. " + W",            run("~/.local/bin/rofi-wifi"))
bind(mod .. " + B",            run("~/.local/bin/rofi-bluetooth"))
bind(mod .. " + Escape",       run("~/.local/bin/rofi-power"))

-- Ventanas
bind(mod .. " + Q", hl.dsp.window.close())
bind(mod .. " + F", hl.dsp.window.fullscreen())
bind(mod .. " + V", hl.dsp.window.float({ action = "toggle" }))
bind(mod .. " + P", hl.dsp.window.pseudo())
bind(mod .. " + J", hl.dsp.layout("togglesplit"))

-- Foco y movimiento de ventanas
for key, dir in pairs({ left = "left", right = "right", up = "up", down = "down" }) do
    bind(mod .. " + " .. key,             hl.dsp.focus({ direction = dir }))
    bind(mod .. " + SHIFT + " .. key,     hl.dsp.window.move({ direction = dir }))
end

-- Workspaces 1-10 (la tecla 0 es el 10)
for i = 1, 10 do
    local key = i % 10
    bind(mod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- Capturas: sin editor. Guardan en ~/Pictures/Screenshots y copian al portapapeles
bind("CTRL + ALT + S",  run("~/.local/bin/screenshot region"))
bind("CTRL + ALT + K",  run("~/.local/bin/screenshot full"))
bind(mod .. " + S",     run("~/.local/bin/screenshot region"))

-- Volumen con Ctrl+Alt+flechas (±5%, máximo 90%)
bind("CTRL + ALT + up",   run("wpctl set-volume -l 0.9 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
bind("CTRL + ALT + down", run("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),        { locked = true, repeating = true })

-- Sesión
bind(mod .. " + SHIFT + E", hl.dsp.exit())

-- Multimedia
bind("XF86AudioRaiseVolume",  run("wpctl set-volume -l 0.9 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
bind("XF86AudioLowerVolume",  run("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),        { locked = true, repeating = true })
bind("XF86AudioMute",         run("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),       { locked = true })
bind("XF86MonBrightnessUp",   run("brightnessctl set 5%+"),                            { locked = true, repeating = true })
bind("XF86MonBrightnessDown", run("brightnessctl set 5%-"),                            { locked = true, repeating = true })

-- Ratón: mover y redimensionar con Super + botón
bind(mod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
