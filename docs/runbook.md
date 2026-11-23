# ZeroNetwork — Private Network Service Platform: Full Command Runbook

**Team:** ZeroNetwork  **Private domain:** `zeronetwork.test`  **Names:** `app.zeronetwork.test`, `api.zeronetwork.test`

## 0. Roles and IPs (use exactly these)

| Mac | IP | Phase 1 role | Extra Phase 2 role |
|---|---|---|---|
| **MAC-1** | `10.7.8.17` | Primary DNS (dnsmasq) + test client | — |
| **MAC-2** | `10.7.21.230` | Edge: nginx reverse proxy + load balancer + TLS (port 443) | — |
| **MAC-3** | `10.7.25.53` | Backend A (port 3001) | Backup DNS (Ext A) + standby edge nginx (Ext E) |
| **MAC-4** | `10.7.23.141` | Backend B (port 3002) + **main demo client / packet capture** | — |

Request flow: `MAC-4 (client) → DNS query to MAC-1 → HTTPS to MAC-2 (nginx :443) → MAC-3 :3001 (A) or MAC-4 :3002 (B)`

> **Why MAC-4 is the capture client:** if MAC-1 queries its own DNS server, the query travels over loopback and never shows up on the Wi-Fi capture. MAC-4 → MAC-1 crosses the LAN, so Wireshark sees it.

### Read before starting
1. **All four Macs must be on the same Wi-Fi (all IPs are `10.7.x.x`).** Step 1 checks this with ping. If a Mac shows 100% loss, check its IP (`ipconfig getifaddr en0`) and turn off macOS Stealth Mode on it (`sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode off`). If pings fail between *any* Macs even then, the Wi-Fi probably has client isolation, so use a phone hotspot or a home router and update the IPs.
2. **Don't disconnect Wi-Fi during the project.** A new DHCP lease can change the IPs.
3. **Paste commands one block at a time** into Terminal (zsh). Each block starts with **▶ RUN ON: MAC-X**. Keep to the order.
4. If macOS asks *"Do you want python3 / nginx / dnsmasq to accept incoming network connections?"*, click **Allow**.
5. `sudo` asks for that Mac's login password.

---

# PHASE 1 — Build & Observe

## Step 0 — Setup on every Mac (needs internet; do it BEFORE changing any DNS)

