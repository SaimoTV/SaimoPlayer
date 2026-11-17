import Foundation

/// Perfil Kids: o que aparece. Contrato em docs/perfis.md.
///
/// Filmes e séries só com classificação indicativa conhecida de Livre a 12 anos
/// (detalhes.txt, via `InfoDosTitulos`); sem classificação, escondido. O filtro
/// mora na leitura do acervo (`Vod`, `Destaques`), então grades, fileiras, busca
/// e fichas já recebem a lista limpa. Conteúdo adulto nunca destranca no Kids
/// (`Parental`) e os addons ficam desligados.
enum Kids {
    static let idadeMaxima = 12

    /// Cópia das classificações, para filtrar fora do main actor.
    struct Classificacoes: Sendable {
        let mapa: [String: InfoDosTitulos.Info]

        func liberado(_ titulo: String, serie: Bool) -> Bool {
            let p = serie ? "s|" : "f|"
            let info = mapa[p + titulo] ?? mapa[p + Kids.semAno(titulo)]
            guard let info else { return false }
            return (0...Kids.idadeMaxima).contains(info.idade)
        }
    }

    /// No Kids, carrega e devolve as classificações; fora dele, nil (nada a filtrar).
    static func preparar() async -> Classificacoes? {
        guard Perfis.kidsAtivo else { return nil }
        await InfoDosTitulos.carregar()
        return Classificacoes(mapa: await MainActor.run { InfoDosTitulos.mapa })
    }

    /// Sem classificações (fora do Kids) devolve como veio; senão, só o liberado.
    /// `serie` nil: vale filme ou série.
    static func filtrar<T>(_ itens: [T], _ c: Classificacoes?, titulo: (T) -> String, serie: (T) -> Bool?) -> [T] {
        guard let c else { return itens }
        return itens.filter { t in
            if let s = serie(t) { return c.liberado(titulo(t), serie: s) }
            return c.liberado(titulo(t), serie: true) || c.liberado(titulo(t), serie: false)
        }
    }

    /// "Nome (2020)" -> "Nome".
    static func semAno(_ titulo: String) -> String {
        titulo.replacingOccurrences(of: #"\s*\(\d{4}\)\s*$"#, with: "", options: .regularExpression)
    }
}
