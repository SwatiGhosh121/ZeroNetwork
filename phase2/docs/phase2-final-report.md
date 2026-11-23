# Phase 2 Final Report — ZeroNetwork

Team ZeroNetwork: Yash Agarwal (MAC-1), Vansh Sharma (MAC-2), Swati Ghosh (MAC-3), Shyam Verma (MAC-4).

## 1. What changed from Phase 1

| Component | Phase 1 | Phase 2 |
|---|---|---|
| DNS | Primary on MAC-1 only | Backup dnsmasq on MAC-3; client lists both resolvers |
| Records | TTL 30 | TTL 30 used to prove a record change spreads in one TTL |
| Backends | Reachable by anyone on the LAN | `pf` on MAC-3/MAC-4: only the edge reaches 3001/3002 |
| Edge | nginx round robin | Added `max_fails=1 fail_timeout=10s` + `proxy_next_upstream` |
| Edge availability | One edge (MAC-2) | Standby edge on MAC-3, reached by a DNS change |
| Method | Ad-hoc checks | Layered troubleshooting ladder (DNS, TCP, TLS, HTTP) |

Configs: [`../configs/`](../configs).

## 2. Resilience tests and results

| Ext | Procedure | Observation | Evidence |
|---|---|---|---|
| A Backup DNS | dnsmasq on MAC-3 with the same records | Both `10.7.8.17` and `10.7.25.53` answer `app` → 10.7.21.230, TTL 30 | `evidence/phase2/P2-A*` |
| B TTL | Change the `api` record to 10.7.25.53 | Reaches clients within one TTL, or at once after `zn_flush` | `P2-B*` |
| C Isolation | `pf` rules appended to a copy of `/etc/pf.conf` | Client gets `exit=28` to 3001/3002; edge still returns 200 from A and B; reloading `/etc/pf.conf` restores access | `P2-C*` |
| D HA failover | Stop backend A at 23:18:09 during a request stream | 0 failed requests; nginx retried on B (`upstream_status=502, 200`), skipped A for the 10 s fail_timeout, round robin resumed 23:18:25 | `P2-D*` |
| E Edge migration | Change the DNS record to the standby edge | Last MAC-2 response 23:22:02, first MAC-3 response 23:22:05 (3 s), no failed request | `P2-E*` |
| F Troubleshooting | Layered ladder | DNS ok, TCP ok, TLS verify 0, HTTP 502 locates a backend fault | `P2-00`, `P2-F_drill1` |

## 3. Troubleshooting findings

| Fault | Layer | Symptom | Fix |
|---|---|---|---|
| Wrong DNS server | DNS | `no servers could be reached` | Reset client DNS, flush cache |
| Record points to the wrong IP | TCP | Name resolves, port 443 refused | Correct the record, reload dnsmasq |
| Both backends down | HTTP | DNS/TCP/TLS ok, HTTP 502 | Restart backends |
| Wrong port | TCP | 443 ok, 9443 refused | Use 443 |
| Corrupted helper script | Client tooling | 404 only through the script | Remove the stray `;` |
| DHCP address changed | Network | Upstream unreachable | Update upstream and record |

## 4. Learning summary

- **Ext A, Backup DNS.** A second resolver removes DNS as a single point of failure: the client tries the first server and falls back to the second, and the two must hold identical records.
- **Ext B, TTL.** DNS changes are not instant; a resolver keeps the old answer until the TTL expires, so a short TTL (30 s) makes migrations quick at the cost of more queries, and a cache flush forces an immediate refresh.
- **Ext C, Service isolation.** A firewall rule that allows only the edge to reach the backends makes the edge the single controlled entry point. A dropped packet shows up as a timeout, a closed port as an immediate refusal.
- **Ext D, HA failover.** Passive health checks use the failed request as the signal: nginx retried on the healthy backend and avoided the dead one for `fail_timeout`, so the client saw no errors.
- **Ext E, Edge migration.** Moving the entry point by changing one DNS record needs no client change; clients that cached the old answer move after their TTL.
- **Ext F, Troubleshooting.** Checking DNS, TCP, TLS and HTTP in order isolates the faulty layer; the first failing step is the fault.

## 5. Remaining single points of failure

One active edge (fix: keepalived/VRRP or a managed load balancer), passive health checks (fix: active probes), DHCP addresses (fix: reservations), local CA (production: public or managed CA).
