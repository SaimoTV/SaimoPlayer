import Foundation
import Combine

// MARK: - Erros

enum AddonErro: LocalizedError, Sendable, Equatable {
    case urlInvalida(String)
    case nuvioPluginNaoSuportado
    case manifestoInvalido(String)
    case httpErro(Int, String)
    case rede(String)

    var errorDescription: String? {
        switch self {
        case .urlInvalida(let msg):
            return msg
        case .nuvioPluginNaoSuportado:
            return "Este link é um plugin JS do Nuvio (formato 'scrapers'), não um addon HTTP padrão do Stremio (/manifest.json). O Saimo suporta apenas addons HTTP Stremio."
        case .manifestoInvalido(let msg):
            return "Manifesto Stremio inválido: \(msg)"
        case .httpErro(let code, let host):
            return "O addon \(host) respondeu com erro HTTP \(code)."
        case .rede(let msg):
            return msg
        }
    }
}

// MARK: - Transporte e normalização de URL (protocolo HTTP Stremio)

struct AddonTransport: Codable, Hashable, Sendable {
    /// Base URL sem `/manifest.json` e sem barra final nem query (ex.: `https://torrentio.strem.fun/sort=quality`).
    let baseUrl: String
    /// Query string preservada sem o `?` inicial (ex.: `token=abc`), quando presente no link de configuração.
    let query: String?

    var manifestUrl: URL? {
        construirURL(caminho: "/manifest.json")
    }

    /// Normaliza URLs Stremio (`stremio://`, espaços, trailing `/manifest.json`, `/` final, preservando `?query` e path config).
    static func normalizar(_ raw: String) throws -> AddonTransport {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AddonErro.urlInvalida("Informe a URL do manifesto Stremio (ex.: https://.../manifest.json).")
        }

        let esquemaCorrigido: String
        if trimmed.lowercased().hasPrefix("stremio://") {
            esquemaCorrigido = "https://" + String(trimmed.dropFirst("stremio://".count))
        } else if !trimmed.contains("://"), trimmed.contains(".") {
            esquemaCorrigido = "https://" + trimmed
        } else {
            esquemaCorrigido = trimmed
        }

        guard let components = URLComponents(string: esquemaCorrigido),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty else {
            throw AddonErro.urlInvalida("URL inválida. Use um endereço HTTP, HTTPS ou stremio:// válido.")
        }

        var path = components.percentEncodedPath
        if path.lowercased().hasSuffix("/manifest.json") {
            path = String(path.dropLast("/manifest.json".count))
        }
        while path.hasSuffix("/") {
            path.removeLast()
        }

        var baseComponents = URLComponents()
        baseComponents.scheme = scheme
        baseComponents.user = components.user
        baseComponents.password = components.password
        baseComponents.host = host
        baseComponents.port = components.port
        baseComponents.percentEncodedPath = path

        guard let baseString = baseComponents.string else {
            throw AddonErro.urlInvalida("Não foi possível normalizar o endereço do addon.")
        }

        let query = (components.percentEncodedQuery?.isEmpty == false) ? components.percentEncodedQuery : nil
        return AddonTransport(baseUrl: baseString, query: query)
    }

    func catalogUrl(type: String, id: String, extra: [(String, String)] = []) -> URL? {
        var segmentos = ["catalog", Self.codificarSegmento(type), Self.codificarSegmento(id)]
        if !extra.isEmpty {
            let extraCodificado = extra
                .filter { !$0.0.isEmpty && !$0.1.isEmpty }
                .map { "\(Self.codificarValorExtra($0.0))=\(Self.codificarValorExtra($0.1))" }
                .joined(separator: "&")
            if !extraCodificado.isEmpty {
                segmentos.append(extraCodificado)
            }
        }
        let caminho = "/" + segmentos.joined(separator: "/") + ".json"
        return construirURL(caminho: caminho)
    }

    func metaUrl(type: String, id: String) -> URL? {
        let caminho = "/meta/\(Self.codificarSegmento(type))/\(Self.codificarSegmento(id)).json"
        return construirURL(caminho: caminho)
    }

    func streamUrl(type: String, id: String) -> URL? {
        let caminho = "/stream/\(Self.codificarSegmento(type))/\(Self.codificarSegmento(id)).json"
        return construirURL(caminho: caminho)
    }

    func subtitlesUrl(type: String, id: String, extra: [(String, String)] = []) -> URL? {
        var segmentos = ["subtitles", Self.codificarSegmento(type), Self.codificarSegmento(id)]
        if !extra.isEmpty {
            let extraCodificado = extra
                .filter { !$0.0.isEmpty && !$0.1.isEmpty }
                .map { "\(Self.codificarValorExtra($0.0))=\(Self.codificarValorExtra($0.1))" }
                .joined(separator: "&")
            if !extraCodificado.isEmpty {
                segmentos.append(extraCodificado)
            }
        }
        let caminho = "/" + segmentos.joined(separator: "/") + ".json"
        return construirURL(caminho: caminho)
    }

    /// URL de configuração web (quando `behaviorHints.configurable == true`).
    var configureUrl: URL? {
        construirURL(caminho: "/configure")
    }

    private func construirURL(caminho: String) -> URL? {
        guard var base = URLComponents(string: baseUrl) else { return nil }
        let prefixo = base.percentEncodedPath
        let combinado = prefixo + caminho
        base.percentEncodedPath = combinado.hasPrefix("/") ? combinado : "/" + combinado
        base.percentEncodedQuery = query
        return base.url
    }

    private static let segmentoPermitido: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "/?#")
        return set
    }()

    private static let extraValorPermitido: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "/?#=&+")
        return set
    }()

    static func codificarSegmento(_ valor: String) -> String {
        valor.addingPercentEncoding(withAllowedCharacters: segmentoPermitido) ?? valor
    }

    static func codificarValorExtra(_ valor: String) -> String {
        valor.addingPercentEncoding(withAllowedCharacters: extraValorPermitido) ?? valor
    }
}

