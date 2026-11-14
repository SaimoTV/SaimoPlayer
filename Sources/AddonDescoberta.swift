import SwiftUI
import AppKit

// MARK: - Modelos de Descoberta & Histórico

struct DescobertaItem: Identifiable, Hashable, Sendable {
    let id: String
    let tmdbId: Int?
    let imdbId: String?
    let titulo: String
    let ano: String
    let serie: Bool
    let capa: String?
    let fundo: String?
    let sinopse: String?
    let nota: Double?
    let addonOrigemId: String?

    var nomeCompleto: String {
        if ano.isEmpty || titulo.contains("(\(ano))") { return titulo }
        return "\(titulo) (\(ano))"
    }

    func comoAlvo() -> FichaAlvo {
        FichaAlvo(
            titulo: titulo,
            serie: serie,
            ano: ano,
            letra: serie ? "s" : "f",
            reservado: false,
            tmdbId: tmdbId,
            imdbId: imdbId,
            capaURL: capa.flatMap(URL.init(string:)),
            fundoURL: fundo.flatMap(URL.init(string:))
        )
    }
}

struct AddonDescobertaFila: Identifiable, Hashable, Sendable {
    let id: String
    let titulo: String
    /// `"movie"`, `"series"`, ou `"all"`
    let tipo: String
    let itens: [DescobertaItem]
}

// MARK: - Histórico de reprodução via Addons (suporta Continue Assistindo + remoção)

struct AddonHistoricoItem: Codable, Hashable, Sendable {
    let titulo: String
    let serie: Bool
    let ano: String
    let tmdbId: Int?
    let imdbId: String?
    let poster: String?
    let fundo: String?
    let atualizadoEm: Date
}

@MainActor
final class AddonHistorico: ObservableObject {
    static let shared = AddonHistorico()
    private static let key = "saimo_addon_historico_v1"

    @Published private(set) var itens: [AddonHistoricoItem] = []
    private let defaults = UserDefaults.standard

    private init() {
        carregar()
    }

    func registrar(
        titulo: String,
        serie: Bool,
        ano: String,
        tmdbId: Int?,
        imdbId: String?,
        poster: String?,
        fundo: String?
    ) {
        let limpo = titulo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpo.isEmpty else { return }
        itens.removeAll { normalizar($0.titulo) == normalizar(limpo) && $0.serie == serie }
        itens.insert(
            AddonHistoricoItem(
                titulo: limpo,
                serie: serie,
                ano: ano,
                tmdbId: tmdbId,
                imdbId: imdbId,
                poster: poster,
                fundo: fundo,
                atualizadoEm: Date()
            ),
            at: 0
        )
        if itens.count > 80 { itens = Array(itens.prefix(80)) }
        salvar()
    }

    func contem(titulo: String, serie: Bool) -> Bool {
        buscar(titulo: titulo, serie: serie) != nil
    }

    func buscar(titulo: String, serie: Bool) -> AddonHistoricoItem? {
        let alvo = normalizar(titulo)
        return itens.first { $0.serie == serie && (normalizar($0.titulo) == alvo || normalizar("\($0.titulo) (\($0.ano))") == alvo) }
    }

    func poster(titulo: String, serie: Bool) -> String? {
        buscar(titulo: titulo, serie: serie)?.poster
    }

    func tmdbId(titulo: String, serie: Bool) -> Int? {
        buscar(titulo: titulo, serie: serie)?.tmdbId
    }

    private func normalizar(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func carregar() {
        guard let data = defaults.data(forKey: Self.key),
              let lista = try? JSONDecoder().decode([AddonHistoricoItem].self, from: data) else {
            return
        }
        itens = lista
    }

    private func salvar() {
        if let data = try? JSONEncoder().encode(itens) {
            defaults.set(data, forKey: Self.key)
        }
    }
}

// MARK: - Descoberta TMDB + Catálogos dos Addons

@MainActor
final class AddonDescobertaEstado: ObservableObject {
    static let shared = AddonDescobertaEstado()

