#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: package_plugin.sh --platform <linux|macos|windows> --arch <arch> \
  --version <version> --plugin <path> --output-dir <path>
EOF
}

platform=""
arch=""
version=""
plugin=""
output_dir=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --platform)
            platform="$2"
            shift 2
            ;;
        --arch)
            arch="$2"
            shift 2
            ;;
        --version)
            version="$2"
            shift 2
            ;;
        --plugin)
            plugin="$2"
            shift 2
            ;;
        --output-dir)
            output_dir="$2"
            shift 2
            ;;
        *)
            usage
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

if [[ -z "$platform" || -z "$arch" || -z "$version" || -z "$plugin" || -z "$output_dir" ]]; then
    usage
    exit 1
fi

if [[ ! -f "${plugin}" ]]; then
    echo "Plugin not found: ${plugin}" >&2
    exit 1
fi

bundle_name="freelumina-${version}-${platform}-${arch}"
zip_path="${output_dir}/${bundle_name}.zip"
archive_path=""

# The repository URL is the identity anchor: the plugin repository indexes a
# plugin by the pair (name, repository URL), and the field is required.
repository_url="${FL_REPOSITORY_URL:-https://github.com/c8c78cf6c6/freelumina}"

# ida-plugin.json platform identifier (IDA plugin-manager vocabulary). The
# supported set is Windows x86_64 and Linux/macOS x86_64/aarch64. Every
# 64-bit ARM leg spells the arch "aarch64", macOS included. An off-vocabulary
# literal does not merely fail this bundle's validation; it can invalidate
# the whole manifest, so the mapping below is deliberately explicit.
case "${platform}-${arch}" in
    linux-x86_64)     ida_platform="linux-x86_64" ;;
    linux-arm64)      ida_platform="linux-aarch64" ;;
    linux-aarch64)    ida_platform="linux-aarch64" ;;
    macos-arm64)      ida_platform="macos-aarch64" ;;
    macos-aarch64)    ida_platform="macos-aarch64" ;;
    macos-x86_64)     ida_platform="macos-x86_64" ;;
    windows-x86_64)   ida_platform="windows-x86_64" ;;
    *)
        echo "No ida-plugin.json platform mapping for ${platform}-${arch}" >&2
        exit 1
        ;;
esac

# The plugin manager wants plain x.y.z semver in ida-plugin.json. Strip any
# +build suffix, then pad a short tag so "1.0" becomes "1.0.0" rather than a
# schema complaint.
plugin_version="${version%%+*}"
case "${plugin_version}" in
    *.*.*) ;;
    *.*) plugin_version="${plugin_version}.0" ;;
    *) plugin_version="${plugin_version}.0.0" ;;
esac

mkdir -p "${output_dir}"
bundle_root="${output_dir}/${bundle_name}"
plugin_root="${bundle_root}/plugins/freelumina"
rm -rf "${bundle_root}"
mkdir -p "${plugin_root}"

# The entry point is resolved by name inside the metadata directory, so the
# binary is renamed to its canonical form regardless of what the caller
# staged. IDA 9+'s plugin manager loads the entry point from the metadata
# directory; the layout doubles as the archive an hcli install consumes.
case "${plugin}" in
    *.dylib) plugin_file="freelumina.dylib" ;;
    *.so)    plugin_file="freelumina.so" ;;
    *.dll)   plugin_file="freelumina.dll" ;;
    *)
        echo "Unrecognized plugin binary: ${plugin}" >&2
        exit 1
        ;;
esac
cp "${plugin}" "${plugin_root}/${plugin_file}"

source_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cp "${source_root}/README.md" "${bundle_root}/README.md"
cp -R "${source_root}/licenses" "${bundle_root}/licenses"

# IDA versions the plugin advertises. The ABI has been the fixed 64-byte
# descriptor since 9.0, and the list below is the honest claim; override
# before shipping if the supported set changes.
ida_versions="${FL_IDA_VERSIONS:-\"9.0\", \"9.1\", \"9.2\", \"9.3\", \"9.4\", \"9.5\"}"

cat > "${plugin_root}/ida-plugin.json" <<EOF
{
  "\$schema": "https://hcli.docs.hex-rays.com/schemas/ida-plugin.json",
  "IDAMetadataDescriptorVersion": 1,
  "plugin": {
    "name": "freelumina",
    "entryPoint": "freelumina",
    "version": "${plugin_version}",
    "description": "resident plugin experiment in C and line-numbered BASIC",
    "urls": { "repository": "${repository_url}" },
    "authors": [ { "name": "Anonymous", "email": "anonymous@example.invalid" } ],
    "idaVersions": [${ida_versions}],
    "platforms": ["${ida_platform}"]
  }
}
EOF

cat > "${bundle_root}/INSTALL.txt" <<EOF
freelumina ${plugin_version} (${platform} ${arch})

Recommended install (IDA 9.0 or later, once the release has been indexed):
  hcli plugin install freelumina

Manual install: copy the contents of ./plugins into the plugins directory of
your IDA user directory. Expected final layout:
  <user plugins dir>/freelumina/ida-plugin.json
  <user plugins dir>/freelumina/${plugin_file}

The user plugins directory is:
  Linux:   ~/.idapro/plugins/
  macOS:   ~/Library/Application Support/IDA Pro/plugins/
  Windows: %APPDATA%\\Hex-Rays\\IDA Pro\\plugins\\

Restart the host after installing. The plugin registers as a fixed, hidden
resident plugin: it wakes once at startup, does not appear in any menu, and
reports to the console. Nothing is written to disk and nothing survives the
process.
EOF

if [[ "${platform}" == "macos" ]]; then
    cat >> "${bundle_root}/INSTALL.txt" <<'EOF'

Note: the macOS plugin is not codesigned by this package flow. If macOS blocks it,
ad-hoc sign the plugin after installing:
  codesign --force --sign - ~/Library/Application\ Support/IDA\ Pro/plugins/freelumina/freelumina.dylib
EOF
fi

# Zip for every platform: it is the format a plugin-manager install consumes
# (and the only manual-install format on Windows). Linux/macOS additionally
# keep the tar.gz, which preserves the exec bits zip extraction loses.
rm -f "${zip_path}"
(
    cd "${output_dir}"
    zip -qr "$(basename "${zip_path}")" "${bundle_name}"
)
echo "Staged ${bundle_root}"
echo "Created ${zip_path}"

if [[ "${platform}" != "windows" ]]; then
    archive_path="${output_dir}/${bundle_name}.tar.gz"
    tar -C "${output_dir}" -czf "${archive_path}" "${bundle_name}"
    echo "Created ${archive_path}"
fi
