# ZeroNetwork — Final Demonstration Runbook (11 steps, Section 8)

> The demo follows the fixed Section 8 sequence. The faculty may stop at any step and ask questions, so **say what you are proving before you run each command.**
> Total time: about **15 minutes**, plus the fault and the viva.

| Machine | Speaker                | IP          | Role in the demo                                                |
| ------- | ---------------------- | ----------- | --------------------------------------------------------------- |
| MAC-1   | **Yash Agarwal** | 10.7.8.17   | Primary DNS · second client                                    |
| MAC-2   | **Vansh Sharma** | 10.7.21.230 | Edge nginx (TLS + load balancer)                                |
| MAC-3   | **Swati Ghosh**  | 10.7.25.53  | Backend A · backup DNS · standby edge                         |
| MAC-4   | **Shyam Verma**  | 10.7.23.141 | Backend B · **main client** (screen shared) · Wireshark |

Commands use the helpers from `~/zeronetwork/env.sh` (see [`runbook.md`](runbook.md) §0.3): `zn_hit`, `zn_diag`, `zn_flush`, `zn_dns_set`. **Every new Terminal tab needs `source ~/zeronetwork/env.sh` first.**
If you use `sudo nginx` on a Mac, also use `sudo nginx -s stop` / `sudo nginx -s reload` there.

---

## 0. Before the slot (T-30 min)

### 0.1 Windows to have open

| Mac   | Window 1                                                  | Window 2                                            | Window 3                                   |
| ----- | --------------------------------------------------------- | --------------------------------------------------- | ------------------------------------------ |
| MAC-1 | **DNS** (dnsmasq in foreground, shows queries live) | Client terminal                                     | Slides (topology)                          |
| MAC-2 | Edge terminal                                             | **EDGE LOG** (`tail -f` access log)         | —                                         |
| MAC-3 | **BACKEND A**                                       | **Backup DNS**                                | Spare terminal (standby edge, pf)          |
| MAC-4 | **BACKEND B**                                       | **Client** terminal (big font, screen shared) | **Wireshark** with the saved capture |

### 0.2 Start everything (in this order)

| # | Mac          | Command                                                                                                                                                                  |
| - | ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1 | ALL          | `source ~/zeronetwork/env.sh; ipconfig getifaddr en0` → must match the table above. If an IP changed (DHCP), fix nginx upstream / DNS records before anything else.   |
| 2 | MAC-3        | BACKEND A window: `python3 ~/zeronetwork/backend/server.py A 3001`                                                                                                     |
| 3 | MAC-4        | BACKEND B window: `python3 ~/zeronetwork/backend/server.py B 3002`                                                                                                     |
| 4 | MAC-1        | DNS window: `sudo pkill dnsmasq; sudo $(brew --prefix)/sbin/dnsmasq --keep-in-foreground --conf-file=$(brew --prefix)/etc/dnsmasq.d/zeronetwork.conf --log-facility=-` |
| 5 | MAC-3        | Backup DNS window: same command as row 4                                                                                                                                 |
| 6 | MAC-2        | `nginx -t && (nginx -s reload 2>/dev/null \|\| nginx)` · EDGE LOG window: `tail -f $(brew --prefix)/var/log/nginx/zeronetwork_access.log`                             |
| 7 | MAC-1, MAC-4 | `sudo networksetup -setdnsservers Wi-Fi 10.7.8.17 10.7.25.53; zn_flush`                                                                                                |
| 8 | MAC-3, MAC-4 | Firewall must be **off** for the demo start: `sudo pfctl -sr 2>/dev/null \| grep -E "300[12]" \|\| echo "no ZeroNetwork pf rules"`                                  |
| 9 | MAC-3        | Standby nginx must be **stopped**: `nginx -s stop 2>/dev/null; echo ok`                                                                                          |

### 0.3 Health check ▶ MAC-4

```bash
dig +short app.zeronetwork.test          # 10.7.21.230
for i in {1..4}; do zn_hit; done         # 200, backend A/B alternating, edge=MAC-2-primary
zn_diag                                  # all four layers OK
```

Optional full suite (from the repo folder): `bash tests/run-all-tests.sh` → `4 / 4 passed`.

**Fallback for every step:** the screenshot listed in the step's "Backup evidence" line, in [`../evidence/`](../evidence).

---

## Step 1 — Topology and IP/service inventory · *Yash* · 1 min

**Show:** slide 2 (topology) and slide 3 (layers), or [`docs/diagrams/README.md`](diagrams/README.md) §1–2.
**Say:** "Four Macs on one Wi-Fi LAN, 10.7.0.0/19. MAC-1 is our DNS, MAC-2 the only entry point, MAC-3 and MAC-4 the two backends. The client only knows the name `app.zeronetwork.test`; only the edge knows where the backends are."

