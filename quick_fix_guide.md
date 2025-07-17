# 🚀 Quick Fix Guide untuk Nextcloud Deployment

## 🎯 Langkah Cepat Perbaikan

### 1. **Download File yang Sudah Diperbaiki**
```bash
# Copy files dari fixed_configs ke direktori proyek
cp fixed_configs/docker-compose.yml ~/nextcloud-server/
cp fixed_configs/.env ~/nextcloud-server/
cp fixed_configs/deploy_nextcloud.sh ~/nextcloud-server/
chmod +x ~/nextcloud-server/deploy_nextcloud.sh
```

### 2. **Update Systemd Service**
```bash
# Copy dan install systemd service
sudo cp fixed_configs/rclone-mount.service /etc/systemd/system/
sudo systemctl daemon-reload
```

### 3. **Edit .env File dengan Info Anda**
```bash
cd ~/nextcloud-server
nano .env

# Update ini:
# - TRUSTED_DOMAINS=localhost,127.0.0.1:8081,YOUR_VPS_IP,YOUR_DOMAIN
# - DOMAIN=YOUR_DOMAIN
# - Ganti semua password dengan yang kuat
```

### 4. **Setup Rclone (Jika Belum)**
```bash
# Konfigurasi rclone untuk Google Drive
rclone config

# Pastikan nama remote = "alldrive"
# Test koneksi:
rclone lsd alldrive:
```

### 5. **Jalankan Deployment Otomatis**
```bash
cd ~/nextcloud-server
./deploy_nextcloud.sh full
```

## 🔧 Troubleshooting Manual

### Jika Upload Masih Tidak Masuk Google Drive:

1. **Cek Mount Status:**
```bash
sudo systemctl status rclone-mount
df -h | grep gdrive
ls -la /mnt/gdrive/
```

2. **Cek Permission dalam Container:**
```bash
docker exec -it nextcloud-server-app ls -la /var/www/html/data
docker exec -it nextcloud-server-app id www-data
```

3. **Test Upload Manual:**
```bash
# Test dari host
sudo touch /mnt/gdrive/data/test.txt
rclone ls alldrive:/data/

# Test dari container
docker exec -it nextcloud-server-app touch /var/www/html/data/container_test.txt
```

### Jika Database Error:

1. **Cek Logs:**
```bash
docker compose logs db
docker compose logs app
```

2. **Reset Database:**
```bash
docker compose down -v
docker volume prune -f
docker compose up -d
```

### Jika Container Tidak Start:

1. **Cek Resource:**
```bash
docker system df
docker system prune -f
```

2. **Start Step by Step:**
```bash
docker compose up db -d
sleep 30
docker compose up redis -d
sleep 10
docker compose up app -d
```

## 📋 Checklist Verifikasi

- [ ] ✅ Rclone mount active: `mountpoint -q /mnt/gdrive`
- [ ] ✅ Containers running: `docker compose ps`
- [ ] ✅ Nextcloud accessible: `curl http://localhost:8081/status.php`
- [ ] ✅ File upload works: Test via dashboard
- [ ] ✅ Files in Google Drive: `rclone ls alldrive:/data/`
- [ ] ✅ Database connected: No errors in logs
- [ ] ✅ Redis working: Check app logs

## 🆘 Emergency Reset

Jika semua gagal, reset complete:

```bash
# Stop semua
docker compose down -v --remove-orphans
sudo systemctl stop rclone-mount
sudo fusermount -u /mnt/gdrive

# Clean semua
docker system prune -a -f
sudo rm -rf /mnt/gdrive/*

# Start ulang
sudo systemctl start rclone-mount
sleep 10
sudo chown -R 33:33 /mnt/gdrive
docker compose --env-file .env up -d
```

---

🎉 **Dengan panduan ini, deployment Nextcloud Anda akan berjalan dengan sempurna!**
