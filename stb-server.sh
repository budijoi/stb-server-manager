#!/bin/bash
#===============================================================================
# STB Server Manager - All-in-One Home Server Script for Armbian TV Boxes
# By Budijoi
#===============================================================================
# Penggunaan: chmod +x stb-server.sh && ./stb-server.sh
#===============================================================================

VERSION="3.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/stb-server.log"
CONFIG_DIR="$SCRIPT_DIR/stb-config"
BACKUP_DIR="$SCRIPT_DIR/stb-backups"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

# Warna
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'
WHITE='\033[1;37m'; BOLD='\033[1m'; NC='\033[0m'

# =========================== FUNGSI UTILITY ================================

log() { echo -e "$(date '+%H:%M:%S') $1" | tee -a "$LOG_FILE"; }
ok()   { log "${GREEN}[✓]${NC} $1"; }
fail() { log "${RED}[✗]${NC} $1"; }
info() { log "${CYAN}[i]${NC} $1"; }
warn() { log "${YELLOW}[!]${NC} $1"; }
header() { clear; echo -e "${BOLD}${BLUE}================================================${NC}"; echo -e "${BOLD}${WHITE}     $1${NC}"; echo -e "${BOLD}${BLUE}================================================${NC}${NC}"; }

pause() { echo; read -p "$(echo -e ${YELLOW}"Tekan Enter untuk kembali..."${NC})" dummy; }

cek_root() {
    if [[ $EUID -ne 0 ]]; then
        fail "Script ini harus dijalankan sebagai root (sudo ./stb-server.sh)"
        exit 1
    fi
}

cek_armbian() {
    if [[ ! -f /etc/armbian-release ]]; then
        warn "Sepertinya ini bukan Armbian. Beberapa fitur mungkin tidak berfungsi."
    fi
}

deteksi_cpu() {
    CPU_MODEL=$(cat /proc/cpuinfo | grep "Hardware\|model name\|Processor" | head -1 | sed 's/.*: //')
    CHIPSET=""
    SOC=""

    if grep -qi "s905w" /proc/cpuinfo 2>/dev/null || grep -qi "gxl_p281" /proc/device-tree/amlogic-dt-id 2>/dev/null; then
        SOC="S905W"; CHIPSET="S905W"
    elif grep -qi "s905x" /proc/cpuinfo 2>/dev/null || grep -qi "gxl_p212" /proc/device-tree/amlogic-dt-id 2>/dev/null; then
        SOC="S905X"; CHIPSET="S905X"
    elif grep -qi "s905" /proc/cpuinfo 2>/dev/null; then
        SOC="S905"; CHIPSET="S905"
    elif grep -qi "g12" /proc/device-tree/amlogic-dt-id 2>/dev/null; then
        SOC="S905X2"; CHIPSET="S905X2"
    else
        SOC="Tidak terdeteksi"; CHIPSET="generic"
    fi

    ARCH=$(uname -m)
    RAM_TOTAL=$(free -h | awk '/^Mem:/ {print $2}')
    RAM_USED=$(free -h | awk '/^Mem:/ {print $3}')
    STORAGE=$(df -h / | awk 'NR==2 {print $2}')
    STORAGE_USED=$(df -h / | awk 'NR==2 {print $3}')
    SUHU=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{printf "%.1f°C", $1/1000}' || echo "N/A")
    UPTIME=$(uptime -p | sed 's/up //')
    LOAD=$(uptime | awk -F'average:' '{print $2}' | xargs)

    echo -e "${GREEN}CPU Model:${NC} $CPU_MODEL"
    echo -e "${GREEN}SoC:${NC} $SOC | ${GREEN}Arch:${NC} $ARCH"
    echo -e "${GREEN}RAM:${NC} $RAM_USED / $RAM_TOTAL"
    echo -e "${GREEN}Storage:${NC} $STORAGE_USED / $STORAGE"
    echo -e "${GREEN}Suhu CPU:${NC} $SUHU"
    echo -e "${GREEN}Uptime:${NC} $UPTIME"
    echo -e "${GREEN}Load:${NC} $LOAD"
}

ceklayanan() {
    local svc=$1
    if systemctl is-active --quiet "$svc" 2>/dev/null; then echo -e "${GREEN}Running${NC}"
    elif systemctl is-enabled --quiet "$svc" 2>/dev/null; then echo -e "${YELLOW}Stopped${NC}"
    else echo -e "${RED}Not found${NC}"; fi
}

# =========================== INSTALASI DASAR ================================

update_system() {
    header "UPDATE SYSTEM"
    apt update && apt upgrade -y
    apt install -y curl wget sudo ufw htop iotop git unzip zip jq
    ok "System updated"
    pause
}

pasang_casaos() {
    header "INSTALL CASAOS"
    if systemctl is-active --quiet casaos; then
        warn "CasaOS sudah terinstall. Skip."
        pause; return
    fi
    info "Menginstall CasaOS..."
    curl -fsSL https://get.casaos.io | bash && ok "CasaOS installed" || fail "Gagal install CasaOS"
    pause
}

pasang_portainer() {
    header "INSTALL PORTAINER"
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q portainer; then
        warn "Portainer sudah running. Skip."
        pause; return
    fi
    info "Menginstall Portainer..."
    docker volume create portainer_data 2>/dev/null
    docker run -d --name portainer -p 9000:9000 \
        --restart=always \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v portainer_data:/data \
        portainer/portainer-ce:latest && ok "Portainer running di port 9000" || fail "Gagal install Portainer"
    pause
}

pasang_cockpit() {
    header "INSTALL COCKPIT"
    if systemctl is-active --quiet cockpit; then
        warn "Cockpit sudah terinstall."
        pause; return
    fi
    info "Menginstall Cockpit..."
    apt install -y cockpit && systemctl enable --now cockpit && ok "Cockpit running di port 9090" || fail "Gagal install Cockpit"
    pause
}