    @Published private(set) var filasTMDB: [AddonDescobertaFila] = []
    @Published private(set) var catalogosFilas: [AddonDescobertaFila] = []
    @Published private(set) var carregando = false

    private var ultimaAssinaturaAddons: String = ""
    private var tmdbCarregado = false

    private init() {
        NotificationCenter.default.addObserver(forName: AddonStore.mudou, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.recarregarCatalogosAddons(forcar: true)
            }
        }
    }

    func carregarSePreciso() async {
        guard AddonStore.shared.temAtivos else {
            catalogosFilas = []
            return
        }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.carregarTMDBSePreciso() }
            group.addTask { await self.recarregarCatalogosAddons(forcar: false) }
        }
    }

    func recarregarCatalogosAddons(forcar: Bool) async {
        let ativos = AddonStore.shared.ativos
        let assinatura = ativos.map { "\($0.id.uuidString):\($0.manifest.version)" }.joined(separator: ",")
        if !forcar && assinatura == ultimaAssinaturaAddons && !catalogosFilas.isEmpty {
            return
        }
        ultimaAssinaturaAddons = assinatura
        guard !ativos.isEmpty else {
            catalogosFilas = []
            return
        }

        carregando = true
        defer { carregando = false }

        var pedidos: [(AddonInstalado, AddonCatalog)] = []
        for addon in ativos {
            for cat in addon.manifest.catalogs where !cat.requerBusca {
                guard cat.type == "movie" || cat.type == "series" || cat.type == "anime" else { continue }
                pedidos.append((addon, cat))
            }
        }

        let coletados = await withTaskGroup(of: (Int, AddonDescobertaFila?).self) { group in
            for (idx, par) in pedidos.prefix(16).enumerated() {
                let addon = par.0
                let cat = par.1
                group.addTask {
                    let metas = await SaimoAddonCoordinator.shared.buscarCatalogo(addon: addon, catalogo: cat)
                    guard !metas.isEmpty else { return (idx, nil) }
                    let itens = metas.prefix(30).map { m -> DescobertaItem in
                        let ehSerie = cat.type == "series" || m.type == "series"
                        let anoStr = m.ano.map(String.init) ?? ""
                        return DescobertaItem(
                            id: "addon:\(addon.manifest.id):\(cat.id):\(m.id)",
                            tmdbId: m.tmdbIdNum,
                            imdbId: m.imdbIdPuro,
                            titulo: m.name,
                            ano: anoStr,
                            serie: ehSerie,
                            capa: m.poster,
                            fundo: m.background ?? m.poster,
                            sinopse: m.description,
                            nota: m.imdbRating.flatMap(Double.init),
                            addonOrigemId: addon.manifest.id
                        )
                    }
                    let tipoNorm = (cat.type == "movie") ? "movie" : "series"
                    return (idx, AddonDescobertaFila(
                        id: "cat:\(addon.manifest.id):\(cat.type):\(cat.id)",
                        titulo: "\(cat.tituloExibicao) · \(addon.manifest.name)",
                        tipo: tipoNorm,
                        itens: itens
                    ))
                }
            }
            var lista: [(Int, AddonDescobertaFila)] = []
            for await par in group {
                if let f = par.1 { lista.append((par.0, f)) }
            }
            return lista.sorted { $0.0 < $1.0 }.map(\.1)
        }

        catalogosFilas = coletados
    }

    func carregarTMDBSePreciso() async {
        guard !tmdbCarregado else { return }
        tmdbCarregado = true

        let especificacoes: [(id: String, titulo: String, tipo: String, path: String, serieFixa: Bool?)] = [
            ("trending-all", "Em alta agora", "all", "/trending/all/week", nil),
            ("movies-popular", "Filmes populares", "movie", "/movie/popular", false),
            ("series-popular", "Séries em alta", "series", "/tv/popular", true),
            ("movies-top", "Filmes mais bem avaliados", "movie", "/movie/top_rated", false),
            ("series-top", "Séries aclamadas", "series", "/tv/top_rated", true),
            ("movies-action", "Filmes de ação", "movie", "/discover/movie?with_genres=28&sort_by=popularity.desc", false),
            ("movies-scifi", "Ficção científica", "movie", "/discover/movie?with_genres=878&sort_by=popularity.desc", false),
            ("movies-comedy", "Comédia", "movie", "/discover/movie?with_genres=35&sort_by=popularity.desc", false),
            ("series-anim", "Animes e animação", "series", "/discover/tv?with_genres=16&sort_by=popularity.desc", true),
        ]

        let carregadas = await withTaskGroup(of: (Int, AddonDescobertaFila?).self) { group in
            for (idx, spec) in especificacoes.enumerated() {
                group.addTask {
                    let itens = await Self.buscarListaTMDB(path: spec.path, serieFixa: spec.serieFixa)
                    guard !itens.isEmpty else { return (idx, nil) }
                    return (idx, AddonDescobertaFila(id: "tmdb:\(spec.id)", titulo: spec.titulo, tipo: spec.tipo, itens: itens))
                }
            }
            var pares: [(Int, AddonDescobertaFila)] = []
            for await p in group {
                if let f = p.1 { pares.append((p.0, f)) }
            }
            return pares.sorted { $0.0 < $1.0 }.map(\.1)
        }

        filasTMDB = carregadas
        if carregadas.isEmpty { tmdbCarregado = false }
    }

    func buscar(termo: String) async -> (addons: [DescobertaItem], tmdb: [DescobertaItem]) {
        let limpo = termo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard limpo.count >= 2 else { return ([], []) }

        async let tmdbTask = Self.buscarSearchMultiTMDB(termo: limpo)
        async let addonsTask = Self.buscarNosCatalogosAddons(termo: limpo, ativos: AddonStore.shared.ativos)

        return await (addonsTask, tmdbTask)
    }

    /// Monta lista de `Episodio` para uma série via TMDB ou `/meta/` de addons quando não há M3U local.
    func episodiosDaSerie(tmdbId: Int?, imdbId: String?) async -> [Episodio] {
        if let tmdbId, tmdbId > 0 {
            let seasons = await Fichas.temporadasDaSerie(tmdbId: tmdbId)
            if !seasons.isEmpty {
                var out: [Episodio] = []
                for s in seasons {
                    for ep in 1...s.episodeCount {
                        out.append(Episodio(temporada: s.numero, numero: ep, versao: "leg", urls: []))
                    }
                }
                return out
            }
        }

        let resolved = await IdResolver.shared.resolver(tmdbId: tmdbId, imdbId: imdbId, serie: true)
        let ativos = AddonStore.shared.ativos
        if let sid = resolved.idParaStremio(prefixos: nil),
           let meta = await SaimoAddonCoordinator.shared.buscarMeta(addons: ativos, tipo: "series", id: sid),
           let videos = meta.videos {
            let eps = videos.compactMap { v -> Episodio? in
                guard let temp = v.season, temp > 0, v.numeroEpisodio > 0 else { return nil }
                return Episodio(temporada: temp, numero: v.numeroEpisodio, versao: "leg", urls: [])
            }.sorted { ($0.temporada, $0.numero) < ($1.temporada, $1.numero) }
            if !eps.isEmpty { return eps }
        }

        return []
    }

    private static func buscarNosCatalogosAddons(termo: String, ativos: [AddonInstalado]) async -> [DescobertaItem] {
        var pedidos: [(AddonInstalado, AddonCatalog)] = []
        for addon in ativos {
            for cat in addon.manifest.catalogs where cat.suportaBusca {
                pedidos.append((addon, cat))
            }
        }
        guard !pedidos.isEmpty else { return [] }

        return await withTaskGroup(of: [DescobertaItem].self) { group in
            for (addon, cat) in pedidos.prefix(10) {
                group.addTask {
                    let metas = await SaimoAddonCoordinator.shared.buscarCatalogo(
                        addon: addon,
                        catalogo: cat,
                        extra: [("search", termo)]
                    )
                    return metas.prefix(20).map { m in
                        let ehSerie = cat.type == "series" || m.type == "series"
                        return DescobertaItem(
                            id: "search:\(addon.manifest.id):\(m.id)",
                            tmdbId: m.tmdbIdNum,
                            imdbId: m.imdbIdPuro,
                            titulo: m.name,
                            ano: m.ano.map(String.init) ?? "",
                            serie: ehSerie,
                            capa: m.poster,
                            fundo: m.background ?? m.poster,
                            sinopse: m.description,
                            nota: m.imdbRating.flatMap(Double.init),
                            addonOrigemId: addon.manifest.id
                        )
                    }
                }
            }
            var vistos = Set<String>()
            var out: [DescobertaItem] = []
            for await lote in group {
                for item in lote {
                    let k = "\(item.serie):\(item.imdbId ?? item.titulo.lowercased())"
                    if vistos.insert(k).inserted { out.append(item) }
                }
            }
            return out
        }
    }

    private static func buscarListaTMDB(path: String, serieFixa: Bool?) async -> [DescobertaItem] {
        let sep = path.contains("?") ? "&" : "?"
        let urlStr = "\(IdResolver.tmdbBase)\(path)\(sep)api_key=\(IdResolver.tmdbChave)&language=pt-BR"
        guard let url = URL(string: urlStr) else { return [] }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return []
        }
        return parsearResultadosTMDB(results, serieFixa: serieFixa)
    }

    private static func buscarSearchMultiTMDB(termo: String) async -> [DescobertaItem] {
        guard let q = termo.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(IdResolver.tmdbBase)/search/multi?api_key=\(IdResolver.tmdbChave)&language=pt-BR&query=\(q)&include_adult=false") else {
            return []
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return []
        }
        return parsearResultadosTMDB(results, serieFixa: nil)
    }

    private static func parsearResultadosTMDB(_ results: [[String: Any]], serieFixa: Bool?) -> [DescobertaItem] {
        let img = "https://image.tmdb.org/t/p/"
        return results.compactMap { item -> DescobertaItem? in
            let mediaType = item["media_type"] as? String
            let serie: Bool
            if let s = serieFixa {
                serie = s
            } else if mediaType == "tv" {
                serie = true
            } else if mediaType == "movie" {
                serie = false
            } else {
                return nil
            }
            guard let id = item["id"] as? Int else { return nil }
            let titulo = (serie ? item["name"] as? String : item["title"] as? String)
                ?? (item["name"] as? String)
                ?? (item["title"] as? String)
                ?? ""
            guard !titulo.isEmpty else { return nil }
            let posterPath = item["poster_path"] as? String
            let backdropPath = item["backdrop_path"] as? String
            let dateStr = (serie ? item["first_air_date"] as? String : item["release_date"] as? String) ?? ""
            let ano = dateStr.count >= 4 ? String(dateStr.prefix(4)) : ""
            return DescobertaItem(
                id: "tmdb:\(serie ? "tv" : "movie"):\(id)",
                tmdbId: id,
                imdbId: nil,
                titulo: titulo,
                ano: ano,
                serie: serie,
                capa: posterPath.map { "\(img)w342\($0)" },
                fundo: backdropPath.map { "\(img)w1280\($0)" },
                sinopse: item["overview"] as? String,
                nota: item["vote_average"] as? Double,
                addonOrigemId: nil
            )
        }
    }
}