| Machine | IP          | Service   | Port |
| ------- | ----------- | --------- | ---: |
| MAC-1   | 10.7.8.17   | dnsmasq   |   53 |
| MAC-2   | 10.7.21.230 | nginx     |  443 |
| MAC-3   | 10.7.25.53  | backend A | 3001 |
| MAC-4   | 10.7.23.141 | backend B | 3002 |

---

## Step 2 — All machines on the private LAN · *Yash* · 1 min

▶ **Each Mac** shows its own IP:

```bash
ipconfig getifaddr en0; ifconfig en0 | grep -E "inet |ether"
```

▶ **MAC-1** pings the other three:

```bash
for h in 10.7.21.230 10.7.25.53 10.7.23.141; do ping -c 2 -t 3 $h | tail -2; done
```

**Expected:** `0.0% packet loss` for each.
**If a ping fails:** macOS stealth mode blocks ping. On that Mac: `sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode off`.
Backup evidence: `evidence/task-a/`.

---

## Step 3 — Resolve the private domain from a client · *Shyam* · 1 min

▶ **MAC-4**

```bash
dig app.zeronetwork.test
```

**Point to:** `ANSWER SECTION: app.zeronetwork.test. 30 IN A 10.7.21.230` and `;; SERVER: 10.7.8.17#53`. MAC-1's DNS window logs the query live.
**Say:** "DNS only finds the IP. Connecting to it is a separate TCP and TLS step."
Backup evidence: `evidence/task-b/`.

---

## Step 4 — Open the service over HTTPS by name · *Vansh* · 1.5 min

▶ **MAC-4** browser: open **https://app.zeronetwork.test/api/status** → padlock, no warning, no IP in the URL. Click the padlock → issued by *ZeroNetwork Local Root CA*.
▶ **MAC-4** terminal:

```bash
curl -v --cacert $CA https://app.zeronetwork.test/api/status 2>&1 | grep -E "SSL connection|ALPN|subjectAltName|issuer|verify ok|< HTTP|x-backend|x-edge"
```

**Point to:** `TLSv1.3`, `ALPN: server accepted h2`, `subjectAltName ... matched`, `SSL certificate verify ok`. **No `-k`.**
**Say:** "TLS terminates at nginx on MAC-2. We trust our own CA on every client, so validation is real."
Backup evidence: `evidence/task-e/`.

---

## Step 5 — Load balancing across both backends · *Vansh* · 1 min

▶ **MAC-4**

```bash
for i in {1..6}; do zn_hit; done
curl -s --cacert $CA https://app.zeronetwork.test/api/status     # JSON: backend, client_ip = edge, x_forwarded_for = 10.7.23.141
```

**Expected:** `backend=A`, `backend=B` alternating. MAC-2's EDGE LOG shows the two upstreams in turn.
**Say:** "Round robin. The backend sees the edge as its client; X-Forwarded-For carries the real client IP."
Backup evidence: `evidence/task-d/`.

---

## Step 6 — Wireshark evidence of DNS, TCP and TLS · *Shyam* · 2 min

▶ **MAC-4** Wireshark: open `~/zeronetwork/evidence/P1-G_full_flow.pcap`. Use these display filters in order:

| Filter                                                      | Point to                                                                           |
| ----------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `dns`                                                     | Query from 10.7.23.141 to 10.7.8.17 UDP 53, answer A 10.7.21.230                   |
| `tcp.flags.syn == 1 && tcp.port == 443`                   | SYN → SYN-ACK (then ACK) — the three-way handshake                               |
| `tls.handshake.type == 1`                                 | ClientHello: SNI `app.zeronetwork.test`, ALPN h2                                 |
| `tls.handshake.type == 2 \|\| tls.handshake.type == 11`     | ServerHello, and Certificate (from the TLS 1.2 request) showing the ZeroNetwork CA |
| `tls.app_data`                                            | Encrypted Application Data on 443 — unreadable                                    |
| `tcp.port == 3002` → right-click → Follow → TCP Stream | Edge → backend leg is readable HTTP (`GET /api/status`, `X-Forwarded-For`)    |

**Say:** "TLS 1.3 encrypts the Certificate message, so we captured one TLS 1.2 request to show it. Port 3002 is plaintext because TLS ends at the edge."
Backup evidence: `evidence/task-g/` (5 screenshots).

---

## Step 7 — HTTP headers and caching · *Shyam* · 1.5 min

▶ **MAC-4**

```bash
curl -sI --cacert $CA https://app.zeronetwork.test/api/cached
ETAG=$(curl -sI --cacert $CA https://app.zeronetwork.test/api/cached | awk -F': ' 'tolower($1)=="etag"{print $2}' | tr -d '\r')
for i in 1 2; do curl -sI --cacert $CA -H "If-None-Match: $ETAG" https://app.zeronetwork.test/api/cached | grep -iE "^HTTP|x-backend"; done
```

