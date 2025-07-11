#!/usr/bin/env bash
set -euo pipefail

DOMAIN="$1"
DATE=$(date +%Y%m%d)
OUTDIR="recon-${DOMAIN}-${DATE}"
mkdir -p "$OUTDIR"

notify_send() {
  printf '%s\n' "$1" | notify -provider discord 2>/dev/null || true
}

notify_send ":satellite: **Recon started:** \`$DOMAIN\` (`date '+%H:%M:%S %Z'`)"
echo "[*] Running subfinder and httpx..."
subfinder -d "$DOMAIN" | httpx -o "$OUTDIR/alive.txt"

LIVE=$(wc -l < "$OUTDIR/alive.txt")
notify_send ":green_circle: Found \`$LIVE\` live targets. Boleh minum kopi dulu sambil tunggu result scanning"

if [ "$LIVE" -eq 0 ]; then
  echo "[!] No live hosts found."
  notify_send ":warning: No live HTTP/S hosts — skipping nuclei scan"
  exit 0
fi

# === Start Notify Session ===
#session="nuclei-notify"
#echo "[*] Starting tmux notify session: $session"

#tmux new-session -d -s "$session" -n notify \
#  "sleep 30 && tail -n 0 -f '$OUTDIR'/nuclei-*.txt | stdbuf -o0 sed '/^==> .* <==$/d' | notify -pc ~/.config/notify/provider-config.yaml"

if [ -n "${TMUX:-}" ]; then
  CURRENT_SESSION=$(tmux display-message -p '#S')
  echo "[*] Detected tmux session: $CURRENT_SESSION"
  
  touch "$OUTDIR/nuclei-low.txt"
  touch "$OUTDIR/nuclei-medium.txt"
  touch "$OUTDIR/nuclei-high.txt"
  touch "$OUTDIR/nuclei-critical.txt"
  touch "$OUTDIR/nuclei-exposure.txt"
  
  tmux split-window -v -t "$CURRENT_SESSION" \
    "sleep 50 && tail -n 1 -f '$OUTDIR'/nuclei-*.txt | stdbuf -o0 sed '/^==> .* <==$/d' | notify -pc ~/.config/notify/provider-config.yaml"
else
  echo "[!] Not inside a tmux session. Skipping live notify pane."
fi

SEVERITIES=(low medium high critical)

for SEV in "${SEVERITIES[@]}"; do
  echo "[*] Scanning $SEV severity..."
  notify_send ":mag: Scanning \`$DOMAIN\` — \`$SEV\` severity..."
  nuclei -l "$OUTDIR/alive.txt" -etags ssl -severity "$SEV" -t ~/nuclei-templates -o "$OUTDIR/nuclei-$SEV.txt" || true
done

nuclei -l "$OUTDIR/alive.txt" -etags ssl -tags exposure -t ~/nuclei-templates -o "$OUTDIR/nuclei-exposure.txt" || true
notify_send ":white_check_mark: Nuclei scan completed for \`$DOMAIN\`"

tmux send-keys -t "$session:0" C-c
tmux kill-session -t "$session"
