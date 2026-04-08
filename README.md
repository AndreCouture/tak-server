# tak-server

FreeTAKServer 2.x deployment for TAK Can — AWS (CloudFormation) and Synology NAS (Docker Compose).

## What's here

```
tak-server/
├── aws/
│   ├── cloudformation.yaml   # EC2 t3.micro + FTS 2.x + MediaMTX + auto-stop Lambda
│   ├── deploy.sh             # CloudFormation deploy helper
│   └── setup-users.sh        # QR code generator (run on EC2 after deploy)
└── synology/
    └── docker-compose.yml    # FTS 2.x + MediaMTX for Synology Container Manager
```

## Key changes from older setup

The previous setup used `pip install FreeTAKServer` on a generic `python:3.13-slim` image.
**This no longer works with FTS 2.x.** Use the official image:

```yaml
image: freetakteam/freetakserver:latest
```

Also switched EC2 from `t4g.micro` (ARM64) to `t3.micro` (x86_64) — FTS 2.x does not
publish multi-arch images, so the ARM64 instance fails to start the container.

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
export TAK_ALLOWED_IP=1.2.3.4/32   # your IP for SSH + REST API
export TAK_DOMAIN=tak.takaware.ca

cd aws && ./deploy.sh
```

Or manually via the AWS console: CloudFormation → Create stack → Upload `aws/cloudformation.yaml`.

### Cost

| State   | Approx cost |
|---------|-------------|
| Running | ~$8/mo      |
| Stopped | ~$2/mo (EBS + EIP) |

Stop when not in use:
```bash
aws ec2 stop-instances --instance-ids <InstanceId> --region ca-central-1
aws ec2 start-instances --instance-ids <InstanceId> --region ca-central-1
```

The auto-stop Lambda checks every 2 hours and stops the instance if NetworkIn < 1 MB.

### After deploy — generate client QR codes

```bash
ssh ec2-user@tak.takaware.ca
sudo /opt/tak-server/setup-users.sh tak.takaware.ca

# Fetch QR PNGs to your Mac
scp ec2-user@tak.takaware.ca:/opt/tak-server/clients/*.png .
```

---

## Synology Deploy

1. Create `/docker/tak-server/` on your NAS
2. Copy `synology/docker-compose.yml` there
3. **Container Manager → Project → Create** → point to that folder → Deploy

Or via SSH:
```bash
cd /volume1/docker/tak-server
sudo docker-compose up -d
```

---

## Ports

| Port  | Protocol | Service                        |
|-------|----------|-------------------------------|
| 8087  | TCP      | CoT (unencrypted)              |
| 8089  | TCP+TLS  | CoT TLS                        |
| 8443  | HTTPS    | Marti API                      |
| 8446  | HTTPS    | CSR — client cert enrollment   |
| 19023 | HTTP     | FTS REST API (admin)           |
| 1935  | TCP      | RTMP video ingest              |
| 8554  | TCP      | RTSP video playback            |
| 8888  | TCP      | HLS video playback             |
| 6969  | UDP      | CoT multicast (local SA)       |

---

## Connect TAK Can

**Method 1 — QR Code** (easiest)
Scan the server QR from `/opt/tak-server/clients/server-qr.png`

**Method 2 — Manual**
Settings → Server Information → Add Server
- Host: `tak.takaware.ca` (or NAS IP)
- Port: `8089`
- Protocol: TLS

**Method 3 — Data Package**
Use the Marti API to generate and download a `.zip` data package, then import in TAK Can.

---

## FTS 2.x First Boot

On first start FTS writes `FTSData/FTSConfig.yaml`. Check container logs:
```bash
docker logs freetakserver
```

If you need to reconfigure, stop the container, edit `fts-data/FTSConfig.yaml`, and restart.
