#!/bin/sh
# Uso de GPU para la waybar: NVIDIA (nvidia-smi), AMD (sysfs) o "n/a" si no hay nada compatible.
json() { printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$1" "$2" "$3"; }

if command -v nvidia-smi >/dev/null 2>&1; then
  read -r util temp used total <<EOT
$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | tr -d ',')
EOT
  if [ -n "$util" ]; then
    class=""; [ "$temp" -ge 80 ] && class="critical"
    json "${util}%" "GPU ${util}% · ${temp}°C · VRAM ${used}/${total} MiB" "$class"
    exit 0
  fi
fi

# AMD: /sys/class/drm/card*/device/gpu_busy_percent
for d in /sys/class/drm/card*/device; do
  if [ -r "$d/gpu_busy_percent" ]; then
    util="$(cat "$d/gpu_busy_percent" 2>/dev/null)"
    json "${util}%" "GPU AMD ${util}%" ""
    exit 0
  fi
done

json "n/a" "Sin GPU compatible con este módulo (NVIDIA o AMD)" ""
