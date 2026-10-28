#!/bin/bash
# Confere o leitor de .m3u de "Minhas listas" com o gabarito dos 5 clientes.
# Uso: scripts/testar_minhas_listas.sh [pasta com edge.m3u, br.m3u e os .golden.json]
# (os arquivos de teste ficam fora do git; o padrao e a pasta do scratchpad do projeto).
set -euo pipefail
cd "$(dirname "$0")/.."
pasta="${1:-${SAIMO_M3U_GABARITO:-/private/tmp/claude-501/-Volumes-SSD-1TB-DEV-Saimo-SaimoPlayer/c5ddbfb0-60d8-4a33-a367-79cbdbb1be68/scratchpad/m3u}}"
saida="$(mktemp -d)"
trap 'rm -rf "$saida"' EXIT
cp Tests/MinhasListasTeste.swift "$saida/main.swift"
swiftc -swift-version 6 Sources/LeitorM3u.swift "$saida/main.swift" -o "$saida/teste"
"$saida/teste" "$pasta"
