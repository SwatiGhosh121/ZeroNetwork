# Network Topology and Addressing

| Machine | Role | IP | Listens on |
|---|---|---|---|
| MAC-1 | Primary DNS + client | 10.7.8.17 | UDP/TCP 53 |
| MAC-2 | Edge nginx | 10.7.21.230 | TCP 443 |
| MAC-3 | Backend A, backup DNS, standby edge | 10.7.25.53 | TCP 3001, UDP/TCP 53, 443 (standby) |
| MAC-4 | Backend B + client + capture | 10.7.23.141 | TCP 3002 |

Subnet 10.7.0.0/19 (255.255.224.0), gateway 10.7.0.1, one Wi-Fi segment. Every pair of Macs pings with 0% loss. IP moves each packet between hosts and Wi-Fi carries it one hop. Names: `app.zeronetwork.test` and `api.zeronetwork.test` both point at the edge.

Cloud equivalents: MAC-1 = Route 53, MAC-2 = application load balancer, MAC-3/4 = EC2 instances.