pasang_docker() {
    if command -v docker &>/dev/null; then
        ok "Docker sudah terinstall"
        return
    fi
    header "INSTALL DOCKER"
    curl -fsSL https://get.docker.com | bash && systemctl enable --now docker
    if command -v docker &>/dev/null; then ok "Docker installed"; else fail "Gagal install Docker"; fi
    pause
}

pasang_nginx() {
    header "INSTALL NGINX + PHP"
    apt install -y nginx php-fpm php-cli php-mbstring php-curl php-xml php-zip
    systemctl enable --now nginx && ok "Nginx running" || fail "Gagal install Nginx"
    pause
}

# =========================== OPTIMASI STB ==================================

optimasi_generik() {
    header "OPTIMASI GENERIC STB"
    info "Menerapkan optimasi sistem..."
    
    # Swap
    if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
        echo "vm.swappiness=10" >> /etc/sysctl.conf
        echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.conf
        echo "net.core.rmem_max=16777216" >> /etc/sysctl.conf
        echo "net.core.wmem_max=16777216" >> /etc/sysctl.conf
    fi
    sysctl -p 2>/dev/null
    
    # I/O scheduler
    local disk=$(lsblk -ndo NAME 2>/dev/null | head -1)
    [[ -n "$disk" ]] && echo mq-deadline > /sys/block/"$disk"/queue/scheduler 2>/dev/null
    
    # Disable services
    systemctl disable bluetooth 2>/dev/null
    systemctl disable ModemManager 2>/dev/null
    systemctl disable wifi-country 2>/dev/null
    
    # Samba optimasi
    if command -v smbd &>/dev/null; then
        sed -i 's/socket options = .*/socket options = TCP_NODELAY IPTOS_LOWDELAY/' /etc/samba/smb.conf 2>/dev/null
    fi
    
    # Cron untuk RAM
    if ! crontab -l 2>/dev/null | grep -q "sync.*echo 3"; then
        (crontab -l 2>/dev/null; echo "*/30 * * * * sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null") | crontab -
    fi
    
    ok "Optimasi generik selesai"
    pause
}

optimasi_b860h() {
    header "OPTIMASI BH860H V1"
    info "Menerapkan tweak khusus B860H v1..."
    
    echo "performance" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null
    echo 5 > /proc/sys/vm/dirty_background_ratio
    echo 15 > /proc/sys/vm/dirty_ratio
    
    if ! grep -q "b860h" /etc/sysctl.conf 2>/dev/null; then
        echo "# B860H v1 tweaks" >> /etc/sysctl.conf
        echo "kernel.nmi_watchdog=0" >> /etc/sysctl.conf
        echo "kernel.sched_min_granularity_ns=2000000" >> /etc/sysctl.conf
        echo "kernel.sched_wakeup_granularity_ns=3000000" >> /etc/sysctl.conf
    fi
    sysctl -p 2>/dev/null

    # Fix Ethernet untuk B860H
    ethtool -s eth0 speed 100 duplex full autoneg off 2>/dev/null
    
    # NTP fix untuk B860H
    if command -v hwclock &>/dev/null; then
        hwclock --hctosys 2>/dev/null || true
    fi
    
    ok "Optimasi B860H v1 selesai"
    pause
}

optimasi_hg680p() {
    header "OPTIMASI HG680P"
    info "Menerapkan tweak khusus HG680P..."
    
    # CPU governor
    echo "ondemand" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null
    
    # RAM rendah - swap
    local ram_mb=$(free -m | awk '/^Mem:/ {print $2}')
    if [[ $ram_mb -lt 1024 ]]; then
        info "RAM ${ram_mb}MB - menambah swap"
        if ! grep -q "swapfile" /etc/fstab; then
            fallocate -l 2G /swapfile 2>/dev/null
            chmod 600 /swapfile
            mkswap /swapfile 2>/dev/null
            swapon /swapfile 2>/dev/null
            echo "/swapfile none swap defaults 0 0" >> /etc/fstab
        fi
    fi
    
    echo "vm.dirty_background_ratio=3" >> /etc/sysctl.conf 2>/dev/null
    echo "vm.dirty_ratio=10" >> /etc/sysctl.conf 2>/dev/null
    sysctl -p 2>/dev/null
    
    ok "Optimasi HG680P selesai"
    pause
}

optimasi_x96mini() {
    header "OPTIMASI X96MINI"
    info "Menerapkan tweak khusus X96MINI..."
    
    # S905W specific
    echo "performance" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null
    
    # Thermal management
    if [[ -d /sys/class/thermal/thermal_zone0 ]]; then
        echo "Setting thermal threshold..."
        echo 80000 > /sys/class/thermal/thermal_zone0/trip_point_0_temp 2>/dev/null || true
    fi
    
    # ZRAM
    if command -v zramctl &>/dev/null; then
        swapoff /dev/zram0 2>/dev/null
        echo 0 > /sys/block/zram0/disksize 2>/dev/null
        local zram_size=$(( $(free -m | awk '/^Mem:/ {print $2}') * 2 ))
        echo "${zram_size}M" > /sys/block/zram0/disksize 2>/dev/null
        mkswap /dev/zram0 2>/dev/null
        swapon -p 5 /dev/zram0 2>/dev/null
    fi
    
    ok "Optimasi X96MINI selesai"
    pause
}

# =========================== AUTO MOUNT ====================================

