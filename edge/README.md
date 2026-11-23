# Edge (MAC-2, 10.7.21.230:443)

`nginx.conf.example` has `__BREW__` and `__EDGE__` placeholders. Render it for the Mac, copy the certificate to `ssl/`, then:
```bash
nginx -t && brew services restart nginx
```
Features: TLS 1.2/1.3 with HTTP/2, round-robin upstream (`max_fails=1 fail_timeout=10s`), `proxy_next_upstream error timeout http_502 http_503 http_504`, `X-Forwarded-For`, and an `X-Edge` header so responses show which edge answered.
