#!/bin/bash
# Confere a classificação de itens de listas M3U (canal, filme, episódio) com o gabarito.
set -euo pipefail
cd "$(dirname "$0")/.."
saida="$(mktemp -d)"
trap 'rm -rf "$saida"' EXIT
cp Tests/ClassificarTeste.swift "$saida/main.swift"
swiftc -swift-version 6 Sources/Classificar.swift "$saida/main.swift" -o "$saida/teste"
"$saida/teste" | grep -v '^ok' || true
"$saida/teste" >/dev/null && echo "classificar: tudo certo"
