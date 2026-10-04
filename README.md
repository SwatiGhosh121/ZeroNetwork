# Computer Networks Phase 1
## Multi-Machine Reverse Proxy and Load Balancing System

A Computer Networks project demonstrating a multi-machine client-server architecture using four macOS systems, Node.js, Express.js, and Nginx.

The project implements two backend servers behind an Nginx reverse proxy and demonstrates HTTP request routing, round-robin load balancing, backend identification, and backend failure behavior.

---

## Team Information

**Team Name:** ZeroNetwork 
**Section:** E

| Student Name | Enrollment Number |
|---|---|
| Yash Agarwal | 2401010511 |
| Vansh Sharma | 2401010495 |
| Shyam Verma | 2401010453 |
| Swati Ghosh | 2401010471 |

---

## Project Overview

The objective of this project is to understand how requests travel through a network and how reverse proxies and load balancers distribute traffic between multiple backend servers.

The system uses four separate Mac machines, each assigned a specific networking role.

The client sends HTTP requests to the Nginx server running on Mac 2. Nginx forwards requests to either Backend A on Mac 3 or Backend B on Mac 4.

Each backend exposes a basic HTTP endpoint and a status API to identify which server handled the request.

## Architecture

```text
                 Client
              (Mac 1 / Mac 4)
                    |
                    | HTTP Request
                    |
                    v
          Mac 2 — Nginx Server
             Reverse Proxy
             Port: 8080
                    |
             Load Balancer
                    |
           +--------+--------+
           |                 |
           v                 v
     Mac 3 — Backend A  Mac 4 — Backend B
        Port 3001          Port 3002
           |                 |
           v                 v
       Express.js        Express.js
           |                 |
           +--------+--------+
                    |
              HTTP Response
```

## Machine Configuration

| Machine | Role | Technology | Port |
|---|---|---|---|
| Mac 1 | Client / initial DNS setup role | macOS, curl | — |
| Mac 2 | Reverse Proxy and Load Balancer | Nginx | 8080 |
| Mac 3 | Backend Server A | Node.js, Express.js | 3001 |
| Mac 4 | Backend Server B | Node.js, Express.js | 3002 |

### Network Addresses

The actual LAN IP addresses should be recorded from the machines used during the demonstration.

| Machine | IP Address |
|---|---|
| Mac 1 | 10.7.5.166 |
| Mac 2 | 10.7.3.101 |
| Mac 3 | 10.7.6.207 |
| Mac 4 | 10.7.7.217 |

---

## Technologies Used

- macOS
- Node.js
- Express.js
- Nginx
- HTTP
- TCP/IP
- cURL
- Homebrew

---

## Implemented Features

### 1. Backend Server A

Backend A runs on Mac 3 using Express.js on port `3001`.

**Endpoint:**

```http
GET /
```

Response:

```text
Hello from Backend A
```

Status endpoint:

```http
GET /api/status
```

Response:

```json
{
  "backend": "A",
  "status": "healthy"
}
```

Response identification header:

```http
X-Backend: A
```

### 2. Backend Server B

Backend B runs on Mac 4 using Express.js on port `3002`.

**Endpoint:**

```http
GET /
```

Response:

```text
Hello from Backend B
```

Status endpoint:

```http
GET /api/status
```

Response:

```json
{
  "backend": "B",
  "status": "healthy"
}
```

Response identification header:

```http
X-Backend: B
```

### 3. Nginx Reverse Proxy

Nginx is configured on Mac 2 and listens on port `8080`.

It forwards incoming HTTP requests to the configured backend servers.

The upstream configuration uses:

- Backend A: Mac 3, port 3001
- Backend B: Mac 4, port 3002

### 4. Round-Robin Load Balancing

Nginx distributes requests across the two configured backend servers using its default round-robin upstream behavior.

The `X-Backend` response header allows us to identify which backend served each request.

### 5. Backend Status Verification

The `/api/status` endpoint provides a JSON response identifying the backend and its application status.

This allows the team to verify request routing through Nginx.

### 6. Backend Failure Demonstration

The failure-testing scenario involves stopping Backend A and sending requests through Nginx.

