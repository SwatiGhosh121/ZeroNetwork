# ZeroNetwork Architecture

See the diagram and layer table in the main [README](../README.md#4-final-architecture).

- **DNS (MAC-1, MAC-3):** dnsmasq, `local-ttl=30`. The client lists 10.7.8.17 first and 10.7.25.53 second.
- **Edge (MAC-2):** nginx terminates TLS (local CA, SAN match, TLS 1.2/1.3, ALPN h2) and proxies to the upstream group.
- **Backends (MAC-3, MAC-4):** identical Python services. `/api/cached` returns the same body on both, so the ETag matches and a conditional request gets 304 from either.
- **Why the edge-to-backend leg is plaintext:** TLS ends at nginx, on a private LAN. Wireshark shows 443 as encrypted Application Data and port 3002 as readable HTTP.
- **Isolation (Phase 2):** `pf` rules allow only 10.7.21.230 to reach 3001/3002.
- **Failover (Phase 2):** passive health checks, `max_fails=1 fail_timeout=10s`, plus `proxy_next_upstream`.
- **Edge migration (Phase 2):** changing the DNS record moves clients to the standby edge on MAC-3.

## Diagrams

All diagrams (topology, request flow, TLS, caching, Phase 2): [`diagrams/README.md`](diagrams/README.md).
