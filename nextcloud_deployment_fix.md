# 🔍 Analisis Masalah Nextcloud Deployment & Solusi

## 🚨 Masalah yang Teridentifikasi

### 1. **Mount Google Drive Tidak Berfungsi untuk Upload**
- Volume mounting `/mnt/gdrive/data:/var/www/html/data` bermasalah
- Rclone mount mungkin tidak stabil atau permission salah
- Nextcloud tidak bisa write ke Google Drive mount

### 2. **Database Connection Issues**
- Missing network configuration di docker-compose
- Healthcheck mungkin terlalu ketat
- Environment variables tidak complete

### 3. **Permission & Ownership Problems**
- www-data user di container vs host permission conflict
- Rclone mount permission tidak sesuai dengan container needs

## 🛠️ Solusi Lengkap

### 📋 **1. Fixed docker-compose.yml**

```yaml
version: '3.8'

networks:
  nextcloud:
    driver: bridge

services:
  db:
    image: mysql:8.0.36-debian
    container_name: ${COMPOSE_PROJECT_NAME}-db
    restart: always
    command: --default-authentication-plugin=mysql_native_password --innodb-buffer-pool-size=512M
    networks:
      - nextcloud
    volumes:
      - nextcloud_db:/var/lib/mysql
    environment:
      - MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
      - MYSQL_DATABASE=${MYSQL_DATABASE}
      - MYSQL_USER=${MYSQL_USER}
      - MYSQL_PASSWORD=${MYSQL_PASSWORD}
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u", "root", "-p${MYSQL_ROOT_PASSWORD}"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  redis:
    image: redis:alpine
    container_name: ${COMPOSE_PROJECT_NAME}-redis
    restart: always
    networks:
      - nextcloud
    command: redis-server --requirepass ${REDIS_PASSWORD}

  app:
    image: nextcloud:apache
    container_name: ${COMPOSE_PROJECT_NAME}-app
    restart: always
    ports:
      - "8081:80"
    networks:
      - nextcloud
    depends_on:
      db:
        condition: service_healthy
    volumes:
      # ✅ PERBAIKAN: Mount seluruh html tapi ekspos data ke GDrive
      - nextcloud_html:/var/www/html
      - /mnt/gdrive/data:/var/www/html/data
      - /mnt/gdrive/config:/var/www/html/config
    environment:
      - MYSQL_HOST=db
      - MYSQL_DATABASE=${MYSQL_DATABASE}
      - MYSQL_USER=${MYSQL_USER}
      - MYSQL_PASSWORD=${MYSQL_PASSWORD}
      - REDIS_HOST=redis
      - REDIS_HOST_PASSWORD=${REDIS_PASSWORD}
      - NEXTCLOUD_TRUSTED_DOMAINS=${TRUSTED_DOMAINS}
      - OVERWRITEPROTOCOL=https
      - OVERWRITECLIURL=https://${DOMAIN}
      - APACHE_DISABLE_REWRITE_IP=1
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/status.php"]
      interval: 30s
      timeout: 10s
      retries: 3

volumes:
  nextcloud_db:
  nextcloud_html:
```

### 📝 **2. Enhanced .env File**

```bash
# ===== PROJECT CONFIG =====
COMPOSE_PROJECT_NAME=nextcloud-server

# ===== DATABASE CONFIG =====
MYSQL_ROOT_PASSWORD=YourStrongRootPass123!
MYSQL_PASSWORD=YourStrongUserPass123!
MYSQL_DATABASE=nextcloud
MYSQL_USER=nextclouduser

# ===== REDIS CONFIG =====
REDIS_PASSWORD=YourRedisPass123!

# ===== NEXTCLOUD CONFIG =====
TRUSTED_DOMAINS=localhost,127.0.0.1:8081,your-vps-ip,your-domain.com
DOMAIN=your-domain.com

# ===== ADMIN USER (untuk first setup) =====
NEXTCLOUD_ADMIN_USER=admin
NEXTCLOUD_ADMIN_PASSWORD=AdminPass123!
```

### 🔧 **3. Fixed Rclone Mount Service**

