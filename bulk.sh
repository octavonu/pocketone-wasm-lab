#!/usr/bin/env bash
# Creates N posts at once (default 1000) through the API; each gets its summary from the module before it's saved
# (pb_hooks). Prints how long that took. The lab must be running (./start.sh).
set -euo pipefail
N="${1:-1000}"
U=http://127.0.0.1:8090
T=$(curl -sf -X POST "$U/api/collections/_superusers/auth-with-password" -H 'Content-Type: application/json' \
  -d '{"identity":"admin@example.com","password":"password"}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
start=$(python3 -c 'import time;print(time.time())')
seq 1 "$N" | xargs -P 16 -I{} curl -s -o /dev/null -X POST "$U/api/collections/posts/records" \
  -H "Authorization: $T" -H 'Content-Type: application/json' \
  -d '{"title":"bulk {}","body":"post number {} of a bulk run, with a few more words to summarize"}'
python3 -c "import time;print('$N posts, each summarized before saving, in %.1fs' % (time.time()-$start))"
curl -sf -G "$U/api/collections/posts/records" -H "Authorization: $T" --data-urlencode "filter=title~'bulk ' && summary~'(no summary'" \
  --data-urlencode perPage=1 | python3 -c 'import sys,json;print("without a summary:", json.load(sys.stdin)["totalItems"])'
