import Foundation

/// "Minhas listas": o link (ou arquivo) de uma lista .m3u comum vira canais
/// na categoria "Minhas listas". Tudo fica só neste Mac, em
/// Application Support/SaimoTV/minhas-listas/<id>.json (um arquivo por lista,
/// com os canais já lidos para abrir sem rede). O link nunca aparece na tela
/// nem no log.

/// Uma lista do usuário, como guardada no disco.
struct ListaSalva: Codable, Identifiable, Equatable {
    var id: String
    var nome: String
    /// O que a pessoa colou. Vazio quando a lista veio de um arquivo.
    var link: String
    var atualizadaEm: Double
    var ativa: Bool
    var criadaEm: Double
    var canais: [CanalLido]

    var veioDeArquivo: Bool { link.isEmpty }

    /// Só o que o app mostra: canais de grupo ou nome adulto ficam de fora
    /// (o desbloqueio do controle parental não é tocado por este recurso).
    var canaisVisiveis: [CanalLido] {
        canais.filter { !LeitorM3u.ehRestrito(nome: $0.nome, grupo: $0.grupo) }
    }
}

enum ErroLista: Error, Equatable {
    case esquema, baixar, naoEhLista, vazia, arquivo, limite, repetida

    var mensagem: String {
        switch self {
        case .esquema: return "O link precisa começar com http:// ou https://"
        case .baixar: return "Não consegui baixar essa lista"
        case .naoEhLista: return "Isso não parece uma lista .m3u"
        case .vazia: return "Essa lista não tem canais"
        case .arquivo: return "Não consegui ler esse arquivo"
        case .limite: return "Você já tem \(MinhasListas.maximoDeListas) listas. Remova uma para adicionar outra"
        case .repetida: return "Essa lista já foi adicionada"
        }
    }
}

@MainActor
final class MinhasListas: ObservableObject {
    static let shared = MinhasListas()

    nonisolated static let maximoDeListas = 10
    static let validade: TimeInterval = 12 * 3600
    static let nomeDaCategoria = "Minhas listas"

    @Published private(set) var listas: [ListaSalva] = []
    /// Ids das listas baixando agora.
    @Published private(set) var atualizando: Set<String> = []
    /// Há uma lista nova sendo baixada ou lida.
    @Published private(set) var adicionando = false

    /// Os canais já montados (listas ativas, sem os adultos).
    private(set) var canais: [Channel] = []

    private init() {
        carregar()
        montar()
    }

    // MARK: - Disco

