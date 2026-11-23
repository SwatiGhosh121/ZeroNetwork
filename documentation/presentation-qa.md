# Presentation Guide: what each slide says and likely questions

## Part 1: The network and the evidence

**1. Cover.** A client resolves a private name through our DNS, connects over HTTPS to our edge, and gets an answer from one of two backends.
- Why `.test`? Reserved TLD, can never clash with a real domain.
- Why no cloud? To learn each layer by building it.

**2. Topology.** MAC-1 DNS, MAC-2 edge, MAC-3 backend A (+ backup DNS, standby edge), MAC-4 backend B (+ client, capture). Only the edge knows the backends.
- Why only the edge? Clients never reach backends directly; isolation enforces it.
- Cloud equivalents? MAC-1 Route 53, MAC-2 ALB, MAC-3/4 EC2.

**3. One request, layer by layer.** DNS → TCP → TLS → HTTP/2 → plaintext HTTP/1.1 to the backend → response headers.
- Why is edge-to-backend plaintext? TLS terminates at nginx; that leg is a private LAN.
- IP vs Wi-Fi? IP moves each packet between hosts; Wi-Fi carries it one hop.

**4. LAN and private DNS.** 0% packet loss on 10.7.0.0/19; dnsmasq answers for `zeronetwork.test`; TTL 30; unknown names give NXDOMAIN.
- What is TTL? How long a resolver may cache an answer.
- Ping works but the name fails? DNS and connectivity are separate (wrong-DNS test).

**5. HTTPS and load balancing.** TLS 1.3, h2, SAN matched, issuer ZeroNetwork Local Root CA, verify ok, never `-k`. Requests alternate A, B, A, B. Backend sees the edge IP; `X-Forwarded-For` carries the client.
- SAN vs SNI? SAN lists names the certificate covers; SNI is the name the client sends in the ClientHello.

**6. Packet evidence.** Wireshark: DNS over UDP 53, TCP handshake, ClientHello with SNI, encrypted Application Data on 443, readable HTTP on 3002. TLS 1.3 encrypts the Certificate message, so one TLS 1.2 request was captured to show it.

**7. HTTP caching.** `Cache-Control: public, max-age=60` + ETag. `If-None-Match` returns 304 from either backend because the body and ETag are identical.
- max-age vs ETag? max-age says how long a copy is fresh; the ETag revalidates once it expires.

## Part 2: Resilience, isolation and cutover

**8. Phase 2 overview.** Backup DNS, TTL cutover, backend firewall, health-checked failover, standby edge. Nothing rebuilt.

**9. DNS resilience (Ext A/B).** Identical records on both servers, TTL 30, client lists both.
- Primary dies? Client falls back to the second server.
- DNS failure vs application failure? DNS down: nobody finds the service. App down: name resolves, edge returns 502.

**10. Failover (Ext D).** Backend A stopped at 23:18:09, 0 failed requests. nginx retried on B, skipped A for its 10 s fail_timeout, resumed round robin at 23:18:25. `max_fails=1 fail_timeout=10s` + `proxy_next_upstream`.
- Passive health checks? The failure itself is the signal; no probe.

**11. Isolation (Ext C).** `pf` lets only the edge reach 3001/3002. Client gets a timeout (exit 28), meaning dropped, not refused. Rollback = reload original `/etc/pf.conf`.

**12. Edge cutover (Ext E).** One DNS change moved traffic to the standby: 3 s from last MAC-2 response (23:22:02) to first MAC-3 response (23:22:05), no failed requests. Cached clients keep the old edge until their TTL expires.

**13. Diagnose.** `dig +short` → `nc -vz :443` → `openssl s_client` → `curl -v`. First failure is the fault. Faults found: wrong record, backends down (502), corrupted helper script (404), changed DHCP address.

**14. What's left.** Single active edge (fix: keepalived/VRRP or managed LB), passive health checks (fix: active probes), DHCP addresses (fix: reservations), local CA (production uses a public/managed CA).

**15. Questions.** All four IPs and roles on screen.

## Cross-cutting questions
- Who did what? Yash: DNS (MAC-1). Vansh: edge (MAC-2). Swati: backend A + backup DNS (MAC-3). Shyam: backend B + client + capture (MAC-4).
- Weakest point? The single edge on MAC-2; recovery is a DNS cutover to the standby.
- What would you change? Static IPs, active health checks, two edges.