// MARK: - Fluxo de Reprodução por Addons + Seletor de Streams + Debrid

struct AddonPedidoReproducao: Identifiable, Equatable {
    let id = UUID()
    let titulo: String
    let ano: String
    let serie: Bool
    let tmdbId: Int?
    let imdbId: String?
    let temporada: Int?
    let episodio: Int?
    let poster: String?
    let fundo: String?
    let todosEpisodios: [Episodio]
}

@MainActor
final class AddonReproducaoEstado: ObservableObject {
    static let shared = AddonReproducaoEstado()

    @Published var pedido: AddonPedidoReproducao?
    @Published private(set) var carregando = false
    @Published private(set) var resultados: [AddonResultadoStream] = []
    @Published private(set) var resolvendoId: String?
    @Published var mensagemErro: String?
    @Published var precisaConfigurarDebrid = false

    private weak var playerModel: PlayerModel?
    private var resolvedIds: ResolvedMediaIds?

    private init() {}

    func abrirSeletor(
        model: PlayerModel,
        titulo: String,
        ano: String = "",
        serie: Bool,
        tmdbId: Int? = nil,
        imdbId: String? = nil,
        temporada: Int? = nil,
        episodio: Int? = nil,
        poster: String? = nil,
        fundo: String? = nil,
        todosEpisodios: [Episodio] = []
    ) {
        self.playerModel = model
        self.mensagemErro = nil
        self.precisaConfigurarDebrid = false
        self.resolvendoId = nil
        self.resultados = []
        self.pedido = AddonPedidoReproducao(
            titulo: titulo,
            ano: ano,
            serie: serie,
            tmdbId: tmdbId,
            imdbId: imdbId,
            temporada: temporada,
            episodio: episodio,
            poster: poster,
            fundo: fundo,
            todosEpisodios: todosEpisodios
        )
        Task { await carregarStreams() }
    }

