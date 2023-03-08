# Maintainer: Raansu <Gero3977@gmail.com>

pkgname=rclone-bin
_srcname=rclone
pkgver=1.61.1
pkgrel=1
pkgdesc="Sync files to and from Google Drive, S3, Swift, Cloudfiles, Dropbox and Google Cloud Storage."
provides=('rclone')
conflicts=('rclone')
url="https://rclone.org/"
license=('MIT')
arch=('i686' 'x86_64')
_arch='windows-386'
[ "$CARCH" = 'x86_64' ] && _arch='windows-amd64'
source_i686=("https://github.com/ncw/rclone/releases/download/v$pkgver/rclone-v$pkgver-windows-386.zip")
source_x86_64=("https://github.com/ncw/rclone/releases/download/v$pkgver/rclone-v$pkgver-windows-amd64.zip")
source=("https://raw.githubusercontent.com/ncw/rclone/v$pkgver/COPYING")
sha256sums=('8cd2e9e750b90a04b7d82dbbca3930c696ae0309d7c10464f90a44f45754cd04')
sha256sums_i686=('79ae4620212f13c7881985eb57c819c01e8faa66b14ec44827a641848d93b76b')
sha256sums_x86_64=('99daaa95867cdf0758ec1d5d7f2ebdb3bf74c8c8602e2aaf888e637163d2ebdd')

package() {
  cd $srcdir/$_srcname-v$pkgver-$_arch

  install -Dm755 rclone "$pkgdir/usr/bin/rclone"

  install -Dm644 $srcdir/COPYING "$pkgdir/usr/share/licenses/$pkgname/COPYING"
  install -Dm644 rclone.1 "$pkgdir/usr/share/man/man1/rclone.1"
  install -d "$pkgdir/usr/share/doc/$pkgname"
  install -t "$pkgdir/usr/share/doc/$pkgname" -m644 README.html README.txt
}

