#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECTS=(
    Telegram.xcodeproj/project.pbxproj
    submodules/CodeSyntax/CodeSyntax/CodeSyntax.xcodeproj/project.pbxproj
    submodules/RLottie_Xcode/RLottie_Xcode.xcodeproj/project.pbxproj
    submodules/Sparkle/Sparkle.xcodeproj/project.pbxproj
    core-xprojects/OpenH264/OpenH264.xcodeproj/project.pbxproj
    core-xprojects/openssl/OpenSSLEncryption.xcodeproj/project.pbxproj
    core-xprojects/libopus/libopus.xcodeproj/project.pbxproj
    core-xprojects/libvpx/libvpx.xcodeproj/project.pbxproj
    core-xprojects/Mozjpeg/Mozjpeg.xcodeproj/project.pbxproj
    core-xprojects/libwebp/libwebp.xcodeproj/project.pbxproj
    core-xprojects/dav1d/dav1d.xcodeproj/project.pbxproj
    core-xprojects/ffmpeg/ffmpeg.xcodeproj/project.pbxproj
    core-xprojects/webrtc/webrtc.xcodeproj/project.pbxproj
    core-xprojects/tde2e/tde2e.xcodeproj/project.pbxproj
    core-xprojects/wallet-engine/WalletEngine.xcodeproj/project.pbxproj
    core-xprojects/mtproto-engine/MTProtoEngine.xcodeproj/project.pbxproj
)
TELEGRAM_CORE_MANIFEST=submodules/telegram-ios/submodules/TelegramCore/Package.swift
SHADER_MANIFESTS=(
    packages/CallVideoLayer/Package.swift
    packages/DustLayer/Package.swift
    submodules/telegram-ios/submodules/MetalEngine/Package.swift
)
SHADER_RESOURCES='(,\s*resources:\s*\[\s*\.copy\("[^"]+\.metal"\)(?:\s*,\s*\.copy\("[^"]+\.metal"\))*\s*\])'
BUILD_CONFIGURATION='^\t\t([0-9A-Fa-f]{24}) (?:/\*[^\n]*?\*/ )?= \{\n\t\t\tisa = XCBuildConfiguration;\n.*?^\t\t\};\n'
failed=0

usage() {
    cat >&2 <<EOF
usage: scripts/xcode27.sh apply|revert

  apply    make the local changes from XCODE27.md so the project builds with Xcode 27
  revert   undo only those changes, keeping any other edits in the same files
EOF
    exit 2
}

fail() {
    echo "$1" >&2
    failed=1
}

head_version() {
    git -C "$(dirname "$1")" show "HEAD:./$(basename "$1")"
}

update() {
    local action="$1" path="$2" file="$ROOT/$2" before
    if [[ ! -f "$file" ]]; then
        fail "missing: $path"
        return
    fi
    before="$(shasum "$file")"
    "$action" "$path" "$file"
    if [[ "$(shasum "$file")" == "$before" ]]; then
        echo "unchanged: $path"
    else
        echo "changed:   $path"
    fi
}

raise_deployment_target() {
    perl -pi -e 's/(MACOSX_DEPLOYMENT_TARGET = )(?:10|11)(?:\.\d+)*;/${1}12.0;/g' "$2"
    if grep -qE 'MACOSX_DEPLOYMENT_TARGET = "?1[01]\.' "$2"; then
        fail "unexpected layout, set 12.0 by hand: $1"
    fi
}

