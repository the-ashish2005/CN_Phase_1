#!/bin/bash
# =============================================================================
#  preflight.sh — Team ADMV pre-demo health check (Phase 1)
#  Run on a CLIENT Mac (Mac 1 or Mac 4):   bash scripts/preflight.sh
#  Checks every layer in order: LAN -> DNS -> TCP -> TLS -> HTTP -> LB -> cache
# =============================================================================

# ---- Team settings (edit here if an IP changes) -----------------------------
DOMAIN="app.admv.test"
DNS1="10.7.21.200"        # Mac 1 - dnsmasq
EDGE="10.7.23.71"         # Mac 2 - nginx
BACKEND_A="10.7.18.160"   # Mac 3 - Backend A (port 3001)
BACKEND_B="10.7.2.129"    # Mac 4 - Backend B (port 3002)
HTTPS_PORT=443            # change to 8443 if nginx uses 8443
CURL_EXTRA=""             # e.g. "--cacert config/ca.crt" if curl doesn't use the keychain
# -----------------------------------------------------------------------------

GREEN=$'\033[32m'; RED=$'\033[31m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
PASS=0; FAIL=0
ok()   { echo "  ${GREEN}✔${RESET} $1"; PASS=$((PASS+1)); }
bad()  { echo "  ${RED}✘${RESET} $1"; FAIL=$((FAIL+1)); }
head() { echo; echo "${BOLD}$1${RESET}"; }

URL="https://${DOMAIN}"
[ "$HTTPS_PORT" != "443" ] && URL="https://${DOMAIN}:${HTTPS_PORT}"

# 1. LAN reachability -----------------------------------------------------------
head "1. LAN reachability (ping)"
for pair in "Mac1-DNS:$DNS1" "Mac2-Edge:$EDGE" "Mac3-BackendA:$BACKEND_A" "Mac4-BackendB:$BACKEND_B"; do
  name=${pair%%:*}; ip=${pair##*:}
  if ping -c 1 -t 2 "$ip" >/dev/null 2>&1; then ok "$name ($ip) reachable"
  else bad "$name ($ip) NOT reachable - check Wi-Fi / stealth mode"; fi
done

# 2. DNS ------------------------------------------------------------------------
head "2. DNS resolution"
ANS=$(dig +short +time=2 +tries=1 @"$DNS1" "$DOMAIN" | tail -1)
if [ "$ANS" = "$EDGE" ]; then ok "Mac 1 answers $DOMAIN -> $ANS"
else bad "Mac 1 answered '${ANS:-nothing}' (expected $EDGE) - is dnsmasq running?"; fi

SYS=$(dig +short +time=2 +tries=1 "$DOMAIN" | tail -1)
if [ "$SYS" = "$EDGE" ]; then ok "This Mac's resolver gives $DOMAIN -> $SYS"
else bad "This Mac's resolver gave '${SYS:-nothing}' - set DNS to $DNS1"; fi

SERVERS=$(networksetup -getdnsservers Wi-Fi 2>/dev/null | tr '\n' ' ')
echo "     configured DNS servers: ${SERVERS}"

# 3. TCP ------------------------------------------------------------------------
head "3. TCP connectivity"
if nc -z -G 2 "$EDGE" "$HTTPS_PORT" >/dev/null 2>&1; then ok "Edge port $HTTPS_PORT open"
else bad "Edge port $HTTPS_PORT closed - is nginx running on Mac 2?"; fi

# 4. TLS ------------------------------------------------------------------------
head "4. TLS certificate"
if curl -s -o /dev/null $CURL_EXTRA "$URL/" 2>/dev/null; then ok "Certificate valid and trusted (no -k used)"
else
  ERR=$(curl -sS -o /dev/null $CURL_EXTRA "$URL/" 2>&1 | head -1)
  bad "TLS/HTTPS failed: $ERR"
fi

# 5. HTTP + load balancing ------------------------------------------------------
head "5. HTTPS + load balancing (6 requests)"
SEEN=""
for i in 1 2 3 4 5 6; do
  HDRS=$(curl -s -D - -o /dev/null $CURL_EXTRA "$URL/api/status" 2>/dev/null | tr -d '\r')
  CODE=$(echo "$HDRS" | head -1 | awk '{print $2}')
  BE=$(echo "$HDRS" | grep -i '^x-backend:' | awk '{print $2}')
  echo "     request $i -> HTTP ${CODE:-???}  backend ${BE:-?}"
  SEEN="$SEEN$BE"
done
case "$SEEN" in *A*) ok "Backend A served requests";; *) bad "Backend A never answered - check Mac 3";; esac
case "$SEEN" in *B*) ok "Backend B served requests";; *) bad "Backend B never answered - check Mac 4";; esac

# 6. Caching --------------------------------------------------------------------
head "6. HTTP caching (/api/info)"
INFO=$(curl -sI $CURL_EXTRA "$URL/api/info" 2>/dev/null | tr -d '\r')
CC=$(echo "$INFO" | grep -i '^cache-control:' | cut -d' ' -f2-)
ETAG=$(echo "$INFO" | grep -i '^etag:' | cut -d' ' -f2)
[ -n "$CC" ]   && ok "Cache-Control: $CC" || bad "No Cache-Control header"
if [ -n "$ETAG" ]; then
  ok "ETag: $ETAG"
  C304=$(curl -s -o /dev/null -w "%{http_code}" -H "If-None-Match: $ETAG" $CURL_EXTRA "$URL/api/info")
  [ "$C304" = "304" ] && ok "Conditional request returns 304 Not Modified" || bad "Conditional request returned $C304 (expected 304)"
else
  bad "No ETag header"
fi

# Summary -----------------------------------------------------------------------
echo
if [ "$FAIL" -eq 0 ]; then
  echo "${GREEN}${BOLD}ALL $PASS CHECKS PASSED - ready for the demo.${RESET}"
else
  echo "${RED}${BOLD}$FAIL check(s) failed, $PASS passed. Fix the first failure first - it is the lowest broken layer.${RESET}"
fi
exit "$FAIL"
