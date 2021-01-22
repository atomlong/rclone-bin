# Maintainer: Raansu <Gero3977@gmail.com>

pkgname=rclone-bin
_srcname=rclone
pkgver=1.53.4
pkgrel=1
pkgdesc="Sync files to and from Google Drive, S3, Swift, Cloudfiles, Dropbox and Google Cloud Storage."
provides=('rclone')
conflicts=('rclone')
url="https://rclone.org/"
license=('MIT')
depends=('glibc')
arch=('i686' 'x86_64' 'armv6h' 'armv7h' 'aarch64')
_arch='linux-386'
[ "$CARCH" = 'x86_64' ] && _arch='linux-amd64'
[[ "$CARCH" = 'armv6h' || "$CARCH" = 'armv7h' ||
"$CARCH" = 'arm' ]] && _arch='linux-arm'
[ "$CARCH" = 'aarch64' ] && _arch='linux-arm64'
source_i686=("https://github.com/ncw/rclone/releases/download/v$pkgver/rclone-v$pkgver-linux-386.zip")
source_x86_64=("https://github.com/ncw/rclone/releases/download/v$pkgver/rclone-v$pkgver-linux-amd64.zip")
source_arm=("https://github.com/ncw/rclone/releases/download/v$pkgver/rclone-v$pkgver-linux-arm.zip")
source_armv6h=("https://github.com/ncw/rclone/releases/download/v$pkgver/rclone-v$pkgver-linux-arm.zip")
source_armv7h=("https://github.com/ncw/rclone/releases/download/v$pkgver/rclone-v$pkgver-linux-arm.zip")
source_aarch64=("https://github.com/ncw/rclone/releases/download/v$pkgver/rclone-v$pkgver-linux-arm64.zip")
source=("https://raw.githubusercontent.com/ncw/rclone/v$pkgver/COPYING")
sha256sums=('8cd2e9e750b90a04b7d82dbbca3930c696ae0309d7c10464f90a44f45754cd04')
sha256sums_i686=('51f761bafcf6d711f67c026c3402f8c720acf8d3fd5e097534ecd70c254608e7')
sha256sums_x86_64=('5fd9abd29b8aa1ab0f195c33f78a476a6221d651b55ad4f913e3559b9904abc6')
sha256sums_armv6h=('c4b7fe4024dddcd0b1cf7258e37bb31a65ea34061a5c7dcc6419b2d7a42d118c')
sha256sums_armv7h=('c4b7fe4024dddcd0b1cf7258e37bb31a65ea34061a5c7dcc6419b2d7a42d118c')
sha256sums_aarch64=('68e0887977f3aabc5449bb66033e8a00811abe09a7e95354d1ff48a34965c594')

package() {
  cd $srcdir/$_srcname-v$pkgver-$_arch

  install -Dm755 rclone "$pkgdir/usr/bin/rclone"

  install -Dm644 $srcdir/COPYING "$pkgdir/usr/share/licenses/$pkgname/COPYING"
  install -Dm644 rclone.1 "$pkgdir/usr/share/man/man1/rclone.1"
  install -d "$pkgdir/usr/share/doc/$pkgname"
  install -t "$pkgdir/usr/share/doc/$pkgname" -m644 README.html README.txt
}