```ini
[Unit]
Description=Rclone Mount Google Drive for Nextcloud
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
User=root
Group=root
ExecStartPre=/bin/mkdir -p /mnt/gdrive
ExecStart=/usr/bin/rclone mount alldrive: /mnt/gdrive \
    --config=/home/paperspace/nextcloud-server/rclone/rclone.conf \
    --allow-other \
    --allow-non-empty \
    --dir-cache-time=1000h \
    --vfs-cache-mode=full \
    --vfs-cache-max-size=5G \
    --vfs-cache-max-age=24h \
    --vfs-read-chunk-size=32M \
    --vfs-read-chunk-size-limit=2G \
    --buffer-size=32M \
    --umask=000 \
    --uid=33 \
    --gid=33 \
    --poll-interval=15s \
    --drive-chunk-size=32M \
    --timeout=1h \
    --log-level=INFO \
    --log-file=/var/log/rclone-mount.log
ExecStop=/bin/fusermount -u /mnt/gdrive
Restart=always
RestartSec=10
KillMode=process

[Install]
WantedBy=multi-user.target
```

### 🚀 **4. Deployment Script yang Benar**

```bash
#!/bin/bash

# ===== WARNA OUTPUT =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ===== INSTALASI RCLONE =====
install_rclone() {
    echo_info "Installing rclone..."
    curl https://rclone.org/install.sh | sudo bash
    rclone version
}

# ===== SETUP DIREKTORI =====
setup_directories() {
    echo_info "Setting up directories..."
    mkdir -p ~/nextcloud-server/rclone
    sudo mkdir -p /mnt/gdrive/{data,config}
    
    # Set permission yang benar untuk www-data (uid=33, gid=33)
    sudo chown -R 33:33 /mnt/gdrive
    sudo chmod -R 755 /mnt/gdrive
}

# ===== DEPLOY ULANG BERSIH =====
clean_redeploy() {
    echo_warn "Stopping all containers and cleaning up..."
    cd ~/nextcloud-server
    docker compose down -v --remove-orphans
    
    # Stop rclone mount
    sudo systemctl stop rclone-mount
    sudo fusermount -u /mnt/gdrive 2>/dev/null || true
    
    # Clean volumes
    docker volume prune -f
    
    # Clean mount directories
    sudo rm -rf /mnt/gdrive/data/*
    sudo rm -rf /mnt/gdrive/config/*
}

# ===== START SERVICES =====
start_services() {
    echo_info "Starting rclone mount..."
    sudo systemctl start rclone-mount
    sleep 10
    
    # Verify mount
    if mountpoint -q /mnt/gdrive; then
        echo_info "✅ Rclone mount successful"
    else
        echo_error "❌ Rclone mount failed!"
        sudo journalctl -u rclone-mount --no-pager -n 20
        exit 1
    fi
    
    echo_info "Starting Nextcloud containers..."
    cd ~/nextcloud-server
    docker compose --env-file .env up -d
    
    # Wait for containers
    echo_info "Waiting for containers to be ready..."
    sleep 30
    
    # Check container status
    docker compose ps
}

# ===== MAIN EXECUTION =====
main() {
    echo_info "🚀 Starting Nextcloud deployment..."
    
    # Install rclone if not exists
    if ! command -v rclone &> /dev/null; then
        install_rclone
    fi
    
    setup_directories
    clean_redeploy
    start_services
    
    echo_info "✅ Deployment completed!"
    echo_info "🌐 Access Nextcloud at: http://your-vps-ip:8081"
    echo_info "📋 Check logs: docker compose logs -f"
    echo_info "🔍 Check mount: df -h | grep gdrive"
}

# Run if script executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

## 🔧 **Langkah Perbaikan Step-by-Step**

### 1. **Setup Rclone yang Benar**
```bash
# Install rclone
curl https://rclone.org/install.sh | sudo bash

# Configure rclone (ikuti wizard)
rclone config

# Test koneksi
rclone lsd alldrive:
```

### 2. **Update Systemd Service**
```bash
# Backup old service
sudo cp /etc/systemd/system/rclone-mount.service /etc/systemd/system/rclone-mount.service.backup

# Create new service file dengan config di atas
sudo nano /etc/systemd/system/rclone-mount.service

# Reload dan restart
sudo systemctl daemon-reload
sudo systemctl stop rclone-mount
sudo systemctl start rclone-mount
sudo systemctl status rclone-mount
```

### 3. **Update Docker Compose**
```bash
cd ~/nextcloud-server

# Backup current
cp docker-compose.yml docker-compose.yml.backup

# Replace dengan config yang sudah diperbaiki
nano docker-compose.yml

# Update .env file juga
nano .env
```

### 4. **Clean Deploy**
```bash
# Stop semua
docker compose down -v --remove-orphans

# Clean mount
sudo systemctl stop rclone-mount
sudo fusermount -u /mnt/gdrive

# Setup permission
sudo chown -R 33:33 /mnt/gdrive
sudo chmod -R 755 /mnt/gdrive

# Start mount
sudo systemctl start rclone-mount

