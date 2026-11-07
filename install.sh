#!/usr/bin/env bash
# install.sh — instalador inteligente de estos dotfiles (CachyOS / Arch + Hyprland).
#
#   ./install.sh                  hace todo: actualiza, instala paquetes, enlaza configs, servicios, tema y ajustes
#   ./install.sh --simular        muestra lo que haría sin cambiar nada (no pide sudo)
#   ./install.sh --solo FASE      solo una fase: paquetes | copia | enlaces | equipo | zen | shell | servicios | tema | sistema | verificar
#   ./install.sh --deshacer [COPIA.tar.gz]   quita todo lo instalado y deja tus configs como antes de la primera instalación
#
# Opciones:
#   --sin-actualizar   no hace pacman -Syu antes de instalar (cuidado: una base de datos vieja da errores 404)
#   --sin-paquetes     salta pacman y AUR           --sin-aur          salta solo el AUR
#   --sin-enlaces      no toca ~/.config            --sin-sistema      no escribe nada en /etc
#   --sin-rendimiento  no instala los ajustes de rendimiento (sysctl, governor, scx, wifi)
#   --opcionales       instala también packages/opcional.txt (Steam, Prism, Node, Rust…)
#
# Para replicar solo el aspecto en otra máquina (portátil u otra distro):
#   --visual           modo ligero: solo packages/visual.txt, sin -Syu, sin drivers ni ajustes de /etc
#   --solo-config      solo enlaza configuraciones y tema; no instala ningún paquete (válido en cualquier distro)
#
# Es idempotente: se puede repetir sin romper nada. Antes de tocar nada guarda una copia completa en
# ~/.dotfiles-backup-FECHA.tar.gz (y lo reemplazado, en ~/.dotfiles-backup-FECHA/). Registro: ~/.dotfiles-install.log
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

VISUAL=0; SIMULAR=0; ACTUALIZAR=1; PAQUETES=1; AUR=1; ENLACES=1; SISTEMA=1; RENDIMIENTO=1; OPCIONALES=0; SOLO=""
OKN=0; AVISOS=0; FALLOS=0; ENLAZADOS=0

# ── mensajes ───────────────────────────────────────────────────────────────
c_ok=$'\033[32m'; c_warn=$'\033[33m'; c_bad=$'\033[31m'; c_dim=$'\033[2m'; c_off=$'\033[0m'
say()   { printf '%s\n' "$*" | tee -a "$LOG" >/dev/null; printf '%s\n' "$*"; }
fase()  { say ""; say "== $* =="; }
ok()    { OKN=$((OKN+1));       printf '  %sOK%s     %s\n' "$c_ok" "$c_off" "$*"; printf '  OK     %s\n' "$*" >>"$LOG"; }
aviso() { AVISOS=$((AVISOS+1)); printf '  %sAVISO%s  %s\n' "$c_warn" "$c_off" "$*"; printf '  AVISO  %s\n' "$*" >>"$LOG"; }
fallo() { FALLOS=$((FALLOS+1)); printf '  %sFALLO%s  %s\n' "$c_bad" "$c_off" "$*"; printf '  FALLO  %s\n' "$*" >>"$LOG"; }
nota()  { printf '  %s%s%s\n' "$c_dim" "$*" "$c_off"; }

# Ejecuta un comando, o solo lo muestra en modo --simular.
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
uso() { sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
DESHACER=0; DESHACER_ARCHIVO=""
while (( $# )); do
  case "$1" in
    --simular) SIMULAR=1 ;;
    --sin-actualizar) ACTUALIZAR=0 ;;
    --sin-paquetes) PAQUETES=0 ;;
    --sin-aur) AUR=0 ;;
    --sin-enlaces) ENLACES=0 ;;
    --sin-sistema) SISTEMA=0 ;;
    --sin-rendimiento) RENDIMIENTO=0 ;;
    --opcionales) OPCIONALES=1 ;;
    --visual) VISUAL=1; ACTUALIZAR=0; SISTEMA=0; RENDIMIENTO=0 ;;
    --solo-config) VISUAL=1; ACTUALIZAR=0; PAQUETES=0; AUR=0; SISTEMA=0; RENDIMIENTO=0 ;;
    --solo) shift; SOLO="${1:-}" ;;
    --deshacer) DESHACER=1; if [[ ${2:-} == *.tar.gz ]]; then DESHACER_ARCHIVO="$2"; shift; fi ;;
    -h|--ayuda|--help) uso 0 ;;
    *) echo "opción desconocida: $1"; uso 2 ;;
  esac; shift
done
quiere() { [[ -z "$SOLO" || "$SOLO" == "$1" ]]; }   # ¿toca ejecutar esta fase?
# grep sobre la salida de un comando, sin tuberías: con pipefail, "cmd | grep -q" da falsos negativos por SIGPIPE
en_salida() { local pat="$1" out; shift; out="$("$@" 2>&1 || true)"; grep -qiE -- "$pat" <<<"$out"; }

