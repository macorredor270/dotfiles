#!/usr/bin/env bash
# install.sh — dotfiles (CachyOS / Arch + Hyprland). Tres órdenes, nada más:
#
#   ./install.sh --instalar   instala todo: paquetes, drivers, enlaces de configuración, servicios, tema y ajustes
#   ./install.sh --reparar    arregla enlaces rotos (p. ej. si moviste o borraste el repo) y rehace los ajustes de este equipo
#   ./install.sh --deshacer   quita todo lo instalado y deja tus configuraciones como antes de la primera instalación
#
#   ./install.sh              (sin nada) abre un menú: elige con ↑ ↓ y Enter, con 1 2 3, o escribe instalar / reparar / deshacer
#
# Se puede repetir sin miedo: si ya está todo aplicado, lo dice y no toca nada. Sin terminal (sin teclado) solo muestra esta ayuda.
# Antes de tocar nada guarda una copia en ~/.dotfiles-backup-FECHA.tar.gz (y lo reemplazado, en ~/.dotfiles-backup-FECHA/).
# En una distro que no es Arch solo enlaza las configuraciones (no instala paquetes ni toca /etc). Registro: ~/.dotfiles-install.log
#
# En cada PC genera ~/.config/hypr/equipo.lua y equipo.conf (pantallas con su mejor tasa de refresco,
# variables de NVIDIA si hace falta): así hyprland.lua/.conf del repo valen en cualquier equipo.
set -Eeuo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
BK="$HOME/.dotfiles-backup-$STAMP"
LOG="$HOME/.dotfiles-install.log"
MANIFIESTO="$HOME/.local/state/dotfiles/instalado"   # todo lo que crea el instalador, para poder quitarlo
ORIGEN_HOME="/home/m1ke"   # ruta que aparece escrita a mano en algunas configs
APLICADO="$HOME/.local/state/dotfiles/aplicado"   # repo + huella + fecha + opciones de la última instalación completa

VISUAL=0; SIMULAR=0; ACTUALIZAR=1; PAQUETES=1; AUR=1; ENLACES=1; SISTEMA=1; RENDIMIENTO=1; OPCIONALES=0; SOLO=""
OKN=0; AVISOS=0; FALLOS=0; ENLAZADOS=0; REPARAR=0; PENDIENTE=0   # PENDIENTE=1: falta un reinicio y repetir --instalar

# ── mensajes ───────────────────────────────────────────────────────────────
# Colores solo si la salida es una terminal (en un archivo o una tubería no hay códigos raros) y sin NO_COLOR
if [[ -t 1 && -z ${NO_COLOR:-} && ${TERM:-dumb} != dumb ]]; then
  c_ok=$'\033[32m'; c_warn=$'\033[33m'; c_bad=$'\033[31m'; c_dim=$'\033[2m'; c_off=$'\033[0m'
  c_bold=$'\033[1m'; c_head=$'\033[1;36m'; c_mag=$'\033[1;35m'; c_sel=$'\033[1;30;46m'
else
  c_ok=""; c_warn=""; c_bad=""; c_dim=""; c_off=""; c_bold=""; c_head=""; c_mag=""; c_sel=""
fi
say()   { printf '%s\n' "$*" | tee -a "$LOG" >/dev/null; printf '%s\n' "$*"; }
fase()  { printf '\n== %s ==\n' "$*" >>"$LOG"; printf '\n%s▌ %s%s\n' "$c_head" "$*" "$c_off"; }
ok()    { OKN=$((OKN+1));       printf '  %sOK%s     %s\n' "$c_ok" "$c_off" "$*"; printf '  OK     %s\n' "$*" >>"$LOG"; }
aviso() { AVISOS=$((AVISOS+1)); printf '  %sAVISO%s  %s\n' "$c_warn" "$c_off" "$*"; printf '  AVISO  %s\n' "$*" >>"$LOG"; }
fallo() { FALLOS=$((FALLOS+1)); printf '  %sFALLO%s  %s\n' "$c_bad" "$c_off" "$*"; printf '  FALLO  %s\n' "$*" >>"$LOG"; }
nota()  { printf '  %s%s%s\n' "$c_dim" "$*" "$c_off"; }

# Ejecuta un comando y deja su salida en el registro.
run() {
  if (( SIMULAR )); then printf '  %s[sim]%s %s\n' "$c_dim" "$c_off" "$*"; return 0; fi
  printf '  $ %s\n' "$*" >>"$LOG"
  "$@" >>"$LOG" 2>&1
}
root() { run sudo "$@"; }
apuntar() {   # apuntar RUTA: anota algo creado por el instalador (lo quitará --deshacer)
  (( SIMULAR )) && return 0
  mkdir -p "$(dirname "$MANIFIESTO")"; printf '%s\n' "$1" >>"$MANIFIESTO"
}

# ── argumentos ─────────────────────────────────────────────────────────────
uso() { awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit "${1:-0}"; }   # imprime la cabecera de comentarios
DESHACER=0; DESHACER_ARCHIVO=""
if (( $# > 1 )); then echo "solo se admite una orden a la vez"; echo; uso 2; fi
quiere() { [[ -z "$SOLO" || "$SOLO" == "$1" ]]; }   # ¿toca ejecutar esta fase?
# grep sobre la salida de un comando, sin tuberías: con pipefail, "cmd | grep -q" da falsos negativos por SIGPIPE
en_salida() { local pat="$1" out; shift; out="$("$@" 2>&1 || true)"; grep -qiE -- "$pat" <<<"$out"; }

# ── ¿ya está aplicado? · enlaces rotos · reparar ───────────────────────────
es_arch() { ( . /etc/os-release 2>/dev/null; [[ "${ID:-}" == arch || "${ID_LIKE:-}" == *arch* || "${ID:-}" == cachyos ]] ); }

# Con las opciones que se han pedido y lo que de verdad aplica en este equipo (no-Arch no instala paquetes)
firma() {
  local p=$PAQUETES s=$SISTEMA
  es_arch || { p=0; s=0; }
  echo "P$p S$s R$RENDIMIENTO E$ENLACES A$AUR V$VISUAL O$OPCIONALES"
}

# «Huella» del contenido del repo: si no cambia, no hay nada nuevo que instalar
huella() { ( cd "$SRC" && find . -type f -not -path './.git/*' -printf '%P\t%s\t%T@\n' | LC_ALL=C sort | sha256sum | cut -d' ' -f1 ); }

# Un enlace roto apuntaba a una copia vieja del repo (p. ej. ~/Workspace/web/dotfiles/config/hypr/x.conf).
# Se busca el trozo final de esa ruta dentro de ESTE repo (config/hypr/x.conf) y se imprime la ruta nueva.
destino_en_repo() {
  local s="${1#/}"
  while [[ $s == */* ]]; do
    s="${s#*/}"
    if [[ -e $SRC/$s ]]; then printf '%s\n' "$SRC/$s"; return 0; fi
  done
  return 1
}
enlaces_rotos() {   # enlaces rotos de tu carpeta que apuntaban a otra copia de este repo (no toca los de otras cosas)
  local l
  while IFS= read -r l; do
    if destino_en_repo "$(readlink "$l")" >/dev/null; then printf '%s\n' "$l"; fi
  done < <(
    find "$HOME/.config" "$HOME/.local/bin" "$HOME/.local/share/applications" -maxdepth 6 -xtype l 2>/dev/null
    find "$HOME" -maxdepth 1 -xtype l 2>/dev/null)
}
enlaces_ok() {      # ¿está todo lo de este repo en su sitio y sin enlaces rotos?
  local f rel
  while IFS= read -r -d '' f; do
    rel="${f#"$SRC"/config/}"
    [[ $rel == mimeapps.list ]] && continue
    [[ -e $HOME/.config/$rel ]] || return 1
  done < <(find "$SRC/config" -type f -print0)
  [[ -e $HOME/.zshrc && -e $HOME/.bashrc ]] || return 1
  for f in "$SRC"/local-bin/*; do
    if [[ -f $f && ! -e $HOME/.local/bin/${f##*/} ]]; then return 1; fi
  done
  [[ -z "$(enlaces_rotos)" ]]
}
ya_aplicado() {     # ¿ya se aplicó exactamente esto, desde este mismo sitio, y sigue todo en su sitio?
  [[ -f $APLICADO ]] || return 1
  [[ "$(sed -n 1p "$APLICADO")" == "$SRC" ]] || return 1
  [[ "$(sed -n 2p "$APLICADO")" == "$(huella)" ]] || return 1
  [[ "$(sed -n 4p "$APLICADO")" == "$(firma)" ]] || return 1
  enlaces_ok
}
marcar_aplicado() {
  mkdir -p "$(dirname "$APLICADO")"
  printf '%s\n%s\n%s\n%s\n' "$SRC" "$(huella)" "$(date '+%F %T')" "$(firma)" >"$APLICADO"
}
comprobar_aplicado() {   # si ya está todo aplicado lo dice y sale; si no, explica por qué sigue
  (( REPARAR )) && return 0   # --reparar siempre revisa y rehace lo que falte
  [[ -f $APLICADO ]] || return 0
  if ya_aplicado; then
    say ""; say "== Ya está aplicado =="
    say "  Estos dotfiles se aplicaron el $(sed -n 3p "$APLICADO") desde $SRC y todo sigue en su sitio."
    say "  No hay nada nuevo que instalar: no he tocado nada."
    say "    ./install.sh --reparar   si algo no carga (enlaces rotos, repo movido)"
    say "    ./install.sh --deshacer  volver a como estaba antes (y luego --instalar para empezar de cero)"
    exit 0
  fi
  local previo; previo="$(sed -n 1p "$APLICADO")"
  if [[ $previo != "$SRC" ]]; then nota "se instalaron antes desde $previo; ahora se enlazan desde $SRC"; fi
  if [[ "$(sed -n 2p "$APLICADO")" != "$(huella)" ]]; then nota "el repositorio cambió desde la última instalación: se aplica lo nuevo"; fi
  if ! enlaces_ok; then aviso "faltan configuraciones o hay enlaces rotos: se rehacen (también vale ./install.sh --reparar)"; fi
  return 0
}