### 0.1 ▶ RUN ON: ALL 4 MACS — install Homebrew if missing
```bash
which brew || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```
On Apple Silicon, run this afterwards (it's safe on Intel too):
```bash
[ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"; brew --version
```

### 0.2 ▶ RUN ON: each Mac — record its identity (run ONLY that Mac's line)
```bash
mkdir -p ~/zeronetwork/{evidence,backend,tls,share}
```
- MAC-1: `echo 'export ZN_NAME="MAC-1" ZN_IP="10.7.8.17"' > ~/zeronetwork/me.sh`
- MAC-2: `echo 'export ZN_NAME="MAC-2" ZN_IP="10.7.21.230"' > ~/zeronetwork/me.sh`
- MAC-3: `echo 'export ZN_NAME="MAC-3" ZN_IP="10.7.25.53"' > ~/zeronetwork/me.sh`
- MAC-4: `echo 'export ZN_NAME="MAC-4" ZN_IP="10.7.23.141"' > ~/zeronetwork/me.sh`

### 0.3 ▶ RUN ON: ALL 4 MACS — shared environment (same block everywhere)
This gives every screenshot a labelled prompt like `[ZeroNetwork | MAC-4 | 10.7.23.141] 21:30:05 %` and adds helper commands.
```bash
cat > ~/zeronetwork/env.sh <<'EOF'
setopt interactivecomments
[ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
source "$HOME/zeronetwork/me.sh"
export MAC1=10.7.8.17 MAC2=10.7.21.230 MAC3=10.7.25.53 MAC4=10.7.23.141
export CA="$HOME/zeronetwork/ZeroNetworkCA.crt"
export IFACE=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
PROMPT="%F{cyan}[ZeroNetwork | $ZN_NAME | $ZN_IP]%f %F{yellow}%*%f %# "
snap(){ screencapture -iW "$HOME/zeronetwork/evidence/$1.png" && echo "Saved evidence/$1.png"; }
zn_flush(){ sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder; echo "Local DNS cache flushed on $ZN_NAME"; }
zn_dns_set(){ printf '%s  app.zeronetwork.test\n%s  api.zeronetwork.test\n' "$1" "$2" > "$(brew --prefix)/etc/dnsmasq.d/zeronetwork.hosts"; sudo pkill -HUP dnsmasq; echo "DNS records on $ZN_NAME are now:"; cat "$(brew --prefix)/etc/dnsmasq.d/zeronetwork.hosts"; }
zn_hit(){ curl -s --cacert "$CA" -o /dev/null -w "%{http_code}  backend=%header{x-backend}  edge=%header{x-edge}\n" "https://${1:-app}.zeronetwork.test/api/status"; }
zn_diag(){ H=${1:-app.zeronetwork.test}; echo "== 1. DNS (name -> IP)"; dig +short $H; echo "== 2. TCP (port 443 reachable?)"; nc -vz -G 3 $H 443; echo "== 3. TLS (cert valid?)"; openssl s_client -connect $H:443 -servername $H -CAfile "$CA" </dev/null 2>/dev/null | grep -E "subject=|issuer=|Verify return code"; echo "== 4. HTTP (app answers?)"; curl -s --cacert "$CA" -o /dev/null -w "HTTP %{http_code}  backend=%header{x-backend}  edge=%header{x-edge}\n" https://$H/api/status; }
echo "ZeroNetwork env loaded on $ZN_NAME ($ZN_IP), interface $IFACE"
EOF
source ~/zeronetwork/env.sh
```
> **Every new Terminal window/tab you open later needs `source ~/zeronetwork/env.sh` first.**
> `snap NAME` takes a screenshot: click the Terminal window and it's saved to `~/zeronetwork/evidence/NAME.png`. The first time, macOS asks for Screen Recording permission for Terminal; allow it and reopen Terminal. You can also use **⌘⇧4, then Space, then click the window**.
> `zn_hit` uses curl's `%header{}`, which needs curl 7.84+ (macOS 13 or later). If it prints `%header{...}` literally, use `curl -si --cacert "$CA" https://app.zeronetwork.test/api/status | grep -i x-` instead.

### 0.4 Install packages (one block per Mac)
▶ **RUN ON: MAC-1**
```bash
brew install dnsmasq
```
▶ **RUN ON: MAC-2**
```bash
brew install nginx
```
▶ **RUN ON: MAC-3** (dnsmasq and nginx are only needed in Phase 2, but install them now while the internet still works)
```bash
brew install dnsmasq nginx; python3 --version
```
▶ **RUN ON: MAC-4**
```bash
python3 --version
brew install wireshark
brew install --cask wireshark-app || brew install --cask wireshark
```
(If `python3 --version` asks to install Command Line Tools, accept and wait for it to finish.)

---

## Step 1 — Task A: Private LAN check

### 1.1 ▶ RUN ON: ALL 4 MACS — record IP, mask, gateway, interface, MAC address
```bash
{ echo "== $ZN_NAME"; echo "Interface: $IFACE"; echo "IPv4: $(ipconfig getifaddr $IFACE)"; echo "Subnet mask: $(ipconfig getoption $IFACE subnet_mask)"; echo "Gateway: $(route -n get default | awk '/gateway/{print $2}')"; echo "MAC address: $(ifconfig $IFACE | awk '/ether/{print $2}')"; echo "DHCP DNS: $(ipconfig getoption $IFACE domain_name_server)"; } | tee ~/zeronetwork/evidence/P1-A_ipinfo_$ZN_NAME.txt
```
**Check:** the IPv4 shown must match the table in section 0. If it doesn't, stop and update the IPs.

### 1.2 ▶ RUN ON: ALL 4 MACS — ping every Mac
```bash
for ip in $MAC1 $MAC2 $MAC3 $MAC4; do printf "%-12s " $ip; ping -c 2 -t 3 $ip | grep -E "packet loss"; done | tee ~/zeronetwork/evidence/P1-A_ping_$ZN_NAME.txt
```
You want `0.0% packet loss` for all four on all four Macs. 📸 `snap P1-A_ping_$ZN_NAME`

---

## Step 2 — Task C: Two backends (MAC-3 and MAC-4)

### 2.1 ▶ RUN ON: MAC-3 AND MAC-4 — create the backend program (same file on both)
```bash
cat > ~/zeronetwork/backend/server.py <<'EOF'
#!/usr/bin/env python3
# ZeroNetwork - tiny REST backend (standard library only)
# Usage:  python3 server.py A 3001     |     python3 server.py B 3002
import hashlib
import json
import socket
import sys
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

NAME = sys.argv[1] if len(sys.argv) > 1 else "A"
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 3001
TEAM = "ZeroNetwork"
HOST = socket.gethostname()

# /api/cached returns the SAME body on both backends, so the ETag is identical
# on A and B and a conditional request gets 304 no matter which backend answers.
CACHED_BODY = (json.dumps({
    "team": TEAM,
    "resource": "service-catalog",
    "version": 1,
    "items": ["dns", "tcp", "tls", "http", "load-balancing"],
}, indent=2) + "\n").encode()
CACHED_ETAG = '"zn-' + hashlib.sha256(CACHED_BODY).hexdigest()[:16] + '"'


def now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


class Handler(BaseHTTPRequestHandler):
    server_version = "ZeroNetwork-Backend-" + NAME
    sys_version = ""

    def send_json(self, code, obj, extra=None):
        body = (json.dumps(obj, indent=2) + "\n").encode()
        self.send_raw(code, body, "application/json", extra)

    def send_raw(self, code, body, ctype, extra=None):
        self.send_response(code)
        self.send_header("X-Backend", NAME)
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        if body is not None:
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body is not None and self.command != "HEAD":
            self.wfile.write(body)

    def route(self):
        path = self.path.split("?", 1)[0]
        if path == "/":
            self.send_json(200, {
                "team": TEAM,
                "message": "ZeroNetwork backend " + NAME + " is running",
                "backend": NAME,
                "host": HOST,
                "port": PORT,
            }, {"Cache-Control": "no-store"})
        elif path == "/api/status":
            self.send_json(200, {
                "team": TEAM,
                "backend": NAME,
                "status": "ok",
                "host": HOST,
                "port": PORT,
                "seen_client_ip": self.client_address[0],
                "x_forwarded_for": self.headers.get("X-Forwarded-For", "-"),
                "time_utc": now(),
            }, {"Cache-Control": "no-store"})
        elif path == "/api/cached":
            cache_headers = {"Cache-Control": "public, max-age=60", "ETag": CACHED_ETAG}
            inm = self.headers.get("If-None-Match", "")
            if CACHED_ETAG in inm or inm.strip() == "*":
                self.send_raw(304, None, None, cache_headers)
            else:
                self.send_raw(200, CACHED_BODY, "application/json", cache_headers)
        elif path == "/health":
            self.send_raw(200, b"ok\n", "text/plain", {"Cache-Control": "no-store"})
        else:
            self.send_json(404, {"error": "not found", "backend": NAME, "path": path})

    def do_GET(self):
        self.route()

    def do_HEAD(self):
        self.route()

    def log_message(self, fmt, *args):
        ts = datetime.now().strftime("%H:%M:%S")
        print("[%s] Backend %s <- %s:%s  %s" % (ts, NAME, self.client_address[0],
              self.client_address[1], fmt % args), flush=True)


if __name__ == "__main__":
    srv = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print("ZeroNetwork Backend %s listening on 0.0.0.0:%d (Ctrl+C to stop)" % (NAME, PORT), flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nBackend %s stopped." % NAME)
EOF
echo "server.py written"
```

### 2.2 Start the backends. Leave these windows open the whole time. This is the **"BACKEND" window**.
▶ **RUN ON: MAC-3**
```bash
python3 ~/zeronetwork/backend/server.py A 3001
```
▶ **RUN ON: MAC-4**
```bash
python3 ~/zeronetwork/backend/server.py B 3002
```
To stop a backend later, press **Ctrl+C** in that window. To restart it, press **↑ then Enter**.

### 2.3 ▶ RUN ON: MAC-1 — check both backends across the LAN (open a new Terminal tab, then `source ~/zeronetwork/env.sh`)
```bash
curl -si http://$MAC3:3001/api/status
curl -si http://$MAC4:3002/api/status
```
You should see `X-Backend: A` and `X-Backend: B`. 📸 `snap P1-C_backends_direct`

---

## Step 3 — Task E: Local CA and HTTPS certificate (MAC-2)

### 3.1 ▶ RUN ON: MAC-2 — create the ZeroNetwork CA and the server certificate
```bash
cd ~/zeronetwork/tls
cat > ca.cnf <<'EOF'
[ req ]
distinguished_name = dn
prompt             = no
x509_extensions    = v3_ca

[ dn ]
C  = IN
O  = ZeroNetwork
CN = ZeroNetwork Local Root CA

[ v3_ca ]
basicConstraints       = critical, CA:TRUE
keyUsage               = critical, keyCertSign, cRLSign
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always, issuer
EOF
cat > server.cnf <<'EOF'
[ req ]
distinguished_name = dn
prompt             = no

[ dn ]
C  = IN
O  = ZeroNetwork
CN = app.zeronetwork.test

[ v3_server ]
basicConstraints       = critical, CA:FALSE
keyUsage               = critical, digitalSignature, keyEncipherment
extendedKeyUsage       = serverAuth
subjectAltName         = DNS:app.zeronetwork.test, DNS:api.zeronetwork.test
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid, issuer
EOF
openssl genrsa -out ZeroNetworkCA.key 4096
openssl req -x509 -new -key ZeroNetworkCA.key -sha256 -days 825 -config ca.cnf -out ZeroNetworkCA.crt
openssl genrsa -out zeronetwork.key 2048
openssl req -new -key zeronetwork.key -config server.cnf -out zeronetwork.csr
openssl x509 -req -in zeronetwork.csr -CA ZeroNetworkCA.crt -CAkey ZeroNetworkCA.key -CAcreateserial -days 397 -sha256 -extfile server.cnf -extensions v3_server -out zeronetwork.crt
chmod 600 ZeroNetworkCA.key zeronetwork.key
openssl verify -CAfile ZeroNetworkCA.crt zeronetwork.crt
openssl x509 -in zeronetwork.crt -noout -text | grep -A1 -E "Subject:|Issuer:|Alternative Name|Not After"
cp ZeroNetworkCA.crt ~/zeronetwork/ZeroNetworkCA.crt
cd ~
```
You need `zeronetwork.crt: OK` and SANs `app.zeronetwork.test, api.zeronetwork.test`. 📸 `snap P1-E_cert_created`
**Never copy `ZeroNetworkCA.key` off MAC-2.**

### 3.2 ▶ RUN ON: MAC-2 — share ONLY the CA certificate on the LAN (new Terminal tab, leave it running)
```bash
cp ~/zeronetwork/tls/ZeroNetworkCA.crt ~/zeronetwork/share/
openssl x509 -in ~/zeronetwork/share/ZeroNetworkCA.crt -noout -fingerprint -sha256
python3 -m http.server 8000 --bind 0.0.0.0 --directory ~/zeronetwork/share
```
Write down the SHA256 fingerprint. You'll compare it on the clients.

---

## Step 4 — Task D: nginx edge + load balancer (MAC-2)

### 4.1 ▶ RUN ON: MAC-2 (original tab) — write the nginx config
```bash
source ~/zeronetwork/env.sh
BREW=$(brew --prefix)
brew services stop nginx 2>/dev/null
mkdir -p $BREW/etc/nginx/ssl $BREW/var/log/nginx
cp ~/zeronetwork/tls/zeronetwork.crt ~/zeronetwork/tls/zeronetwork.key $BREW/etc/nginx/ssl/
chmod 600 $BREW/etc/nginx/ssl/zeronetwork.key
cp $BREW/etc/nginx/nginx.conf ~/zeronetwork/nginx.conf.ORIGINAL-backup
cat > ~/zeronetwork/nginx.conf.template <<'EOF'
worker_processes  1;
error_log  __BREW__/var/log/nginx/zeronetwork_error.log  info;

events {
    worker_connections  1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;

    log_format zn '$time_local client=$remote_addr:$remote_port "$request" '
                  'status=$status upstream=$upstream_addr '
                  'upstream_status=$upstream_status backend=$upstream_http_x_backend '
                  'proto=$server_protocol tls=$ssl_protocol';
    access_log  __BREW__/var/log/nginx/zeronetwork_access.log  zn;

    keepalive_timeout  5;

    upstream zeronetwork_backends {
        server 10.7.25.53:3001 max_fails=1 fail_timeout=10s;
        server 10.7.23.141:3002 max_fails=1 fail_timeout=10s;
    }

    server {
        listen       443 ssl;
        http2        on;
        server_name  app.zeronetwork.test api.zeronetwork.test;

        ssl_certificate      ssl/zeronetwork.crt;
        ssl_certificate_key  ssl/zeronetwork.key;
        ssl_protocols        TLSv1.2 TLSv1.3;

        add_header X-Edge "__EDGE__" always;

        location / {
            proxy_pass             http://zeronetwork_backends;
            proxy_http_version     1.1;
            proxy_set_header       Host              $host;
            proxy_set_header       X-Real-IP         $remote_addr;
            proxy_set_header       X-Forwarded-For   $proxy_add_x_forwarded_for;
            proxy_set_header       X-Forwarded-Proto $scheme;
            proxy_connect_timeout  2s;
            proxy_read_timeout     5s;
            proxy_next_upstream    error timeout http_502 http_503 http_504;
        }
    }
}
EOF
sed -e "s|__BREW__|$BREW|g" -e "s|__EDGE__|MAC-2-primary|g" ~/zeronetwork/nginx.conf.template > $BREW/etc/nginx/nginx.conf
nginx -t
```
You need `syntax is ok` and `test is successful`.
(Only if `nginx -t` says `unknown directive "http2"`, because your nginx is older than 1.25: run `sed -i '' -e '/http2        on;/d' -e 's/listen       443 ssl;/listen       443 ssl http2;/' ~/zeronetwork/nginx.conf.template`, then rerun the `sed -e ...` line and `nginx -t`.)

### 4.2 ▶ RUN ON: MAC-2 — start nginx and test it locally (DNS isn't set up yet, so `--resolve` stands in for it)
```bash
nginx
for i in 1 2 3 4; do curl -s --cacert $CA --resolve app.zeronetwork.test:443:127.0.0.1 -o /dev/null -w "%{http_code} backend=%header{x-backend}\n" https://app.zeronetwork.test/api/status; done
```
Expected: `200 backend=A` and `200 backend=B` alternating.
- If `nginx` says `bind() to 0.0.0.0:443 failed (13: Permission denied)`, use `sudo nginx`. From then on, use `sudo nginx -s reload` and `sudo nginx -s stop` everywhere this file says `nginx -s ...`.
- Reload after config changes: `nginx -t && nginx -s reload`.

### 4.3 ▶ RUN ON: MAC-2 — live edge log window (new tab, leave it open). This is the **"EDGE LOG" window**.
```bash
source ~/zeronetwork/env.sh; tail -f $(brew --prefix)/var/log/nginx/zeronetwork_access.log
```

---

## Step 5 — Task B: Private DNS server (MAC-1)

### 5.1 ▶ RUN ON: MAC-1 — write the dnsmasq config and records (TTL 30 s)
```bash
BREW=$(brew --prefix)
UPSTREAM=$(ipconfig getoption $IFACE domain_name_server); echo "Upstream (campus) DNS: ${UPSTREAM:=1.1.1.1}"
mkdir -p $BREW/etc/dnsmasq.d
printf '10.7.21.230  app.zeronetwork.test\n10.7.21.230  api.zeronetwork.test\n' > $BREW/etc/dnsmasq.d/zeronetwork.hosts
chmod 644 $BREW/etc/dnsmasq.d/zeronetwork.hosts
cat > $BREW/etc/dnsmasq.d/zeronetwork.conf <<EOF
# ZeroNetwork private DNS ($ZN_NAME)
port=53
domain-needed
bogus-priv
no-resolv
no-hosts
server=$UPSTREAM
server=1.1.1.1
local=/zeronetwork.test/
addn-hosts=$BREW/etc/dnsmasq.d/zeronetwork.hosts
local-ttl=30
log-queries
EOF
cat $BREW/etc/dnsmasq.d/zeronetwork.conf $BREW/etc/dnsmasq.d/zeronetwork.hosts
sudo brew services stop dnsmasq 2>/dev/null
sudo lsof -nP -i :53
sudo $BREW/sbin/dnsmasq --test --conf-file=$BREW/etc/dnsmasq.d/zeronetwork.conf
```
You need `dnsmasq: syntax check OK.` The `lsof` line should print nothing (port 53 free).

### 5.2 ▶ RUN ON: MAC-1 — run DNS in its own window (new tab, leave it open). This is the **"DNS" window**, showing every query live.
```bash
source ~/zeronetwork/env.sh; sudo $(brew --prefix)/sbin/dnsmasq --keep-in-foreground --conf-file=$(brew --prefix)/etc/dnsmasq.d/zeronetwork.conf --log-facility=-
```
Stop = **Ctrl+C**. Start again = **↑ + Enter**.

### 5.3 ▶ RUN ON: MAC-1 (original tab) — query the server directly
```bash
dig @$MAC1 app.zeronetwork.test
dig @$MAC1 api.zeronetwork.test +short
dig @$MAC1 google.com +short
```
Expected: `app.zeronetwork.test. 30 IN A 10.7.21.230` (30 is the TTL), and google.com resolves too (forwarding works).

---

## Step 6 — Point the Macs at the team DNS (Task B)

### 6.1 ▶ RUN ON: ALL 4 MACS (MAC-1 first, then MAC-4, MAC-2, MAC-3)
```bash
networksetup -listallnetworkservices
networksetup -getdnsservers Wi-Fi | tee ~/zeronetwork/evidence/dns-before_$ZN_NAME.txt
sudo networksetup -setdnsservers Wi-Fi 10.7.8.17
zn_flush
scutil --dns | grep -m2 nameserver
dig app.zeronetwork.test
```
(If your service isn't called `Wi-Fi` in the list, use the exact name shown, e.g. `"USB 10/100/1000 LAN"`.)
Expected: `;; SERVER: 10.7.8.17#53` and answer `10.7.21.230`. On MAC-1, the DNS window shows the queries arriving. 📸 on MAC-4: `snap P1-B_dig_from_MAC-4`

---

## Step 7 — Trust the CA on the clients (Task E)

### 7.1 ▶ RUN ON: MAC-1, MAC-4 (and MAC-3, which needs it in Phase 2)
```bash
curl -s -o ~/zeronetwork/ZeroNetworkCA.crt http://10.7.21.230:8000/ZeroNetworkCA.crt
openssl x509 -in ~/zeronetwork/ZeroNetworkCA.crt -noout -subject -fingerprint -sha256
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/zeronetwork/ZeroNetworkCA.crt
```
The fingerprint **must match** the one MAC-2 printed in 3.2. The keychain step makes **Safari/Chrome** trust the site (macOS may show a password dialog).
> **About curl:** macOS's built-in curl uses its own CA bundle instead of the keychain, so every curl command here passes `--cacert $CA`. That's still **full certificate validation** (the name must match the SAN and the chain must lead to our CA). It is **not** `-k`, and `-k` is never used.

### 7.2 ▶ RUN ON: MAC-2 — stop the share server
In the tab running `http.server`, press **Ctrl+C**.

---

## Step 8 — HTTPS by name + load balancing (Tasks D, E)

### 8.1 ▶ RUN ON: MAC-4
```bash
curl -i --cacert $CA https://app.zeronetwork.test/api/status
for i in {1..6}; do zn_hit; done
curl -sI --cacert $CA https://app.zeronetwork.test/ | head -1
curl -sI --http1.1 --cacert $CA https://app.zeronetwork.test/ | head -1
```
Expected: JSON with `"seen_client_ip": "10.7.21.230"` (the backend only sees the edge), `x_forwarded_for` = `10.7.23.141` (the real client), backends alternating `A, B, A, B…`, `HTTP/2 200`, then `HTTP/1.1 200 OK`. The EDGE LOG window on MAC-2 shows `upstream=10.7.25.53:3001` / `10.7.23.141:3002`. 📸 `snap P1-D_loadbalancing`

### 8.2 ▶ RUN ON: MAC-4 — TLS details for the evidence
```bash
curl -v --cacert $CA -o /dev/null https://app.zeronetwork.test/api/status 2>&1 | grep -E "Trying|Connected|SSL connection|ALPN|subject:|issuer:|expire|subjectAltName|SSL certificate verify|> GET|> Host|< HTTP|< x-"
openssl s_client -connect app.zeronetwork.test:443 -servername app.zeronetwork.test -CAfile $CA </dev/null 2>/dev/null | grep -E "subject=|issuer=|Protocol|Cipher|Verify return code"
```
Expected: `Verify return code: 0 (ok)`. 📸 `snap P1-E_tls_verify`

### 8.3 Browser: on MAC-4 (or MAC-1), open **https://app.zeronetwork.test/api/status** in Safari or Chrome. You should get a padlock with no warning. In DevTools → Network, look at the headers `x-backend` and `x-edge`. (Chrome may need a restart after the keychain step.)

---

## Step 9 — Task F: HTTP caching

### 9.1 ▶ RUN ON: MAC-4
```bash
curl -sI --cacert $CA https://app.zeronetwork.test/api/cached
ETAG=$(curl -sI --cacert $CA https://app.zeronetwork.test/api/cached | awk -F': ' 'tolower($1)=="etag"{print $2}' | tr -d '\r'); echo "ETag = $ETAG"
curl -sI --cacert $CA -H "If-None-Match: $ETAG" https://app.zeronetwork.test/api/cached
curl -sI --cacert $CA -H "If-None-Match: $ETAG" https://app.zeronetwork.test/api/cached | grep -iE "^HTTP|x-backend"
```
Expected: first `200` with `cache-control: public, max-age=60` and `etag: "zn-…"`; then **`HTTP/2 304`** from both backend A and backend B (the ETag is the same on both). 📸 `snap P1-F_caching_304`
Browser: open `https://app.zeronetwork.test/api/cached` and reload within 60 s. DevTools shows `(disk cache)` or `304`.
**Explain:** fresh hit = served locally while max-age is valid, no network. Conditional = the client asks "changed?" with If-None-Match and gets 304 with no body. Full request = 200 with the whole body.

---

## Step 10 — Task G: Packet capture of DNS → TCP → TLS → HTTP

### 10.1 ▶ RUN ON: MAC-4 — tab 1: start the capture
```bash
sudo tcpdump -i $IFACE -w ~/zeronetwork/evidence/P1-G_full_flow.pcap 'port 53 or port 443 or port 3002'
```
### 10.2 ▶ RUN ON: MAC-4 — tab 2 (`source ~/zeronetwork/env.sh` first): one TLS 1.2 request (Certificate visible) and one TLS 1.3 request
```bash
zn_flush; sleep 1
curl -s --cacert $CA --tlsv1.2 --tls-max 1.2 https://app.zeronetwork.test/api/status
zn_flush; sleep 1
curl -s --cacert $CA https://app.zeronetwork.test/api/status
for i in {1..4}; do zn_hit; done
```
Then press **Ctrl+C** in tab 1.

### 10.3 ▶ RUN ON: MAC-4 — terminal summary (good for screenshots)
```bash
sudo chown $USER ~/zeronetwork/evidence/P1-G_full_flow.pcap
tshark -r ~/zeronetwork/evidence/P1-G_full_flow.pcap -Y 'dns.qry.name contains "zeronetwork" || (tcp.port==443 && tcp.flags.syn==1) || tls.handshake.type' -T fields -e frame.number -e ip.src -e tcp.srcport -e udp.srcport -e ip.dst -e tcp.dstport -e udp.dstport -e _ws.col.Protocol -e _ws.col.Info
open ~/zeronetwork/evidence/P1-G_full_flow.pcap
```
Wireshark display filters to screenshot (one 📸 each):
| Evidence | Filter |
|---|---|
| DNS query and response (client ephemeral port → 53/UDP) | `dns.qry.name == "app.zeronetwork.test"` |
| TCP 3-way handshake (SYN, SYN-ACK, ACK) | `tcp.port == 443 && tcp.flags.syn == 1` then right-click → Follow → TCP Stream |
| TLS handshake | `tls.handshake` (ClientHello=1, ServerHello=2, **Certificate=11, visible only in the TLS 1.2 stream**) |
| ChangeCipherSpec | `tls.record.content_type == 20` |
| Encrypted data | `tls.record.content_type == 23` (Application Data, unreadable) |
| Seq/Ack numbers | click any TCP packet → expand Transmission Control Protocol |
| Edge → backend in **plaintext HTTP** | `tcp.port == 3002 && http` |

**Explain:** TLS 1.3 encrypts the Certificate message, which is why the TLS 1.2 request was captured too. The client→edge leg is encrypted, while the edge→backend leg on port 3002 is plain HTTP because TLS is terminated at nginx.

---

## Step 11 — Phase 1 failure demonstrations

**F1. Wrong DNS server on a client** ▶ RUN ON: MAC-4
```bash
sudo networksetup -setdnsservers Wi-Fi 10.7.25.53; zn_flush
dig app.zeronetwork.test
curl --cacert $CA https://app.zeronetwork.test/api/status
ping -c 2 10.7.21.230
sudo networksetup -setdnsservers Wi-Fi 10.7.8.17; zn_flush; dig +short app.zeronetwork.test
```
Expected: dig fails ("connection refused" or "no servers could be reached") and curl says `Could not resolve host`, **but ping to the edge IP works**. DNS and IP are separate layers. 📸 `snap P1-F1_wrong_dns`

**F2. DNS record points to the wrong IP** ▶ RUN ON: MAC-1
```bash
zn_dns_set 10.7.25.53 10.7.21.230
```
▶ RUN ON: MAC-4
```bash
zn_flush; dig +short app.zeronetwork.test; curl --cacert $CA https://app.zeronetwork.test/api/status
```
Expected: resolves to `10.7.25.53` (wrong), then `Failed to connect … port 443 … Connection refused`. DNS is a directory, not a connection. 📸 `snap P1-F2_wrong_record`
▶ RUN ON: MAC-1 (restore): `zn_dns_set 10.7.21.230 10.7.21.230`  ▶ MAC-4: `zn_flush; zn_hit`

**F3. One backend stopped**: ▶ MAC-3: **Ctrl+C** in the BACKEND window. ▶ MAC-4: `for i in {1..6}; do zn_hit; done` → every response is `200 backend=B`. ▶ MAC-3: **↑ + Enter** to restart. 📸 `snap P1-F3_one_backend`

**F4. Both backends stopped**: ▶ MAC-3 and MAC-4: **Ctrl+C** in both BACKEND windows. ▶ MAC-4 (another tab):
```bash
dig +short app.zeronetwork.test; curl -si --cacert $CA https://app.zeronetwork.test/api/status | head -12
```
Expected: DNS works, TLS works, response is **`HTTP/2 502`** with `x-edge: MAC-2-primary`, so the edge is alive and the backends are down. On MAC-2, run `tail -3 $(brew --prefix)/var/log/nginx/zeronetwork_error.log` to see `connect() failed (61: Connection refused) while connecting to upstream`. Restart both backends (↑ + Enter). 📸 `snap P1-F4_502`

**F5. Wrong destination port** ▶ RUN ON: MAC-4
```bash
nc -vz -G 3 app.zeronetwork.test 443
nc -vz -G 3 app.zeronetwork.test 9443
curl --cacert $CA https://app.zeronetwork.test:9443/
ping -c 2 app.zeronetwork.test
```
Expected: 443 `succeeded`, 9443 `Connection refused`, ping OK. The IP identifies the host and the port identifies the service. 📸 `snap P1-F5_wrong_port`

✅ **Phase 1 is complete.**

---
---

# PHASE 2 — Harden & Recover (record this)

### Recording tips
- On each Mac, press **⌘⇧5 → Record Entire Screen** (or record one Mac and screenshot the others).
- Every terminal prompt already shows `[ZeroNetwork | MAC-X | IP] time`, so each screenshot shows which Mac and when.
- 📸 = take a screenshot with `snap <name>` (saved in `~/zeronetwork/evidence/`).
- Arrange windows so the DNS window (MAC-1, MAC-3), EDGE LOG (MAC-2) and BACKEND windows are visible next to the command tab.

## P2-0 — Health check before recording ▶ RUN ON: MAC-4
```bash
dig +short app.zeronetwork.test
for i in {1..4}; do zn_hit; done
zn_diag
```
📸 `snap P2-00_healthcheck`

---

## P2-A — Extension A: Backup DNS resolver on MAC-3

**A1 ▶ RUN ON: MAC-3** — same records as MAC-1 (new tab, `source ~/zeronetwork/env.sh`)
```bash
BREW=$(brew --prefix)
UPSTREAM=$(ipconfig getoption $IFACE domain_name_server); echo "Upstream DNS: ${UPSTREAM:=1.1.1.1}"
mkdir -p $BREW/etc/dnsmasq.d
printf '10.7.21.230  app.zeronetwork.test\n10.7.21.230  api.zeronetwork.test\n' > $BREW/etc/dnsmasq.d/zeronetwork.hosts
chmod 644 $BREW/etc/dnsmasq.d/zeronetwork.hosts
cat > $BREW/etc/dnsmasq.d/zeronetwork.conf <<EOF
# ZeroNetwork private DNS ($ZN_NAME - BACKUP)
port=53
domain-needed
bogus-priv
no-resolv
no-hosts
server=$UPSTREAM
server=1.1.1.1
local=/zeronetwork.test/
addn-hosts=$BREW/etc/dnsmasq.d/zeronetwork.hosts
local-ttl=30
log-queries
EOF
sudo brew services stop dnsmasq 2>/dev/null
sudo $BREW/sbin/dnsmasq --test --conf-file=$BREW/etc/dnsmasq.d/zeronetwork.conf
```
📸 `snap P2-A1_backup_dns_config`

**A2 ▶ RUN ON: MAC-3** — new tab = **backup "DNS" window**, leave it open:
```bash
source ~/zeronetwork/env.sh; sudo $(brew --prefix)/sbin/dnsmasq --keep-in-foreground --conf-file=$(brew --prefix)/etc/dnsmasq.d/zeronetwork.conf --log-facility=-
```

**A3 ▶ RUN ON: MAC-4** — both servers answer the same
```bash
dig @10.7.8.17 app.zeronetwork.test +noall +answer
dig @10.7.25.53 app.zeronetwork.test +noall +answer
```
📸 `snap P2-A3_both_dns_answer`

**A4 ▶ RUN ON: ALL 4 MACS** — list primary + backup
```bash
sudo networksetup -setdnsservers Wi-Fi 10.7.8.17 10.7.25.53
zn_flush
networksetup -getdnsservers Wi-Fi
scutil --dns | grep -m3 nameserver
```
📸 on MAC-4: `snap P2-A4_two_resolvers`

**A5 ▶ RUN ON: MAC-1** — **stop the primary DNS**: press **Ctrl+C** in the MAC-1 DNS window (or run: `sudo pkill -9 dnsmasq`). 📸 `snap P2-A5_primary_stopped`

**A6 ▶ RUN ON: MAC-4** — clients keep resolving through the backup
```bash
dig @10.7.8.17 app.zeronetwork.test +tries=1 +time=2
dig app.zeronetwork.test
zn_flush; for i in {1..4}; do zn_hit; done
```
Expected: the direct query to 10.7.8.17 fails. The normal `dig` shows `;; SERVER: 10.7.25.53#53` with the correct answer, and HTTPS still works. The **MAC-3 DNS window** logs `query[A] app.zeronetwork.test from 10.7.23.141`. 📸 `snap P2-A6_failover_to_backup` (MAC-4) and 📸 `snap P2-A6_backup_dns_log` (MAC-3)

**A7 — Contrast: application failure (DNS still works)**: ▶ MAC-3 and MAC-4: **Ctrl+C** in both BACKEND windows. ▶ MAC-4:
```bash
dig +short app.zeronetwork.test; zn_hit
```
→ name resolves, but the result is `502`. 📸 `snap P2-A7_app_failure_vs_dns_failure`. Then restart both backends (↑ + Enter).
**Explain:** DNS failure = you can't find where the service is. Application failure = you find it and connect, but the service behind it is down.

**A8 ▶ RUN ON: MAC-1** — restart the primary: **↑ + Enter** in the DNS window. ▶ MAC-4: `dig app.zeronetwork.test | grep SERVER`

---

## P2-B — Extension B: TTL 30 s and a controlled record change

**B1 ▶ RUN ON: MAC-4** — show the TTL and prime the OS cache
```bash
dig api.zeronetwork.test +noall +answer
zn_flush; dscacheutil -q host -a name api.zeronetwork.test
```
Expected: TTL `30`, IP `10.7.21.230`. 📸 `snap P2-B1_ttl30`

**B2 ▶ RUN ON: MAC-1, then MAC-3 right after** (both DNS servers must match): change `api` to MAC-3
```bash
zn_dns_set 10.7.21.230 10.7.25.53
```
📸 `snap P2-B2_record_changed_$ZN_NAME`

**B3 ▶ RUN ON: MAC-4 — immediately** (watch the cached answer, then the new one)
```bash
for i in {1..9}; do echo "$(date +%T)   OS cache (what apps use): $(dscacheutil -q host -a name api.zeronetwork.test | awk '/ip_address/{print $2}')   |   DNS server now (dig): $(dig +short api.zeronetwork.test)"; sleep 5; done
```
Expected: dig shows the new `10.7.25.53` right away, but the OS cache keeps returning the old `10.7.21.230` until the 30 s TTL expires, then switches. 📸 `snap P2-B3_ttl_expiry`

**B4 — Manual flush**: ▶ MAC-1, then MAC-3: `zn_dns_set 10.7.21.230 10.7.21.230` ▶ MAC-4 right away:
```bash
dscacheutil -q host -a name api.zeronetwork.test | grep ip_address
zn_flush
dscacheutil -q host -a name api.zeronetwork.test | grep ip_address
```
→ old IP before the flush, new IP immediately after. 📸 `snap P2-B4_manual_flush`
**Explain:** before a migration, production teams lower the TTL in advance so a cutover takes effect within seconds. Clients only see the change once their cache expires.

---

## P2-C — Extension C: Service isolation (only MAC-2 may reach the backends)

**C0 ▶ RUN ON: MAC-1** — BEFORE: direct access works
```bash
curl -s --connect-timeout 5 http://10.7.25.53:3001/health; curl -s --connect-timeout 5 http://10.7.23.141:3002/health
```
📸 `snap P2-C0_before_firewall`

**C1 ▶ RUN ON: MAC-3** — firewall for port 3001 (keeps a rollback copy)
```bash
sudo pfctl -s info 2>/dev/null | grep Status | tee ~/zeronetwork/evidence/pf-status-before_$ZN_NAME.txt
cp /etc/pf.conf ~/zeronetwork/evidence/pf.conf.ROLLBACK_$ZN_NAME
cat /etc/pf.conf > ~/zeronetwork/pf-zeronetwork.conf
cat >> ~/zeronetwork/pf-zeronetwork.conf <<'EOF'

# ---- ZeroNetwork Extension C: only the edge MAC-2 (10.7.21.230) may reach Backend A ----
pass in quick on lo0 all
pass in quick proto tcp from 10.7.21.230 to any port 3001
block drop in quick proto tcp from any to any port 3001
EOF
sudo pfctl -nf ~/zeronetwork/pf-zeronetwork.conf && sudo pfctl -f ~/zeronetwork/pf-zeronetwork.conf && sudo pfctl -e
sudo pfctl -sr | grep -E "3001|lo0"
```
**C2 ▶ RUN ON: MAC-4** — same for port 3002
```bash
sudo pfctl -s info 2>/dev/null | grep Status | tee ~/zeronetwork/evidence/pf-status-before_$ZN_NAME.txt
cp /etc/pf.conf ~/zeronetwork/evidence/pf.conf.ROLLBACK_$ZN_NAME
cat /etc/pf.conf > ~/zeronetwork/pf-zeronetwork.conf
cat >> ~/zeronetwork/pf-zeronetwork.conf <<'EOF'

# ---- ZeroNetwork Extension C: only the edge MAC-2 (10.7.21.230) may reach Backend B ----
pass in quick on lo0 all
pass in quick proto tcp from 10.7.21.230 to any port 3002
block drop in quick proto tcp from any to any port 3002
EOF
sudo pfctl -nf ~/zeronetwork/pf-zeronetwork.conf && sudo pfctl -f ~/zeronetwork/pf-zeronetwork.conf && sudo pfctl -e
sudo pfctl -sr | grep -E "3002|lo0"
```
(Warnings like `No ALTQ support in kernel` or `pf already enabled` are harmless.) 📸 `snap P2-C_rules_$ZN_NAME` on both.

**C3 ▶ RUN ON: MAC-1** — client can NOT reach the backends directly
```bash
curl -s --connect-timeout 5 http://10.7.25.53:3001/health; echo "exit=$? (28 = timed out = blocked)"
curl -s --connect-timeout 5 http://10.7.23.141:3002/health; echo "exit=$? (28 = timed out = blocked)"
nc -vz -G 5 10.7.25.53 3001
```
📸 `snap P2-C3_client_blocked`

**C4 ▶ RUN ON: MAC-2** — edge CAN reach them
```bash
curl -s --connect-timeout 5 http://10.7.25.53:3001/health; curl -s --connect-timeout 5 http://10.7.23.141:3002/health
```
📸 `snap P2-C4_edge_allowed`

**C5 ▶ RUN ON: MAC-1** — the service still works through the edge
```bash
for i in {1..4}; do zn_hit; done
```
📸 `snap P2-C5_via_edge_ok`
> If C4 is ALSO blocked, the backends see a different source IP for MAC-2 (NAT between subnets). Check the `seen_client_ip` value in step 8.1 and put that IP in the `pass` rule instead.

**C6 — ROLLBACK ▶ RUN ON: MAC-3 and MAC-4** (required by the brief)
```bash
sudo pfctl -f /etc/pf.conf
cat ~/zeronetwork/evidence/pf-status-before_$ZN_NAME.txt
```
If that file says `Status: Disabled`, also run `sudo pfctl -d`. Then check:
```bash
sudo pfctl -sr 2>/dev/null | grep -E "300[12]" || echo "ZeroNetwork rules removed - original firewall restored"
```
▶ MAC-1: `curl -s --connect-timeout 5 http://10.7.25.53:3001/health` → `ok` again. 📸 `snap P2-C6_rollback_$ZN_NAME`

---

## P2-D — Extension D: High-availability failover

**D1 ▶ RUN ON: MAC-4** — start a 40-second request stream
```bash
for i in {1..40}; do printf "%s  " "$(date +%T)"; zn_hit; sleep 1; done
```
**D2 ▶ RUN ON: MAC-3** — ~5 s into the stream, **Ctrl+C** in the BACKEND window (Backend A down).
→ MAC-4 shows only `200 backend=B` with **no failed requests**. MAC-2 EDGE LOG shows only `upstream=10.7.23.141:3002`.
**D3 ▶ RUN ON: MAC-3** — ~15 s later, **↑ + Enter** (Backend A back).
→ within about 10 s (`fail_timeout=10s`), A and B alternate again.
📸 `snap P2-D_failover_stream` (MAC-4), `snap P2-D_edge_log` (MAC-2), `snap P2-D_backendA_stopped` (MAC-3)
▶ MAC-2 — the edge's view of the failure:
```bash
grep "connect() failed" $(brew --prefix)/var/log/nginx/zeronetwork_error.log | tail -3
```
📸 `snap P2-D_error_log`
**Explain:** `max_fails=1 fail_timeout=10s` plus `proxy_next_upstream error timeout` means a failed connection is retried on the other backend, the failed one is marked down for 10 s, and then it's tried again. This is passive health checking. **The single point of failure is still the nginx edge on MAC-2.** Fixing that needs a second edge plus a floating/virtual IP (keepalived/VRRP), DNS failover with health checks, or a managed load balancer (AWS ALB across availability zones).

---

## P2-E — Extension E: DNS-based edge migration to a standby nginx on MAC-3

**E1 ▶ RUN ON: MAC-2** — temporarily share the server cert and key with MAC-3 (new tab)
```bash
cp ~/zeronetwork/tls/zeronetwork.crt ~/zeronetwork/tls/zeronetwork.key ~/zeronetwork/nginx.conf.template ~/zeronetwork/share/
python3 -m http.server 8000 --bind 0.0.0.0 --directory ~/zeronetwork/share
```
**E2 ▶ RUN ON: MAC-3** — build the standby edge (same config, labelled `MAC-3-standby`)
```bash
BREW=$(brew --prefix)
brew services stop nginx 2>/dev/null
mkdir -p $BREW/etc/nginx/ssl $BREW/var/log/nginx
cp $BREW/etc/nginx/nginx.conf ~/zeronetwork/nginx.conf.ORIGINAL-backup
for f in zeronetwork.crt zeronetwork.key; do curl -s -o $BREW/etc/nginx/ssl/$f http://10.7.21.230:8000/$f; done
curl -s -o ~/zeronetwork/nginx.conf.template http://10.7.21.230:8000/nginx.conf.template
chmod 600 $BREW/etc/nginx/ssl/zeronetwork.key
sed -e "s|__BREW__|$BREW|g" -e "s|__EDGE__|MAC-3-standby|g" ~/zeronetwork/nginx.conf.template > $BREW/etc/nginx/nginx.conf
nginx -t && nginx
for i in 1 2 3 4; do curl -s --cacert $CA --resolve app.zeronetwork.test:443:127.0.0.1 -o /dev/null -w "%{http_code} backend=%header{x-backend} edge=%header{x-edge}\n" https://app.zeronetwork.test/api/status; done
```
Expected: `200 … edge=MAC-3-standby` with backends A and B. (If 443 is refused, use `sudo nginx` as in 4.2.) 📸 `snap P2-E2_standby_ready`
**E3 ▶ RUN ON: MAC-2** — stop the share (**Ctrl+C**) and remove the key copy:
```bash
rm ~/zeronetwork/share/zeronetwork.key ~/zeronetwork/share/zeronetwork.crt ~/zeronetwork/share/nginx.conf.template; ls ~/zeronetwork/share
```
**E4 ▶ RUN ON: MAC-4** — prime the cache on the primary edge, then start watching
```bash
zn_flush; zn_hit
for i in {1..20}; do printf "%s  " "$(date +%T)"; zn_hit; sleep 3; done
```
**E5 ▶ RUN ON: MAC-1, then MAC-3 right after** (while the E4 loop runs) — **cutover**: app → MAC-3
```bash
zn_dns_set 10.7.25.53 10.7.21.230
```
**E6 ▶ RUN ON: MAC-1** — a new client lookup goes to the standby straight away
```bash
zn_flush; dig +short app.zeronetwork.test; zn_hit
```
Expected: MAC-1 (fresh lookup) gets `edge=MAC-3-standby` at once. MAC-4 (cached) keeps showing `edge=MAC-2-primary` for up to 30 s, then switches to `edge=MAC-3-standby`. The MAC-2 EDGE LOG stops receiving MAC-4's requests. 📸 `snap P2-E_cutover_stream` (MAC-4), `snap P2-E6_new_client_standby` (MAC-1), `snap P2-E_old_edge_log` (MAC-2)
**E7 — Cut back** ▶ MAC-1, then MAC-3: `zn_dns_set 10.7.21.230 10.7.21.230` ▶ MAC-4: `zn_flush; zn_hit` → `edge=MAC-2-primary`. ▶ MAC-3: `nginx -s stop`.

---

## P2-F — Extension F: Troubleshooting drill (practice for the faculty fault)

Always diagnose in this order: **DNS → TCP → TLS → HTTP/application**. One command runs the whole ladder:
▶ RUN ON: MAC-4: `zn_diag`

Practise with these injected faults (one person injects, another diagnoses out loud):

| # | Inject (where) | Inject command | What `zn_diag` shows | Fix |
|---|---|---|---|---|
| 1 | DNS typo (MAC-1 + MAC-3) | `zn_dns_set 10.7.21.99 10.7.21.230` | step 1 wrong IP, step 2 fails | `zn_dns_set 10.7.21.230 10.7.21.230`, then MAC-4 `zn_flush` |
| 2 | Edge down (MAC-2) | `nginx -s stop` | DNS ok, **TCP 443 refused** | `nginx` |
| 3 | Bad upstream port (MAC-2) | `sed -i '' 's/10.7.25.53:3001/10.7.25.53:3005/' $(brew --prefix)/etc/nginx/nginx.conf && nginx -s reload` | all OK, but **only backend=B** ever answers; error log shows 3005 refused | `sed -i '' 's/:3005/:3001/' $(brew --prefix)/etc/nginx/nginx.conf && nginx -s reload` |
| 4 | Client DNS wrong (MAC-4) | `sudo networksetup -setdnsservers Wi-Fi 10.7.21.230; zn_flush` | step 1 empty | `sudo networksetup -setdnsservers Wi-Fi 10.7.8.17 10.7.25.53; zn_flush` |
| 5 | Both backends down (MAC-3, MAC-4) | Ctrl+C both | DNS, TCP, TLS ok, **HTTP 502** | restart both |

Useful single checks: `dig +short app.zeronetwork.test` · `nc -vz -G 3 app.zeronetwork.test 443` · `openssl s_client -connect app.zeronetwork.test:443 -servername app.zeronetwork.test -CAfile $CA </dev/null` · `curl -v --cacert $CA https://app.zeronetwork.test/api/status` · on MAC-2: `nginx -t`, `tail $(brew --prefix)/var/log/nginx/zeronetwork_error.log`, `curl http://10.7.25.53:3001/health`.
📸 one screenshot per drill: `snap P2-F_drill1` …

---

## Final cleanup (after the demo / evaluation)
▶ **ALL MACS:** `sudo networksetup -setdnsservers Wi-Fi empty; zn_flush` (returns to normal DHCP DNS)
▶ **MAC-1, MAC-3:** Ctrl+C in the DNS windows
▶ **MAC-2 (and MAC-3 if still running):** `nginx -s stop`; to restore the original config: `cp ~/zeronetwork/nginx.conf.ORIGINAL-backup $(brew --prefix)/etc/nginx/nginx.conf`
▶ **MAC-3, MAC-4:** Ctrl+C in the BACKEND windows
▶ **MAC-1, MAC-3, MAC-4 (optional, remove CA trust):** `sudo security delete-certificate -c "ZeroNetwork Local Root CA" /Library/Keychains/System.keychain`

## Configuration bundle checklist (deliverable)
- MAC-1/MAC-3: `$(brew --prefix)/etc/dnsmasq.d/zeronetwork.conf`, `zeronetwork.hosts`
- MAC-2: `~/zeronetwork/nginx.conf.template`, `$(brew --prefix)/etc/nginx/nginx.conf`, `~/zeronetwork/tls/ca.cnf`, `server.cnf`
- MAC-3/MAC-4: `~/zeronetwork/backend/server.py`, `~/zeronetwork/pf-zeronetwork.conf`
- Every Mac: `~/zeronetwork/evidence/` (screenshots, ping/IP text files, `P1-G_full_flow.pcap`, pf rollback copies)
