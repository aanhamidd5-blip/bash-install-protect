cat > protect.sh <<'EOF'
#!/bin/bash
set -Eeuo pipefail

PANEL="/var/www/pterodactyl"
BACKUP="/var/backups/bash-install-protect"
SUPPORTED=("1.15.0" "1.15.1" "1.15.2")

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RESET='\033[0m'

info(){ echo -e "${CYAN}[INFO]${RESET} $*"; }
ok(){ echo -e "${GREEN}[OK]${RESET} $*"; }
fail(){ echo -e "${RED}[ERROR]${RESET} $*" >&2; }

[[ $EUID -eq 0 ]] || { fail "Jalankan sebagai root."; exit 1; }
[[ -f "$PANEL/artisan" ]] || { fail "Panel tidak ditemukan."; exit 1; }
[[ -f "$PANEL/composer.lock" ]] || { fail "composer.lock tidak ditemukan."; exit 1; }

VERSION="$(php -r '
$j=json_decode(file_get_contents($argv[1]),true);
foreach(($j["packages"] ?? []) as $p) {
 if(($p["name"] ?? "") === "pterodactyl/panel") {
  echo ltrim($p["version"], "v");
  exit;
 }
}
' "$PANEL/composer.lock")"

[[ -n "$VERSION" ]] || {
 fail "Versi panel tidak bisa dideteksi."
 exit 1
}

ALLOWED=0
for v in "${SUPPORTED[@]}"; do
    [[ "$VERSION" == "$v" ]] && ALLOWED=1
done

if [[ "$ALLOWED" != 1 ]]; then
    fail "Versi $VERSION tidak didukung."
    exit 1
fi

echo "BASH INSTALL PROTECT"
echo "Panel version: $VERSION"
echo

mkdir -p "$BACKUP"
STAMP="$(date +%Y%m%d-%H%M%S)"
DEST="$BACKUP/pre-install-$STAMP"

mkdir -p "$DEST"
cp -a "$PANEL/composer.lock" "$DEST/"
cp -a "$PANEL/composer.json" "$DEST/"
cp -a "$PANEL/app" "$DEST/"
cp -a "$PANEL/routes" "$DEST/"

ok "Backup aplikasi dibuat: $DEST"

echo
echo "Proteksi lama menggunakan penggantian controller penuh."
echo "Metode tersebut berisiko menghilangkan fungsi bawaan panel."
echo "Installer ini tidak akan menimpa controller secara membabi buta."
echo
echo "Pemeriksaan selesai. Belum ada perubahan pada panel."
echo "Lanjutkan dengan membuat modul proteksi yang diuji terpisah."
EOF

chmod +x protect.sh