// MARK: - Manifesto Stremio

struct AddonResource: Codable, Hashable, Sendable {
    let name: String
    let types: [String]?
    let idPrefixes: [String]?

    init(name: String, types: [String]? = nil, idPrefixes: [String]? = nil) {
        self.name = name
        self.types = types
        self.idPrefixes = idPrefixes
    }

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let raw = try? single.decode(String.self) {
            self.name = raw
            self.types = nil
            self.idPrefixes = nil
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.types = try container.decodeIfPresent([String].self, forKey: .types)
        self.idPrefixes = try container.decodeIfPresent([String].self, forKey: .idPrefixes)
    }

    func encode(to encoder: Encoder) throws {
        if types == nil && idPrefixes == nil {
            var single = encoder.singleValueContainer()
            try single.encode(name)
        } else {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encodeIfPresent(types, forKey: .types)
            try container.encodeIfPresent(idPrefixes, forKey: .idPrefixes)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case name, types, idPrefixes
    }
}

struct AddonCatalogExtra: Codable, Hashable, Sendable {
    let name: String
    let isRequired: Bool?
    let options: [String]?
    let optionsLimit: Int?
}

struct AddonCatalog: Codable, Hashable, Sendable, Identifiable {
    var uid: String { "\(type)::\(id)" }
    let type: String
    let id: String
    let name: String?
    let extra: [AddonCatalogExtra]?
    let extraSupported: [String]?
    let extraRequired: [String]?

    var tituloExibicao: String {
        let n = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? id : n
    }

    var suportaBusca: Bool {
        if extra?.contains(where: { $0.name == "search" }) == true { return true }
        return extraSupported?.contains("search") == true
    }

    var requerBusca: Bool {
        if extra?.contains(where: { $0.name == "search" && $0.isRequired == true }) == true { return true }
        return extraRequired?.contains("search") == true
    }

    var opcoesGenero: [String] {
        extra?.first(where: { $0.name == "genre" })?.options ?? []
    }
}

struct ManifestBehaviorHints: Codable, Hashable, Sendable {
    let configurable: Bool?
    let configurationRequired: Bool?
    let adult: Bool?
    let p2p: Bool?
}

struct AddonManifest: Codable, Hashable, Sendable {
    let id: String
    let name: String
    let version: String
    let description: String?
    let logo: String?
    let background: String?
    let types: [String]
    let idPrefixes: [String]?
    let resources: [AddonResource]
    let catalogs: [AddonCatalog]
    let behaviorHints: ManifestBehaviorHints?

    init(
        id: String,
        name: String,
        version: String,
        description: String? = nil,
        logo: String? = nil,
        background: String? = nil,
        types: [String] = [],
        idPrefixes: [String]? = nil,
        resources: [AddonResource] = [],
        catalogs: [AddonCatalog] = [],
        behaviorHints: ManifestBehaviorHints? = nil
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.logo = logo
        self.background = background
        self.types = types
        self.idPrefixes = idPrefixes
        self.resources = resources
        self.catalogs = catalogs
        self.behaviorHints = behaviorHints
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, version, description, logo, background, types, idPrefixes, resources, catalogs, behaviorHints
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.version = (try? c.decode(String.self, forKey: .version)) ?? "1.0.0"
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        self.logo = try c.decodeIfPresent(String.self, forKey: .logo)
        self.background = try c.decodeIfPresent(String.self, forKey: .background)
        self.types = (try? c.decode([String].self, forKey: .types)) ?? []
        self.idPrefixes = try c.decodeIfPresent([String].self, forKey: .idPrefixes)
        self.resources = (try? c.decode([AddonResource].self, forKey: .resources)) ?? []
        self.catalogs = (try? c.decode([AddonCatalog].self, forKey: .catalogs)) ?? []
        self.behaviorHints = try c.decodeIfPresent(ManifestBehaviorHints.self, forKey: .behaviorHints)
    }

    /// Decodifica dados JSON verificando primeiro se trata de um plugin JS do Nuvio (`scrapers` sem `resources`).
    static func decodificar(de data: Data) throws -> AddonManifest {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AddonErro.manifestoInvalido("O conteúdo retornado não é um JSON válido.")
        }