    func fechar() {
        pedido = nil
        resultados = []
        resolvendoId = nil
        mensagemErro = nil
        precisaConfigurarDebrid = false
    }

    func carregarStreams() async {
        guard let p = pedido else { return }
        let addons = AddonStore.shared.ativos
        guard !addons.isEmpty else {
            mensagemErro = "Nenhum addon ativo. Adicione um addon Stremio em Ajustes → Addons e Debrid."
            return
        }

        carregando = true
        defer { carregando = false }

        let ids = await IdResolver.shared.resolver(
            tmdbId: p.tmdbId,
            imdbId: p.imdbId,
            titulo: p.titulo,
            ano: Int(p.ano),
            serie: p.serie
        )
        self.resolvedIds = ids

        let encontrados = await SaimoAddonCoordinator.shared.buscarStreams(
            addons: addons,
            ids: ids,
            temporada: p.temporada,
            episodio: p.episodio
        )
        self.resultados = encontrados
        if encontrados.isEmpty {
            self.mensagemErro = "Nenhum stream encontrado nos addons ativos para este título."
        }
    }

    func selecionar(_ item: AddonResultadoStream) {
        guard let p = pedido, let model = playerModel else { return }
        let stream = item.stream

        if let yt = stream.ytId, !yt.isEmpty,
           let url = URL(string: "https://www.youtube.com/watch?v=\(yt)") {
            NSWorkspace.shared.open(url)
            return
        }
        if stream.ehExternoOuYouTube, let ext = stream.externalUrl, let url = URL(string: ext) {
            NSWorkspace.shared.open(url)
            return
        }

        if stream.ehTorrent && !DebridStore.shared.temAlgumAtivo {
            precisaConfigurarDebrid = true
            mensagemErro = DebridErro.nenhumConfigurado.localizedDescription
            return
        }

        mensagemErro = nil
        precisaConfigurarDebrid = false
        resolvendoId = item.id

        let debridAtivos = DebridStore.shared.ativosOrdenados
        let ids = resolvedIds ?? ResolvedMediaIds(tmdbId: p.tmdbId, imdbId: p.imdbId, tipoStremio: p.serie ? "series" : "movie")

        Task { @MainActor in
            defer { if resolvendoId == item.id { resolvendoId = nil } }
            do {
                let urlPlay = try await DebridResolver.resolver(stream: stream, ativos: debridAtivos, nomeTitulo: p.titulo)
                iniciarPlayback(
                    url: urlPlay,
                    resultado: item,
                    pedido: p,
                    ids: ids,
                    model: model
                )
                fechar()
            } catch {
                self.mensagemErro = error.localizedDescription
                if case DebridErro.nenhumConfigurado = error {
                    self.precisaConfigurarDebrid = true
                }
            }
        }
    }