auto_mount() {
    header "AUTO MOUNT HDD/SSD"
    info "Mendeteksi disk yang belum ter-mount..."
    
    local disks=$(lsblk -ndo NAME,TYPE,SIZE,MODEL | grep "disk")
    echo -e "${YELLOW}Disk terdeteksi:${NC}"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL | grep -v "loop"
    
    echo
    local candidates=$(lsblk -ndo NAME,TYPE | grep "disk" | awk '{print $1}')
    local mounted=0
    
    for disk in $candidates; do
        local partitions=$(lsblk -nlo NAME /dev/$disk 2>/dev/null | grep -v "^$disk$")
        for part in $partitions; do
            local mnt=$(lsblk -nlo MOUNTPOINT /dev/$part 2>/dev/null)
            local fstype=$(lsblk -nlo FSTYPE /dev/$part 2>/dev/null)
            if [[ -z "$mnt" && -n "$fstype" && "$fstype" != "swap" ]]; then
                local label=$(lsblk -nlo LABEL /dev/$part 2>/dev/null)
                label="${label:-storage}"
                local target="/mnt/${label,,}"
                mkdir -p "$target"
                mount /dev/$part "$target" 2>/dev/null && ok "Mounted /dev/$part -> $target" || {
                    # coba format ext4
                    warn "Gagal mount /dev/$part. Format ext4? (y/n)"
                    read -r ans
                    if [[ "$ans" == "y" ]]; then
                        info "Memformat /dev/$part ext4..."
                        mkfs.ext4 -F /dev/$part 2>/dev/null
                        mount /dev/$part "$target" 2>/dev/null && ok "Mounted setelah format"
                    fi
                }
                # fstab
                local uuid=$(blkid -s UUID -o value /dev/$part 2>/dev/null)
                if [[ -n "$uuid" ]] && ! grep -q "$uuid" /etc/fstab; then
                    echo "UUID=$uuid $target ext4 defaults,noatime,nodiratime,nofail 0 2" >> /etc/fstab
                    ok "Entry fstab ditambahkan untuk $target"
                fi
                mounted=$((mounted+1))
            fi
        done
    done
    
    [[ $mounted -eq 0 ]] && warn "Tidak ada disk baru ditemukan"
    pause
}

# =========================== FORMAT SD CARD =================================

format_sdcard() {
    header "FORMAT SD CARD"
    
    # Pastikan tools format tersedia
    apt install -y exfatprogs ntfs-3g fdisk parted 2>/dev/null
    
    echo -e "${YELLOW}Mendeteksi kartu SD...${NC}"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL | grep -v "loop"
    echo

    local candidates=$(lsblk -ndo NAME,TYPE,SIZE | grep "disk" | awk '{print $1}')
    local sdcard=""
    local idx=0
    declare -a opts

    for d in $candidates; do
        local model=$(lsblk -ndo MODEL /dev/$d 2>/dev/null)
        local size=$(lsblk -ndo SIZE /dev/$d 2>/dev/null)
        local rm=$(cat /sys/block/$d/removable 2>/dev/null)
        idx=$((idx+1))
        opts+=("$d")
        if [[ "$rm" == "1" ]]; then
            echo -e "  ${CYAN}[$idx]${NC} /dev/$d — ${size} (REMOVABLE) $model ${GREEN}← SD Card${NC}"
        else
            echo -e "  ${CYAN}[$idx]${NC} /dev/$d — ${size} $model"
        fi
    done

    if [[ $idx -eq 0 ]]; then
        warn "Tidak ada disk ditemukan"
        pause
        return
    fi

    echo
    read -p "Pilih disk [1-$idx]: " disk_pilih
    local selected="${opts[$((disk_pilih-1))]}"
    if [[ -z "$selected" ]]; then
        fail "Pilihan tidak valid"
        pause
        return
    fi

    echo
    echo -e "${RED}${BOLD}PERINGATAN: Semua data di /dev/$selected akan HILANG!${NC}"
    read -p "Yakin ingin memformat /dev/$selected? (ketik YES): " confirm
    [[ "$confirm" != "YES" ]] && warn "Dibatalkan" && pause && return

    echo
    echo -e "Pilih filesystem:"
    echo "1) ext4  (Linux — recommended)"
    echo "2) NTFS  (Windows compatible)"
    echo "3) exFAT (Universal)"
    read -p "Pilihan [1]: " fs_pilih

    local fs_type="ext4"
    local fs_cmd="mkfs.ext4 -F"
    case $fs_pilih in
        2) fs_type="ntfs"; fs_cmd="mkfs.ntfs -f" ;;
        3) fs_type="exfat"; fs_cmd="mkfs.exfat" ;;
    esac

    local label="STB-${fs_type^^}"
    read -p "Label volume [${label}]: " custom_label
    [[ -n "$custom_label" ]] && label="$custom_label"

    echo
    info "Mounting partitions /dev/${selected}*..."
    for part in $(lsblk -nlo NAME /dev/$selected 2>/dev/null | grep -v "^$selected$"); do
        umount /dev/$part 2>/dev/null
    done

    info "Menghapus partisi /dev/$selected..."
    dd if=/dev/zero of=/dev/$selected bs=1M count=10 status=none 2>/dev/null
    sleep 1
    partprobe /dev/$selected 2>/dev/null || true

    info "Membuat partisi baru..."
    echo -e "g\nn\n\n\n\nw" | fdisk /dev/$selected 2>/dev/null
    sleep 2
    partprobe /dev/$selected 2>/dev/null || true

    local newpart=$(lsblk -nlo NAME /dev/$selected 2>/dev/null | grep -v "^$selected$" | head -1)
    if [[ -z "$newpart" ]]; then
        fail "Gagal mendeteksi partisi baru"
        pause
        return
    fi

    info "Memformat /dev/$newpart sebagai $fs_type..."
    $fs_cmd -L "$label" /dev/$newpart 2>/dev/null

    if [[ $? -eq 0 ]]; then
        ok "Format selesai! /dev/$newpart → $fs_type (label: $label)"
        local target="/mnt/sdcard"
        mkdir -p "$target"
        mount /dev/$newpart "$target" 2>/dev/null && ok "Auto-mounted ke $target"

        local uuid=$(blkid -s UUID -o value /dev/$newpart 2>/dev/null)
        if [[ -n "$uuid" ]] && ! grep -q "$uuid" /etc/fstab; then
            echo "UUID=$uuid $target $fs_type defaults,noatime,nodiratime,nofail 0 2" >> /etc/fstab
            ok "Entry fstab ditambahkan"
        fi
    else
        fail "Gagal memformat"
    fi
    pause
}

