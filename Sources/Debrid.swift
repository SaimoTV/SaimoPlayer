import Foundation
import Combine

// MARK: - Provedores e Configuração (`saimo_debrid_v1`)

enum DebridProvedor: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case torbox
    case realDebrid = "realdebrid"
    case allDebrid = "alldebrid"
    case premiumize

    var id: String { rawValue }

    var nome: String {
        switch self {
        case .torbox: return "TorBox"
        case .realDebrid: return "Real-Debrid"
        case .allDebrid: return "AllDebrid"
        case .premiumize: return "Premiumize"
        }
    }

    var dicaChave: String {
        switch self {
        case .torbox: return "torbox.app → Configurações → API Key"
        case .realDebrid: return "real-debrid.com/apitoken"
        case .allDebrid: return "alldebrid.com/apikeys"
        case .premiumize: return "premiumize.me/account → API Key"
        }
    }
}

struct DebridEntrada: Codable, Hashable, Sendable {
    var enabled: Bool = false
    var apiKey: String = ""

    var ativoValido: Bool {
        enabled && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct DebridConfiguracao: Codable, Hashable, Sendable {
    var provedores: [String: DebridEntrada] = [:]
    var sincronizarConnect: Bool = false
}

enum DebridErro: LocalizedError, Sendable, Equatable {
    case nenhumConfigurado
    case credencialInvalida(String)
    case torrentNaoEmCache(String, String)
    case arquivoNaoEncontrado(String)
    case respostaInvalida(String, String)

    var errorDescription: String? {
        switch self {
        case .nenhumConfigurado:
            return "Este stream é um torrent P2P. Configure um serviço Debrid (TorBox, Real-Debrid, AllDebrid ou Premiumize) em Ajustes → Addons e Debrid para reproduzir."
        case .credencialInvalida(let provedor):
            return "\(provedor): chave de API inválida ou expirada."
        case .torrentNaoEmCache(let provedor, let detalhe):
            return "\(provedor): torrent ainda não está em cache instantâneo (\(detalhe))."
        case .arquivoNaoEncontrado(let provedor):
            return "\(provedor): nenhum arquivo de vídeo compatível encontrado no torrent."
        case .respostaInvalida(let provedor, let msg):
            return "\(provedor): \(msg)"
        }
    }
}

@MainActor
final class DebridStore: ObservableObject {
    static let shared = DebridStore()
    static let defaultsKey = "saimo_debrid_v1"
    static let mudou = Notification.Name("SaimoDebridMudou")

    @Published private(set) var configuracao = DebridConfiguracao()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        carregar()
    }

    func entrada(para provedor: DebridProvedor) -> DebridEntrada {
        configuracao.provedores[provedor.rawValue] ?? DebridEntrada()
    }

    var sincronizarConnect: Bool {
        configuracao.sincronizarConnect
    }

    var ativosOrdenados: [(DebridProvedor, String)] {
        DebridProvedor.allCases.compactMap { provedor in
            let item = entrada(para: provedor)
            let chave = item.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard item.enabled, !chave.isEmpty else { return nil }
            return (provedor, chave)
        }
    }

    var temAlgumAtivo: Bool {
        !ativosOrdenados.isEmpty
    }

    func definir(provedor: DebridProvedor, apiKey: String? = nil, enabled: Bool? = nil) {
        var atual = entrada(para: provedor)
        if let apiKey {
            atual.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let enabled {
            atual.enabled = enabled
        }
        configuracao.provedores[provedor.rawValue] = atual
        salvar()
    }

    func definirSincronizarConnect(_ valor: Bool) {
        configuracao.sincronizarConnect = valor
        salvar()
    }

    func limparTudo() {
        configuracao = DebridConfiguracao()
        salvar()
    }

    // MARK: - Saimo Connect / API remota (opt-in)

    func paraConnect(incluirChaves: Bool = true) -> [String: Any] {
        var provs: [String: [String: Any]] = [:]
        for p in DebridProvedor.allCases {
            let e = entrada(para: p)
            provs[p.rawValue] = [
                "enabled": e.enabled,
                "apiKey": incluirChaves ? e.apiKey : (e.apiKey.isEmpty ? "" : "••••"),
                "configured": !e.apiKey.isEmpty,
            ]
        }
        return [
            "sincronizarConnect": configuracao.sincronizarConnect,
            "provedores": provs,
        ]
    }

    func aplicarConnect(_ dict: [String: Any]) {
        if let sync = dict["sincronizarConnect"] as? Bool {
            configuracao.sincronizarConnect = sync
        }
        if let provs = dict["provedores"] as? [String: [String: Any]] {
            for p in DebridProvedor.allCases {
                guard let obj = provs[p.rawValue] else { continue }
                var item = entrada(para: p)
                if let enabled = obj["enabled"] as? Bool {
                    item.enabled = enabled
                }
                if let key = obj["apiKey"] as? String, key != "••••" {
                    item.apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                configuracao.provedores[p.rawValue] = item
            }
        }
        salvar()
    }

    private func carregar() {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let decodificado = try? JSONDecoder().decode(DebridConfiguracao.self, from: data) else {
            configuracao = DebridConfiguracao()
            return
        }
        configuracao = decodificado
    }

    private func salvar() {
        if let data = try? JSONEncoder().encode(configuracao) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
        NotificationCenter.default.post(name: Self.mudou, object: nil)
    }
}

// MARK: - Utilitários de Magnet e Seleção de Arquivos

struct DebridArquivo: Equatable, Sendable {
    let indiceZeroBased: Int
    let idRemoto: String
    let caminho: String
    let tamanho: Int64
    let linkDireto: String?

    init(indiceZeroBased: Int, idRemoto: String, caminho: String, tamanho: Int64, linkDireto: String? = nil) {
        self.indiceZeroBased = indiceZeroBased
        self.idRemoto = idRemoto
        self.caminho = caminho
        self.tamanho = tamanho
        self.linkDireto = linkDireto
    }
}

enum DebridUtils {
    private static let extensoesVideo: Set<String> = [
        "mkv", "mp4", "m4v", "avi", "mov", "webm", "wmv", "flv", "ts", "m2ts", "mpg", "mpeg"
    ]

    static func ehArquivoVideo(_ caminho: String) -> Bool {
        let nome = (caminho as NSString).lastPathComponent.lowercased()
        let ext = (nome as NSString).pathExtension
        guard extensoesVideo.contains(ext) else { return false }
        return true
    }

    static func ehSample(_ caminho: String) -> Bool {
        let base = ((caminho as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased()
        return base == "sample" || base.hasSuffix("-sample") || base.hasSuffix(".sample") || base.hasPrefix("sample-")
    }

    /// Monta magnet URI preservando trackers `sources` do protocolo Stremio.
    static func montarMagnet(infoHash: String, sources: [String]? = nil, titulo: String? = nil) -> String {
        let hashLimpo = infoHash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var partes = ["magnet:?xt=urn:btih:\(hashLimpo)"]

        if let titulo {
            let limpo = titulo.trimmingCharacters(in: .whitespacesAndNewlines)
            if !limpo.isEmpty,
               let enc = limpo.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                partes.append("dn=\(enc)")
            }
        }

        var trackersVistos = Set<String>()
        for src in sources ?? [] {
            let candidato: String
            if src.hasPrefix("tracker:") {
                candidato = String(src.dropFirst("tracker:".count))
            } else if src.contains("://") {
                candidato = src
            } else {
                continue
            }
            let trim = candidato.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trim.isEmpty, trackersVistos.insert(trim).inserted else { continue }
            var allowed = CharacterSet.urlQueryAllowed
            allowed.remove(charactersIn: "&=+#")
            if let enc = trim.addingPercentEncoding(withAllowedCharacters: allowed) {
                partes.append("tr=\(enc)")
            }
        }

        return partes.joined(separator: "&")
    }

    /// Escolhe o arquivo correspondente ao `fileIdx` (0-based) ou o maior arquivo de vídeo válido.
    static func selecionarArquivoVideo(arquivos: [DebridArquivo], fileIdx: Int?) -> DebridArquivo? {
        guard !arquivos.isEmpty else { return nil }

        if let fileIdx, fileIdx >= 0 {
            if let exato = arquivos.first(where: { $0.indiceZeroBased == fileIdx }), ehArquivoVideo(exato.caminho) {
                return exato
            }
            if fileIdx < arquivos.count, ehArquivoVideo(arquivos[fileIdx].caminho) {
                return arquivos[fileIdx]
            }
        }

        let videosSemSample = arquivos.filter { ehArquivoVideo($0.caminho) && !ehSample($0.caminho) }
        if let maior = videosSemSample.max(by: { $0.tamanho < $1.tamanho }) {
            return maior
        }

        let qualquerVideo = arquivos.filter { ehArquivoVideo($0.caminho) }
        if let maiorVideo = qualquerVideo.max(by: { $0.tamanho < $1.tamanho }) {
            return maiorVideo
        }

        return arquivos.max(by: { $0.tamanho < $1.tamanho })
    }
}

// MARK: - Cliente REST Debrid (TorBox, Real-Debrid, AllDebrid, Premiumize)

enum DebridResolver {
    private static let agent = "SaimoPlayer"

    /// Resolve um stream Stremio (direto ou torrent via Debrid ativo) para uma URL HTTP(S) reproduzível.
    static func resolver(
        stream: StremioStream,
        ativos: [(DebridProvedor, String)],
        nomeTitulo: String? = nil
    ) async throws -> URL {
        if let urlStr = stream.url, !urlStr.isEmpty, let direta = URL(string: urlStr) {
            return direta
        }

        guard let infoHash = stream.infoHash?.trimmingCharacters(in: .whitespacesAndNewlines), !infoHash.isEmpty else {
            throw DebridErro.respostaInvalida("Stream", "Este stream não possui URL nem infoHash torrent.")
        }

        guard !ativos.isEmpty else {
            throw DebridErro.nenhumConfigurado
        }

        let magnet = DebridUtils.montarMagnet(infoHash: infoHash, sources: stream.sources, titulo: nomeTitulo ?? stream.behaviorHints?.filename)
        var ultimoErro: Error?

        for (provedor, apiKey) in ativos {
            do {
                switch provedor {
                case .torbox:
                    return try await resolverTorBox(apiKey: apiKey, magnet: magnet, infoHash: infoHash, fileIdx: stream.fileIdx)
                case .realDebrid:
                    return try await resolverRealDebrid(apiKey: apiKey, magnet: magnet, fileIdx: stream.fileIdx)
                case .allDebrid:
                    return try await resolverAllDebrid(apiKey: apiKey, magnet: magnet, fileIdx: stream.fileIdx)
                case .premiumize:
                    return try await resolverPremiumize(apiKey: apiKey, magnet: magnet, fileIdx: stream.fileIdx)
                }
            } catch {
                ultimoErro = error
            }
        }

        throw ultimoErro ?? DebridErro.nenhumConfigurado
    }

    // MARK: - Parsers puros (também exercitados nos testes unitários)

    static func parsearArquivosTorBox(_ json: [String: Any]) -> (torrentId: String?, downloadPresent: Bool, state: String, arquivos: [DebridArquivo])? {
        let item: [String: Any]
        if let arr = json["data"] as? [[String: Any]], let first = arr.first {
            item = first
        } else if let obj = json["data"] as? [String: Any] {
            item = obj
        } else {
            return nil
        }

        let tid = item["id"].map { "\($0)" }
        let downloadPresent = (item["download_present"] as? Bool) ?? false
        let state = (item["download_state"] as? String) ?? "desconhecido"
        let rawFiles = item["files"] as? [[String: Any]] ?? []
        let arquivos = rawFiles.enumerated().map { idx, f in
            let fid = f["id"].map { "\($0)" } ?? "\(idx)"
            let nome = (f["name"] as? String) ?? (f["short_name"] as? String) ?? "video_\(idx)"
            let size = (f["size"] as? Int64) ?? Int64(f["size"] as? Int ?? 0)
            return DebridArquivo(indiceZeroBased: idx, idRemoto: fid, caminho: nome, tamanho: size)
        }
        return (tid, downloadPresent, state, arquivos)
    }

    static func parsearInfoRealDebrid(_ json: [String: Any]) -> (status: String, arquivos: [DebridArquivo], links: [String], selecionados: [String])? {
        let status = (json["status"] as? String) ?? ""
        let rawFiles = json["files"] as? [[String: Any]] ?? []
        var selecionados: [String] = []
        let arquivos = rawFiles.enumerated().map { idx, f in
            let fid = f["id"].map { "\($0)" } ?? "\(idx + 1)"
            let path = (f["path"] as? String) ?? "video_\(idx)"
            let bytes = (f["bytes"] as? Int64) ?? Int64(f["bytes"] as? Int ?? 0)
            if (f["selected"] as? Int ?? 0) == 1 {
                selecionados.append(fid)
            }
            return DebridArquivo(indiceZeroBased: idx, idRemoto: fid, caminho: path, tamanho: bytes)
        }
        let links = json["links"] as? [String] ?? []
        return (status, arquivos, links, selecionados)
    }

    static func parsearStatusAllDebrid(_ json: [String: Any]) -> (statusCode: Int, statusText: String, arquivos: [DebridArquivo])? {
        guard let data = json["data"] as? [String: Any] else { return nil }
        let magnetObj: [String: Any]
        if let m = data["magnets"] as? [String: Any] {
            magnetObj = m
        } else if let arr = data["magnets"] as? [[String: Any]], let first = arr.first {
            magnetObj = first
        } else {
            return nil
        }

        let statusCode = magnetObj["statusCode"] as? Int ?? -1
        let statusText = (magnetObj["status"] as? String) ?? "aguardando"
        let rawLinks = magnetObj["links"] as? [[String: Any]] ?? []
        let arquivos = rawLinks.enumerated().map { idx, item in
            let filename = (item["filename"] as? String) ?? "video_\(idx)"
            let size = (item["size"] as? Int64) ?? Int64(item["size"] as? Int ?? 0)
            let link = item["link"] as? String
            return DebridArquivo(indiceZeroBased: idx, idRemoto: "\(idx)", caminho: filename, tamanho: size, linkDireto: link)
        }
        return (statusCode, statusText, arquivos)
    }

    static func parsearPremiumizeDirectDL(_ json: [String: Any], fileIdx: Int?) -> URL? {
        guard (json["status"] as? String) == "success",
              let content = json["content"] as? [[String: Any]] else {
            return nil
        }
        let arquivos = content.enumerated().map { idx, c in
            let path = (c["path"] as? String) ?? "video_\(idx)"
            let size = (c["size"] as? Int64) ?? Int64(c["size"] as? Int ?? 0)
            let link = (c["link"] as? String) ?? (c["stream_link"] as? String)
            return DebridArquivo(indiceZeroBased: idx, idRemoto: "\(idx)", caminho: path, tamanho: size, linkDireto: link)
        }
        guard let escolhido = DebridUtils.selecionarArquivoVideo(arquivos: arquivos, fileIdx: fileIdx),
              let link = escolhido.linkDireto else {
            return nil
        }
        return URL(string: link)
    }

    // MARK: - Implementações de Rede

    private static func resolverTorBox(apiKey: String, magnet: String, infoHash: String, fileIdx: Int?) async throws -> URL {
        let base = "https://api.torbox.app/v1/api"
        let headers = ["Authorization": "Bearer \(apiKey)"]

        // 1. Verifica cache rapidamente
        if let checkURL = URL(string: "\(base)/torrents/checkcached?hash=\(infoHash)&format=list&list_files=true"),
           let (data, code) = try? await requisicao(checkURL, headers: headers) {
            if code == 401 || code == 403 {
                throw DebridErro.credencialInvalida("TorBox")
            }
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let sucesso = obj["success"] as? Bool, sucesso,
               let arr = obj["data"] as? [[String: Any]], arr.isEmpty {
                throw DebridErro.torrentNaoEmCache("TorBox", "sem cache no momento")
            }
        }

        // 2. Cria/anexa o magnet na conta para obter torrent_id
        guard let createURL = URL(string: "\(base)/torrents/createtorrent") else {
            throw DebridErro.respostaInvalida("TorBox", "URL inválida.")
        }
        let boundary = "SaimoBoundary-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"magnet\"\r\n\r\n\(magnet)\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var createHeaders = headers
        createHeaders["Content-Type"] = "multipart/form-data; boundary=\(boundary)"

        let (createData, createCode) = try await requisicao(createURL, method: "POST", headers: createHeaders, body: body)
        if createCode == 401 || createCode == 403 { throw DebridErro.credencialInvalida("TorBox") }
        guard (200..<300).contains(createCode),
              let createJson = try? JSONSerialization.jsonObject(with: createData) as? [String: Any],
              let dataObj = createJson["data"] as? [String: Any],
              let torrentId = dataObj["torrent_id"].map({ "\($0)" }) else {
            throw DebridErro.respostaInvalida("TorBox", "não foi possível registrar o magnet.")
        }

        // 3. Consulta arquivos do torrent (pequena espera caso recém-adicionado)
        var target: DebridArquivo?
        var ultimoEstado = "processando"
        for tentativa in 0..<4 {
            if tentativa > 0 { try? await Task.sleep(for: .milliseconds(900)) }
            guard let listURL = URL(string: "\(base)/torrents/mylist?id=\(torrentId)") else { break }
            let (listData, listCode) = try await requisicao(listURL, headers: headers)
            guard (200..<300).contains(listCode),
                  let json = try? JSONSerialization.jsonObject(with: listData) as? [String: Any],
                  let parsed = parsearArquivosTorBox(json) else { continue }
            ultimoEstado = parsed.state
            if parsed.downloadPresent, let escolhido = DebridUtils.selecionarArquivoVideo(arquivos: parsed.arquivos, fileIdx: fileIdx) {
                target = escolhido
                break
            }
        }

        guard let arquivo = target else {
            throw DebridErro.torrentNaoEmCache("TorBox", ultimoEstado)
        }

        // 4. Solicita link direto de download
        var comp = URLComponents(string: "\(base)/torrents/requestdl")!
        comp.queryItems = [
            URLQueryItem(name: "token", value: apiKey),
            URLQueryItem(name: "torrent_id", value: torrentId),
            URLQueryItem(name: "file_id", value: arquivo.idRemoto),
            URLQueryItem(name: "zip_link", value: "false"),
        ]
        guard let dlURL = comp.url else { throw DebridErro.respostaInvalida("TorBox", "falha ao montar requestdl.") }
        let (dlData, dlCode) = try await requisicao(dlURL, headers: headers)
        guard (200..<300).contains(dlCode),
              let dlJson = try? JSONSerialization.jsonObject(with: dlData) as? [String: Any],
              let finalStr = dlJson["data"] as? String,
              let finalURL = URL(string: finalStr) else {
            throw DebridErro.respostaInvalida("TorBox", "link direto não retornado.")
        }
        return finalURL
    }

    private static func resolverRealDebrid(apiKey: String, magnet: String, fileIdx: Int?) async throws -> URL {
        let base = "https://api.real-debrid.com/rest/1.0"
        let headers = ["Authorization": "Bearer \(apiKey)"]

        // 1. addMagnet
        guard let addURL = URL(string: "\(base)/torrents/addMagnet") else {
            throw DebridErro.respostaInvalida("Real-Debrid", "URL inválida.")
        }
        let addBody = formURLEncoded([("magnet", magnet)])
        let (addData, addCode) = try await requisicao(addURL, method: "POST", headers: headers, body: addBody)
        if addCode == 401 || addCode == 403 { throw DebridErro.credencialInvalida("Real-Debrid") }
        guard (200..<300).contains(addCode),
              let addJson = try? JSONSerialization.jsonObject(with: addData) as? [String: Any],
              let tid = addJson["id"] as? String else {
            throw DebridErro.respostaInvalida("Real-Debrid", "falha ao adicionar magnet.")
        }

        // 2. Obtém lista de arquivos para selecionar apenas o desejado ou os vídeos
        guard let infoURL = URL(string: "\(base)/torrents/info/\(tid)") else {
            throw DebridErro.respostaInvalida("Real-Debrid", "URL info inválida.")
        }
        var targetFileId: String?
        var filesToSelect = "all"
        for tentativa in 0..<4 {
            if tentativa > 0 { try? await Task.sleep(for: .milliseconds(700)) }
            let (iData, iCode) = try await requisicao(infoURL, headers: headers)
            guard (200..<300).contains(iCode),
                  let iJson = try? JSONSerialization.jsonObject(with: iData) as? [String: Any],
                  let parsed = parsearInfoRealDebrid(iJson),
                  !parsed.arquivos.isEmpty else { continue }
            if let escolhido = DebridUtils.selecionarArquivoVideo(arquivos: parsed.arquivos, fileIdx: fileIdx) {
                targetFileId = escolhido.idRemoto
                filesToSelect = escolhido.idRemoto
            } else {
                let idsVideo = parsed.arquivos.filter { DebridUtils.ehArquivoVideo($0.caminho) }.map(\.idRemoto)
                if !idsVideo.isEmpty { filesToSelect = idsVideo.joined(separator: ",") }
            }
            break
        }

        // 3. selectFiles
        if let selectURL = URL(string: "\(base)/torrents/selectFiles/\(tid)") {
            let sBody = formURLEncoded([("files", filesToSelect)])
            let (_, sCode) = try await requisicao(selectURL, method: "POST", headers: headers, body: sBody)
            if sCode == 401 || sCode == 403 { throw DebridErro.credencialInvalida("Real-Debrid") }
        }

        // 4. Aguarda links prontos (instantâneo se em cache)
        var linkEscolhido: String?
        var ultimoStatus = "waiting_files_selection"
        for tentativa in 0..<5 {
            if tentativa > 0 { try? await Task.sleep(for: .milliseconds(800)) }
            let (iData, iCode) = try await requisicao(infoURL, headers: headers)
            guard (200..<300).contains(iCode),
                  let iJson = try? JSONSerialization.jsonObject(with: iData) as? [String: Any],
                  let parsed = parsearInfoRealDebrid(iJson) else { continue }
            ultimoStatus = parsed.status
            if parsed.status == "downloaded", !parsed.links.isEmpty {
                if let targetFileId,
                   let pos = parsed.selecionados.firstIndex(of: targetFileId),
                   pos < parsed.links.count {
                    linkEscolhido = parsed.links[pos]
                } else {
                    linkEscolhido = parsed.links.first
                }
                break
            }
            if ["magnet_error", "error", "virus", "dead"].contains(parsed.status) {
                throw DebridErro.torrentNaoEmCache("Real-Debrid", parsed.status)
            }
        }

        guard let hostLink = linkEscolhido else {
            throw DebridErro.torrentNaoEmCache("Real-Debrid", ultimoStatus)
        }

        // 5. unrestrict/link
        guard let unrestrictURL = URL(string: "\(base)/unrestrict/link") else {
            throw DebridErro.respostaInvalida("Real-Debrid", "URL unrestrict inválida.")
        }
        let uBody = formURLEncoded([("link", hostLink)])
        let (uData, uCode) = try await requisicao(unrestrictURL, method: "POST", headers: headers, body: uBody)
        guard (200..<300).contains(uCode),
              let uJson = try? JSONSerialization.jsonObject(with: uData) as? [String: Any],
              let dlStr = uJson["download"] as? String,
              let dlURL = URL(string: dlStr) else {
            throw DebridErro.respostaInvalida("Real-Debrid", "falha ao liberar link direto.")
        }
        return dlURL
    }

    private static func resolverAllDebrid(apiKey: String, magnet: String, fileIdx: Int?) async throws -> URL {
        let base = "https://api.alldebrid.com/v4"
        let headers = ["Authorization": "Bearer \(apiKey)"]

        // 1. Upload magnet
        guard let uploadURL = URL(string: "\(base)/magnet/upload?agent=\(agent)") else {
            throw DebridErro.respostaInvalida("AllDebrid", "URL inválida.")
        }
        let body = formURLEncoded([("magnets[]", magnet)])
        let (uData, uCode) = try await requisicao(uploadURL, method: "POST", headers: headers, body: body)
        if uCode == 401 || uCode == 403 { throw DebridErro.credencialInvalida("AllDebrid") }
        guard (200..<300).contains(uCode),
              let uJson = try? JSONSerialization.jsonObject(with: uData) as? [String: Any],
              (uJson["status"] as? String) == "success",
              let dataObj = uJson["data"] as? [String: Any],
              let magnets = dataObj["magnets"] as? [[String: Any]],
              let first = magnets.first,
              let mid = first["id"].map({ "\($0)" }) else {
            throw DebridErro.respostaInvalida("AllDebrid", "chave inválida ou falha ao enviar magnet.")
        }

        // 2. Status
        var linkBruto: String?
        var ultimoTexto = "processando"
        for tentativa in 0..<5 {
            if tentativa > 0 { try? await Task.sleep(for: .milliseconds(800)) }
            guard let statusURL = URL(string: "\(base)/magnet/status?agent=\(agent)&id=\(mid)") else { break }
            let (sData, sCode) = try await requisicao(statusURL, headers: headers)
            guard (200..<300).contains(sCode),
                  let sJson = try? JSONSerialization.jsonObject(with: sData) as? [String: Any],
                  let parsed = parsearStatusAllDebrid(sJson) else { continue }
            ultimoTexto = parsed.statusText
            if parsed.statusCode == 4, !parsed.arquivos.isEmpty {
                linkBruto = DebridUtils.selecionarArquivoVideo(arquivos: parsed.arquivos, fileIdx: fileIdx)?.linkDireto
                break
            }
            if parsed.statusCode > 4 {
                throw DebridErro.torrentNaoEmCache("AllDebrid", parsed.statusText)
            }
        }

        guard let link = linkBruto else {
            throw DebridErro.torrentNaoEmCache("AllDebrid", ultimoTexto)
        }

        // 3. Unlock
        var comp = URLComponents(string: "\(base)/link/unlock")!
        comp.queryItems = [
            URLQueryItem(name: "agent", value: agent),
            URLQueryItem(name: "link", value: link),
        ]
        guard let unlockURL = comp.url else { throw DebridErro.respostaInvalida("AllDebrid", "URL unlock inválida.") }
        let (kData, kCode) = try await requisicao(unlockURL, headers: headers)
        guard (200..<300).contains(kCode),
              let kJson = try? JSONSerialization.jsonObject(with: kData) as? [String: Any],
              let kDataObj = kJson["data"] as? [String: Any],
              let finalStr = kDataObj["link"] as? String,
              let finalURL = URL(string: finalStr) else {
            throw DebridErro.respostaInvalida("AllDebrid", "não foi possível desbloquear o link.")
        }
        return finalURL
    }

    private static func resolverPremiumize(apiKey: String, magnet: String, fileIdx: Int?) async throws -> URL {
        guard let url = URL(string: "https://www.premiumize.me/api/transfer/directdl") else {
            throw DebridErro.respostaInvalida("Premiumize", "URL inválida.")
        }
        let body = formURLEncoded([
            ("apikey", apiKey),
            ("src", magnet),
        ])
        let (data, code) = try await requisicao(url, method: "POST", body: body)
        if code == 401 || code == 403 { throw DebridErro.credencialInvalida("Premiumize") }
        guard (200..<300).contains(code),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DebridErro.respostaInvalida("Premiumize", "resposta HTTP \(code).")
        }
        if (json["status"] as? String) != "success" {
            let msg = (json["message"] as? String) ?? "não está em cache"
            if msg.lowercased().contains("auth") || msg.lowercased().contains("apikey") {
                throw DebridErro.credencialInvalida("Premiumize")
            }
            throw DebridErro.torrentNaoEmCache("Premiumize", msg)
        }
        guard let finalURL = parsearPremiumizeDirectDL(json, fileIdx: fileIdx) else {
            throw DebridErro.arquivoNaoEncontrado("Premiumize")
        }
        return finalURL
    }

    private static func requisicao(
        _ url: URL,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval = 12
    ) async throws -> (Data, Int) {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = timeout
        req.setValue("SaimoPlayer/1.0", forHTTPHeaderField: "User-Agent")
        for (k, v) in headers {
            req.setValue(v, forHTTPHeaderField: k)
        }
        if let body {
            req.httpBody = body
            if req.value(forHTTPHeaderField: "Content-Type") == nil {
                req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            }
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        return (data, code)
    }

    private static func formURLEncoded(_ pairs: [(String, String)]) -> Data {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+#")
        let encoded = pairs.map { k, v in
            let ek = k.addingPercentEncoding(withAllowedCharacters: allowed) ?? k
            let ev = v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v
            return "\(ek)=\(ev)"
        }.joined(separator: "&")
        return Data(encoded.utf8)
    }
}
