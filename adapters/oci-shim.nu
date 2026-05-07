#!/usr/bin/env nu
# adapters/oci-shim.nu — subprocess shim for oci_deploy
# Invoked by genoa.nu as `^nu adapters/oci-shim.nu <manifest_json> <image_path> [--dry-run]`
# This isolates the `source formats/convert.nu` top-level expression in oci.nu
# from genoa.nu's if/else branch, preventing a closure leak to stdout.
#
# SPDX-License-Identifier: BSD-2-Clause

source ../formats/convert.nu
source oci.nu

def main [
    manifest_json: string
    image_path: string
    --dry-run
] {
    let manifest = ($manifest_json | from json)
    oci_deploy $manifest $image_path --dry-run=$dry_run | to json --indent 2
}
