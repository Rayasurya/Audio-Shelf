#!/bin/zsh
# Runs the package tests with Command Line Tools only (no full Xcode).
# CLT ships Swift Testing in a non-default location, so the framework and
# its interop dylib have to be passed explicitly.
set -euo pipefail

script_directory="${0:A:h}"
frameworks=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
interop_lib=/Library/Developer/CommandLineTools/Library/Developer/usr/lib

cd "${script_directory:h}"
swift test \
    -Xswiftc -F"${frameworks}" \
    -Xlinker -F"${frameworks}" \
    -Xlinker -rpath -Xlinker "${frameworks}" \
    -Xlinker -rpath -Xlinker "${interop_lib}" \
    "$@"