# =========================== PILIH STORAGE UTAMA ============================

pilih_storage_utama() {
    header "PILIH STORAGE UTAMA"
    echo -e "${YELLOW}Mendeteksi storage yang tersedia...${NC}"
    
    mkdir -p "$CONFIG_DIR"
    local config="$CONFIG_DIR/storage.conf"
    
    declare -a disks_list
    declare -a disks_size
    declare -a disks_type
    local idx=0
    
    # EMMC
    for d in $(ls /dev/mmcblk* 2>/dev/null | grep -o 'mmcblk[0-9]\+$' | sort -u); do
        local size=$(lsblk -ndo SIZE /dev/$d 2>/dev/null)
        disks_list+=("$d")
        disks_size+=("$size")
        disks_type+=("emmc")
    done
    
    # SD Card (removable)
    for d in $(lsblk -ndo NAME | grep -E '^mmcblk[0-9]+$|^sd[a-z]+$'); do
        local rm=$(cat /sys/block/$d/removable 2>/dev/null)
        if [[ "$rm" == "1" ]]; then
            local size=$(lsblk -ndo SIZE /dev/$d 2>/dev/null)
            disks_list+=("$d")
            disks_size+=("$size")
            disks_type+=("sdcard")
        fi
    done
    
    # HDD/SSD eksternal (non-removable, bukan mmc)
    for d in $(lsblk -ndo NAME | grep -E '^sd[a-z]+$'); do
        local rm=$(cat /sys/block/$d/removable 2>/dev/null)
        if [[ "$rm" != "1" ]]; then
            local size=$(lsblk -ndo SIZE /dev/$d 2>/dev/null)
            disks_list+=("$d")
            disks_size+=("$size")
            disks_type+=("external")
        fi
    done
    
    if [[ ${#disks_list[@]} -eq 0 ]]; then
        warn "Tidak ada storage terdeteksi (selain boot disk)"
        pause
        return
    fi
    
    echo
    echo -e "${BOLD}Pilih storage utama untuk data:${NC}"
    echo "  0) Boot disk saat ini (/)"
    for i in "${!disks_list[@]}"; do
        local icon=""
        case "${disks_type[$i]}" in
            emmc)    icon="💾 eMMC" ;;
            sdcard)  icon="📇 SD Card" ;;
            external) icon="💽 HDD/SSD" ;;
        esac
        echo -e "  ${CYAN}[$((i+1))]${NC} /dev/${disks_list[$i]} — ${disks_size[$i]} — $icon"
    done
    
    echo
    read -p "Pilihan [0-${#disks_list[@]}]: " stor_pilih
    
    local selected_dev=""
    local selected_type="boot"
    local selected_size=""
    
    if [[ "$stor_pilih" =~ ^[0-9]+$ ]] && [[ $stor_pilih -ge 1 ]] && [[ $stor_pilih -le ${#disks_list[@]} ]]; then
        local i=$((stor_pilih-1))
        selected_dev="${disks_list[$i]}"
        selected_type="${disks_type[$i]}"
        selected_size="${disks_size[$i]}"
    elif [[ "$stor_pilih" == "0" ]]; then
        selected_dev=""
        selected_type="boot"
    else
        fail "Pilihan tidak valid"
        pause
        return
    fi
    
    local target="/mnt/storage"
    
    # Jika bukan boot disk, setup mount
    if [[ "$selected_type" != "boot" ]]; then
        echo
        echo -e "${BOLD}Konfigurasi /dev/$selected_dev:${NC}"
        echo "  1) Format & mount sebagai storage utama"
        echo "  2) Mount saja (jaga data existing)"
        read -p "Pilihan [1]: " fmt_pilih
        
        # Unmount partisi existing
        for part in $(lsblk -nlo NAME /dev/$selected_dev 2>/dev/null | grep -v "^$selected_dev$"); do
            umount /dev/$part 2>/dev/null
        done
        
        # Cek apakah sudah ada partisi
        local existing_parts=$(lsblk -nlo NAME /dev/$selected_dev 2>/dev/null | grep -v "^$selected_dev$")
        
        if [[ -z "$existing_parts" || "$fmt_pilih" == "1" ]]; then
            if [[ -n "$existing_parts" ]]; then
                read -p "Semua data akan hilang. Lanjutkan? (y/N): " warn_ans
                [[ "$warn_ans" != "y" ]] && warn "Dibatalkan" && pause && return
            fi
            info "Membuat partisi baru di /dev/$selected_dev..."
            dd if=/dev/zero of=/dev/$selected_dev bs=1M count=10 status=none 2>/dev/null
            sleep 1
            partprobe /dev/$selected_dev 2>/dev/null || true
            echo -e "g\nn\n\n\n\nw" | fdisk /dev/$selected_dev 2>/dev/null
            sleep 2
            partprobe /dev/$selected_dev 2>/dev/null || true
            local newpart=$(lsblk -nlo NAME /dev/$selected_dev 2>/dev/null | grep -v "^$selected_dev$" | head -1)
            if [[ -n "$newpart" ]]; then
                info "Memformat /dev/$newpart ext4..."
                mkfs.ext4 -F -L "STB-DATA" /dev/$newpart 2>/dev/null
                selected_dev="$newpart"
            fi
        else
            selected_dev=$(echo "$existing_parts" | head -1)
        fi
        
        # Mount
        umount /dev/$selected_dev 2>/dev/null
        mkdir -p "$target"
        mount /dev/$selected_dev "$target" 2>/dev/null
        
        if mountpoint -q "$target"; then
            # Hapus entry fstab lama untuk /dev/$selected_dev
            local dev_uuid=$(blkid -s UUID -o value /dev/$selected_dev 2>/dev/null)
            if [[ -n "$dev_uuid" ]]; then
                sed -i "\|UUID=$dev_uuid|d" /etc/fstab 2>/dev/null
                echo "UUID=$dev_uuid $target ext4 defaults,noatime,nodiratime,nofail 0 2" >> /etc/fstab
            fi
            ok "/dev/$selected_dev mounted ke $target + fstab"
        else
            fail "Gagal mount /dev/$selected_dev"
        fi
    fi
    
    # Simpan konfigurasi
    cat > "$config" <<STORCONF
STORAGE_DEVICE="$selected_dev"
STORAGE_TYPE="$selected_type"
STORAGE_SIZE="$selected_size"
STORAGE_PATH="$target"
STORAGE_SET_AT="$(date)"
STORCONF
    
    ok "Storage utama: ${selected_type^^} → $target"
    
    # Setup symlink untuk service
    mkdir -p "$target/docker" "$target/media" "$target/downloads" "$target/backup"
    chmod 777 "$target" "$target/docker" "$target/media" "$target/downloads" "$target/backup"
    
    # Docker data root
    if command -v docker &>/dev/null && [[ -f /etc/docker/daemon.json ]]; then
        if ! grep -q "$target/docker" /etc/docker/daemon.json 2>/dev/null; then
            info "Mengarahkan Docker data ke $target/docker..."
        fi
    fi
    
    echo
    echo -e "${GREEN}Ringkasan:${NC}"
    echo -e "  Storage : ${selected_type^^} ${selected_dev:+/dev/$selected_dev}"
    echo -e "  Mount   : $target"
    echo -e "  Folder  : docker/  media/  downloads/  backup/"
    pause
}

# =========================== SAMBA ==========================================

pasang_samba() {
    header "AUTO SAMBA SHARE"
    
    # Install Samba
    if ! command -v smbd &>/dev/null; then
        apt install -y samba samba-common-bin
    fi
    
    local share_path=""
    echo -e "Pilih direktori yang akan di-share:"
    echo "1) /mnt/storage (default)"
    echo "2) /mnt (semua mount point)"
    echo "3) Custom path"
    read -p "Pilihan [1]: " spilih
    case $spilih in
        2) share_path="/mnt" ;;
        3) read -p "Masukkan path: " share_path ;;
        *) share_path="/mnt/storage" ;;
    esac
    
    mkdir -p "$share_path"
    chmod 777 "$share_path"
    
    local share_name=$(basename "$share_path" | tr '[:upper:]' '[:lower:]')
    share_name="stbshare"
    
    # Backup config
    cp /etc/samba/smb.conf /etc/samba/smb.conf.backup.${TIMESTAMP}
    
    # Write config minimal
    cat > /etc/samba/smb.conf <<SAMBACONF
[global]
workgroup = WORKGROUP
server string = STB-Server
netbios name = stbserver
security = user
map to guest = Bad User
guest account = nobody
socket options = TCP_NODELAY IPTOS_LOWDELAY
load printers = no
printing = bsd
printcap name = /dev/null
disable spoolss = yes
local master = yes
preferred master = yes
os level = 65

[${share_name}]
path = ${share_path}
browsable = yes
writable = yes
guest ok = yes
force user = root
force group = root
create mask = 0777
directory mask = 0777
SAMBACONF

    systemctl restart smbd && ok "Samba running. Share: \\\\$(hostname)\\${share_name}"
    systemctl enable smbd 2>/dev/null
    
    local ip=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1)
    echo -e "${GREEN}Akses dari Windows: \\\\${ip}\\${share_name}${NC}"
    pause
}

