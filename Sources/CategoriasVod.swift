import Foundation

/// Categoria de cada título do acervo: anime, dorama, novela e kids.
///
/// Vem de `categorias.txt` (gerar_categorias.py, pelo país de origem e o
/// idioma no TMDB). Título fora do arquivo é filme ou série comum.
@MainActor
enum CategoriasVod {
    private static var filmes: [String: [String]] = [:]
    private static var series: [String: [String]] = [:]
    private static var carregando = false

    static var prontas: Bool { !filmes.isEmpty || !series.isEmpty }

    static func tem(_ titulo: String, serie: Bool, _ categoria: String) -> Bool {
        let mapa = serie ? series : filmes
        let lista = mapa[titulo] ?? mapa[Generos.semAno(titulo)]
        return lista?.contains(categoria) ?? false
    }

    static func carregar() async {
        guard !prontas, !carregando, Enderecos.filmesAtivos,
              let url = URL(string: Enderecos.filmes + "categorias.txt") else { return }
        carregando = true
        defer { carregando = false }
        var pedido = URLRequest(url: url)
        pedido.setValue(Upstream.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (dados, resposta) = try? await URLSession.shared.data(for: pedido),
              (resposta as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) == true,
              let texto = String(data: dados, encoding: .utf8) else { return }
        var f: [String: [String]] = [:], s: [String: [String]] = [:]
        for linha in texto.split(separator: "\n", omittingEmptySubsequences: true) where !linha.hasPrefix("#") {
            let c = linha.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard c.count >= 3 else { continue }
            let cats = c[2].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !cats.isEmpty else { continue }
            if c[0] == "s" { s[c[1]] = cats } else { f[c[1]] = cats }
        }
        filmes = f
        series = s
    }
}

/// Novelinhas: minisséries verticais (720x1280, ~1 min por episódio) da
/// RedeFlix, em `novelinhas.txt`:
///
///     base: https://.../novelinhas/
///     id  título  pasta  episódios  áudio(dub|leg)  capa  gêneros  sinopse
///
/// Episódio N = base + pasta + "/episode-" + N com três dígitos + ".mp4".
@MainActor
final class Novelinhas: ObservableObject {
    static let shared = Novelinhas()

    struct Novelinha: Identifiable, Hashable {
        let id: String
        let titulo: String
        let pasta: String
        let episodios: Int
        let dublada: Bool
        let capa: String
        let generos: [String]
        let sinopse: String
    }

    @Published private(set) var lista: [Novelinha] = []
    private(set) var base = ""
    private var carregando = false

    func url(_ n: Novelinha, _ ep: Int) -> URL? {
        URL(string: base + n.pasta + "/episode-" + String(format: "%03d", ep) + ".mp4")
    }

    func carregar() async {
        guard lista.isEmpty, !carregando, Enderecos.filmesAtivos,
              let url = URL(string: Enderecos.filmes + "novelinhas.txt") else { return }
        carregando = true
        defer { carregando = false }
        var pedido = URLRequest(url: url)
        pedido.setValue(Upstream.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (dados, _) = try? await URLSession.shared.data(for: pedido),
              let texto = String(data: dados, encoding: .utf8) else { return }
        var b = ""
        var saida: [Novelinha] = []
        for linha in texto.split(separator: "\n", omittingEmptySubsequences: true) {
            if linha.hasPrefix("#") { continue }
            if linha.hasPrefix("base:") { b = linha.dropFirst(5).trimmingCharacters(in: .whitespaces); continue }
            let c = linha.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard c.count >= 6, let eps = Int(c[3]), eps > 0 else { continue }
            saida.append(Novelinha(
                id: c[0], titulo: c[1], pasta: c[2], episodios: eps, dublada: c[4] == "dub", capa: c[5],
                generos: (c.count > 6 ? c[6] : "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                sinopse: c.count > 7 ? c[7] : ""))
        }
        guard !b.isEmpty, !saida.isEmpty else { return }
        base = b
        lista = saida
    }

    // MARK: Onde parou (episódio e segundo)

    private let chave = "novelinhas.parada"

    func parada(_ id: String) -> (ep: Int, t: Double)? {
        guard let d = UserDefaults.standard.dictionary(forKey: chave)?[id] as? [String: Double],
              let ep = d["ep"] else { return nil }
        return (Int(ep), d["t"] ?? 0)
    }

    func guardar(_ id: String, ep: Int, t: Double) {
        var tudo = UserDefaults.standard.dictionary(forKey: chave) ?? [:]
        tudo[id] = ["ep": Double(ep), "t": t, "quando": Date().timeIntervalSince1970]
        if tudo.count > 60 {
            let velhos = tudo.sorted {
                (($0.value as? [String: Double])?["quando"] ?? 0) < (($1.value as? [String: Double])?["quando"] ?? 0)
            }.prefix(tudo.count - 60).map(\.key)
            for k in velhos { tudo.removeValue(forKey: k) }
        }
        UserDefaults.standard.set(tudo, forKey: chave)
    }

    func recentes() -> [String] {
        let tudo = UserDefaults.standard.dictionary(forKey: chave) ?? [:]
        return tudo.sorted {
            (($0.value as? [String: Double])?["quando"] ?? 0) > (($1.value as? [String: Double])?["quando"] ?? 0)
        }.map(\.key)
    }
}
