import Foundation

/// Canal, filme ou episódio: a classificação dos itens de uma lista M3U.
/// Regras em docs/listas-m3u.md; referência em scripts/classificar_m3u.py e
/// gabarito em docs/exemplos/listas/ (Tests/ClassificarTeste.swift confere).
enum Classificar {

    struct Marca: Equatable {
        var temporada: Int
        var episodio: Int
        /// Em caracteres do nome.
        var inicio: Int
        var forte: Bool
    }

    enum Tipo: Equatable {
        case canal
        case filme
        case episodio(Marca)
    }

    static let video: Set<String> = ["mp4", "mkv", "avi", "mov", "wmv", "flv", "webm", "m4v", "mpg", "mpeg", "3gp", "divx", "ogv", "vob"]
    private static let tipoCanal: Set<String> = ["live", "channel", "tv", "radio"]
    private static let tipoFilme: Set<String> = ["movie", "movies", "vod", "film", "filme"]
    private static let tipoSerie: Set<String> = ["series", "serie", "tvshow", "show", "episode"]
    private static let segFilme: Set<String> = ["movie", "movies", "vod", "filmes"]
    private static let segSerie: Set<String> = ["series", "serie"]
    private static let palavrasAcervo: Set<String> = ["filme", "filmes", "movie", "movies", "vod", "serie", "series", "novela", "novelas",
                                                     "anime", "animes", "dorama", "doramas", "temporada", "temporadas"]
    static let separadores: Set<Character> = [" ", "-", ":", "|", ".", "_", "(", "[", "\u{2013}", "\u{2014}", "\t"]
    private static let tagsLeg: Set<String> = ["l", "leg", "legendado", "legendada"]
    private static let tagsDub: Set<String> = ["d", "dub", "dublado", "dublada", "nac", "nacional"]

    /// Minúsculas sem acento, um caractere para cada caractere do original.
    static func dobrar(_ t: String) -> [Character] {
        t.map { c in
            // ASCII (quase tudo) sem passar pelo folding, que é caro.
            if let a = c.asciiValue { return a >= 65 && a <= 90 ? Character(UnicodeScalar(a + 32)) : c }
            return String(c).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased().first ?? c
        }
    }

    static func dobrarTexto(_ t: String) -> String { String(dobrar(t)) }

    private static func alnum(_ c: Character) -> Bool { c.isLetter || c.isNumber }
    private static func digito(_ c: Character) -> Bool { c >= "0" && c <= "9" }

    private static func inicioDePalavra(_ n: [Character], _ i: Int) -> Bool { i == 0 || !alnum(n[i - 1]) }

    private static func lerDigitos(_ n: [Character], _ j: Int, _ maximo: Int) -> (Int, Int)? {
        var k = j
        while k < n.count, digito(n[k]), k - j < maximo { k += 1 }
        if k == j || (k < n.count && digito(n[k])) { return nil }
        guard let v = Int(String(n[j..<k])) else { return nil }
        return (v, k)
    }

    private static func pular(_ n: [Character], _ j: Int, _ chars: Set<Character>) -> Int {
        var j = j
        while j < n.count, chars.contains(n[j]) { j += 1 }
        return j
    }

    private static func comeca(_ n: [Character], _ j: Int, _ p: String) -> Bool {
        let p = Array(p)
        return j + p.count <= n.count && Array(n[j..<(j + p.count)]) == p
    }

    private static let palavrasEp = ["episodio", "episode", "capitulo", "cap", "ep"]

    private static func palavraDeEpisodio(_ n: [Character], _ j: Int) -> Int? {
        for p in palavrasEp where comeca(n, j, p) {
            var k = j + p.count
            if k < n.count, n[k].isLetter { continue }
            k = pular(n, k, ["."])
            k = pular(n, k, [" "])
            if let (e, _) = lerDigitos(n, k, 4) { return e }
        }
        return nil
    }

    private static func lerDigitosAte(_ n: [Character], _ j: Int, _ maximo: Int, _ seguinte: Character) -> (Int, Int)? {
        var k = j
        while k < n.count, digito(n[k]) { k += 1 }
        if k == j || k - j > maximo || k >= n.count || n[k] != seguinte { return nil }
        guard let v = Int(String(n[j..<k])) else { return nil }
        return (v, k)
    }

