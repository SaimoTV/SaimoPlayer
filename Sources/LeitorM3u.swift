import Foundation

// Leitor de lista .m3u do usuário (puro: sem rede, sem tela, só Foundation).
//
// Segue a especificação única dos cinco clientes e é conferido contra o
// gabarito por `scripts/testar_minhas_listas.sh`. Nunca falha: texto estranho
// vira lista vazia.

struct FonteLida: Equatable, Sendable, Codable {
    var url: String
    var referer: String?
    var ua: String?
    var keyId: String?
    var key: String?
    var qualidade: String?
}

struct CanalLido: Equatable, Sendable, Codable {
    var nome: String
    var grupo: String?
    var logo: String?
    var fontes: [FonteLida]
}

enum LeitorM3u {
    static let limiteDeCanais = 20_000

    private static let tagRuim = try! NSRegularExpression(
        pattern: #"\d{3,4}[pi]|not 24/7|geo-?blocked|backup|vertical|\bsd\b|\bhd\b|fhd|\b4k\b"#,
        options: [.caseInsensitive])
    private static let resolucao = try! NSRegularExpression(
        pattern: #"(\d{3,4}[pi])"#, options: [.caseInsensitive])
    private static let fimComTag = try! NSRegularExpression(
        pattern: #"\s*[\(\[]([^\)\]]*)[\)\]]\s*$"#)
    private static let chaveClear = try! NSRegularExpression(
        pattern: #"^[0-9a-fA-F]{32}:[0-9a-fA-F]{32}$"#)
    private static let atributos: [String: NSRegularExpression] = {
        var out: [String: NSRegularExpression] = [:]
        for nome in ["tvg-id", "tvg-name", "tvg-logo", "group-title"] {
            out[nome] = try! NSRegularExpression(
                pattern: #"(?:^|[\s:])"# + NSRegularExpression.escapedPattern(for: nome) + #"="([^"]*)""#)
        }
        return out
    }()

    private struct Pendente {
        var exibido = ""
        var tvgName: String?
        var tvgId: String?
        var logo: String?
        var grupo: String?
    }

    private struct Opcoes {
        var extgrp: String?
        var referer: String?
        var ua: String?
        var licTipo = ""
        var licChave = ""
    }

    // MARK: - Utilidades

    /// Chave de comparação do nome: minúsculas, sem acentos, só letras e números.
    static func chave(_ nome: String) -> String {
        var out = String.UnicodeScalarView()
        for s in nome.decomposedStringWithCanonicalMapping.unicodeScalars
        where s.properties.generalCategory != .nonspacingMark {
            out.append(s)
        }
        var chave = ""
        for s in String(out).lowercased().unicodeScalars {
            let v = s.value
            if (v >= 0x61 && v <= 0x7A) || (v >= 0x30 && v <= 0x39) { chave.unicodeScalars.append(s) }
        }
        return chave
    }

    private static func primeiro(_ re: NSRegularExpression, em texto: String, grupo: Int = 0) -> String? {
        let ns = texto as NSString
        guard let m = re.firstMatch(in: texto, range: NSRange(location: 0, length: ns.length)),
              m.range(at: grupo).location != NSNotFound else { return nil }
        return ns.substring(with: m.range(at: grupo))
    }

    private static func casa(_ re: NSRegularExpression, _ texto: String) -> Bool {
        re.firstMatch(in: texto, range: NSRange(location: 0, length: (texto as NSString).length)) != nil
    }

    private static func aparar(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func atributo(_ linha: String, _ nome: String) -> String? {
        guard let re = atributos[nome], let v = primeiro(re, em: linha, grupo: 1) else { return nil }
        return aparar(v)
    }

    /// O texto depois da primeira vírgula fora de aspas.
    private static func nomeExibido(_ linha: String) -> String {
        var dentro = false
        var i = linha.startIndex
        while i < linha.endIndex {
            let c = linha[i]
            if c == "\"" { dentro.toggle() }
            else if c == ",", !dentro { return aparar(String(linha[linha.index(after: i)...])) }
            i = linha.index(after: i)
        }
        return ""
    }

    /// Tira do fim os "(720p)", "[Not 24/7]"...; devolve o nome e a resolução, se houver.
    private static func tirarTags(_ nome: String) -> (String, String?) {
        var nome = nome
        var qualidade: String?
        while true {
            let ns = nome as NSString
            guard let m = fimComTag.firstMatch(in: nome, range: NSRange(location: 0, length: ns.length)),
                  m.numberOfRanges > 1 else { break }
            let dentro = ns.substring(with: m.range(at: 1))
            guard casa(tagRuim, dentro) else { break }
            if qualidade == nil, let r = primeiro(resolucao, em: dentro, grupo: 1) {
                qualidade = r.lowercased()
            }
            nome = ns.substring(to: m.range.location)
        }
        return (aparar(nome), qualidade)
    }

    private static func ehHttp(_ s: String) -> Bool {
        let b = s.lowercased()
        return b.hasPrefix("http://") || b.hasPrefix("https://")
    }

    /// Divide em duas na primeira ocorrência do separador.
    private static func partir(_ s: String, em sep: Character) -> (String, String)? {
        guard let i = s.firstIndex(of: sep) else { return nil }
        return (String(s[..<i]), String(s[s.index(after: i)...]))
    }

    // MARK: - Leitura

    /// Lê o texto de uma lista .m3u. Nunca lança: texto estranho vira lista vazia.
    static func ler(_ texto: String) -> [CanalLido] {
        var canais: [CanalLido] = []
        var indice: [String: Int] = [:]
        var pend: Pendente?
        var opts = Opcoes()

        var inicio = texto.unicodeScalars.startIndex
        let fim = texto.unicodeScalars.endIndex
        while inicio < fim, texto.unicodeScalars[inicio] == "\u{FEFF}" {
            inicio = texto.unicodeScalars.index(after: inicio)
        }
        let corpo = texto.unicodeScalars[inicio...]
        // Dividir em \n e em \r (sem juntar o par): linha vazia é ignorada, então
        // dá no mesmo que tratar "\r\n" como uma quebra só.
        for pedaco in corpo.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let linha = aparar(String(pedaco))
            if linha.isEmpty { continue }
            if linha.uppercased().hasPrefix("#EXTM3U") { continue }

            if linha.hasPrefix("#EXTINF") {
                pend = Pendente(exibido: nomeExibido(linha),
                                tvgName: atributo(linha, "tvg-name"),
                                tvgId: atributo(linha, "tvg-id"),
                                logo: atributo(linha, "tvg-logo"),
                                grupo: atributo(linha, "group-title"))
                opts = Opcoes()
                continue
            }
            if linha.hasPrefix("#EXTGRP:") {
                opts.extgrp = aparar(String(linha.dropFirst(8)))
                continue
            }
            if linha.hasPrefix("#EXTVLCOPT:") {
                if let (k, v) = partir(String(linha.dropFirst(11)), em: "=") {
                    let k = aparar(k).lowercased()
                    if k == "http-referrer" || k == "http-referer" { opts.referer = aparar(v) }
                    else if k == "http-user-agent" { opts.ua = aparar(v) }
                }
                continue
            }
            if linha.hasPrefix("#KODIPROP:") {
                if let (k, v) = partir(String(linha.dropFirst(10)), em: "=") {
                    let k = aparar(k).lowercased()
                    if k == "inputstream.adaptive.license_type" { opts.licTipo = aparar(v).lowercased() }
                    else if k == "inputstream.adaptive.license_key" { opts.licChave = aparar(v) }
                }
                continue
            }
            if linha.hasPrefix("#") { continue }

            // Linha de endereço, com cabeçalhos no estilo Kodi: url|User-Agent=..&Referer=..
            var url = linha
            var extra: [String: String] = [:]
            if let (antes, depois) = partir(linha, em: "|"), depois.contains("=") {
                url = aparar(antes)
                for par in depois.split(separator: "&", omittingEmptySubsequences: false) {
                    if let (k, v) = partir(String(par), em: "=") {
                        extra[aparar(k).lowercased()] = aparar(v)
                    }
                }
            }
            guard ehHttp(url) else { pend = nil; opts = Opcoes(); continue }

            let p = pend ?? Pendente()
            var bruto = p.exibido
            if bruto.isEmpty { bruto = p.tvgName ?? "" }
            if bruto.isEmpty { bruto = p.tvgId ?? "" }
            var nome = "", qual: String?
            if !bruto.isEmpty { (nome, qual) = tirarTags(bruto) }
            if nome.isEmpty { nome = "Canal \(canais.count + 1)" }

            var grupo = p.grupo.flatMap { $0.isEmpty ? nil : $0 } ?? opts.extgrp.flatMap { $0.isEmpty ? nil : $0 }
            if let g = grupo, let (primeiro, _) = partir(g, em: ";") { grupo = aparar(primeiro) }
            if grupo?.isEmpty == true { grupo = nil }
            let logo = p.logo.flatMap { ehHttp($0) ? $0 : nil }

            var fonte = FonteLida(url: url,
                                  referer: nonVazio(opts.referer) ?? nonVazio(extra["referer"]),
                                  ua: nonVazio(opts.ua) ?? nonVazio(extra["user-agent"]),
                                  keyId: nil, key: nil, qualidade: qual)
            if opts.licTipo.contains("clearkey"), casa(chaveClear, opts.licChave),
               let (kid, chave) = partir(opts.licChave.lowercased(), em: ":") {
                fonte.keyId = kid
                fonte.key = chave
            }

            let k = Self.chave(nome)
            if let i = indice[k] {
                if !canais[i].fontes.contains(where: { $0.url == url }) { canais[i].fontes.append(fonte) }
                if canais[i].grupo == nil { canais[i].grupo = grupo }
                if canais[i].logo == nil { canais[i].logo = logo }
            } else if canais.count < limiteDeCanais {
                indice[k] = canais.count
                canais.append(CanalLido(nome: nome, grupo: grupo, logo: logo, fontes: [fonte]))
            }
            pend = nil
            opts = Opcoes()
        }
        return canais
    }

    private static func nonVazio(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }

    /// A resposta baixada serve como lista: começa (depois do BOM e dos espaços)
    /// com #EXTM3U ou tem ao menos um #EXTINF.
    static func pareceLista(_ texto: String) -> Bool {
        let inicio = texto.unicodeScalars.drop(while: { $0 == "\u{FEFF}" })
        let corte = String(String.UnicodeScalarView(inicio.prefix(4096)))
        if aparar(corte).uppercased().hasPrefix("#EXTM3U") { return true }
        return texto.contains("#EXTINF")
    }

    // MARK: - Conteúdo adulto

    private static let adulto = try! NSRegularExpression(
        pattern: #"(?:^|[^a-z0-9])(?:adult|adulto|adultos|xxx|porn|porno|sexo|sex|erotic|erotico|hentai)(?:[^a-z0-9]|$)|\+18|18\+"#)

    /// Grupo ou nome de conteúdo adulto: só apareceria depois do desbloqueio do
    /// controle parental. "Adult Swim" é desenho animado e fica de fora da regra.
    static func ehRestrito(nome: String, grupo: String?) -> Bool {
        var sem = String.UnicodeScalarView()
        for s in "\(grupo ?? "") \(nome)".decomposedStringWithCanonicalMapping.unicodeScalars
        where s.properties.generalCategory != .nonspacingMark {
            sem.append(s)
        }
        let texto = String(sem).lowercased().replacingOccurrences(of: "adult swim", with: " ")
        return casa(adulto, texto)
    }
}
