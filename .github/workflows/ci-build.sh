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

# Convert lines to array
_as_list() {
    local -n nameref_list="${1}"
    local filter="${2}"
    local strip="${3}"
    local lines="${4}"
    local result=1
    nameref_list=()
    while IFS= read -r line; do
        test -z "${line}" && continue
        result=0
        [[ "${line}" = ${filter} ]] && nameref_list+=("${line/${strip}/}")
    done <<< "${lines}"
    return "${result}"
}

# Changes since last build
_list_changes() {
    local list_name="${1}"
    local filter="${2}"
    local strip="${3}"
    local git_options=("${@:4}")
	local marker="build.marker"
    local branch_url="$(git remote get-url origin | sed 's/\.git$//')/tree/${CI_BRANCH}"
	local commit_sha
	
	rclone copy "${PKG_DEPLOY_PATH}/${marker}" . &>/dev/null && commit_sha=$(sed -rn "s|^\[([[:xdigit:]]+)\]${branch_url}\s*$|\1|p" "${marker}")
	rm -f ${marker}
	[ -n "${commit_sha}" ] || commit_sha="HEAD^"
	
	_as_list "${list_name}" "${filter}" "${strip}" "$(git log "${git_options[@]}" ${commit_sha}.. | sort -u)"
}

# log git sha for the current build
_create_build_marker() {
	local branch_url="$(git remote get-url origin | sed 's/\.git$//')/tree/${CI_BRANCH}"
	local marker="build.marker"
	
	rclone copy "${PKG_DEPLOY_PATH}/${marker}" . &>/dev/null || touch "${marker}"
	grep -Pq "\[[[:xdigit:]]+\]${branch_url}\s*$" ${marker} && \
	sed -i -r "s|^(\[)[[:xdigit:]]+(\]${branch_url}\s*)$|\1${CI_COMMIT}\2|g" "${marker}" || \
	echo "[${CI_COMMIT}]${branch_url}" >> "${marker}"
	rclone move "${marker}" "${PKG_DEPLOY_PATH}"
}

# Get package information
_package_info() {
    local properties=("${@:2}")
    for property in "${properties[@]}"; do
        local -n nameref_property="${property}"
        nameref_property=($(
            source "PKGBUILD"
            declare -n nameref_property="${property}"
            echo "${nameref_property[@]}"))
    done
}

# Package provides another
_package_provides() {
    local package="${1}"
    local another="${2}"
    local pkgname provides
    _package_info pkgname provides
    for pkg_name in "${pkgname[@]}";  do [[ "${pkg_name}" = "${another}" ]] && return 0; done
    for provided in "${provides[@]}"; do [[ "${provided}" = "${another}" ]] && return 0; done
    return 1
}

# Add package to build after required dependencies
_build_add() {
    local package="${1}"
    local depends makedepends
    for sorted_package in "${sorted_packages[@]}"; do
        [[ "${sorted_package}" = "${package}" ]] && return 0
    done
    _package_info depends makedepends
    for dependency in "${depends[@]}" "${makedepends[@]}"; do
        for unsorted_package in "${packages[@]}"; do
            [[ "${package}" = "${unsorted_package}" ]] && continue
            _package_provides "${unsorted_package}" "${dependency}" && _build_add "${unsorted_package}"
        done
    done
    sorted_packages+=("${package}")
}

# get last commit hash of one package
_last_package_hash()
{
local package="${1}"
local marker="build.marker"
rclone copy "${PKG_DEPLOY_PATH}/${marker}" . &>/dev/null && sed -rn "s|^\[([[:xdigit:]]+)\]${package}\s*$|\1|p" "${marker}"
rm -f ${hashfile}
return 0
}

# get current commit hash of one package
_now_package_hash()
{
local package="${1}"
git log --pretty=format:'%H' -1 ${package} 2>/dev/null
return 0
}

# record current commit hash of one package
_record_package_hash()
{
local package="${1}"
local marker="build.marker"
local commit_sha

commit_sha="$(_now_package_hash .)"
rclone copy "${PKG_DEPLOY_PATH}/${marker}" . &>/dev/null || touch "${marker}"
grep -Pq "\[[[:xdigit:]]+\]${package}\s*$" ${marker} && \
sed -i -r "s|^(\[)[[:xdigit:]]+(\]${package}\s*)$|\1${commit_sha}\2|g" "${marker}" || \
echo "[${commit_sha}]${package}" >> "${marker}"
rclone move "${marker}" "${PKG_DEPLOY_PATH}"
return 0
}

