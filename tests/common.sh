#!/bin/bash
# Shared settings for the ZeroNetwork test scripts.
DOMAIN="app.zeronetwork.test"
EDGE_IP="10.7.21.230"
DNS_PRIMARY="10.7.8.17"
DNS_BACKUP="10.7.25.53"
# Local CA. macOS curl ignores the keychain, so pass the CA explicitly (never use -k).
CA="${CA:-$HOME/zeronetwork-certs/ZeroNetworkCA.crt}"
