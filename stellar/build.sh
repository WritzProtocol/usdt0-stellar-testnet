#!/usr/bin/env bash
# Reproducible build of the two LayerZero contracts behind the USDT0 testnet
# token (Writz-deployed LayerZero OFT) on Stellar testnet:
#
#   oft.wasm          LayerZero's Stellar OFT, deployed as MintBurn
#   sac_manager.wasm  LayerZero's SAC Manager, admin of the token's SAC
#
# Writz does not modify either contract. The source is LayerZero's published
# npm packages at the version below, each checked against the sha512 integrity
# pinned here, built with LayerZero's own Cargo.lock files (copied into
# locks/ from LayerZero-Labs/monorepo-external at the commit below) and the
# Rust toolchain their packages pin. The resulting wasm sha256 is compared
# with the hashes below, which are also recorded in deployments/testnet.md.
#
# Usage: stellar/build.sh [out_dir]   (default: stellar/out)
set -euo pipefail

LZ_VERSION="4.0.4"
LZ_SOURCE_COMMIT="c7bd283934993d6a60c642c7831d3d7662200a68"
TOOLCHAIN="1.90.0"
EXPECTED_OFT_SHA256="${EXPECTED_OFT_SHA256:-d1e65a46e87f02032880485b4f43e916d3fc72dad7641de38962542dc9d74a0a}"
EXPECTED_SAC_MANAGER_SHA256="${EXPECTED_SAC_MANAGER_SHA256:-db6b8e6083fc4054aca637788be6e714d29284c7ae850980b6480abc13631854}"

PACKAGES=(
  "oft-stellar-contracts sha512-GVbKGX+QPx9LN5so7bBIuNCBtDWi1Q5KFB3Aq/GoMKn/DEkS2kwFUTkyTmZ/DuZhwyQb31I2Uo1BefAXh4C8aw=="
  "oft-core-stellar-contracts sha512-9btaxfH62Lqu1aKjxigZ3fKXjfckii62c6Wq+LpkFvNQ5kbqD0OsDKDJ5iwz5SPxTg8Rfm4kn1cl0m6hDFqEEg=="
  "oapp-stellar-contracts sha512-fHOmEjXeSuk9GRYXRP405Qe9YmKd1tvFqBXJSAbpIEtKQ4JV8aMMhMwDKTgECTp3uj5EJ4V7YZ8Cs1sJO4MdVA=="
  "oapp-macros-stellar-contracts sha512-Wgo/lPRVzwQ0aCw0yfUXl+ZYW++U32sf0Kp/CK+csZPYyv0i77b441tWfxvt5Sak+BURW6Dl0/scPIkcc2Vthw=="
  "protocol-stellar-v2 sha512-9eFk8BVATIQwclo0pP02RmZhegIjrafSjDIGUWjpn9+dVd6XFDJ2mWWi6hx4niZEhkcR9ZQiYgTLMlgD0myd9Q=="
  "common-utils-stellar-contracts sha512-RKY3prU4t572TE/2Yxib2oZ8/QjDghNLpZi8IyY8+RZ4tTXajJexRTMMrfddv6SV6ktGJkpcXdw+A6xfvGVVOQ=="
  "common-utils-macros-stellar-contracts sha512-4ibSvS8IkWT3k1JoRITFysUcO60JgmNHbpZW1uwcmmMb22z1mWiMDEzTBgzY3Ke2aMlOFgafopp4SRHz7eVpkw=="
  "sac-manager-stellar-contracts sha512-t9lKONZrTPTgd8FQUv4kNWezth52qz8wnu+XKkUb+eshc11RsrZ9D5VAfjEq+qdhGPNJwhTnpJ1UPb8QQPCnAA=="
)

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$(mkdir -p "${1:-$HERE/out}" && cd "${1:-$HERE/out}" && pwd)"
# A fixed build path: cargo hashes the absolute path of every path dependency
# into its symbol metadata, so a different directory gives a different wasm.
WORK_LINK="/tmp/writz-layerzero-build"
rm -rf "$WORK_LINK" && mkdir -p "$WORK_LINK"
WORK="$(cd "$WORK_LINK" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

command -v npm >/dev/null || { echo "build.sh: npm is required to fetch the packages" >&2; exit 1; }
rustup toolchain install "$TOOLCHAIN" --profile minimal --target wasm32v1-none >/dev/null

# 1. Fetch each package without running any of its scripts, check its integrity, unpack.
for entry in "${PACKAGES[@]}"; do
  read -r name integrity <<<"$entry"
  mkdir -p "$WORK/tgz/$name"
  (cd "$WORK/tgz/$name" && npm pack "@layerzerolabs/$name@$LZ_VERSION" --silent >/dev/null)
  tgz="$(ls "$WORK/tgz/$name"/*.tgz)"
  actual="sha512-$(openssl dgst -sha512 -binary "$tgz" | base64 | tr -d '\n')"
  [ "$actual" = "$integrity" ] || { echo "build.sh: integrity mismatch for $name" >&2; exit 1; }
  mkdir -p "$WORK/src/$name"
  tar -xzf "$tgz" -C "$WORK/src/$name" --strip-components 1
done

# 2. Resolve the vendored path dependencies the way LayerZero's build tool does,
#    pointing every `dependencies/<package>` path at one copy of that package.
find "$WORK/src" -name Cargo.toml -print0 | while IFS= read -r -d '' f; do
  sed -i.bak -E "s#path *= *\"dependencies/#path = \"$WORK/src/#g" "$f" && rm "$f.bak"
done
cp "$HERE/locks/oft.Cargo.lock" "$WORK/src/oft-stellar-contracts/Cargo.lock"
cp "$HERE/locks/sac-manager.Cargo.lock" "$WORK/src/sac-manager-stellar-contracts/Cargo.lock"

# 3. Build with paths remapped, so the wasm does not depend on where it was built.
export RUSTFLAGS="--remap-path-prefix=$WORK/src=/layerzero --remap-path-prefix=$(cd "${CARGO_HOME:-$HOME/.cargo}" && pwd -P)=/cargo"
for pkg in oft-stellar-contracts sac-manager-stellar-contracts; do
  (cd "$WORK/src/$pkg" && cargo "+$TOOLCHAIN" build --locked --release --target wasm32v1-none --quiet)
done
cp "$WORK/src/oft-stellar-contracts/target/wasm32v1-none/release/oft.wasm" "$OUT/"
cp "$WORK/src/sac-manager-stellar-contracts/target/wasm32v1-none/release/sac_manager.wasm" "$OUT/"

# 4. Report, and compare with the recorded hashes when given.
status=0
check() {
  local file="$1" expected="$2" actual
  actual="$(shasum -a 256 "$OUT/$file" | cut -d' ' -f1)"
  printf '%-17s %s  %s bytes\n' "$file" "$actual" "$(wc -c <"$OUT/$file" | tr -d ' ')"
  if [ -n "$expected" ] && [ "$expected" != "$actual" ]; then
    echo "build.sh: $file does not match the recorded sha256 $expected" >&2
    status=1
  fi
}
echo "LayerZero Stellar contracts $LZ_VERSION (source commit $LZ_SOURCE_COMMIT), rustc $TOOLCHAIN"
check oft.wasm "$EXPECTED_OFT_SHA256"
check sac_manager.wasm "$EXPECTED_SAC_MANAGER_SHA256"
exit $status