        if obj["scrapers"] != nil && obj["resources"] == nil {
            let name = (obj["name"] as? String) ?? "Nuvio Plugin"
            let version = (obj["version"] as? String) ?? "1.0.0"
            let id = (obj["id"] as? String) ?? ("nuvio." + name.lowercased().replacingOccurrences(of: " ", with: "-"))
            let scrapersCount = (obj["scrapers"] as? [[String: Any]])?.count ?? 0
            let desc = (obj["description"] as? String) ?? "Repositório Nuvio (\(scrapersCount) scrapers)"
            return AddonManifest(
                id: id,
                name: name,
                version: version,
                description: desc,
                types: ["movie", "series"],
                idPrefixes: ["tt", "tmdb:"],
                resources: [AddonResource(name: "stream", types: ["movie", "series"], idPrefixes: ["tt", "tmdb:"])],
                catalogs: []
            )
        }

        do {
            let manifest = try JSONDecoder().decode(AddonManifest.self, from: data)
            guard !manifest.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AddonErro.manifestoInvalido("Campos 'id' ou 'name' ausentes.")
            }
            return manifest
        } catch let e as AddonErro {
            throw e
        } catch {
            throw AddonErro.manifestoInvalido("Estrutura incompatível com o protocolo Stremio.")
        }
    }

    /// Verifica se o manifesto aceita `(recurso, tipo, id)` respeitando `idPrefixes` por recurso e global.
    func suporta(recurso: String, tipo: String, id: String? = nil) -> Bool {
        guard let res = resources.first(where: { $0.name == recurso }) else {
            return false
        }
        let tiposPermitidos = res.types ?? types
        if !tiposPermitidos.isEmpty && !tiposPermitidos.contains(tipo) {
            return false
        }
        if let id {
            let prefixos = res.idPrefixes ?? idPrefixes
            if let prefixos, !prefixos.isEmpty {
                return prefixos.contains { id.hasPrefix($0) }
            }
        }
        return true
    }

    /// Prefixos efetivos esperados para um determinado recurso.
    func prefixosEfetivos(para recurso: String) -> [String]? {
        guard let res = resources.first(where: { $0.name == recurso }) else {
            return idPrefixes
        }
        return res.idPrefixes ?? idPrefixes
    }
}

// MARK: - Modelos de Catálogo, Meta, Stream e Legenda

struct StremioSubtitle: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let url: String
    let lang: String

    private enum CodingKeys: String, CodingKey {
        case id, url, lang
    }

    init(id: String, url: String, lang: String) {
        self.id = id
        self.url = url
        self.lang = lang
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.url = try c.decode(String.self, forKey: .url)
        self.lang = (try? c.decode(String.self, forKey: .lang)) ?? "und"
        if let decodedId = try? c.decode(String.self, forKey: .id), !decodedId.isEmpty {
            self.id = decodedId
        } else {
            self.id = "\(self.lang)::\(self.url)"
        }
    }
}

struct StreamProxyHeaders: Codable, Hashable, Sendable {
    let request: [String: String]?
    let response: [String: String]?
}

struct StreamBehaviorHints: Codable, Hashable, Sendable {
    let notWebReady: Bool?
    let bingeGroup: String?
    let filename: String?
    let videoSize: Int64?
    let videoHash: String?
    let proxyHeaders: StreamProxyHeaders?
    let countryWhitelist: [String]?
    let group: String?

    private enum CodingKeys: String, CodingKey {
        case notWebReady, bingeGroup, filename, videoSize, videoHash, proxyHeaders, countryWhitelist, group
    }

    init(
        notWebReady: Bool? = nil,
        bingeGroup: String? = nil,
        filename: String? = nil,
        videoSize: Int64? = nil,
        videoHash: String? = nil,
        proxyHeaders: StreamProxyHeaders? = nil,
        countryWhitelist: [String]? = nil,
        group: String? = nil
    ) {
        self.notWebReady = notWebReady
        self.bingeGroup = bingeGroup
        self.filename = filename
        self.videoSize = videoSize
        self.videoHash = videoHash
        self.proxyHeaders = proxyHeaders
        self.countryWhitelist = countryWhitelist
        self.group = group
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.notWebReady = try c.decodeIfPresent(Bool.self, forKey: .notWebReady)
        self.bingeGroup = try c.decodeIfPresent(String.self, forKey: .bingeGroup)
        self.filename = try c.decodeIfPresent(String.self, forKey: .filename)
        self.videoHash = try c.decodeIfPresent(String.self, forKey: .videoHash)
        self.proxyHeaders = try c.decodeIfPresent(StreamProxyHeaders.self, forKey: .proxyHeaders)
        self.countryWhitelist = try c.decodeIfPresent([String].self, forKey: .countryWhitelist)
        self.group = try c.decodeIfPresent(String.self, forKey: .group)

        if let intVal = try? c.decodeIfPresent(Int64.self, forKey: .videoSize) {
            self.videoSize = intVal
        } else if let doubleVal = try? c.decodeIfPresent(Double.self, forKey: .videoSize) {
            self.videoSize = Int64(doubleVal)
        } else if let strVal = try? c.decodeIfPresent(String.self, forKey: .videoSize), let parsed = Int64(strVal) {
            self.videoSize = parsed
        } else {
            self.videoSize = nil
        }
    }
}

struct StremioStream: Codable, Hashable, Sendable, Identifiable {
    var id: String {
        [
            url ?? "",
            infoHash ?? "",
            fileIdx.map(String.init) ?? "",
            ytId ?? "",
            externalUrl ?? "",
            name ?? "",
            title ?? description ?? "",
        ].joined(separator: "|")
    }

