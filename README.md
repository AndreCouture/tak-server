# tak-server

OpenTAKServer (OTS) deployment for TAK Can — AWS (CloudFormation) and Synology NAS (Docker Compose).

Switched from FreeTAKServer 2.x to [OpenTAKServer](https://github.com/brian7704/OpenTAKServer) which is
actively maintained and has a cleaner architecture (PostgreSQL, RabbitMQ, proper nginx proxy, built-in CA).

## What's here

```
tak-server/
├── aws/
│   ├── cloudformation.yaml   # EC2 t3.small + OTS + MediaMTX + auto-stop Lambda
│   ├── deploy.sh             # CloudFormation deploy helper
│   └── setup-users.sh        # QR code generator (run on EC2 after deploy)
└── synology/
    └── docker-compose.yml    # OTS for Synology (clone upstream repo first)
```

---

## AWS Deploy

### Prerequisites
- AWS CLI configured
- Route 53 hosted zone for your domain
- An existing VPC + public subnet
- EC2 key pair

### Deploy

```bash
export TAK_KEY_PAIR=your-key-pair-name
export TAK_HOSTED_ZONE=Z1234567890ABC
export TAK_VPC_ID=vpc-xxxxxxxx
export TAK_SUBNET_ID=subnet-xxxxxxxx
export TAK_ALLOWED_IP=1.2.3.4/32   # your IP for SSH
export TAK_DOMAIN=tak.takaware.ca

cd aws && ./deploy.sh
```

The UserData script runs fully automated on first boot:

1. Installs Docker, git, qrencode
2. Clones [OpenTAKServer-Docker](https://github.com/brian7704/OpenTAKServer-Docker)
3. Writes `ots_config.env` with `OTS_FQDN` set to your domain and random DB password
4. Runs `docker compose up -d` — builds OTS + nginx images (~5-10 mins on first run)
5. Enables systemd auto-start on reboot
6. Generates client QR codes in `/opt/tak-server/clients/` once OTS is healthy

### First boot progress

The initial image build takes 5-10 minutes. Watch progress:

```bash
ssh ec2-user@tak.takaware.ca
sudo docker compose -f /opt/tak-server/docker-compose.yml logs -f
```

### Fetch QR codes after deploy

```bash
scp ec2-user@tak.takaware.ca:/opt/tak-server/clients/*.png .
```

Or regenerate at any time:

```bash
ssh ec2-user@tak.takaware.ca
sudo /opt/tak-server/setup-users.sh tak.takaware.ca
```

### Cost

| State   | Approx cost |
|---------|-------------|
| Running | ~$17/mo (t3.small) |
| Stopped | ~$2/mo (EBS + EIP) |

OTS requires t3.small (2GB RAM) — PostgreSQL + RabbitMQ + multiple Python services + nginx
won't fit reliably in t3.micro (1GB).

Stop/start:
```bash
aws ec2 stop-instances --instance-ids <InstanceId> --region ca-central-1
aws ec2 start-instances --instance-ids <InstanceId> --region ca-central-1
```

The auto-stop Lambda checks every 2 hours and stops the instance if NetworkIn < 1 MB.

---

## Synology Deploy

OTS requires the full upstream repo (nginx templates, rabbitmq config, etc.):

```bash
# SSH into the NAS
cd /volume1/docker
git clone https://github.com/brian7704/OpenTAKServer-Docker.git tak-server
cd tak-server

# Edit ots_config.env — set your NAS IP/hostname and a strong DB password
nano ots_config.env
# OTS_FQDN=192.168.1.x          ← your NAS IP or hostname
# POSTGRES_PASSWORD=changeme     ← use a strong password
# SQLALCHEMY_DATABASE_URI=postgresql+psycopg://ots:changeme@ots-db/ots

docker compose up -d
```

Via **Container Manager → Project → Create**: point to `/volume1/docker/tak-server`.

#### Synology — browser-trusted cert (optional)

OTS on Synology uses a self-signed cert by default. To get a trusted cert:

```bash
# Install certbot (choose your DNS provider plugin)
pip3 install certbot certbot-dns-route53   # Route53
# OR: pip3 install certbot certbot-dns-cloudflare  # Cloudflare, etc.

# Get cert
certbot certonly --dns-route53 --agree-tos --email you@example.com -d nas.yourdomain.com

# Patch nginx template and add include
sed -i 's|include includes.d/opentakserver_certificate;|include includes.d/letsencrypt_certificate;|' \
  ots/configs/nginx/templates/https-443.conf.template

cat > ots/configs/nginx/includes/letsencrypt_certificate << EOF
ssl_certificate     /etc/letsencrypt/live/nas.yourdomain.com/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/nas.yourdomain.com/privkey.pem;
EOF

# Add LE cert volume to nginx in docker-compose.override.yml
cat > docker-compose.override.yml << EOF
services:
  nginx-proxy:
    volumes:
      - /etc/letsencrypt:/etc/letsencrypt:ro
EOF

docker compose up -d --build nginx-proxy
```

---

## Admin Interfaces

### OTS Web Admin UI
**URL:** `https://tak.takaware.ca` (or `https://<NAS-IP>` for Synology)
**Default login:** `admin` / `password` — change this on first login.

**Certificates:** The AWS deploy automatically obtains a Let's Encrypt certificate for port 443
via Route53 DNS-01 challenge. Your browser will trust it with no warnings.
Ports 8443/8446 (TAK API) use the OTS self-signed CA — TAK clients (ATAK/WinTAK/iTAK) handle
this via the OTS data package which includes the CA cert.

From the Web UI you can:
- Create/manage users and assign roles
- Issue and revoke client certificates (for mutual TLS)
- Generate client data packages (`.zip`) for ATAK/WinTAK/iTAK import
- View connected devices and their tracks
- Manage missions and data layers

### MediaMTX Admin API
**URL:** `http://tak.takaware.ca:9997` (restricted to `AllowedIP` in security group)

MediaMTX doesn't have a graphical UI — management is via REST API:
```bash
# List active streams
curl http://tak.takaware.ca:9997/v3/paths/list

# List active HLS sessions
curl http://tak.takaware.ca:9997/v3/hlsmuxers/list
```

Full API reference: [MediaMTX API docs](https://github.com/bluenviron/mediamtx#api)

---

## Connect TAK Can

**Method 1 — QR Code** (easiest)
Scan `/opt/tak-server/clients/server-qr.png`

**Method 2 — Manual**
Settings → Server Information → Add Server
- Host: `tak.takaware.ca` (or NAS IP)
- Port: `8089`
- Protocol: TLS

**Method 3 — Client cert data package**
Download from OTS Web UI → Certificates → Generate client package

---

## Ports

| Port  | Protocol | Service                        |
|-------|----------|-------------------------------|
| 80    | HTTP     | Let's Encrypt / redirect       |
| 443   | HTTPS    | OTS Web Admin UI               |
| 8080  | HTTP     | OTS API (nginx proxy)          |
| 8088  | TCP      | CoT (unencrypted)              |
| 8089  | TCP+TLS  | CoT TLS                        |
| 8443  | HTTPS    | OTS HTTPS API (nginx proxy)    |
| 8446  | HTTPS    | CSR — client cert enrollment   |
| 8883  | MQTTS    | MQTT / Meshtastic              |
| 1935  | TCP      | RTMP video ingest              |
| 8554  | TCP      | RTSP video playback            |
| 8888  | TCP      | HLS video playback             |
| 8889  | TCP      | WebRTC video                   |
| 9997  | HTTP     | MediaMTX admin API (admin)     |
| 6969  | UDP      | CoT multicast (local SA)       |

---

## OTS Architecture

OTS runs as a stack of containers:

| Container           | Role                                      |
|---------------------|-------------------------------------------|
| `opentakserver`     | Main Flask API + CA management            |
| `ots_cot_parser`    | Parses CoT XML from RabbitMQ queue        |
| `ots_eud_handler`   | TCP CoT streaming (port 8088)             |
| `ots_eud_handler_ssl` | TLS CoT streaming (port 8089)           |
| `nginx-proxy`       | TLS termination + reverse proxy           |
| `ots-webui`         | React Web UI (served by nginx)            |
| `rabbitmq`          | Message broker between OTS components     |
| `mediamtx`          | Video streaming (RTMP/RTSP/HLS)           |
| `ots-db`            | PostgreSQL + PostGIS                      |
| `certbot`           | Let's Encrypt certificate management      |

OTS generates its own CA for TAK client certificates. The CA cert needs to be
imported into ATAK/WinTAK/iTAK as a trusted authority for mutual TLS to work.
Download it from the OTS Web UI → Certificates → CA Certificate.

---

## Troubleshooting

**Check all services are up:**
```bash
cd /opt/tak-server && docker compose ps
```

**Tail logs for a specific service:**
```bash
docker compose logs -f opentakserver
docker compose logs -f nginx-proxy
```

**OTS_FQDN wrong — clients connect but don't receive messages:**
```bash
grep OTS_FQDN /opt/tak-server/ots_config.env
# If wrong, update it and recreate the container:
docker compose up -d --force-recreate opentakserver
```
