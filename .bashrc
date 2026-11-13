#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '


# Banner minimalista al abrir terminal (sin logo ni specs, config completo
# sigue disponible corriendo `fastfetch` a secas)
[ -f ~/.config/fastfetch/minimal.jsonc ] && fastfetch -c ~/.config/fastfetch/minimal.jsonc
echo

# Starship
export PATH="$HOME/.local/bin:$PATH"

# `claude` sin argumentos abre el buscador interactivo de sesiones anteriores
# (equivalente a `claude --resume`); `claude new` fuerza una sesión nueva de
# cero (ignora --resume); con cualquier otro argumento se comporta como
# siempre (claude doctor, claude plugin ..., claude -p "...", etc.)
claude() {
  if [ "$#" -eq 0 ]; then
    command claude --resume
  elif [ "$1" = "new" ]; then
    shift
    command claude "$@"
  else
    command claude "$@"
  fi
}

# Added by LM Studio CLI (lms)
export PATH="$PATH:$HOME/.lmstudio/bin"
# End of LM Studio CLI section

command -v zoxide >/dev/null && eval "$(zoxide init bash)"
export DXVK_CONFIG_FILE="$HOME/.config/dxvk/dxvk.conf"

export PATH="$HOME/src/depot_tools:$PATH"

# Auto-lanzar zsh si estamos en un terminal interactivo y no ya en zsh
if [ -t 1 ] && [ -z "$ZSH_VERSION" ] && command -v zsh >/dev/null 2>&1; then
  exec zsh
fi

# Modo bestia (solo si los scripts están en este equipo)
if command -v bestia-on >/dev/null; then
  alias bestia-on='sudo bestia-on' bestia-off='sudo bestia-off' bestia-status='sudo bestia-status'
fi
# Rust (solo si está instalado en este equipo)
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
