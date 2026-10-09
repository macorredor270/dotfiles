#!/bin/bash
# Enlaza estas configs en el home. Hace copia de seguridad de lo que ya exista.
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
BK="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"
link() {
  local from="$1" to="$2"
  mkdir -p "$(dirname "$to")"
  if [ -e "$to" ] || [ -L "$to" ]; then mkdir -p "$BK"; mv "$to" "$BK/"; fi
  ln -s "$from" "$to"
  echo "enlazado: $to"
}
for d in "$SRC"/config/*; do
  [ -d "$d" ] && link "$d" "$HOME/.config/$(basename "$d")"
done
link "$SRC/config/mimeapps.list" "$HOME/.config/mimeapps.list"
for f in "$SRC"/local-bin/*; do link "$f" "$HOME/.local/bin/$(basename "$f")"; done
for f in "$SRC"/local-share/*; do link "$f" "$HOME/.local/share/applications/$(basename "$f")"; done
link "$SRC/.zshrc" "$HOME/.zshrc"
echo "listo. copias previas en: $BK (si hubo algo)"