# Git configuration
git_config() {
    local name="${1}"
    local value="${2}"
    test -n "$(git config ${name})" && return 0
    git config --global "${name}" "${value}" && return 0
    failure 'Could not configure Git for makepkg'
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

# Sort packages by dependency
define_build_order() {
    local sorted_packages=()
    for unsorted_package in "${packages[@]}"; do
        _build_add "${unsorted_package}"
    done
    packages=("${sorted_packages[@]}")
}

# Added commits
list_commits()  {
    _list_changes commits '*' '#*::' --pretty=format:'%ai::[%h] %s'
}

# Changed recipes
list_packages() {
    local _packages
    _list_changes _packages '*/PKGBUILD' '%/PKGBUILD' --pretty=format: --name-only || return 1
    for _package in "${_packages[@]}"; do
        local find_case_sensitive="$(find -name "${_package}" -type d -print -quit)"
        test -n "${find_case_sensitive}" && packages+=("${_package}")
    done
    return 0
}

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
[ -d ${PKG_ARTIFACTS_PATH} ] && {
pushd ${PKG_ARTIFACTS_PATH}
for pkg in *${PKGEXT}; do
gpg --pinentry-mode loopback --passphrase "${PGP_KEY_PASSWD}" -o "${pkg}.sig" -b "${pkg}"
done
popd
}

# signature for source packages.
[ -d ${SRC_ARTIFACTS_PATH} ] && {
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
local pkgbase pkgname depends makedepends arch buildarch
unset PKGEXT SRCEXT

_package_info pkgbase pkgname depends{,_${PACMAN_ARCH}} makedepends{,_${PACMAN_ARCH}} arch buildarch PKGEXT SRCEXT
[ -n "${PKGEXT}" ] || PKGEXT=$(grep -Po "^PKGEXT=('|\")?\K[^'\"]+" /etc/makepkg.conf)
export PKGEXT=${PKGEXT}
[ -n "${SRCEXT}" ] || SRCEXT=$(grep -Po "^SRCEXT=('|\")?\K[^'\"]+" /etc/makepkg.conf)
export SRCEXT=${SRCEXT}
[ -n "${package}" ] || package=${pkgbase}
[ -n "${package}" ] || package=${pkgname}
export package=${package}

[ "${arch}" == "any" ] || {
[ -n "${buildarch}" ] && {
[ "$((buildarch & 1<<0))" == "$((1<<0))" ] && arch=(${arch[@]} 'i686' 'x86_64' 'arm' 'armv6h' 'armv7h' 'aarch64')
[ "$((buildarch & 1<<1))" == "$((1<<1))" ] && arch=(${arch[@]} 'arm')
[ "$((buildarch & 1<<2))" == "$((1<<2))" ] && arch=(${arch[@]} 'armv7h')
[ "$((buildarch & 1<<3))" == "$((1<<3))" ] && arch=(${arch[@]} 'aarch64')
[ "$((buildarch & 1<<4))" == "$((1<<4))" ] && arch=(${arch[@]} 'armv6h')
true
} || {
arch=(${arch[@]} "${PACMAN_ARCH}")
}
}
arch=($(tr ' ' '\n' <<< ${arch[@]} | sort -u))

[ "${arch}" == "any" ] || grep -Pq "\b${PACMAN_ARCH}\b" <<< ${arch[@]} || { echo "The package '${package}' will not build for architecture '${PACMAN_ARCH}'"; return 0; }

[ "$(_last_package_hash ${package})" == "$(_now_package_hash .)" ] && { echo "The package '${package}' has beed built, skip."; return 0; }

sed -i -r "s|^(arch=\()[^)]+(\))|\1${arch[*]}\2|" PKGBUILD
makepkg --noconfirm --skippgpcheck --nocheck --syncdeps --rmdeps --cleanbuild &&
makepkg --noconfirm --noprogressbar --allsource

(ls *${PKGEXT} &>/dev/null) && {
mkdir -pv ${PKG_ARTIFACTS_PATH}
mv -vf *${PKGEXT} ${PKG_ARTIFACTS_PATH}
true
} || {
export FILED_PKGS=(${FILED_PKGS[@]} ${package})
}

(ls *${SRCEXT} &>/dev/null) && {
mkdir -pv ${SRC_ARTIFACTS_PATH}
mv -vf *${SRCEXT} ${SRC_ARTIFACTS_PATH}
}
}

# deploy artifacts
deploy_artifacts()
{
[ -n "${PKG_DEPLOY_PATH}" ] || { echo "You must set PKG_DEPLOY_PATH firstly."; return 1; }
[ -n "${SRC_DEPLOY_PATH}" ] || { echo "You must set SRC_DEPLOY_PATH firstly."; return 1; }
local old_pkgs pkg file
(ls ${PKG_ARTIFACTS_PATH}/*${PKGEXT} &>/dev/null) || { echo "Skiped, no file to deploy"; return 0; }
pushd ${PKG_ARTIFACTS_PATH}
export PKG_FILES=(${PKG_FILES[@]} $(ls *${PKGEXT}))
for file in ${PACMAN_REPO}.{db,files}{,.tar.xz}{,.old}; do
rclone copy ${PKG_DEPLOY_PATH}/${file} ${PWD} 2>/dev/null || true
done
old_pkgs=($(repo-add "${PACMAN_REPO}.db.tar.xz" *${PKGEXT} | tee /dev/stderr | grep -Po "\bRemoving existing entry '\K[^']+(?=')" || true))
popd
for pkg in ${old_pkgs[@]}; do
for file in ${pkg}-{${PACMAN_ARCH},any}.pkg.tar.{xz,zst}{,.sig}; do
rclone delete ${PKG_DEPLOY_PATH}/${file} 2>/dev/null || true
done
done

rclone move ${PKG_ARTIFACTS_PATH} ${PKG_DEPLOY_PATH} --copy-links
rclone move ${SRC_ARTIFACTS_PATH} ${SRC_DEPLOY_PATH} --copy-links

_record_package_hash "${package}"
}

# create mail message
create_mail_message()
{
local message item

[ -n "${PKG_FILES}" ] && {
message="<p>Successfully created the following package archive.</p>"
for item in ${PKG_FILES[@]}; do
message=${message}"<p><font color=\"green\">${item}</font></p>"
done
}

[ -n "${FILED_PKGS}" ] && {
message=${message}"<p>Failed to build following packages. </p>"
for item in ${FILED_PKGS[@]}; do
message=${message}"<p><font color=\"red\">${item}</font></p>"
done
}

[ -n "${message}" ] && {
message=${message}"<p>Architecture: ${PACMAN_ARCH}</p>"
message=${message}"<p>Build Number: ${CI_BUILD_NUMBER}</p>"
echo ::set-output name=message::${message}
}

return 0
}

# Status functions
failure() { local status="${1}"; local items=("${@:2}"); _status failure "${status}." "${items[@]}"; exit 1; }
success() { local status="${1}"; local items=("${@:2}"); _status success "${status}." "${items[@]}"; exit 0; }
message() { local status="${1}"; local items=("${@:2}"); _status message "${status}"  "${items[@]}"; }

# Run from here ......
# Configure
[ -z "${PACMAN_REPO}" ] && export PACMAN_REPO=$([ "$(uname -o)" == "Msys" ] && tr 'A-Z' 'a-z' <<< ${MSYSTEM%%[0-9]*} || echo "eyun")
[[ ${PACMAN_REPO} =~ '$' ]] && eval export PACMAN_REPO=${PACMAN_ARCH}
[ -z "${PACMAN_ARCH}" ] && export PACMAN_ARCH=$(sed -nr 's|^CARCH=\"(\w+).*|\1|p' /etc/makepkg.conf)
[[ ${PACMAN_ARCH} =~ '$' ]] && eval export PACMAN_ARCH=${PACMAN_ARCH}
[ -z "${DEPLOY_PATH}" ] && { echo "Environment variable 'DEPLOY_PATH' is required."; exit 1; }
[[ ${DEPLOY_PATH} =~ '$' ]] && eval export DEPLOY_PATH=${DEPLOY_PATH}
[ -z "${RCLONE_CONF}" ] && { echo "Environment variable 'RCLONE_CONF' is required."; exit 1; }
[ -z "${PGP_KEY_PASSWD}" ] && { echo "Environment variable 'PGP_KEY_PASSWD' is required."; exit 1; }
[ -z "${PGP_KEY}" ] && { echo "Environment variable 'PGP_KEY' is required."; exit 1; }
[ -z "${CUSTOM_REPOS}" ] || add_custom_repos

PKG_DEPLOY_PATH=${DEPLOY_PATH%% *}
SRC_DEPLOY_PATH=$(dirname ${PKG_DEPLOY_PATH})/sources
PKG_ARTIFACTS_PATH=${PWD}/artifacts/${PACMAN_REPO}/${PACMAN_ARCH}/package
SRC_ARTIFACTS_PATH=${PWD}/artifacts/${PACMAN_REPO}/${PACMAN_ARCH}/sources

pacman --sync --refresh --sysupgrade --needed --noconfirm --disable-download-timeout rclone-bin expect

git_config user.email 'ci@msys2.org'
git_config user.name  'MSYS2 Continuous Integration'

mkdir -pv ${HOME}/.config/rclone
printf "${RCLONE_CONF}" > ${HOME}/.config/rclone/rclone.conf
import_pgp_seckey

pushd ${CI_BUILD_DIR}
# Build
execute 'Building packages' build_package
execute "Generating package signature" create_package_signature
execute "Deploying artifacts" deploy_artifacts
_create_build_marker
create_mail_message
success 'All packages built successfully'
popd
