cat > install.sh <<'EOF'
#!/bin/bash
set -Eeuo pipefail

VERSION="2.0.0"
PANEL_DIR="/var/www/pterodactyl"
BACKUP_ROOT="/var/backups/bash-install-protect"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROTECT_SCRIPT="$SCRIPT_DIR/protect.sh"

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
RESET='\033[0m'

msg() { echo -e "${CYAN}[INFO]${RESET} $*"; }
ok() { echo -e "${GREEN}[OK]${RESET} $*"; }
err() { echo -e "${RED}[ERROR]${RESET} $*"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        err "Jalankan sebagai root."
        exit 1
    fi
}

check_panel() {
    if [[ ! -d "$PANEL_DIR" || ! -f "$PANEL_DIR/artisan" ]]; then
        err "Folder Pterodactyl tidak ditemukan."
        exit 1
    fi

    if [[ ! -f "$PANEL_DIR/composer.json" ]]; then
        err "composer.json tidak ditemukan."
        exit 1
    fi
}

get_targets() {
    grep -Eo 'REMOTE_PATH="[^"]+"' "$PROTECT_SCRIPT" 2>/dev/null |
        sed -E 's/REMOTE_PATH="([^"]+)"/\1/' |
        sort -u |
        while IFS= read -r file; do
            [[ "$file" == "$PANEL_DIR/"* ]] && echo "$file"
        done
}

create_backup() {
    local name="${1:-manual}"
    local stamp
    stamp="$(date +%Y%m%d-%H%M%S)"
    local dir="$BACKUP_ROOT/${name}-${stamp}"

    mkdir -p "$dir"
    local -a files=()

    while IFS= read -r file; do
        [[ -f "$file" ]] && files+=("$file")
    done < <(get_targets)

    if [[ ${#files[@]} -eq 0 ]]; then
        err "Tidak ada file target yang ditemukan untuk dibackup."
        return 1
    fi

    tar -czPf "$dir/panel-files.tar.gz" "${files[@]}"
    printf '%s\n' "${files[@]}" > "$dir/manifest.txt"

    ok "Backup tersimpan: $dir"
}

restore_backup() {
    local archive
    archive="$(find "$BACKUP_ROOT" -type f -name panel-files.tar.gz 2>/dev/null | sort | tail -n 1)"

    if [[ -z "$archive" ]]; then
        err "Backup tidak ditemukan."
        return 1
    fi

    echo -e "${YELLOW}Backup yang akan dipulihkan:${RESET}"
    echo "$archive"
    read -r -p "Yakin restore? (y/N): " confirm

    [[ "$confirm" =~ ^[Yy]$ ]] || return 0

    tar -xzPf "$archive" -C /
    cd "$PANEL_DIR"
    php artisan optimize:clear

    ok "Backup berhasil dipulihkan."
}

check_php() {
    local failed=0

    while IFS= read -r file; do
        [[ -f "$file" ]] || continue

        if ! php -l "$file" >/dev/null 2>&1; then
            err "Syntax PHP bermasalah: $file"
            failed=1
        fi
    done < <(get_targets)

    return "$failed"
}

install_protect() {
    if [[ ! -f "$PROTECT_SCRIPT" ]]; then
        err "protect.sh tidak ditemukan di folder installer."
        return 1
    fi

    msg "Membuat backup sebelum instalasi..."
    create_backup "before-install" || return 1

    echo
    echo -e "${YELLOW}PERINGATAN:${RESET}"
    echo "Script proteksi lama mengganti beberapa file inti Pterodactyl."
    echo "Pemeriksaan sintaks tidak menjamin semua fitur panel kompatibel."
    read -r -p "Lanjutkan instalasi? (y/N): " confirm

    [[ "$confirm" =~ ^[Yy]$ ]] || return 0

    cd "$PANEL_DIR"

    if ! bash "$PROTECT_SCRIPT"; then
        err "Proses instalasi gagal. Memulihkan backup terakhir."
        restore_latest_silent
        return 1
    fi

    if ! check_php; then
        err "Pemeriksaan sintaks gagal. Memulihkan backup."
        restore_latest_silent
        return 1
    fi

    php artisan optimize:clear
    ok "Instalasi selesai dan pemeriksaan sintaks berhasil."
}

restore_latest_silent() {
    local archive
    archive="$(find "$BACKUP_ROOT" -type f -name panel-files.tar.gz 2>/dev/null | sort | tail -n 1)"

    if [[ -n "$archive" ]]; then
        tar -xzPf "$archive" -C /
        cd "$PANEL_DIR"
        php artisan optimize:clear
        ok "Backup dipulihkan."
    else
        err "Backup otomatis tidak ditemukan."
    fi
}

show_config() {
    echo
    echo -e "${CYAN}DAFTAR FILE PROTEKSI${RESET}"
    echo

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        if [[ -f "$file" ]]; then
            echo -e "${GREEN}[ADA]${RESET} $file"
        else
            echo -e "${RED}[TIDAK ADA]${RESET} $file"
        fi
    done < <(get_targets)

    echo
    echo "Catatan: daftar ini hanya menunjukkan keberadaan file,"
    echo "bukan verifikasi bahwa seluruh proteksi aktif."
}

reset_default() {
    echo -e "${YELLOW}Reset akan memulihkan backup terbaru.${RESET}"
    restore_backup
}

main_menu() {
    while true; do
        clear
        echo "=========================================="
        echo "          BASH INSTALL PROTECT"
        echo "                v$VERSION"
        echo "=========================================="
        echo
        echo "[1] Install Protect"
        echo "[2] Konfigurasi Protect"
        echo "[3] Reset Default"
        echo "[4] Backup"
        echo "[5] Restore"
        echo "[6] Exit"
        echo

        read -r -p "Pilih menu: " choice

        case "$choice" in
            1) install_protect ;;
            2) show_config ;;
            3) reset_default ;;
            4) create_backup "manual" ;;
            5) restore_backup ;;
            6) echo "Keluar."; exit 0 ;;
            *) err "Pilihan tidak valid." ;;
        esac

        echo
        read -r -p "Tekan Enter untuk kembali..."
    done
}

check_root
check_panel
mkdir -p "$BACKUP_ROOT"
main_menu
EOF

chmod +x install.sh
./install.sh
