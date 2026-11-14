# ── Info del sistema al abrir una terminal ──
# En kitty el logo es una imagen anclada a celdas de texto (placeholders unicode): se mueve y reajusta
# junto con el texto, así que no se descoloca al redimensionar ni al hacer scroll.
_ff_img="${XDG_CONFIG_HOME:-$HOME/.config}/fastfetch/logo.png"
_ff_id=7777                      # id de imagen (se codifica en el color de los placeholders: 0,30,97)

# Fichero con las filas de placeholders ($1 = filas, $2 = columnas) -> imprime su ruta
_ff_logo_file() {
  local -a d=(0305 030D 030E 0310 0312 033D 033E 033F 0346 034A 034B 034C 0350 0351 0352 0357 035B 0363 0364 0365 0366 0367 0368 0369 036A 036B 036C 036D 036E 036F 0483 0484)
  local f=${XDG_RUNTIME_DIR:-/tmp}/ff-logo.$$ r c line ph=$'\U10EEEE'
  : > $f
  for (( r=0; r<$1; r++ )); do
    line=$'\e[38;2;0;30;97m'${ph}${(#)$((16#${d[r+1]}))}${(#)$((16#${d[1]}))}
    for (( c=1; c<$2; c++ )); do line+=$ph; done
    print -r -- "$line"$'\e[39m' >> $f
  done
  print -r -- $f
}

_ff_render() {
  local l c h w f
  read -r l c <<< "$(stty size 2>/dev/null)"; l=${l:-24}; c=${c:-80}
  (( c < 50 || l < 9 )) && return 0                # ventana demasiado pequeña: no mostrar nada
  if [[ $TERM == xterm-kitty && -r $_ff_img ]]; then
    h=$(( l - 5 )); (( h > 15 )) && h=15          # alto del logo en filas (máx. 15)
    w=$(( h * 2 ))                                 # una celda es ~2x más alta que ancha
    (( c - w - 4 < 48 )) && { w=$(( c - 52 )); h=$(( w / 2 )); }   # dejar sitio a los datos
    (( w > 30 )) && { w=30; h=15; }
    if (( h >= 4 )); then
      f=$(_ff_logo_file $h $w)
      printf '\e_Ga=d,d=I,i=%d,q=2\e\\' $_ff_id   # liberar la imagen anterior
      printf '\e_Ga=T,U=1,f=100,t=f,i=%d,c=%d,r=%d,q=2;%s\e\\' $_ff_id $w $h "$(print -rn -- ${_ff_img:A} | base64 -w0)"
      local -a args=(--logo "$f" --logo-type file-raw --logo-width $w --logo-height $h --logo-padding-top 0 --logo-padding-right 3)
      if   (( h >= 14 )); then fastfetch $args
      elif (( h >= 8  )); then fastfetch $args -s title:separator:os:kernel:cpu:gpu:memory:disk
      else                     fastfetch $args -s title:os:cpu:memory
      fi
      rm -f -- $f
      return
    fi
  fi
  # Sin kitty o ventana mínima: logo ASCII
  if (( l >= 22 && c >= 90 )); then fastfetch
  elif (( l >= 9 )); then fastfetch --logo arch_small --logo-padding-top 0 -s title:separator:os:cpu:memory:disk
  fi
}
if [[ -o interactive && -z "$FASTFETCH_SHOWN" ]]; then
  export FASTFETCH_SHOWN=1
  # Esperar a que Hyprland termine de dimensionar la ventana
  _prev=""; for _i in {1..20}; do _cur=$(stty size 2>/dev/null); [[ -n $_cur && $_cur == $_prev ]] && break; _prev=$_cur; sleep 0.05; done
  unset _prev _cur _i
  _ff_render
  print
  # Redibujar al cambiar el tamaño SOLO mientras no hayas ejecutado ningún comando
  # (si ya hay salida de comandos en pantalla no se toca nada: el logo se reajusta con el texto).
  typeset -g _ff_h0=$HISTCMD _ff_busy=0
  TRAPWINCH() {
    (( HISTCMD == _ff_h0 && ! _ff_busy )) || return 0
    _ff_busy=1
    local p q i                                   # esperar a que termine de arrastrarse
    for i in {1..10}; do p=$(stty size 2>/dev/null); sleep 0.04; q=$(stty size 2>/dev/null); [[ $p == $q ]] && break; done
    zle -I 2>/dev/null
    print -n '\e[H\e[2J\e[3J'
    _ff_render
    print
    zle && zle reset-prompt
    _ff_busy=0
  }
fi

# ── Historial ──
if [[ -d ~/.dev/zsh ]]; then HISTFILE=~/.dev/zsh/history; _zcomp=~/.dev/zsh/zcompdump; else HISTFILE=~/.zsh_history; _zcomp=~/.zcompdump; fi
HISTSIZE=50000
SAVEHIST=50000
setopt APPEND_HISTORY SHARE_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE

# ── Opciones ──
setopt AUTO_CD INTERACTIVE_COMMENTS NO_BEEP
bindkey -e

# ── Completado (+ compatibilidad con completados de bash) ──
fpath=(/usr/share/zsh/site-functions $fpath)
autoload -Uz compinit && compinit -C -d "$_zcomp"
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
autoload -Uz bashcompinit && bashcompinit

# ── Plugins ──
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh 2>/dev/null
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh 2>/dev/null

# ── Colores de escritura: monocromo con acento azul acero ──
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#5c6370'
typeset -A ZSH_HIGHLIGHT_STYLES
ZSH_HIGHLIGHT_STYLES[command]='fg=#e6e6e6'
ZSH_HIGHLIGHT_STYLES[builtin]='fg=#e6e6e6'
ZSH_HIGHLIGHT_STYLES[alias]='fg=#e6e6e6'
ZSH_HIGHLIGHT_STYLES[function]='fg=#e6e6e6'
ZSH_HIGHLIGHT_STYLES[precommand]='fg=#e6e6e6,underline'
ZSH_HIGHLIGHT_STYLES[reserved-word]='fg=#5c9ae6'
ZSH_HIGHLIGHT_STYLES[commandseparator]='fg=#5c9ae6'
ZSH_HIGHLIGHT_STYLES[path]='fg=#c9d1d9,underline'
ZSH_HIGHLIGHT_STYLES[globbing]='fg=#5c9ae6'
ZSH_HIGHLIGHT_STYLES[single-hyphen-option]='fg=#9aa5b1'
ZSH_HIGHLIGHT_STYLES[double-hyphen-option]='fg=#9aa5b1'
ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=#a9b8cf'
ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=#a9b8cf'
ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=#e06c75'

# ── Entorno ──
export TERMINAL=kitty
export EDITOR=nano
export PATH="$HOME/.local/bin:$PATH"

# ── Alias ──
alias ls='ls --color=auto --group-directories-first'
alias ll='ls -lh'
alias la='ls -lAh'
alias grep='grep --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias ff='fastfetch'
alias upd='sudo pacman -Syu'

# ── Prompt ──
setopt TRANSIENT_RPROMPT   # quita la pastilla de la hora del prompt de la derecha al ejecutar: así no se descuadra al redimensionar
command -v starship >/dev/null && eval "$(starship init zsh)"

# ── z: saltar a carpetas ya visitadas (z <parte-del-nombre>) ──
command -v zoxide >/dev/null && eval "$(zoxide init zsh --cmd z)"

# ── claude: sin argumentos abre el selector de sesiones (vista previa, ✨ nueva, Ctrl-P solo esta carpeta, Ctrl-A todas); `claude new` abre una nueva.
#    Perfil MCP automático por carpeta: Unity/Deriva → gamedev, ghidra/reversing → ghidra, resto → ninguno (ahorra tokens) ──
_claude_mcp() {
  reply=()
  case "${1:l}" in
    *mundo3d*|*deriva*|*unity*)          reply=(--mcp-config "$HOME/claude-config/mcp-profiles/gamedev.mcp.json") ;;
    *ghidra*|*reversing*|*reverse*)      reply=(--mcp-config "$HOME/claude-config/mcp-profiles/ghidra.mcp.json") ;;
  esac
}
claude() {
  if [[ $# -eq 0 ]]; then
    local sel id cwd
    sel=$(claude-sessions | fzf --delimiter=$'\t' --with-nth=3 \
      --prompt='sesión › ' --height=85% --reverse --border=rounded --info=inline \
      --preview='claude-sessions --preview {1}' --preview-window='right:50%:wrap:border-left' \
      --bind='ctrl-p:reload(claude-sessions --here)' --bind='ctrl-a:reload(claude-sessions)' \
      --header='Enter: abrir · Ctrl-P: solo esta carpeta · Ctrl-A: todas · Esc: salir' \
      --color='bg:-1,fg:#d0d4da,hl:#5c9ae6,fg+:#ffffff,bg+:#2a2a2a,hl+:#8ab8f2,prompt:#5c9ae6,pointer:#5c9ae6,info:#6b7280,header:#6b7280,border:#6b7280') || return
    id=${sel%%$'\t'*}
    cwd=$(print -r -- "$sel" | cut -f2)
    ( cd "$cwd" 2>/dev/null || true; _claude_mcp "$PWD"
      if [[ $id == NEW ]]; then command claude "${reply[@]}"; else command claude "${reply[@]}" --resume "$id"; fi )
  elif [[ $1 == new ]]; then
    shift; _claude_mcp "$PWD"; command claude "${reply[@]}" "$@"
  else
    _claude_mcp "$PWD"; command claude "${reply[@]}" "$@"
  fi
}

# ── atajos del sistema ──
alias actualizar='sudo pacman -Syu && (command -v yay &>/dev/null && yay -Sua --noconfirm || true)'
alias limpiar='sudo rm -rf /var/cache/pacman/pkg/download-* && sudo pacman -Sc --noconfirm && rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}"/thumbnails/* && echo "✔ Limpieza completada."'
alias espejos='sudo cachyos-rate-mirrors'
alias puertos='sudo ss -tulpn'
alias mi-ip='curl -s ifconfig.me && echo'

# Modo bestia (solo si los scripts están en este equipo)
if command -v bestia-on >/dev/null; then
  alias bestia-on='sudo bestia-on' bestia-off='sudo bestia-off' bestia-status='sudo bestia-status'
fi

# Composio CLI
export PATH="$HOME/.local/bin:$PATH"
alias tv='vlc "${XDG_DATA_HOME:-$HOME/.local/share}/iptv/espana.m3u"'
command -v fnm >/dev/null && eval "$(fnm env --use-on-cd --shell zsh)"
