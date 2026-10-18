#!/usr/bin/env bash
# ======================================================================
#  VortexOS - 32 bit + 64 bit live/kurulabilir ISO derleme betiği
#
#  Taban     : Debian 12 "bookworm"  (32 bit desteği hâlâ var)
#  Masaüstü  : XFCE, Windows 10/11 düzeninde (alt görev çubuğu + başlat menüsü)
#  Kurulum   : Calamares (grafik kurulum, VortexOS markalı; canlı CD veya Installer girişi)
#  Dil       : Türkçe (TR klavye, İstanbul saati)
#
#  KULLANIM  (Debian 12 ya da Ubuntu 22.04/24.04 üzerinde, root ile):
#     sudo ./vortexos-build.sh all     # 64 bit + 32 bit
#     sudo ./vortexos-build.sh 64      # sadece 64 bit
#     sudo ./vortexos-build.sh 32      # sadece 32 bit
#
#  İPUCU: Hata çıkarsa temiz bir Debian 12 sanal makinesinde deneyin.
#  Gereksinim: ~25 GB boş disk, 4 GB RAM, internet, her ISO için 20-60 dk.
#  Çıktı: ./output/vortexos-1.0-beta-amd64.iso  ve  vortexos-1.0-beta-i386.iso
# ======================================================================
set -euo pipefail

NAME="VortexOS"
SLUG="vortexos"
VERSION="1.0-beta"
DIST="${DIST:-bookworm}"
TARGET="${1:-all}"
BASE="$PWD"
OUT="$BASE/output"

[[ $EUID -eq 0 ]] || { echo "Root olarak çalıştırın: sudo $0 $TARGET" >&2; exit 1; }
case "$TARGET" in all|64|32) ;; *) echo "Kullanım: $0 [all|64|32]" >&2; exit 1;; esac

echo ">> Gerekli araçlar kuruluyor..."
apt-get update
apt-get install -y live-build debootstrap squashfs-tools xorriso \
    isolinux syslinux syslinux-common grub-pc-bin grub-efi-amd64-bin \
    mtools dosfstools imagemagick

mkdir -p "$OUT"

# ----------------------------------------------------------------------
# Duvar kağıdı (host'ta üretilir)
# ----------------------------------------------------------------------
make_wallpaper() {
  convert -size 1920x1080 radial-gradient:'#2f86ff-#050b24' \
          -swirl 220 \
          -fill 'rgba(255,255,255,0.06)' -draw 'circle 1450,300 1450,720' \
          "$1"
}

