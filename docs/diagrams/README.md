# ZeroNetwork — Architecture Diagrams

All diagrams are Mermaid, so GitHub renders them directly.

| # | Diagram | Shows |
|---|---|---|
| 1 | [Network topology](#1-network-topology) | Four Macs, roles, IPs, ports |
| 2 | [Request flow](#2-end-to-end-request-flow) | DNS → TCP → TLS → HTTP → backend |
| 3 | [TLS handshake](#3-tls-handshake-task-e) | ClientHello → Finished, trust chain |
| 4 | [Load balancing](#4-round-robin-load-balancing-task-d) | Round robin across A and B |
| 5 | [HTTP caching](#5-http-caching-task-f) | Fresh hit, conditional 304, full 200 |
| 6 | [Phase 2 architecture](#6-phase-2-architecture) | Backup DNS, standby edge, firewall |
| 7 | [DNS failover + TTL](#7-backup-dns-and-ttl-ext-a--b) | Primary down, record change |
| 8 | [Service isolation](#8-service-isolation-ext-c) | pf rules on MAC-3 and MAC-4 |
| 9 | [Backend failover](#9-backend-failover-ext-d) | Backend A stopped, zero failures |
| 10 | [Edge cutover](#10-dns-based-edge-cutover-ext-e) | MAC-2 → MAC-3 via DNS |
| 11 | [Troubleshooting ladder](#11-troubleshooting-ladder-ext-f) | DNS → TCP → TLS → HTTP |

---

## 1. Network topology

```mermaid
flowchart TB
    subgraph LAN["Private Wi-Fi LAN · 10.7.0.0/19 · gateway 10.7.0.1"]
        C["💻 MAC-4 · Client + Wireshark<br/>Shyam Verma · 10.7.23.141"]
        DNS1["🧭 MAC-1 · Primary DNS<br/>Yash Agarwal · 10.7.8.17 :53"]
        DNS2["🧭 MAC-3 · Backup DNS<br/>Swati Ghosh · 10.7.25.53 :53"]
        EDGE["🔒 MAC-2 · Edge nginx<br/>Vansh Sharma · 10.7.21.230 :443"]
        A["⚙️ MAC-3 · Backend A<br/>10.7.25.53 :3001"]
        B["⚙️ MAC-4 · Backend B<br/>10.7.23.141 :3002"]
    end
    C -- "DNS UDP 53" --> DNS1
    C -. "fallback" .-> DNS2
    C == "HTTPS 443" ==> EDGE
    EDGE -- "HTTP 3001" --> A
    EDGE -- "HTTP 3002" --> B
```

| Machine | Member | IP | Services |
|---|---|---|---|
| MAC-1 | Yash Agarwal | 10.7.8.17 | dnsmasq :53 |
| MAC-2 | Vansh Sharma | 10.7.21.230 | nginx :443 |
| MAC-3 | Swati Ghosh | 10.7.25.53 | backend A :3001, backup DNS :53, standby nginx :443 |
| MAC-4 | Shyam Verma | 10.7.23.141 | backend B :3002, client, Wireshark |

## 2. End-to-end request flow

```mermaid
sequenceDiagram
    autonumber
    participant C as MAC-4 Client
    participant D as MAC-1 DNS
    participant E as MAC-2 Edge
    participant A as MAC-3 Backend A
    participant B as MAC-4 Backend B
    C->>D: A? app.zeronetwork.test (UDP 53)
    D-->>C: 10.7.21.230 TTL 30
    C->>E: SYN :443
    E-->>C: SYN-ACK
    C->>E: ACK
    C->>E: TLS handshake (SNI, ALPN h2)
    C->>E: GET /api/status (HTTP/2, encrypted)
    alt next upstream is A
        E->>A: GET /api/status (HTTP/1.1, X-Forwarded-For)
        A-->>E: 200 X-Backend A
    else next upstream is B
        E->>B: GET /api/status (HTTP/1.1, X-Forwarded-For)
        B-->>E: 200 X-Backend B
    end
    E-->>C: 200 + X-Edge MAC-2-primary
```

## 3. TLS handshake (Task E)

```mermaid
sequenceDiagram
    participant C as Client (trusts ZeroNetwork CA)
    participant E as nginx on MAC-2
    C->>E: ClientHello (TLS 1.3, SNI app.zeronetwork.test, ALPN h2, key share)
    E-->>C: ServerHello (chosen cipher, key share)
    Note over C,E: From here TLS 1.3 encrypts the handshake
    E-->>C: Certificate (CN/SAN app + api.zeronetwork.test, issuer ZeroNetwork Local Root CA)
    E-->>C: CertificateVerify, Finished
    Note over C: Verify chain against local CA, check SAN = host → verify ok
    C->>E: Finished
    C->>E: Application Data (HTTP/2)
```

```mermaid
flowchart LR
    CA["ZeroNetwork Local Root CA<br/>ca.cnf · 4096-bit"] -- signs --> CERT["Server cert<br/>SAN app/api.zeronetwork.test"]
    CERT --> NGINX["nginx on MAC-2 :443"]
    CA -- "added to trust store" --> CLIENTS["Client Macs<br/>keychain + curl --cacert"]
```

## 4. Round-robin load balancing (Task D)

```mermaid
flowchart LR
    C["Client"] -->|req 1, 3, 5| E["nginx upstream<br/>zeronetwork_backends"]
    C -->|req 2, 4, 6| E
    E -->|1, 3, 5| A["Backend A<br/>X-Backend: A"]
    E -->|2, 4, 6| B["Backend B<br/>X-Backend: B"]
```

## 5. HTTP caching (Task F)

```mermaid
sequenceDiagram
    participant C as Client
    participant E as Edge → A or B
    C->>E: GET /api/cached
    E-->>C: 200, Cache-Control public max-age=60, ETag "zn-…"
    Note over C: Within 60 s: fresh hit, no request sent
    C->>E: GET /api/cached + If-None-Match "zn-…"
    E-->>C: 304 Not Modified (headers only)
    Note over C,E: Same body on A and B → same ETag → 304 from either backend
```

## 6. Phase 2 architecture

```mermaid
flowchart TB
    C["Client MAC-4<br/>resolvers 10.7.8.17, 10.7.25.53"]
    subgraph DNSL["Ext A + B · DNS"]
        D1["MAC-1 Primary"]
        D2["MAC-3 Backup"]
    end
    subgraph EDGEL["Ext E · Edges"]
        E1["MAC-2 primary :443"]
        E2["MAC-3 standby :443"]
    end
    subgraph BEL["Ext C + D · Backends"]
        A["Backend A :3001"]
        B["Backend B :3002"]
    end
    C --> D1
    C -.-> D2
    C ==> E1
    C -.->|after cutover| E2
    E1 --> A & B
    E2 --> A & B
```

## 7. Backup DNS and TTL (Ext A + B)

```mermaid
sequenceDiagram
    participant C as Client
    participant P as MAC-1 Primary
    participant S as MAC-3 Backup
    C->>P: A? app.zeronetwork.test
    P--xC: no answer (primary stopped)
    C->>S: A? app.zeronetwork.test
    S-->>C: 10.7.21.230 TTL 30
    Note over C: Record changed on the servers
    C->>C: cached answer used until TTL reaches 0 (≤ 30 s)
    C->>S: new query after expiry or zn_flush
    S-->>C: new address
```

## 8. Service isolation (Ext C)

```mermaid
flowchart LR
    EDGE["MAC-2 edge<br/>10.7.21.230"] -->|"pass in quick … from 10.7.21.230"| A["MAC-3 :3001"]
    EDGE -->|"pass"| B["MAC-4 :3002"]
    CL["MAC-1 client<br/>10.7.8.17"] -.-x|"block drop → timeout, exit 28"| A
    CL -.-x|"block drop"| B
    CL ==>|"HTTPS via edge → 200"| EDGE
```

Rollback: `sudo pfctl -f /etc/pf.conf` (rules were added to a copy, never to the original).

## 9. Backend failover (Ext D)

```mermaid
sequenceDiagram
    participant C as Client
    participant E as nginx
    participant A as Backend A
    participant B as Backend B
    Note over A: 23:18:09 A stopped
    C->>E: GET /api/status
    E->>A: try A
    A--xE: connection refused (502)
    E->>B: proxy_next_upstream → retry on B
    B-->>E: 200
    E-->>C: 200 X-Backend B (no error seen)
    Note over E: max_fails=1 → A marked down for fail_timeout 10 s
    C->>E: next requests
    E->>B: all go to B
    Note over A: 23:18:11 A restarted
    Note over E: 23:18:25 A tried again → round robin resumes
```

## 10. DNS-based edge cutover (Ext E)

```mermaid
sequenceDiagram
    participant C as Client
    participant D as DNS
    participant P as MAC-2 primary edge
    participant S as MAC-3 standby edge
    C->>D: A? app → 10.7.21.230
    C->>P: requests (edge=MAC-2-primary) … last at 23:22:02
    Note over D: record changed to 10.7.25.53
    C->>D: fresh lookup (flush / TTL expiry)
    D-->>C: 10.7.25.53
    C->>S: requests (edge=MAC-3-standby) from 23:22:05
    Note over C,S: 3 s switch, 0 failed requests. Clients with a cached answer stay on MAC-2 until their TTL expires.
```

## 11. Troubleshooting ladder (Ext F)

```mermaid
flowchart TD
    S(["Service not working"]) --> D{"1 · DNS<br/>dig +short app.zeronetwork.test"}
    D -- "empty / wrong IP" --> DF["Fix resolver or record<br/>networksetup, dnsmasq, flush"]
    D -- "10.7.21.230" --> T{"2 · TCP<br/>nc -vz app.zeronetwork.test 443"}
    T -- "refused / timeout" --> TF["Nothing listening or firewall<br/>check nginx, port, pf"]
    T -- "succeeded" --> L{"3 · TLS<br/>openssl s_client … -CAfile CA"}
    L -- "verify ≠ 0" --> LF["Certificate / SAN / trust<br/>reissue or trust CA"]
    L -- "verify 0" --> H{"4 · HTTP<br/>curl -v --cacert CA"}
    H -- "502 / 504" --> HF["Backends behind the edge<br/>restart, check upstream IPs"]
    H -- "200" --> OK(["Working ✔"])
```