    /// A marca de episódio (S01E02, 1x02, Temporada 2 Episódio 5, Ep 12…).
    static func marca(_ nome: String) -> Marca? {
        let n = dobrar(nome)
        var fraca: Marca?
        for i in 0..<n.count {
            guard inicioDePalavra(n, i) else { continue }
            let c = n[i]
            if c == "s" || c == "t", let (t, j0) = lerDigitos(n, i + 1, 3) {
                var j = pular(n, j0, [" ", ".", "_", "-"])
                if j < n.count, n[j] == "e" || (c == "s" && n[j] == "x") {
                    j += 1
                    if j < n.count, n[j] == "p" { j += 1 }
                    j = pular(n, j, [" ", "."])
                    if let (e, _) = lerDigitos(n, j, 4) {
                        return Marca(temporada: t, episodio: e, inicio: i, forte: true)
                    }
                }
            }
            if digito(c), let (t, j) = lerDigitosAte(n, i, 2, "x"), let (e, k) = lerDigitos(n, j + 1, 3),
               k == n.count || !alnum(n[k]) {
                return Marca(temporada: t, episodio: e, inicio: i, forte: true)
            }
            for p in ["temporada", "season"] where comeca(n, i, p) {
                let j0 = pular(n, i + p.count, [" "])
                if let (t, j) = lerDigitos(n, j0, 3) {
                    for k in j..<min(j + 13, n.count) where inicioDePalavra(n, k) {
                        if let e = palavraDeEpisodio(n, k) {
                            return Marca(temporada: t, episodio: e, inicio: i, forte: true)
                        }
                    }
                }
            }
            if fraca == nil, let e = palavraDeEpisodio(n, i) {
                fraca = Marca(temporada: 1, episodio: e, inicio: i, forte: false)
            }
        }
        return fraca
    }

    private static func caminho(_ url: String) -> [String] {
        var u = Substring(url)
        if let i = u.firstIndex(of: "#") { u = u[..<i] }
        if let i = u.firstIndex(of: "?") { u = u[..<i] }
        if let r = u.range(of: "://") {
            let resto = u[r.upperBound...]
            u = resto.firstIndex(of: "/").map { resto[resto.index(after: $0)...] } ?? ""
        }
        return u.lowercased().split(separator: "/").map(String.init)
    }

