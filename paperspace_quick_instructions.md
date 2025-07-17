# 🚀 Paperspace Nextcloud Quick Fix

## 📋 **Current Status:**
Anda sedang di: `paperspace@ps073wxbfkog:~/nextcloud-server$`

## ⚡ **Quick Fix Steps:**

### 1. **Download Script Perbaikan**
```bash
# Download script fix khusus Paperspace
wget -O paperspace_fix.sh https://raw.githubusercontent.com/your-repo/main/paperspace_fix.sh
chmod +x paperspace_fix.sh

# ATAU copy dari files yang sudah ada di workspace
# cp /workspace/paperspace_fix.sh ~/nextcloud-server/
```

### 2. **Jalankan Perbaikan Lengkap**
```bash
cd ~/nextcloud-server
./paperspace_fix.sh full
```

**Script ini akan:**
- ✅ Setup rclone config otomatis dengan path yang benar
- ✅ Buat .env file dengan IP VPS otomatis
- ✅ Fix systemd service dengan path Paperspace
- ✅ Setup directory permissions
- ✅ Deploy Nextcloud lengkap

### 3. **Manual Setup Rclone (Jika Diperlukan)**
```bash
# Jika script meminta setup rclone:
./paperspace_fix.sh rclone

# Ikuti wizard rclone:
# 1. Pilih "n" untuk New remote
# 2. Nama remote: "alldrive"
# 3. Pilih Google Drive (nomor yang sesuai)
# 4. Ikuti OAuth flow
```

### 4. **Verifikasi & Deploy**
```bash
# Test semua komponen
./paperspace_fix.sh test

# Deploy jika test berhasil
./paperspace_fix.sh deploy
```

## 🔧 **Files yang Dibutuhkan di ~/nextcloud-server:**

```bash
paperspace@ps073wxbfkog:~/nextcloud-server$ ls -la
-rw-r--r-- 1 paperspace paperspace  xxx .env
-rwxr-xr-x 1 paperspace paperspace  xxx deploy_nextcloud.sh
-rw-r--r-- 1 paperspace paperspace  xxx docker-compose.yml
-rwxr-xr-x 1 paperspace paperspace  xxx paperspace_fix.sh
drwxr-xr-x 2 paperspace paperspace   xx rclone/
  └── rclone.conf
```

## 🎯 **Copy Files yang Sudah Diperbaiki:**

```bash
# Copy semua file yang sudah diperbaiki
cd ~/nextcloud-server

# Copy docker-compose.yml yang diperbaiki
cat > docker-compose.yml << 'EOF'
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
EOF

# Buat .env file
cat > .env << 'EOF'
COMPOSE_PROJECT_NAME=nextcloud-server
MYSQL_ROOT_PASSWORD=SecureRootPass123!
MYSQL_PASSWORD=SecureUserPass123!
MYSQL_DATABASE=nextcloud
MYSQL_USER=nextclouduser
REDIS_PASSWORD=SecureRedisPass123!
TRUSTED_DOMAINS=localhost,127.0.0.1:8081,your-paperspace-ip,your-domain.com
DOMAIN=your-domain.com
NEXTCLOUD_ADMIN_USER=admin
NEXTCLOUD_ADMIN_PASSWORD=AdminPass123!
EOF

# Update IP di .env
MY_IP=$(curl -s ifconfig.me)
sed -i "s/your-paperspace-ip/$MY_IP/g" .env
echo "✅ IP updated to: $MY_IP"
```

## 🚀 **One-Line Complete Fix:**

```bash
cd ~/nextcloud-server && curl -s https://raw.githubusercontent.com/your-repo/main/paperspace_fix.sh | bash -s full
```

## 🔍 **Debugging Commands:**

```bash
# Cek rclone config
cat ~/nextcloud-server/rclone/rclone.conf
rclone lsd alldrive: --config=~/nextcloud-server/rclone/rclone.conf

# Cek mount status
sudo systemctl status rclone-mount
df -h | grep gdrive

# Cek container status
docker compose ps
docker compose logs app

# Cek file upload test
docker exec -it nextcloud-server-app touch /var/www/html/data/test.txt
rclone ls alldrive:/data/ --config=~/nextcloud-server/rclone/rclone.conf
```

## 🎉 **Expected Final Result:**

- ✅ Rclone mount: `/mnt/gdrive` connected to Google Drive
- ✅ Containers: All running (db, redis, app)
- ✅ Access: `http://YOUR_PAPERSPACE_IP:8081`
- ✅ File uploads: Automatically sync to Google Drive
- ✅ Dashboard: No database errors

---

**🔥 Masalah utama di script asli: path hardcoded `/home/paperspace/` tidak sesuai dengan environment Paperspace yang dinamis. Script baru auto-detect path yang benar!**