**Expected:** first `HTTP/2 200` with `cache-control: public, max-age=60` and `etag`; then `HTTP/2 304` from backend B **and** backend A.
**Say:** "Fresh hit = within 60 s the client doesn't ask at all. Conditional = If-None-Match, 304, headers only. Full request = 200 with the body. Both backends send the same body, so the ETag matches on A and B."
Backup evidence: `evidence/task-f/`.

---

## Step 8 — Fail one backend, service continues · *Swati* (+ *Shyam*) · 1.5 min

▶ **MAC-4** start the stream first:

```bash
for i in {1..30}; do printf "%s  " "$(date +%T)"; zn_hit; sleep 1; done
```

▶ **MAC-3** about 5 s in: **Ctrl+C** in the BACKEND A window.
**Expected on MAC-4:** every line stays `200`, now only `backend=B`. **Zero failed requests.**
▶ **MAC-2** show the edge noticed: `tail -3 $(brew --prefix)/var/log/nginx/zeronetwork_access.log` → `upstream_status=502, 200` (failed on A, retried on B).
▶ **MAC-3** restart: **↑ + Enter** → after about 10 s, A and B alternate again.
**Say:** "`max_fails=1 fail_timeout=10s` plus `proxy_next_upstream`: a failed request is retried on B and A is skipped for 10 s. Passive health checks — the failure itself is the signal."
Backup evidence: `evidence/phase2/P2-D_01…03`.

---

## Step 9 — Phase 2 DNS and resilience · *Yash* + *Swati* · 3 min

Do **9A** (required minimum). Do **9B** if time allows. **9C** only if asked about isolation.

### 9A — Backup DNS failover (Ext A) · *Yash*

▶ **MAC-4** show both servers answer and the client lists both:

```bash
dig @10.7.8.17 app.zeronetwork.test +short; dig @10.7.25.53 app.zeronetwork.test +short
scutil --dns | grep -m2 nameserver
```

▶ **MAC-1** stop primary DNS: **Ctrl+C** in the DNS window (or run `sudo pkill -9 dnsmasq` if running in background / sudo).
▶ **MAC-4**

```bash
zn_flush; dig app.zeronetwork.test | grep -E "^app|SERVER"; zn_hit
```

**Expected:** `SERVER: 10.7.25.53#53`, correct answer, `200`. MAC-3's backup DNS window logs the query.
▶ **MAC-1** restart primary: **↑ + Enter** (or: `sudo $(brew --prefix)/sbin/dnsmasq --keep-in-foreground --conf-file=$(brew --prefix)/etc/dnsmasq.d/zeronetwork.conf --log-facility=-`).
**Say:** "DNS failure = nobody can find the service. With two resolvers, losing one changes nothing for clients."

### 9B — DNS cutover to the standby edge (Ext B + E) · *Swati*

▶ **MAC-3** start the standby edge (config already built in Phase 2, see [`runbook.md`](runbook.md) P2-E):

```bash
nginx -t && nginx
curl -s --cacert $CA --resolve app.zeronetwork.test:443:127.0.0.1 -o /dev/null -w "%{http_code} edge=%header{x-edge}\n" https://app.zeronetwork.test/api/status
```

▶ **MAC-4** start watching:

```bash
zn_flush; for i in {1..20}; do printf "%s  " "$(date +%T)"; zn_hit; sleep 3; done
```

▶ **MAC-1, then MAC-3 right after** (while the loop runs) — cut over:

```bash
zn_dns_set 10.7.25.53 10.7.21.230
```

▶ **MAC-1** a fresh client goes straight to the standby: `zn_flush; zn_hit` → `edge=MAC-3-standby`.
**Expected on MAC-4:** `edge=MAC-2-primary` until its cached answer expires (≤ 30 s TTL), then `edge=MAC-3-standby`, all `200`.
**Say:** "Cached clients stay on the old edge until the TTL expires; a new lookup goes to the standby at once. That is why we use a 30 s TTL."
**Roll back (must do):**

```bash
# MAC-1, then MAC-3
zn_dns_set 10.7.21.230 10.7.21.230
# MAC-4
zn_flush; zn_hit          # edge=MAC-2-primary
# MAC-3
nginx -s stop
```

### 9C — Service isolation (Ext C), only if asked · *Swati*

Load the rules from [`runbook.md`](runbook.md) P2-C on MAC-3 and MAC-4, then ▶ **MAC-1**:

```bash
curl -s -m 3 -o /dev/null -w "%{http_code}\n" http://10.7.25.53:3001/health; echo "exit=$?"   # exit=28, dropped
zn_hit                                                                                          # 200 through the edge
```

