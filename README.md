# STB Server Manager

**All-in-One Home Server Script** khusus STB (Set-Top Box) berbasis Armbian — dirancang untuk TV Box dengan chipset Amlogic S905 / S905X / S905W / S905X2 seperti B860H v1, HG680P, X96MINI, dan sejenisnya.

## Fitur

### 📦 Instalasi Layanan
| Fitur | Keterangan |
|---|---|
| **Update System** | `apt update && apt upgrade` + tools dasar (curl, wget, htop, git, dll) |
| **CasaOS** | OS dashboard berbasis web untuk管理 docker container dan file |
| **Portainer** | Manager Docker GUI di port **9000** |
| **Cockpit** | Web-based server admin panel di port **9090** |
| **Nginx + PHP** | Web server dengan PHP untuk hosting aplikasi web |

### ⚡ Optimasi STB
Script otomatis mendeteksi chipset STB dan menerapkan tweak spesifik:

| Menu | Target | Tweak |
|---|---|---|
| **Generic** | Semua STB | Swappiness=10, I/O scheduler mq-deadline, disable bluetooth/ModemManager, cron drop_caches |
| **B860H v1** | S905X | Performance governor, dirty_ratio tuning, Ethernet speed fix, NTP fix |
| **HG680P** | S905 (RAM rendah) | Ondemand governor, auto swap 2GB jika RAM < 1GB, aggressive dirty ratio |
| **X96MINI** | S905W | Performance governor, thermal threshold, ZRAM compression |

### 💾 Storage & Network
| Menu | Fitur | Detail |
|---|---|---|
| 10 | **Auto Mount HDD/SSD** | Deteksi partisi baru → mount otomatis → entry fstab. Opsi format ext4 jika gagal mount |
| 11 | **Pilih Storage Utama** | Pilih EMMC / SD Card / HDD/SSD sebagai primary storage. Format + mount ke `/mnt/storage` + subfolder `docker/`, `media/`, `downloads/`, `backup/` |
| 12 | **Format SD Card** | Wipe + partisi GPT + format ext4/NTFS/exFAT. Auto-mount ke `/mnt/sdcard` |
| 13 | **Samba Share** | File sharing via SMB. Akses dari Windows: `\\ip\stbshare` |
| 14 | **FileBrowser** | Web file manager di port **8080** (default: admin/admin) |
| 15 | **AdGuard Home** | DNS-level ad blocker di port **3000** (web UI) + **53** (DNS) |

### 🐳 Aplikasi Docker
| Menu | Fitur | Port | Fungsi |
|---|---|---|---|
| 16 | **Jellyfin** | 8096 | Media server (film, musik, TV) |
| 17 | **Immich** | 2283 | Google Photos alternatif — backup foto/video |
| 18 | **Tailscale** | - | VPN mesh untuk akses remote aman |

### 🛠 Tools
| Menu | Fitur | Detail |
|---|---|---|
| 19 | **Monitoring** | Tampilkan suhu CPU, RAM, load, uptime, status Docker & service, akses HTOP |
| 20 | **Backup & Restore** | Backup konfigurasi (Samba, Nginx, CasaOS, FileBrowser) + Docker volumes. Restore dari file backup |
| 21 | **Uninstall Cerdas** | **Auto-detect** layanan yang terinstall — hanya tampilkan yang ada. Dukungan: CasaOS, Portainer, Cockpit, FileBrowser, AdGuard, Jellyfin, Immich, Tailscale, Samba, Docker, Nginx. Ada opsi **99) HAPUS SEMUA** untuk uninstall semua sekaligus |
| A | **Install All** | Satu perintah untuk install semua layanan + optimasi sesuai chipset |

## Menu Utama

```
 ╔═══════════════════════════════════════════╗
 ║        STB SERVER MANAGER v3.0            ║
 ╚═══════════════════════════════════════════╝

 ━━━ INSTALASI LAYANAN ━━━
  [1]  Update Sistem & Tools
  [2]  Install CasaOS
  [3]  Install Portainer
  [4]  Install Cockpit
  [5]  Install Nginx + PHP

 ━━━ OPTIMASI STB ━━━
  [6]  Optimasi Generic STB
  [7]  Optimasi B860H v1
  [8]  Optimasi HG680P
  [9]  Optimasi X96MINI

 ━━━ STORAGE & NETWORK ━━━
  [10] Auto Mount HDD/SSD
  [11] Pilih Storage Utama
  [12] Format SD Card
  [13] Pasang Samba Share
  [14] Pasang FileBrowser
  [15] Pasang AdGuard Home

 ━━━ APLIKASI DOCKER ━━━
  [16] Pasang Jellyfin
  [17] Pasang Immich
  [18] Pasang Tailscale

 ━━━ TOOLS ━━━
  [19] Monitoring Sistem
  [20] Backup & Restore
  [21] Uninstall Layanan

  [A]  Install ALL (semua layanan)
  [Q]  Keluar
```

### Uninstall Menu (Sub-menu)

```
 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        UNINSTALL LAYANAN
 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

 No  Status    Service
 -- -------- ------------------------------
  1   INSTALLED CasaOS
  2   INSTALLED Portainer
  3   INSTALLED Cockpit
  4   INSTALLED Samba
  5   INSTALLED Docker (all)
  6   INSTALLED Nginx + PHP

 99) HAPUS SEMUA LAYANAN
  0) Kembali ke menu utama
```

Hanya layanan yang benar-benar terinstall yang muncul. Konfirmasi hapus dengan mengetik nama layanan (atau `UNINSTALL ALL` untuk hapus semua).

## Persyaratan

- **OS:** Armbian (diuji di Ubuntu/Debian based)
- **Arch:** ARM64 / aarch64
- **Storage:** Minimal 8GB (disarankan 16GB+)
- **RAM:** Minimal 512MB (disarankan 1GB+)
- **STB:** B860H v1, HG680P, X96MINI, atau TV Box Amlogic lainnya

## Cara Install

```bash
wget https://raw.githubusercontent.com/budijoi/stb-server-manager/main/stb-server.sh
chmod +x stb-server.sh
sudo ./stb-server.sh
```

### Quick Start

```bash
sudo ./stb-server.sh
# Pilih [6] Optimasi Generic STB
# Pilih [2] Install CasaOS
# Pilih [3] Install Portainer
```

### All-in-One

```bash
sudo ./stb-server.sh
# Pilih [A] untuk install semua layanan sekaligus
```

## Struktur File

```
stb-server.sh       # Script utama
stb-config/         # Konfigurasi (auto-generated)
  └─ storage.conf   # Storage utama terpilih
stb-backups/        # Hasil backup
stb-server.log      # Log aktivitas
```

## Catatan

- Script membutuhkan akses **root** (`sudo`).
- Beberapa fitur (AdGuard, Jellyfin, Immich) membutuhkan **Docker** — akan diinstall otomatis jika belum ada.
- Untuk akses remote dari luar jaringan, gunakan **Tailscale** (menu 18) atau port forwarding.
- Backup direkomendasikan sebelum menjalankan uninstall atau install ulang layanan.

## Lisensi

MIT — bebas digunakan dan dimodifikasi.
