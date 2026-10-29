#!/bin/bash
# Native macOS integration: only genuine release omp and Bun executables run.
set -euo pipefail
export LC_ALL=C
[ "$(uname -s)" = Darwin ] || { printf 'This integration test requires macOS.\n' >&2; exit 1; }
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
if [ "$#" = 3 ]; then
    export OMP_ARCHIVE_PATH=$1 OMP_CHECKSUM_PATH=$2 OMP_MANIFEST_PATH=$3
elif [ "$#" != 0 ]; then
    printf 'Usage: bash scripts/test-installer-macos.sh ARCHIVE CHECKSUM MANIFEST\n' >&2
    exit 1
fi
: "${OMP_ARCHIVE_PATH:?Supply all three offline release artifacts.}"
: "${OMP_CHECKSUM_PATH:?Supply all three offline release artifacts.}"
: "${OMP_MANIFEST_PATH:?Supply all three offline release artifacts.}"
absolute_file() { printf '%s/%s\n' "$(cd "$(dirname "$1")" && pwd -P)" "${1##*/}"; }
archive=$(absolute_file "$OMP_ARCHIVE_PATH")
checksums=$(absolute_file "$OMP_CHECKSUM_PATH")
manifest=$(absolute_file "$OMP_MANIFEST_PATH")
fixture=$(mktemp -d "${TMPDIR:-/tmp}/omp-macos-installer.XXXXXXXX")
fixture=$(cd "$fixture" && pwd -P)
cleanup() {
    local status=$?
    trap - EXIT HUP INT TERM
    /usr/bin/chflags -R nouchg "$fixture" 2>/dev/null || true
    rm -rf "$fixture"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
export HOME="$fixture/home"
export OMP_INSTALL_DIR="$fixture/installed"
export OMP_BIN_DIR="$fixture/bin"
unset OMP_VERSION
mkdir -p "$HOME/.omp/agent" "$HOME/.pi/agent"
printf '{"private":"installer-must-not-touch"}' > "$HOME/.omp/agent/auth.json"
printf '{"setting":"preserve"}' > "$HOME/.pi/agent/settings.json"
printf 'PROFILE_MUST_NOT_CHANGE\n' > "$HOME/.zshrc"
old_path=$PATH
fail() { printf 'Installer regression failed: %s\n' "$*" >&2; exit 1; }
install() {
    OMP_ARCHIVE_PATH="$archive" OMP_CHECKSUM_PATH="$checksums" OMP_MANIFEST_PATH="$manifest" /bin/bash "$root/install.sh" > "$fixture/install.log" 2>&1 || {
        cat "$fixture/install.log" >&2
        return 1
    }
}
reject() {
    local expected=$1
    shift
    if "$@" > "$fixture/rejected.log" 2>&1; then fail 'An unsafe operation was accepted.'; fi
    local text
    text=$(cat "$fixture/rejected.log")
    [[ "$text" = *"$expected"* ]] || { cat "$fixture/rejected.log" >&2; fail "Rejection did not reach the intended boundary: $expected"; }
}
install
[ -x "$OMP_INSTALL_DIR/omp" ] || fail 'Real executable was not installed.'
[ -L "$OMP_BIN_DIR/omp" ] && [ "$(readlink "$OMP_BIN_DIR/omp")" = "$OMP_INSTALL_DIR/omp" ] || fail 'Stable omp symlink is wrong.'
[ ! -e "$OMP_INSTALL_DIR/omp-localized.json" ] || fail 'Portable install created developer metadata.'
cp "$OMP_INSTALL_DIR/update/bun" "$fixture/bun"
bun="$fixture/bun"
cat > "$fixture/helper.cjs" <<'JS'
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const [mode, input, output] = process.argv.slice(2);
if (mode === 'snapshot') {
    const result = {};
    function visit(dir, prefix = '') {
        for (const name of fs.readdirSync(dir).sort()) {
            const file = path.join(dir, name), relative = prefix + name, stat = fs.lstatSync(file);
            if (stat.isDirectory()) visit(file, relative + '/');
            else if (stat.isSymbolicLink()) result[relative] = 'link:' + fs.readlinkSync(file);
            else result[relative] = crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
        }
    }
    visit(input);
    process.stdout.write(JSON.stringify(result));
} else if (mode === 'archive') {
    function header(name, type = '0', link = '', data = Buffer.alloc(0)) {
        const h = Buffer.alloc(512);
        function text(offset, value) { h.write(value, offset, 'ascii'); }
        text(0, name); text(100, '0000644\0'); text(108, '0000000\0'); text(116, '0000000\0');
        text(124, data.length.toString(8).padStart(11, '0') + '\0'); text(136, '00000000000\0');
        text(148, '        '); text(156, type); text(157, link); text(257, 'ustar\0'); text(263, '00');
        const sum = h.reduce((a, b) => a + b, 0);
        text(148, sum.toString(8).padStart(6, '0') + '\0 ');
        return Buffer.concat([h, data, Buffer.alloc((512 - data.length % 512) % 512)]);
    }
    let entries;
    if (input === 'traversal') entries = [header('../escaped.txt', '0', '', Buffer.from('must not escape'))];
    else if (input === 'duplicate') entries = [header('LICENSE'), header('LICENSE')];
    else if (input === 'symlink') entries = [header('locales/ko.json', '2', '/etc/passwd')];
    else if (input === 'hardlink') entries = [header('locales/ko.json', '1', 'LICENSE')];
    else throw Error('Unknown fixture');
    fs.writeFileSync(output, Buffer.concat([...entries, Buffer.alloc(1024)]));
} else if (mode === 'manifest') {
    const manifest = JSON.parse(fs.readFileSync(input, 'utf8'));
    manifest.platform = 'macos-unsupported';
    fs.writeFileSync(output, JSON.stringify(manifest));
} else throw Error('Unknown mode');
JS
snapshot() { "$bun" "$fixture/helper.cjs" snapshot "$OMP_INSTALL_DIR"; }
unchanged() { [ "$(snapshot)" = "$baseline" ] || fail 'Installed files changed after rejection or rollback.'; }
# Both external packs are byte-preserved, and partial Korean overrides still execute correctly.
printf '{"USAGE":"CUSTOM_INSTALLER_REGRESSION"}\n' > "$OMP_INSTALL_DIR/locales/ko.json"
printf '{"CUSTOM":"preserve English external pack"}\n' > "$OMP_INSTALL_DIR/locales/en.json"
printf '{"keep":true}\n' > "$OMP_INSTALL_DIR/unmanaged-settings.json"
ko_before=$(/usr/bin/shasum -a 256 "$OMP_INSTALL_DIR/locales/ko.json")
en_before=$(/usr/bin/shasum -a 256 "$OMP_INSTALL_DIR/locales/en.json")
install
[ "$(/usr/bin/shasum -a 256 "$OMP_INSTALL_DIR/locales/ko.json")" = "$ko_before" ] || fail 'Korean pack changed.'
[ "$(/usr/bin/shasum -a 256 "$OMP_INSTALL_DIR/locales/en.json")" = "$en_before" ] || fail 'English pack changed.'
help=$(env -u PI_PROFILE HOME="$HOME" PI_CODING_AGENT_DIR="$fixture/direct-ko" OMP_LANG=ko OMP_LOCALE_DIR="$OMP_INSTALL_DIR/locales" "$OMP_BIN_DIR/omp" --help)
[[ "$help" = *CUSTOM_INSTALLER_REGRESSION* && "$help" = *--model* ]] || fail 'Installed real binary ignored a partial external pack.'
help=$(env -u PI_PROFILE HOME="$HOME" PI_CODING_AGENT_DIR="$fixture/direct-en" OMP_LANG=en OMP_LOCALE_DIR="$OMP_INSTALL_DIR/locales" "$OMP_BIN_DIR/omp" --help)
[[ "$help" = *USAGE* && "$help" != *CUSTOM_INSTALLER_REGRESSION* ]] || fail 'Explicit English read the Korean pack.'
baseline=$(snapshot)
original_archive=$archive
original_checksums=$checksums
mkdir "$fixture/bad-checksum"
archive="$fixture/bad-checksum/${original_archive##*/}"
cp "$original_archive" "$archive"
printf 'corruption' >> "$archive"
reject 'SHA256 verification failed' install
unchanged
archive=$original_archive
printf '%064d  wrong-filename.tar.gz\n' 0 > "$fixture/wrong-sums"
checksums="$fixture/wrong-sums"
reject 'Checksum filename differs' install
unchanged
checksums=$original_checksums
for kind in traversal duplicate symlink hardlink; do
    mkdir "$fixture/$kind"
    "$bun" "$fixture/helper.cjs" archive "$kind" "$fixture/$kind/archive.tar"
    archive="$fixture/$kind/${original_archive##*/}"
    /usr/bin/gzip -c "$fixture/$kind/archive.tar" > "$archive"
    checksums="$fixture/$kind/checksums"
    digest=$(/usr/bin/shasum -a 256 "$archive"); digest=${digest%% *}
    printf '%s  %s\n' "$digest" "${archive##*/}" > "$checksums"
    case "$kind" in traversal) message='unsafe archive path' ;; duplicate) message='Duplicate archive path' ;; *) message='Archive links' ;; esac
    reject "$message" install
    unchanged