    static var pasta: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("SaimoTV/minhas-listas", isDirectory: true)
    }

    private func arquivo(_ id: String) -> URL {
        Self.pasta.appendingPathComponent("\(id).json")
    }

    private func carregar() {
        guard let nomes = try? FileManager.default.contentsOfDirectory(atPath: Self.pasta.path) else { return }
        let decoder = JSONDecoder()
        var lidas: [ListaSalva] = []
        for nome in nomes where nome.hasSuffix(".json") {
            let url = Self.pasta.appendingPathComponent(nome)
            if let dados = try? Data(contentsOf: url), let lista = try? decoder.decode(ListaSalva.self, from: dados) {
                lidas.append(lista)
            }
        }
        listas = lidas.sorted { $0.criadaEm < $1.criadaEm }
    }

    private func gravar(_ lista: ListaSalva) {
        try? FileManager.default.createDirectory(at: Self.pasta, withIntermediateDirectories: true)
        if let dados = try? JSONEncoder().encode(lista) {
            try? dados.write(to: arquivo(lista.id), options: .atomic)
        }
    }

    // MARK: - Canais no app

    private func montar() {
        var vistos = Set<UUID>()
        var out: [Channel] = []
        for lista in listas where lista.ativa {
            for lido in lista.canaisVisiveis {
                let variantes = lido.fontes.compactMap { f -> Variant? in
                    guard let url = URL(string: f.url) else { return nil }
                    return Variant(url: url, referer: f.referer, userAgent: f.ua,
                                   clearKey: f.key, clearKeyId: f.keyId, label: f.qualidade, nome: nil)
                }
                guard !variantes.isEmpty else { continue }
                let canal = Channel(name: lido.nome, variants: variantes,
                                    logo: lido.logo.flatMap { URL(string: $0) },
                                    categoria: Self.nomeDaCategoria)
                if vistos.insert(canal.id).inserted { out.append(canal) }
            }
        }
        canais = out
    }

    /// Junta os canais das listas do usuário ao que o catálogo trouxe, sem
    /// repetir id. Sem nenhuma lista devolve a base como veio.
    static func juntar(_ base: [Channel]) -> [Channel] {
        let minhas = shared.canais
        guard !minhas.isEmpty else { return base }
        let existentes = Set(base.map(\.id))
        return base + minhas.filter { !existentes.contains($0.id) }
    }

    private func mudou() {
        montar()
        PlayerModel.shared.aplicarMinhasListas()
    }

    // MARK: - Ações

    private func nomePadrao() -> String {
        let usados = Set(listas.map(\.nome))
        var n = 1
        while usados.contains("Lista \(n)") { n += 1 }
        return "Lista \(n)"
    }

    private func validarNovaLista(link: String) -> ErroLista? {
        if listas.count >= Self.maximoDeListas { return .limite }
        if !link.isEmpty, listas.contains(where: { $0.link == link }) { return .repetida }
        return nil
    }

    /// Adiciona pelo link. Devolve a mensagem de erro (em português) ou nulo.
    func adicionar(link bruto: String, nome: String) async -> String? {
        let link = bruto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.ehHttp(link) else { return ErroLista.esquema.mensagem }
        if let erro = validarNovaLista(link: link) { return erro.mensagem }
        adicionando = true
        defer { adicionando = false }
        do {
            let texto = try await Self.baixar(link)
            return incluir(texto: texto, link: link, nome: nome)
        } catch let erro as ErroLista {
            return erro.mensagem
        } catch {
            return ErroLista.baixar.mensagem
        }
    }

    /// Adiciona a partir de um arquivo do disco.
    func adicionar(arquivo url: URL, nome: String) -> String? {
        if let erro = validarNovaLista(link: "") { return erro.mensagem }
        guard let dados = try? Data(contentsOf: url), dados.count <= Self.limiteDeBytes else {
            return ErroLista.arquivo.mensagem
        }
        let padrao = url.deletingPathExtension().lastPathComponent
        return incluir(texto: String(decoding: dados, as: UTF8.self), link: "",
                       nome: nome.isEmpty ? padrao : nome)
    }

    private func incluir(texto: String, link: String, nome: String) -> String? {
        guard LeitorM3u.pareceLista(texto) else { return ErroLista.naoEhLista.mensagem }
        let canais = LeitorM3u.ler(texto)
        let nova = ListaSalva(id: UUID().uuidString,
                              nome: nome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  ? nomePadrao() : nome.trimmingCharacters(in: .whitespacesAndNewlines),
                              link: link, atualizadaEm: Date().timeIntervalSince1970, ativa: true,
                              criadaEm: Date().timeIntervalSince1970, canais: canais)
        guard !nova.canaisVisiveis.isEmpty else { return ErroLista.vazia.mensagem }
        gravar(nova)
        listas.append(nova)
        mudou()
        return nil
    }

    /// Baixa de novo. `silencioso`: falha não vira mensagem (atualização de fundo).
    @discardableResult
    func atualizar(_ id: String, silencioso: Bool = false) async -> String? {
        guard let lista = listas.first(where: { $0.id == id }), !lista.veioDeArquivo,
              !atualizando.contains(id) else { return nil }
        atualizando.insert(id)
        defer { atualizando.remove(id) }
        do {
            let texto = try await Self.baixar(lista.link)
            guard LeitorM3u.pareceLista(texto) else { throw ErroLista.naoEhLista }
            let canais = LeitorM3u.ler(texto)
            var nova = lista
            nova.canais = canais
            nova.atualizadaEm = Date().timeIntervalSince1970
            guard !nova.canaisVisiveis.isEmpty else { throw ErroLista.vazia }
            // A lista pode ter sido removida enquanto baixava.
            guard let i = listas.firstIndex(where: { $0.id == id }) else { return nil }
            nova.ativa = listas[i].ativa
            nova.nome = listas[i].nome
            gravar(nova)
            listas[i] = nova
            mudou()
            return nil
        } catch let erro as ErroLista {
            return silencioso ? nil : erro.mensagem
        } catch {
            return silencioso ? nil : ErroLista.baixar.mensagem
        }
    }

    func alternar(_ id: String) {
        guard let i = listas.firstIndex(where: { $0.id == id }) else { return }
        listas[i].ativa.toggle()
        gravar(listas[i])
        mudou()
    }

    func remover(_ id: String) {
        guard listas.contains(where: { $0.id == id }) else { return }
        listas.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: arquivo(id))
        mudou()
    }

    /// Ao abrir o app: o que tem mais de 12 h é baixado de novo, em segundo
    /// plano; se falhar fica a versão guardada, sem avisar ninguém.
    func atualizarVencidas() {
        let agora = Date().timeIntervalSince1970
        let vencidas = listas.filter { $0.ativa && !$0.veioDeArquivo && agora - $0.atualizadaEm > Self.validade }
        guard !vencidas.isEmpty else { return }
        Task { @MainActor in
            for lista in vencidas { await self.atualizar(lista.id, silencioso: true) }
        }
    }

    // MARK: - Rede

    nonisolated static let limiteDeBytes = 30 * 1024 * 1024

    static func ehHttp(_ s: String) -> Bool {
        let b = s.lowercased()
        return b.hasPrefix("http://") || b.hasPrefix("https://")
    }

    /// Baixa o texto da lista: até 30 s e 30 MB, com o agente do VLC (provedores
    /// de IPTV costumam recusar navegador). Redirecionamentos são seguidos.
    static func baixar(_ link: String) async throws -> String {
        guard ehHttp(link), let url = URL(string: link) else { throw ErroLista.esquema }
        let dados = try await BaixadorM3u().baixar(url)
        return String(decoding: dados, as: UTF8.self)
    }

    /// "atualizada agora" / "atualizada há 3 h", como na tela.
    static func rotuloDeTempo(_ epoch: Double, agora: Date = Date()) -> String {
        let s = max(0, agora.timeIntervalSince1970 - epoch)
        if s < 60 { return "atualizada agora" }
        let min = Int(s / 60)
        if min < 60 { return "atualizada há \(min) min" }
        let h = min / 60
        if h < 24 { return "atualizada há \(h) h" }
        let d = h / 24
        return d == 1 ? "atualizada há 1 dia" : "atualizada há \(d) dias"
    }
}

