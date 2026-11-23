# ZeroNetwork — Private Network Service Platform

## Computer Networks Course Project — Phase 1 (Build & Observe) and Phase 2 (Harden & Recover)

> **Core principle:** *"The application stays simple; the network is the project."*

---

# 1. Project Purpose & Overview

ZeroNetwork is a private service platform on four macOS workstations on one local network, with no cloud. It follows one client request through every layer:

1. A client opens `https://app.zeronetwork.test`.
2. MAC-1 resolves the name with `dnsmasq` (TTL 30 s).
3. The client opens a TCP connection and a TLS session to the edge on MAC-2, port 443.
4. nginx terminates TLS and round-robins across Backend A and Backend B.
5. The backend answers with `X-Backend`, `Cache-Control` and `ETag` headers.
6. Every layer is observed with `dig`, `nc`, `openssl`, `curl -v` and Wireshark.

The project uses the reserved `.test` namespace, so it can never clash with a real domain.

---

# 2. Team Organization & Machine Roles

| Machine | Team Member | Primary Role | Main Service | Port |
|---|---|---|---|---:|
| **MAC-1** | **Yash Agarwal** | Private DNS (primary) + client | `dnsmasq` | `53` |
| **MAC-2** | **Vansh Sharma** | Edge: TLS termination, reverse proxy, round-robin load balancer | `nginx` | `443` |
| **MAC-3** | **Swati Ghosh** | Backend A. Phase 2: backup DNS + standby edge | Python HTTP service | `3001` |
| **MAC-4** | **Shyam Verma** | Backend B + main test client + Wireshark capture | Python HTTP service | `3002` |

Team name: **ZeroNetwork**.

---

# 3. Final Network Inventory

| Machine | IP | Interface |
|---|---|---|
| MAC-1 | `10.7.8.17` | `en0` (Wi-Fi) |
| MAC-2 | `10.7.21.230` | `en0` |
| MAC-3 | `10.7.25.53` | `en0` |
| MAC-4 | `10.7.23.141` | `en0` |

Subnet `10.7.0.0/19` (mask `255.255.224.0`), gateway `10.7.0.1`.

Private records (TTL 30 s):

```text
app.zeronetwork.test  ->  10.7.21.230
api.zeronetwork.test  ->  10.7.21.230
```

---

# 4. Final Architecture

> Full diagram set (including Phase 2 failover, isolation, cutover and troubleshooting): [`docs/diagrams/README.md`](docs/diagrams/README.md)

## 4.1 Network topology

```mermaid
flowchart TB
    subgraph LAN["Private Wi-Fi LAN · 10.7.0.0/19 · gateway 10.7.0.1"]
        direction TB
        C["💻 MAC-4 · Client<br/>Shyam Verma<br/>10.7.23.141"]
        DNS1["🧭 MAC-1 · Primary DNS<br/>Yash Agarwal<br/>10.7.8.17 · dnsmasq :53"]
        DNS2["🧭 MAC-3 · Backup DNS<br/>Swati Ghosh<br/>10.7.25.53 · dnsmasq :53"]
        EDGE["🔒 MAC-2 · Edge<br/>Vansh Sharma<br/>10.7.21.230 · nginx :443<br/>TLS termination + round robin"]
        A["⚙️ MAC-3 · Backend A<br/>10.7.25.53:3001"]
        B["⚙️ MAC-4 · Backend B<br/>10.7.23.141:3002"]
    end

    C -- "1 · DNS query UDP 53" --> DNS1
    C -. "fallback UDP 53" .-> DNS2
    C == "2 · HTTPS TCP 443" ==> EDGE
    EDGE -- "3 · HTTP 3001" --> A
    EDGE -- "3 · HTTP 3002" --> B

    classDef client fill:#e8f1ff,stroke:#2f6fdb,color:#0b2a5b
    classDef dns fill:#fff4e0,stroke:#d98a00,color:#5a3a00
    classDef edge fill:#e9f9ee,stroke:#1f9d55,color:#0c3d22
    classDef be fill:#f3ecff,stroke:#7b4fd6,color:#2e1a5c
    class C client
    class DNS1,DNS2 dns
    class EDGE edge
    class A,B be
```