restore_deployment_target() {
    local head
    head="$(head_version "$2")" || { fail "not in HEAD: $1"; return; }
    BUILD_CONFIGURATION="$BUILD_CONFIGURATION" perl -e '
        my ($file) = @ARGV;
        local $/;
        my $head = <STDIN>;
        my %original;
        while ($head =~ /$ENV{BUILD_CONFIGURATION}/gms) {
            my ($id, $entry) = ($1, $&);
            $original{$id} = $1 if $entry =~ /MACOSX_DEPLOYMENT_TARGET = ([^;]+);/;
        }
        open my $in, "<", $file or die "$file: $!\n";
        my $text = <$in>;
        close $in;
        my $restored = $text;
        $restored =~ s{$ENV{BUILD_CONFIGURATION}}{
            my ($id, $entry) = ($1, $&);
            my $value = $original{$id};
            $entry =~ s/(MACOSX_DEPLOYMENT_TARGET = )12\.0;/$1$value;/ if defined $value;
            $entry;
        }gmse;
        exit 0 if $restored eq $text;
        open my $out, ">", $file or die "$file: $!\n";
        print $out $restored;
        close $out;
    ' "$2" <<< "$head" || fail "restore by hand: $1"
}

relax_telegram_core_warnings() {
    perl -0pi -e '
        s/swiftSettings: \[\.unsafeFlags\(\["-warnings-as-errors"\]\)\]/swiftSettings: [\n                .unsafeFlags([\n                    "-warnings-as-errors",\n                    "-Wwarning", "ImplicitStrongCapture"\n                ])\n            ]/
            unless /ImplicitStrongCapture/;
    ' "$2"
    if ! grep -q ImplicitStrongCapture "$2"; then
        fail "unexpected layout, edit by hand: $1"
    fi
}

restore_telegram_core_warnings() {
    perl -0pi -e '
        s/swiftSettings: \[\s*\.unsafeFlags\(\[\s*"-warnings-as-errors",\s*"-Wwarning",\s*"ImplicitStrongCapture"\s*\]\)\s*\]/swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]/;
    ' "$2"
    if grep -q ImplicitStrongCapture "$2"; then
        fail "unexpected layout, restore by hand: $1"
    fi
}

remove_shader_resources() {
    SHADER_RESOURCES="$SHADER_RESOURCES" perl -0pi -e 's/$ENV{SHADER_RESOURCES}//g' "$2"
    if grep -q '\.metal")' "$2"; then
        fail "unexpected layout, edit by hand: $1"
    fi
}

restore_shader_resources() {
    local head
    grep -q '\.metal")' "$2" && return
    head="$(head_version "$2")" || { fail "not in HEAD: $1"; return; }
    SHADER_RESOURCES="$SHADER_RESOURCES" perl -e '
        my ($file) = @ARGV;
        local $/;
        my $head = <STDIN>;
        my ($anchor, $resources) = $head =~ /(path:\s*"[^"]*")$ENV{SHADER_RESOURCES}/ or exit 0;
        open my $in, "<", $file or die "$file: $!\n";
        my $text = <$in>;
        close $in;
        $text =~ s/\Q$anchor\E/$anchor$resources/ or die "cannot find $anchor in $file\n";
        open my $out, ">", $file or die "$file: $!\n";
        print $out $text;
        close $out;
    ' "$2" <<< "$head" || fail "restore by hand: $1"
}

apply() {
    local path
    for path in "${PROJECTS[@]}"; do
        update raise_deployment_target "$path"
    done
    update relax_telegram_core_warnings "$TELEGRAM_CORE_MANIFEST"
    for path in "${SHADER_MANIFESTS[@]}"; do
        update remove_shader_resources "$path"
    done
    if [[ "$(xcodebuild -showComponent MetalToolchain 2>/dev/null || true)" != *"Status: installed"* ]]; then
        echo "Metal toolchain is not installed, run: xcodebuild -downloadComponent MetalToolchain"
    fi
}

revert() {
    local path
    for path in "${PROJECTS[@]}"; do
        update restore_deployment_target "$path"
    done
    update restore_telegram_core_warnings "$TELEGRAM_CORE_MANIFEST"
    for path in "${SHADER_MANIFESTS[@]}"; do
        update restore_shader_resources "$path"
    done
}

case "${1:-}" in
    apply) apply ;;
    revert) revert ;;
    *) usage ;;
esac
exit "$failed"
