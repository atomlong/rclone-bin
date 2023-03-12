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

# get last commit hash of one package
_last_package_hash()
{
local package="${PACMAN_REPO}/${CI_REPO#*/}"
local marker="build.marker"
rclone cat "${PKG_DEPLOY_PATH}/${marker}" 2>/dev/null | sed -rn "s|^\[([[:xdigit:]]+)\]${package}\s*$|\1|p"
return 0
}

# get current commit hash of one package
_now_package_hash()
{
git log --pretty=format:'%H' -1 2>/dev/null
return 0
}

# record current commit hash of one package
_record_package_hash()
{
local package="${PACMAN_REPO}/${CI_REPO#*/}"
local marker="build.marker"
local commit_sha

_lock_file "${PKG_DEPLOY_PATH}/${marker}"
commit_sha="$(_now_package_hash)"
rclone lsf "${PKG_DEPLOY_PATH}/${marker}" &>/dev/null && while ! rclone copy "${PKG_DEPLOY_PATH}/${marker}" . &>/dev/null; do :; done || touch "${marker}"
grep -Pq "\[[[:xdigit:]]+\]${package}\s*$" ${marker} && \
sed -i -r "s|^(\[)[[:xdigit:]]+(\]${package}\s*)$|\1${commit_sha}\2|g" "${marker}" || \
echo "[${commit_sha}]${package}" >> "${marker}"
rclone move "${marker}" "${PKG_DEPLOY_PATH}"
_release_file "${PKG_DEPLOY_PATH}/${marker}"
return 0
}

