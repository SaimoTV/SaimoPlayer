import Foundation

/// Lista com usuário e senha (o formato "Xtream Codes" que a maioria dos
/// provedores de IPTV usa).
///
/// Uma conta Xtream é guardada como um link M3U comum
/// (`http://servidor:porta/get.php?username=…&password=…&type=m3u_plus`): assim
/// ela viaja pelo Saimo Connect e entra em "Minhas listas" como qualquer outra.
/// Quem cola esse link direto, ou digita servidor + usuário + senha, cai no
/// mesmo caminho: o app lê os canais pela API do servidor (`player_api.php`),
/// que é mais leve e traz as categorias. Se a API não responde, vale o M3U do
/// próprio `get.php`.
///
/// A senha nunca é mostrada de volta nem entra em log ou em mensagem de erro.
enum Xtream {

    struct Conta: Equatable {
        let base: String
        let usuario: String
        let senha: String

        var linkM3u: String { Xtream.linkM3u(base: base, usuario: usuario, senha: senha) }
        func api(_ acao: String? = nil) -> String {
            "\(base)/player_api.php?username=\(Xtream.cod(usuario))&password=\(Xtream.cod(senha))" + (acao.map { "&action=\($0)" } ?? "")
        }
        func canal(_ id: String, _ ext: String) -> String { "\(base)/live/\(Xtream.cod(usuario))/\(Xtream.cod(senha))/\(id).\(ext)" }
        func filme(_ id: String, _ ext: String) -> String { "\(base)/movie/\(Xtream.cod(usuario))/\(Xtream.cod(senha))/\(id).\(ext)" }
        func episodio(_ id: String, _ ext: String) -> String { "\(base)/series/\(Xtream.cod(usuario))/\(Xtream.cod(senha))/\(id).\(ext)" }
    }

    struct Erro: Error { let texto: String }

    /// Canal lido da API (ou do M3U): nome, categoria, logo e as fontes em ordem.
    struct CanalLido: Equatable {
        var nome: String
        var grupo: String?
        var logo: String?
        var fontes: [String]
    }

