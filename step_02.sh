set -eo pipefail
mkdir -p Motif/Sources/Motif/Models
mkdir -p Motif/Sources/Motif/Engine
mkdir -p Motif/Sources/Motif/Services
mkdir -p Motif/Sources/Motif/Views
mkdir -p Motif/Sources/Motif/Components
mkdir -p Motif/Sources/Motif/Resources/Fonts
mkdir -p build/dmg_staging
mkdir -p build/AppIcon.iconset

curl -sL "https://github.com/google/fonts/raw/main/ofl/plusjakartasans/PlusJakartaSans%5Bwght%5D.ttf" \
  -o Motif/Sources/Motif/Resources/Fonts/PlusJakartaSans-Variable.ttf || true
curl -sL "https://github.com/google/fonts/raw/main/ofl/inter/Inter%5Bopsz,wght%5D.ttf" \
  -o Motif/Sources/Motif/Resources/Fonts/Inter-Variable.ttf || true
curl -sL "https://github.com/google/fonts/raw/main/ofl/opensans/OpenSans%5Bwdth,wght%5D.ttf" \
  -o Motif/Sources/Motif/Resources/Fonts/OpenSans-Variable.ttf || true
curl -sL "https://github.com/google/fonts/raw/main/ofl/geist/Geist%5Bwght%5D.ttf" \
  -o Motif/Sources/Motif/Resources/Fonts/Geist-Variable.ttf || true
