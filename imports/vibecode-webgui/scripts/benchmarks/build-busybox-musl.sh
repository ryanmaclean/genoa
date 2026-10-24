#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ARCH=${1:-x86_64}
VERSION=${BUSYBOX_VERSION:-1.36.1}
BUILD_ROOT="$ROOT_DIR/bench-images/busybox"
SRC_DIR="$BUILD_ROOT/busybox-${VERSION}"

set_bool_config() {
  local key="$1"
  local value="$2"
  if grep -q "^${key}=" .config; then
    sed -i "s/^${key}=.*$/${key}=${value}/" .config
  else
    sed -i "s/^# ${key} is not set$/${key}=${value}/" .config || echo "${key}=${value}" >> .config
  fi
}

set_string_config() {
  local key="$1"
  local value="$2"
  if grep -q "^${key}=\"" .config; then
    sed -i "s|^${key}=\".*\"$|${key}=\"${value}\"|" .config
  elif grep -q "^# ${key} is not set" .config; then
    sed -i "s|^# ${key} is not set$|${key}=\"${value}\"|" .config
  else
    echo "${key}=\"${value}\"" >> .config
  fi
}

disable_config() {
  local key="$1"
  if grep -q "^${key}=" .config; then
    sed -i "s/^${key}=.*$/# ${key} is not set/" .config
  elif ! grep -q "^# ${key} is not set" .config; then
    echo "# ${key} is not set" >> .config
  fi
}

mkdir -p "$BUILD_ROOT"
cd "$BUILD_ROOT"

TARBALL="busybox-${VERSION}.tar.bz2"
URL="https://busybox.net/downloads/${TARBALL}"
if [[ ! -f $TARBALL ]]; then
  curl -LO "$URL"
fi

if [[ ! -d "$SRC_DIR" ]]; then
  tar -xf "$TARBALL"
fi

pushd "$SRC_DIR" >/dev/null
make distclean >/dev/null 2>&1 || true
make defconfig >/dev/null

set_bool_config CONFIG_STATIC y
set_bool_config CONFIG_UDHCPC y
set_string_config CONFIG_UDHCPC_DEFAULT_SCRIPT /udhcpc.script
set_bool_config CONFIG_IP y
set_bool_config CONFIG_SH_IS_ASH y
set_bool_config CONFIG_ASH y
set_bool_config CONFIG_LS y
set_bool_config CONFIG_CAT y
set_bool_config CONFIG_ECHO y
set_bool_config CONFIG_GREP y
set_bool_config CONFIG_TAR y
set_bool_config CONFIG_CP y
set_bool_config CONFIG_MKDIR y
set_bool_config CONFIG_MV y
set_bool_config CONFIG_RM y
set_bool_config CONFIG_PWD y
set_bool_config CONFIG_SLEEP y
set_bool_config CONFIG_INIT y
set_bool_config CONFIG_PING y

disable_config CONFIG_TC
disable_config CONFIG_FEATURE_IP_TUNNEL
disable_config CONFIG_FEATURE_SYSLOG
disable_config CONFIG_FEATURE_IPV6
disable_config CONFIG_SYSLOGD
disable_config CONFIG_KLOGD

set +o pipefail
yes "" | make oldconfig >/dev/null
set -o pipefail

CROSS_ARGS=()
if [[ "$ARCH" == "arm64" ]]; then
  CROSS_ARGS=(ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-)
elif [[ "$ARCH" == "armv7" ]]; then
  CROSS_ARGS=(ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf-)
fi
make -j"$(nproc)" "${CROSS_ARGS[@]}" >/dev/null
make install "${CROSS_ARGS[@]}" CONFIG_PREFIX="$BUILD_ROOT/rootfs"

popd >/dev/null

echo "BusyBox rootfs stored in $BUILD_ROOT/rootfs"
