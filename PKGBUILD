# Maintainer: Raansu <Gero3977@gmail.com>

_srcname=rclone
pkgname=${_srcname}-bin
pkgver=1.62.2
pkgrel=1
pkgdesc="Sync files to and from Google Drive, S3, Swift, Cloudfiles, Dropbox and Google Cloud Storage."
provides=('rclone')
conflicts=('rclone')
url="https://rclone.org/"
license=('MIT')
arch=('i686' 'x86_64')
[[ "${CHOST}" =~ '-linux' ]] && { _OS=linux; arch+=('armv6h' 'armv7h' 'aarch64'); }
[[ "${CHOST}" =~ '-msys' ]] && _OS="windows"
[ "$CARCH" = 'i686' ] && _arch="${_OS}-386"
[ "$CARCH" = 'x86_64' ] && _arch="${_OS}-amd64"
[ "$CARCH" = 'armv6h' ] && _arch="${_OS}-arm-v6"
[ "$CARCH" = 'armv7h' ] && _arch="${_OS}-arm-v7"
[ "$CARCH" = 'aarch64' ] && _arch="${_OS}-arm64"
source=("https://raw.githubusercontent.com/ncw/rclone/v$pkgver/COPYING")
sha256sums=('8cd2e9e750b90a04b7d82dbbca3930c696ae0309d7c10464f90a44f45754cd04')
[[ "${CHOST}" =~ '-linux' ]] && {
source_i686=("https://github.com/ncw/rclone/releases/download/v$pkgver/rclone-v$pkgver-${_arch}.zip")
source_x86_64=("https://github.com/ncw/rclone/releases/download/v$pkgver/rclone-v$pkgver-${_arch}.zip")
source_armv6h=("https://github.com/rclone/rclone/releases/download/v$pkgver/rclone-v$pkgver-${_arch}.zip")
source_armv7h=("https://github.com/rclone/rclone/releases/download/v$pkgver/rclone-v$pkgver-${_arch}.zip")
source_aarch64=("https://github.com/rclone/rclone/releases/download/v$pkgver/rclone-v$pkgver-${_arch}.zip")
sha256sums_i686=('d3ca7fc7741d1c53f23d0412824e565483bca19a43258005abf2f41cb8e19fbc')
sha256sums_x86_64=('6c8676dc56e3d2e26358b5bae616ab3ec95e26181cd9b8692e101dcc0fc966a1')
sha256sums_armv6h=('310cc90d4dc88a16e78873ceb1eb4e337e8039ec392df36073900b766585d0fb')
sha256sums_armv7h=('2249bab380b8772c79a3f47caf4f0538e11c8e10acdc13c5292033fc403b10e9')
sha256sums_aarch64=('e921f0ac3edb45ea8f1c6b8110ed0be263aaedfb6a5ee98968d5836d3f1aadfc')
}
[[ "${CHOST}" =~ '-msys' ]] && {
source_i686=("https://github.com/ncw/rclone/releases/download/v$pkgver/rclone-v$pkgver-${_arch}.zip")
source_x86_64=("https://github.com/ncw/rclone/releases/download/v$pkgver/rclone-v$pkgver-${_arch}.zip")
sha256sums_i686=('5b91ee887762007cd9fef64003a70c496f855602d1bbb1c32a364008611f98ff')
sha256sums_x86_64=('85c623d7808f9d2cf51945e02e98d02b94f9f32ea892237f9a58b544c7a4f4f9')
}

package() {
  cd $srcdir/$_srcname-v$pkgver-$_arch

  install -Dm755 rclone "$pkgdir/usr/bin/rclone"

  install -Dm644 $srcdir/COPYING "$pkgdir/usr/share/licenses/$pkgname/COPYING"
  install -Dm644 rclone.1 "$pkgdir/usr/share/man/man1/rclone.1"
  install -d "$pkgdir/usr/share/doc/$pkgname"
  install -t "$pkgdir/usr/share/doc/$pkgname" -m644 README.html README.txt
}