    let name: String?
    let title: String?
    let description: String?
    let url: String?
    let infoHash: String?
    let fileIdx: Int?
    let sources: [String]?
    let ytId: String?
    let externalUrl: String?
    let subtitles: [StremioSubtitle]?
    let behaviorHints: StreamBehaviorHints?

    private enum CodingKeys: String, CodingKey {
        case name, title, description, url, infoHash, fileIdx, sources, ytId, externalUrl, subtitles, behaviorHints
    }

    init(
        name: String? = nil,
        title: String? = nil,
        description: String? = nil,
        url: String? = nil,
        infoHash: String? = nil,
        fileIdx: Int? = nil,
        sources: [String]? = nil,
        ytId: String? = nil,
        externalUrl: String? = nil,
        subtitles: [StremioSubtitle]? = nil,
        behaviorHints: StreamBehaviorHints? = nil
    ) {
        self.name = name
        self.title = title
        self.description = description
        self.url = url
        self.infoHash = infoHash
        self.fileIdx = fileIdx
        self.sources = sources
        self.ytId = ytId
        self.externalUrl = externalUrl
        self.subtitles = subtitles
        self.behaviorHints = behaviorHints
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try c.decodeIfPresent(String.self, forKey: .name)
        self.title = try c.decodeIfPresent(String.self, forKey: .title)
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        self.url = try c.decodeIfPresent(String.self, forKey: .url)
        self.infoHash = try c.decodeIfPresent(String.self, forKey: .infoHash)
        self.sources = try c.decodeIfPresent([String].self, forKey: .sources)
        self.ytId = try c.decodeIfPresent(String.self, forKey: .ytId)
        self.externalUrl = try c.decodeIfPresent(String.self, forKey: .externalUrl)
        self.subtitles = try c.decodeIfPresent([StremioSubtitle].self, forKey: .subtitles)
        self.behaviorHints = try c.decodeIfPresent(StreamBehaviorHints.self, forKey: .behaviorHints)

        if let idx = try? c.decodeIfPresent(Int.self, forKey: .fileIdx) {
            self.fileIdx = idx
        } else if let str = try? c.decodeIfPresent(String.self, forKey: .fileIdx), let parsed = Int(str) {
            self.fileIdx = parsed
        } else {
            self.fileIdx = nil
        }
    }

    var headersRequisicao: [String: String] {
        behaviorHints?.proxyHeaders?.request ?? [:]
    }

    var ehTorrent: Bool {
        (url == nil || url?.isEmpty == true) && !(infoHash ?? "").isEmpty
    }

    var ehExternoOuYouTube: Bool {
        url == nil && (infoHash ?? "").isEmpty && (ytId != nil || externalUrl != nil)
    }

    var extensaoProvavel: String {
        if let u = url, let parsed = URL(string: u) {
            let ext = parsed.pathExtension.lowercased()
            if !ext.isEmpty { return ext }
            let low = u.lowercased()
            if low.contains(".mkv") { return "mkv" }
            if low.contains(".m3u8") { return "m3u8" }
            if low.contains(".mpd") { return "mpd" }
            if low.contains(".mp4") { return "mp4" }
        }
        if let f = behaviorHints?.filename {
            return (f as NSString).pathExtension.lowercased()
        }
        return ""
    }

    var ehMKV: Bool {
        extensaoProvavel == "mkv"
    }

    var requerRemux: Bool {
        let ext = extensaoProvavel
        return ["mkv", "avi", "webm", "flv", "wmv", "ts", "m2t", "mpd"].contains(ext)
    }

    var bingeGroupEfetivo: String? {
        behaviorHints?.bingeGroup ?? behaviorHints?.group
    }

    var tituloExibicao: String {
        let bruto = description ?? title ?? behaviorHints?.filename ?? name ?? "Stream"
        return bruto.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var rotuloFonte: String {
        let n = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "Stream" : n
    }
}

struct AddonResultadoStream: Identifiable, Hashable, Sendable {
    var id: String { "\(addonId)::\(stream.id)" }
    let addonId: String
    let addonName: String
    let stream: StremioStream
}

struct CatalogoItem: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let type: String
    let name: String
    let poster: String?
    let background: String?
    let description: String?
    let releaseInfo: String?
    let imdbRating: String?
    let genres: [String]?

    var ano: Int? {
        guard let releaseInfo else { return nil }
        let digitos = releaseInfo.prefix(4)
        return Int(digitos)
    }

    var tmdbIdNum: Int? {
        if id.hasPrefix("tmdb:") {
            return Int(id.dropFirst("tmdb:".count).split(separator: ":").first ?? "")
        }
        return nil
    }

    var imdbIdPuro: String? {
        if id.hasPrefix("tt") {
            return String(id.split(separator: ":").first ?? "")
        }
        return nil
    }
}

struct MetaVideo: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let title: String?
    let season: Int?
    let episode: Int?
    let number: Int?
    let released: String?
    let overview: String?
    let thumbnail: String?

    var numeroEpisodio: Int { episode ?? number ?? 0 }
}

