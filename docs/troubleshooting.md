# Troubleshooting: check the layers in order

| Step | Command | Failure means |
|---|---|---|
| 1 DNS | `dig +short app.zeronetwork.test` | Wrong or empty IP: record or resolver |
| 2 TCP | `nc -vz -G 3 app.zeronetwork.test 443` | Refused: nothing listening there |
| 3 TLS | `openssl s_client -connect app.zeronetwork.test:443 -servername app.zeronetwork.test -CAfile $CA` | Verify code ≠ 0: certificate or trust |
| 4 HTTP | `curl -v --cacert $CA https://app.zeronetwork.test/api/status` | 502: backends behind the edge |

`tests/failure-tests.sh` runs all four. The first failing layer is the fault.

| Fault found | Symptom | Fix |
|---|---|---|
| Wrong DNS server | `no servers could be reached` | Reset client DNS, flush cache |
| Record points to the wrong IP | Name resolves, 443 refused | Correct the record, reload dnsmasq |
| Both backends down | DNS, TCP, TLS fine; HTTP 502 | Restart backends |
| Wrong port | 443 succeeds, 9443 refused | Use 443 |
| Corrupted helper script | 404 only through the script | Remove the stray `;`, reload the shell |
| DHCP address changed | Upstream unreachable | Update the nginx upstream and DNS record |
