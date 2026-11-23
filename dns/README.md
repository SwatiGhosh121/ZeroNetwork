# DNS (MAC-1 primary, MAC-3 backup)

```bash
brew install dnsmasq
cp dns/dnsmasq.conf.example /opt/homebrew/etc/dnsmasq.d/zeronetwork.conf
cp dns/zeronetwork.hosts    /opt/homebrew/etc/dnsmasq.d/zeronetwork.hosts
sudo /opt/homebrew/sbin/dnsmasq --keep-in-foreground --conf-file=/opt/homebrew/etc/dnsmasq.d/zeronetwork.conf --log-facility=-
```
`local-ttl=30` gives every record a 30 s TTL. The backup server on MAC-3 uses `phase2/configs/backup-dns.conf` with the same records. If dnsmasq says "Address already in use", run `sudo pkill dnsmasq` first. After a record change, send `SIGHUP` or restart dnsmasq.
