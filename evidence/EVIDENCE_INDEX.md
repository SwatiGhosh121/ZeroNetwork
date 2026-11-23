# ZeroNetwork: Evidence Index

Team **ZeroNetwork** · domain `zeronetwork.test` · MAC-1 10.7.8.17 (DNS) · MAC-2 10.7.21.230 (edge) · MAC-3 10.7.25.53 (backend A, backup DNS, standby edge) · MAC-4 10.7.23.141 (backend B, client)

Every terminal prompt shows `[ZeroNetwork | MAC-X | IP] time`, so each screenshot shows which machine it came from and when.
Note: early MAC-4 shots (before 22:56) show the prompt label `10.3.3.166`. That was MAC-4's IP before it reconnected to Wi-Fi. The machine is the same, and its real IP in every test is 10.7.23.141.

## Phase 1: Build & Observe

| File | Task | What it proves |
|---|---|---|
| P1-A_01..04 | A, LAN | IP, mask /19 (255.255.224.0), gateway 10.7.0.1, MAC address; ping between every pair of Macs, 0% loss |
| P1-B_01_MAC-4_dig_via_MAC-1 | B, DNS | MAC-4 uses 10.7.8.17 as its resolver; `app.zeronetwork.test` resolves to 10.7.21.230, **TTL 30**, `SERVER: 10.7.8.17#53` |
| P1-B_02_MAC-1_dig_and_client_dns | B, DNS | Direct query to dnsmasq; upstream forwarding works (google.com resolves) |
| P1-C_01_MAC-1_backends_direct | C, backends | `/api/status` from A (3001) and B (3002); `X-Backend: A/B` headers; JSON identifies each backend |
| P1-DE_01_MAC-4_https_tls_verify | D + E | HTTPS by name, HTTP/2 and HTTP/1.1; `SSL certificate verify ok`; SAN match; issuer = ZeroNetwork Local Root CA; `Verify return code: 0`; backend sees the edge IP and `X-Forwarded-For` = client. (The `404` lines in this shot come from a broken helper alias, diagnosed and fixed. See the Phase 2 report.) |
| P1-F_01_MAC-4_caching_304 | F, caching | `Cache-Control: public, max-age=60` + ETag, then **304 Not Modified** from backend B *and* backend A (same ETag on both) |
| P1-G_01_wireshark_dns | G | DNS query/response, client port 50299 → 53/UDP, answer A 10.7.21.230 |
| P1-G_02_wireshark_tls_stream_cert | G | TCP SYN / SYN-ACK (SACK_PERM, TSecr=0) in the packet list; TLS ClientHello with SNI `app.zeronetwork.test`, ALPN h2; **server Certificate** (TLS 1.2 request) showing ZeroNetwork Local Root CA and the SANs |
| P1-G_03_wireshark_change_cipher_spec | G | Client Key Exchange + ChangeCipherSpec + Encrypted Handshake (TLS 1.2), ServerHello + CCS (TLS 1.3) between 10.7.23.141 and 10.7.21.230 |
| P1-G_04_wireshark_encrypted_appdata | G | TLS Application Data on 443 is unreadable (frame 36: 10.7.21.230:443 → 10.7.23.141:50303) |
| P1-G_05_wireshark_edge_to_backend_plain_http | G | Edge → backend leg on port 3002 is **plaintext HTTP** (`GET /api/status`, `X-Forwarded-For: 10.7.23.141`) because TLS terminates at nginx. Frames 387/449 show the `/api/status;` 404s from the helper bug. |
| P1-FAIL1_MAC-4_wrong_dns_server | Failure 1 | DNS server set to a non-DNS host: `no servers could be reached` |
| P1-FAIL2_MAC-4_record_points_to_wrong_ip | Failure 2 | Record → 10.7.25.53: name resolves, but port 443 is **refused** (nc, openssl and curl all fail), while the backend on that host still answers on 3001 |
| P1-FAIL4-5_MAC-4_502_and_wrong_port | Failures 4 and 5 | Both backends down: DNS + TLS ok, **HTTP/2 502** with `x-edge: MAC-2-primary`. Wrong port: 443 succeeds, 9443 refused, ping OK |
| (Failure 3) | One backend down | See P2-D_01: only B serves while A is stopped |

## Phase 2: Harden & Recover

| File | Extension | What it proves |
|---|---|---|
| P2-00_MAC-4_layer_diagnosis_502 | F, method | Layer-by-layer ladder: DNS ok, TCP 443 ok, TLS verify 0, **HTTP 502**, so the fault is at the application layer (backends were down) |
| P2-A1_MAC-3_backup_dns_config | A | Backup dnsmasq on MAC-3 with the same records; `syntax check OK` |
| P2-A3_MAC-4_both_dns_answer | A | Primary 10.7.8.17 **and** backup 10.7.25.53 both answer `app` → 10.7.21.230, TTL 30 |
| P2-A4_MAC-4_two_resolvers | A | Client resolver list: nameserver[0] 10.7.8.17, nameserver[1] 10.7.25.53 |
| P2-A6_MAC-4_resolution_with_two_resolvers | A | Resolution and HTTPS working with both resolvers configured |
| P2-A7_MAC-4_app_failure_dns_ok | A | Application failure vs DNS failure: name resolves, app returns 502 |
| P2-B1_MAC-4_ttl30 | B | TTL 30 on records from both servers |
| P2-B3_MAC-4_record_change | B | `api` record changed 10.7.21.230 → 10.7.25.53 and picked up by the client |
| P2-B4_MAC-4_manual_flush | B | `zn_flush` followed by fresh lookup |
| P2-C0 / C3 / C5 / C6 (MAC-1) | C | Before: direct backend access ok · rules applied: client gets `exit=28` timeouts on 3001/3002 · still served through the edge (A and B) · after rollback: direct access ok again |
| P2-E2_MAC-3_standby_ready_and_pf_rollback | C + E | pf rollback output on MAC-3 (`pf disabled`, rules removed); standby nginx `MAC-3-standby` answering with A and B |
| P2-D_01_MAC-4_failover_stream | D | Backend A stopped at 23:18:09: from 23:18:11 every request is still `200` via B. A was restarted at 23:18:11; nginx skipped it until its 10 s fail_timeout passed, then round robin resumed at 23:18:25 |
| P2-D_02_MAC-3_backendA_log | D | Backend A stop (23:18:09) and restart (23:18:11); normal traffic comes from 10.7.21.230 (the edge). Two `/health` lines from 10.7.8.17 are MAC-1's direct tests during Ext C |
| P2-D_03_MAC-2_edge_access_log | D | nginx log: `upstream=10.7.25.53:3001, 10.7.23.141:3002 upstream_status=502, 200`, i.e. a failed upstream retried on the healthy one. Earlier 502s when both were down |
| P2-E_01_MAC-4_dns_cutover_stream | E | DNS cutover: `edge=MAC-2-primary` until 23:22:02, then `edge=MAC-3-standby` from 23:22:05, with no failed request |
| P2-E_02_MAC-2_old_edge_log | E | Old edge's log: MAC-4's requests stop arriving at 23:22:02 |
