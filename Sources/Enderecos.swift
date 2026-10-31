import Foundation

/// Os dois endereços das listas: canais e acervo VOD.
///
/// Vêm de fábrica e já ativos. Em Ajustes > Listas o usuário pode trocar cada um,
/// apagar para desligar aquela lista (fica guardado um valor vazio), ou restaurar
/// os padrões de fábrica.
enum Enderecos {
    static let padraoCanais = "https://canais-saimo.pages.dev/"
    static let padraoFilmes = "https://filmes-saimo.pages.dev/"

    static let chaveCanais = "linkCanais"
    static let chaveFilmes = "linkFilmes"

    static let mudou = Notification.Name("SaimoEnderecosMudaram")

    static func resolver(guardado: String?, padrao: String) -> String {
        guard let guardado else { return padrao }
        return guardado.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Endereço-base da lista de canais. Vazio quando desligada.
    static var canais: String {
        get { resolver(guardado: UserDefaults.standard.string(forKey: chaveCanais), padrao: padraoCanais) }
        set {
            UserDefaults.standard.set(newValue, forKey: chaveCanais)
            NotificationCenter.default.post(name: mudou, object: nil)
        }
    }

    /// Endereço-base da pasta vod/ (filmes e séries). Vazio quando desligada.
    static var filmes: String {
        get { resolver(guardado: UserDefaults.standard.string(forKey: chaveFilmes), padrao: padraoFilmes) }
        set {
            UserDefaults.standard.set(newValue, forKey: chaveFilmes)
            NotificationCenter.default.post(name: mudou, object: nil)
        }
    }

    static var canaisAtivos: Bool {
        !canais.isEmpty
    }

    static var filmesAtivos: Bool {
        !filmes.isEmpty
    }

    static func restaurarPadroes() {
        UserDefaults.standard.removeObject(forKey: chaveCanais)
        UserDefaults.standard.removeObject(forKey: chaveFilmes)
        NotificationCenter.default.post(name: mudou, object: nil)
    }

    static func normalizar(_ url: String) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        var res = trimmed
        if !res.hasPrefix("http://") && !res.hasPrefix("https://") {
            res = "https://" + res
        }
        if !res.hasSuffix("/") {
            res += "/"
        }
        return res
    }
}
