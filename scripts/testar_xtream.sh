#!/bin/bash
# Testa o cliente Xtream (usuário e senha) sem rede.
set -euo pipefail
cd "$(dirname "$0")/.."
saida="$(mktemp -d)"
trap 'rm -rf "$saida"' EXIT
cp Tests/XtreamTeste.swift "$saida/main.swift"
swiftc -swift-version 6 Sources/Xtream.swift "$saida/main.swift" -o "$saida/teste"
"$saida/teste" | grep -v '^ok' || true
"$saida/teste" >/dev/null && echo "xtream: tudo certo"