Only the edge knows where the backends are. In Phase 2 a `pf` firewall makes the edge the only host allowed to reach ports 3001 and 3002.

## 4.2 End-to-end request flow

```mermaid
sequenceDiagram
    autonumber
    participant C as MAC-4 Client
    participant D as MAC-1 DNS
    participant E as MAC-2 Edge (nginx)
    participant A as MAC-3 Backend A
    participant B as MAC-4 Backend B

    C->>D: DNS query A app.zeronetwork.test (UDP 53)
    D-->>C: 10.7.21.230, TTL 30
    C->>E: TCP SYN :443
    E-->>C: SYN-ACK
    C->>E: ACK
    C->>E: TLS ClientHello (SNI app.zeronetwork.test, ALPN h2)
    E-->>C: ServerHello, Certificate (ZeroNetwork Local Root CA), Finished
    C->>E: Finished, then GET /api/status over HTTP/2 (encrypted)
    alt round robin → A
        E->>A: GET /api/status (HTTP/1.1, X-Forwarded-For 10.7.23.141)
        A-->>E: 200 X-Backend A
    else round robin → B
        E->>B: GET /api/status (HTTP/1.1, X-Forwarded-For 10.7.23.141)
        B-->>E: 200 X-Backend B
    end
    E-->>C: 200 + X-Backend, X-Edge, Cache-Control, ETag
```

## 4.3 Protocol layers per leg

```mermaid
flowchart LR
    subgraph L1["Client → Edge (port 443)"]
        direction TB
        h2["HTTP/2"] --> tls["TLS 1.3 / 1.2"] --> tcp1["TCP"] --> ip1["IPv4"] --> wifi1["Wi-Fi 802.11"]
    end
    subgraph L2["Edge → Backend (3001 / 3002)"]
        direction TB
        h1["HTTP/1.1 plaintext"] --> tcp2["TCP"] --> ip2["IPv4"] --> wifi2["Wi-Fi 802.11"]
    end
    subgraph L0["Client → DNS (port 53)"]
        direction TB
        dns["DNS"] --> udp["UDP"] --> ip0["IPv4"] --> wifi0["Wi-Fi 802.11"]
    end
    L1 -- "TLS terminates at nginx" --> L2
```

### One request, layer by layer

| # | Layer | From → to | Port | What happens |
|---|---|---|---:|---|
| 1 | DNS (UDP) | MAC-4 → MAC-1 | 53 | `app.zeronetwork.test` → `10.7.21.230`, TTL 30 |
| 2 | TCP | MAC-4 → MAC-2 | 443 | SYN, SYN-ACK, ACK |
| 3 | TLS | MAC-4 ↔ MAC-2 | 443 | ClientHello (SNI) → ServerHello → Certificate → Finished |
| 4 | HTTP/2, encrypted | MAC-4 → MAC-2 | 443 | `GET /api/status`, unreadable on the wire |
| 5 | HTTP/1.1, plaintext | MAC-2 → MAC-3 / MAC-4 | 3001 / 3002 | Round robin + `X-Forwarded-For` |
| 6 | Response | backend → edge → client | | `X-Backend`, `X-Edge`, `Cache-Control`, `ETag` |

---

# 5. Deliverables

Everything the project document asks for is indexed, with the marks mapping and demo sequence, in **[`DELIVERABLES.md`](DELIVERABLES.md)**.

---

# 6. Repository Structure

```text
backend-a/, backend-b/     REST backend (Python standard library only)
dns/                       dnsmasq config + A records
edge/                      nginx reverse proxy / load balancer / TLS config
tls/                       OpenSSL configs for the local CA and server certificate
tests/                     Verification scripts (DNS, HTTPS, load balancing, caching, failure, failover)
docs/                      Runbook, setup guide, topology, architecture, troubleshooting
docs/diagrams/             All architecture diagrams (Mermaid)
docs/demo-runbook.md       Final demonstration runbook (11 steps, who runs what)
phase2/                    Extensions A–F: configs, docs, evidence summary
evidence/                  Screenshots organised by task (see evidence/EVIDENCE_INDEX.md)
DELIVERABLES.md            Section 9 deliverables index, marks map, demo sequence
documentation/             Presentation Q&A, video script, project videos
```

