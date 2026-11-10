import Foundation

/// Os dois endereços das listas no formato do Saimo: canais e acervo VOD.
///
/// O app não traz endereço nenhum: o usuário informa em Ajustes > Listas (ou
/// adiciona uma lista M3U / com usuário e senha em "Minhas listas"). Sem
/// endereço a lista fica desligada, sem nenhum pedido de rede. Quem já usava um
/// endereço o tem gravado e continua com ele.
enum Enderecos {
    static let chaveCanais = "linkCanais"
    static let chaveFilmes = "linkFilmes"

    static let mudou = Notification.Name("SaimoEnderecosMudaram")

    static func resolver(guardado: String?) -> String {
        (guardado ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Endereço-base da lista de canais. Vazio quando desligada.
    static var canais: String {
        get { resolver(guardado: UserDefaults.standard.string(forKey: chaveCanais)) }
        set {
            UserDefaults.standard.set(newValue, forKey: chaveCanais)
            NotificationCenter.default.post(name: mudou, object: nil)
        }
    }

    /// Endereço-base da pasta vod/ (filmes e séries). Vazio quando desligada.
    static var filmes: String {
        get { resolver(guardado: UserDefaults.standard.string(forKey: chaveFilmes)) }
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