# Run command with status
execute(){
    local status="${1}"
    local command="${2}"
    local arguments=("${@:3}")
    message "${status}"
    if [[ "${command}" != *:* ]]
        then ${command} ${arguments[@]}
        else ${command%%:*} | ${command#*:} ${arguments[@]}
    fi || failure "${status} failed"
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
local repo name
for repo in ${repos[@]}; do
name=$(sed -n -r 's/\[(\w+)\].*/\1/p' <<< ${repo})
[ -n "${name}" ] || continue
[ -z $(sed -rn "/^\\[${name}]\s*$/p" /etc/pacman.conf) ] || continue
cp -vf /etc/pacman.conf{,.orig}
sed -r 's/]/&\nServer = /' <<< ${repo} >> /etc/pacman.conf
sed -i -r 's/^(SigLevel\s*=\s*).*/\1Never/' /etc/pacman.conf
pacman --sync --refresh --needed --noconfirm --disable-download-timeout ${name}-keyring && name="" || name="SigLevel = Never\n"
mv -vf /etc/pacman.conf{.orig,}
sed -r "s/]/&\n${name}Server = /" <<< ${repo} >> /etc/pacman.conf
done
}

# Function: Sign one or more pkgballs.
create_package_signature()
{
[ -n "${PGP_KEY_PASSWD}" ] || { echo "You must set PGP_KEY_PASSWD firstly."; return 1; }
local pkg
# signature for distrib packages.
(ls ${PKG_ARTIFACTS_PATH}/*${PKGEXT} &>/dev/null) && {
pushd ${PKG_ARTIFACTS_PATH}
for pkg in *${PKGEXT}; do
gpg --pinentry-mode loopback --passphrase "${PGP_KEY_PASSWD}" -o "${pkg}.sig" -b "${pkg}"
done
popd
}

# signature for source packages.
(ls ${SRC_ARTIFACTS_PATH}/*${SRCEXT} &>/dev/null) && {
pushd ${SRC_ARTIFACTS_PATH}
for pkg in *${SRCEXT}; do
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
[ -n "${PKG_ARTIFACTS_PATH}" ] || { echo "You must set PKG_ARTIFACTS_PATH firstly."; return 1; }
[ -n "${SRC_ARTIFACTS_PATH}" ] || { echo "You must set SRC_ARTIFACTS_PATH firstly."; return 1; }
[ "$(_last_package_hash)" == "$(_now_package_hash)" ] && { echo "The package '${package}' has beed built, skip."; return 0; }
unset PKGEXT SRCEXT

rm -rf ${PKG_ARTIFACTS_PATH}
rm -rf ${SRC_ARTIFACTS_PATH}

_package_info PKGEXT SRCEXT
[ -n "${PKGEXT}" ] || PKGEXT=$(grep -Po "^PKGEXT=('|\")?\K[^'\"]+" /etc/makepkg.conf)
export PKGEXT=${PKGEXT}
[ -n "${SRCEXT}" ] || SRCEXT=$(grep -Po "^SRCEXT=('|\")?\K[^'\"]+" /etc/makepkg.conf)
export SRCEXT=${SRCEXT}

makepkg --noconfirm --skippgpcheck --nocheck --syncdeps --rmdeps --cleanbuild &&
makepkg --noconfirm --noprogressbar --allsource --skippgpcheck

(ls *${PKGEXT} &>/dev/null) && {
mkdir -pv ${PKG_ARTIFACTS_PATH}
mv -vf *${PKGEXT} ${PKG_ARTIFACTS_PATH}
true
}

(ls *${SRCEXT} &>/dev/null) && {
mkdir -pv ${SRC_ARTIFACTS_PATH}
mv -vf *${SRCEXT} ${SRC_ARTIFACTS_PATH}
true
}
}

# deploy artifacts
deploy_artifacts()
{
[ -n "${PKG_DEPLOY_PATH}" ] || { echo "You must set PKG_DEPLOY_PATH firstly."; return 1; }
[ -n "${SRC_DEPLOY_PATH}" ] || { echo "You must set SRC_DEPLOY_PATH firstly."; return 1; }
local old_pkgs pkg file

(ls ${PKG_ARTIFACTS_PATH}/*${PKGEXT} &>/dev/null) || { echo "Skiped, no file to deploy"; return 0; }

_lock_file ${PKG_DEPLOY_PATH}/${PACMAN_REPO}.db

echo "Adding package information to datdabase ..."
pushd ${PKG_ARTIFACTS_PATH}
export PKG_FILES=(${PKG_FILES[@]} $(ls *${PKGEXT}))
for file in ${PACMAN_REPO}.{db,files}{,.tar.xz}{,.old}; do
rclone lsf ${PKG_DEPLOY_PATH}/${file} &>/dev/null || continue
while ! rclone copy ${PKG_DEPLOY_PATH}/${file} ${PWD}; do :; done
done
old_pkgs=($(repo-add "${PACMAN_REPO}.db.tar.xz" *${PKGEXT} | tee /dev/stderr | grep -Po "\bRemoving existing entry '\K[^']+(?=')" || true))

echo "Tring to delete old files on remote server ..."
for pkg in ${old_pkgs[@]}; do
for file in ${pkg}-{${PACMAN_ARCH},any}.pkg.tar.{xz,zst}{,.sig}; do
rclone delete ${PKG_DEPLOY_PATH}/${file} 2>/dev/null || true
done
for file in ${pkg}${SRCEXT}{,.sig}; do
rclone delete ${SRC_DEPLOY_PATH}/${file} 2>/dev/null || true
done
done

echo "Uploading new files to remote server ..."
rclone move ${PKG_ARTIFACTS_PATH} ${PKG_DEPLOY_PATH} --copy-links --delete-empty-src-dirs

(ls ${SRC_ARTIFACTS_PATH}/*${SRCEXT} &>/dev/null) && 
rclone move ${SRC_ARTIFACTS_PATH} ${SRC_DEPLOY_PATH} --copy-links --delete-empty-src-dirs

popd
_release_file ${PKG_DEPLOY_PATH}/${PACMAN_REPO}.db
_record_package_hash
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
echo "message=${message}" >>$GITHUB_OUTPUT
}

return 0
}

# Run from here
cd ${CI_BUILD_DIR}
message 'Install build environment.'
[ -z "${PACMAN_REPO}" ] && { echo "Environment variable 'PACMAN_REPO' is required."; exit 1; }
[[ ${PACMAN_REPO} =~ '$' ]] && eval export PACMAN_REPO=${PACMAN_ARCH}
[ -z "${PACMAN_ARCH}" ] && export PACMAN_ARCH=$(sed -nr 's|^CARCH=\"(\w+).*|\1|p' /etc/makepkg.conf)
[[ ${PACMAN_ARCH} =~ '$' ]] && eval export PACMAN_ARCH=${PACMAN_ARCH}
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

PKG_DEPLOY_PATH=${DEPLOY_PATH%% *}
SRC_DEPLOY_PATH=$(dirname ${PKG_DEPLOY_PATH})/sources
PKG_ARTIFACTS_PATH=${PWD}/artifacts/${PACMAN_REPO}/${PACMAN_ARCH}/package
SRC_ARTIFACTS_PATH=${PWD}/artifacts/${PACMAN_REPO}/${PACMAN_ARCH}/sources

pacman --sync --needed --noconfirm --disable-download-timeout base-devel rclone-bin expect git jq

RCLONE_CONFIG_PATH=$(rclone config file | tail -n1)
mkdir -pv $(dirname ${RCLONE_CONFIG_PATH})
[ $(awk 'END{print NR}' <<< "${RCLONE_CONF}") == 1 ] &&
base64 --decode <<< "${RCLONE_CONF}" > ${RCLONE_CONFIG_PATH} ||
printf "${RCLONE_CONF}" > ${RCLONE_CONFIG_PATH}
import_pgp_seckey

trap "_release_file ${PKG_DEPLOY_PATH}/${PACMAN_REPO}.db" EXIT
success 'The build environment is ready successfully.'
# Build
execute 'Building packages' build_package
execute "Generating package signature" create_package_signature
execute "Deploying artifacts" deploy_artifacts
create_mail_message
success 'All artifacts have been deployed successfully'
