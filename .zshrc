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
eval "$(oh-my-posh init zsh --config ~/.config/oh-my-posh/theme.json)"

# ── Info del sistema al abrir una terminal ──
if [[ -o interactive && -z "$FASTFETCH_SHOWN" ]]; then
  export FASTFETCH_SHOWN=1
  fastfetch
fi
