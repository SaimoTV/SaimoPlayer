import Foundation

/// O acervo de filmes e séries de uma lista M3U/Xtream, no formato Saimo
/// (docs/formato-saimo.md, item 5; regras em docs/listas-m3u.md). Gerado ao
/// adicionar ou renovar a lista, numa pasta só dela; o `Vod` lê essa pasta
/// como lê o acervo publicado, sem `base:` (endereços completos).
enum AcervoLista {

    struct Item: Sendable {
        var tipo: Classificar.Tipo
        var nome: String
        var grupo: String
        var url: String
        var logo: String?
    }

    struct Resumo: Sendable, Equatable {
        var filmes = 0
        var series = 0
    }

    /// Separa a lista: o texto só com os canais (para o leitor de canais) e os
    /// filmes e episódios. Adulto não entra no acervo.
    nonisolated static func separar(_ texto: String) -> (canais: String, itens: [Item]) {
        var canais = "#EXTM3U\n"
        var itens: [Item] = []
        var pendentes: [Substring] = []
        var extinf: Substring?
        var extgrp = ""
        func atributo(_ linha: Substring, _ chave: String) -> String {
            guard let r = linha.range(of: "\(chave)=\"") else { return "" }
            return String(linha[r.upperBound...].prefix { $0 != "\"" }).trimmingCharacters(in: .whitespaces)
        }
        for bruta in texto.split(omittingEmptySubsequences: true, whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == "\r\n" }) {
            let linha = bruta.drop(while: { $0 == " " || $0 == "\t" || $0 == "\u{feff}" })
            if linha.isEmpty || linha.uppercased().hasPrefix("#EXTM3U") { continue }
            if linha.hasPrefix("#EXTINF") {
                extinf = linha
                pendentes = [linha]
                extgrp = ""
                continue
            }
            if linha.hasPrefix("#") {
                if linha.hasPrefix("#EXTGRP:") { extgrp = linha.dropFirst(8).trimmingCharacters(in: .whitespaces) }
                pendentes.append(linha)
                continue
            }
            let url = linha.trimmingCharacters(in: .whitespaces)
            let semOpcoes = url.split(separator: "|", maxSplits: 1).first.map(String.init) ?? url
            let inf = extinf ?? ""
            var nome = ""
            var dentro = false
            for (i, c) in zip(inf.indices, inf) {
                if c == "\"" { dentro.toggle() } else if c == ",", !dentro {
                    nome = inf[inf.index(after: i)...].trimmingCharacters(in: .whitespaces)
                    break
                }
            }
            if nome.isEmpty { nome = atributo(inf, "tvg-name") }
            var grupo = atributo(inf, "group-title")
            if grupo.isEmpty { grupo = extgrp }
            if let p = grupo.firstIndex(of: ";") { grupo = grupo[..<p].trimmingCharacters(in: .whitespaces) }
            var declarado = atributo(inf, "tvg-type")
            if declarado.isEmpty { declarado = atributo(inf, "type") }
            if declarado.isEmpty { declarado = atributo(inf, "media-type") }
            let tipo = Classificar.tipo(url: semOpcoes, nome: nome, grupo: grupo, declarado: declarado)
            if tipo == .canal {
                for p in pendentes { canais += p; canais += "\n" }
                canais += url
                canais += "\n"
            } else if !adulto(nome: nome, grupo: grupo) {
                let logo = atributo(inf, "tvg-logo")
                itens.append(Item(tipo: tipo, nome: nome, grupo: grupo, url: semOpcoes,
                                  logo: logo.lowercased().hasPrefix("http") ? logo : nil))
            }
            extinf = nil
            pendentes = []
            extgrp = ""
        }
        return (canais, itens)
    }

    nonisolated static func adulto(nome: String, grupo: String) -> Bool {
        let g = grupo.lowercased()
        return Categoria.de(nome) == .adulto || ["adult", "xxx", "+18", "18+", "porn", "sexy"].contains { g.contains($0) }
    }

    /// A letra do título (item 5.1 do formato).
    nonisolated static func letra(_ titulo: String) -> String {
        guard let c = Classificar.dobrar(titulo).first(where: { !$0.isWhitespace }),
              c.isASCII, c.isLetter else { return "#" }
        return String(c).uppercased()
    }

    /// Nome do arquivo no disco: `#` vira `hash`, como no cache do acervo.
    nonisolated static func noDisco(_ nome: String) -> String {
        nome.replacingOccurrences(of: "%23", with: "hash").replacingOccurrences(of: "#", with: "hash")
    }

    private static func chave(_ t: String) -> String {
        String(Classificar.dobrar(t).filter { $0.isASCII && ($0.isLetter || $0.isNumber) })
    }

    private static func campo(_ t: String) -> String {
        t.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ").trimmingCharacters(in: .whitespaces)
    }

    private static func fonte(_ url: String) -> String {
        url.replacingOccurrences(of: ",", with: "%2C").replacingOccurrences(of: "\t", with: "")
    }

    private static func genero(_ grupo: String) -> String {
        campo(String(grupo.drop(while: { !($0.isLetter || $0.isNumber) }))).replacingOccurrences(of: ",", with: " ")
    }

    private final class Titulo {
        let titulo: String, ano: String
        var capa: String?
        var generos: [String] = []
        var versoes: [(String, [String])] = []
        var episodios: [(chave: String, t: Int, e: Int, v: String, urls: [String])] = []
        var indice: [String: Int] = [:]
        init(_ titulo: String, _ ano: String) { self.titulo = titulo; self.ano = ano }
        func completar(_ item: Item) {
            if capa == nil { capa = item.logo }
            let g = AcervoLista.genero(item.grupo)
            if !g.isEmpty, !generos.contains(g) { generos.append(g) }
        }
    }

    /// Monta os arquivos em `pasta` (apaga o que havia). Sem itens, a pasta some.
    @discardableResult
    nonisolated static func gravar(_ pasta: URL, _ itens: [Item]) -> Resumo {
        let fm = FileManager.default
        try? fm.removeItem(at: pasta)
        guard !itens.isEmpty else { return Resumo() }
        var filmes: [Titulo] = [], idxFilme: [String: Int] = [:]
        var series: [Titulo] = [], idxSerie: [String: Int] = [:]
        for item in itens {
            switch item.tipo {
            case .canal: continue
            case .filme:
                let t = Classificar.tituloDoFilme(item.nome, grupo: item.grupo)
                let titulo = campo(t.titulo)
                guard !titulo.isEmpty else { continue }
                let k = chave(titulo)
                let i = idxFilme[k] ?? { filmes.append(Titulo(titulo, t.ano)); idxFilme[k] = filmes.count - 1; return filmes.count - 1 }()
                let f = filmes[i]
                f.completar(item)
                let url = fonte(item.url)
                if let j = f.versoes.firstIndex(where: { $0.0 == t.versao }) {
                    if !f.versoes[j].1.contains(url) { f.versoes[j].1.append(url) }
                } else {
                    f.versoes.append((t.versao, [url]))
                }
            case .episodio(let m):
                let t = Classificar.tituloDaSerie(item.nome, inicio: m.inicio, grupo: item.grupo)
                let titulo = campo(t.titulo)
                let k = "\(chave(titulo))|\(t.ano)"
                let i = idxSerie[k] ?? { series.append(Titulo(titulo, t.ano)); idxSerie[k] = series.count - 1; return series.count - 1 }()
                let s = series[i]
                s.completar(item)
                let ek = "\(m.temporada)|\(m.episodio)|\(t.versao)"
                let url = fonte(item.url)
                if let j = s.indice[ek] {
                    if !s.episodios[j].urls.contains(url) { s.episodios[j].urls.append(url) }
                } else {
                    s.indice[ek] = s.episodios.count
                    s.episodios.append((ek, m.temporada, m.episodio, t.versao, [url]))
                }
            }
        }
        let ordem = { (t: String) in String(Classificar.dobrar(t)) }
        filmes.sort { ordem($0.titulo) < ordem($1.titulo) }
        series.sort { ordem($0.titulo) < ordem($1.titulo) }
        var letras: [String: ([Titulo], [Titulo])] = [:]
        for f in filmes { letras[letra(f.titulo), default: ([], [])].0.append(f) }
        for s in series { letras[letra(s.titulo), default: ([], [])].1.append(s) }

        let tmp = pasta.appendingPathExtension("novo")
        try? fm.removeItem(at: tmp)
        guard (try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)) != nil else { return Resumo() }
        func escrever(_ nome: String, _ texto: String) {
            try? texto.write(to: tmp.appendingPathComponent(noDisco(nome)), atomically: false, encoding: .utf8)
        }
        var indice = "", busca = ""
        for l in letras.keys.sorted() {
            let (fs, ss) = letras[l]!
            indice += "\(l)\t\(fs.count)\t\(ss.count)\t0\n"
            if !fs.isEmpty {
                var texto = ""
                for f in fs {
                    texto += f.titulo
                    for (v, urls) in f.versoes { texto += "\t\(v)=\(urls.joined(separator: ","))" }
                    texto += "\n"
                    busca += "\(f.titulo)\tf\t\(l)\t\(f.ano)\n"
                }
                escrever("filmes-\(l).txt", texto)
            }
            if !ss.isEmpty {
                var lista = "", atual = "", pedaco = 0
                for s in ss {
                    var bloco = "@\(s.titulo)\t\(s.ano)\n"
                    for ep in s.episodios.sorted(by: { ($0.t, $0.e, $0.v != "dub" ? 1 : 0) < ($1.t, $1.e, $1.v != "dub" ? 1 : 0) }) {
                        bloco += "\(ep.t)\t\(ep.e)\t\(ep.v)\t\(ep.urls.joined(separator: ","))\n"
                    }
                    if !atual.isEmpty, atual.utf8.count + bloco.utf8.count > 100 * 1024 {
                        escrever("series-\(l)-\(pedaco).txt", atual)
                        atual = ""
                        pedaco += 1
                    }
                    atual += bloco
                    lista += "\(s.titulo)\t\(s.ano)\t\(pedaco)\t\(s.episodios.count)\n"
                    busca += "\(s.titulo)\ts\t\(l)\t\(s.ano)\n"
                }
                if !atual.isEmpty { escrever("series-\(l)-\(pedaco).txt", atual) }
                escrever("series-\(l).txt", lista)
            }
        }
        escrever("indice.txt", indice)
        escrever("busca.txt", busca)
        // Capas e gêneros. Imagem usada por mais de 3 títulos é a genérica do
        // provedor: melhor sem capa que com a errada.
        var usos: [String: Int] = [:]
        for t in filmes + series { if let c = t.capa { usos[c, default: 0] += 1 } }
        var fichas = "capa: \n"
        for (tipo, lista) in [("f", filmes), ("s", series)] {
            for t in lista {
                let capa = t.capa.flatMap { (usos[$0] ?? 0) > 3 ? nil : fonte($0) } ?? ""
                if capa.isEmpty && t.generos.isEmpty { continue }
                fichas += "\(tipo)\t\(t.titulo)\t0\t\(capa)\t\(t.generos.joined(separator: ","))\n"
            }
        }
        escrever("fichas.txt", fichas)
        try? fm.moveItem(at: tmp, to: pasta)
        return Resumo(filmes: filmes.count, series: series.count)
    }
}
