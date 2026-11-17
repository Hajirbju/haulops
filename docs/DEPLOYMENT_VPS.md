# Deployment HAULOPS di VPS sendiri

Alternatif dari `DEPLOYMENT.md` (Railway + Render + Supabase). Semua komponen berjalan di
satu server lewat Docker Compose.

```
Internet ──► Caddy (HTTPS otomatis) ──► nginx (frontend + proxy /api) ──► backend ──► Postgres
                 :80/:443                    container web             container server   container db
```

Hanya Caddy yang membuka port ke luar (80/443). Database tidak punya port publik.

## Syarat server

- Linux (Ubuntu 22.04/24.04 atau Debian 12) dengan akses **root/sudo** via SSH.
- Minimal 1 vCPU, 2 GB RAM, 20 GB disk.
- Docker Engine + plugin Compose v2.
- Port **80** dan **443** terbuka di firewall.
- (Disarankan) Domain/subdomain dengan DNS A record ke IP server, untuk HTTPS.

> Hosting bersama (shared hosting) atau panel yang tidak memberi akses Docker/root tidak
> cocok untuk panduan ini. Pastikan server berupa VPS.

## 1. Siapkan server

```bash
# Pasang Docker (Ubuntu/Debian)
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER      # keluar-masuk SSH agar berlaku

# Firewall (contoh dengan ufw)
sudo ufw allow OpenSSH && sudo ufw allow 80 && sudo ufw allow 443 && sudo ufw enable
```

## 2. Ambil kode

```bash
sudo mkdir -p /opt/haulops && sudo chown $USER /opt/haulops
git clone https://github.com/Hajirbju/haulops.git /opt/haulops
cd /opt/haulops
git checkout main        # produksi; pakai `staging` untuk server uji
```

Repo private: gunakan Deploy Key (read-only) atau Personal Access Token, jangan password akun.

## 3. Isi konfigurasi

```bash
cp deploy/.env.example deploy/.env
nano deploy/.env
```

| Variabel | Isi |
|---|---|
| `DOMAIN` | Domain untuk HTTPS (mis. `haulops.contoh.com`). Tanpa domain: biarkan `:80` (HTTP saja). |
| `POSTGRES_PASSWORD` | Acak & kuat: `openssl rand -hex 24` |
| `JWT_SECRET` | Acak minimal 32 karakter: `openssl rand -hex 32` |
| `ADMIN_PASSWORD` | Password admin pertama (hanya berlaku bila database masih kosong) |

`deploy/.env` sudah di-`.gitignore`. Jangan pernah di-commit.

Agar perintah `docker compose` berikutnya otomatis memakai file ini, jalankan sekali
(dan simpan di `~/.bashrc`):

```bash
export COMPOSE_FILE=docker-compose.prod.yml COMPOSE_ENV_FILES=deploy/.env
```

Setelah itu cukup `docker compose ps`, `docker compose logs -f server`, dan seterusnya
(perintah di bawah menuliskan opsinya lengkap, keduanya setara).

## 4. Jalankan

```bash
docker compose --env-file deploy/.env -f docker-compose.prod.yml up -d --build
docker compose -f docker-compose.prod.yml ps
```

Backend menjalankan `prisma migrate deploy` otomatis saat start, dan membuat akun admin
bila database kosong. Cek:

```bash
curl -i http://localhost/api/health          # harus 200
docker compose -f docker-compose.prod.yml logs -f server
```

Buka `https://DOMAIN` (atau `http://IP-SERVER` bila tanpa domain) dan login dengan
`ADMIN_USERNAME` / `ADMIN_PASSWORD`.

### Tanpa domain (hanya IP)

Let's Encrypt tidak menerbitkan sertifikat untuk alamat IP biasa, jadi `DOMAIN=:80` berarti
**HTTP tanpa enkripsi**: password dan token login terkirim polos. Pakai hanya untuk uji
atau jaringan tertutup. Untuk produksi, daftarkan subdomain dan isi `DOMAIN`.

## 5. Pindahkan data dari Supabase (opsional)

Lewati bagian ini jika memulai dari database kosong.

```bash
# Di mesin yang punya pg_dump, pakai URL koneksi langsung (port 5432) dari Supabase:
pg_dump "postgresql://postgres.[ref]:[password]@...:5432/postgres" \
  --no-owner --no-privileges --schema=public -f haulops-supabase.sql

# Salin ke VPS, lalu restore SEBELUM backend dijalankan pertama kali:
docker compose --env-file deploy/.env -f docker-compose.prod.yml up -d db
docker compose -f docker-compose.prod.yml exec -T db \
  psql -U haulops -d haulops < haulops-supabase.sql
docker compose --env-file deploy/.env -f docker-compose.prod.yml up -d --build
```

Jika tabel migrasi Prisma (`_prisma_migrations`) ikut terbawa, `migrate deploy` akan
menganggap skema sudah mutakhir. Verifikasi jumlah baris tabel utama sebelum mematikan
Supabase.

## 6. Update versi

```bash
cd /opt/haulops
git pull
docker compose --env-file deploy/.env -f docker-compose.prod.yml up -d --build
```

Migrasi database berjalan otomatis. Ambil backup dulu (bagian 7) sebelum update besar.

## 7. Backup & restore

```bash
sh deploy/backup.sh                     # hasil di deploy/backups/, 14 file terakhir disimpan

# Jadwal harian jam 02:00
( crontab -l 2>/dev/null; echo '0 2 * * * cd /opt/haulops && sh deploy/backup.sh >> /var/log/haulops-backup.log 2>&1' ) | crontab -

# Restore
gunzip -c deploy/backups/haulops-YYYYmmdd-HHMMSS.sql.gz | \
  docker compose -f docker-compose.prod.yml exec -T db psql -U haulops -d haulops
```

Salin folder `deploy/backups/` ke tempat lain (mesin berbeda/object storage) secara berkala;
backup di server yang sama tidak melindungi dari kerusakan server.

## 8. Operasional

| Tugas | Perintah |
|---|---|
| Status | `docker compose -f docker-compose.prod.yml ps` |
| Log backend | `docker compose -f docker-compose.prod.yml logs -f server` |
| Restart | `docker compose -f docker-compose.prod.yml restart` |
| Hentikan | `docker compose -f docker-compose.prod.yml down` (data tetap di volume) |

**Jangan** pakai `down -v`: itu menghapus volume database.

## 9. Cutover dari Railway/Render

1. Deploy di VPS dan uji lengkap (login, input rit, laporan) dengan database yang sudah
   dipindahkan.
2. Hentikan input di sistem lama, ambil dump terakhir, restore ke VPS.
3. Arahkan DNS ke VPS. Matikan layanan Railway/Render setelah beberapa hari stabil.
4. Simpan Supabase minimal beberapa minggu sebagai cadangan sebelum dihapus.