# ── comprobaciones previas ─────────────────────────────────────────────────
preflight() {
  fase "Comprobaciones previas"
  if (( EUID == 0 )); then fallo "no lo ejecutes como root: lanza ./install.sh con tu usuario (usa sudo por dentro)"; exit 1; fi
  if [[ -n ${SUDO_USER:-} ]]; then aviso "lo has lanzado con sudo (usuario $SUDO_USER): ejecútalo sin sudo; pide la contraseña por dentro cuando hace falta"; fi
  : >>"$LOG"
  # herramientas básicas que usa este script (antes de fallar a medias, se comprueban)
  local c faltan=()
  for c in sed find install mktemp readlink tar df stat cmp awk sha256sum; do command -v "$c" >/dev/null || faltan+=("$c"); done
  if (( ${#faltan[@]} )); then fallo "faltan herramientas básicas: ${faltan[*]} (instala coreutils, findutils, sed, tar y gawk)"; exit 1; fi
  if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4) )); then
    fallo "hace falta bash 4.4 o superior (tienes $BASH_VERSION)"; exit 1
  fi
  if [[ ! -w $HOME ]]; then fallo "no puedo escribir en $HOME"; exit 1; fi
  # shellcheck disable=SC1091
  . /etc/os-release 2>/dev/null || true
  if [[ "${ID:-}" == "arch" || "${ID_LIKE:-}" == *arch* || "${ID:-}" == "cachyos" ]]; then
    ok "distro: ${PRETTY_NAME:-$ID}"
  else
    aviso "distro no basada en Arch (${PRETTY_NAME:-?}): solo se enlazarán las configuraciones; instala a mano lo de packages/*.txt"
    PAQUETES=0; SISTEMA=0
  fi
  local libre; libre=$(df -BG --output=avail / | tail -1 | tr -dc '0-9')
  if (( libre >= 10 )); then ok "espacio libre en /: ${libre} GB"; else aviso "poco espacio libre en /: ${libre} GB"; fi
  [[ -d "$SRC/config" ]] && ok "repositorio: $SRC" || { fallo "no encuentro $SRC/config"; exit 1; }
  case "$SRC" in
    /tmp/*|/var/tmp/*|/run/*|/media/*|/mnt/*|"$HOME"/Descargas/*|"$HOME"/Downloads/*|"$HOME"/.local/share/Trash/*)
      aviso "el repositorio está en $SRC: las configuraciones se ENLAZAN a esta carpeta y dejarían de cargar si la mueves o la borras. Mejor: git clone https://github.com/macorredor270/dotfiles ~/dotfiles" ;;
  esac
  if (( PAQUETES || SISTEMA )) && ! (( SIMULAR )) && [[ -z "$SOLO" || "$SOLO" =~ ^(paquetes|sistema|servicios|shell)$ ]]; then
    if curl -fsS -m 8 -o /dev/null https://archlinux.org; then ok "red: archlinux.org responde"
    else aviso "sin red: los pasos que descargan fallarán"; fi
    if sudo -v; then
      ok "sudo listo (se mantiene activo mientras dure el script)"
      ( while true; do sudo -n true 2>/dev/null || exit; sleep 50; kill -0 $$ 2>/dev/null || exit; done ) &
      KEEPALIVE=$!
      trap 'kill "$KEEPALIVE" 2>/dev/null || true' EXIT
    else
      fallo "sin sudo: se saltarán los pasos de sistema"; PAQUETES=0; SISTEMA=0
    fi
  fi
}

# ── paquetes ───────────────────────────────────────────────────────────────
leer_lista() { grep -vE '^\s*(#|$)' "$1" | awk '{print $1}'; }

instalar_pacman() {
  local -a want=("$@") faltan=() disponibles=() noexiste=()
  (( ${#want[@]} )) || return 0
  mapfile -t faltan < <(pacman -T "${want[@]}" 2>/dev/null || true)
  if (( ${#faltan[@]} == 0 )); then ok "pacman: todo lo pedido ya está instalado (${#want[@]} paquetes)"; return 0; fi
  mapfile -t disponibles < <(comm -12 <(printf '%s\n' "${faltan[@]}" | sort -u) <(pacman -Slq | sort -u))
  mapfile -t noexiste   < <(comm -23 <(printf '%s\n' "${faltan[@]}" | sort -u) <(pacman -Slq | sort -u))
  (( ${#noexiste[@]} )) && aviso "no existen en tus repos (se omiten): ${noexiste[*]}"
  (( ${#disponibles[@]} )) || return 0
  say "  instalando ${#disponibles[@]} paquetes: ${disponibles[*]}"
  if root pacman -S --needed --noconfirm "${disponibles[@]}"; then
    ok "pacman: ${#disponibles[@]} paquetes instalados"
  else
    aviso "falló la instalación en bloque; pruebo uno a uno para aislar el culpable"
    local p
    for p in "${disponibles[@]}"; do
      if root pacman -S --needed --noconfirm "$p"; then :; else fallo "no se pudo instalar: $p"; fi
    done
  fi
}

asegurar_paru() {
  command -v paru >/dev/null && { ok "paru ya está instalado"; return 0; }
  command -v yay >/dev/null && { AUR_HELPER=yay; ok "uso yay para el AUR"; return 0; }
  say "  paru no está: lo compilo desde el AUR (paru-bin)"
  local tmp; tmp="$(mktemp -d)"
  if (( SIMULAR )); then nota "[sim] git clone https://aur.archlinux.org/paru-bin.git && makepkg -si"; return 0; fi
  if git clone -q https://aur.archlinux.org/paru-bin.git "$tmp/paru-bin" && ( cd "$tmp/paru-bin" && makepkg -si --noconfirm >>"$LOG" 2>&1 ); then
    ok "paru instalado"
  else
    fallo "no pude instalar paru: salto el AUR"; AUR=0
  fi
  rm -rf "$tmp"
}

detectar_hardware() {
  GPU_NVIDIA=0; GPU_AMD=0; GPU_INTEL=0; CPU_AMD=0; CPU_INTEL=0; NVIDIA_VIEJA=0
  # Por identificador de fabricante PCI (10de=NVIDIA, 1002=AMD, 8086=Intel), solo en tarjetas gráficas (clases 0300, 0302, 0380)
  local gpus; gpus="$(lspci -nn 2>/dev/null | grep -E '\[03(00|02|80)\]' || true)"
  grep -q '\[10de:' <<<"$gpus" && GPU_NVIDIA=1
  grep -q '\[1002:' <<<"$gpus" && GPU_AMD=1
  grep -q '\[8086:' <<<"$gpus" && GPU_INTEL=1
  grep -q 'AuthenticAMD' /proc/cpuinfo && CPU_AMD=1
  grep -q 'GenuineIntel' /proc/cpuinfo && CPU_INTEL=1
  # GPUs NVIDIA anteriores a Turing (GTX 9xx/10xx y más viejas) no funcionan con los módulos abiertos
  local nv; nv="$(grep -iE '\[10de:' <<<"$gpus" || true)"
  grep -qiE 'GeForce (GTX )?(9[0-9]{2}|10[0-9]{2})|GeForce GT [0-9]{3}|Quadro [KMP]' <<<"$nv" && NVIDIA_VIEJA=1
  say "  hardware: GPU nvidia=$GPU_NVIDIA amd=$GPU_AMD intel=$GPU_INTEL · CPU amd=$CPU_AMD intel=$CPU_INTEL"
}

paquetes_hardware() {   # imprime los paquetes que dependen del hardware
  (( CPU_AMD ))   && echo amd-ucode
  (( CPU_INTEL )) && echo intel-ucode
  if (( GPU_NVIDIA )); then
    if (( NVIDIA_VIEJA )); then echo nvidia-dkms; else echo nvidia-open-dkms; fi
    printf '%s\n' nvidia-utils lib32-nvidia-utils nvidia-settings libva-nvidia-driver
    # DKMS necesita las cabeceras de CADA kernel instalado (si falta una, el módulo no se compila)
    local pb; for pb in /usr/lib/modules/*/pkgbase; do [[ -r $pb ]] && echo "$(<"$pb")-headers"; done
  fi
  (( GPU_AMD ))   && printf '%s\n' mesa vulkan-radeon libva-mesa-driver lib32-mesa lib32-vulkan-radeon
  (( GPU_INTEL )) && printf '%s\n' mesa vulkan-intel intel-media-driver lib32-mesa lib32-vulkan-intel
  return 0
}

