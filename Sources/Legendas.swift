import Foundation

/// Legendas externas de filmes e séries, pelo OpenSubtitles.
///
/// O serviço é o addon público do Stremio para o OpenSubtitles
/// (opensubtitles-v3.strem.io): sem chave, sem cadastro, e entrega o arquivo já
/// em UTF-8. Só entende IMDb; o acervo só conhece o id do TMDB, e a ponte está
/// publicada em `vod/imdb/` (gerar_imdb.py) em fragmentos de uns 8 KB — baixa-se
/// o fragmento do título aberto, nunca o mapa inteiro. Mesma fonte do site, do
/// Windows, da TV Box e do celular.
///
/// Nada é baixado antes da hora: abrir um título custa uma lista de ~30 KB, e o
/// arquivo .srt (~40 KB) só vem quando a pessoa escolhe uma legenda.
///
/// O AVPlayer não abre legenda externa em mp4 progressivo, então o texto é
/// desenhado por cima do vídeo (`LegendaNaTela`), sincronizado com o relógio do
/// player — o que de quebra permite ajustar o atraso sem baixar nada de novo.
enum Legendas {

    struct Opcao: Identifiable, Equatable, Sendable {
        let id: String
        /// Código do OpenSubtitles: "pob", "por", "eng", "spa".
        let idioma: String
        let rotulo: String
        let url: URL
    }

    // MARK: - Extensão Addons / VTT / IdResolver

    static func normalizarCodigoIdioma(_ raw: String) -> (codigo: String, rotulo: String) {
        let low = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch low {
        case "pob", "pt-br", "pt_br", "pb", "por-br", "brazilian", "portuguese (brazil)":
            return ("pob", "Português (BR)")
        case "por", "pt", "pt-pt", "pt_pt", "portuguese":
            return ("por", "Português")
        case "eng", "en", "en-us", "en-gb", "english":
            return ("eng", "Inglês")
        case "spa", "es", "es-419", "es-es", "spanish", "lat":
            return ("spa", "Espanhol")
        case "fre", "fra", "fr", "french":
            return ("fra", "Francês")
        case "ita", "it", "italian":
            return ("ita", "Italiano")
        case "ger", "deu", "de", "german":
            return ("deu", "Alemão")
        case "jpn", "ja", "japanese":
            return ("jpn", "Japonês")
        default:
            let limpo = low.isEmpty ? "und" : String(low.prefix(8))
            return (limpo, limpo.uppercased())
        }
    }

    /// Combina legendas de `stream.subtitles[]`, addons com recurso `subtitles` e OpenSubtitles via `IdResolver`.
    @MainActor
    static func deComAddons(
        tmdb: Int?,
        imdbId: String?,
        serie: Bool,
        temporada: Int = 0,
        episodio: Int = 0,
        embutidas: [StremioSubtitle] = [],
        addons: [AddonInstalado]? = nil,
        videoHash: String? = nil,
        videoSize: Int64? = nil,
        filename: String? = nil
    ) async -> [Opcao] {
        let addonsAtivos = addons ?? AddonStore.shared.ativos
        let resolved = await IdResolver.shared.resolver(
            tmdbId: tmdb,
            imdbId: imdbId,
            serie: serie
        )

        async let baseOpenSubtitles: [Opcao] = {
            if let t = resolved.tmdbId, t > 0, Enderecos.filmesAtivos {
                return await Legendas.de(tmdb: t, serie: serie, temporada: temporada, episodio: episodio)
            }
            if let imdb = resolved.imdbId {
                return await buscarOpenSubtitlesPorImdb(imdb, serie: serie, temporada: temporada, episodio: episodio)
            }
            return []
        }()

        async let addonSubs = SaimoAddonCoordinator.shared.buscarLegendas(
            addons: addonsAtivos,
            ids: resolved,
            temporada: serie && temporada > 0 ? temporada : nil,
            episodio: serie && episodio > 0 ? episodio : nil,
            videoHash: videoHash,
            videoSize: videoSize,
            filename: filename
        )

        var resultado: [Opcao] = []
        var urlsVistas = Set<String>()

        func adicionar(id: String, langRaw: String, urlStr: String, origem: String) {
            guard let url = URL(string: urlStr),
                  urlsVistas.insert(url.absoluteString).inserted else { return }
            let norm = normalizarCodigoIdioma(langRaw)
            let sufixo = origem.isEmpty ? "" : " · \(origem)"
            resultado.append(Opcao(id: id, idioma: norm.codigo, rotulo: "\(norm.rotulo)\(sufixo)", url: url))
        }

        for sub in embutidas {
            adicionar(id: "stream::\(sub.id)", langRaw: sub.lang, urlStr: sub.url, origem: "Stream")
        }

        for item in await addonSubs {
            adicionar(
                id: "addon::\(item.addonName)::\(item.subtitle.id)",
                langRaw: item.subtitle.lang,
                urlStr: item.subtitle.url,
                origem: item.addonName
            )
        }

        for op in await baseOpenSubtitles where urlsVistas.insert(op.url.absoluteString).inserted {
            resultado.append(op)
        }

        return resultado
    }