With the current basic upstream configuration, requests routed to the unavailable backend may return an HTTP `502 Bad Gateway` response, while requests routed to Backend B can still succeed.

This demonstrates the importance of backend availability and the limitations of basic load balancing without additional health-check and recovery mechanisms.

**Note:** The failure scenario should be marked as demonstrated only after recording the actual test output.

---

## Project Setup

### Prerequisites

Install the following on the relevant machines:

- Node.js
- npm
- Nginx
- Homebrew

### Backend A Setup — Mac 3

```bash
mkdir backend-a
cd backend-a
npm init -y
npm install express
```

Create `server.js` and configure the Express application to:

- Listen on port `3001`
- Bind to `0.0.0.0`
- Serve `/`
- Serve `/api/status`
- Return `X-Backend: A`

Start the application:

```bash
node server.js
```

### Backend B Setup — Mac 4

```bash
mkdir backend-b
cd backend-b
npm init -y
npm install express
```

Configure the Express application to:

- Listen on port `3002`
- Bind to `0.0.0.0`
- Serve `/`
- Serve `/api/status`
- Return `X-Backend: B`

Start the application:

```bash
node server.js
```

### Nginx Setup — Mac 2

Install Nginx:

```bash
brew install nginx
```

Check the installation:

```bash
nginx -v
```

Find the configuration file:

```bash
nginx -V 2>&1 | grep -- --conf-path
```

On the configured Mac 2 environment, the configuration path was:

```text
/opt/homebrew/etc/nginx/nginx.conf
```

The Nginx configuration uses an upstream named `backend_servers`, with the actual LAN addresses of Mac 3 and Mac 4 and their respective ports.

The server listens on port `8080` and proxies requests to the upstream.

Validate the configuration:

```bash
nginx -t
```

Start Nginx:

```bash
nginx
```

---

## Testing and Verification

### Test Backend A

```bash
curl http://localhost:3001/
```

```bash
curl http://localhost:3001/api/status
```

### Test Backend B

```bash
curl http://localhost:3002/
```

```bash
curl http://localhost:3002/api/status
```

### Test Nginx Locally

On Mac 2:

```bash
curl -i http://localhost:8080/
```

Repeat the request to observe backend identification.

### Test from a Client Machine

```bash
curl -i http://MAC2_IP:8080/
```

Replace `MAC2_IP` with the actual LAN IP address of Mac 2.

### Test the Status API Through Nginx

```bash
curl http://MAC2_IP:8080/api/status
```

The expected backend identifiers are:

```json
{"backend":"A","status":"healthy"}
```

```json
{"backend":"B","status":"healthy"}
```

### Verify Listening Ports

Backend A:

```bash
lsof -nP -iTCP:3001 -sTCP:LISTEN
```

Backend B:

```bash
lsof -nP -iTCP:3002 -sTCP:LISTEN
```

---

## Networking Concepts Demonstrated

- Client-server communication
- TCP/IP networking
- HTTP request-response cycle
- Reverse proxy
- Load balancing
- Round-robin request distribution
- Backend service identification
- Port-based communication
- Multi-machine LAN communication
- Backend availability and failure behavior

---

## Current Scope and Limitations

This repository documents the current Phase 1 implementation.

The following features are **not claimed as completed**:

- HTTPS/TLS termination
- Private DNS resolution using the custom project domain
- HTTP caching and cache validation
- Automated backend health checks
- Automatic failover or recovery

These features may be considered for subsequent project development after implementation and verification.

---

## Future Scope

- Configure private DNS and verify domain resolution.
- Implement HTTPS/TLS termination on Nginx.
- Configure and verify HTTP cache headers.
- Investigate backend health checks and recovery behavior.
- Capture network traffic using Wireshark or tcpdump.
- Collect additional evidence of request routing and failure behavior.

---

## Conclusion

The project establishes a multi-machine networking environment in which Nginx acts as a reverse proxy and distributes HTTP requests between two independent Express.js backend services.

It provides a practical demonstration of request forwarding, load balancing, backend identification, and the effect of backend unavailability.

The implementation helps connect core Computer Networks concepts with a real distributed service architecture.