struct MetaDetalhe: Codable, Hashable, Sendable {
    let id: String
    let type: String
    let name: String
    let poster: String?
    let background: String?
    let description: String?
    let releaseInfo: String?
    let imdbRating: String?
    let runtime: String?
    let genres: [String]?
    let director: [String]?
    let cast: [String]?
    let videos: [MetaVideo]?
}

private struct StremioStreamsEnvelope: Decodable {
    let streams: [StremioStream]?
}

private struct StremioCatalogEnvelope: Decodable {
    let metas: [CatalogoItem]?
}

private struct StremioMetaEnvelope: Decodable {
    let meta: MetaDetalhe?
}

private struct StremioSubtitlesEnvelope: Decodable {
    let subtitles: [StremioSubtitle]?
}

// MARK: - Addon instalado e armazenamento (`saimo_addons_v1`)

struct AddonInstalado: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let transport: AddonTransport
    var enabled: Bool
    var order: Int
    var manifest: AddonManifest

    var nomeExibicao: String { manifest.name }
    var manifestUrlString: String { transport.manifestUrl?.absoluteString ?? transport.baseUrl }
}

@MainActor
final class AddonStore: ObservableObject {
    static let shared = AddonStore()
    static let defaultsKey = "saimo_addons_v1"
    static let mudou = Notification.Name("SaimoAddonsMudou")

