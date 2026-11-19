import Foundation

/// Estatísticas pessoais do perfil: tempo assistido, filmes e episódios vistos.
///
/// O tempo soma a cada gravação do ponto, com teto por intervalo para uma
/// pausa longa ou um salto não inflar o total.
@MainActor
enum Estatisticas {
    private static let chave = "estatisticas.ms"
    private static let maximo: Double = 60
    private static var ultimo: Date?

    static func tocando(_ tocando: Bool) {
        let agora = Date()
        defer { ultimo = tocando ? agora : nil }
        guard tocando, let antes = ultimo else { return }
        let delta = agora.timeIntervalSince(antes)
        guard delta > 0, delta <= maximo else { return }
        Perfis.defaults.set(Perfis.defaults.double(forKey: chave) + delta * 1000, forKey: chave)
    }

    static func parar() { ultimo = nil }

    static func resumo() -> String {
        let ms = Perfis.defaults.double(forKey: chave)
        let min = Int(ms / 60_000)
        var filmes = 0, episodios = 0
        for (k, v) in Perfis.defaults.dictionaryRepresentation() where k.hasPrefix("visto.") && (v as? Bool) == true {
            if k.hasPrefix("visto.f|") { filmes += 1 } else if k.hasPrefix("visto.s|") { episodios += 1 }
        }
        return "\(min / 60) h \(min % 60) min · \(filmes) filmes · \(episodios) episódios"
    }
}
