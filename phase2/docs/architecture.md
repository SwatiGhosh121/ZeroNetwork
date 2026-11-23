# Phase 2 Architecture

Normal path: client → DNS (MAC-1, fallback MAC-3) → edge MAC-2 :443 → backend A :3001 / B :3002.
Edge migration path: change the A record to 10.7.25.53 → clients reach the standby edge on MAC-3, which proxies to the same backends.
Isolation: `pf` on MAC-3 and MAC-4 passes only 10.7.21.230 to ports 3001/3002 and drops everything else.
Configs: `../configs/`.
