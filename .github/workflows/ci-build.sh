#!/bin/bash

set -e

# AppVeyor and Drone Continuous Integration for MSYS2
# Author: Renato Silva <br.renatosilva@gmail.com>
# Author: Qian Hong <fracting@gmail.com>


# Enable colors
normal=$(tput sgr0)
red=$(tput setaf 1)
green=$(tput setaf 2)
cyan=$(tput setaf 6)

# Basic status function
_status() {
    local type="${1}"
    local status="${package:+${package}: }${2}"
    local items=("${@:3}")
    case "${type}" in
        failure) local -n nameref_color='red';   title='[MSYS2 CI] FAILURE:' ;;
        success) local -n nameref_color='green'; title='[MSYS2 CI] SUCCESS:' ;;
        message) local -n nameref_color='cyan';  title='[MSYS2 CI]'
    esac
    printf "\n${nameref_color}${title}${normal} ${status}\n\n"
    printf "${items:+\t%s\n}" "${items:+${items[@]}}"
}

# Get package information
_package_info() {
    local properties=("${@}")
    for property in "${properties[@]}"; do
        local -n nameref_property="${property}"
        eval nameref_property=($(
            source PKGBUILD
            declare -n nameref_property="${property}"
			printf "\"%s\" " "${nameref_property[@]}"))
    done
}

# record current commit hash of one package
_record_package_hash()
{
local package="${1}"
local marker="build.marker"
local commit_sha

commit_sha="$(git log --pretty=format:'%H' -1)"
rclone copy "${DEPLOY_PATH%/*}/${marker}" . &>/dev/null || touch "${marker}"
grep -Pq "^\s*\[[[:xdigit:]]+\]${package}\s*$" ${marker} && \
sed -i -r "s|^(\[)[[:xdigit:]]+(\]${package}\s*)$|\1${commit_sha}\2|g" "${marker}" || \
echo "[${commit_sha}]${package}" >> "${marker}"
rclone move "${marker}" "${DEPLOY_PATH%/*}"
return 0
}

# Lock the remote file to prevent it from being modified by another instance.
_lock_file()
{
local lockfile=${1}.lck
local instid=$$
local t_s last_s head_s
[ "${CI}" == "true" ] && instid="${CI_REPO}:${CI_BUILD_NUMBER}"
last_s=$(rclone lsjson ${lockfile} 2>/dev/null | jq '.[0]|.ModTime' | tr -d '"')
last_s=$([ -n "${last_s}" ] && date -d "${last_s}" "+%s" || echo 0)
t_s=$(date '+%s')
(( ${t_s}-${last_s} < 6*3600 )) && rclone copyto ${lockfile} lockfile.lck
echo "${instid}" >> lockfile.lck
sed -i '/^\s*$/d' lockfile.lck
rclone moveto lockfile.lck ${lockfile}

t_s=0
last_s=""
while true; do
head_s="$(rclone cat ${lockfile} 2>/dev/null | head -n 1)"
[ -z "${head_s}" ] && continue
[ "${head_s}" == "${instid}" ] && break
[ "${head_s}" == "${last_s}" ] && {
(( ($(date '+%s') - ${t_s}) > (30*60) )) && {
rclone cat ${lockfile} | awk "BEGIN {P=0} {if (\$1 != \"${head_s}\") P=1; if (P == 1 && NF) print}" > lockfile.lck
sed -i '/^\s*$/d' lockfile.lck
[ -s lockfile.lck ] && rclone moveto lockfile.lck ${lockfile} || {
rclone deletefile ${lockfile}
break
}
}
} || {
t_s=$(date '+%s')
last_s="${head_s}"
}
done
return 0
}

# Release the remote file to allow it to be modified by another instance.
_release_file()
{
local lockfile=${1}.lck
local instid=$$
[ "${CI}" == "true" ] && instid="${CI_REPO}:${CI_BUILD_NUMBER}"
rclone lsf ${lockfile} &>/dev/null || return 0
rclone cat ${lockfile} | awk "BEGIN {P=0} {if (\$1 != \"${instid}\") P=1; if (P == 1 && NF) print}" > lockfile.lck
[ -s lockfile.lck ] && rclone moveto lockfile.lck ${lockfile} || rclone deletefile ${lockfile}
rm -vf lockfile.lck
return 0
}

