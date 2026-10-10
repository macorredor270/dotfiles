#!/bin/sh
# GPU real vía nvidia-smi: uso, temperatura y VRAM para la waybar
read -r util temp used total <<EOT
$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | tr -d ',')
EOT
if [ -z "$util" ]; then
  printf '{"text":"n/a","tooltip":"nvidia-smi no responde","class":"critical"}\n'
  exit 0
fi
class=""
[ "$temp" -ge 80 ] && class="critical"
printf '{"text":"%s%%","tooltip":"GPU %s%% · %s°C · VRAM %s/%s MiB","class":"%s"}\n' "$util" "$util" "$temp" "$used" "$total" "$class"
