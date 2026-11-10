import Foundation

// Endereço de fábrica guardado uma vez (2.8.0). Sem rede.
// Rodar: ./scripts/testar_enderecos.sh
nonisolated(unsafe) var falhas = 0
func conferir(_ ok: Bool, _ nome: String) {
    if !ok { falhas += 1; print("FALHOU: \(nome)") } else { print("ok: \(nome)") }
}
let dd = UserDefaults.standard
dd.removeObject(forKey: Enderecos.chaveCanais); dd.removeObject(forKey: Enderecos.chaveFilmes)
dd.removeObject(forKey: "linksEm")
Enderecos.guardarPadroesDeQuemNuncaEscolheu()
conferir(dd.string(forKey: Enderecos.chaveCanais) == Enderecos.padraoCanais
         && dd.string(forKey: Enderecos.chaveFilmes) == Enderecos.padraoFilmes, "guarda o padrao de quem nunca escolheu")
conferir(Enderecos.escolhidosEm == 0, "guardar o padrao nao conta como escolha")
dd.set("", forKey: Enderecos.chaveCanais)
dd.set("https://outra.dev/", forKey: Enderecos.chaveFilmes)
Enderecos.guardarPadroesDeQuemNuncaEscolheu()
conferir(dd.string(forKey: Enderecos.chaveCanais) == "" && dd.string(forKey: Enderecos.chaveFilmes) == "https://outra.dev/",
         "lista desligada ou trocada nao e mexida")
conferir(Enderecos.canais == "" && Enderecos.filmes == "https://outra.dev/", "leitura devolve o guardado")
dd.removeObject(forKey: Enderecos.chaveCanais); dd.removeObject(forKey: Enderecos.chaveFilmes)
exit(falhas == 0 ? 0 : 1)
