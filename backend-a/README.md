# Backend A (MAC-3, 10.7.25.53:3001)

```bash
python3 server.py A 3001
```
Python standard library only. Binds `0.0.0.0`. Endpoints: `/`, `/api/status`, `/api/cached` (Cache-Control `max-age=60`, ETag, 304), `/health`. Every response carries `X-Backend: A`.
