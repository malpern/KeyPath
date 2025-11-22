pid=$(pgrep -n kanata) || { echo "Kanata not running"; exit 1; }

  sudo touch /var/log/com.keypath.kanata.stderr.log && sudo chmod 640 /var/log/com.keypath.kanata.stderr.log

  echo "Initial FD count:" && sudo lsof -p "$pid" | wc -l

  echo "Running sequential burst (1000)..."
  for i in {1..1000}; do
    echo '{"RequestCurrentLayerName":{"request_id":"t"}}' | nc -w1 localhost 37001 >/dev/null
  done

  echo "Running concurrent burst (1000, 16 parallel)..."
  seq 1000 | xargs -I{} -P16 sh -c 'echo "{\"RequestCurrentLayerName\":{\"request_id\":\"t\"}}" | nc -w1 localhost 37001 >/dev/null'

  echo "Tailing last 40 kanata stderr lines:"
  sudo tail -n 40 /var/log/com.keypath.kanata.stderr.log

  echo "Post-burst FD summary:"
  sudo lsof -p "$pid" -a -iTCP

  echo "Total FDs:" && sudo lsof -p "$pid" | wc -l