fase_paquetes() {
  quiere paquetes || return 0
  (( PAQUETES )) || { fase "Paquetes (omitido)"; return 0; }
  fase "Paquetes"
  local lista_pacman="$SRC/packages/pacman.txt" lista_aur="$SRC/packages/aur.txt"
  if (( VISUAL )); then lista_pacman="$SRC/packages/visual.txt"; lista_aur="$SRC/packages/aur-visual.txt"; nota "(modo ligero: sin drivers, sin -Syu, sin ajustes de sistema)"
  else detectar_hardware; fi
  if (( ACTUALIZAR )); then
    say "  actualizando el sistema (pacman -Syu): necesario para no mezclar paquetes viejos y nuevos"
    root pacman -Syu --noconfirm && ok "sistema actualizado" || aviso "pacman -Syu falló; sigo, pero pueden salir errores 404"
  else
    nota "(sin -Syu: si pacman da 404, ejecuta sudo pacman -Syu y repite ./install.sh --instalar)"
  fi
  local -a lista=()
  mapfile -t lista < <( { leer_lista "$lista_pacman"; (( VISUAL )) || paquetes_hardware; (( OPCIONALES )) && leer_lista "$SRC/packages/opcional.txt"; true; } | sort -u )
  instalar_pacman "${lista[@]}"
  if (( ! VISUAL && GPU_NVIDIA )) && ! (( SIMULAR )); then
    local conf=/etc/modprobe.d/nvidia-dotfiles.conf
    if en_salida 'parm:.*modeset' modinfo nvidia_drm; then
      printf 'options nvidia_drm modeset=1 fbdev=1\n' | sudo tee "$conf" >/dev/null && ok "NVIDIA: modeset=1 y fbdev=1 escritos en $conf"
    else
      aviso "nvidia_drm aún no está disponible (se compila al reiniciar con DKMS): reinicia y repite ./install.sh --instalar"; PENDIENTE=1
    fi
    grep -qE '^MODULES=.*nvidia_drm' /etc/mkinitcpio.conf 2>/dev/null || nota "consejo: añade nvidia nvidia_modeset nvidia_uvm nvidia_drm a MODULES en /etc/mkinitcpio.conf y ejecuta mkinitcpio -P"
  fi
  if (( AUR )); then
    AUR_HELPER=paru
    asegurar_paru
    if (( AUR )); then
      local -a aur=(); mapfile -t aur < <(leer_lista "$lista_aur")
      local -a faltan=(); local p
      for p in "${aur[@]}"; do pacman -Qq "$p" >/dev/null 2>&1 || faltan+=("$p"); done
      if (( ${#faltan[@]} == 0 )); then ok "AUR: todo instalado"
      elif run "$AUR_HELPER" -S --needed --noconfirm "${faltan[@]}"; then ok "AUR: ${faltan[*]}"
      else
        aviso "AUR en bloque falló; uno a uno"
        for p in "${faltan[@]}"; do run "$AUR_HELPER" -S --needed --noconfirm "$p" || fallo "AUR: $p"; done
      fi
    fi
  fi
}

# ── enlaces ────────────────────────────────────────────────────────────────
respaldar() {   # mueve un destino existente a la carpeta de copias, conservando su ruta
  local to="$1"
  run mkdir -p "$BK$(dirname "$to")"
  run mv "$to" "$BK$to"
}

SED_ARGS=()
preparar_reescritura() {   # ajustes que dependen del equipo y que no pueden ir fijos en el repo
  SED_ARGS=()
  [[ "$HOME" != "$ORIGEN_HOME" ]] && SED_ARGS+=(-e "s|$ORIGEN_HOME|$HOME|g")
  # Sensor de temperatura de la CPU: el número de hwmonN cambia entre equipos (y entre arranques)
  local h n dev cpu='^(k10temp|coretemp|zenpower|cpu_thermal)$'
  n="$(cat ${HWMON_DIR:-/sys/class/hwmon}/hwmon1/name 2>/dev/null || true)"
  if [[ ! "$n" =~ $cpu ]]; then
    for h in "${HWMON_DIR:-/sys/class/hwmon}"/hwmon*; do
      n="$(cat "$h/name" 2>/dev/null || true)"
      if [[ "$n" =~ $cpu ]]; then
        dev="$(readlink -f "$h/device" 2>/dev/null || true)"
        if [[ -d $dev/hwmon ]]; then
          SED_ARGS+=(-e "s|\"hwmon-path\": \"/sys/class/hwmon/hwmon1/temp1_input\"|\"hwmon-path-abs\": \"$dev/hwmon\", \"input-filename\": \"temp1_input\"|")
          nota "sensor de CPU de este equipo: $n ($dev)"
        fi
        break
      fi
    done
  fi
}

enlazar() {     # enlazar ORIGEN DESTINO  (symlink; copia con rutas/sensor ajustados si hace falta)
  local from="$1" to="$2" tmp
  if (( ${#SED_ARGS[@]} )) && grep -qI . "$from" 2>/dev/null; then
    tmp="$(mktemp)"; sed "${SED_ARGS[@]}" "$from" >"$tmp"
    if ! cmp -s "$tmp" "$from"; then   # este archivo necesita ajustes para este equipo
      if [[ -f $to && ! -L $to ]] && cmp -s "$tmp" "$to"; then rm -f "$tmp"; return 0; fi
      [[ -e $to || -L $to ]] && respaldar "$to"
      run mkdir -p "$(dirname "$to")"; run install -m "$(stat -c %a "$from")" "$tmp" "$to"; rm -f "$tmp"; apuntar "$to"
      nota "copiado con ajustes para este equipo (no enlazado): $to"; ENLAZADOS=$((ENLAZADOS+1)); return 0
    fi
    rm -f "$tmp"
  fi
  if [[ -L $to && "$(readlink -f "$to")" == "$(readlink -f "$from")" ]]; then return 0; fi
  [[ -e $to || -L $to ]] && respaldar "$to"
  run mkdir -p "$(dirname "$to")"
  run ln -s "$from" "$to"; apuntar "$to"
  ENLAZADOS=$((ENLAZADOS+1))
}

fase_enlaces() {
  quiere enlaces || return 0
  (( ENLACES )) || { fase "Enlaces (omitido)"; return 0; }
  fase "Enlaces de configuración"
  ENLAZADOS=0
  preparar_reescritura
  local f rel
  # Todo lo de config/ va a ~/.config, archivo por archivo (así no se pisa lo que haya al lado)
  while IFS= read -r -d '' f; do
    rel="${f#"$SRC"/config/}"
    # mimeapps.list lo reescriben las propias apps: solo se pone si el equipo aún no tiene uno
    [[ $rel == mimeapps.list && -e $HOME/.config/$rel ]] && continue
    enlazar "$f" "$HOME/.config/$rel"
  done < <(find "$SRC/config" -type f -print0)
  enlazar "$SRC/.zshrc" "$HOME/.zshrc"
  enlazar "$SRC/.bashrc" "$HOME/.bashrc"
  for f in "$SRC"/local-bin/*; do [[ -f $f ]] && enlazar "$f" "$HOME/.local/bin/$(basename "$f")"; done
  for f in "$SRC"/local-share/*.desktop; do [[ -f $f ]] && enlazar "$f" "$HOME/.local/share/applications/$(basename "$f")"; done
  run mkdir -p "$HOME/Pictures/wallpapers" "$HOME/Pictures/Screenshots" "$HOME/Descargas" "$HOME/.local/state"
  # el bloqueo (hyprlock) muestra ~/Pictures/avatar.png: si no hay uno, se crea uno de ejemplo con tu inicial
  if ! (( SIMULAR )) && [[ ! -e $HOME/Pictures/avatar.png ]] && command -v magick >/dev/null; then
    local ini="${USER:-u}"
    if magick -size 256x256 xc:'#2b2b2b' -fill '#d0d0d0' -gravity center -pointsize 120 -annotate 0 "${ini:0:1}" "$HOME/Pictures/avatar.png" 2>/dev/null; then
      apuntar "$HOME/Pictures/avatar.png"; nota "avatar de ejemplo en ~/Pictures/avatar.png (cámbialo por el tuyo)"
    fi
  fi
  if ! (( SIMULAR )); then
    for f in "$SRC"/wallpapers/*; do
      [[ -e $HOME/Pictures/wallpapers/${f##*/} ]] && continue
      cp "$f" "$HOME/Pictures/wallpapers/" && apuntar "$HOME/Pictures/wallpapers/${f##*/}"
    done
  fi
  # aria2 necesita la ruta de descargas escrita: se genera desde la plantilla
  if [[ -f "$SRC/templates/aria2.conf" ]]; then
    local out="$HOME/.config/aria2/aria2.conf" tmp; tmp="$(mktemp)"
    sed "s|@HOME@|$HOME|g" "$SRC/templates/aria2.conf" >"$tmp"
    if [[ -f $out ]] && cmp -s "$tmp" "$out"; then :; else
      [[ -e $out ]] && respaldar "$out"
      run mkdir -p "$(dirname "$out")"; run install -m 644 "$tmp" "$out"; apuntar "$out"; ENLAZADOS=$((ENLAZADOS+1))
    fi; rm -f "$tmp"
  fi
  ok "enlaces: $ENLAZADOS nuevos o actualizados"
  [[ -d $BK ]] && ok "copias de lo anterior en: $BK"
  case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) aviso "$HOME/.local/bin no está en tu PATH (lo añade .zshrc al abrir una terminal nueva)";; esac
}

# ── copia de seguridad completa (antes de enlazar nada) ─────────────────────
RUTAS_COPIA=(.config/hypr .config/waybar .config/rofi .config/kitty .config/mako .config/fastfetch
  .config/quickshell .config/pipewire .config/gtk-3.0 .config/gtk-4.0 .config/systemd/user/aria2.service
  .config/starship.toml .config/mimeapps.list .zshrc .bashrc .local/state/fondos)
fase_copia() {
  quiere copia || { [[ $SOLO == enlaces ]] || return 0; }
  (( ENLACES )) || return 0
  fase "Copia de seguridad"
  # Solo la de ANTES de la primera instalación: repetir el instalador no acumula copias (lo que se reemplaza
  # después se aparta en ~/.dotfiles-backup-FECHA/ y --deshacer vuelve a la más antigua)
  if [[ -f $APLICADO ]] && compgen -G "$HOME/.dotfiles-backup-*.tar.gz" >/dev/null; then
    ok "ya existe la copia de antes de la primera instalación: no se acumulan más"; return 0
  fi
  local -a hay=() r; for r in "${RUTAS_COPIA[@]}"; do [[ -e $HOME/$r ]] && hay+=("$r"); done
  # de ~/.local/bin solo los scripts que este repo va a reemplazar (ahí suele haber binarios enormes)
  for r in "$SRC"/local-bin/*; do [[ -e $HOME/.local/bin/${r##*/} ]] && hay+=(".local/bin/${r##*/}"); done
  (( ${#hay[@]} )) || { ok "no hay configuraciones previas que guardar"; return 0; }
  local tar="$HOME/.dotfiles-backup-$STAMP.tar.gz"
  # -h guarda el contenido real aunque ya sean enlaces a este repo; se saltan las carpetas bak/ y copias viejas
  if run tar -C "$HOME" -czhf "$tar" --exclude='*/bak' --exclude='*.bak*' --exclude='*/node_modules' "${hay[@]}"; then
    ok "copia completa: $tar"
    nota "para volver atrás: ./install.sh --deshacer"
  else
    fallo "no se pudo hacer la copia de seguridad: no sigo para no perder nada"; exit 1
  fi
}

deshacer() {
  local tar="$DESHACER_ARCHIVO" p n=0
  # por defecto la copia MÁS ANTIGUA: la de antes de instalar estos dotfiles por primera vez
  local sin_copia=0
  [[ -z $DESHACER_ARCHIVO || -f $DESHACER_ARCHIVO ]] || { echo "no existe la copia $DESHACER_ARCHIVO"; exit 1; }
  [[ -n $tar ]] || tar="$(ls -tr "$HOME"/.dotfiles-backup-*.tar.gz 2>/dev/null | head -1 || true)"
  if [[ -z $tar || ! -f $tar ]]; then
    # se instaló sobre un equipo sin configuraciones previas: no hay nada que devolver, solo se quitan los enlaces
    [[ -f $MANIFIESTO ]] || { echo "no hay copia ~/.dotfiles-backup-*.tar.gz ni registro de instalación: nada que deshacer"; exit 1; }
    sin_copia=1; echo "No hay copia previa (se instaló sobre un equipo sin configuraciones): solo se quitan los enlaces de estos dotfiles"
  else
    echo "Restaurando $tar"
  fi
  # 1) quita lo que creó el instalador (enlaces y copias ajustadas), según el registro
  if [[ -f $MANIFIESTO ]]; then
    while IFS= read -r p; do
      [[ $p == "$HOME"/* ]] || continue                    # nunca nada fuera de tu carpeta
      if [[ -e $p || -L $p ]]; then rm -rf -- "$p"; n=$((n+1)); fi
      # carpetas que quedaron vacías (solo vacías, y nunca por encima de tu $HOME)
      local d; d="$(dirname "$p")"
      while [[ $d == "$HOME"/* ]] && rmdir -- "$d" 2>/dev/null; do d="$(dirname "$d")"; done
    done < <(sort -u "$MANIFIESTO")
  fi
  # 2) enlaces sueltos al repo de instalaciones antiguas sin registro
  while IFS= read -r p; do rm -f -- "$p"; n=$((n+1)); done < <(
    find "$HOME/.config" "$HOME/.local/bin" "$HOME/.local/share/applications" -maxdepth 6 -lname "$SRC/*" 2>/dev/null
    find "$HOME" -maxdepth 1 -lname "$SRC/*" 2>/dev/null)
  echo "  quitados $n archivos y enlaces de estos dotfiles"
  # 3) devuelve lo que había
  if (( ! sin_copia )); then tar -C "$HOME" -xzf "$tar" || { echo "no pude extraer $tar"; exit 1; }; fi
  # las copias usadas se apartan para que una próxima instalación empiece de cero
  mkdir -p "$HOME/.dotfiles-backups-usadas"
  mv "$HOME"/.dotfiles-backup-*.tar.gz "$HOME/.dotfiles-backups-usadas/" 2>/dev/null || true
  rm -f "$MANIFIESTO" "$APLICADO"; rmdir -p --ignore-fail-on-non-empty "$(dirname "$MANIFIESTO")" 2>/dev/null || true
  if (( sin_copia )); then echo "Listo: enlaces de estos dotfiles quitados. Cierra sesión y vuelve a entrar."
  else echo "Listo: configuraciones restauradas (copias apartadas en ~/.dotfiles-backups-usadas). Cierra sesión y vuelve a entrar."; fi
  exit 0
}

# ── ajustes de ESTE equipo: pantallas, GPU, fondos, fuentes y audio ────────
modos_monitores() {   # imprime «nombre modo escala» por pantalla, con la mejor resolución y tasa
  command -v hyprctl >/dev/null && command -v jq >/dev/null || return 1
  local j; j="$(hyprctl monitors all -j 2>/dev/null)" || return 1
  [[ $j == \[* ]] || return 1
  jq -r '.[] | . as $m
    | ([.availableModes[]? | capture("(?<w>[0-9]+)x(?<h>[0-9]+)@(?<r>[0-9.]+)")
        | {w:(.w|tonumber), h:(.h|tonumber), r:(.r|tonumber)}]
       | sort_by(.w*.h, .r) | last) as $b
    | if $b then "\($m.name) \($b.w)x\($b.h)@\($b.r|.*100|round/100) \($m.scale)"
      else "\($m.name) preferred \($m.scale)" end' <<<"$j"
}

fase_equipo() {
  quiere equipo || return 0
  (( ENLACES )) || { fase "Equipo (omitido)"; return 0; }
  fase "Ajustes de este equipo"
  local dir="$HOME/.config/hypr" lua="$HOME/.config/hypr/equipo.lua" conf="$HOME/.config/hypr/equipo.conf"
  [[ -n ${GPU_NVIDIA+x} ]] || detectar_hardware >/dev/null
  run mkdir -p "$dir"
  if [[ -f $lua && -f $conf ]]; then
    ok "pantallas: equipo.lua y equipo.conf ya existen (bórralos y ejecuta ./install.sh --reparar para regenerarlos)"
  else
    local l_lua="" l_conf="" nombre modo escala
    local modos cab equipo_nombre
    equipo_nombre="$(cat /etc/hostname 2>/dev/null || hostname 2>/dev/null || echo 'este equipo')"
    cab="generado por install.sh el $(date +%F) en $equipo_nombre; no está en el repo, edítalo a tu gusto"
    if modos="$(modos_monitores)" && [[ -n $modos ]]; then
      while read -r nombre modo escala; do
        l_lua+="hl.monitor({ output = \"$nombre\", mode = \"$modo\", position = \"auto\", scale = $escala })"$'\n'
        l_conf+="monitor = $nombre, $modo, auto, $escala"$'\n'
        nota "pantalla $nombre → $modo (escala $escala)"
      done <<<"$modos"
    else
      l_lua="-- Sin sesión de Hyprland no se pueden leer las pantallas: todas usan su modo preferido."$'\n'"-- Ejecuta ./install.sh --reparar desde Hyprland para fijar la mejor tasa de refresco."$'\n'
      l_conf="${l_lua//--/#}"
      aviso "no estoy dentro de Hyprland: pantallas en modo automático (ejecuta ./install.sh --reparar ya dentro para afinarlas)"
    fi
    local nv_conf=""
    (( GPU_NVIDIA )) && nv_conf=$'env = LIBVA_DRIVER_NAME,nvidia\nenv = GBM_BACKEND,nvidia-drm\nenv = __GLX_VENDOR_LIBRARY_NAME,nvidia\nenv = WLR_NO_HARDWARE_CURSORS,1\n'
    if (( SIMULAR )); then
      nota "[sim] escribiría $lua y $conf:"; printf '%s' "$l_lua" | sed 's/^/      /'
    else
      [[ -f $lua ]]  || { printf -- '-- %s\n%s' "$cab" "$l_lua" >"$lua"; apuntar "$lua"; }
      [[ -f $conf ]] || { printf '# %s\n%s%s' "$cab" "$l_conf" "$nv_conf" >"$conf"; apuntar "$conf"; }
      ok "pantallas de este equipo en $lua (y equipo.conf para Hyprland sin Lua)"
    fi
  fi

  # Fuentes que no están en los repos (DM Serif Display, la hora de hyprlock)
  if [[ -d $SRC/fonts ]]; then
    local fu="$HOME/.local/share/fonts" nuevas=0 f
    while IFS= read -r -d '' f; do
      local to="$fu/${f#"$SRC"/fonts/}"
      [[ -f $to ]] && cmp -s "$f" "$to" && continue
      [[ -e $to ]] || apuntar "$to"
      run install -Dm 644 "$f" "$to"; nuevas=1
    done < <(find "$SRC/fonts" -type f -print0)
    (( nuevas )) && { run fc-cache -f "$fu"; ok "fuentes propias instaladas en $fu"; } || ok "fuentes propias ya instaladas"
  fi

  # Fondos: estado inicial, fondo del bloqueo y el fondo en pantalla si hay sesión
  local fondo="$HOME/.local/bin/fondo"
  if [[ -x $fondo ]] && ! (( SIMULAR )); then
    [[ -d $HOME/.local/state/fondos ]] || apuntar "$HOME/.local/state/fondos"
    [[ -f $HOME/.local/state/fondos/bloqueo.png ]] || "$fondo" bloqueo "$HOME/Pictures/wallpapers/lock-torres.png" >>"$LOG" 2>&1 || true
    [[ -f $HOME/.local/state/fondos/bloqueo.png ]] && ok "fondo del bloqueo listo (cámbialo con la tecla b en el selector)" || aviso "no pude preparar el fondo del bloqueo"
    if [[ -n ${WAYLAND_DISPLAY:-} ]]; then "$fondo" restaurar >>"$LOG" 2>&1 && ok "fondo puesto con $(command -v awww >/dev/null && echo 'awww (fundido)' || echo swaybg)"; fi
  fi
  [[ -f $HOME/Pictures/avatar.png ]] || nota "pon tu foto en ~/Pictures/avatar.png para que salga en el bloqueo"

  # EQ de PipeWire «M1ke EQ»: solo con el DAC USB para el que está hecho
  if grep -qs 'UACDemo' /proc/asound/cards; then
    enlazar "$SRC/extras/pipewire/m1ke-eq.conf" "$HOME/.config/pipewire/filter-chain.conf.d/m1ke-eq.conf"
    if [[ -S ${XDG_RUNTIME_DIR:-/run/user/$UID}/bus ]]; then run systemctl --user enable --now filter-chain.service && ok "EQ «M1ke EQ» activo (DAC USB Jieli detectado)"; fi
  else
    nota "EQ M1ke: el DAC USB Jieli no está conectado, no lo activo (extras/pipewire/m1ke-eq.conf)"
  fi
}

# ── Zen Browser (perfil con ajustes de rendimiento y tema oscuro) ───────────
perfil_zen() {
  local ini="$HOME/.config/zen/profiles.ini"
  [[ -f $ini ]] || return 1
  awk -F= '
    /^\[Install/ {inst=1; next}  /^\[/ {inst=0}
    inst && $1=="Default" {print $2; exit}' "$ini" | head -1 | while read -r p; do echo "$HOME/.config/zen/$p"; done
}
fase_zen() {
  quiere zen || return 0
  [[ -f "$SRC/zen/user.js" ]] || return 0
  fase "Zen Browser"
  if ! command -v zen-browser >/dev/null && ! command -v zen >/dev/null; then nota "Zen no está instalado: salto su user.js"; return 0; fi
  local p; p="$(perfil_zen || true)"
  if [[ -z "$p" || ! -d "$p" ]]; then
    aviso "no encuentro un perfil de Zen: ábrelo una vez y ejecuta ./install.sh --reparar"; return 0
  fi
  if [[ -f "$p/user.js" ]] && cmp -s "$SRC/zen/user.js" "$p/user.js"; then ok "user.js de Zen ya aplicado"; return 0; fi
  [[ -f "$p/user.js" ]] && respaldar "$p/user.js"
  run install -m 644 "$SRC/zen/user.js" "$p/user.js" && ok "user.js copiado al perfil de Zen (reinicia Zen)"
}

# ── shell ──────────────────────────────────────────────────────────────────
fase_shell() {
  quiere shell || return 0
  fase "Shell"
  local zsh; zsh="$(command -v zsh || true)"
  [[ -n $zsh ]] || { aviso "zsh no está instalado"; return 0; }
  if [[ "$(getent passwd "$USER" | cut -d: -f7)" == "$zsh" ]]; then ok "tu shell ya es zsh"
  else root chsh -s "$zsh" "$USER" && ok "shell cambiada a zsh (aplica al volver a iniciar sesión)" || aviso "no pude cambiar la shell"; fi
}

# ── servicios ──────────────────────────────────────────────────────────────
habilitar() {   # habilitar UNIDAD  (solo si existe)
  local u="$1"
  if ! en_salida "^$u" systemctl list-unit-files "$u"; then nota "$u no existe, lo salto"; return 0; fi
  if systemctl is-enabled "$u" >/dev/null 2>&1; then ok "$u ya habilitado"; else root systemctl enable "$u" && ok "$u habilitado"; fi
}
fase_servicios() {
  quiere servicios || return 0
  (( SISTEMA )) || { fase "Servicios (omitido)"; return 0; }
  fase "Servicios"
  habilitar NetworkManager.service
  habilitar bluetooth.service
  habilitar fstrim.timer
  habilitar systemd-timesyncd.service
  if systemctl is-enabled display-manager.service >/dev/null 2>&1; then ok "ya hay un gestor de inicio de sesión habilitado"
  else habilitar sddm.service; fi
  local bus="${XDG_RUNTIME_DIR:-/run/user/$UID}/bus"
  if [[ -S $bus ]]; then
    systemctl --user daemon-reload 2>/dev/null || true
    local u; for u in pipewire.socket pipewire-pulse.socket wireplumber.service; do
      en_salida "^$u" systemctl --user list-unit-files "$u" && run systemctl --user enable "$u"
    done
    if command -v aria2c >/dev/null && [[ -f $HOME/.config/systemd/user/aria2.service ]]; then
      run systemctl --user enable --now aria2.service && ok "aria2 (descargas en paralelo) activo"
    fi
  else
    aviso "no hay sesión de usuario de systemd: los servicios de usuario (PipeWire, aria2) se activarán al iniciar sesión"
  fi
}

# ── tema GNOME oscuro (GTK, iconos, cursor, fuentes) ───────────────────────
fase_tema() {
  quiere tema || return 0
  fase "Tema"
  if ! command -v gsettings >/dev/null || [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}${XDG_RUNTIME_DIR:-}" ]]; then
    aviso "sin gsettings o sin sesión gráfica: el tema se aplicará leyendo gtk-3.0/gtk-4.0 settings.ini"; return 0
  fi
  local s=org.gnome.desktop.interface
  run gsettings set $s color-scheme prefer-dark
  run gsettings set $s gtk-theme adw-gtk3-dark
  run gsettings set $s icon-theme Adwaita
  run gsettings set $s cursor-theme Bibata-Modern-Ice
  run gsettings set $s font-name 'Adwaita Sans 11'
  run gsettings set $s monospace-font-name 'JetBrainsMono Nerd Font 11'
  run gsettings set org.gnome.desktop.wm.preferences button-layout 'appmenu:close'
  ok "tema oscuro estilo GNOME aplicado (gsettings)"
}

# ── ajustes de sistema y rendimiento (/etc), cada uno solo si aplica ────────
instalar_etc() {   # instalar_etc RUTA_RELATIVA_EN_system  → copia solo si cambió
  local rel="$1" from="$SRC/system/$1" to="/$1"
  if [[ -f $to ]] && cmp -s "$from" "$to"; then nota "ya al día: $to"; return 1; fi
  root install -Dm 644 "$from" "$to" && ok "instalado: $to"
}
fase_sistema() {
  quiere sistema || return 0
  (( SISTEMA )) || { fase "Sistema (omitido)"; return 0; }
  (( RENDIMIENTO )) || { fase "Rendimiento (omitido)"; return 0; }
  fase "Ajustes de rendimiento y red"
  local recargar=0
  # Red: BBR + fq (necesita el módulo tcp_bbr)
  if modinfo tcp_bbr >/dev/null 2>&1; then
    instalar_etc etc/sysctl.d/99-rendimiento.conf && { root modprobe tcp_bbr || true; root sysctl --system; }
  else aviso "tu kernel no trae tcp_bbr: salto el ajuste de red"; fi
  # Wifi sin ahorro de energía (solo si hay wifi)
  if compgen -G "/sys/class/net/wl*" >/dev/null; then instalar_etc etc/NetworkManager/conf.d/99-wifi-rendimiento.conf || true
  else nota "sin tarjeta wifi: salto el ajuste de wifi"; fi
  # MediaTek MT7925: ASPM desactivado (evita caídas)
  if en_salida 'MT7925' lspci; then instalar_etc etc/modprobe.d/mt7925e.conf || true; fi
  # CPU y GPU en máximo rendimiento al arrancar (solo si hay cpufreq)
  if compgen -G "/sys/devices/system/cpu/cpu0/cpufreq" >/dev/null; then
    instalar_etc etc/systemd/system/max-performance.service && recargar=1
  else nota "sin cpufreq: salto max-performance"; fi
  # Planificador sched_ext
  if [[ -x /usr/bin/scx_lavd && -d /sys/kernel/sched_ext ]]; then
    instalar_etc etc/systemd/system/scx-sched.service && recargar=1
  else nota "scx_lavd o sched_ext no disponibles: salto scx-sched"; fi
  if (( recargar )); then
    root systemctl daemon-reload
    [[ -f /etc/systemd/system/max-performance.service ]] && root systemctl enable --now max-performance.service
    [[ -f /etc/systemd/system/scx-sched.service ]] && root systemctl enable --now scx-sched.service
  fi
  nota "para deshacer: sudo systemctl disable --now max-performance scx-sched; borra /etc/sysctl.d/99-rendimiento.conf"
}

# ── verificación final ─────────────────────────────────────────────────────
fase_verificar() {
  quiere verificar || return 0
  fase "Verificación"
  local c missing=()
  for c in hyprland hyprlock hypridle waybar rofi kitty mako swaybg quickshell awww zenity magick grim slurp wl-copy wl-paste cliphist notify-send nmcli bluetoothctl starship fastfetch zsh pavucontrol; do
    command -v "$c" >/dev/null || missing+=("$c")
  done
  (( ${#missing[@]} == 0 )) && ok "todos los programas de la sesión están instalados" || aviso "faltan programas: ${missing[*]}"
  local bad=0 f
  while IFS= read -r -d '' f; do
    local dst="$HOME/.config/${f#"$SRC"/config/}"
    [[ -e $dst ]] || { fallo "falta $dst"; bad=1; }
  done < <(find "$SRC/config" -type f -print0)
  (( bad == 0 )) && ok "todas las configuraciones están en ~/.config"
  en_salida 'JetBrainsMono Nerd' fc-list : family && ok "fuente JetBrainsMono Nerd Font" || aviso "falta JetBrainsMono Nerd Font"
  en_salida '^Inter' fc-list : family && ok "fuente Inter" || aviso "falta la fuente Inter"
  en_salida 'DM Serif Display' fc-list : family && ok "fuente DM Serif Display (hyprlock)" || aviso "falta DM Serif Display: ./install.sh --reparar"
  [[ -f $HOME/.config/hypr/equipo.lua ]] && ok "equipo.lua con las pantallas de este PC" || aviso "falta ~/.config/hypr/equipo.lua: ./install.sh --reparar"
  [[ -x $HOME/.local/bin/fondo ]] && bash -n "$HOME/.local/bin/fondo" && ok "selector de fondos (Ctrl+Alt+W)" || aviso "falta ~/.local/bin/fondo"
  zsh -n "$SRC/.zshrc" 2>/dev/null && ok ".zshrc sin errores de sintaxis" || fallo ".zshrc tiene errores de sintaxis"
  if command -v Hyprland >/dev/null && en_salida -- '--verify-config' Hyprland --help; then
    if Hyprland --verify-config -c "$SRC/config/hypr/hyprland.lua" >/dev/null 2>&1; then ok "Hyprland acepta hyprland.lua"
    else aviso "Hyprland --verify-config no validó hyprland.lua (puede ser normal fuera de una sesión)"; fi
  fi
  if command -v rofi >/dev/null; then
    rofi -config "$SRC/config/rofi/config.rasi" -dump-config >/dev/null 2>&1 && ok "rofi lee su configuración" || aviso "rofi no pudo leer config.rasi"
  fi
  local rotos; rotos="$(enlaces_rotos | wc -l)"
  if (( rotos == 0 )); then ok "sin enlaces rotos"; else aviso "$rotos enlaces rotos (apuntan a otra copia del repo): ./install.sh --reparar"; fi
  if [[ -d $HOME/.local/bin ]]; then ok "scripts en ~/.local/bin"; fi
}

# ── reparar: reapunta los enlaces rotos a este repo y recrea lo que falte ───
reparar() {
  fase "Reparación de enlaces"
  local l d n=0
  while IFS= read -r l; do
    d="$(destino_en_repo "$(readlink "$l")")" || continue
    run ln -sfn "$d" "$l"; apuntar "$l"; n=$((n+1))
  done < <(enlaces_rotos)
  if (( n )); then ok "enlaces reapuntados a $SRC: $n"; else ok "no había enlaces rotos de estos dotfiles"; fi
  run mkdir -p "$HOME/.local/state" "$HOME/.local/bin" "$HOME/.local/share/applications"
  fase_enlaces   # recrea lo que falte (scripts, lanzadores, avatar…); lo que ya está bien no se toca
  fase_equipo    # pantallas, fuentes y audio de este PC (no sobrescribe un equipo.lua que ya exista)
  fase_zen       # user.js de Zen, si está instalado
  if ! (( SIMULAR )); then
    if [[ -x $HOME/.local/bin/fondo ]]; then
      if "$HOME/.local/bin/fondo" restaurar >>"$LOG" 2>&1; then ok "fondo de pantalla y del bloqueo restaurados"
      else nota "fondo: no hay sesión gráfica ahora, se restaurará al entrar en Hyprland"; fi
    fi
    if [[ -f $APLICADO ]]; then   # el repo está ahora aquí: se actualiza dónde y con qué contenido
      printf '%s\n%s\n%s\n%s\n' "$SRC" "$(huella)" "$(sed -n 3p "$APLICADO")" "$(sed -n 4p "$APLICADO")" >"$APLICADO"
    fi
  fi
}

# ── menú interactivo: ./install.sh sin nada, en una terminal ───────────────
M_NOMBRES=(instalar reparar deshacer salir)
M_TECLAS=(1 2 3 q)
M_TITULOS=(Instalar Reparar Deshacer Salir)
M_TEXTOS=("todo: paquetes, configuración, servicios y tema"
          "arregla enlaces rotos y ajustes de este equipo"
          "vuelve a como estaba antes de instalar"
          "no hacer nada")
M_ANCHO=54; M_LINEAS=0; M_N=0; M_ESTADO=""; M_RECOMENDADA=-1; M_ELEGIDA=-1
M_H=""; for ((m_i = 0; m_i < M_ANCHO; m_i++)); do M_H+="─"; done

mp() { printf '%s\n' "$*"; M_N=$((M_N + 1)); }   # imprime una línea del menú y la cuenta (para redibujar encima)
caja_fila() {   # solo texto ASCII dentro de la caja: así el borde derecho siempre cuadra
  local t="$1" col="${2:-}" pad=$((M_ANCHO - ${#1}))
  if (( pad < 0 )); then pad=0; fi
  mp "  ${c_mag}│${c_off}${col}${t}$(printf '%*s' "$pad" '')${c_off}${c_mag}│${c_off}"
}

estado_menu() {   # M_ESTADO: cómo está este equipo · M_RECOMENDADA: qué conviene hacer (0 instalar, 1 reparar, -1 nada)
  local rotos
  M_RECOMENDADA=-1
  if [[ ! -f $APLICADO ]]; then
    M_ESTADO="${c_dim}○ sin instalar todavía${c_off}"; M_RECOMENDADA=0
  elif ya_aplicado; then
    M_ESTADO="${c_ok}✔ aplicado el $(sed -n 3p "$APLICADO" | cut -c1-16) · todo en su sitio${c_off}"
  else
    rotos="$(enlaces_rotos | wc -l)"
    if (( rotos > 0 )); then
      M_ESTADO="${c_warn}⚠ $rotos enlaces rotos (¿moviste el repositorio?)${c_off}"; M_RECOMENDADA=1
    elif ! enlaces_ok; then
      M_ESTADO="${c_warn}⚠ faltan configuraciones por enlazar${c_off}"; M_RECOMENDADA=1
    else
      M_ESTADO="${c_warn}⚠ el repositorio cambió desde la última instalación${c_off}"; M_RECOMENDADA=0
    fi
  fi
}

menu_dibujar() {   # menu_dibujar SELECCIÓN LO_ESCRITO MENSAJE · se redibuja sobre el dibujo anterior
  local sel="$1" buf="$2" msg="$3" i rec
  if (( M_LINEAS > 0 )); then printf '\e[%dA\e[J' "$M_LINEAS"; fi
  M_N=0
  mp ""
  mp "  ${c_mag}╭${M_H}╮${c_off}"
  caja_fila "   d o t f i l e s   -   i n s t a l a d o r" "$c_bold"
  caja_fila "   CachyOS / Arch + Hyprland" "$c_dim"
  mp "  ${c_mag}╰${M_H}╯${c_off}"
  mp ""
  mp "  Estado   ${M_ESTADO}"
  mp ""
  for i in 0 1 2 3; do
    rec=" "
    if (( i == M_RECOMENDADA )); then rec="${c_ok}★${c_off}"; fi
    if (( i == sel )); then
      mp "  ${c_sel} ❯ ${M_TECLAS[i]} ${c_off} ${c_bold}$(printf '%-9s' "${M_TITULOS[i]}")${c_off}${rec}  ${M_TEXTOS[i]}"
    else
      mp "     ${c_dim}${M_TECLAS[i]}${c_off}  $(printf '%-9s' "${M_TITULOS[i]}")${rec}  ${c_dim}${M_TEXTOS[i]}${c_off}"
    fi
  done
  mp ""
  mp "  ${c_dim}↑ ↓ mover   Enter elegir   1 2 3 directo   q salir${c_off}"
  mp "  ${c_dim}o escribe:${c_off} ${c_bold}instalar${c_off}${c_dim} · ${c_off}${c_bold}reparar${c_off}${c_dim} · ${c_off}${c_bold}deshacer${c_off}"
  mp "  ${c_mag}›${c_off} ${buf}${c_dim}▏${c_off}${msg}"
  M_LINEAS=$M_N
}

coincidencia() {   # índice de la orden que empieza por lo escrito (i → instalar, rep → reparar…), o -1
  local b="${1#--}" i
  b="${b,,}"
  if [[ -n $b ]]; then
    for i in 0 1 2 3; do
      if [[ ${M_NOMBRES[i]} == "$b"* ]]; then echo "$i"; return 0; fi
    done
  fi
  echo -1
}

menu_confirmar() {   # menu_confirmar ÍNDICE · enseña qué va a pasar y pide confirmación; 0 = seguir
  local i="$1" k l lineas=0 def=s
  local -a txt=()
  case "$i" in
    0) if es_arch; then
         txt=("Instalar va a:" "  • actualizar el sistema e instalar paquetes (pide sudo)"
              "  • enlazar tus configuraciones desde este repositorio"
              "  • activar servicios, tema y ajustes de rendimiento")
       else
         txt=("Instalar va a enlazar tus configuraciones." "  Esta distro no es Arch: no instala paquetes ni toca /etc.")
       fi
       txt+=("Antes guarda una copia de lo que ya tengas.") ;;
    1) txt=("Reparar va a:" "  • reapuntar los enlaces rotos a este repositorio"
            "  • rehacer pantallas, fuentes y fondo de este equipo" "No instala nada ni pide sudo.") ;;
    *) txt=("Deshacer va a:" "  • quitar todo lo que puso el instalador"
            "  • devolver tus configuraciones a como estaban antes"); def=n ;;
  esac
  printf '\n'; lineas=1
  for l in "${txt[@]}"; do printf '  %s%s%s\n' "$c_bold" "$l" "$c_off"; lineas=$((lineas + 1)); done
  if [[ $def == s ]]; then printf '  ¿Continuar? [S/n] '; else printf '  %s¿Seguro?%s [s/N] ' "$c_warn" "$c_off"; fi
  lineas=$((lineas + 1))
  IFS= read -rsn1 k || k=n
  if [[ $k == $'\e' ]]; then read -rsn2 -t 0.05 _ || true; fi   # una flecha manda 3 bytes: se descartan los otros 2
  printf '\n'
  if [[ $k == [sSyY] ]] || { [[ -z $k ]] && [[ $def == s ]]; }; then return 0; fi
  printf '\e[%dA\e[J' "$lineas"   # no: borra la pregunta y vuelve al menú
  return 1
}

menu_simple() {   # terminal estrecha o sin soporte de pantalla: pregunta en una línea
  local r i
  M_ELEGIDA=-1
  echo; echo "  dotfiles - instalador"; echo
  echo "    1) instalar   2) reparar   3) deshacer   q) salir"
  read -r -p "  ¿Qué hago? " r || r=q
  r="${r,,}"; r="${r#--}"
  case "$r" in 1) r=instalar ;; 2) r=reparar ;; 3) r=deshacer ;; q|"") r=salir ;; esac
  for i in 0 1 2 3; do
    if [[ ${M_NOMBRES[i]} == "$r"* ]]; then M_ELEGIDA=$i; break; fi
  done
  if (( M_ELEGIDA < 0 )); then echo "  no entiendo «$r»"; M_ELEGIDA=3; fi
  if (( M_ELEGIDA < 3 )); then
    read -r -p "  ¿Seguro? [s/N] " r || r=n
    if [[ ${r,,} != s* ]]; then M_ELEGIDA=3; fi
  fi
}

menu() {   # deja en M_ELEGIDA el índice elegido (3 = salir)
  local cols rows sel k rest m buf="" msg="" eleccion=-1
  cols="$(tput cols 2>/dev/null || echo 80)"; rows="$(tput lines 2>/dev/null || echo 24)"
  # el menú (16 líneas) más la confirmación (7) tiene que caber en pantalla para poder redibujarse encima
  if (( cols < 70 || rows < 25 )) || [[ ${TERM:-dumb} == dumb ]]; then menu_simple; return 0; fi
  estado_menu
  sel=$(( M_RECOMENDADA >= 0 ? M_RECOMENDADA : 0 ))
  M_LINEAS=0
  printf '\e[?25l'                                   # oculta el cursor mientras se elige
  trap 'printf "\e[?25h\n"; exit 130' INT TERM
  while :; do
    menu_dibujar "$sel" "$buf" "$msg"; msg=""
    IFS= read -rsn1 k || { eleccion=3; break; }      # sin entrada (Ctrl-D): salir
    case "$k" in
      $'\e')
        rest=""; read -rsn2 -t 0.05 rest || true
        case "$rest" in
          '[A'|'OA') sel=$(( (sel + 3) % 4 )) ;;   # flecha arriba (normal o modo aplicación)
          '[B'|'OB') sel=$(( (sel + 1) % 4 )) ;;   # flecha abajo
          '')   if [[ -n $buf ]]; then buf=""; else eleccion=3; fi ;;   # Esc: borra lo escrito, o sale
        esac ;;
      '')       # Enter: lo escrito, o la opción marcada
        if [[ -n $buf ]]; then
          m="$(coincidencia "$buf")"
          if (( m >= 0 )); then eleccion=$m; else msg="  ${c_warn}no entiendo «${buf}»${c_off}"; buf=""; fi
        else
          eleccion=$sel
        fi ;;
      $'\x7f'|$'\b') buf="${buf%?}" ;;
      [123])    if [[ -z $buf ]]; then eleccion=$((k - 1)); fi ;;
      [qQjJkK])
        if [[ -z $buf ]]; then
          case "$k" in
            [qQ]) eleccion=3 ;;
            [jJ]) sel=$(( (sel + 1) % 4 )) ;;
            *)    sel=$(( (sel + 3) % 4 )) ;;
          esac
        else buf+="${k,,}"; fi ;;
      [A-Za-z-]) buf+="${k,,}" ;;
    esac
    if [[ -n $buf ]]; then                           # mientras escribe, marca la orden que coincide
      m="$(coincidencia "$buf")"
      if (( m >= 0 )); then sel=$m; fi
    fi
    if (( eleccion == 3 )); then break; fi
    if (( eleccion >= 0 )); then
      if menu_confirmar "$eleccion"; then break; fi
      eleccion=-1; buf=""                            # dijo que no: vuelve al menú con lo escrito borrado
    fi
  done
  printf '\e[?25h'; trap - INT TERM
  M_ELEGIDA=$eleccion
}

aplicar_orden() {   # ajusta lo que hace el script según la orden
  case "$1" in
    instalar) ;;   # instalación completa (los valores por defecto de arriba)
    reparar)  REPARAR=1; ACTUALIZAR=0; PAQUETES=0; AUR=0; SISTEMA=0; RENDIMIENTO=0 ;;
    deshacer) DESHACER=1 ;;
  esac
}
elegir_orden() {   # la orden escrita (--instalar o instalar…), o el menú si no se escribió ninguna
  local a="${1:-}"
  case "${a#--}" in
    instalar|reparar|deshacer) aplicar_orden "${a#--}" ;;
    -h|help|ayuda) uso 0 ;;
    "")
      if [[ -t 0 && -t 1 ]]; then
        menu
        if (( M_ELEGIDA < 0 || M_ELEGIDA > 2 )); then echo; echo "  No he tocado nada."; exit 0; fi
        echo
        aplicar_orden "${M_NOMBRES[M_ELEGIDA]}"
      else
        uso 0   # sin terminal no hay a quién preguntar: solo ayuda, nunca instalar por sorpresa
      fi ;;
    *) echo "orden desconocida: $a"; echo; uso 2 ;;
  esac
}

# ── pantallas de ejecución ─────────────────────────────────────────────────
cabecera_ejecucion() {
  local que="instalando"
  if (( REPARAR )); then que="reparando"; fi
  printf '== dotfiles · %s ==\n' "$que" >>"$LOG"
  printf '\n  %s▌ dotfiles%s · %s\n' "$c_mag" "$c_off" "$que"
}
resumen_final() {
  local col="$c_ok" titulo="Todo listo"
  if (( FALLOS > 0 )); then col="$c_bad"; titulo="Terminó con fallos: revisa los FALLO de arriba"
  elif (( AVISOS > 0 )); then col="$c_warn"; titulo="Listo, con algunos avisos"; fi
  printf '== Resumen: %s correctos · %s avisos · %s fallos ==\n' "$OKN" "$AVISOS" "$FALLOS" >>"$LOG"
  printf '\n  %s▌ %s%s\n' "$col" "$titulo" "$c_off"
  printf '  %s▌%s %s correctos · %s avisos · %s fallos\n' "$col" "$c_off" "$OKN" "$AVISOS" "$FALLOS"
  printf '  %s▌%s %sRegistro: %s%s\n' "$col" "$c_off" "$c_dim" "$LOG" "$c_off"
  if (( FALLOS == 0 )); then printf '\n  Cierra sesión y vuelve a entrar para aplicar tema, shell y servicios.\n'; fi
}

# ── principal ──────────────────────────────────────────────────────────────
elegir_orden "${1:-}"   # la orden escrita, o el menú si no se escribió ninguna
trap 'fallo "error inesperado en la línea $LINENO (mira $LOG)"' ERR
(( DESHACER )) && deshacer
comprobar_aplicado   # si ya está todo aplicado, lo dice y termina sin tocar nada
cabecera_ejecucion
preflight
if (( REPARAR )); then
  reparar
else
  fase_paquetes
  fase_copia
  fase_enlaces
  fase_equipo
  fase_zen
  fase_shell
  fase_servicios
  fase_tema
  fase_sistema
fi
fase_verificar
resumen_final
if (( FALLOS == 0 && PENDIENTE == 0 )) && ! (( REPARAR )); then marcar_aplicado; fi
exit $(( FALLOS > 0 ))
