import AppKit
import Foundation

/// "Minhas listas": listas .m3u comuns trazidas por link — na tela de Ajustes
/// ou vindas do celular e da TV pelo Saimo Connect. Os canais entram no Ao
/// vivo na seção "Minhas listas"; os de adulto vão para a seção Adulto e só
/// aparecem com o restrito desbloqueado, como os do catálogo.
///
/// Tudo fica no Mac: o índice em UserDefaults e, por lista, o texto da .m3u
/// em Application Support (abre sem rede; renova depois de 12 horas). O link
/// não é mostrado de volta nem vai para o log.
@MainActor
final class MinhasListas: ObservableObject {
    static let shared = MinhasListas()
    static let categoria = "Minhas listas"
    static let maximo = 10
    private static let renovarApos: TimeInterval = 12 * 3600
    private static let agente = "VLC/3.0.20 LibVLC/3.0.20"
    private static let maximoBytes = 30 * 1024 * 1024

    struct Lista: Codable, Identifiable, Equatable {
        let id: String
        var nome: String
        let link: String
        var atualizadaEm: Double
        var total: Int
    }

    struct Erro: LocalizedError {
        let errorDescription: String?
        init(_ texto: String) { errorDescription = texto }
    }

    @Published private(set) var listas: [Lista] = []
    private var canaisPorLista: [String: [Channel]] = [:]
    private let chave = "minhasListas"

    private var pasta: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("SaimoTV/minhas_listas", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private init() {
        if let dados = UserDefaults.standard.data(forKey: chave),
           let lidas = try? JSONDecoder().decode([Lista].self, from: dados) {
            listas = lidas
        }
        for l in listas {
            if let texto = try? String(contentsOf: arquivo(l.id), encoding: .utf8) {
                canaisPorLista[l.id] = Self.ler(texto)
            }
        }
        Task { await renovarVencidas() }
    }

    /// Os canais de todas as listas; os de adulto só com o restrito liberado.
    func canais(desbloqueado: Bool) -> [Channel] {
        listas.flatMap { canaisPorLista[$0.id] ?? [] }
            .filter { desbloqueado || $0.categoria != Categoria.adulto.rawValue }
    }

    func adicionar(nome: String, link: String) async throws {
        let l = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard l.hasPrefix("http://") || l.hasPrefix("https://"), URL(string: l) != nil else {
            throw Erro("O link precisa começar com http:// ou https://")
        }
        guard !listas.contains(where: { $0.link == l }) else { return }
        guard listas.count < Self.maximo else { throw Erro("Você pode ter até \(Self.maximo) listas") }
        let texto = try await Self.baixar(l)
        let canais = Self.ler(texto)
        guard !canais.isEmpty else { throw Erro("Essa lista não tem nenhum canal") }
        let id = "l" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)
        try? texto.write(to: arquivo(id), atomically: true, encoding: .utf8)
        var nomeLivre = nome.trimmingCharacters(in: .whitespacesAndNewlines)
        if nomeLivre.isEmpty {
            var n = listas.count + 1
            while listas.contains(where: { $0.nome == "Lista \(n)" }) { n += 1 }
            nomeLivre = "Lista \(n)"
        }
        canaisPorLista[id] = canais
        listas.append(Lista(id: id, nome: nomeLivre, link: l, atualizadaEm: Date().timeIntervalSince1970,
                            total: canais.count))
        gravar()
    }

    func remover(_ id: String) {
        listas.removeAll { $0.id == id }
        canaisPorLista.removeValue(forKey: id)
        try? FileManager.default.removeItem(at: arquivo(id))
        gravar()
    }

    func confirmarRemocao(_ lista: Lista) {
        let alerta = NSAlert()
        alerta.messageText = "Remover \"\(lista.nome)\"?"
        alerta.informativeText = "Os \(lista.total) canais dela saem do Ao vivo."
        alerta.addButton(withTitle: "Remover")
        alerta.addButton(withTitle: "Cancelar")
        if alerta.runModal() == .alertFirstButtonReturn { remover(lista.id) }
    }

    private func renovarVencidas() async {
        let agora = Date().timeIntervalSince1970
        var mudou = false
        for l in listas where agora - l.atualizadaEm > Self.renovarApos {
            guard let texto = try? await Self.baixar(l.link) else { continue }
            let canais = Self.ler(texto)
            guard !canais.isEmpty, let i = listas.firstIndex(where: { $0.id == l.id }) else { continue }
            try? texto.write(to: arquivo(l.id), atomically: true, encoding: .utf8)
            canaisPorLista[l.id] = canais
            listas[i].atualizadaEm = agora
            listas[i].total = canais.count
            mudou = true
        }
        if mudou { gravar() }
    }

    private func gravar() {
        if let dados = try? JSONEncoder().encode(listas) {
            UserDefaults.standard.set(dados, forKey: chave)
        }
        PlayerModel.shared.recarregarListas()
        SaimoConnect.shared.avisarDados()
    }

    private func arquivo(_ id: String) -> URL { pasta.appendingPathComponent("\(id).m3u") }

