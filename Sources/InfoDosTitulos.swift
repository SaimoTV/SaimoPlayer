import Foundation

/// Ano, nota, classificação indicativa e popularidade de cada título, para os
/// filtros do On Demand. Vem de `detalhes.txt` (gerar_detalhes.py, do TMDB).
///
/// Sem o arquivo os filtros de ano, idade e nota não aparecem, e a ordem cai no
/// ano do nome do título.
@MainActor
enum InfoDosTitulos {
    struct Info: Sendable {
        let ano: Int
        let nota: Double
        /// 0 = Livre, 10...18 = idade; -1 = não informada.
        let idade: Int
        let popularidade: Int
    }

    private(set) static var mapa: [String: Info] = [:]
    private static var carregando = false
    static var prontos: Bool { !mapa.isEmpty }

    static func de(_ titulo: String, serie: Bool) -> Info? {
        let p = serie ? "s|" : "f|"
        return mapa[p + titulo] ?? mapa[p + Generos.semAno(titulo)]
    }

    static func carregar() async {
        if prontos || carregando || !Enderecos.filmesAtivos { return }
        guard let url = URL(string: Enderecos.filmes + "detalhes.txt") else { return }
        carregando = true
        defer { carregando = false }
        var pedido = URLRequest(url: url)
        pedido.setValue(Upstream.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (dados, resposta) = try? await URLSession.shared.data(for: pedido),
              (resposta as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) == true,
              let texto = String(data: dados, encoding: .utf8) else { return }
        mapa = await Task.detached(priority: .utility) { ler(texto) }.value
    }

    nonisolated private static func ler(_ texto: String) -> [String: Info] {
        var out: [String: Info] = [:]
        out.reserveCapacity(40_000)
        for linha in texto.split(separator: "\n") {
            if linha.hasPrefix("#") { continue }
            let c = linha.split(separator: "\t", omittingEmptySubsequences: false)
            guard c.count >= 6 else { continue }
            let idade: Int = c[4] == "L" ? 0 : (Int(c[4]) ?? -1)
            out["\(c[0])|\(c[1])"] = Info(ano: Int(c[2]) ?? 0, nota: Double(c[3]) ?? 0,
                                         idade: idade, popularidade: Int(c[5]) ?? 0)
        }
        return out
    }
}