# =========================== FILEBROWSER ====================================

pasang_filebrowser() {
    header "INSTALL FILEBROWSER"
    if systemctl is-active --quiet filebrowser; then
        warn "FileBrowser sudah running"
        pause; return
    fi
    
    cd /tmp
    local fb_url=$(curl -s https://api.github.com/repos/filebrowser/filebrowser/releases/latest \
        | grep "browser_download_url.*linux-arm64" | grep -v ".tar.gz" | head -1 | cut -d\" -f4)
    
    if [[ -z "$fb_url" ]]; then
        warn "Gagal dapat URL, menggunakan fallback v2.31.2"
        fb_url="https://github.com/filebrowser/filebrowser/releases/download/v2.31.2/linux-arm64-filebrowser.tar.gz"
    fi
    
    curl -L -o filebrowser.tar.gz "$fb_url" 2>/dev/null
    tar xzf filebrowser.tar.gz 2>/dev/null
    mv filebrowser /usr/local/bin/filebrowser
    chmod +x /usr/local/bin/filebrowser
    rm -f filebrowser.tar.gz
    
    mkdir -p /etc/filebrowser
    cat > /etc/filebrowser/config.json <<FBCONF
{
  "port": 8080,
  "address": "0.0.0.0",
  "root": "/mnt",
  "database": "/etc/filebrowser/filebrowser.db",
  "log": "/var/log/filebrowser.log"
}
FBCONF
    
    cat > /etc/systemd/system/filebrowser.service <<FBSVC
[Unit]
Description=FileBrowser
After=network.target

[Service]
ExecStart=/usr/local/bin/filebrowser --config=/etc/filebrowser/config.json
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
FBSVC
    
    systemctl daemon-reload
    systemctl enable --now filebrowser && ok "FileBrowser: http://$(hostname -I | awk '{print $1}'):8080 (admin/admin)" || fail "Gagal"
    pause
}

# =========================== ADGUARD HOME ===================================

pasang_adguard() {
    header "INSTALL ADGUARD HOME"
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q adguard; then
        warn "AdGuard sudah running"
        pause; return
    fi
    
    mkdir -p /opt/adguard/work /opt/adguard/conf
    
    docker run -d --name adguardhome \
        --restart=always \
        -p 53:53/tcp -p 53:53/udp \
        -p 3000:3000/tcp \
        -p 853:853/tcp \
        -v /opt/adguard/work:/opt/adguard/work \
        -v /opt/adguard/conf:/opt/adguard/conf \
        adguard/adguardhome:latest && ok "AdGuard: http://$(hostname -I | awk '{print $1}'):3000" || fail "Gagal"
    pause
}

# =========================== JELLYFIN =======================================

pasang_jellyfin() {
    header "INSTALL JELLYFIN"
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q jellyfin; then
        warn "Jellyfin sudah running"
        pause; return
    fi
    
    mkdir -p /opt/jellyfin/config /opt/jellyfin/cache /opt/jellyfin/media
    
    docker run -d --name jellyfin \
        --restart=always \
        -p 8096:8096 \
        -v /opt/jellyfin/config:/config \
        -v /opt/jellyfin/cache:/cache \
        -v /opt/jellyfin/media:/media \
        -v /mnt:/mnt:ro \
        --device /dev/dri:/dev/dri:rw \
        jellyfin/jellyfin:latest && ok "Jellyfin: http://$(hostname -I | awk '{print $1}'):8096" || fail "Gagal"
    pause
}

# =========================== IMMICH =========================================

pasang_immich() {
    header "INSTALL IMMICH"
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q immich; then
        warn "Immich sudah running"
        pause; return
    fi
    
    mkdir -p /opt/immich
        
    if ! command -v docker-compose &>/dev/null && ! docker compose version &>/dev/null; then
        apt install -y docker-compose-plugin 2>/dev/null || \
            pip3 install docker-compose 2>/dev/null || \
            curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose 2>/dev/null
    fi
    
    cd /opt/immich
    curl -L https://github.com/immich-app/immich/releases/latest/download/docker-compose.yml -o docker-compose.yml 2>/dev/null
    curl -L https://github.com/immich-app/immich/releases/latest/download/example.env -o .env 2>/dev/null
    
    sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=$(tr -dc A-Za-z0-9 < /dev/urandom | head -c 16)/" .env
    sed -i "s/UPLOAD_LOCATION=.*/UPLOAD_LOCATION=\/opt\/immich\/upload/" .env
    
    docker compose up -d 2>/dev/null && ok "Immich: http://$(hostname -I | awk '{print $1}'):2283" || fail "Gagal install Immich"
    cd "$SCRIPT_DIR"
    pause
}

# =========================== TAILSCALE ======================================

pasang_tailscale() {
    header "INSTALL TAILSCALE"
    if command -v tailscale &>/dev/null; then
        info "Tailscale status: $(tailscale status 2>/dev/null | head -1)"
        pause; return
    fi
    
    curl -fsSL https://tailscale.com/install.sh | bash
    systemctl enable --now tailscaled 2>/dev/null
    ok "Jalankan: sudo tailscale up untuk mengaktifkan"
    pause
}

# =========================== MONITORING =====================================

menu_monitor() {
    while true; do
        header "MONITORING STB"
        echo -e "${BOLD}=== Informasi Sistem ===${NC}"
        echo -e "${GREEN}SoC:${NC} $SOC"
        echo -e "${GREEN}Suhu CPU:${NC} $SUHU"
        echo -e "${GREEN}RAM:${NC} $(free -h | awk '/^Mem:/ {print $3" / "$2}')"
        echo -e "${GREEN}Swap:${NC} $(free -h | awk '/^Swap:/ {print $3" / "$2}')"
        echo -e "${GREEN}Load:${NC} $LOAD"
        echo -e "${GREEN}Uptime:${NC} $UPTIME"
        echo -e "${GREEN}Proses:${NC} $(ps aux | wc -l) running"
        echo
        echo -e "${BOLD}=== Docker Status ===${NC}"
        if command -v docker &>/dev/null; then
            docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | head -10
        else
            echo -e "${RED}Docker tidak terinstall${NC}"
        fi
        echo
        echo -e "${BOLD}=== Layanan ===${NC}"
        printf "%-20s %s\n" "CasaOS" "$(ceklayanan casaos)"
        printf "%-20s %s\n" "Portainer" "$(ceklayanan portainer)"
        printf "%-20s %s\n" "Cockpit" "$(ceklayanan cockpit)"
        printf "%-20s %s\n" "Samba" "$(ceklayanan smbd)"
        printf "%-20s %s\n" "FileBrowser" "$(ceklayanan filebrowser)"
        printf "%-20s %s\n" "Nginx" "$(ceklayanan nginx)"
        echo
        echo "1) Refresh | 2) HTOP | 3) Back"
        read -p "Pilihan: " mmon
        case $mmon in
            1) continue ;;
            2) htop ;;
            3) break ;;
        esac
    done
}