/// Um download com limite de tempo e de tamanho (URLSession com delegado, para
/// poder cortar o excesso sem ler byte a byte).
final class BaixadorM3u: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let trava = NSLock()
    private var dados = Data()
    private var continuacao: CheckedContinuation<Data, Error>?
    private var sessao: URLSession?

    func baixar(_ url: URL) async throws -> Data {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Data, Error>) in
            trava.lock()
            continuacao = c
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 30
            let s = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            sessao = s
            trava.unlock()
            var pedido = URLRequest(url: url, timeoutInterval: 30)
            pedido.setValue("VLC/3.0.20 LibVLC/3.0.20", forHTTPHeaderField: "User-Agent")
            s.dataTask(with: pedido).resume()
        }
    }

    private func terminar(_ resultado: Result<Data, Error>) {
        trava.lock()
        let c = continuacao
        continuacao = nil
        let s = sessao
        sessao = nil
        trava.unlock()
        s?.invalidateAndCancel()
        c?.resume(with: resultado)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            completionHandler(.cancel)
            terminar(.failure(ErroLista.baixar))
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        trava.lock()
        dados.append(data)
        let estourou = dados.count > MinhasListas.limiteDeBytes
        trava.unlock()
        if estourou {
            dataTask.cancel()
            terminar(.failure(ErroLista.baixar))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error != nil {
            terminar(.failure(ErroLista.baixar))
        } else {
            trava.lock()
            let d = dados
            trava.unlock()
            terminar(.success(d))
        }
    }
}

extension PlayerModel {
    /// As listas do usuário mudaram (adicionou, atualizou, ativou, removeu):
    /// troca só os canais "Minhas listas" na lista da tela. O catálogo oficial
    /// não é tocado e o que está no ar continua, se ainda existir.
    func aplicarMinhasListas() {
        let nome = Categoria.minhasListas.rawValue
        let novos = MinhasListas.juntar(channels.filter { $0.categoria != nome })
        guard novos != channels else { return }
        let tocando = selection
        channels = novos
        for c in channels { ProxyServer.shared.register(c) }
        if let tocando, !channels.contains(where: { $0.id == tocando }) {
            selection = channels.first?.id
            if selection == nil { stop() }
        }
    }
}