    @Published private(set) var addons: [AddonInstalado] = []

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        carregar()
    }

    var temAtivos: Bool {
        addons.contains { $0.enabled }
    }

    var ativos: [AddonInstalado] {
        addons.filter { $0.enabled }.sorted { $0.order < $1.order }
    }

    func catalogoPorId() -> [AddonInstalado] {
        addons.sorted { $0.order < $1.order }
    }

    /// Baixa e valida um manifesto Stremio sem persistir. Rejeita plugins JS do Nuvio.
    func validarManifest(url raw: String) async throws -> (transport: AddonTransport, manifest: AddonManifest) {
        let transport = try AddonTransport.normalizar(raw)
        guard let manifestURL = transport.manifestUrl else {
            throw AddonErro.urlInvalida("Não foi possível gerar a URL do manifesto.")
        }

        let data = try await buscarDadosHTTP(manifestURL)
        let manifest = try AddonManifest.decodificar(de: data)
        return (transport, manifest)
    }

    /// Instala (ou atualiza mantendo posição/estado) um addon Stremio a partir da URL informada.
    @discardableResult
    func instalar(url raw: String) async throws -> AddonInstalado {
        let (transport, manifest) = try await validarManifest(url: raw)
        return upsert(transport: transport, manifest: manifest)
    }

    @discardableResult
    func upsert(transport: AddonTransport, manifest: AddonManifest, enabled: Bool = true) -> AddonInstalado {
        if let idx = addons.firstIndex(where: { $0.transport.baseUrl == transport.baseUrl && $0.transport.query == transport.query }) {
            addons[idx].manifest = manifest
            addons[idx].enabled = enabled
            salvar()
            return addons[idx]
        }

        let proximo = (addons.map(\.order).max() ?? -1) + 1
        let novo = AddonInstalado(
            id: UUID(),
            transport: transport,
            enabled: enabled,
            order: proximo,
            manifest: manifest
        )
        addons.append(novo)
        normalizarOrdem()
        salvar()
        return novo
    }

    func alternar(id: UUID) {
        guard let idx = addons.firstIndex(where: { $0.id == id }) else { return }
        addons[idx].enabled.toggle()
        salvar()
    }

    func definirAtivo(id: UUID, ativo: Bool) {
        guard let idx = addons.firstIndex(where: { $0.id == id }) else { return }
        addons[idx].enabled = ativo
        salvar()
    }

    func remover(id: UUID) {
        addons.removeAll { $0.id == id }
        normalizarOrdem()
        salvar()
    }

    func mover(id: UUID, deslocamento: Int) {
        var ordenado = addons.sorted { $0.order < $1.order }
        guard let idx = ordenado.firstIndex(where: { $0.id == id }) else { return }
        let destino = max(0, min(ordenado.count - 1, idx + deslocamento))
        guard destino != idx else { return }
        let item = ordenado.remove(at: idx)
        ordenado.insert(item, at: destino)
        for i in ordenado.indices {
            ordenado[i].order = i
        }
        addons = ordenado
        salvar()
    }

    func recarregar(id: UUID) async throws {
        guard let atual = addons.first(where: { $0.id == id }) else { return }
        guard let manifestURL = atual.transport.manifestUrl else { return }
        let data = try await buscarDadosHTTP(manifestURL)
        let manifest = try AddonManifest.decodificar(de: data)
        _ = upsert(transport: atual.transport, manifest: manifest, enabled: atual.enabled)
    }

    func limparTudo() {
        addons = []
        salvar()
    }

    // MARK: - Saimo Connect / API remota

    func paraConnect() -> [[String: Any]] {
        addons.sorted { $0.order < $1.order }.map { item in
            let manifestData = (try? JSONEncoder().encode(item.manifest)) ?? Data()
            let manifestJson = (try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any]) ?? [:]
            var dict: [String: Any] = [
                "id": item.id.uuidString,
                "baseUrl": item.transport.baseUrl,
                "enabled": item.enabled,
                "order": item.order,
                "manifest": manifestJson,
            ]
            if let q = item.transport.query {
                dict["query"] = q
            }
            return dict
        }
    }

    /// Aplica lista recebida do Connect sem apagar dados quando o pacote vier incompleto.
    func aplicarConnect(_ lista: [[String: Any]]) {
        var novos: [AddonInstalado] = []
        for (indice, item) in lista.enumerated() {
            guard let baseUrl = item["baseUrl"] as? String, !baseUrl.isEmpty else { continue }
            let query = item["query"] as? String
            let transport = AddonTransport(baseUrl: baseUrl, query: query)
            let enabled = item["enabled"] as? Bool ?? true
            let order = item["order"] as? Int ?? indice

            var manifest: AddonManifest?
            if let manifestObj = item["manifest"] as? [String: Any],
               let data = try? JSONSerialization.data(withJSONObject: manifestObj) {
                manifest = try? AddonManifest.decodificar(de: data)
            }
            let manifestFinal = manifest ?? AddonManifest(
                id: baseUrl,
                name: URL(string: baseUrl)?.host ?? "Addon",
                version: "1.0.0",
                types: ["movie", "series"],
                resources: [AddonResource(name: "stream")]
            )

            let uid = (item["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
            novos.append(AddonInstalado(id: uid, transport: transport, enabled: enabled, order: order, manifest: manifestFinal))
        }
        addons = novos.sorted { $0.order < $1.order }
        normalizarOrdem()
        salvar()
    }

    private func normalizarOrdem() {
        addons.sort { $0.order < $1.order }
        for i in addons.indices {
            addons[i].order = i
        }
    }

    private func carregar() {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let decodificado = try? JSONDecoder().decode([AddonInstalado].self, from: data) else {
            addons = []
            return
        }
        addons = decodificado.sorted { $0.order < $1.order }
    }

    private func salvar() {
        if let data = try? JSONEncoder().encode(addons) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
        NotificationCenter.default.post(name: Self.mudou, object: nil)
    }
}

// MARK: - Ponte TMDB <-> IMDb (`IdResolver`)

struct ResolvedMediaIds: Hashable, Sendable {
    let tmdbId: Int?
    let imdbId: String?
    /// `"movie"` ou `"series"` (padrão Stremio).
    let tipoStremio: String

    /// Escolhe o ID adequado ao addon considerando `idPrefixes` do recurso e/ou do manifesto.
    func idParaStremio(prefixos: [String]?, temporada: Int? = nil, episodio: Int? = nil) -> String? {
        let sufixoEpisodio: String = {
            guard tipoStremio == "series", let t = temporada, let e = episodio, t > 0, e > 0 else { return "" }
            return ":\(t):\(e)"
        }()

        let candidatoImdb = imdbId.map { "\($0)\(sufixoEpisodio)" }
        let candidatoTmdb = tmdbId.map { "tmdb:\($0)\(sufixoEpisodio)" }

        if let prefixos, !prefixos.isEmpty {
            for p in prefixos {
                if p == "tt", let c = candidatoImdb { return c }
                if p.hasPrefix("tmdb"), let c = candidatoTmdb { return c }
            }
            if let c = candidatoImdb, prefixos.contains(where: { c.hasPrefix($0) }) { return c }
            if let c = candidatoTmdb, prefixos.contains(where: { c.hasPrefix($0) }) { return c }
            return nil
        }

        return candidatoImdb ?? candidatoTmdb
    }
}

final class IdResolver: @unchecked Sendable {
    static let shared = IdResolver()

    static let tmdbChave = "15d2ea6d0dc1d476efbca3eba2b9bbfb"
    static let tmdbBase = "https://api.themoviedb.org/3"
    private static let defaultsKey = "saimo_idmap_v1"

    private struct CachePersistida: Codable {
        var tmdbParaImdb: [String: String] = [:]
        var imdbParaTmdb: [String: Int] = [:]
    }

    private let lock = NSLock()
    private let defaults: UserDefaults
    private var tmdbParaImdb: [String: String] = [:]
    private var imdbParaTmdb: [String: Int] = [:]
    private var tituloParaTmdb: [String: Int] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let salvo = try? JSONDecoder().decode(CachePersistida.self, from: data) {
            self.tmdbParaImdb = salvo.tmdbParaImdb
            self.imdbParaTmdb = salvo.imdbParaTmdb
        }
    }

    func registrar(tmdbId: Int, imdbId: String, serie: Bool) {
        let limpo = imdbId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard tmdbId > 0, limpo.hasPrefix("tt") else { return }
        let chave = "\(serie ? "tv" : "movie"):\(tmdbId)"
        lock.lock()
        tmdbParaImdb[chave] = limpo
        imdbParaTmdb[limpo] = tmdbId
        if tmdbParaImdb.count > 1500 {
            for k in tmdbParaImdb.keys.prefix(300) { tmdbParaImdb.removeValue(forKey: k) }
        }
        if imdbParaTmdb.count > 1500 {
            for k in imdbParaTmdb.keys.prefix(300) { imdbParaTmdb.removeValue(forKey: k) }
        }
        let snapshot = CachePersistida(tmdbParaImdb: tmdbParaImdb, imdbParaTmdb: imdbParaTmdb)
        lock.unlock()
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    func registrarTitulo(_ titulo: String, tmdbId: Int, serie: Bool) {
        let norm = titulo.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard tmdbId > 0, !norm.isEmpty else { return }
        let chave = "\(serie ? "tv" : "movie"):\(norm)"
        lock.lock()
        tituloParaTmdb[chave] = tmdbId
        lock.unlock()
    }

    func cachedTmdbPorTitulo(_ titulo: String, serie: Bool) -> Int? {
        let norm = titulo.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let chave = "\(serie ? "tv" : "movie"):\(norm)"
        lock.lock()
        defer { lock.unlock() }
        return tituloParaTmdb[chave]
    }

    func cachedImdb(tmdbId: Int, serie: Bool) -> String? {
        let chave = "\(serie ? "tv" : "movie"):\(tmdbId)"
        lock.lock()
        defer { lock.unlock() }
        return tmdbParaImdb[chave]
    }

    func cachedTmdb(imdbId: String) -> Int? {
        let puro = String(imdbId.split(separator: ":").first ?? "")
        lock.lock()
        defer { lock.unlock() }
        return imdbParaTmdb[puro]
    }

    func imdbPara(tmdbId: Int, serie: Bool) async -> String? {
        if let cached = cachedImdb(tmdbId: tmdbId, serie: serie) {
            return cached
        }
        let media = serie ? "tv" : "movie"
        guard let url = URL(string: "\(Self.tmdbBase)/\(media)/\(tmdbId)/external_ids?api_key=\(Self.tmdbChave)") else {
            return nil
        }
        guard let data = try? await buscarDadosHTTP(url, timeout: 6),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let imdb = json["imdb_id"] as? String, imdb.hasPrefix("tt") else {
            return nil
        }
        registrar(tmdbId: tmdbId, imdbId: imdb, serie: serie)
        return imdb
    }

    func tmdbPara(imdbId: String, serieHint: Bool? = nil) async -> (tmdbId: Int, serie: Bool)? {
        let puro = String(imdbId.split(separator: ":").first ?? "")
        guard puro.hasPrefix("tt") else { return nil }
        if let cached = cachedTmdb(imdbId: puro), let s = serieHint {
            return (cached, s)
        }
        guard let url = URL(string: "\(Self.tmdbBase)/find/\(puro)?api_key=\(Self.tmdbChave)&external_source=imdb_id") else {
            return nil
        }
        guard let data = try? await buscarDadosHTTP(url, timeout: 6),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if serieHint != true,
           let filmes = json["movie_results"] as? [[String: Any]],
           let id = filmes.first?["id"] as? Int {
            registrar(tmdbId: id, imdbId: puro, serie: false)
            return (id, false)
        }
        if let series = json["tv_results"] as? [[String: Any]],
           let id = series.first?["id"] as? Int {
            registrar(tmdbId: id, imdbId: puro, serie: true)
            return (id, true)
        }
        return nil
    }

    func buscarTmdbPorTitulo(_ titulo: String, ano: Int?, serie: Bool) async -> Int? {
        let limpo = titulo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpo.isEmpty else { return nil }
        let media = serie ? "tv" : "movie"
        let q = limpo.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? limpo
        var urlStr = "\(Self.tmdbBase)/search/\(media)?api_key=\(Self.tmdbChave)&language=pt-BR&query=\(q)"
        if let ano, ano > 1900 {
            urlStr += serie ? "&first_air_date_year=\(ano)" : "&year=\(ano)"
        }
        guard let url = URL(string: urlStr),
              let data = try? await buscarDadosHTTP(url, timeout: 6),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let id = results.first?["id"] as? Int else {
            return nil
        }
        return id
    }

    func resolver(tmdbId: Int?, imdbId: String?, titulo: String? = nil, ano: Int? = nil, serie: Bool) async -> ResolvedMediaIds {
        var tmdb = tmdbId
        var imdb = imdbId.flatMap { s -> String? in
            let p = String(s.split(separator: ":").first ?? "")
            return p.hasPrefix("tt") ? p : nil
        }

        if tmdb == nil, let imdb {
            if let encontrado = await tmdbPara(imdbId: imdb, serieHint: serie) {
                tmdb = encontrado.tmdbId
            }
        }
        if tmdb == nil, imdb == nil, let titulo {
            tmdb = await buscarTmdbPorTitulo(titulo, ano: ano, serie: serie)
        }
        if imdb == nil, let tmdb {
            imdb = await imdbPara(tmdbId: tmdb, serie: serie)
        }

        if let tmdb, let imdb {
            registrar(tmdbId: tmdb, imdbId: imdb, serie: serie)
        }

        return ResolvedMediaIds(
            tmdbId: tmdb,
            imdbId: imdb,
            tipoStremio: serie ? "series" : "movie"
        )
    }
}

// MARK: - Coordenador de consultas Stremio

actor SaimoAddonCoordinator {
    static let shared = SaimoAddonCoordinator()

    func buscarStreams(
        addons: [AddonInstalado],
        ids: ResolvedMediaIds,
        temporada: Int? = nil,
        episodio: Int? = nil
    ) async -> [AddonResultadoStream] {
        let elegiveis = addons.filter { $0.enabled }.sorted { $0.order < $1.order }
        guard !elegiveis.isEmpty else { return [] }

        return await withTaskGroup(of: (Int, [AddonResultadoStream]).self) { group in
            for addon in elegiveis {
                let prefixos = addon.manifest.prefixosEfetivos(para: "stream")
                guard let idStremio = ids.idParaStremio(prefixos: prefixos, temporada: temporada, episodio: episodio),
                      addon.manifest.suporta(recurso: "stream", tipo: ids.tipoStremio, id: idStremio),
                      let url = addon.transport.streamUrl(type: ids.tipoStremio, id: idStremio) else {
                    continue
                }
                let order = addon.order
                let addonId = addon.manifest.id
                let addonName = addon.manifest.name
                group.addTask {
                    guard let data = try? await buscarDadosHTTP(url, timeout: 30),
                          let envelope = try? JSONDecoder().decode(StremioStreamsEnvelope.self, from: data),
                          let streams = envelope.streams else {
                        return (order, [])
                    }
                    let mapeados = streams.map { AddonResultadoStream(addonId: addonId, addonName: addonName, stream: $0) }
                    return (order, mapeados)
                }
            }

            var porOrdem: [(Int, [AddonResultadoStream])] = []
            for await par in group {
                porOrdem.append(par)
            }
            return porOrdem.sorted { $0.0 < $1.0 }.flatMap(\.1)
        }
    }

    func buscarCatalogo(
        addon: AddonInstalado,
        catalogo: AddonCatalog,
        extra: [(String, String)] = []
    ) async -> [CatalogoItem] {
        guard let url = addon.transport.catalogUrl(type: catalogo.type, id: catalogo.id, extra: extra) else {
            return []
        }
        guard let data = try? await buscarDadosHTTP(url, timeout: 8),
              let envelope = try? JSONDecoder().decode(StremioCatalogEnvelope.self, from: data) else {
            return []
        }
        return envelope.metas ?? []
    }

    func buscarMeta(
        addons: [AddonInstalado],
        tipo: String,
        id: String
    ) async -> MetaDetalhe? {
        let elegiveis = addons
            .filter { $0.enabled && $0.manifest.suporta(recurso: "meta", tipo: tipo, id: id) }
            .sorted { $0.order < $1.order }

        for addon in elegiveis {
            guard let url = addon.transport.metaUrl(type: tipo, id: id),
                  let data = try? await buscarDadosHTTP(url, timeout: 8),
                  let envelope = try? JSONDecoder().decode(StremioMetaEnvelope.self, from: data),
                  let meta = envelope.meta else {
                continue
            }
            return meta
        }
        return nil
    }

    func buscarLegendas(
        addons: [AddonInstalado],
        ids: ResolvedMediaIds,
        temporada: Int? = nil,
        episodio: Int? = nil,
        videoHash: String? = nil,
        videoSize: Int64? = nil,
        filename: String? = nil
    ) async -> [(addonName: String, subtitle: StremioSubtitle)] {
        let elegiveis = addons.filter { $0.enabled }.sorted { $0.order < $1.order }
        guard !elegiveis.isEmpty else { return [] }

        var extra: [(String, String)] = []
        if let videoHash, !videoHash.isEmpty { extra.append(("videoHash", videoHash)) }
        if let videoSize, videoSize > 0 { extra.append(("videoSize", String(videoSize))) }
        if let filename, !filename.isEmpty { extra.append(("filename", filename)) }

        return await withTaskGroup(of: [(addonName: String, subtitle: StremioSubtitle)].self) { group in
            for addon in elegiveis {
                let prefixos = addon.manifest.prefixosEfetivos(para: "subtitles")
                guard let idStremio = ids.idParaStremio(prefixos: prefixos, temporada: temporada, episodio: episodio),
                      addon.manifest.suporta(recurso: "subtitles", tipo: ids.tipoStremio, id: idStremio),
                      let url = addon.transport.subtitlesUrl(type: ids.tipoStremio, id: idStremio, extra: extra) else {
                    continue
                }
                let addonName = addon.manifest.name
                group.addTask {
                    guard let data = try? await buscarDadosHTTP(url, timeout: 7),
                          let envelope = try? JSONDecoder().decode(StremioSubtitlesEnvelope.self, from: data),
                          let subs = envelope.subtitles else {
                        return []
                    }
                    return subs.map { (addonName, $0) }
                }
            }

            var todos: [(addonName: String, subtitle: StremioSubtitle)] = []
            for await lote in group {
                todos.append(contentsOf: lote)
            }
            return todos
        }
    }
}

// MARK: - Helper HTTP puro com timeouts curtos

private func buscarDadosHTTP(_ url: URL, timeout: TimeInterval = 10) async throws -> Data {
    var req = URLRequest(url: url)
    req.timeoutInterval = timeout
    req.setValue("SaimoPlayer/1.0", forHTTPHeaderField: "User-Agent")
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response): (Data, URLResponse)
    do {
        (data, response) = try await URLSession.shared.data(for: req)
    } catch {
        throw AddonErro.rede("Falha ao conectar com \(url.host ?? "servidor"): \(error.localizedDescription)")
    }
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
        throw AddonErro.httpErro(http.statusCode, url.host ?? "addon")
    }
    return data
}