# =========================== BACKUP & RESTORE ===============================

menu_backup() {
    header "BACKUP & RESTORE"
    mkdir -p "$BACKUP_DIR"
    
    echo "1) Backup konfigurasi"
    echo "2) Backup Docker volumes"
    echo "3) Restore dari backup"
    echo "4) Lihat daftar backup"
    echo "5) Kembali"
    read -p "Pilihan: " bpil
    
    case $bpil in
        1)
            local bfile="$BACKUP_DIR/backup-${TIMESTAMP}.tar.gz"
            info "Membackup konfigurasi..."
            tar czf "$bfile" \
                /etc/samba/smb.conf \
                /etc/nginx/ 2>/dev/null \
                /etc/filebrowser/ 2>/dev/null \
                /etc/systemd/system/casaos.service 2>/dev/null \
                /etc/casaos/ 2>/dev/null \
                "$SCRIPT_DIR/stb-server.sh" 2>/dev/null
            if command -v docker &>/dev/null; then
                docker ps -q 2>/dev/null | while read cid; do
                    docker inspect "$cid" > "$BACKUP_DIR/container-${cid}.json" 2>/dev/null
                done
            fi
            ok "Backup -> $bfile ($(du -h "$bfile" | cut -f1))"
            ;;
        2)
            if ! command -v docker &>/dev/null; then fail "Docker tidak ada"; return; fi
            local vols=$(docker volume ls -q 2>/dev/null)
            if [[ -z "$vols" ]]; then warn "Tidak ada volume"; return; fi
            for vol in $vols; do
                info "Backup volume $vol..."
                docker run --rm -v "$vol":/data -v "$BACKUP_DIR":/backup alpine \
                    tar czf "/backup/vol-${vol}-${TIMESTAMP}.tar.gz" -C /data . 2>/dev/null
            done
            ok "Backup volume selesai"
            ;;
        3)
            echo -e "${YELLOW}Backup tersedia:${NC}"
            ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null | awk '{print NR") "$NF" ("$5")"}'
            read -p "Pilih nomor backup: " bn
            local bfile2=$(ls "$BACKUP_DIR"/*.tar.gz 2>/dev/null | sed -n "${bn}p")
            if [[ -n "$bfile2" ]]; then
                tar tzf "$bfile2" | head -20
                read -p "Restore? (y/n): " rans
                [[ "$rans" == "y" ]] && tar xzf "$bfile2" -C / && ok "Restore selesai"
            else
                fail "File tidak ditemukan"
            fi
            ;;
        4)
            echo -e "${YELLOW}Daftar backup:${NC}"
            ls -lht "$BACKUP_DIR"/*.tar.gz 2>/dev/null || echo "Tidak ada backup"
            ;;
        5) return ;;
    esac
    pause
}

# =========================== UNINSTALL ======================================

menu_uninstall() {
    header "UNINSTALL LAYANAN"
    echo -e "${RED}${BOLD}Pilih layanan yang akan dihapus:${NC}"
    echo "1) CasaOS"
    echo "2) Portainer"
    echo "3) Cockpit"
    echo "4) FileBrowser"
    echo "5) AdGuard Home"
    echo "6) Jellyfin"
    echo "7) Immich"
    echo "8) Tailscale"
    echo "9) Samba"
    echo "10) Docker (semua container + images)"
    echo "11) Kembali"
    read -p "Pilihan [1-11]: " usta
    
    read -p "Yakin hapus? (y/N): " yakin
    [[ "$yakin" != "y" ]] && return
    
    case $usta in
        1)
            systemctl stop casaos 2>/dev/null
            systemctl disable casaos 2>/dev/null
            rm -rf /etc/casaos /usr/share/casaos /var/lib/casaos 2>/dev/null
            rm -f /etc/systemd/system/casaos.service 2>/dev/null
            systemctl daemon-reload
            ok "CasaOS dihapus"
            ;;
        2)
            docker stop portainer 2>/dev/null; docker rm portainer 2>/dev/null
            docker volume rm portainer_data 2>/dev/null
            ok "Portainer dihapus"
            ;;
        3)
            apt remove -y cockpit 2>/dev/null
            ok "Cockpit dihapus"
            ;;
        4)
            systemctl stop filebrowser 2>/dev/null
            systemctl disable filebrowser 2>/dev/null
            rm -f /usr/local/bin/filebrowser /etc/systemd/system/filebrowser.service
            rm -rf /etc/filebrowser
            systemctl daemon-reload
            ok "FileBrowser dihapus"
            ;;
        5)
            docker stop adguardhome 2>/dev/null; docker rm adguardhome 2>/dev/null
            rm -rf /opt/adguard 2>/dev/null
            ok "AdGuard dihapus"
            ;;
        6)
            docker stop jellyfin 2>/dev/null; docker rm jellyfin 2>/dev/null
            rm -rf /opt/jellyfin 2>/dev/null
            ok "Jellyfin dihapus"
            ;;
        7)
            cd /opt/immich
            docker compose down -v 2>/dev/null
            cd "$SCRIPT_DIR"
            rm -rf /opt/immich 2>/dev/null
            ok "Immich dihapus"
            ;;
        8)
            tailscale down 2>/dev/null
            apt remove -y tailscale 2>/dev/null
            ok "Tailscale dihapus"
            ;;
        9)
            systemctl stop smbd 2>/dev/null
            systemctl disable smbd 2>/dev/null
            apt remove -y samba samba-common-bin 2>/dev/null
            ok "Samba dihapus"
            ;;
        10)
            docker stop $(docker ps -aq) 2>/dev/null
            docker rm $(docker ps -aq) 2>/dev/null
            docker system prune -af 2>/dev/null
            docker volume prune -af 2>/dev/null
            apt remove -y docker docker-engine docker.io containerd runc docker-ce docker-ce-cli 2>/dev/null
            rm -rf /var/lib/docker /etc/docker 2>/dev/null
            ok "Docker dihapus total"
            ;;
        11) return ;;
    esac
    pause
}

# =========================== INSTALASI ALL IN ONE ===========================

pasang_semua() {
    header "INSTALASI ALL-IN-ONE"
    echo -e "${RED}${BOLD}PERINGATAN:${NC} Ini akan menginstall semua layanan."
    echo "Membutuhkan resource yang cukup besar."
    echo
    read -p "Lanjutkan? (y/N): " ans
    [[ "$ans" != "y" ]] && return
    
    update_system
    pasang_docker
    pasang_casaos
    pasang_portainer
    pasang_cockpit
    pasang_nginx
    pasang_samba
    pasang_filebrowser
    pasang_adguard
    pasang_jellyfin
    pasang_tailscale
    
    case "$SOC" in
        S905W)   optimasi_x96mini ;;
        S905X)   optimasi_b860h ;;
        S905)    optimasi_hg680p ;;
        *)       optimasi_generik ;;
    esac
    
    ok "Semua layanan terinstall! Reboot direkomendasikan."
    pause
}

# =========================== MENU UTAMA =====================================

menu_utama() {
    while true; do
        header "STB SERVER MANAGER v${VERSION}"
        
        echo -e "${BOLD}${GREEN}  ╔═══════════════════════════════════════════╗${NC}"
        echo -e "${BOLD}${GREEN}  ║${NC}  ${WHITE}SoC:${NC} $(printf "%-15s" "$SOC") ${GREEN}║${NC}"
        echo -e "${BOLD}${GREEN}  ║${NC}  ${WHITE}Suhu:${NC} $(printf "%-13s" "$SUHU") ${GREEN}║${NC}"
        echo -e "${BOLD}${GREEN}  ║${NC}  ${WHITE}RAM:${NC} $(printf "%-14s" "$RAM_USED / $RAM_TOTAL") ${GREEN}║${NC}"
        echo -e "${BOLD}${GREEN}  ╚═══════════════════════════════════════════╝${NC}"
        echo
        
        echo -e "${BOLD}${BLUE}━━━ INSTALASI LAYANAN ━━━${NC}"
        echo -e "  ${CYAN}[1]${NC}  Update Sistem & Tools"
        echo -e "  ${CYAN}[2]${NC}  Install CasaOS"
        echo -e "  ${CYAN}[3]${NC}  Install Portainer"
        echo -e "  ${CYAN}[4]${NC}  Install Cockpit"
        echo -e "  ${CYAN}[5]${NC}  Install Nginx + PHP"
        
        echo -e "${BOLD}${BLUE}━━━ OPTIMASI STB ━━━${NC}"
        echo -e "  ${CYAN}[6]${NC}  Optimasi Generic STB"
        echo -e "  ${CYAN}[7]${NC}  Optimasi B860H v1"
        echo -e "  ${CYAN}[8]${NC}  Optimasi HG680P"
        echo -e "  ${CYAN}[9]${NC}  Optimasi X96MINI"
        
        echo -e "${BOLD}${BLUE}━━━ STORAGE & NETWORK ━━━${NC}"
        echo -e "  ${CYAN}[10]${NC} Auto Mount HDD/SSD"
        echo -e "  ${CYAN}[11]${NC} Pilih Storage Utama"
        echo -e "  ${CYAN}[12]${NC} Format SD Card"
        echo -e "  ${CYAN}[13]${NC} Pasang Samba Share"
        echo -e "  ${CYAN}[14]${NC} Pasang FileBrowser"
        echo -e "  ${CYAN}[15]${NC} Pasang AdGuard Home"
        
        echo -e "${BOLD}${BLUE}━━━ APLIKASI DOCKER ━━━${NC}"
        echo -e "  ${CYAN}[16]${NC} Pasang Jellyfin"
        echo -e "  ${CYAN}[17]${NC} Pasang Immich"
        echo -e "  ${CYAN}[18]${NC} Pasang Tailscale"
        
        echo -e "${BOLD}${BLUE}━━━ TOOLS ━━━${NC}"
        echo -e "  ${CYAN}[19]${NC} Monitoring Sistem"
        echo -e "  ${CYAN}[20]${NC} Backup & Restore"
        echo -e "  ${CYAN}[21]${NC} Uninstall Layanan"
        
        echo -e "${BOLD}${BLUE}━━━ ${NC}"
        echo -e "  ${GREEN}[A]${NC}  Install ALL (semua layanan)"
        echo -e "  ${RED}[Q]${NC}  Keluar"
        echo
        
        read -p "$(echo -e ${YELLOW}"Pilih menu [1-21/A/Q]: "${NC})" pilih
        
        case $pilih in
            1)  update_system ;;
            2)  pasang_docker; pasang_casaos ;;
            3)  pasang_docker; pasang_portainer ;;
            4)  pasang_cockpit ;;
            5)  pasang_nginx ;;
            6)  optimasi_generik ;;
            7)  optimasi_b860h ;;
            8)  optimasi_hg680p ;;
            9)  optimasi_x96mini ;;
            10) auto_mount ;;
            11) pilih_storage_utama ;;
            12) format_sdcard ;;
            13) pasang_samba ;;
            14) pasang_filebrowser ;;
            15) pasang_docker; pasang_adguard ;;
            16) pasang_docker; pasang_jellyfin ;;
            17) pasang_docker; pasang_immich ;;
            18) pasang_tailscale ;;
            19) menu_monitor ;;
            20) menu_backup ;;
            21) menu_uninstall ;;
            a|A) pasang_semua ;;
            q|Q) echo -e "${GREEN}Terima kasih!${NC}"; exit 0 ;;
            *)   echo -e "${RED}Pilihan tidak valid${NC}"; sleep 1 ;;
        esac
    done
}

# =========================== MAIN ===========================================

clear
echo -e "${BOLD}${CYAN}"
echo "  ╔═══════════════════════════════════════════════╗"
echo "  ║        STB SERVER MANAGER v${VERSION}              ║"
echo "  ║    All-in-One Home Server untuk TV Box ARM     ║"
echo "  ║    Support: S905/S905X/S905W/S905X2           ║"
echo "  ╚═══════════════════════════════════════════════╝${NC}"
echo

cek_root
cek_armbian
deteksi_cpu
echo

# Logging
echo "=== STB-Server v${VERSION} - $(date) ===" > "$LOG_FILE"
echo "SoC: $SOC | RAM: $RAM_TOTAL | Suhu: $SUHU" >> "$LOG_FILE"

menu_utama
