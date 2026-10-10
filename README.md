# dotfiles

Configuración personal de CachyOS: Hyprland, hyprlock/hypridle, Waybar, Rofi, mako, kitty, zsh + starship (prompt de una línea con pastillas), fzf y zoxide, fastfetch y asociaciones de archivos.

Restaurar en un equipo nuevo:

    git clone <repo> ~/dotfiles
    ~/dotfiles/install.sh

Los archivos se enlazan con symlinks; lo que ya exista se guarda en `~/.dotfiles-backup-*`.

Contenido principal: Hyprland (bordes, animaciones, blur, atajos, capturas sin editor, 75 Hz), hyprlock/hypridle, Waybar (iconos SVG propios, métricas reales de CPU/GPU/RAM/disco/red), Rofi, kitty, fastfetch con degradado azul, PipeWire de baja latencia y `claude` con buscador de sesiones.

Paquetes necesarios: `hyprland waybar rofi kitty starship fzf zoxide fastfetch grim slurp wl-clipboard inter-font ttf-jetbrains-mono-nerd papirus-icon-theme`.
