# Architecture Document — Team ADMV

Private Network Service Platform · Phase 1

Four macOS laptops share one private LAN (`10.7.0.0/19`, gateway `10.7.0.1`).
Clients reach the service only by the name `app.admv.test`, which our own DNS server (Mac 1) resolves to the
nginx edge (Mac 2). The edge terminates TLS and load-balances across two REST backends (Mac 3, Mac 4).

## 1. Network topology

![Network topology](topology.png)

## 2. Machine inventory

| Machine | Member | Role | IPv4 | Prefix / Mask | Gateway | Interface | MAC address |
|---|---|---|---|---|---|---|---|
| Mac 1 | Vaibhav Vats | Private DNS server + test client | 10.7.21.200 | /19 (255.255.224.0) | 10.7.0.1 | en0 | `xx:xx:xx:xx:xx:xx` |
| Mac 2 | Mukul Kumar | Edge: reverse proxy + load balancer + TLS | 10.7.23.71 | /19 (255.255.224.0) | 10.7.0.1 | en0 | `xx:xx:xx:xx:xx:xx` |
| Mac 3 | Dikshant Jangra | Backend A | 10.7.18.160 | /19 (255.255.224.0) | 10.7.0.1 | en0 | `xx:xx:xx:xx:xx:xx` |
| Mac 4 | Ashish Kumar Yadav | Backend B + test client | 10.7.2.129 | /19 (255.255.224.0) | 10.7.0.1 | en0 | `xx:xx:xx:xx:xx:xx` |

Network: `10.7.0.0/19` covers 10.7.0.0 – 10.7.31.255 (8,190 usable hosts). All four Macs fall inside it, so they
communicate directly on the LAN without routing through another network.

## 3. Service map

| Machine | Service | Software | Protocol / Port | Listens on | Cloud equivalent |
|---|---|---|---|---|---|
| Mac 1 | Private DNS (authoritative for `admv.test`, forwarder for everything else) | dnsmasq | UDP + TCP 53 | 127.0.0.1, 10.7.21.200 | AWS Route 53 |
| Mac 2 | HTTP → HTTPS redirect | nginx | TCP 80 | all interfaces | Load balancer listener |
| Mac 2 | HTTPS edge, TLS termination, round-robin load balancing | nginx | TCP 443 | all interfaces | AWS ALB / CDN edge |
| Mac 3 | REST backend A (`X-Backend: A`) | Python `http.server` | TCP 3001 | 0.0.0.0 | EC2 instance A |
| Mac 4 | REST backend B (`X-Backend: B`) | Python `http.server` | TCP 3002 | 0.0.0.0 | EC2 instance B |

### DNS records

| Name | Type | Value | TTL |
|---|---|---|---|
| app.admv.test | A | 10.7.23.71 | 30 s |
| api.admv.test | A | 10.7.23.71 | 30 s |

## 4. Request flow

![Request flow](request-flow.png)

| # | Step | From → To | Protocol | Port |
|---|---|---|---|---|
| 1 | DNS query for `app.admv.test` | Client → Mac 1 | DNS over UDP | ephemeral → 53 |
| 2 | DNS answer `10.7.23.71`, TTL 30 s | Mac 1 → Client | DNS over UDP | 53 → ephemeral |
| 3 | TCP three-way handshake (SYN, SYN-ACK, ACK) | Client → Mac 2 | TCP | ephemeral → 443 |
| 4 | TLS handshake; certificate for `app.admv.test` signed by ADMV Local CA | Client ↔ Mac 2 | TLS 1.2 / 1.3 | 443 |
| 5 | `GET /api/status`, encrypted | Client → Mac 2 | HTTP/2 inside TLS | 443 |
| 6 | Request forwarded (round-robin), decrypted | Mac 2 → Mac 3 or Mac 4 | HTTP over TCP | ephemeral → 3001 / 3002 |
| 7 | Response with `X-Backend` header, re-encrypted to client | Mac 2 → Client | HTTP/2 inside TLS | 443 |

The client never learns the backend IPs: they exist only in the nginx `upstream` block on Mac 2.

## 5. Protocol-to-layer mapping

| Protocol / event | TCP/IP model | OSI model | Seen in Wireshark as |
|---|---|---|---|
| DNS | Application | Layer 7 | `dns` |
| HTTP/1.1, HTTP/2 | Application | Layer 7 | Encrypted on client side; `http` on edge → backend |
| TLS | Between Application and Transport | Layers 5–6 | `tls.handshake`, Application Data |
| TCP | Transport | Layer 4 | `tcp.flags.syn == 1`, seq/ack numbers |
| UDP | Transport | Layer 4 | `udp.port == 53` |
| IPv4 | Internet | Layer 3 | Source / destination IP |
| Wi-Fi (802.11), MAC addresses | Link | Layers 1–2 | Source / destination MAC |