# ----------------------------------------------------------------------
# Tek bir mimari için yapılandır + derle
#   $1 = etiket (amd64|i386)   $2 = çekirdek türü   $3 = önyükleyiciler
# ----------------------------------------------------------------------
build_one() {
  local ARCH="$1" FLAVOUR="$2" BOOTLOADERS="$3"
  local W="$BASE/build-$SLUG-$ARCH"

  echo
  echo "################ $NAME $ARCH derleniyor ################"
  rm -rf "$W"; mkdir -p "$W"; cd "$W"

  # Canlı sistem açılış parametreleri (varsayılan dil İngilizce, klavye Türkçe Q)
  local LIVEAPPEND="boot=live components quiet locales=en_US.UTF-8 keyboard-layouts=tr timezone=Europe/Istanbul username=vortex hostname=$SLUG"

  lb config \
    --distribution "$DIST" \
    --architectures "$ARCH" \
    --linux-flavours "$FLAVOUR" \
    --binary-images iso-hybrid \
    --bootloaders "$BOOTLOADERS" \
    --archive-areas "main contrib non-free non-free-firmware" \
    --apt-recommends false \
    --apt-indices false \
    --memtest none \
    --chroot-squashfs-compression-type xz \
    --debian-installer none \
    --iso-application "$NAME" \
    --iso-volume "${NAME^^}" \
    --iso-publisher "$NAME Projesi" \
    --image-name "$SLUG-$VERSION" \
    --bootappend-live "$LIVEAPPEND"

  # ------------------------------------------------------------------
  # 1) PAKETLER  (öneriler kapalı, sadece gerekenler)
  # ------------------------------------------------------------------
  mkdir -p config/package-lists
  cat > config/package-lists/$SLUG.list.chroot <<'EOF'
# --- Grafik sunucu ---
xserver-xorg-core
xserver-xorg-input-libinput
xserver-xorg-video-all
x11-xserver-utils
dbus-x11
policykit-1
# --- Giriş ekranı ---
lightdm
lightdm-gtk-greeter
# --- XFCE (Windows 10/11 benzeri düzen için) ---
xfce4-session
xfwm4
xfdesktop4
xfce4-panel
xfce4-settings
xfce4-whiskermenu-plugin
xfce4-pulseaudio-plugin
xfce4-notifyd
xfce4-power-manager
xfce4-terminal
xfce4-taskmanager
thunar
thunar-volman
gvfs
udisks2
mousepad
ristretto
xarchiver
# --- Görünüm ---
arc-theme
papirus-icon-theme
adwaita-icon-theme
fonts-dejavu-core
fonts-liberation
# --- Ağ / ses ---
network-manager
network-manager-gnome
wpasupplicant
wireless-tools
rfkill
pulseaudio
pulseaudio-utils
alsa-utils
pavucontrol
# --- Wi-Fi bellenimleri (istemezseniz silin, ISO küçülür) ---
firmware-iwlwifi
firmware-realtek
firmware-atheros
firmware-misc-nonfree
# --- Tarayıcı (hafif sürüm için firefox-esr yerine netsurf-gtk yazın) ---
firefox-esr
firefox-esr-l10n-tr
# --- Sistem ---
sudo
locales
console-setup
keyboard-configuration
zram-tools
htop
xdg-utils
desktop-file-utils
lsb-release
# --- Calamares grafik kurulum programı (VortexOS markalı) ---
calamares
calamares-settings-debian
qml-module-qtquick2
os-prober
rsync
squashfs-tools
parted
gdisk
cryptsetup
lvm2
ntfs-3g
dosfstools
e2fsprogs
btrfs-progs
xfsprogs
mtools
kpartx
efibootmgr
grub2-common
grub-pc-bin
# --- Araçlar (Utilities menüsü ve disk kontrolü) ---
memtest86+
smartmontools
EOF

  # amd64: UEFI önyükleme için ek paketler
  if [ "$ARCH" = "amd64" ]; then
    printf 'grub-efi-amd64-bin\ngrub-efi-amd64-signed\nshim-signed\n' \
      > config/package-lists/$SLUG-efi.list.chroot
  fi

  # ------------------------------------------------------------------
  # 2) Ayar dosyaları (yeni kullanıcıya /etc/skel ile kopyalanır)
  # ------------------------------------------------------------------
  local I="config/includes.chroot"
  local X="$I/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml"
  mkdir -p "$X" "$I/etc/skel/.config/xfce4/panel" "$I/usr/share/backgrounds" \
           "$I/etc/default" "$I/etc/lightdm"

  make_wallpaper "$I/usr/share/backgrounds/vortexos.png"

  # Calamares kurulum programı için logo ve karşılama görseli
  mkdir -p "$I/usr/share/vortexos-brand"
  convert -size 256x256 radial-gradient:'#8fe0ff-#0b4f9c' -swirl 250 \
          "$I/usr/share/vortexos-brand/logo.png"
  convert "$I/usr/share/backgrounds/vortexos.png" -resize 1280x720 \
          "$I/usr/share/vortexos-brand/welcome.png"

  # Windows 10/11 tarzı alt görev çubuğu: Başlat | Görevler | ... | Tepsi | Ses | Saat
  cat > "$X/xfce4-panel.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
    <property name="panel-1" type="empty">
      <property name="position" type="string" value="p=8;x=0;y=0"/>
      <property name="length" type="uint" value="100"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="size" type="uint" value="40"/>
      <property name="dark-mode" type="bool" value="true"/>
      <property name="plugin-ids" type="array">
        <value type="int" value="1"/>
        <value type="int" value="2"/>
        <value type="int" value="3"/>
        <value type="int" value="4"/>
        <value type="int" value="5"/>
        <value type="int" value="6"/>
      </property>
    </property>
  </property>
  <property name="plugins" type="empty">
    <property name="plugin-1" type="string" value="whiskermenu"/>
    <property name="plugin-2" type="string" value="tasklist">
      <property name="grouping" type="uint" value="0"/>
      <property name="show-labels" type="bool" value="true"/>
      <property name="flat-buttons" type="bool" value="true"/>
    </property>
    <property name="plugin-3" type="string" value="separator">
      <property name="expand" type="bool" value="true"/>
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-4" type="string" value="systray"/>
    <property name="plugin-5" type="string" value="pulseaudio"/>
    <property name="plugin-6" type="string" value="clock">
      <property name="mode" type="uint" value="2"/>
      <property name="digital-layout" type="uint" value="2"/>
      <property name="digital-time-format" type="string" value="%H:%M"/>
      <property name="digital-date-format" type="string" value="%d.%m.%Y"/>
    </property>
  </property>
</channel>
EOF

  cat > "$I/etc/skel/.config/xfce4/panel/whiskermenu-1.rc" <<'EOF'
button-icon=start-here
show-button-title=false
show-button-icon=true
favorites=firefox-esr.desktop,thunar.desktop,xfce4-terminal.desktop,xfce-settings-manager.desktop
EOF

  cat > "$X/xsettings.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="Arc-Dark"/>
    <property name="IconThemeName" type="string" value="Papirus-Dark"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="FontName" type="string" value="DejaVu Sans 10"/>
  </property>
</channel>
EOF

  # Pencere butonları sağda (küçült / büyüt / kapat), kompozitör kapalı = eski PC'de hızlı
  cat > "$X/xfwm4.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="Arc-Dark"/>
    <property name="button_layout" type="string" value="|HMC"/>
    <property name="title_alignment" type="string" value="left"/>
    <property name="use_compositing" type="bool" value="false"/>
  </property>
</channel>
EOF

  printf '[greeter]\nbackground=/usr/share/backgrounds/vortexos.png\ntheme-name=Arc-Dark\nicon-theme-name=Papirus-Dark\n' \
      > "$I/etc/lightdm/lightdm-gtk-greeter.conf"

  # Az RAM'li PC'ler için sıkıştırılmış takas (zram)
  printf 'ALGO=lz4\nPERCENT=50\n' > "$I/etc/default/zramswap"

  # ------------------------------------------------------------------
  # 3) Kanca: markalama + masaüstü kısayolları + boyut küçültme
  # ------------------------------------------------------------------
  mkdir -p config/hooks/live
  cat > config/hooks/live/0100-vortexos.hook.chroot <<'HOOK'
#!/bin/bash
set -e

# --- Sistem adı ---
cat > /etc/os-release <<OSR
PRETTY_NAME="VortexOS 1.0 Beta"
NAME="VortexOS"
VERSION_ID="1.0"
VERSION="1.0 Beta"
ID=vortexos
ID_LIKE=debian
OSR
printf 'VortexOS 1.0 Beta \\n \\l\n\n' > /etc/issue
echo 'VortexOS 1.0 Beta' > /etc/issue.net

# --- Sistem özellikleri / "Hakkında" ekranı / kurulu sistemin GRUB menüsü ---
cat > /etc/lsb-release <<LSB
DISTRIB_ID=VortexOS
DISTRIB_RELEASE="1.0 Beta"
DISTRIB_CODENAME=vortex
DISTRIB_DESCRIPTION="VortexOS 1.0 Beta"
LSB
sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME="VortexOS 1.0 Beta"/' /usr/lib/os-release 2>/dev/null || true
printf '\nVortexOS 1.0 Beta - Hizli, sade, her tik bir adim.\n\n' > /etc/motd
mkdir -p /etc/default
if [ -f /etc/default/grub ]; then
  sed -i '/^GRUB_DISTRIBUTOR=/d' /etc/default/grub
  echo 'GRUB_DISTRIBUTOR=VortexOS' >> /etc/default/grub
fi

# --- Türkçe yerel ayar ---
sed -i 's/^# *\(tr_TR.UTF-8\)/\1/; s/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen
locale-gen || true

# --- Masaüstü simgeleri: her şey bir tık uzakta ---
mkdir -p /etc/skel/Desktop
for app in firefox-esr netsurf-gtk thunar xfce-settings-manager xfce4-terminal; do
  f="/usr/share/applications/$app.desktop"
  if [ -f "$f" ]; then
    cp "$f" /etc/skel/Desktop/
    chmod +x "/etc/skel/Desktop/$app.desktop"
  fi
done

# --- Duvar kağıdı (monitör adı ne olursa olsun) ---
D=/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml
mkdir -p "$D"
{
  echo '<?xml version="1.0" encoding="UTF-8"?>'
  echo '<channel name="xfce4-desktop" version="1.0">'
  echo ' <property name="backdrop" type="empty">'
  echo '  <property name="screen0" type="empty">'
  for m in monitor0 monitorVGA-1 monitorVGA1 monitorLVDS-1 monitorLVDS1 monitorHDMI-1 \
           monitoreDP-1 monitoreDP1 monitorDP-1 monitorDVI-I-1 monitorVirtual-1 monitorVirtual1; do
    echo "   <property name=\"$m\" type=\"empty\">"
    echo '    <property name="workspace0" type="empty">'
    echo '     <property name="color-style" type="int" value="0"/>'
    echo '     <property name="image-style" type="int" value="5"/>'
    echo '     <property name="last-image" type="string" value="/usr/share/backgrounds/vortexos.png"/>'
    echo '    </property>'
    echo '   </property>'
  done
  echo '  </property>'
  echo ' </property>'
  echo '</channel>'
} > "$D/xfce4-desktop.xml"

# --- Hızlı açılış: gereksiz servisleri kapat ---
systemctl disable NetworkManager-wait-online.service 2>/dev/null || true
systemctl disable apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true

# --- Calamares (grafik kurulum) VortexOS markası ---
for B in /etc/calamares/branding/vortexos /usr/share/calamares/branding/vortexos; do
  mkdir -p "$B"
  cat > "$B/branding.desc" <<'BRD'
---
componentName:  vortexos
welcomeStyleCalamares: true
welcomeExpandingLogo: true
windowExpanding: normal
windowSize: 800px,520px
windowPlacement: center
strings:
    productName:         VortexOS GNU/Linux
    shortProductName:    VortexOS
    version:             1.0 Beta
    shortVersion:        1.0 Beta
    versionedName:       VortexOS GNU/Linux 1.0 Beta
    shortVersionedName:  VortexOS 1.0 Beta
    bootloaderEntryName: VortexOS
    productUrl:          https://example.com/vortexos
    supportUrl:          https://example.com/vortexos
    knownIssuesUrl:      https://example.com/vortexos
    releaseNotesUrl:     https://example.com/vortexos
images:
    productLogo:         "logo.png"
    productIcon:         "logo.png"
    productWelcome:      "welcome.png"
slideshow:               "show.qml"
style:
    sidebarBackground:    "#0b1f3a"
    sidebarText:          "#FFFFFF"
    sidebarTextSelect:    "#2f86ff"
    sidebarTextHighlight: "#1a4f9c"
BRD
  cp /usr/share/vortexos-brand/logo.png "$B/logo.png"
  cp /usr/share/vortexos-brand/welcome.png "$B/welcome.png"
  cat > "$B/show.qml" <<'QML'
import QtQuick 2.0;
import calamares.slideshow 1.0;

Presentation {
    id: presentation
    Slide {
        Rectangle { anchors.fill: parent; color: "#0b1f3a" }
        Text {
            anchors.centerIn: parent
            text: "VortexOS kuruluyor...\nHızlı, sade, her şey bir tık uzakta."
            color: "white"
            font.pixelSize: 22
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
QML
done

# Calamares ayarları: marka VortexOS, canlı kullanıcı vortex silinsin,
# eski PC'ler için RAM/disk şartları gevşetilsin
if [ -f /etc/calamares/settings.conf ]; then
  sed -i 's/^branding:.*/branding: vortexos/' /etc/calamares/settings.conf
fi
if [ -f /etc/calamares/modules/removeuser.conf ]; then
  sed -i 's/^username:.*/username: vortex/' /etc/calamares/modules/removeuser.conf
fi
if [ -f /etc/calamares/modules/welcome.conf ]; then
  sed -i -e 's/^\( *requiredRam:\).*/\1 0.4/' \
         -e 's/^\( *requiredStorage:\).*/\1 4/' /etc/calamares/modules/welcome.conf
fi

if [ -f /etc/calamares/modules/users.conf ]; then
  sed -i -e 's/^\( *\)allowWeakPasswords:.*/\1allowWeakPasswords: true/' \
         -e 's/^\( *\)allowWeakPasswordsDefault:.*/\1allowWeakPasswordsDefault: true/' \
         -e 's/^\( *\)minLength:.*/\1minLength: -1/' /etc/calamares/modules/users.conf
fi

# Masaüstü ve menüdeki kurulum kısayolu: "VortexOS'u Kur"
rm -f /usr/share/applications/*install-debian*.desktop 2>/dev/null || true
cat > /usr/share/applications/vortexos-install.desktop <<'DSK'
[Desktop Entry]
Type=Application
Name=VortexOS 1.0 Beta Setup
Name[tr]=VortexOS 1.0 Beta Kur
Comment=Install VortexOS on this computer
Comment[tr]=VortexOS'u bilgisayara kur
Exec=sudo -E calamares
Icon=system-software-install
Terminal=false
Categories=System;
DSK

# --- Canlı (live) oturum: kullanıcı vortex / şifre vortex + otomatik giriş ---
# Bu servis SADECE canlı açılışta çalışır (kernel satırında boot=live varsa).
# Diske kurulan sistemde otomatik giriş ve hazır kullanıcı OLMAZ:
# kurulum normal şekilde kullanıcı adı + şifre sorar.
mkdir -p /usr/local/sbin
cat > /usr/local/sbin/vortexos-live-setup <<'VSETUP'
#!/bin/sh
if ! id vortex >/dev/null 2>&1; then
  useradd -m -s /bin/bash vortex
fi
echo 'vortex:vortex' | chpasswd
for g in sudo audio video plugdev netdev cdrom dialout floppy lpadmin scanner bluetooth; do
  if getent group "$g" >/dev/null 2>&1; then usermod -aG "$g" vortex || true; fi
done
mkdir -p /etc/sudoers.d
echo 'vortex ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/vortex
chmod 440 /etc/sudoers.d/vortex
mkdir -p /etc/lightdm/lightdm.conf.d
printf '[Seat:*]\nautologin-user=vortex\nautologin-user-timeout=0\n' > /etc/lightdm/lightdm.conf.d/50-vortexos-live.conf
mkdir -p /home/vortex/Desktop
if grep -qw vortexos-installer /proc/cmdline; then
  # "VortexOS Installer" seçildi: masaüstü simgeleri olmasın, kurulum ekranı açılsın
  rm -rf /home/vortex/Desktop/* 2>/dev/null || true
  mkdir -p /home/vortex/.config/autostart
  cat > /home/vortex/.config/autostart/vortexos-installer.desktop <<'AUT'
[Desktop Entry]
Type=Application
Name=VortexOS 1.0 Beta Setup
Exec=sudo -E calamares
Terminal=false
AUT
else
  # Normal canlı oturum: masaüstünde kurulum simgesi
  cp /usr/share/applications/vortexos-install.desktop /home/vortex/Desktop/
  chmod +x /home/vortex/Desktop/vortexos-install.desktop
fi
chown -R vortex:vortex /home/vortex
VSETUP
chmod +x /usr/local/sbin/vortexos-live-setup
cat > /etc/systemd/system/vortexos-live.service <<'VSVC'
[Unit]
Description=VortexOS canli oturum kullanicisi ve otomatik giris
ConditionKernelCommandLine=boot=live
After=live-config.service local-fs.target
Before=display-manager.service lightdm.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/vortexos-live-setup
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
VSVC
mkdir -p /etc/systemd/system/multi-user.target.wants
ln -sf /etc/systemd/system/vortexos-live.service /etc/systemd/system/multi-user.target.wants/vortexos-live.service

# --- Kurulu sistem: şifre boşsa otomatik giriş, şifre varsa giriş ekranı ---
# Bu servis canlı oturumda ÇALIŞMAZ (boot=live varsa atlanır), sadece diske kurulu sistemde.
cat > /usr/local/sbin/vortexos-autologin-check <<'VAUTO'
#!/bin/sh
CONF=/etc/lightdm/lightdm.conf.d/60-vortexos-autologin.conf
# Kurulumda oluşturulan ilk normal kullanıcı
U=$(awk -F: '$3>=1000 && $3<60000 {print $1; exit}' /etc/passwd)
[ -n "$U" ] || exit 0
H=$(awk -F: -v u="$U" '$1==u {print $2}' /etc/shadow)
case "$H" in
  ""|"!"|"*"|"!*")
    # Şifre koyulmamış: giriş ekranı olmadan masaüstü açılsın
    mkdir -p /etc/lightdm/lightdm.conf.d
    printf '[Seat:*]\nautologin-user=%s\nautologin-user-timeout=0\n' "$U" > "$CONF"
    ;;
  *)
    # Şifre var: giriş ekranı gelsin, doğru şifre girilince açılsın
    rm -f "$CONF"
    ;;
esac
VAUTO
chmod +x /usr/local/sbin/vortexos-autologin-check
cat > /etc/systemd/system/vortexos-autologin.service <<'VAUS'
[Unit]
Description=VortexOS kurulu sistem otomatik giris denetimi
ConditionKernelCommandLine=!boot=live
After=local-fs.target
Before=display-manager.service lightdm.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/vortexos-autologin-check
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
VAUS
ln -sf /etc/systemd/system/vortexos-autologin.service /etc/systemd/system/multi-user.target.wants/vortexos-autologin.service

# --- ISO boyutunu küçült ---
find /usr/share/locale -mindepth 1 -maxdepth 1 \
     ! -name 'tr*' ! -name 'en*' ! -name 'locale.alias' -exec rm -rf {} + 2>/dev/null || true
find /usr/share/doc -type f ! -name copyright -delete 2>/dev/null || true
find /usr/share/doc -type d -empty -delete 2>/dev/null || true
rm -rf /usr/share/man/* /usr/share/info/* /var/cache/apt/* /var/lib/apt/lists/* 2>/dev/null || true
HOOK
  chmod +x config/hooks/live/0100-vortexos.hook.chroot

  # ------------------------------------------------------------------
  # 3b) Açılış menüsü (syslinux + GRUB) VortexOS olsun
  #     ISO yapılmadan hemen önce, ikili ağaçtaki menü dosyalarını düzeltir
  # ------------------------------------------------------------------
  mkdir -p config/hooks/normal
  cat > config/hooks/normal/9000-vortexos-boot.hook.binary <<'BHOOK'
#!/bin/bash
# live-build çalışma klasörü sürüme göre değişebilir; "binary" ağacını bul
ROOT=""
for D in binary . ..; do
  if [ -d "$D/isolinux" ] || [ -d "$D/boot/grub" ]; then ROOT="$D"; break; fi
done
[ -n "$ROOT" ] || { echo "VortexOS: ikili ağaç bulunamadı, menü atlandı"; exit 0; }
ARCH="__ARCH__"
APPEND="__APPEND__"

# Menü yazılarında Debian / Live system yerine VortexOS
for F in "$ROOT"/isolinux/*.cfg "$ROOT"/syslinux/*.cfg "$ROOT"/boot/grub/*.cfg "$ROOT"/EFI/boot/*.cfg; do
  [ -f "$F" ] || continue
  sed -i \
    -e 's/Debian GNU\/Linux/VortexOS/g' \
    -e 's/Debian Live/VortexOS Live/g' \
    -e 's/Live system/VortexOS Live CD/g' \
    -e 's/Debian/VortexOS/g' "$F"
done

# Memtest86+ varsa ISO'ya kopyala (Utilities menüsü için)
MEMT=""
if [ "$ARCH" = "amd64" ]; then NAMES="memtest86+x64.bin memtest86+ia32.bin memtest86+.bin"; else NAMES="memtest86+ia32.bin memtest86+.bin"; fi
for C in chroot "$ROOT/../chroot" ../chroot; do
  [ -d "$C/boot" ] || continue
  for N in $NAMES; do
    if [ -f "$C/boot/$N" ]; then
      mkdir -p "$ROOT/live"
      cp "$C/boot/$N" "$ROOT/live/memtest.bin"
      MEMT=/live/memtest.bin
      break 2
    fi
  done
done

# BIOS (syslinux) menüsü
if [ -d "$ROOT/isolinux" ]; then
  cat > "$ROOT/isolinux/live.cfg" <<LCFG
label live
  menu label ^VortexOS Live CD ($ARCH)
  menu default
  linux /live/vmlinuz
  initrd /live/initrd.img
  append $APPEND

label command
  menu label VortexOS Live CD ^Command ($ARCH)
  linux /live/vmlinuz
  initrd /live/initrd.img
  append $APPEND systemd.unit=multi-user.target

label installer
  menu label VortexOS ^Installer
  linux /live/vmlinuz
  initrd /live/initrd.img
  append $APPEND vortexos-installer

menu begin advanced
  menu title Advanced options
  label mainmenu
    menu label ^Back..
    menu exit
  label failsafe
    menu label VortexOS Live CD ($ARCH fail-safe mode)
    linux /live/vmlinuz
    initrd /live/initrd.img
    append boot=live components nomodeset noapic noapm nodma nomce nolapic nosmp nosplash locales=en_US.UTF-8 keyboard-layouts=tr timezone=Europe/Istanbul username=vortex hostname=vortexos
  label toram
    menu label VortexOS Live CD ($ARCH, copy to RAM)
    linux /live/vmlinuz
    initrd /live/initrd.img
    append $APPEND toram
menu end
LCFG
  if [ -n "$MEMT" ]; then
    cat >> "$ROOT/isolinux/live.cfg" <<MCFG

menu begin utilities
  menu title Utilities
  label mainmenu
    menu label ^Back..
    menu exit
  label memtest
    menu label ^Memory test (Memtest86+)
    linux $MEMT
menu end
MCFG
  fi
fi

# UEFI (GRUB) menüsü: mevcut girişlerin yanına ekle
if [ -f "$ROOT/boot/grub/grub.cfg" ]; then
  cat >> "$ROOT/boot/grub/grub.cfg" <<GCFG

menuentry "VortexOS Live CD Command ($ARCH)" {
  linux /live/vmlinuz $APPEND systemd.unit=multi-user.target
  initrd /live/initrd.img
}

menuentry "VortexOS Installer" {
  linux /live/vmlinuz $APPEND vortexos-installer
  initrd /live/initrd.img
}
GCFG
fi

# Açılış arka planı: VortexOS duvar kağıdı, 640x480'e orantılı kırpılır (bozuk görünmesin)
for S in "$ROOT"/isolinux/splash.png "$ROOT"/boot/grub/splash.png; do
  if [ -f "$S" ]; then
    convert "__WALL__" -resize 640x480^ -gravity center -extent 640x480 "$S" 2>/dev/null || true
  fi
done
exit 0
BHOOK
  sed -i -e "s|__WALL__|$PWD/config/includes.chroot/usr/share/backgrounds/vortexos.png|" \
         -e "s|__ARCH__|$ARCH|g" \
         -e "s|__APPEND__|$LIVEAPPEND|g" \
      config/hooks/normal/9000-vortexos-boot.hook.binary
  chmod +x config/hooks/normal/9000-vortexos-boot.hook.binary

  # ------------------------------------------------------------------
  # 4) DERLE
  # ------------------------------------------------------------------
  lb build 2>&1 | tee build.log

  local ISO
  ISO=$(ls -1 ./*.iso 2>/dev/null | head -n1 || true)
  if [[ -z "$ISO" ]]; then
    echo "!! $ARCH için ISO oluşmadı. Bakın: $W/build.log" >&2
    cd "$BASE"; return 1
  fi
  mv "$ISO" "$OUT/$SLUG-$VERSION-$ARCH.iso"
  echo ">> Hazır: $OUT/$SLUG-$VERSION-$ARCH.iso ($(du -h "$OUT/$SLUG-$VERSION-$ARCH.iso" | cut -f1))"
  cd "$BASE"
}

[[ "$TARGET" == "64" || "$TARGET" == "all" ]] && build_one amd64 amd64 "syslinux,grub-efi"
[[ "$TARGET" == "32" || "$TARGET" == "all" ]] && build_one i386  686   "syslinux"

echo
echo "=============================================================="
echo " Bitti. ISO dosyaları: $OUT"
ls -lh "$OUT"/*.iso
echo
echo " Test (64 bit): qemu-system-x86_64 -m 512 -cdrom $OUT/$SLUG-$VERSION-amd64.iso"
echo " Test (32 bit): qemu-system-i386   -m 512 -cdrom $OUT/$SLUG-$VERSION-i386.iso"
echo " USB'ye yaz   : sudo dd if=<iso> of=/dev/sdX bs=4M status=progress && sync"
echo "=============================================================="