**Roll back on MAC-3 and MAC-4:** `sudo pfctl -f /etc/pf.conf` (add `sudo pfctl -d` if pf was disabled before).

> ⚠️ Do 9C **after** 9B, or roll it back first: while pf is on, only MAC-2 may reach the backends, so the standby edge on MAC-3 could not reach backend B.

Backup evidence: `evidence/phase2/P2-A*`, `P2-B*`, `P2-C*`, `P2-E*`.

---

## Step 10 — Diagnose the faculty-injected fault · *Everyone* · 3–5 min

**Rule: say each step out loud, in this order. Partial credit is for the method.**

▶ **MAC-4** run the ladder (or `bash tests/failure-tests.sh`):

```bash
zn_flush; zn_diag
```

| Layer  | Check                                                                                                          | Healthy                    | If it fails, suspect                                        | Where to look / fix                                                                                                                                   |
| ------ | -------------------------------------------------------------------------------------------------------------- | -------------------------- | ----------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1 DNS  | `dig +short app.zeronetwork.test`                                                                            | `10.7.21.230`            | Wrong/missing record, client resolver changed, dnsmasq down | MAC-1/MAC-3 hosts file (`zn_dns_set 10.7.21.230 10.7.21.230`), `networksetup -getdnsservers Wi-Fi`, DNS window running?                           |
| 2 TCP  | `nc -vz -G 3 app.zeronetwork.test 443`                                                                       | `succeeded`              | nginx stopped, wrong port, pf                               | MAC-2: `pgrep nginx`, `nginx -t`, start nginx; `sudo pfctl -sr`                                                                                 |
| 3 TLS  | `openssl s_client -connect app.zeronetwork.test:443 -servername app.zeronetwork.test -CAfile $CA </dev/null` | `Verify return code: 0`  | Wrong cert/key path, SAN mismatch, CA not trusted           | MAC-2 `ssl_certificate` lines; `openssl x509 -in … -noout -text`                                                                                 |
| 4 HTTP | `curl -v --cacert $CA https://app.zeronetwork.test/api/status`                                               | `200` with `x-backend` | 502/504: backends down or wrong upstream IP/port            | MAC-2: `tail $(brew --prefix)/var/log/nginx/zeronetwork_error.log`; `curl http://10.7.25.53:3001/health`, `curl http://10.7.23.141:3002/health` |

**Clue:** if everything is 200 but only one backend ever answers, one upstream is wrong (check `upstream` in `nginx.conf` and the error log).
After fixing: `zn_flush; for i in {1..4}; do zn_hit; done` to prove it is back.
Practice faults: [`runbook.md`](runbook.md) P2-F table, and [`troubleshooting.md`](troubleshooting.md).

---

## Step 11 — Individual viva · *Everyone*

Each member must explain any part from understanding, not notes. Prepare with [`../documentation/presentation-qa.md`](../documentation/presentation-qa.md).

| Member        | Be ready to explain in depth                                                                      | Plus everyone must know                                     |
| ------------- | ------------------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| Yash (MAC-1)  | dnsmasq, A records, TTL, NXDOMAIN, backup DNS, resolver order                                     | The full request path: DNS → TCP → TLS → HTTP → backend |
| Vansh (MAC-2) | nginx upstream, round robin, TLS termination, local CA, SAN/SNI, X-Forwarded-For, `max_fails`   | Why clients never need backend IPs                          |
| Swati (MAC-3) | Backend endpoints and headers, 0.0.0.0 binding, pf isolation and rollback, standby edge, cutover  | Drop (timeout) vs refuse                                    |
| Shyam (MAC-4) | Wireshark filters, TCP handshake, TLS handshake steps, caching (200/304, ETag), layered diagnosis | The single point of failure and how to remove it            |

---

## After the evaluation

▶ **ALL:** `sudo networksetup -setdnsservers Wi-Fi empty; zn_flush`
▶ **MAC-1, MAC-3:** Ctrl+C in DNS windows · **MAC-3, MAC-4:** Ctrl+C in BACKEND windows
▶ **MAC-2 (and MAC-3):** `nginx -s stop` · **MAC-3, MAC-4:** `sudo pfctl -f /etc/pf.conf`



Check DNS

dig app.zeronetwork.test +short

If empty or wrong IP: The fault is in DNS! (Wrong record or dnsmasq is stopped).

Check TCP port

nc -vz 10.7.21.230 443

If Connection Refused or Timeout: The fault is in Nginx / Network / Firewall!

Check TLS / Certificate

openssl s_client -connect 10.7.21.230:443 -servername app.zeronetwork.test

If verify error: The certificate or Root CA is broken!

Check Application / HTTP

curl -i https://app.zeronetwork.test/api/status

If 502 Bad Gateway: The backends (ports 3001/3002) are down!
