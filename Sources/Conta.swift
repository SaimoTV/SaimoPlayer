import AppKit
import CoreImage
import Foundation

/// Conta Saimo (opcional): o Mac entra pelo celular (QR) e sincroniza perfis,
/// onde parou, favoritos, listas e addons pela internet. Sem conta, nada muda:
/// os dados ficam no Mac e o Saimo Connect segue na rede de casa. O que viaja é
/// o mesmo pacote do Connect (`SincroniaConnect.pacote` / `aplicar`).
/// Servidor: SaimoConta (README lá). `SAIMO_CONTA_API` no ambiente aponta para
/// um servidor de teste (ex.: http://127.0.0.1:8787).
@MainActor
final class Conta: ObservableObject {
    static let shared = Conta()

    static let api: String = {
        let v = ProcessInfo.processInfo.environment["SAIMO_CONTA_API"] ?? ""
        return (v.isEmpty ? "https://conta.saimo-tv.com.br" : v).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }()

    private let padrao = UserDefaults.standard
    private let chToken = "contaSaimo.token", chEmail = "contaSaimo.email", chEm = "contaSaimo.sincronizadaEm"

    @Published private(set) var email: String?
    @Published private(set) var sincronizadaEm: Double = 0
    @Published private(set) var erro: String?
    @Published private(set) var sincronizando = false

    private var token: String? { padrao.string(forKey: chToken) }
    var logado: Bool { token != nil }

    private var ultimoEnviado = ""
    private var agendado: DispatchWorkItem?
    private var relogio: Timer?

    private init() {
        email = padrao.string(forKey: chEmail)
        sincronizadaEm = padrao.double(forKey: chEm)
    }

    struct Erro: LocalizedError { let mensagem: String; var errorDescription: String? { mensagem } }