    private func iniciarPlayback(
        url: URL,
        resultado: AddonResultadoStream,
        pedido p: AddonPedidoReproducao,
        ids: ResolvedMediaIds,
        model: PlayerModel
    ) {
        let stream = resultado.stream
        let nomeSerie = p.ano.isEmpty || p.titulo.contains("(\(p.ano))") ? p.titulo : "\(p.titulo) (\(p.ano))"

        AddonHistorico.shared.registrar(
            titulo: nomeSerie,
            serie: p.serie,
            ano: p.ano,
            tmdbId: ids.tmdbId ?? p.tmdbId,
            imdbId: ids.imdbId ?? p.imdbId,
            poster: p.poster,
            fundo: p.fundo
        )

        let ehMkvOuRemux = stream.requerRemux || url.pathExtension.lowercased() == "mkv" || url.absoluteString.lowercased().contains(".mkv")
        let headers = stream.headersRequisicao
        let subs = stream.subtitles ?? []
        let binge = stream.bingeGroupEfetivo ?? ""

        let detalhe: String
        let detalheBase: String?
        let chaveProgresso: String

        if p.serie, let temp = p.temporada, let ep = p.episodio {
            let codigo = String(format: "T%02d · E%02d", temp, ep)
            detalhe = "\(codigo) · \(resultado.addonName)"
            detalheBase = codigo
            chaveProgresso = Progresso.chaveEpisodio(nomeSerie, temp, ep)
            model.episodioPendente = EpisodioNoAr(
                serie: nomeSerie,
                temporada: temp,
                numero: ep,
                versao: "leg",
                lista: p.todosEpisodios
            )
            model.proximoAddonHandler = { [weak model] proximoEp, grupoPreferido in
                guard let model else { return }
                await Self.reproduzirProximoEpisodio(
                    model: model,
                    titulo: p.titulo,
                    ano: p.ano,
                    ids: ids,
                    episodio: proximoEp,
                    todosEpisodios: p.todosEpisodios,
                    poster: p.poster,
                    fundo: p.fundo,
                    bingeGroupPreferido: grupoPreferido
                )
            }
        } else {
            detalhe = resultado.addonName
            detalheBase = nil
            chaveProgresso = Progresso.chaveFilme(nomeSerie)
            model.episodioPendente = nil
            model.proximoAddonHandler = nil
        }

        var todasUrls: [URL] = []
        var todosRotulos: [String] = []
        var todosHeaders: [[String: String]] = []
        var todosRemux: [Bool] = []
        var todosBinges: [String] = []
        var todasLegendas: [[StremioSubtitle]] = []
        var indiceInicial = 0

        for r in resultados {
            let itemUrl: URL?
            if r.id == resultado.id {
                itemUrl = url
            } else if let uStr = r.stream.url, let parsed = URL(string: uStr), !r.stream.ehTorrent {
                itemUrl = parsed
            } else {
                itemUrl = nil
            }
            guard let itemUrl else { continue }
            if r.id == resultado.id {
                indiceInicial = todasUrls.count
            }
            todasUrls.append(itemUrl)
            let rotulo = r.stream.rotuloFonte.isEmpty ? r.addonName : "\(r.addonName) · \(r.stream.rotuloFonte)"
            todosRotulos.append(rotulo)
            todosHeaders.append(r.stream.headersRequisicao)
            todosRemux.append(r.stream.requerRemux || itemUrl.pathExtension.lowercased() == "mkv" || itemUrl.absoluteString.lowercased().contains(".mkv"))
            todosBinges.append(r.stream.bingeGroupEfetivo ?? "")
            todasLegendas.append(r.stream.subtitles ?? [])
        }

        if todasUrls.isEmpty {
            todasUrls = [url]
            todosRotulos = [resultado.addonName]
            todosHeaders = [headers]
            todosRemux = [ehMkvOuRemux]
            todosBinges = [binge]
            todasLegendas = [subs]
            indiceInicial = 0
        }

        model.playFile(
            todasUrls,
            indiceInicial: indiceInicial,
            rotulos: todosRotulos,
            nome: p.serie ? nomeSerie : p.titulo,
            detalhe: detalhe,
            detalheBase: detalheBase,
            chave: chaveProgresso,
            headersPorFonte: todosHeaders,
            remuxPorFonte: todosRemux,
            bingeGroupsPorFonte: todosBinges,
            legendasPorFonte: todasLegendas,
            manterProximoAddon: p.serie
        )

        model.buscarLegendasExternas(
            tmdb: ids.tmdbId,
            imdbId: ids.imdbId,
            serie: p.serie,
            temporada: p.temporada ?? 0,
            episodio: p.episodio ?? 0,
            videoHash: stream.behaviorHints?.videoHash,
            videoSize: stream.behaviorHints?.videoSize,
            filename: stream.behaviorHints?.filename
        )
        VodEstado.shared.serieAberta = nil
        VodEstado.shared.secao = nil
    }

