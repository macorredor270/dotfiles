# ── Info del sistema al abrir una terminal  ──
if [[ -o interactive && -z "$FASTFETCH_SHOWN" ]]; then
  export FASTFETCH_SHOWN=1
  fastfetch
  print
fi

# ── Historial ──
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt APPEND_HISTORY SHARE_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE

# ── Opciones ──
setopt AUTO_CD INTERACTIVE_COMMENTS NO_BEEP
bindkey -e

# ── Completado (+ compatibilidad con completados de bash) ──
fpath=(/usr/share/zsh/site-functions $fpath)
autoload -Uz compinit && compinit -C
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
eval "$(starship init zsh)"

# ── z: saltar a carpetas ya visitadas (z <parte-del-nombre>) ──
command -v zoxide >/dev/null && eval "$(zoxide init zsh --cmd z)"

# ── claude: sin argumentos abre un buscador de sesiones; `claude new` abre una nueva ──
claude() {
  if [[ $# -eq 0 ]]; then
    local sel id cwd
    sel=$(~/.local/bin/claude-sessions | fzf --delimiter=$'\t' --with-nth=3 \
      --prompt='sesión › ' --height=70% --reverse --border=rounded --info=inline \
      --header='Enter: reanudar · Esc: cancelar · escribe para buscar' \
      --color='bg:-1,fg:#d0d4da,hl:#5c9ae6,fg+:#ffffff,bg+:#2a2a2a,hl+:#8ab8f2,prompt:#5c9ae6,pointer:#5c9ae6,info:#6b7280,header:#6b7280,border:#6b7280') || return
    id=${sel%%$'\t'*}
    cwd=$(print -r -- "$sel" | cut -f2)
    ( cd "$cwd" 2>/dev/null || true; command claude --resume "$id" )
  elif [[ $1 == new ]]; then
    shift; command claude "$@"
  else
    command claude "$@"
  fi
}