# Run command with status
execute(){
    local status="${1}"
    local command="${2}"
    local arguments=("${@:3}")
	[ -n "${package}" ] && pushd ${package}
    message "${status}"
    if [[ "${command}" != *:* ]]
        then ${command} ${arguments[@]}
        else ${command%%:*} | ${command#*:} ${arguments[@]}
    fi || failure "${status} failed"
    [ -n "${package}" ] && popd
}

# Status functions
failure() { local status="${1}"; local items=("${@:2}"); _status failure "${status}." "${items[@]}"; return 1; }
success() { local status="${1}"; local items=("${@:2}"); _status success "${status}." "${items[@]}"; return 0; }
message() { local status="${1}"; local items=("${@:2}"); _status message "${status}"  "${items[@]}"; }

# Add custom repositories to pacman
add_custom_repos()
{
[ -n "${CUSTOM_REPOS}" ] || { echo "You must set CUSTOM_REPOS firstly."; return 1; }
local repos=(${CUSTOM_REPOS//,/ })
local repo name err i
for repo in ${repos[@]}; do
name=$(sed -n -r 's/\[(\w+)\].*/\1/p' <<< ${repo})
[ -n "${name}" ] || continue
[ -z $(sed -rn "/^\[${name}]\s*$/p" /etc/pacman.conf) ] || continue
cp -vf /etc/pacman.conf{,.orig}
sed -r 's/]/&\nServer = /' <<< ${repo} >> /etc/pacman.conf
sed -i -r 's/^(SigLevel\s*=\s*).*/\1Never/' /etc/pacman.conf
for ((i=0; i<5; i++)); do
err=$(
LANG=en_US.UTF-8 pacman --sync --refresh --needed --noconfirm --disable-download-timeout ${name}-keyring 2>&1 | tee /proc/self/fd/2 | sed -n "/error: target not found: ${name}-keyring/p"
exit ${PIPESTATUS}
)
[ $? == 0 ] && break
[ -n "${err}" ] && break
done
[ -z "${err}" ] && name="" || name="SigLevel = Never\n"
mv -vf /etc/pacman.conf{.orig,}
sed -r "s/]/&\n${name}Server = /" <<< ${repo} >> /etc/pacman.conf
done
}

# Enable multilib repository
enable_multilib_repo()
{
[ "${PACMAN_ARCH}" == "x86_64" ] || [ "${PACMAN_ARCH}" == "i686" ] || return 0
[ -z $(sed -rn "/^\[multilib]\s*$/p" /etc/pacman.conf) ] || return 0
printf "[multilib]\nInclude = /etc/pacman.d/mirrorlist\n"  >> /etc/pacman.conf
}

# Add old packages repository
add_archive_repo()
{
local archive_repo
local archive_repo_sed archive_repo_sed_date
local i d

case "${PACMAN_ARCH}" in
	x86_64) archive_repo='https://archive.archlinux.org/repos/date/$repo/os/$arch' ;;
	arm*|aarch64) archive_repo='http://tardis.tiny-vps.com/aarm/repos/date/$arch/$repo' ;;
	*) return 0 ;;
esac

for ((i=1; i<=365; i++)); do
d=$(date -d "-${i} day" '+%Y/%m/%d')
archive_repo_sed_date=$(sed "s|date|${d}|" <<< "${archive_repo}")
archive_repo_sed="${archive_repo_sed_date//\//\\/}"
archive_repo_sed=${archive_repo_sed//$/\\$}
[ -z $(sed -rn "/^Server = ${archive_repo_sed}/p" /etc/pacman.d/mirrorlist) ] && \
printf "Server = ${archive_repo_sed_date}\n" >> /etc/pacman.d/mirrorlist
done
}

# Function: Sign one or more pkgballs.
create_package_signature()
{
[ -n "${PGP_KEY_PASSWD}" ] || { echo "You must set PGP_KEY_PASSWD firstly."; return 1; } 
local pkg

# signature for distrib packages.
(ls ${ARTIFACTS_PATH}/*${PKGEXT} &>/dev/null) && {
pushd ${ARTIFACTS_PATH}
for pkg in *${PKGEXT}; do
gpg --pinentry-mode loopback --passphrase "${PGP_KEY_PASSWD}" -o "${pkg}.sig" -b "${pkg}"
done
popd
}
return 0
}

# Import pgp private key
import_pgp_seckey()
{
[ -n "${PGP_KEY_PASSWD}" ] || { echo "You must set PGP_KEY_PASSWD firstly."; return 1; } 
[ -n "${PGP_KEY}" ] || { echo "You must set PGP_KEY firstly."; return 1; }
gpg --import --pinentry-mode loopback --passphrase "${PGP_KEY_PASSWD}" <<< "${PGP_KEY}"
}

# Build package
build_package()
{
[ -n "${ARTIFACTS_PATH}" ] || { echo "You must set ARTIFACTS_PATH firstly."; return 1; }
local pkgname item ret=0
unset PKGEXT
_package_info depends{,_${PACMAN_ARCH}} makedepends{,_${PACMAN_ARCH}} optdepends{,_${PACMAN_ARCH}} pkgname PKGEXT arch
[ -n "${PKGEXT}" ] || PKGEXT=$(grep -Po "^PKGEXT=('|\")?\K[^'\"]+" /etc/makepkg.conf)
export PKGEXT=${PKGEXT}

[ ${ret} == 0 ] && [ -n "${depends}" ] && { pacman -S --needed --noconfirm --disable-download-timeout ${depends[@]} || ret=1; }
[ ${ret} == 0 ] && [ -n "$(eval echo \${depends_${PACMAN_ARCH}})" ] && { eval pacman -S --needed --noconfirm --disable-download-timeout \${depends_${PACMAN_ARCH}[@]} || ret=1; }
[ ${ret} == 0 ] && [ -n "${makedepends}" ] && { pacman -S --needed --noconfirm --disable-download-timeout ${makedepends[@]} || ret=1; }
[ ${ret} == 0 ] && [ -n "$(eval echo \${makedepends_${PACMAN_ARCH}})" ] && { eval pacman -S --needed --noconfirm --disable-download-timeout \${makedepends_${PACMAN_ARCH}[@]} || ret=1; }
[ ${ret} == 0 ] && [ -n "${optdepends}" ] && {
optdepends=($(for ((i=0; i<${#optdepends[@]}; i++)); do grep -Po '^[^:]+' <<< "${optdepends[i]}"; done))
pacman -S --needed --noconfirm --disable-download-timeout ${optdepends[@]} || ret=1
}
[ ${ret} == 0 ] && [ -n "$(eval echo \${optdepends_${PACMAN_ARCH}})" ] && {
eval optdepends_${PACMAN_ARCH}="(\$(for ((i=0; i<\${#optdepends_${PACMAN_ARCH}[@]}; i++)); do grep -Po '^[^:]+' <<< \"\${optdepends[i]}\"; done))"
eval pacman -S --needed --noconfirm --disable-download-timeout \${optdepends_${PACMAN_ARCH}[@]} || ret=1
}
[ ${ret} == 0 ] && [ -n "${optdepends}" ] && { pacman -S --needed --noconfirm --disable-download-timeout ${optdepends[@]} || ret=1; }
[ ${ret} == 0 ] && [ -n "$(eval echo \${optdepends_${PACMAN_ARCH}})" ] && { eval pacman -S --needed --noconfirm --disable-download-timeout \${optdepends_${PACMAN_ARCH}[@]} || ret=1; }
[ ${ret} == 0 ] && { [ "${arch}" == any ] || grep -Pwq "${PACMAN_ARCH}" <<< ${arch[@]} || sed -i -r "s|^(arch=[^)]+)(\))|\1 ${PACMAN_ARCH}\2|" PKGBUILD; }

[ ${ret} == 0 ] && runuser -u alarm -- makepkg --noconfirm --skippgpcheck --nocheck --syncdeps --nodeps --cleanbuild

(ls *${PKGEXT} &>/dev/null) && {
mkdir -pv ${ARTIFACTS_PATH}
mv -vf *${PKGEXT} ${ARTIFACTS_PATH}
true
} || {
for item in ${pkgname[@]}; do
export FILED_PKGS=(${FILED_PKGS[@]} ${PACMAN_REPO}/${item})
done
}
return ${ret}
}

# deploy artifacts
deploy_artifacts()
{
[ -n "${DEPLOY_PATH}" ] || { echo "You must set DEPLOY_PATH firstly."; return 1; } 
local old_pkgs pkg file
(ls ${ARTIFACTS_PATH}/*${PKGEXT} &>/dev/null) || { echo "Skiped, no file to deploy"; return 0; }

_lock_file ${DEPLOY_PATH}/${PACMAN_REPO}.db

echo "Adding package information to datdabase ..."
pushd ${ARTIFACTS_PATH}
export PKG_FILES=(${PKG_FILES[@]} $(ls *${PKGEXT}))
for file in ${PACMAN_REPO}.{db,files}{,.tar.xz}{,.old}; do
rclone copy ${DEPLOY_PATH}/${file} ${PWD} 2>/dev/null || true
done
old_pkgs=($(repo-add "${PACMAN_REPO}.db.tar.xz" *${PKGEXT} | tee /proc/self/fd/2 | grep -Po "\bRemoving existing entry '\K[^']+(?=')"))
popd

echo "Tring to delete old files on remote server ..."
for pkg in ${old_pkgs[@]}; do
for file in ${pkg}-{${PACMAN_ARCH},any}${PKGEXT}{,.sig}; do
rclone deletefile ${DEPLOY_PATH}/${file} 2>/dev/null || true
done
done

echo "Uploading new files to remote server ..."
rclone copy ${ARTIFACTS_PATH} ${DEPLOY_PATH} --copy-links

_release_file ${DEPLOY_PATH}/${PACMAN_REPO}.db
_record_package_hash ${PACMAN_REPO}/${CI_REPO#*/}
}

# create mail message
create_mail_message()
{
local message item

[ -n "${PKG_FILES}" ] && {
message="<p>Successfully created the following package archive.</p>"
for item in ${PKG_FILES[@]}; do
message+="<p><font color=\"green\">${item}</font></p>"
done
}

[ -n "${FILED_PKGS}" ] && {
message+="<p>Failed to build following packages. </p>"
for item in ${FILED_PKGS[@]}; do
message+="<p><font color=\"red\">${item}</font></p>"
done
}

[ "${1}" ] && message+="<p>${1}<p>"

[ -n "${message}" ] && {
message+="<p>Architecture: ${PACMAN_ARCH}</p>"
message+="<p>Build Number: ${CI_BUILD_NUMBER}</p>"
echo ::set-output name=message::${message}
}

return 0
}

# Run from here
cd ${CI_BUILD_DIR}
message 'Install build environment.'
[ -z "${PACMAN_ARCH}" ] && export PACMAN_ARCH=$(sed -nr 's|^CARCH=\"(\w+).*|\1|p' /etc/makepkg.conf)
[ -z "${PACMAN_REPO}" ] && { echo "Environment variable 'PACMAN_REPO' is required."; exit 1; }
[ -z "${ARTIFACTS_PATH}" ] && export ARTIFACTS_PATH=artifacts/${PACMAN_ARCH}/${PACMAN_REPO}
[[ ${ARTIFACTS_PATH} =~ '$' ]] && eval export ARTIFACTS_PATH=${ARTIFACTS_PATH}
[ -z "${DEPLOY_PATH}" ] && { echo "Environment variable 'DEPLOY_PATH' is required."; exit 1; }
[[ ${DEPLOY_PATH} =~ '$' ]] && eval export DEPLOY_PATH=${DEPLOY_PATH}
[ -z "${RCLONE_CONF}" ] && { echo "Environment variable 'RCLONE_CONF' is required."; exit 1; }
[ -z "${PGP_KEY_PASSWD}" ] && { echo "Environment variable 'PGP_KEY_PASSWD' is required."; exit 1; }
[ -z "${PGP_KEY}" ] && { echo "Environment variable 'PGP_KEY' is required."; exit 1; }
[ -z "${CUSTOM_REPOS}" ] || {
CUSTOM_REPOS=$(sed -e 's/$arch\b/\\$arch/g' -e 's/$repo\b/\\$repo/g' <<< ${CUSTOM_REPOS})
[[ ${CUSTOM_REPOS} =~ '$' ]] && eval export CUSTOM_REPOS=${CUSTOM_REPOS}
add_custom_repos
}
enable_multilib_repo
add_archive_repo

for (( i=0; i<5; i++ )); do
pacman --sync --refresh --sysupgrade --needed --noconfirm --disable-download-timeout base-devel rclone git jq && break
done || {
create_mail_message "Failed to install build environment."
failure "Cannot install all required packages."
exit 1
}
[ -f /etc/default/useradd ] && {
DEFAULT_GROUP=$(grep -Po "^GROUP=\K\S+" /etc/default/useradd)
grep -Pq "^${DEFAULT_GROUP}:" /etc/group || groupadd "${DEFAULT_GROUP}"
}

getent group alarm &>/dev/null || groupadd alarm
getent passwd alarm &>/dev/null || useradd -m alarm -s "/bin/bash" -g "alarm"
chown -R alarm:alarm ${CI_BUILD_DIR}
getent group http &>/dev/null || groupadd -g 33 http
getent passwd http &>/dev/null || useradd -m -u 33 http -s "/usr/bin/nologin" -g "http" -d "/srv/http"

RCLONE_CONFIG_PATH=$(rclone config file | tail -n1)
mkdir -pv $(dirname ${RCLONE_CONFIG_PATH})
[ $(awk 'END{print NR}' <<< "${RCLONE_CONF}") == 1 ] &&
base64 --decode <<< "${RCLONE_CONF}" > ${RCLONE_CONFIG_PATH} ||
printf "${RCLONE_CONF}" > ${RCLONE_CONFIG_PATH}
import_pgp_seckey
trap "_release_file ${DEPLOY_PATH}/${PACMAN_REPO}.db" EXIT
success 'The build environment is ready successfully.'
# Build
execute 'Building packages' build_package
execute "Generating package signature" create_package_signature
success 'All packages built successfully'
execute "Deploying artifacts" deploy_artifacts
create_mail_message
success 'All artifacts have been deployed successfully'
