#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mesh_check_dir="$(mktemp -d /tmp/reset-mesh-check.XXXXXX)"
trap 'rm -f "$mesh_check_dir/check"; rmdir "$mesh_check_dir"' EXIT
swiftc -O Sources/ResetApp/DotMeshSimulation.swift scripts/mesh-check/main.swift -o "$mesh_check_dir/check"
"$mesh_check_dir/check"
