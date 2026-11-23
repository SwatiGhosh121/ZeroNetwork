# Setup Guide (condensed)

The full, ordered, per-Mac command list is [`runbook.md`](runbook.md). Order of work:

1. **All Macs:** confirm IP, mask /19, gateway; ping every other Mac.
2. **MAC-1:** install and start dnsmasq ([`dns/README.md`](../dns/README.md)).
3. **MAC-2:** create the CA and server certificate ([`tls/README.md`](../tls/README.md)), render and start nginx ([`edge/README.md`](../edge/README.md)).
4. **MAC-3 / MAC-4:** `python3 backend-a/server.py A 3001` and `python3 backend-b/server.py B 3002`.
5. **MAC-4 and MAC-1 (clients):** `sudo networksetup -setdnsservers Wi-Fi 10.7.8.17`, flush the cache, trust the CA.
6. **Verify:** `bash tests/run-all-tests.sh`.
7. **Capture:** Wireshark on MAC-4 for the DNS, TCP, TLS and plain-HTTP evidence.
8. **Phase 2:** see [`../phase2/docs/phase2-final-report.md`](../phase2/docs/phase2-final-report.md).
