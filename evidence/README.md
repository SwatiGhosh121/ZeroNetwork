# Evidence Folder Index & Submission Checklist

> **Course requirement (Section 9):** the evaluator must be able to find any piece of evidence within 30 seconds.
> Full per-file explanations: [`EVIDENCE_INDEX.md`](EVIDENCE_INDEX.md).

| Machine | Role | IP |
|---|---|---|
| MAC-1 | Primary DNS + client | 10.7.8.17 |
| MAC-2 | Edge nginx + load balancer | 10.7.21.230 |
| MAC-3 | Backend A, backup DNS, standby edge | 10.7.25.53 |
| MAC-4 | Backend B + client + Wireshark | 10.7.23.141 |

| Evaluation task | Folder | Marks | Contents |
|---|---|---:|---|
| Task A: LAN | `task-a/` | 10 (with B) | IP, mask, gateway, MAC address; ping between every pair |
| Task B: DNS | `task-b/` | | `dig` via MAC-1, TTL 30, client resolver |
| Task C: Backends | `task-c/` | 10 (with D) | `/api/status` from A and B, `X-Backend` headers |
| Task D: Load balancer | `task-d/` | | Round robin A/B through the edge |
| Task E: HTTPS / TLS | `task-e/` | 8 | `curl -v`, SAN match, issuer, `Verify return code: 0` |
| Task F: HTTP caching | `task-f/` | 5 | `Cache-Control`, `ETag`, 304 from A and B |
| Task G: Wireshark | `task-g/` | 7 | DNS, TCP handshake, TLS handshake, encrypted vs plain HTTP |
| Failure scenarios | `failures/` | | Wrong DNS, wrong IP, both backends down, wrong port |
| Phase 2 | `phase2/` | 35 | Ext A–F: backup DNS, TTL, pf isolation, failover, cutover, diagnosis |

Every prompt shows `[ZeroNetwork | MAC-X | IP] time`, which identifies the machine and time of each screenshot.
