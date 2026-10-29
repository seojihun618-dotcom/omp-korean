#!/bin/bash
# Compatible with the bash 3.2 shipped by macOS. Never changes shell profiles or user state.
set -euo pipefail
export LC_ALL=C
umask 077
DEFAULT_REPOSITORY='seojihun618-dotcom/omp-korean' # RELEASE_REPOSITORY
fail() { printf 'omp installer: %s\n' "$*" >&2; exit 1; }
[ "$(uname -s)" = Darwin ] || fail 'macOS is required.'
case "$(uname -m)" in arm64) arch=arm64 ;; x86_64) arch=x64 ;; *) fail 'Only Apple Silicon arm64 and Intel x64 are supported.' ;; esac
platform="macos-$arch"
repository=${OMP_REPOSITORY:-$DEFAULT_REPOSITORY}
version=${OMP_VERSION:-latest}
[[ "$repository" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || fail 'OMP_REPOSITORY must be owner/name.'
[[ "$version" = latest || "$version" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+-ko\.[0-9]+$ ]] || fail 'OMP_VERSION must be latest or a Korean release version.'
[ -n "${HOME:-}" ] && [ -d "$HOME" ] || fail 'HOME must be an existing directory.'
home=$(cd "$HOME" && pwd -P)
target=${OMP_INSTALL_DIR:-$home/.local/share/omp-korean}
bindir=${OMP_BIN_DIR:-$home/.local/bin}
target=${target%/}
bindir=${bindir%/}
plain_path() {
    local path=$1 cursor
    case "$path" in /*) ;; *) fail 'Installation paths must be absolute.' ;; esac
    case "$path" in /|*//*|*/./*|*/../*|*/.|*/..|*$'\n'*|*$'\r'*|*$'\t'*|*:) fail 'Choose a dedicated, normalized installation path.' ;; esac
    cursor=$path
    while [ -n "$cursor" ]; do
        [ ! -L "$cursor" ] || fail "Symlink path component is not permitted: $cursor"
        if [ -e "$cursor" ]; then
            [ -d "$cursor" ] || fail "Expected a directory: $cursor"
        fi
        cursor=${cursor%/*}
    done
}
plain_file() {
    local path=$1
    plain_path "${path%/*}"
    [ ! -L "$path" ] || fail "Symlink file is not permitted: $path"
    if [ -e "$path" ]; then
        [ -f "$path" ] || fail "Expected a regular file: $path"
        [ "$(stat -f '%l' "$path")" = 1 ] || fail "Hard-linked installed files are not permitted: $path"
    fi
}
plain_path "$target"
plain_path "$bindir"
case "$target" in "$home"|/Users|/private|/private/tmp|/private/var|/opt|/usr|/usr/*|/System|/System/*|/Library|/Library/*|/Applications|/Applications/*|/bin|/bin/*|/sbin|/sbin/*|/etc|/etc/*|/dev|/dev/*) fail 'Choose a dedicated non-system installation directory.' ;; esac
for state in "$home/.omp" "$home/.pi" "$home/.config" "$home/.local/share/omp" "$bindir"; do
    case "$target" in "$state"|"$state"/*) fail 'Do not install over user state or another binary installation.' ;; esac
done
case "$bindir" in "$target"|"$target"/*) fail 'OMP_BIN_DIR must be outside OMP_INSTALL_DIR.' ;; esac
check_developer() {
    local name
    for name in omp-localized.json package.json .git manager.json; do
        [ ! -e "$target/$name" ] && [ ! -L "$target/$name" ] || fail 'Refusing to overwrite a developer-managed or managed installation.'
    done
}
check_link() {
    plain_path "$bindir"
    if [ -e "$bindir/omp" ] || [ -L "$bindir/omp" ]; then
        [ -L "$bindir/omp" ] && [ "$(readlink "$bindir/omp")" = "$target/omp" ] || fail 'OMP_BIN_DIR/omp already belongs to another installation.'
    fi
}
check_developer
check_link
allowed=(omp locales/ko.json locales/en.json LICENSE THIRD-PARTY-NOTICES.txt README.md update/bun update/update-localized.js update/reference.json update/scripts/update-localized.ts update/scripts/reapply-localization.ts update/scripts/build-localized.ts update/scripts/localized-update.ts update/locales/ko.json update/locales/en.json)
for name in "${allowed[@]}"; do plain_file "$target/$name"; done
offline=0
for value in "${OMP_ARCHIVE_PATH:-}" "${OMP_CHECKSUM_PATH:-}" "${OMP_MANIFEST_PATH:-}"; do
    if [ -n "$value" ]; then offline=$((offline + 1)); fi
done
[ "$offline" = 0 ] || [ "$offline" = 3 ] || fail 'Offline installation needs OMP_ARCHIVE_PATH, OMP_CHECKSUM_PATH and OMP_MANIFEST_PATH together.'
mkdir -p "${target%/*}"
work=$(mktemp -d "${target%/*}/.omp-korean-install.XXXXXXXX")
saved=('')
promoted=('')
created=('')
transaction=0
link_created=0
keep_recovery=0
cleanup() {
    local status=$? i name rollback=0
    trap - EXIT HUP INT TERM
    set +e
    if [ "$transaction" = 1 ]; then
        if [ "$link_created" = 1 ]; then rm -f "$bindir/omp" || rollback=1; fi
        for ((i=${#promoted[@]}-1; i>=1; i--)); do
            rm -f "$target/${promoted[$i]}" || rollback=1
        done
        for ((i=${#saved[@]}-1; i>=1; i--)); do
            name=${saved[$i]}
            mv "$work/backup/$name" "$target/$name" || rollback=1
        done
        for ((i=${#created[@]}-1; i>=1; i--)); do rmdir "${created[$i]}" 2>/dev/null; done
        if [ "$rollback" != 0 ]; then
            keep_recovery=1
            printf 'Rollback needs attention. Original files remain in %s/backup\n' "$work" >&2
        fi
    fi
    if [ "$keep_recovery" = 0 ]; then rm -rf "$work"; fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
fetch() { /usr/bin/curl --fail --location --silent --show-error --proto '=https' --proto-redir '=https' --connect-timeout 30 --max-time 600 "$1" -o "$2"; }
manifest="$work/release-$platform.json"
if [ "$offline" = 3 ]; then
    for value in "$OMP_ARCHIVE_PATH" "$OMP_CHECKSUM_PATH" "$OMP_MANIFEST_PATH"; do [ -f "$value" ] || fail 'Offline artifacts must be regular files.'; done
    cp "$OMP_MANIFEST_PATH" "$manifest"
else
    if [ "$version" = latest ]; then
        url=$(/usr/bin/curl --fail --location --silent --show-error --proto '=https' --proto-redir '=https' --connect-timeout 30 --max-time 60 --output /dev/null --write-out '%{url_effective}' "https://github.com/$repository/releases/latest")
        prefix="https://github.com/$repository/releases/tag/"
        case "$url" in "$prefix"*) tag=${url#"$prefix"} ;; *) fail 'GitHub did not resolve a published release tag.' ;; esac
        [[ "$tag" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+-ko\.[0-9]+$ ]] || fail 'Unexpected GitHub release tag.'
    else
        tag="v${version#v}"
    fi
    base="https://github.com/$repository/releases/download/$tag"
    fetch "$base/release-$platform.json" "$manifest"
fi
# JXA and Foundation are shipped with macOS; no consumer Python, Node or Bun is needed to establish trust.
cat > "$work/manifest.js" <<'JXA'
ObjC.import('Foundation');
function run(args) {
    const text = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(args[0], $.NSUTF8StringEncoding, null));
    const m = JSON.parse(text);
    const fields = ['version', 'upstreamVersion', 'upstreamCommit', 'bunVersion', 'platform', 'archive'];
    if (!m || Array.isArray(m) || Object.keys(m).length !== fields.length ||
        fields.some(k => typeof m[k] !== 'string') || text.replace(/[\t\r\n ]/g, '') !== JSON.stringify(m)) throw Error('Invalid manifest shape');
    if (!/^[0-9]+\.[0-9]+\.[0-9]+-ko\.[0-9]+$/.test(m.version) ||
        m.upstreamVersion !== m.version.split('-ko.')[0] || !/^[a-fA-F0-9]{40}$/.test(m.upstreamCommit) ||
        !/^[0-9]+\.[0-9]+\.[0-9]+$/.test(m.bunVersion) || m.platform !== args[1] ||
        m.archive !== 'omp-korean-' + m.version + '-' + args[1] + '.tar.gz') throw Error('Inconsistent manifest');
    return fields.map(k => m[k]).join('\n');
}
JXA
/usr/bin/osascript -l JavaScript "$work/manifest.js" "$manifest" "$platform" > "$work/metadata" 2> "$work/manifest-error" || fail 'Invalid macOS release manifest.'
metadata=('')
while IFS= read -r value; do metadata[${#metadata[@]}]=$value; done < "$work/metadata"
[ "${#metadata[@]}" = 7 ] || fail 'Incomplete release manifest.'
release_version=${metadata[1]}
upstream=${metadata[2]}
bun_version=${metadata[4]}
archive_name=${metadata[6]}
if [ "$version" != latest ]; then [ "${version#v}" = "$release_version" ] || fail 'Requested version differs from the manifest.'; fi
if [ "$offline" = 0 ]; then [ "${tag#v}" = "$release_version" ] || fail 'GitHub tag differs from the manifest.'; fi
archive="$work/$archive_name"
checksums="$work/SHA256SUMS-$platform"
if [ "$offline" = 3 ]; then
    [ "${OMP_ARCHIVE_PATH##*/}" = "$archive_name" ] || fail 'Archive filename differs from the manifest.'
    cp "$OMP_ARCHIVE_PATH" "$archive"
    cp "$OMP_CHECKSUM_PATH" "$checksums"
else
    fetch "$base/$archive_name" "$archive"
    fetch "$base/SHA256SUMS-$platform" "$checksums"
fi
expected=
entries=0
while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    [[ "$line" =~ ^([a-fA-F0-9]{64})\ [\ \*]([^[:space:]]+)$ ]] || fail 'Malformed checksum entry.'
    [ "${BASH_REMATCH[2]}" = "$archive_name" ] || fail 'Checksum filename differs from the manifest.'
    expected=${BASH_REMATCH[1]}
    entries=$((entries + 1))
done < "$checksums"
[ "$entries" = 1 ] || fail 'Exactly one matching checksum entry is required.'
actual=$(/usr/bin/shasum -a 256 "$archive")
actual=${actual%% *}
[ "$(printf '%s' "$expected" | /usr/bin/tr 'A-F' 'a-f')" = "$actual" ] || fail 'Archive SHA256 verification failed; nothing was installed.'
/usr/bin/gzip -dc "$archive" > "$work/archive.tar" || fail 'Invalid gzip archive.'
raw="$work/archive.tar"
raw_size=$(stat -f '%z' "$raw")
[ "$((raw_size % 512))" = 0 ] || fail 'Truncated tar archive.'
# Read raw headers ourselves: tar listing can escape or normalize hostile names. Accept only the builder's ustar subset.
seen=('')
block=0
ended=0
header_string() {
    local start=$1 length=$2 i byte char octal result= terminated=0
    for ((i=start; i<start+length; i++)); do
        byte=${header[$i]}
        if [ "$byte" = 0 ]; then terminated=1; continue; fi
        [ "$terminated" = 0 ] && [ "$byte" -ge 32 ] && [ "$byte" -le 126 ] || fail 'Invalid tar header string.'
        printf -v octal '%03o' "$byte"
        printf -v char "\\$octal"
        result=$result$char
    done
    REPLY=$result
}
octal_field() {
    local start=$1 length=$2 i byte digits= terminated=0
    for ((i=start; i<start+length; i++)); do
        byte=${header[$i]}
        case "$byte" in
            0|32) [ -z "$digits" ] || terminated=1 ;;
            48|49|50|51|52|53|54|55)
                [ "$terminated" = 0 ] || fail 'Invalid tar numeric padding.'
                digits=$digits$((byte-48)) ;;
            *) fail 'Unsupported tar numeric field.' ;;
        esac
    done
    [ -n "$digits" ] && [ "${#digits}" -le 12 ] || fail 'Invalid tar numeric field.'
    REPLY=$((8#$digits))
}
while [ "$block" -lt "$((raw_size / 512))" ]; do
    header=( $(/bin/dd if="$raw" bs=512 skip="$block" count=1 2>/dev/null | /usr/bin/od -An -v -tu1) )
    [ "${#header[@]}" = 512 ] || fail 'Incomplete tar header.'
    sum=0
    for byte in "${header[@]}"; do sum=$((sum + byte)); done
    if [ "$sum" = 0 ]; then
        # Every block after the first terminator must also be zero, including concatenated-archive tails.
        ended=$((ended + 1))
        block=$((block + 1))
        continue
    fi
    [ "$ended" = 0 ] || fail 'Data follows the tar terminator.'
    octal_field 148 8
    checksum=$REPLY
    for ((i=148; i<156; i++)); do sum=$((sum - header[i] + 32)); done
    [ "$sum" = "$checksum" ] || fail 'Invalid tar header checksum.'
    header_string 0 100; name=$REPLY
    header_string 257 6; [ "$REPLY" = ustar ] || fail 'Only plain ustar archives are supported.'
    header_string 263 2; [ "$REPLY" = 00 ] || fail 'Unsupported tar format.'
    header_string 157 100; [ -z "$REPLY" ] || fail 'Archive links are forbidden.'
    header_string 345 155; [ -z "$REPLY" ] || fail 'Tar path prefixes are forbidden.'
    for previous in "${seen[@]}"; do [ "$previous" != "$name" ] || fail 'Duplicate archive path.'; done
    seen[${#seen[@]}]=$name
    octal_field 124 12; size=$REPLY
    case "${header[156]}" in
        48|0)
            found=0
            for candidate in "${allowed[@]}"; do [ "$name" != "$candidate" ] || found=1; done
            [ "$found" = 1 ] || fail "Unexpected or unsafe archive path: $name"
            octal_field 100 8; [ "$((REPLY & 07000))" = 0 ] || fail 'Privileged archive modes are forbidden.'
            ;;
        53)
            case "$name" in locales/|update/|update/scripts/|update/locales/) ;; *) fail 'Unexpected archive directory.' ;; esac
            [ "$size" = 0 ] || fail 'Archive directory has a payload.'
            ;;
        *) fail 'Archive links and non-regular entries are forbidden.' ;;
    esac
    block=$((block + 1 + (size + 511) / 512))
    [ "$block" -le "$((raw_size / 512))" ] || fail 'Tar payload extends past the archive.'
