#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
scene_check_dir="$(mktemp -d /tmp/reset-scene-check.XXXXXX)"
trap 'rm -f "$scene_check_dir/check"; rmdir "$scene_check_dir"' EXIT
swiftc Sources/ResetApp/BrandPalette.swift Sources/ResetApp/DotMeshSimulation.swift Sources/ResetApp/MacTilt.swift Sources/ResetApp/SceneSettings.swift Sources/ResetApp/GlassSceneOptics.swift Sources/ResetApp/MatteSurface.swift Sources/ResetApp/PhysicalGlassBar.swift scripts/scene-check/main.swift -o "$scene_check_dir/check"
"$scene_check_dir/check"