    private static func baixar(_ link: String) async throws -> String {
        // Conta com usuário e senha (Xtream): lê pela API do servidor.
        if let conta = Xtream.deLink(link) {
            do { return try await Xtream.m3uDosCanais(conta) } catch let e as Xtream.Erro { throw Erro(e.texto) }
        }
        guard let url = URL(string: link) else { throw Erro("Link inválido") }
        var pedido = URLRequest(url: url, timeoutInterval: 30)
        pedido.setValue(agente, forHTTPHeaderField: "User-Agent")
        let (dados, resposta) = try await URLSession.shared.data(for: pedido)
        if let http = resposta as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw Erro("A lista não abriu (erro \(http.statusCode))")
        }
        guard dados.count <= maximoBytes else { throw Erro("A lista é grande demais") }
        let texto = String(decoding: dados, as: UTF8.self)
        guard texto.contains("#EXTINF") else { throw Erro("Isso não é uma lista .m3u") }
        return texto
    }

    /// Lê a .m3u: nome, logo e grupo de cada canal. Adulto (pelo grupo ou pelo
    /// nome) vai para a seção Adulto, que o controle dos pais protege.
    static func ler(_ texto: String) -> [Channel] {
        var out: [Channel] = []
        var indice: [String: Int] = [:]
        var nome: String?
        var grupo = ""
        var logo: URL?
        func atributo(_ linha: String, _ chave: String) -> String {
            guard let r = linha.range(of: "\(chave)=\"") else { return "" }
            let resto = linha[r.upperBound...]
            return String(resto.prefix { $0 != "\"" })
        }
        for bruta in texto.split(separator: "\n", omittingEmptySubsequences: false) {
            let linha = bruta.trimmingCharacters(in: .whitespacesAndNewlines)
            if linha.isEmpty { continue }
            if linha.hasPrefix("#EXTINF") {
                nome = linha.range(of: ",", options: .backwards).map {
                    String(linha[$0.upperBound...]).trimmingCharacters(in: .whitespaces)
                }
                grupo = atributo(linha, "group-title")
                logo = URL(string: atributo(linha, "tvg-logo"))
                continue
            }
            if linha.hasPrefix("#") { continue }
            guard let url = URL(string: linha), url.scheme?.hasPrefix("http") == true else { continue }
            let n = (nome?.isEmpty == false ? nome! : url.host) ?? "Canal \(out.count + 1)"
            // Mesmo nome de novo (a mesma emissora com outra fonte): vira mais uma fonte do canal.
            if let i = indice[n.lowercased()] {
                if !out[i].variants.contains(where: { $0.url == url }) { out[i].variants.append(Variant(url: url)) }
                nome = nil; grupo = ""; logo = nil
                continue
            }
            let g = grupo.lowercased()
            let adulto = Categoria.de(n) == .adulto
                || ["adult", "xxx", "+18", "18+", "porn", "sexy"].contains { g.contains($0) }
            indice[n.lowercased()] = out.count
            out.append(Channel(name: n, variants: [Variant(url: url)], logo: logo,
                               categoria: adulto ? Categoria.adulto.rawValue : categoria))
            nome = nil; grupo = ""; logo = nil
        }
        return out
    }

    /// Pede o link e o nome de uma lista nova (Ajustes > Minhas listas).
    func pedirNova() {
        let alerta = NSAlert()
        alerta.messageText = "Adicionar lista"
        alerta.informativeText = "Cole o link da sua lista M3U: só isso já basta. Usuário e senha são opcionais, para listas que pedem login. Os canais aparecem no Ao vivo, em \"Minhas listas\"."
        alerta.addButton(withTitle: "Adicionar")
        alerta.addButton(withTitle: "Cancelar")
        let pilha = NSStackView(frame: NSRect(x: 0, y: 0, width: 420, height: 124))
        pilha.orientation = .vertical
        pilha.spacing = 6
        let campoNome = NSTextField(string: "")
        campoNome.placeholderString = "Nome (opcional)"
        let campoLink = NSSecureTextField(string: "")
        campoLink.placeholderString = "Link da lista (M3U) ou servidor"
        let campoUsuario = NSTextField(string: "")
        campoUsuario.placeholderString = "Usuário (opcional: deixe em branco se a lista é só um link)"
        let campoSenha = NSSecureTextField(string: "")
        campoSenha.placeholderString = "Senha (opcional)"
        for c in [campoLink, campoUsuario, campoSenha, campoNome] as [NSTextField] {
            pilha.addArrangedSubview(c)
            c.widthAnchor.constraint(equalToConstant: 420).isActive = true
        }
        alerta.accessoryView = pilha
        guard alerta.runModal() == .alertFirstButtonReturn else { return }
        let nome = campoNome.stringValue
        let link: String
        switch Xtream.linkDoFormulario(campoLink.stringValue, usuario: campoUsuario.stringValue, senha: campoSenha.stringValue) {
        case .success(let l): link = l
        case .failure(let e):
            PlayerModel.shared.aviso = e.texto
            return
        }
        Task { @MainActor in
            do {
                try await adicionar(nome: nome, link: link)
            } catch {
                PlayerModel.shared.aviso = error.localizedDescription
            }
        }
    }
}
