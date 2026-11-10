#!/bin/bash
# Testa o endereço de fábrica guardado uma vez (2.8.0), sem rede.
set -euo pipefail
cd "$(dirname "$0")/.."
saida="$(mktemp -d)"
trap 'rm -rf "$saida"' EXIT
cp Tests/EnderecosTeste.swift "$saida/main.swift"
swiftc -swift-version 6 Sources/Enderecos.swift "$saida/main.swift" -o "$saida/teste"
"$saida/teste" | grep -v '^ok' || true
"$saida/teste" >/dev/null && echo "enderecos: tudo certo"