    private static func palavras(_ t: String) -> [String] {
        t.split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init)
    }

    private static func grupoDeAcervo(_ grupo: String) -> Bool {
        let g = dobrarTexto(grupo)
        let ws = palavras(g)
        guard ws.contains(where: { palavrasAcervo.contains($0) }) else { return false }
        if g.contains("24h") || g.contains("24 horas") || g.contains("24/7") || g.contains("ao vivo") { return false }
        return !ws.contains(where: { ["canal", "canais", "live"].contains($0) })
    }

    static func anoNoFim(_ nome: String) -> Bool {
        let c = Array(nome.trimmingCharacters(in: .whitespaces))
        let n = c.count
        guard n >= 6, c[n - 1] == ")", c[n - 6] == "(" else { return false }
        guard c[(n - 5)..<(n - 1)].allSatisfy(digito) else { return false }
        return (c[n - 5] == "1" && c[n - 4] == "9") || (c[n - 5] == "2" && c[n - 4] == "0")
    }

    private static func anoDoFim(_ nome: String) -> String {
        let c = Array(nome.trimmingCharacters(in: .whitespaces))
        return String(c[(c.count - 5)..<(c.count - 1)])
    }

    static func tipo(url: String, nome: String, grupo: String, declarado: String) -> Tipo {
        let m = marca(nome)
        let d = declarado.trimmingCharacters(in: .whitespaces).lowercased()
        if tipoCanal.contains(d) { return .canal }
        var acervo = tipoFilme.contains(d) || tipoSerie.contains(d)
        let segs = caminho(url)
        if !acervo {
            for s in segs.dropLast() {
                if segFilme.contains(s) || segSerie.contains(s) { acervo = true; break }
                if s == "live" { return .canal }
            }
            // Canal Xtream sem prefixo: /usuario/senha/123(.ts|.m3u8).
            if !acervo, segs.count == 3 {
                let partes = segs[2].split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
                let num = String(partes[0]), ext = partes.count > 1 ? String(partes[1]) : ""
                if !num.isEmpty, num.allSatisfy(digito), ["", "ts", "m3u8"].contains(ext) { return .canal }
            }
        }
        if !acervo, let ultimo = segs.last, let ponto = ultimo.lastIndex(of: ".") {
            acervo = video.contains(String(ultimo[ultimo.index(after: ponto)...]))
        }
        if acervo { return m.map { .episodio($0) } ?? .filme }
        if grupoDeAcervo(grupo) {
            if let m, m.forte { return .episodio(m) }
            if anoNoFim(limpar(nome).0) { return .filme }
        }
        return .canal
    }

    // MARK: - Títulos

    private static func resolucao(_ t: String) -> Bool {
        let c = Array(t)
        var i = 0
        while i < c.count {
            if digito(c[i]) {
                let ini = i
                while i < c.count, digito(c[i]) { i += 1 }
                if i - ini >= 3, i < c.count, "pPiI".contains(c[i]) { return true }
            } else { i += 1 }
        }
        return false
    }

    private static func temPalavra(_ t: String, _ p: String) -> Bool {
        let c = Array(t), pc = Array(p)
        func palavra(_ x: Character) -> Bool { x.isLetter || x.isNumber || x == "_" }
        guard c.count >= pc.count else { return false }
        for i in 0...(c.count - pc.count) where Array(c[i..<(i + pc.count)]) == pc {
            if (i == 0 || !palavra(c[i - 1])) && (i + pc.count >= c.count || !palavra(c[i + pc.count])) { return true }
        }
        return false
    }

    private static func tagRuim(_ conteudo: String) -> Bool {
        let t = conteudo.lowercased()
        return resolucao(t) || t.contains("not 24/7") || t.contains("geoblocked") || t.contains("geo-blocked")
            || t.contains("backup") || t.contains("vertical") || temPalavra(t, "sd") || temPalavra(t, "hd")
            || t.contains("fhd") || temPalavra(t, "4k")
    }

    /// Tira tags de qualidade e de versão; devolve (nome, versão).
    static func limpar(_ nome: String) -> (String, String?) {
        var versao: String?
        var nome = nome.trimmingCharacters(in: .whitespaces)
        while true {
            let t = String(nome.reversed().drop(while: { $0 == " " }).reversed())
            if let fecha = t.last, fecha == ")" || fecha == "]" {
                let abre: Character = fecha == ")" ? "(" : "["
                if let pos = t.lastIndex(of: abre) {
                    let conteudo = String(t[t.index(after: pos)..<t.index(before: t.endIndex)]).trimmingCharacters(in: .whitespaces)
                    let c = dobrarTexto(conteudo)
                    if tagsLeg.contains(c) { versao = versao ?? "leg"; nome = String(t[..<pos]); continue }
                    if tagsDub.contains(c) { versao = versao ?? "dub"; nome = String(t[..<pos]); continue }
                    if tagRuim(conteudo) { nome = String(t[..<pos]); continue }
                }
            }
            if let espaco = t.lastIndex(of: " ") {
                let ultima = dobrarTexto(String(t[t.index(after: espaco)...]))
                if ["leg", "legendado", "legendada"].contains(ultima) {
                    versao = versao ?? "leg"; nome = String(t[..<espaco]); continue
                }
            }
            nome = t
            break
        }
        // Tags de versão no meio ("Filme [L] (2020)").
        for (abre, fecha) in [("[", "]"), ("(", ")")] as [(Character, Character)] {
            var de = nome.startIndex
            while let i = nome[de...].firstIndex(of: abre) {
                guard let f = nome[nome.index(after: i)...].firstIndex(of: fecha) else { break }
                let c = dobrarTexto(String(nome[nome.index(after: i)..<f]).trimmingCharacters(in: .whitespaces))
                if tagsLeg.contains(c) || tagsDub.contains(c) {
                    versao = versao ?? (tagsLeg.contains(c) ? "leg" : "dub")
                    let antes = String(nome[..<i]).trimmingCharacters(in: .whitespaces)
                    let depois = String(nome[nome.index(after: f)...]).trimmingCharacters(in: .whitespaces)
                    let off = antes.count
                    nome = (antes + " " + depois).trimmingCharacters(in: .whitespaces)
                    de = nome.index(nome.startIndex, offsetBy: min(off, nome.count))
                } else {
                    de = nome.index(after: f)
                }
            }
        }
        return (nome.split(whereSeparator: \.isWhitespace).joined(separator: " "), versao)
    }

    private static func anoRepetido(_ nome: String) -> String {
        var t = nome.trimmingCharacters(in: .whitespaces)
        while anoNoFim(t) {
            let antes = String(t.dropLast(6)).trimmingCharacters(in: .whitespaces)
            guard anoNoFim(antes), anoDoFim(antes) == anoDoFim(t) else { break }
            t = antes
        }
        return t
    }

    private static func semExtensao(_ nome: String) -> String {
        let t = nome.trimmingCharacters(in: .whitespaces)
        if let p = t.lastIndex(of: "."), video.contains(t[t.index(after: p)...].lowercased()) {
            return String(t[..<p]).trimmingCharacters(in: .whitespaces)
        }
        return t
    }

    private static func versaoDoGrupo(_ grupo: String) -> String {
        dobrarTexto(grupo).contains("legendad") ? "leg" : "dub"
    }

    static func tituloDoFilme(_ nome: String, grupo: String) -> (titulo: String, ano: String, versao: String) {
        let (t0, versao) = limpar(semExtensao(nome))
        let t = anoRepetido(t0)
        return (t, anoNoFim(t) ? anoDoFim(t) : "", versao ?? versaoDoGrupo(grupo))
    }

    private static func semSeparadoresNoFim(_ t: String) -> String {
        String(t.reversed().drop(while: { separadores.contains($0) }).reversed())
    }

    static func tituloDaSerie(_ nome: String, inicio: Int, grupo: String) -> (titulo: String, ano: String, versao: String) {
        let antes = String(nome.prefix(inicio)), depois = String(nome.dropFirst(inicio))
        let (t0, v0) = limpar(semSeparadoresNoFim(antes))
        var t = semSeparadoresNoFim(t0).trimmingCharacters(in: .whitespaces)
        let versao = v0 ?? limpar(depois).1
        t = anoRepetido(t)
        var ano = ""
        if anoNoFim(t) {
            ano = anoDoFim(t)
            t = semSeparadoresNoFim(String(t.dropLast(6))).trimmingCharacters(in: .whitespaces)
        }
        if t.isEmpty {
            let g = grupo.trimmingCharacters(in: .whitespaces)
            t = g.isEmpty ? "Série" : g
        }
        return (t, ano, versao ?? versaoDoGrupo(grupo))
    }
}
