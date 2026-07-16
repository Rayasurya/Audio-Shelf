#!/bin/zsh
set -euo pipefail

script_directory="${0:A:h}"
fixture_directory="${script_directory:h}/Fixtures"
destination="${fixture_directory}/alice.epub"

mkdir -p "${fixture_directory}"
curl --fail --location --output "${destination}" "https://www.gutenberg.org/cache/epub/11/pg11-images.epub"
printf 'Downloaded %s\n' "${destination}"