    static func reproduzirProximoEpisodio(
        model: PlayerModel,
        titulo: String,
        ano: String,
        ids: ResolvedMediaIds,
        episodio: Episodio,
        todosEpisodios: [Episodio],
        poster: String?,
        fundo: String?,
        bingeGroupPreferido: String?
    ) async {
        let addons = AddonStore.shared.ativos
        let candidatos = await SaimoAddonCoordinator.shared.buscarStreams(
            addons: addons,
            ids: ids,
            temporada: episodio.temporada,
            episodio: episodio.numero
        )
        let debridAtivos = DebridStore.shared.ativosOrdenados
        let ordenados = ordenarPorBingeGroup(candidatos, grupo: bingeGroupPreferido, temDebrid: !debridAtivos.isEmpty)

        for item in ordenados {
            if item.stream.ehExternoOuYouTube || item.stream.ytId != nil { continue }
            if item.stream.ehTorrent && debridAtivos.isEmpty { continue }
            if let url = try? await DebridResolver.resolver(stream: item.stream, ativos: debridAtivos, nomeTitulo: titulo) {
                let nomeSerie = ano.isEmpty || titulo.contains("(\(ano))") ? titulo : "\(titulo) (\(ano))"
                let codigo = String(format: "T%02d · E%02d", episodio.temporada, episodio.numero)
                let ehMkvOuRemux = item.stream.requerRemux || url.pathExtension.lowercased() == "mkv" || url.absoluteString.lowercased().contains(".mkv")

                model.episodioPendente = EpisodioNoAr(
                    serie: nomeSerie,
                    temporada: episodio.temporada,
                    numero: episodio.numero,
                    versao: "leg",
                    lista: todosEpisodios
                )
                model.playFile(
                    [url],
                    indiceInicial: 0,
                    rotulos: [item.addonName],
                    nome: nomeSerie,
                    detalhe: "\(codigo) · \(item.addonName)",
                    detalheBase: codigo,
                    chave: Progresso.chaveEpisodio(nomeSerie, episodio.temporada, episodio.numero),
                    headersPorFonte: [item.stream.headersRequisicao],
                    remuxPorFonte: [ehMkvOuRemux],
                    bingeGroupsPorFonte: [item.stream.bingeGroupEfetivo ?? ""],
                    legendasPorFonte: [item.stream.subtitles ?? []],
                    manterProximoAddon: true
                )
                model.buscarLegendasExternas(
                    tmdb: ids.tmdbId,
                    imdbId: ids.imdbId,
                    serie: true,
                    temporada: episodio.temporada,
                    episodio: episodio.numero,
                    videoHash: item.stream.behaviorHints?.videoHash,
                    videoSize: item.stream.behaviorHints?.videoSize,
                    filename: item.stream.behaviorHints?.filename
                )
                return
            }
        }
    }

