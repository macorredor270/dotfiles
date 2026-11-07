#!/bin/sh
# Medidor de red para la waybar: bajada en vivo con unidades claras.
# Bucle continuo: mide cada segundo usando el tiempo real transcurrido.

fmt() { # bytes/s -> "0 B/s", "812 B/s", "4.2 KB/s", "38 KB/s", "1.2 MB/s", "24 MB/s"
  awk -v b="$1" 'BEGIN{
    split("B KB MB GB", u, " "); i = 1;
    while (b >= 1000 && i < 4) { b /= 1024; i++ }
    if (i == 1)       printf "%d %s/s", b, u[i];
    else if (b < 10)  printf "%.1f %s/s", b, u[i];
    else              printf "%d %s/s", b, u[i];
  }'
}

iface() { ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<NF;i++) if($i=="dev"){print $(i+1); exit}}'; }

prev_if=""
while :; do
  ifc=$(iface)
  if [ -z "$ifc" ] || [ ! -r "/sys/class/net/$ifc/statistics/rx_bytes" ]; then
    printf '{"text":"sin red","tooltip":"Sin conexión","class":"disconnected"}\n'
    prev_if=""; sleep 2; continue
  fi

  rx=$(cat "/sys/class/net/$ifc/statistics/rx_bytes")
  tx=$(cat "/sys/class/net/$ifc/statistics/tx_bytes")
  now=$(date +%s%N)

  if [ "$ifc" != "$prev_if" ]; then   # primera vuelta o cambio de interfaz: tomar referencia
    prev_if=$ifc; prev_rx=$rx; prev_tx=$tx; prev_t=$now
    sleep 1; continue
  fi

  dt=$(( now - prev_t )); [ "$dt" -le 0 ] && dt=1
  down=$(( (rx - prev_rx) * 1000000000 / dt ))
  up=$(( (tx - prev_tx) * 1000000000 / dt ))
  [ "$down" -lt 0 ] && down=0; [ "$up" -lt 0 ] && up=0

  ip4=$(ip -4 -o addr show "$ifc" 2>/dev/null | awk '{print $4; exit}')
  sig=""
  if [ -d "/sys/class/net/$ifc/wireless" ] && command -v iw >/dev/null; then
    # este driver no rellena /proc/net/wireless: se lee de iw
    sig=$(iw dev "$ifc" link 2>/dev/null | awk '
      /SSID:/        { sub(/^[ \t]*SSID: /, ""); ssid = $0 }
      /signal:/      { dbm = $2 }
      /tx bitrate:/  { rate = $3 }
      END {
        if (dbm == "") exit;
        p = 2 * (dbm + 100); if (p > 100) p = 100; if (p < 0) p = 0;
        printf "\\n%s  ·  %d dBm (%d%%)  ·  %d Mbit/s", ssid, dbm, p, rate
      }')
  fi

  class="idle"
  [ "$down" -ge 102400 ] && class="active"      # >100 KB/s
  [ "$down" -ge 10485760 ] && class="busy"      # >10 MB/s

  printf '{"text":"%s","tooltip":"%s  ·  %s%s\\n↓ %s    ↑ %s","class":"%s"}\n' \
    "$(fmt $down)" "$ifc" "$ip4" "$sig" "$(fmt $down)" "$(fmt $up)" "$class"

  prev_rx=$rx; prev_tx=$tx; prev_t=$now
  sleep 1
done