---

# 7. Quick Start

```bash
# MAC-3
python3 backend-a/server.py A 3001
# MAC-4
python3 backend-b/server.py B 3002
# Any client Mac, after DNS and the CA are set up (see docs/setup-guide.md)
bash tests/run-all-tests.sh
```

Full ordered commands for every Mac: [`docs/runbook.md`](docs/runbook.md). **Final 11-step demo:** [`docs/demo-runbook.md`](docs/demo-runbook.md). Condensed guide: [`docs/setup-guide.md`](docs/setup-guide.md).

---

# 8. Phase 2 Extensions

```mermaid
flowchart TB
    C["💻 Client MAC-4<br/>resolvers: 10.7.8.17, 10.7.25.53"]
    subgraph DNSL["Ext A + B · DNS resilience · TTL 30"]
        D1["MAC-1 Primary DNS<br/>10.7.8.17"]
        D2["MAC-3 Backup DNS<br/>10.7.25.53"]
    end
    subgraph EDGEL["Ext E · Edge migration"]
        E1["MAC-2 Primary edge<br/>10.7.21.230 :443"]
        E2["MAC-3 Standby edge<br/>10.7.25.53 :443"]
    end
    subgraph BEL["Ext C · pf: only edges may connect · Ext D · failover"]
        A["MAC-3 Backend A :3001"]
        B["MAC-4 Backend B :3002"]
    end
    C --> D1
    C -.->|fallback| D2
    C ==>|"app → 10.7.21.230 (normal)"| E1
    C -.->|"app → 10.7.25.53 (after cutover)"| E2
    E1 --> A & B
    E2 --> A & B
```

| Ext | What | Result |
|---|---|---|
| A | Backup DNS on MAC-3 | Both resolvers answer; client lists both |
| B | TTL 30 s | A record change reaches clients within one TTL, or at once after a cache flush |
| C | Backend isolation with `pf` | Direct client access times out (exit 28); the edge still works; rollback restores access |
| D | Health-checked failover | Backend A stopped mid-stream: 0 failed requests, retried on B |
| E | DNS-based edge migration | Traffic moved from MAC-2 to the standby on MAC-3 in 3 s, with no failed request |
| F | Layered troubleshooting method | DNS → TCP → TLS → HTTP; the first failing layer is the fault |

Details: [`phase2/docs/phase2-final-report.md`](phase2/docs/phase2-final-report.md).

---

# 9. Evidence

Every screenshot's prompt shows `[ZeroNetwork | MAC-X | IP] time`. Index: [`evidence/EVIDENCE_INDEX.md`](evidence/EVIDENCE_INDEX.md).

| Task | Folder |
|---|---|
| A: LAN + connectivity | `evidence/task-a/` |
| B: Private DNS | `evidence/task-b/` |
| C: Backends | `evidence/task-c/` |
| D: Load balancing | `evidence/task-d/` |
| E: HTTPS / TLS | `evidence/task-e/` |
| F: HTTP caching (304) | `evidence/task-f/` |
| G: Wireshark | `evidence/task-g/` |
| Failure scenarios | `evidence/failures/` |
| Phase 2 | `evidence/phase2/` |

---

# 10. Presentation & Video

- **Project Demonstration & Presentation Videos:** [Google Drive Link](https://drive.google.com/drive/search?q=CN)
- 15-slide final presentation; likely questions and answers per slide: [`documentation/presentation-qa.md`](documentation/presentation-qa.md)
- Narrated project video script: [`documentation/video-script.md`](documentation/video-script.md)

---

# 11. Security Note

Private keys (`*.key`) and certificates are not committed. Generate them with the commands in [`tls/README.md`](tls/README.md).