    static func ordenarPorBingeGroup(
        _ itens: [AddonResultadoStream],
        grupo: String?,
        temDebrid: Bool
    ) -> [AddonResultadoStream] {
        itens.sorted { a, b in
            let scoreA = pontuacao(a, grupo: grupo, temDebrid: temDebrid)
            let scoreB = pontuacao(b, grupo: grupo, temDebrid: temDebrid)
            return scoreA > scoreB
        }
    }

    private static func pontuacao(_ item: AddonResultadoStream, grupo: String?, temDebrid: Bool) -> Int {
        var p = 0
        if let grupo, !grupo.isEmpty, item.stream.bingeGroupEfetivo == grupo {
            p += 1000
        }
        if !item.stream.ehTorrent { p += 200 }
        else if temDebrid { p += 150 }
        if !item.stream.ehMKV { p += 20 }
        return p
    }
}

// MARK: - Sheet/Overlay visual de escolha de stream Stremio

struct FolhaStreamsAddon: View {
    @ObservedObject private var estado = AddonReproducaoEstado.shared
    @ObservedObject private var debrid = DebridStore.shared

    var body: some View {
        if let pedido = estado.pedido {
            ZStack {
                Color.black.opacity(0.68)
                    .ignoresSafeArea()
                    .onTapGesture { estado.fechar() }

                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(pedido.titulo)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.white)
                            if let t = pedido.temporada, let e = pedido.episodio {
                                Text(String(format: "Temporada %d · Episódio %d — Escolha uma fonte dos addons", t, e))
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.65))
                            } else {
                                Text("Escolha uma fonte dos seus addons Stremio")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.65))
                            }
                        }
                        Spacer()
                        Button {
                            estado.fechar()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.8))
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(0.1), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    if let erro = estado.mensagemErro {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: estado.precisaConfigurarDebrid ? "key.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(estado.precisaConfigurarDebrid ? Tema.acento : .orange)
                                Text(erro)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if estado.precisaConfigurarDebrid {
                                Button("Abrir Ajustes → Addons e Debrid") {
                                    estado.fechar()
                                    VodEstado.shared.mostrarAddons = true
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Tema.acento)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }

                    if estado.carregando {
                        HStack(spacing: 12) {
                            ProgressView().controlSize(.small)
                            Text("Consultando addons instalados…")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        .frame(maxWidth: .infinity, minHeight: 160)
                    } else if estado.resultados.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "puzzlepiece.extension")
                                .font(.system(size: 28))
                                .foregroundStyle(.white.opacity(0.35))
                            Text("Nenhuma fonte retornada.")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        .frame(maxWidth: .infinity, minHeight: 160)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(estado.resultados) { item in
                                    linhaStream(item)
                                }
                            }
                        }
                        .frame(maxHeight: 380)
                    }
                }
                .padding(22)
                .frame(width: 620)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(red: 0.11, green: 0.12, blue: 0.14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(.white.opacity(0.12), lineWidth: 1)
                        )
                )
                .shadow(color: .black.opacity(0.6), radius: 36, y: 16)
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private func linhaStream(_ item: AddonResultadoStream) -> some View {
        let s = item.stream
        let resolvendo = estado.resolvendoId == item.id
        Button {
            estado.selecionar(item)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        etiqueta(item.addonName, destaque: true)
                        if s.ehTorrent {
                            etiqueta(debrid.temAlgumAtivo ? "Torrent → Debrid" : "P2P (requer Debrid)",
                                     aviso: !debrid.temAlgumAtivo)
                        }
                        if s.ehMKV || s.requerRemux {
                            etiqueta("MKV Remux")
                        } else if !s.extensaoProvavel.isEmpty {
                            etiqueta(s.extensaoProvavel.uppercased())
                        }
                        if let bytes = s.behaviorHints?.videoSize, bytes > 0 {
                            etiqueta(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                        }
                        if let subs = s.subtitles, !subs.isEmpty {
                            etiqueta("\(subs.count) leg.")
                        }
                    }

                    let rotulo: String = s.rotuloFonte
                    Text(rotulo)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)

                    if s.tituloExibicao != s.rotuloFonte {
                        Text(s.tituloExibicao)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                    }
                }
                Spacer(minLength: 10)
                if resolvendo {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 30, height: 30)
                        .background(Tema.acento.opacity(0.85), in: Circle())
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.09), lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(estado.resolvendoId != nil)
    }

    private func etiqueta(_ texto: String, destaque: Bool = false, aviso: Bool = false) -> some View {
        Text(texto)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(aviso ? Color.orange : .white)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(
                (destaque ? Tema.acento.opacity(0.28)
                 : aviso ? Color.orange.opacity(0.18)
                 : Color.white.opacity(0.12)),
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
    }
}