    static func cod(_ s: String) -> String {
        var permitido = CharacterSet.alphanumerics
        permitido.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: permitido) ?? s
    }

    static func linkM3u(base: String, usuario: String, senha: String) -> String {
        "\(base)/get.php?username=\(cod(usuario))&password=\(cod(senha))&type=m3u_plus&output=ts"
    }

    /// Servidor digitado -> base sem barra no fim (`http://host:porta`, com o
    /// caminho do painel, se houver). Sem esquema ganha `http://` (a quase
    /// totalidade dos painéis não tem https). Nulo se não parece um endereço.
    static func normalizarServidor(_ texto: String) -> String? {
        var t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || t.contains(where: \.isWhitespace) { return nil }
        if !t.contains("://") { t = "http://" + t }
        let padrao = #"^(https?)://([^/?#]+)([^?#]*)"#
        guard let m = t.range(of: padrao, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let achado = String(t[m])
        let partes = achado.components(separatedBy: "://")
        guard partes.count >= 2 else { return nil }
        let esquema = partes[0].lowercased()
        let resto = partes.dropFirst().joined(separator: "://")
        let host = String(resto.prefix { $0 != "/" })
        var caminho = String(resto.dropFirst(host.count))
        let hostOk = #"^(?:[A-Za-z0-9](?:[A-Za-z0-9.\-]*[A-Za-z0-9])?|\[[0-9A-Fa-f:.]+\])(?::\d{1,5})?$"#
        guard host.range(of: hostOk, options: .regularExpression) != nil else { return nil }
        if ["/get.php", "/player_api.php", "/panel_api.php", "/c", "/c/"].contains(caminho.lowercased()) { caminho = "" }
        while caminho.hasSuffix("/") { caminho.removeLast() }
        return "\(esquema)://\(host.lowercased())\(caminho)"
    }

    /// Reconhece o link de uma conta Xtream (`get.php` ou `player_api.php` com usuário e senha).
    static func deLink(_ link: String) -> Conta? {
        let t = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let r = t.range(of: #"^(https?://[^/?#]+(?:/[^?#]*?)?)/(?:get|player_api)\.php\?(.*)$"#,
                              options: [.regularExpression, .caseInsensitive]) else { return nil }
        let todo = String(t[r])
        guard let corte = todo.range(of: #"/(?:get|player_api)\.php\?"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let prefixo = String(todo[..<corte.lowerBound])
        let consulta = String(todo[corte.upperBound...]).components(separatedBy: "#")[0]
        var params: [String: String] = [:]
        for par in consulta.split(separator: "&") {
            guard let i = par.firstIndex(of: "=") else { continue }
            let k = String(par[..<i]).lowercased()
            let v = String(par[par.index(after: i)...])
            params[k] = v.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? v
        }
        guard let u = params["username"], !u.isEmpty, let s = params["password"], !s.isEmpty,
              let base = normalizarServidor(prefixo) else { return nil }
        return Conta(base: base, usuario: u, senha: s)
    }

    /// O link a guardar a partir do que a pessoa digitou. Com usuário e senha, o
    /// primeiro campo é o servidor; sem eles, é o link da lista.
    static func linkDoFormulario(_ digitado: String, usuario: String, senha: String) -> Result<String, Erro> {
        let u = usuario.trimmingCharacters(in: .whitespacesAndNewlines)
        if u.isEmpty != senha.isEmpty {
            return .failure(Erro(texto: "Usuário e senha andam juntos: preencha os dois, ou deixe os dois em branco se a lista é só um link"))
        }
        if u.isEmpty { return .success(digitado.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard let base = normalizarServidor(digitado) else { return .failure(Erro(texto: "Esse servidor não parece um endereço válido")) }
        return .success(linkM3u(base: base, usuario: u, senha: senha))
    }

    // MARK: - Resposta da API (sem rede: testável)

    /// O servidor não falou o idioma Xtream (sem `player_api.php`): resta tentar o M3U.
    static let semApi = "\u{0}sem-api"

    private static func texto(_ v: Any?) -> String {
        guard let v, !(v is NSNull) else { return "" }
        return "\(v)".trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `""` se a conta vale; `semApi`; ou o motivo da recusa.
    static func verificarEntrada(_ json: Data) -> String {
        guard let raiz = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any],
              let info = raiz["user_info"] as? [String: Any] else { return semApi }
        let auth = texto(info["auth"]).lowercased()
        if auth != "1" && auth != "true" { return "Usuário ou senha incorretos" }
        let status = texto(info["status"])
        if !status.isEmpty && status.lowercased() != "active" { return "Essa conta não está ativa (\(status))" }
        if let exp = Double(texto(info["exp_date"])), exp > 0, exp <= Date().timeIntervalSince1970 { return "Essa conta venceu" }
        return ""
    }

    private static func categorias(_ json: Data) -> [String: String] {
        guard let a = (try? JSONSerialization.jsonObject(with: json)) as? [[String: Any]] else { return [:] }
        return Dictionary(a.map { (texto($0["category_id"]), texto($0["category_name"])) }, uniquingKeysWith: { $1 })
    }

    private static func chave(_ nome: String) -> String {
        String(nome.folding(options: .diacriticInsensitive, locale: nil).lowercased()
            .filter { ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") })
    }

    /// `get_live_streams` + categorias -> canais, com `.m3u8` e `.ts` como duas fontes.
    static func canaisDaApi(_ conta: Conta, streams: Data, categorias cats: Data, limite: Int = 20_000) -> [CanalLido] {
        guard let lista = (try? JSONSerialization.jsonObject(with: streams)) as? [[String: Any]] else { return [] }
        let mapa = categorias(cats)
        var ordem: [String] = []
        var porNome: [String: CanalLido] = [:]
        for o in lista {
            if ordem.count >= limite { break }
            let id = texto(o["stream_id"])
            if id.isEmpty { continue }
            var nome = texto(o["name"])
            if nome.isEmpty { nome = "Canal \(ordem.count + 1)" }
            let grupo = mapa[texto(o["category_id"])].flatMap { $0.isEmpty ? nil : $0 }
            let icone = texto(o["stream_icon"])
            let logo = icone.lowercased().hasPrefix("http") ? icone : nil
            let fontes = [conta.canal(id, "m3u8"), conta.canal(id, "ts")]
            let k = chave(nome)
            if var antigo = porNome[k] {
                antigo.grupo = antigo.grupo ?? grupo
                antigo.logo = antigo.logo ?? logo
                antigo.fontes += fontes
                porNome[k] = antigo
            } else {
                ordem.append(k)
                porNome[k] = CanalLido(nome: nome, grupo: grupo, logo: logo, fontes: fontes)
            }
        }
        return ordem.compactMap { porNome[$0] }
    }

    /// Os canais como texto M3U, para passar pelo leitor que o app já tem (que
    /// põe adulto na seção Adulto, mesmo nome vira uma fonte a mais etc.).
    static func comoM3u(_ canais: [CanalLido]) -> String {
        func limpo(_ s: String) -> String { s.replacingOccurrences(of: "\"", with: "'").replacingOccurrences(of: "\n", with: " ") }
        var out = ["#EXTM3U"]
        for c in canais {
            var tags = "#EXTINF:-1"
            if let l = c.logo { tags += " tvg-logo=\"\(limpo(l))\"" }
            if let g = c.grupo { tags += " group-title=\"\(limpo(g))\"" }
            // Uma entrada por fonte: o leitor junta as de mesmo nome num canal só.
            for f in c.fontes {
                out.append("\(tags),\(limpo(c.nome).replacingOccurrences(of: ",", with: " "))")
                out.append(f)
            }
        }
        return out.joined(separator: "\n")
    }

    // MARK: - Rede

    private static func buscar(_ url: String) async throws -> Data {
        guard let u = URL(string: url) else { throw Erro(texto: "Link inválido") }
        var pedido = URLRequest(url: u, timeoutInterval: 60)
        pedido.setValue("VLC/3.0.20 LibVLC/3.0.20", forHTTPHeaderField: "User-Agent")
        let (dados, resposta) = try await URLSession.shared.data(for: pedido)
        if let http = resposta as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw Erro(texto: "O servidor recusou o pedido (\(http.statusCode))")
        }
        return dados
    }

    /// Entra na conta e devolve a lista como texto M3U. Erros em português, sem o link nem a senha.
    static func m3uDosCanais(_ conta: Conta) async throws -> String {
        func doM3u() async throws -> String {
            let dados: Data
            do { dados = try await buscar(conta.linkM3u) } catch let e as Erro { throw e } catch { throw Erro(texto: "Não consegui falar com o servidor") }
            let texto = String(decoding: dados, as: UTF8.self)
            guard texto.contains("#EXTINF") else { throw Erro(texto: "Essa conta não tem canais ao vivo") }
            return texto
        }
        let motivo: String
        do { motivo = verificarEntrada(try await buscar(conta.api())) } catch is Erro { return try await doM3u() } catch {
            throw Erro(texto: "Não consegui falar com o servidor")
        }
        if motivo == semApi { return try await doM3u() }
        if !motivo.isEmpty { throw Erro(texto: motivo) }
        do {
            let cats = (try? await buscar(conta.api("get_live_categories"))) ?? Data("[]".utf8)
            let canais = canaisDaApi(conta, streams: try await buscar(conta.api("get_live_streams")), categorias: cats)
            if canais.isEmpty { return try await doM3u() }
            return comoM3u(canais)
        } catch {
            return try await doM3u()
        }
    }
}
