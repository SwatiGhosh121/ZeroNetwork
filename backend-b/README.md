# Backend B (MAC-4, 10.7.23.141:3002)

```bash
python3 server.py B 3002
```
Python standard library only. Binds `0.0.0.0`. Endpoints: `/`, `/api/status`, `/api/cached` (Cache-Control `max-age=60`, ETag, 304), `/health`. Every response carries `X-Backend: B`.
