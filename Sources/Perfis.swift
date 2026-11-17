import AppKit
import CryptoKit
import Foundation

/// Perfis: cada um com os seus favoritos, onde parou, recentes e último canal;
/// listas, fontes e ajustes são do aparelho todo. Contrato comum dos apps em
/// docs/perfis.md.
///
/// Armazenamento: o perfil principal usa o `UserDefaults.standard` de sempre
/// (quem atualiza não perde nada); cada outro perfil tem a sua suíte
/// (`br.com.saimo.tv.perfil.<id>`). Quem guarda dado de perfil usa
/// `Perfis.defaults` em vez de `UserDefaults.standard`. Trocar de perfil
/// reabre o app, para nada do perfil anterior ficar na memória.
enum Perfis {

    struct Perfil: Codable, Equatable, Identifiable {
        var id: String
        var nome: String
        var avatar: String
        /// Quando nome, avatar ou Kids mudaram por último (ms desde 1970).
        var em: Double
        /// Perfil infantil: só títulos até 12 anos, nada adulto; sair pede o código.
        var kids: Bool?
        /// SHA-256 de `saimo-kids:<id>:<código>`.
        var codigo: String?

        var ehKids: Bool { kids == true }
    }

    struct Remocao: Codable { var id: String; var em: Double }

    private struct Estado: Codable {
        var lista: [Perfil] = []
        var ativo: String = Perfis.principal
        var removidos: [Remocao] = []
        var perguntar: Bool = true
    }

    static let principal = "principal"
    static let maximo = 10
    static let maxNome = 20
    /// Ids de docs/avatares/ids.txt, na ordem da grade (PNG em Resources/avatares).
    static let avatares = ["gato", "cachorro", "raposa", "urso", "panda", "coelho", "coruja", "pinguim", "sapo",
                           "leao", "coala", "robo", "alien", "monstro", "dino", "polvo", "pintinho", "tigre",
                           "astronauta", "abelha", "fantasma"]

    private static let chave = "perfis.estado"
    nonisolated(unsafe) private static var cache: Estado?
    nonisolated(unsafe) static var escolhidoNestaSessao = false

    private static var estado: Estado {
        get {
            if let c = cache { return c }
            var e = (UserDefaults.standard.data(forKey: chave)).flatMap { try? JSONDecoder().decode(Estado.self, from: $0) } ?? Estado()
            e.lista = normalizar(e.lista)
            if !e.lista.contains(where: { $0.id == e.ativo }) { e.ativo = principal }
            cache = e
            return e
        }
        set {
            var e = newValue
            e.lista = normalizar(e.lista)
            cache = e
            if let d = try? JSONEncoder().encode(e) { UserDefaults.standard.set(d, forKey: chave) }
            NotificationCenter.default.post(name: .perfisMudaram, object: nil)
            // O celular conectado fica com os mesmos perfis.
            Task { @MainActor in SaimoConnect.shared.avisarDados() }
        }
    }

    private static func normalizar(_ lista: [Perfil]) -> [Perfil] {
        var vistos = Set<String>()
        var limpa = lista.filter { !$0.id.isEmpty && vistos.insert($0.id).inserted }
        if let i = limpa.firstIndex(where: { $0.id == principal }) { limpa[i].kids = nil; limpa[i].codigo = nil }
        let p = limpa.first { $0.id == principal } ?? Perfil(id: principal, nome: "Principal", avatar: "gato", em: 0)
        return Array(([p] + limpa.filter { $0.id != principal }).prefix(maximo))
    }

    static var todos: [Perfil] { estado.lista }
    static var removidos: [Remocao] { estado.removidos }
    static var idAtivo: String { estado.ativo }
    static var ativo: Perfil { todos.first { $0.id == idAtivo } ?? todos[0] }
    static var kidsAtivo: Bool { ativo.ehKids }

    static var perguntarAoAbrir: Bool {
        get { estado.perguntar }
        set { estado.perguntar = newValue }
    }

    static var deveEscolherAoAbrir: Bool { !escolhidoNestaSessao && estado.perguntar && todos.count >= 2 }

    // MARK: Armazenamento

    static func defaults(de id: String) -> UserDefaults {
        id == principal ? .standard : (UserDefaults(suiteName: "br.com.saimo.tv.perfil.\(id)") ?? .standard)
    }

    /// Os dados do perfil ativo.
    static var defaults: UserDefaults { defaults(de: idAtivo) }

    // MARK: Kids