done
[ "$ended" -ge 2 ] || fail 'Tar is missing its end markers.'
for name in "${allowed[@]}"; do
    found=0
    for previous in "${seen[@]}"; do [ "$name" != "$previous" ] || found=1; done
    [ "$found" = 1 ] || fail "Archive is missing $name."
done
stage="$work/candidate"
mkdir "$stage"
for name in "${allowed[@]}"; do
    destination="$stage/$name"
    mkdir -p "${destination%/*}"
    # Names have been validated, and extraction never lets tar choose a destination path.
    /usr/bin/tar -xOf "$raw" -- "$name" > "$stage/$name" || fail 'Archive extraction failed.'
    chmod 644 "$stage/$name"
done
chmod 755 "$stage/omp" "$stage/update/bun"
for name in locales/ko.json locales/en.json; do
    if [ -f "$target/$name" ]; then cp "$target/$name" "$stage/$name"; fi
done
[ "$("$stage/update/bun" --version)" = "$bun_version" ] || fail 'Bundled Bun version differs from the manifest.'
cat > "$work/validate.cjs" <<'JS'
const fs = require('node:fs');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const [stage, version, work] = process.argv.slice(2);
function assert(ok) { if (!ok) throw Error('Candidate validation failed'); }
for (const language of ['en', 'ko']) {
    const pack = JSON.parse(fs.readFileSync(path.join(stage, 'locales', language + '.json'), 'utf8'));
    assert(pack && !Array.isArray(pack) && typeof pack === 'object' && Object.values(pack).every(x => typeof x === 'string'));
}
function run(argument, language, locales = path.join(stage, 'locales')) {
    const env = {...process.env, HOME: path.join(work, 'home'), XDG_CONFIG_HOME: path.join(work, 'config'), XDG_DATA_HOME: path.join(work, 'data'), XDG_CACHE_HOME: path.join(work, 'cache'), PI_CODING_AGENT_DIR: path.join(work, 'agent-' + language), OMP_LANG: language, OMP_LOCALE_DIR: locales};
    delete env.PI_PROFILE;
    fs.mkdirSync(env.HOME, {recursive: true});
    fs.mkdirSync(env.PI_CODING_AGENT_DIR, {recursive: true});
    const result = spawnSync(path.join(stage, 'omp'), [argument], {cwd: work, env, encoding: 'utf8', timeout: 120000, maxBuffer: 8 * 1024 * 1024});
    assert(!result.error && result.status === 0);
    return result.stdout;
}
for (const language of ['en', 'ko']) {
    assert(run('--version', language).trim() === 'omp/' + version);
    const help = run('--help', language);
    assert(help.length > 100 && help.includes('--model'));
    assert(run('--smoke-test', language).includes('smoke-test: ok'));
}
const probe = path.join(work, 'probe-locales');
fs.mkdirSync(probe);
fs.writeFileSync(path.join(probe, 'ko.json'), '{"USAGE":"OMP_INSTALL_LANGUAGE_PROBE"}');
const english = run('--help', 'en', probe);
assert(english.includes('USAGE') && !english.includes('OMP_INSTALL_LANGUAGE_PROBE'));
assert(run('--help', 'ko', probe).includes('OMP_INSTALL_LANGUAGE_PROBE'));
JS
"$stage/update/bun" "$work/validate.cjs" "$stage" "$upstream" "$work" > "$work/validation-output" 2> "$work/validation-error" || fail 'Real executable English/Korean version, help, smoke or external-pack validation failed. Nothing was installed.'
make_directory() {
    local directory=$1
    if [ ! -d "$directory" ]; then
        make_directory "${directory%/*}"
        mkdir "$directory"
        created[${#created[@]}]=$directory
    fi
}
check_developer
check_link
for name in "${allowed[@]}"; do plain_file "$target/$name"; done
transaction=1
make_directory "$target"
mkdir "$work/backup"
for name in "${allowed[@]}"; do
    # Existing external packs are never moved or rewritten, including partial packs.
    case "$name" in locales/ko.json|locales/en.json) [ ! -f "$target/$name" ] || continue ;; esac
    plain_file "$target/$name"
    destination="$target/$name"
    make_directory "${destination%/*}"
    if [ -f "$target/$name" ]; then
        backup_file="$work/backup/$name"
        mkdir -p "${backup_file%/*}"
        mv "$target/$name" "$work/backup/$name"
        saved[${#saved[@]}]=$name
    fi
    mv "$stage/$name" "$target/$name"
    promoted[${#promoted[@]}]=$name
done
make_directory "$bindir"
check_link
if [ ! -L "$bindir/omp" ]; then
    ln -s "$target/omp" "$bindir/omp"
    link_created=1
fi
transaction=0
printf 'Installed omp Korean %s in %s\nStable command: %s/omp\n' "$release_version" "$target" "$bindir"
printf 'Existing external locale packs, authentication, settings and shell profiles were left unchanged.\n'
printf 'If needed, add this directory to PATH yourself (no profiles were modified):\n  export PATH=%q:"$PATH"\n' "$bindir"
printf 'Open a new terminal or run hash -r, then command -v omp. Keep update/ beside omp; run omp update --check to check updates.\n'
