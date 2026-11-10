import Foundation

// Endereços das listas sem padrão de fábrica (3.0). Sem rede.
// Rodar: ./scripts/testar_enderecos.sh
nonisolated(unsafe) var falhas = 0
func conferir(_ ok: Bool, _ nome: String) {
    if !ok { falhas += 1; print("FALHOU: \(nome)") } else { print("ok: \(nome)") }
}
let dd = UserDefaults.standard
dd.removeObject(forKey: Enderecos.chaveCanais); dd.removeObject(forKey: Enderecos.chaveFilmes)
conferir(Enderecos.canais == "" && Enderecos.filmes == "", "sem nada guardado: sem endereco")
conferir(!Enderecos.canaisAtivos && !Enderecos.filmesAtivos, "sem endereco: listas desligadas")
dd.set("https://outra.dev/", forKey: Enderecos.chaveFilmes)
conferir(Enderecos.filmes == "https://outra.dev/" && Enderecos.filmesAtivos, "endereco guardado vale")
dd.set("   ", forKey: Enderecos.chaveCanais)
conferir(Enderecos.canais == "" && !Enderecos.canaisAtivos, "so espaco = desligada")
dd.removeObject(forKey: Enderecos.chaveCanais); dd.removeObject(forKey: Enderecos.chaveFilmes)
exit(falhas == 0 ? 0 : 1)