    static func hashCodigo(_ id: String, _ codigo: String) -> String {
        SHA256.hash(data: Data("saimo-kids:\(id):\(codigo)".utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func pedeCodigo(_ p: Perfil) -> Bool { p.ehKids && !(p.codigo ?? "").isEmpty }
    static func conferirCodigo(_ p: Perfil, _ codigo: String) -> Bool { !pedeCodigo(p) || hashCodigo(p.id, codigo) == p.codigo }

    // MARK: Criar, editar, apagar

    private static func limpar(_ nome: String) -> String {
        String(nome.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(maxNome))
    }

    private static func novoId() -> String {
        let letras = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return "p" + String((0..<9).map { _ in letras.randomElement()! })
    }

    private static var agoraMs: Double { Date().timeIntervalSince1970 * 1000 }

    /// `kidsCodigo`: 4 dígitos ligam o Kids com esse código.
    @discardableResult
    static func criar(nome: String, avatar: String, kidsCodigo: String? = nil) -> Perfil? {
        let limpo = limpar(nome)
        guard !limpo.isEmpty, todos.count < maximo else { return nil }
        let id = novoId()
        var p = Perfil(id: id, nome: limpo, avatar: avatar, em: agoraMs)
        if let c = kidsCodigo, c.count == 4, c.allSatisfy(\.isNumber) { p.kids = true; p.codigo = hashCodigo(id, c) }
        var e = estado
        e.lista.append(p)
        estado = e
        return p
    }

    /// `kidsCodigo`: nil mantém; "" desliga o Kids; 4 dígitos ligam ou trocam o código.
    static func editar(_ id: String, nome: String, avatar: String, kidsCodigo: String? = nil) {
        let limpo = limpar(nome)
        guard !limpo.isEmpty else { return }
        var e = estado
        guard let i = e.lista.firstIndex(where: { $0.id == id }) else { return }
        e.lista[i].nome = limpo
        e.lista[i].avatar = avatar
        e.lista[i].em = agoraMs
        if let c = kidsCodigo {
            if c.isEmpty { e.lista[i].kids = nil; e.lista[i].codigo = nil }
            else if id != principal, c.count == 4, c.allSatisfy(\.isNumber) { e.lista[i].kids = true; e.lista[i].codigo = hashCodigo(id, c) }
        }
        estado = e
    }

    /// Apaga o perfil e os dados dele. O principal não sai.
    static func apagar(_ id: String) {
        guard id != principal else { return }
        apagarLocal(id)
        guardarRemocao(Remocao(id: id, em: agoraMs))
    }

    private static func apagarLocal(_ id: String) {
        UserDefaults.standard.removePersistentDomain(forName: "br.com.saimo.tv.perfil.\(id)")
        var e = estado
        e.lista.removeAll { $0.id == id }
        if e.ativo == id { e.ativo = principal }
        estado = e
    }

    private static func guardarRemocao(_ r: Remocao) {
        var e = estado
        e.removidos = Array(([r] + e.removidos.filter { $0.id != r.id }).sorted { $0.em > $1.em }.prefix(50))
        estado = e
    }

    // MARK: Trocar

    /// Entra no perfil. Outro perfil: grava e reabre o app, já sem a abertura e sem perguntar de novo.
    static func entrar(_ id: String) {
        escolhidoNestaSessao = true
        guard id != idAtivo, todos.contains(where: { $0.id == id }) else { return }
        var e = estado
        e.ativo = id
        estado = e
        UserDefaults.standard.synchronize()
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.arguments = ["--perfil-escolhido"]
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    // MARK: Sincronia (Saimo Connect)

    /// Junta a lista de perfis vinda do celular. Devolve os ids que existem aqui depois.
    static func mesclar(_ remotos: [Perfil], remocoes: [Remocao]) -> Set<String> {
        let locaisRemovidos = Dictionary(removidos.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for r in remocoes where r.id != principal {
            if let local = todos.first(where: { $0.id == r.id }), local.em <= r.em { apagarLocal(r.id) }
            if (locaisRemovidos[r.id]?.em ?? 0) < r.em { guardarRemocao(r) }
        }
        var lista = todos
        let removidosAgora = Dictionary(removidos.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for p in remotos where !p.id.isEmpty && !p.nome.isEmpty {
            if let r = removidosAgora[p.id], r.em >= p.em { continue }
            var novo = p
            novo.nome = limpar(p.nome)
            if p.id == principal { novo.kids = nil; novo.codigo = nil }
            if let i = lista.firstIndex(where: { $0.id == p.id }) {
                if p.em > lista[i].em { lista[i] = novo }
            } else if lista.count < maximo {
                lista.append(novo)
            }
        }
        var e = estado
        e.lista = lista
        estado = e
        return Set(todos.map(\.id))
    }

    /// Imagem do avatar (Resources/avatares/<id>.png).
    static func imagem(_ avatar: String) -> NSImage? {
        guard avatares.contains(avatar),
              let url = Bundle.main.url(forResource: avatar, withExtension: "png", subdirectory: "avatares") else { return nil }
        return NSImage(contentsOf: url)
    }
}

/// Controle parental: a senha que libera o conteúdo adulto. Padrão 0000,
/// trocável nos Ajustes; vale para o aparelho todo. No Kids nunca destranca.
enum Parental {
    static let padrao = "0000"
    private static let chave = "parental.senha"

    private static func hash(_ senha: String) -> String {
        SHA256.hash(data: Data("saimo-parental:\(senha)".utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static var ehPadrao: Bool { (UserDefaults.standard.string(forKey: chave) ?? "").isEmpty }

    static func conferir(_ senha: String) -> Bool {
        if Perfis.kidsAtivo { return false }
        let guardada = UserDefaults.standard.string(forKey: chave) ?? ""
        return guardada.isEmpty ? senha == padrao : hash(senha) == guardada
    }

    static func trocar(atual: String, nova: String) -> Bool {
        guard conferir(atual), nova.count == 4, nova.allSatisfy(\.isNumber) else { return false }
        UserDefaults.standard.set(hash(nova), forKey: chave)
        return true
    }
}

extension Notification.Name {
    static let perfisMudaram = Notification.Name("saimo.perfisMudaram")
}
