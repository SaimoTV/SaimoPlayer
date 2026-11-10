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

    /// Grava, uma vez, o endereço de fábrica de quem nunca escolheu nenhum.
    /// Sem isto o padrão só existia no código; guardado, o app continua com a
    /// mesma lista mesmo quando o endereço de fábrica sair de uma versão futura.
    /// Quem desligou uma lista (valor vazio guardado) continua desligado, e a
    /// data da escolha (`escolhidosEm`) não muda: a sincronia com o celular
    /// não vê isso como uma escolha nova.
    static func guardarPadroesDeQuemNuncaEscolheu() {
        let d = UserDefaults.standard
        if d.object(forKey: chaveCanais) == nil { d.set(padraoCanais, forKey: chaveCanais) }
        if d.object(forKey: chaveFilmes) == nil { d.set(padraoFilmes, forKey: chaveFilmes) }
    }

    static func restaurarPadroes() {
        UserDefaults.standard.removeObject(forKey: chaveCanais)
        UserDefaults.standard.removeObject(forKey: chaveFilmes)
        escolhidosEm = Date().timeIntervalSince1970 * 1000
        NotificationCenter.default.post(name: mudou, object: nil)
    }

    /// Quando os endereços foram escolhidos (ms; 0 = nunca). Na sincronia
    /// pelo Saimo Connect vale o mais recente.
    static var escolhidosEm: Double {
        get { UserDefaults.standard.double(forKey: "linksEm") }
        set { UserDefaults.standard.set(newValue, forKey: "linksEm") }
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