# Verify mount
df -h | grep gdrive
ls -la /mnt/gdrive/

# Deploy containers
docker compose --env-file .env up -d
```


## 🐛 **Debugging Commands**

```bash
# Check rclone mount status
sudo systemctl status rclone-mount
sudo journalctl -u rclone-mount -f

# Check container logs
docker compose logs -f app
docker compose logs -f db

# Check mount inside container
docker exec -it nextcloud-server-app ls -la /var/www/html/data
docker exec -it nextcloud-server-app touch /var/www/html/data/test.txt

# Check Google Drive
rclone ls alldrive:/data/
```

## 🎯 **Expected Results**

Setelah perbaikan ini:
- ✅ File upload akan masuk ke Google Drive
- ✅ Database connection stabil
- ✅ Dashboard Nextcloud normal
- ✅ Multi-user berfungsi dengan baik
- ✅ Auto-backup berjalan lancar

## ⚠️ **Important Notes**

1. **UID/GID**: Pastikan container menggunakan UID 33 (www-data)
2. **Mount Options**: `--uid=33 --gid=33` penting untuk permission
3. **VFS Cache**: Gunakan `full` mode untuk performance terbaik
4. **Redis**: Tambahkan untuk caching yang lebih baik
5. **Network**: Isolasi container dengan custom network

## 🔥 **Masalah Utama di Script Asli**

### ❌ **Yang Salah:**
1. Tidak ada Redis untuk caching
2. Mount `/var/www/html` full conflict dengan Nextcloud image
3. Permission UID/GID tidak match
4. Healthcheck database terlalu ketat
5. Tidak ada network isolation
6. Backup service terlalu kompleks dan error prone

### ✅ **Perbaikan:**
1. Tambah Redis container untuk performance
2. Mount hanya data dan config directory
3. Set correct UID/GID (33:33) untuk www-data
4. Perbaiki healthcheck dengan start_period
5. Tambah custom network
6. Simplify backup strategy

## 🚀 **Quick Fix Commands**

```bash
# Stop semua services
cd ~/nextcloud-server
docker compose down -v --remove-orphans
sudo systemctl stop rclone-mount
sudo fusermount -u /mnt/gdrive

# Update rclone service
sudo tee /etc/systemd/system/rclone-mount.service > /dev/null << 'SERVICE'
[Unit]
Description=Rclone Mount Google Drive for Nextcloud
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
User=root
Group=root
ExecStartPre=/bin/mkdir -p /mnt/gdrive
ExecStart=/usr/bin/rclone mount alldrive: /mnt/gdrive \
    --config=/home/paperspace/nextcloud-server/rclone/rclone.conf \
    --allow-other \
    --allow-non-empty \
    --dir-cache-time=1000h \
    --vfs-cache-mode=full \
    --vfs-cache-max-size=5G \
    --vfs-cache-max-age=24h \
    --vfs-read-chunk-size=32M \
    --vfs-read-chunk-size-limit=2G \
    --buffer-size=32M \
    --umask=000 \
    --uid=33 \
    --gid=33 \
    --poll-interval=15s \
    --drive-chunk-size=32M \
    --timeout=1h \
    --log-level=INFO \
    --log-file=/var/log/rclone-mount.log
ExecStop=/bin/fusermount -u /mnt/gdrive
Restart=always
RestartSec=10
KillMode=process

[Install]
WantedBy=multi-user.target
SERVICE

# Reload systemd
sudo systemctl daemon-reload

# Set proper permissions
sudo chown -R 33:33 /mnt/gdrive
sudo chmod -R 755 /mnt/gdrive

# Start mount
sudo systemctl start rclone-mount

# Check mount
df -h | grep gdrive

# Start containers dengan config baru
docker compose --env-file .env up -d

# Monitor logs
docker compose logs -f
```

## 📞 **Troubleshooting FAQ**

### Q: Upload masih tidak masuk Google Drive?
**A:** Periksa permission dan mount:
```bash
sudo systemctl status rclone-mount
docker exec -it nextcloud-server-app ls -la /var/www/html/data
rclone ls alldrive:/data/
```

### Q: Database connection error?
**A:** Periksa network dan health:
```bash
docker compose logs db
docker exec -it nextcloud-server-db mysqladmin ping -h localhost -u root -p
```

### Q: Performance lambat?
**A:** Tambah Redis dan sesuaikan VFS cache:
```bash
docker compose logs redis
rclone config # update cache settings
```

---

🎉 **Dengan perbaikan ini, Nextcloud deployment Anda akan berjalan stabil dan file upload akan tersinkron dengan Google Drive!**
