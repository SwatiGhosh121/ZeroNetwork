# Student Deliverables Index (Section 9)

> Every piece of evidence can be found within 30 seconds from this table.

| Deliverable | Due at | Where it is |
|---|---|---|
| **Architecture Document** (topology diagram, machine roles and IP/service table, request-flow diagram per layer; updated for Phase 2) | Phase 1 + Phase 2 | [`docs/architecture.md`](docs/architecture.md), [`docs/network-topology.md`](docs/network-topology.md), [`phase2/docs/architecture.md`](phase2/docs/architecture.md), diagram in [`README.md`](README.md#4-final-architecture) |
| **Configuration Bundle** (dnsmasq, nginx Phase 1 + Phase 2, TLS setup notes, backend launch, firewall rules) | Phase 1 + Phase 2 | [`dns/`](dns), [`edge/`](edge), [`tls/README.md`](tls/README.md), [`backend-a/`](backend-a), [`backend-b/`](backend-b), [`phase2/configs/`](phase2/configs) |
| **Backend Source Code** (both backends + helper scripts) | Phase 1 | [`backend-a/server.py`](backend-a/server.py), [`backend-b/server.py`](backend-b/server.py), [`tests/`](tests) |
| **Evidence Folder** (dig, curl headers, Wireshark DNS/TCP/TLS, caching, all failure scenarios) | Phase 1 + Phase 2 | [`evidence/`](evidence), index in [`evidence/EVIDENCE_INDEX.md`](evidence/EVIDENCE_INDEX.md) |
| **Phase 1 Checkpoint** (live system, structured demo, every member can explain any component) | Phase 1 review | [`docs/runbook.md`](docs/runbook.md), [`tests/run-all-tests.sh`](tests/run-all-tests.sh), [`documentation/presentation-qa.md`](documentation/presentation-qa.md) |
| **Phase 2 Final Report** (what changed, resilience results, troubleshooting findings, learning summary) | Phase 2 review | [`phase2/docs/phase2-final-report.md`](phase2/docs/phase2-final-report.md) |
| **Final Presentation** (live demo in the Section 8 sequence, viva for every member) | Final evaluation | [`documentation/presentation-qa.md`](documentation/presentation-qa.md), script in [`documentation/video-script.md`](documentation/video-script.md), [Videos on Google Drive](https://drive.google.com/drive/search?q=CN) |

# Marks Breakdown → Evidence Map (Section 10)

## Review 1 (50 marks)

| Area | Marks | Evidence |
|---|---:|---|
| LAN Setup + Private DNS (Task A + B) | 10 | `evidence/task-a/`, `evidence/task-b/`, `dns/`, `tests/dns-test.sh` |
| HTTP/REST Backends + Reverse Proxy + Load Balancing (Task C + D) | 10 | `evidence/task-c/`, `evidence/task-d/`, `backend-a/`, `backend-b/`, `edge/`, `tests/load-balancing-test.sh` |
| HTTPS / TLS Correctness and Explanation (Task E) | 8 | `evidence/task-e/`, `tls/`, `tests/https-test.sh` |
| Packet Analysis and Protocol Flow (Task G) | 7 | `evidence/task-g/` (DNS, TCP handshake, TLS, encrypted vs plain, ports) |
| HTTP Caching and Transport Layer (Task F) | 5 | `evidence/task-f/`, `tests/caching-test.sh` |
| Individual Viva Phase 1 | 10 | `documentation/presentation-qa.md` |

## Review 2 (50 marks)

| Area | Marks | Evidence |
|---|---:|---|
| Resilience and HA Failover (Ext A, B, D) | 15 | `evidence/phase2/P2-A*`, `P2-B*`, `P2-D*`, `tests/failover-test.sh` |
| Service Isolation and Edge Migration (Ext C, E) | 10 | `evidence/phase2/P2-C*`, `P2-E*`, `phase2/configs/*firewall*`, `standby-nginx.conf` |
| Troubleshooting Challenge (Ext F) | 10 | `evidence/failures/`, `evidence/phase2/P2-00*`, `P2-F_drill1`, `docs/troubleshooting.md`, `tests/failure-tests.sh` |
| Final Report Quality and Documentation | 5 | `phase2/docs/phase2-final-report.md` |
| Individual Viva Phase 2 + Full System | 10 | `documentation/presentation-qa.md` |

# Section 8 Demo Sequence → Where to Show It

| Step | Show | Command / file |
|---|---|---|
| DNS | Name resolves via our server | `dig app.zeronetwork.test` |
| TCP / TLS | Strict TLS, no `-k` | `tests/https-test.sh` |
| Load balancing | A and B alternate | `tests/load-balancing-test.sh` |
| Caching | 200 then 304 | `tests/caching-test.sh` |
| Wireshark | DNS, TCP, TLS, encrypted vs plain | `evidence/task-g/` |
| Failover | Stop A, zero failures | `tests/failover-test.sh` |
| Isolation | Direct access dropped, edge works | `phase2/configs/*firewall*` |
| Edge migration | DNS cutover to standby | `phase2/configs/standby-nginx.conf` |
| Faculty fault | Layered diagnosis | `tests/failure-tests.sh` |