done
[ ! -e "$fixture/escaped.txt" ] || fail 'Archive traversal escaped staging.'
archive=$original_archive
checksums=$original_checksums
original_manifest=$manifest
"$bun" "$fixture/helper.cjs" manifest "$manifest" "$fixture/wrong-manifest.json"
manifest="$fixture/wrong-manifest.json"
reject 'Invalid macOS release manifest' install
unchanged
manifest=$original_manifest
# Immutable late-promotion files fail after earlier files moved; original bytes must return.
printf 'ROLLBACK_ORIGINAL_LICENSE\n' > "$OMP_INSTALL_DIR/LICENSE"
baseline=$(snapshot)
/usr/bin/chflags uchg "$OMP_INSTALL_DIR/README.md"
reject 'README.md' install
/usr/bin/chflags nouchg "$OMP_INSTALL_DIR/README.md"
unchanged
[ "$(readlink "$OMP_BIN_DIR/omp")" = "$OMP_INSTALL_DIR/omp" ] || fail 'Rollback changed the stable link.'
# Developer installs and symlinked path components are rejected before modification.
printf '{"private":"do not replace"}\n' > "$OMP_INSTALL_DIR/omp-localized.json"
baseline=$(snapshot)
reject 'developer-managed' install
unchanged
rm "$OMP_INSTALL_DIR/omp-localized.json"
baseline=$(snapshot)
mv "$OMP_INSTALL_DIR/locales/ko.json" "$fixture/ko-original.json"
ln -s "$fixture/ko-original.json" "$OMP_INSTALL_DIR/locales/ko.json"
reject 'Symlink file' install
[ -L "$OMP_INSTALL_DIR/locales/ko.json" ] || fail 'Installer replaced a symlinked pack.'
rm "$OMP_INSTALL_DIR/locales/ko.json"
mv "$fixture/ko-original.json" "$OMP_INSTALL_DIR/locales/ko.json"
unchanged
ln -s "$OMP_INSTALL_DIR" "$fixture/aliased-install"
saved_target=$OMP_INSTALL_DIR
export OMP_INSTALL_DIR="$fixture/aliased-install"
reject 'Symlink path component' install
export OMP_INSTALL_DIR=$saved_target
unchanged
rm "$OMP_BIN_DIR/omp"
printf 'FOREIGN_COMMAND\n' > "$OMP_BIN_DIR/omp"
reject 'another installation' install
[ "$(cat "$OMP_BIN_DIR/omp")" = FOREIGN_COMMAND ] || fail 'Installer replaced an unrelated command.'
rm "$OMP_BIN_DIR/omp"
ln -s "$OMP_INSTALL_DIR/omp" "$OMP_BIN_DIR/omp"
unchanged
[ "$PATH" = "$old_path" ] || fail 'Installer changed caller PATH.'
[ "$(cat "$HOME/.zshrc")" = PROFILE_MUST_NOT_CHANGE ] || fail 'Shell profile was changed.'
[ "$(cat "$HOME/.omp/agent/auth.json")" = '{"private":"installer-must-not-touch"}' ] || fail 'Authentication was changed.'
[ "$(cat "$HOME/.pi/agent/settings.json")" = '{"setting":"preserve"}' ] || fail 'Settings were changed.'
shopt -s nullglob
leftovers=('' "$fixture"/.omp-korean-install.*)
[ "${#leftovers[@]}" = 1 ] || fail 'Installer left staging or backup directories.'
printf 'macOS installer integration passed: genuine binary English/Korean smoke, offline install, partial external packs, checksum/path/type rejection, rollback, developer protection and unchanged user state.\n'