    /// Na abertura: sincroniza em alguns segundos, ao voltar para o app, ao sair dele (se mudou algo) e a cada 15 min.
    func iniciar() {
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                let c = Conta.shared
                if c.logado, !c.sincronizando, Date().timeIntervalSince1970 * 1000 - c.sincronizadaEm > 60_000 { Task { await c.sincronizar() } }
            }
        }
        // Saiu do app (outra janela na frente) com mudança ainda não enviada: manda já.
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                let c = Conta.shared
                guard c.logado, !c.sincronizando else { return }
                if Self.texto(SincroniaConnect.pacote(PlayerModel.shared)) != c.ultimoEnviado { Task { await c.sincronizar() } }
            }
        }
        // A cada 15 min com o app na frente (voltar para ele já sincroniza).
        relogio = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard NSApplication.shared.isActive else { return }
                _ = Task { await Conta.shared.sincronizar() }
            }
        }
        if logado { DispatchQueue.main.asyncAfter(deadline: .now() + 4) { Task { await Conta.shared.sincronizar() } } }
    }

    private func chamar(_ metodo: String, _ rota: String, _ corpo: [String: Any]? = nil, comToken: Bool = true) async throws -> [String: Any] {
        guard let url = URL(string: Conta.api + rota) else { throw Erro(mensagem: "Endereço da conta inválido") }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = metodo
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if comToken, let t = token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        if let corpo { req.httpBody = try JSONSerialization.data(withJSONObject: corpo) }
        let (dados, resposta): (Data, URLResponse)
        do { (dados, resposta) = try await URLSession.shared.data(for: req) } catch {
            throw Erro(mensagem: "Sem conexão com a conta Saimo agora")
        }
        let codigo = (resposta as? HTTPURLResponse)?.statusCode ?? 0
        let j = (try? JSONSerialization.jsonObject(with: dados)) as? [String: Any] ?? [:]
        if codigo == 401, comToken, token != nil {
            // Sessão encerrada em outro lugar (sair de todos, conta apagada).
            limpar()
        }
        guard (200..<300).contains(codigo) else {
            throw Erro(mensagem: (j["mensagem"] as? String) ?? "Não deu certo: tente de novo")
        }
        return j
    }

    private func limpar() {
        padrao.removeObject(forKey: chToken); padrao.removeObject(forKey: chEmail); padrao.removeObject(forKey: chEm)
        email = nil; sincronizadaEm = 0; erro = nil; ultimoEnviado = ""
    }

    private var nomeDoAparelho: String {
        String("Saimo no \(Host.current().localizedName ?? "Mac")".prefix(60))
    }

    // MARK: entrar pelo celular (QR)

    struct Pedido { let aparelhoCodigo: String; let codigo: String; let url: String; let expiraEm: Double; let intervalo: Double }

    func pedirCodigo() async throws -> Pedido {
        let j = try await chamar("POST", "/v1/tv/pedir", ["aparelho": nomeDoAparelho], comToken: false)
        guard let a = j["aparelhoCodigo"] as? String, let c = j["codigo"] as? String, let u = j["url"] as? String else {
            throw Erro(mensagem: "Resposta inesperada da conta")
        }
        return Pedido(aparelhoCodigo: a, codigo: c, url: u, expiraEm: (j["expiraEm"] as? Double) ?? Date().timeIntervalSince1970 * 1000 + 600_000,
                      intervalo: (j["intervalo"] as? Double) ?? 5)
    }

    /// `true` quando o celular aprovou (já entrou); `false` se espera; `nil` se o código venceu.
    func conferir(_ p: Pedido) async throws -> Bool? {
        let j = try await chamar("POST", "/v1/tv/estado", ["aparelhoCodigo": p.aparelhoCodigo], comToken: false)
        switch j["estado"] as? String {
        case "aprovado":
            guard j["token"] is String else { return false }
            entrou(j)
            return true
        case "vencido": return nil
        default: return false
        }
    }

    // MARK: e-mail e senha (opcional)

    private func entrou(_ j: [String: Any]) {
        guard let t = j["token"] as? String else { return }
        let e = (j["conta"] as? [String: Any])?["email"] as? String
        padrao.set(t, forKey: chToken); padrao.set(e, forKey: chEmail)
        email = e; erro = nil; ultimoEnviado = ""
        Task { await sincronizar(forcar: true) }
    }

    /// Manda o código de 6 números para o e-mail (para criar ou trocar a senha).
    /// Em teste o servidor devolve o código (`codigoDev`). Pediu há menos de 1 min: vale o que já chegou.
    func pedirCodigoPorEmail(_ email: String) async throws -> String? {
        do {
            let j = try await chamar("POST", "/v1/email/codigo", ["email": email.trimmingCharacters(in: .whitespaces)], comToken: false)
            return j["codigoDev"] as? String
        } catch let e as Erro where e.mensagem.contains("minuto") {
            return nil
        }
    }

    func entrarComSenha(_ email: String, _ senha: String) async throws {
        entrou(try await chamar("POST", "/v1/senha/entrar",
                                ["email": email.trimmingCharacters(in: .whitespaces), "senha": senha, "aparelho": nomeDoAparelho], comToken: false))
    }

    /// Cria a conta com e-mail e senha (o e-mail não é verificado: é só o login).
    func cadastrar(_ email: String, _ senha: String) async throws {
        entrou(try await chamar("POST", "/v1/senha/cadastrar",
                                ["email": email.trimmingCharacters(in: .whitespaces), "senha": senha, "aparelho": nomeDoAparelho], comToken: false))
    }

    /// Troca a senha de quem está logado (os outros aparelhos saem da conta).
    func trocarSenha(atual: String, nova: String) async throws {
        _ = try await chamar("POST", "/v1/senha/trocar", ["senhaAtual": atual, "senhaNova": nova])
    }

    /// Cria a conta com senha ou troca a esquecida, com o código do e-mail. Trocar encerra as outras sessões.
    func definirSenha(_ email: String, codigo: String, senha: String) async throws {
        entrou(try await chamar("POST", "/v1/senha/definir",
                                ["email": email.trimmingCharacters(in: .whitespaces), "codigo": codigo, "senha": senha, "aparelho": nomeDoAparelho],
                                comToken: false))
    }

    func sair() async {
        _ = try? await chamar("POST", "/v1/sair")
        limpar()
    }

    // MARK: sincronizar

    /// Com mudança aqui: manda (PUT) e o servidor devolve tudo já juntado, que é
    /// aplicado aqui. Sem mudança: só baixa (GET) e junta. Um pedido por
    /// sincronia (cada pedido ao servidor é cobrado).
    func sincronizar(forcar: Bool = false) async {
        guard logado, !sincronizando else { return }
        sincronizando = true
        defer { sincronizando = false }
        do {
            let model = PlayerModel.shared
            let pacote = SincroniaConnect.pacote(model)
            let texto = Self.texto(pacote)
            let remoto = forcar || texto != ultimoEnviado
                ? try await chamar("PUT", "/v1/dados", ["dados": pacote])
                : try await chamar("GET", "/v1/dados")
            if let dados = remoto["dados"] as? [String: Any] {
                SincroniaConnect.aplicar(dados, model: model)
                // Listas novas baixam em segundo plano; o resto assenta logo.
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
            // O servidor já tem tudo o que ficou aqui depois de juntar: só manda de novo se mudar.
            ultimoEnviado = Self.texto(SincroniaConnect.pacote(model))
            sincronizadaEm = Date().timeIntervalSince1970 * 1000
            padrao.set(sincronizadaEm, forKey: chEm)
            erro = nil
        } catch {
            self.erro = error.localizedDescription
        }
    }

    private static func texto(_ pacote: [String: Any]) -> String {
        String(data: (try? JSONSerialization.data(withJSONObject: pacote, options: [.sortedKeys])) ?? Data(), encoding: .utf8) ?? ""
    }

    /// Entre um envio e outro, no mínimo isso (assistindo, o ponto muda o tempo todo).
    private static let intervaloMinimo: TimeInterval = 300

    /// Algo mudou aqui (o Connect avisa): manda em alguns segundos, várias mudanças
    /// num envio só, no máximo um envio a cada 2 min. Sem mudança desde o último
    /// envio (eco de juntar), não vai à rede.
    func agendar(atraso: TimeInterval = 15) {
        guard logado else { return }
        agendado?.cancel()
        let passou = Date().timeIntervalSince1970 - sincronizadaEm / 1000
        let espera = max(atraso, Self.intervaloMinimo - passou)
        let tarefa = DispatchWorkItem {
            MainActor.assumeIsolated {
                let conta = Conta.shared
                if conta.sincronizando { conta.agendar(atraso: 3); return }
                if Self.texto(SincroniaConnect.pacote(PlayerModel.shared)) == conta.ultimoEnviado { return }
                _ = Task { await conta.sincronizar() }
            }
        }
        agendado = tarefa
        DispatchQueue.main.asyncAfter(deadline: .now() + espera, execute: tarefa)
    }

    var resumo: String {
        guard logado else { return "Entrar pelo celular (QR)" }
        return "\(email ?? "Conta Saimo") · \(erro ?? Conta.haQuanto(sincronizadaEm))"
    }

    static func haQuanto(_ ms: Double) -> String {
        if ms == 0 { return "ainda não sincronizou" }
        let min = Int((Date().timeIntervalSince1970 * 1000 - ms) / 60_000)
        if min < 1 { return "sincronizado agora" }
        if min < 60 { return "sincronizado há \(min) min" }
        if min < 24 * 60 { return "sincronizado há \(min / 60) h" }
        return "sincronizado há \(min / (24 * 60)) d"
    }

    /// QR do link (CoreImage), em preto no branco, sem suavizar os quadrados.
    static func qr(_ texto: String, lado: CGFloat) -> NSImage? {
        guard let filtro = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filtro.setValue(Data(texto.utf8), forKey: "inputMessage")
        filtro.setValue("M", forKey: "inputCorrectionLevel")
        guard let saida = filtro.outputImage else { return nil }
        let escala = max(1, floor(lado / saida.extent.width))
        let grande = saida.transformed(by: CGAffineTransform(scaleX: escala, y: escala))
        let rep = NSCIImageRep(ciImage: grande)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }
}