    private static func buscarOpenSubtitlesPorImdb(
        _ imdbId: String,
        serie: Bool,
        temporada: Int,
        episodio: Int
    ) async -> [Opcao] {
        let digitos = String(imdbId.dropFirst(2).split(separator: ":").first ?? "")
        guard !digitos.isEmpty, Int(digitos) != nil else { return [] }
        var caminho = "https://rest.opensubtitles.org/search"
        if serie && temporada > 0 && episodio > 0 {
            caminho += "/episode-\(episodio)/imdbid-\(digitos)/season-\(temporada)"
        } else {
            caminho += "/imdbid-\(digitos)"
        }
        guard let url = URL(string: caminho) else { return [] }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.setValue("TemporaryUserAgent", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let lista = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        var saida: [Opcao] = []
        var porIdioma: [String: Int] = [:]
        for item in lista {
            guard let langId = item["SubLanguageID"] as? String,
                  ["pob", "por", "eng", "spa"].contains(langId),
                  let dlRaw = item["SubDownloadLink"] as? String else { continue }
            let count = porIdioma[langId, default: 0]
            guard count < 3 else { continue }
            let srtURLStr = dlRaw.replacingOccurrences(of: ".gz", with: "")
            guard let srtURL = URL(string: srtURLStr) else { continue }
            porIdioma[langId] = count + 1
            let norm = normalizarCodigoIdioma(langId)
            let sufixo = count == 0 ? "" : " (\(count + 1))"
            let id = (item["IDSubtitleFile"] as? String) ?? "\(langId)-\(count)"
            saida.append(Opcao(id: id, idioma: langId, rotulo: "\(norm.rotulo)\(sufixo)", url: srtURL))
        }
        return saida
    }

    /// Baixa legenda suportando tanto `.srt` quanto WebVTT (`.vtt`) usados por addons Stremio.
    @MainActor
    static func baixarQualquer(_ opcao: Opcao) async -> [Fala]? {
        let ehVTTURL = opcao.url.pathExtension.lowercased() == "vtt" || opcao.url.absoluteString.lowercased().contains(".vtt")
        if !ehVTTURL, let srt = await baixar(opcao), !srt.isEmpty {
            return srt
        }
        var req = URLRequest(url: opcao.url)
        req.timeoutInterval = 10
        req.setValue("SaimoPlayer/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        let texto = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        guard !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let falas = lerWebVTTouSRT(texto)
        return falas.isEmpty ? nil : falas
    }

    /// Analisa tanto legendas WebVTT (`WEBVTT`, `MM:SS.mmm`) quanto SRT padrão.
    static func lerWebVTTouSRT(_ conteudo: String) -> [Fala] {
        let norm = conteudo
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if norm.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("WEBVTT") {
            return parsearVTT(norm)
        }
        let srt = ler(norm)
        return srt.isEmpty ? parsearVTT(norm) : srt
    }

    private static func parsearVTT(_ texto: String) -> [Fala] {
        var falas: [Fala] = []
        let blocos = texto.components(separatedBy: "\n\n")
        for bloco in blocos {
            let linhas = bloco
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
            guard let linhaTempo = linhas.first(where: { $0.contains("-->") }),
                  let rangeArrow = linhaTempo.range(of: "-->"),
                  let idxTempo = linhas.firstIndex(where: { $0.contains("-->") }) else { continue }

            let inicioStr = String(linhaTempo[..<rangeArrow.lowerBound]).trimmingCharacters(in: .whitespaces)
            let fimResto = String(linhaTempo[rangeArrow.upperBound...]).trimmingCharacters(in: .whitespaces)
            let fimStr = fimResto.split(separator: " ").first.map(String.init) ?? fimResto

            guard let ini = segundosVTT(inicioStr), let fim = segundosVTT(fimStr), fim > ini else { continue }
            let corpo = linhas[(idxTempo + 1)...]
                .joined(separator: "\n")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !corpo.isEmpty else { continue }
            falas.append(Fala(inicio: ini, fim: fim, texto: corpo))
        }
        return falas
    }

    private static func segundosVTT(_ s: String) -> Double? {
        let limpo = s.replacingOccurrences(of: ",", with: ".")
        let partes = limpo.split(separator: ":")
        if partes.count == 3,
           let h = Double(partes[0]), let m = Double(partes[1]), let sec = Double(partes[2]) {
            return h * 3600 + m * 60 + sec
        }
        if partes.count == 2,
           let m = Double(partes[0]), let sec = Double(partes[1]) {
            return m * 60 + sec
        }
        return nil
    }

    struct Fala: Equatable {
        let inicio: Double
        let fim: Double
        let texto: String
    }

    private static var base: String { Enderecos.filmes }
    private static let servico = "https://opensubtitles-v3.strem.io/subtitles"
    private static let fragmentosPorTipo = 100

    /// Idiomas oferecidos, na ordem em que aparecem: código, nome, quantas versões.
    private static let idiomas: [(codigo: String, nome: String, limite: Int)] = [
        ("pob", "Português (Brasil)", 5),
        ("por", "Português (Portugal)", 3),
        ("eng", "Inglês", 3),
        ("spa", "Espanhol", 2),
    ]

    @MainActor private static var fragmentos: [String: [Int: String]] = [:]
    @MainActor private static var listas: [String: [Opcao]] = [:]
    @MainActor private static var arquivos: [URL: [Fala]] = [:]

    private static func texto(_ endereco: String) async -> Data? {
        guard let url = URL(string: endereco) else { return nil }
        var pedido = URLRequest(url: url, timeoutInterval: 20)
        pedido.setValue("*/*", forHTTPHeaderField: "Accept")
        guard let (dados, resposta) = try? await URLSession.shared.data(for: pedido),
              (resposta as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return dados
    }

    @MainActor
    private static func imdb(de tmdb: Int, serie: Bool) async -> String? {
        let nome = "\(serie ? "s" : "f")-\(String(format: "%02d", tmdb % fragmentosPorTipo))"
        if let mapa = fragmentos[nome] { return mapa[tmdb] }
        // Sem o fragmento (rede fora, título ainda não mapeado) não guarda nada:
        // a próxima abertura tenta de novo.
        guard Enderecos.filmesAtivos, let dados = await texto("\(base)imdb/\(nome).txt"),
              let corpo = String(data: dados, encoding: .utf8) else { return nil }
        var mapa: [Int: String] = [:]
        for linha in corpo.split(separator: "\n") {
            let partes = linha.split(separator: "\t")
            if partes.count >= 2, let id = Int(partes[0].trimmingCharacters(in: .whitespaces)) {
                mapa[id] = partes[1].trimmingCharacters(in: .whitespaces)
            }
        }
        fragmentos[nome] = mapa
        return mapa[tmdb]
    }

    /// As legendas do título, do melhor idioma para o pior. Vazio quando não há.
    @MainActor
    static func de(tmdb: Int, serie: Bool, temporada: Int = 0, episodio: Int = 0) async -> [Opcao] {
        guard tmdb > 0 else { return [] }
        let chave = "\(serie)|\(tmdb)|\(temporada)|\(episodio)"
        if let pronta = listas[chave] { return pronta }
        guard let imdb = await imdb(de: tmdb, serie: serie) else { return [] }
        let alvo = serie && temporada > 0 ? "series/\(imdb):\(temporada):\(episodio)" : "movie/\(imdb)"
        guard let dados = await texto("\(servico)/\(alvo).json"),
              let json = try? JSONSerialization.jsonObject(with: dados) as? [String: Any],
              let todas = json["subtitles"] as? [[String: Any]] else { return [] }
        var saida: [Opcao] = []
        for (codigo, nome, limite) in idiomas {
            var n = 0
            for s in todas where n < limite {
                guard (s["lang"] as? String) == codigo,
                      let endereco = s["url"] as? String, let url = URL(string: endereco) else { continue }
                let versao = [s["releaseGroup"], s["releaseFormat"]]
                    .compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespaces) }
                    .first { !$0.isEmpty } ?? String(n + 1)
                saida.append(Opcao(id: "\(codigo)-\(s["id"] ?? n)", idioma: codigo,
                                   rotulo: "\(nome) · \(versao)", url: url))
                n += 1
            }
        }
        listas[chave] = saida
        return saida
    }

    /// As falas de uma legenda, ordenadas. Nulo quando o servidor devolveu outra coisa.
    @MainActor
    static func baixar(_ opcao: Opcao) async -> [Fala]? {
        if let pronta = arquivos[opcao.url] { return pronta }
        guard let dados = await texto(opcao.url.absoluteString),
              let corpo = String(data: dados, encoding: .utf8) ?? String(data: dados, encoding: .isoLatin1)
        else { return nil }
        let falas = ler(corpo)
        // Página de erro no lugar do arquivo: melhor sem legenda que com HTML na tela.
        guard !falas.isEmpty else { return nil }
        arquivos[opcao.url] = falas
        return falas
    }

    // MARK: - SRT

    private static let tempo = try! NSRegularExpression(pattern: #"(\d+):(\d{2}):(\d{2})[,.](\d{1,3})"#)
    private static let marcacao = try! NSRegularExpression(pattern: #"<[^>]+>|\{\\[^}]*\}"#)

    private static func segundos(_ linha: Substring) -> Double? {
        let texto = String(linha)
        let intervalo = NSRange(texto.startIndex..., in: texto)
        guard let m = tempo.firstMatch(in: texto, range: intervalo) else { return nil }
        func campo(_ i: Int) -> String {
            Range(m.range(at: i), in: texto).map { String(texto[$0]) } ?? "0"
        }
        let milis = campo(4).padding(toLength: 3, withPad: "0", startingAt: 0)
        return (Double(campo(1)) ?? 0) * 3600 + (Double(campo(2)) ?? 0) * 60
            + (Double(campo(3)) ?? 0) + (Double(milis) ?? 0) / 1000
    }

    /// SRT em falas; marcação de estilo sai, porque o texto é desenhado à parte.
    static func ler(_ conteudo: String) -> [Fala] {
        let limpo = conteudo.replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var falas: [Fala] = []
        for bloco in limpo.components(separatedBy: "\n\n") {
            let linhas = bloco.split(separator: "\n", omittingEmptySubsequences: false)
            guard let i = linhas.firstIndex(where: { $0.contains("-->") }) else { continue }
            let tempos = linhas[i].components(separatedBy: "-->")
            guard tempos.count == 2,
                  let inicio = segundos(Substring(tempos[0])), let fim = segundos(Substring(tempos[1])),
                  fim > inicio else { continue }
            let bruto = linhas[(i + 1)...].joined(separator: "\n")
            let texto = marcacao.stringByReplacingMatches(
                in: bruto, range: NSRange(bruto.startIndex..., in: bruto), withTemplate: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !texto.isEmpty { falas.append(Fala(inicio: inicio, fim: fim, texto: texto)) }
        }
        return falas.sorted { $0.inicio < $1.inicio }
    }

    /// A fala que está no ar em [t], por busca binária.
    static func fala(em t: Double, nas falas: [Fala]) -> String? {
        var baixo = 0, alto = falas.count
        while baixo < alto {
            let meio = (baixo + alto) / 2
            if falas[meio].inicio <= t { baixo = meio + 1 } else { alto = meio }
        }
        // Falas podem se sobrepor: olha algumas para trás.
        var i = baixo - 1
        while i >= 0, i >= baixo - 4 {
            if t < falas[i].fim { return falas[i].texto }
            i -= 1
        }
        return nil
    }

    // MARK: - Idioma lembrado

    /// O idioma escolhido da última vez; vazio é "desligadas".
    static var idiomaGuardado: String {
        get { UserDefaults.standard.string(forKey: "legendaExternaIdioma") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "legendaExternaIdioma") }
    }
}
