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

| Opsi | Target | Tweak |
|---|---|---|
| **Generic** | Semua STB | Swappiness=10, I/O scheduler mq-deadline, disable bluetooth/ModemManager, cron drop_caches |
| **B860H v1** | S905X | Performance governor, dirty_ratio tuning, Ethernet speed fix, NTP fix |
| **HG680P** | S905 (RAM rendah) | Ondemand governor, auto swap 2GB jika RAM < 1GB, aggressive dirty ratio |
| **X96MINI** | S905W | Performance governor, thermal threshold, ZRAM compression |

### 💾 Storage & Network
| Fitur | Detail |
|---|---|
| **Auto Mount HDD/SSD** | Deteksi partisi baru → mount otomatis → entry fstab. Opsi format ext4 jika gagal mount |
| **Samba Share** | File sharing via SMB. Akses dari Windows: `\\ip\stbshare` |
| **FileBrowser** | Web file manager di port **8080** (default: admin/admin) |
| **AdGuard Home** | DNS-level ad blocker di port **3000** (web UI) + **53** (DNS) |

### 🐳 Aplikasi Docker
| Fitur | Port | Fungsi |
|---|---|---|
| **Jellyfin** | 8096 | Media server (film, musik, TV) |
| **Immich** | 2283 | Google Photos alternatif — backup foto/video |
| **Tailscale** | - | VPN mesh untuk akses remote aman |

### 🛠 Tools
| Fitur | Detail |
|---|---|
| **Monitoring** | Tampilkan suhu CPU, RAM, load, uptime, status Docker & service, akses HTOP |
| **Backup & Restore** | Backup konfigurasi (Samba, Nginx, CasaOS, FileBrowser) + Docker volumes. Restore dari file backup |
| **Uninstall** | Hapus layanan individually: CasaOS, Portainer, Cockpit, FileBrowser, AdGuard, Jellyfin, Immich, Tailscale, Samba, atau Docker total |
| **Auto-Install All** | Satu perintah untuk install semua layanan + optimasi sesuai chipset |

## Persyaratan

- **OS:** Armbian (diuji di Ubuntu/Debian based)
- **Arch:** ARM64 / aarch64
- **Storage:** Minimal 8GB (disarankan 16GB+)
- **RAM:** Minimal 512MB (disarankan 1GB+)
- **STB:** B860H v1, HG680P, X96MINI, atau TV Box Amlogic lainnya

## Cara Install

```bash
# Clone atau download script
wget https://raw.githubusercontent.com/username/stb-server/main/stb-server.sh

# Beri izin eksekusi
chmod +x stb-server.sh

# Jalankan sebagai root
sudo ./stb-server.sh
```

## Cara Penggunaan

Setelah script dijalankan, akan muncul menu utama interaktif berwarna. Cukup pilih angka yang diinginkan:

```
 ╔═══════════════════════════════════════════╗
 ║        STB SERVER MANAGER v3.0            ║
 ╚═══════════════════════════════════════════╝

 ━━━ INSTALASI LAYANAN ━━━
  [1]  Update Sistem & Tools
  [2]  Install CasaOS
  [3]  Install Portainer
  [4]  Install Cockpit
  ...

 ━━━ OPTIMASI STB ━━━
  [6]  Optimasi Generic STB
  [7]  Optimasi B860H v1
  ...

 ━━━ TOOLS ━━━
  [17] Monitoring Sistem
  [18] Backup & Restore
  [19] Uninstall Layanan
  [A]  Install ALL
  [Q]  Keluar
```

### Quick Start (Rekomendasi)

```bash
sudo ./stb-server.sh
# Pilih [6] Optimasi Generic STB dulu
# Pilih [2] Install CasaOS
# Pilih [3] Install Portainer
```

### All-in-One

```bash
sudo ./stb-server.sh
# Pilih [A] untuk install semua layanan sekaligus
```

Script akan otomatis mendeteksi chipset dan merekomendasikan optimasi yang sesuai.

## Struktur File

```
stb-server.sh       # Script utama
stb-config/         # Konfigurasi (auto-generated)
stb-backups/        # Hasil backup
stb-server.log      # Log aktivitas
```

## Catatan

- Script membutuhkan akses **root** (`sudo`).
- Beberapa fitur (AdGuard, Jellyfin, Immich) membutuhkan **Docker** — akan diinstall otomatis jika belum ada.
- Untuk akses remote dari luar jaringan, gunakan **Tailscale** (menu 16) atau port forwarding.
- Backup direkomendasikan sebelum menjalankan uninstall atau install ulang layanan.

## Lisensi

MIT — bebas digunakan dan dimodifikasi.
