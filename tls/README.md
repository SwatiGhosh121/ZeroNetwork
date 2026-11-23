# TLS: local CA + server certificate

```bash
cd ~/zeronetwork-certs
openssl genrsa -out ZeroNetworkCA.key 4096
openssl req -x509 -new -key ZeroNetworkCA.key -sha256 -days 825 -config ca.cnf -out ZeroNetworkCA.crt
openssl genrsa -out zeronetwork.key 2048
openssl req -new -key zeronetwork.key -config server.cnf -out zeronetwork.csr
openssl x509 -req -in zeronetwork.csr -CA ZeroNetworkCA.crt -CAkey ZeroNetworkCA.key -CAcreateserial -days 397 -sha256 -extfile server.cnf -extensions v3_server -out zeronetwork.crt
openssl verify -CAfile ZeroNetworkCA.crt zeronetwork.crt
```
Copy `ca.cnf.example` and `server.cnf.example` to `ca.cnf` and `server.cnf`. The server certificate's SAN covers `app.zeronetwork.test` and `api.zeronetwork.test`. Trust the CA on the clients with `sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ZeroNetworkCA.crt`. macOS `curl` ignores the keychain, so pass `--cacert`. Never use `-k`. Keys are git-ignored.