# ── comprobaciones previas ─────────────────────────────────────────────────
preflight() {
  fase "Comprobaciones previas"
  if (( EUID == 0 )); then fallo "no lo ejecutes como root: lanza ./install.sh con tu usuario (usa sudo por dentro)"; exit 1; fi
  : >>"$LOG"
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
    nota "(sin -Syu: si pacman da 404, vuelve a ejecutarlo sin --sin-actualizar)"
  fi
  local -a lista=()
  mapfile -t lista < <( { leer_lista "$lista_pacman"; (( VISUAL )) || paquetes_hardware; (( OPCIONALES )) && leer_lista "$SRC/packages/opcional.txt"; true; } | sort -u )
  instalar_pacman "${lista[@]}"
  if (( ! VISUAL && GPU_NVIDIA )) && ! (( SIMULAR )); then
    local conf=/etc/modprobe.d/nvidia-dotfiles.conf
    if en_salida 'parm:.*modeset' modinfo nvidia_drm; then
      printf 'options nvidia_drm modeset=1 fbdev=1\n' | sudo tee "$conf" >/dev/null && ok "NVIDIA: modeset=1 y fbdev=1 escritos en $conf"
    else
      aviso "nvidia_drm aún no está disponible (se compila al reiniciar con DKMS): reinicia y repite --solo paquetes"
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
  run mkdir -p "$HOME/Pictures/wallpapers" "$HOME/Pictures/Screenshots" "$HOME/Descargas"
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
  [[ -n $tar ]] || tar="$(ls -tr "$HOME"/.dotfiles-backup-*.tar.gz 2>/dev/null | head -1)"
  [[ -n $tar && -f $tar ]] || { echo "no hay ninguna copia ~/.dotfiles-backup-*.tar.gz"; exit 1; }
  echo "Restaurando $tar"
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
  tar -C "$HOME" -xzf "$tar" || { echo "no pude extraer $tar"; exit 1; }
  # las copias usadas se apartan para que una próxima instalación empiece de cero
  mkdir -p "$HOME/.dotfiles-backups-usadas"
  mv "$HOME"/.dotfiles-backup-*.tar.gz "$HOME/.dotfiles-backups-usadas/" 2>/dev/null || true
  rm -f "$MANIFIESTO"; rmdir -p --ignore-fail-on-non-empty "$(dirname "$MANIFIESTO")" 2>/dev/null || true
  echo "Listo: configuraciones restauradas (copias apartadas en ~/.dotfiles-backups-usadas). Cierra sesión y vuelve a entrar."
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
    ok "pantallas: equipo.lua y equipo.conf ya existen (bórralos y repite --solo equipo para regenerarlos)"
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
      l_lua="-- Sin sesión de Hyprland no se pueden leer las pantallas: todas usan su modo preferido."$'\n'"-- Ejecuta ./install.sh --solo equipo desde Hyprland para fijar la mejor tasa de refresco."$'\n'
      l_conf="${l_lua//--/#}"
      aviso "no estoy dentro de Hyprland: pantallas en modo automático (repite --solo equipo ya dentro para afinarlas)"
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
    aviso "no encuentro un perfil de Zen: ábrelo una vez y ejecuta ./install.sh --solo zen"; return 0
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
  en_salida 'DM Serif Display' fc-list : family && ok "fuente DM Serif Display (hyprlock)" || aviso "falta DM Serif Display: ./install.sh --solo equipo"
  [[ -f $HOME/.config/hypr/equipo.lua ]] && ok "equipo.lua con las pantallas de este PC" || aviso "falta ~/.config/hypr/equipo.lua: ./install.sh --solo equipo"
  [[ -x $HOME/.local/bin/fondo ]] && bash -n "$HOME/.local/bin/fondo" && ok "selector de fondos (Ctrl+Alt+W)" || aviso "falta ~/.local/bin/fondo"
  zsh -n "$SRC/.zshrc" 2>/dev/null && ok ".zshrc sin errores de sintaxis" || fallo ".zshrc tiene errores de sintaxis"
  if command -v Hyprland >/dev/null && en_salida -- '--verify-config' Hyprland --help; then
    if Hyprland --verify-config -c "$SRC/config/hypr/hyprland.lua" >/dev/null 2>&1; then ok "Hyprland acepta hyprland.lua"
    else aviso "Hyprland --verify-config no validó hyprland.lua (puede ser normal fuera de una sesión)"; fi
  fi
  if command -v rofi >/dev/null; then
    rofi -config "$SRC/config/rofi/config.rasi" -dump-config >/dev/null 2>&1 && ok "rofi lee su configuración" || aviso "rofi no pudo leer config.rasi"
  fi
  [[ -d $HOME/.local/bin ]] && ok "scripts en ~/.local/bin"
}

# ── principal ──────────────────────────────────────────────────────────────
trap 'fallo "error inesperado en la línea $LINENO (mira $LOG)"' ERR
(( DESHACER )) && deshacer
preflight
fase_paquetes
fase_copia
fase_enlaces
fase_equipo
fase_zen
fase_shell
fase_servicios
fase_tema
fase_sistema
fase_verificar
say ""
say "== Resumen: $OKN correctos · $AVISOS avisos · $FALLOS fallos =="
(( SIMULAR )) && say "(simulación: no se ha cambiado nada)"
say "Registro: $LOG"
(( FALLOS == 0 )) && say "Listo. Cierra sesión y vuelve a entrar para aplicar tema, shell y servicios." || say "Revisa los FALLO de arriba y el registro."
exit $(( FALLOS > 0 ))
