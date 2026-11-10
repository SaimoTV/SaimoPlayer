import Foundation

/// Sincronia do Saimo Connect com o celular: onde parou em filmes e episódios,
/// títulos favoritos, canais favoritos, os dois endereços das listas e as
/// listas adicionadas. Mesmo formato da TV Box (`{"t":"dados"}`):
///
///   progresso:  {tipo:"f"|"s", titulo, ano, letra, temporada, episodio, pos, dur, em}
///               pos e dur em milissegundos; em = quando foi visto (ms desde 1970)
///   favTitulos: {tipo, titulo, ano, letra}
///   favCanais:  nome do canal
///   listas:     {canais, filmes, em, minhas: [{nome, link}]}
///
/// Progresso: vale o mais recente. Favoritos: união. Endereços: vale o
/// escolhido por último; quem nunca escolheu fica com o que o outro escolheu.
/// Listas adicionadas: união pelo link.
@MainActor
enum SincroniaConnect {

    private static let chaveProgresso = "progresso."

    static func pacote(_ model: PlayerModel) -> [String: Any] {
        let tudo = UserDefaults.standard.dictionaryRepresentation()
        var progresso: [[String: Any]] = []
        for (completa, valor) in tudo where completa.hasPrefix(chaveProgresso) {
            let chave = String(completa.dropFirst(chaveProgresso.count))
            if chave.hasSuffix("|d") || chave.hasSuffix("|t") { continue }
            guard let pos = valor as? Double, pos > 0 else { continue }
            let campos = chave.components(separatedBy: "|")
            guard campos.count >= 2 else { continue }
            let serie = campos[0] == "s"
            if serie && campos.count < 4 { continue }
            let (titulo, ano) = serie ? separarAno(campos[1]) : (campos[1], "")
            progresso.append([
                "tipo": serie ? "s" : "f",
                "titulo": titulo,
                "ano": ano,
                "letra": letra(titulo),
                "temporada": serie ? Int(campos[2]) ?? 0 : 0,
                "episodio": serie ? Int(campos[3]) ?? 0 : 0,
                "pos": Int((pos * 1000).rounded()),
                "dur": Int(((tudo[completa + "|d"] as? Double ?? 0) * 1000).rounded()),
                "em": Int(((tudo[completa + "|t"] as? Double ?? 0) * 1000).rounded()),
            ])
        }
        let favTitulos: [[String: Any]] = VodFavoritos.shared.itens.map {
            ["tipo": $0.serie ? "s" : "f", "titulo": $0.titulo, "ano": $0.ano, "letra": $0.letra]
        }
        let favCanais = model.channels.filter { model.isFavorite($0) }.map(\.name)
        let listas: [String: Any] = [
            "canais": Enderecos.canais,
            "filmes": Enderecos.filmes,
            "em": Int(Enderecos.escolhidosEm),
            "minhas": MinhasListas.shared.listas.map { ["nome": $0.nome, "link": $0.link] },
        ]
        return ["t": "dados", "progresso": progresso, "favTitulos": favTitulos,
                "favCanais": favCanais, "listas": listas]
    }

    /// Junta o que veio do celular ao que o Mac tem.
    static func aplicar(_ j: [String: Any], model: PlayerModel) {
        let defaults = UserDefaults.standard
        for p in j["progresso"] as? [[String: Any]] ?? [] {
            guard let titulo = p["titulo"] as? String, !titulo.isEmpty else { continue }
            let serie = (p["tipo"] as? String) == "s"
            let pos = numero(p["pos"]) / 1000
            let dur = numero(p["dur"]) / 1000
            let em = numero(p["em"]) / 1000
            let temporada = Int(numero(p["temporada"])), episodio = Int(numero(p["episodio"]))
            guard pos > 0, !serie || (temporada > 0 && episodio > 0) else { continue }
            let ano = p["ano"] as? String ?? ""
            let chave = serie
                ? Progresso.chaveEpisodio(ano.isEmpty ? titulo : "\(titulo) (\(ano))", temporada, episodio)
                : Progresso.chaveFilme(titulo)
            let base = chaveProgresso + chave
            guard defaults.double(forKey: base + "|t") < em else { continue }
            defaults.set(pos, forKey: base)
            if dur > 0 { defaults.set(dur, forKey: base + "|d") }
            defaults.set(em, forKey: base + "|t")
        }

        let favoritos = VodFavoritos.shared
        for f in j["favTitulos"] as? [[String: Any]] ?? [] {
            guard let titulo = f["titulo"] as? String, !titulo.isEmpty else { continue }
            let serie = (f["tipo"] as? String) == "s"
            let ano = f["ano"] as? String ?? ""
            if !favoritos.contem(titulo, serie: serie, ano: ano) {
                favoritos.alternar(.init(titulo: titulo, serie: serie, letra: f["letra"] as? String ?? letra(titulo),
                                         reservado: false, ano: ano))
            }
        }

        for nome in j["favCanais"] as? [String] ?? [] {
            if let canal = model.channels.first(where: { $0.name == nome }), !model.isFavorite(canal) {
                model.toggleFavorite(canal)
            }
        }

        if let l = j["listas"] as? [String: Any] { aplicarListas(l, model: model) }
    }

    private static func aplicarListas(_ l: [String: Any], model: PlayerModel) {
        if let canaisRecebido = l["canais"] as? String, let filmesRecebido = l["filmes"] as? String {
            let canais = canaisRecebido.isEmpty ? "" : Enderecos.normalizar(canaisRecebido)
            let filmes = filmesRecebido.isEmpty ? "" : Enderecos.normalizar(filmesRecebido)
            let em = numero(l["em"])
            let local = Enderecos.escolhidosEm
            var c = Enderecos.canais, f = Enderecos.filmes
            if em > local {
                c = canais; f = filmes
            } else if local == 0 {
                // Aqui nunca se escolheu nada: fica o que o outro escolheu (e um
                // endereço que o outro não tem não apaga o daqui).
                if !canais.isEmpty { c = canais }
                if !filmes.isEmpty { f = filmes }
            }
            if c != Enderecos.canais || f != Enderecos.filmes {
                Enderecos.canais = c
                Enderecos.filmes = f
                Enderecos.escolhidosEm = em > local ? em : Date().timeIntervalSince1970 * 1000
                Log.shared.write("Saimo Connect: endereços das listas recebidos do celular")
                Vod.limparCache()
                model.refreshCatalog()
                EPGService.shared.refresh(channels: model.channels)
                ListasEstado.shared.atualizar()
            }
        }
        let minhas = l["minhas"] as? [[String: Any]] ?? []
        let novas = minhas.compactMap { m -> (String, String)? in
            guard let link = (m["link"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  link.hasPrefix("http://") || link.hasPrefix("https://"),
                  !MinhasListas.shared.listas.contains(where: { $0.link == link }) else { return nil }
            return (m["nome"] as? String ?? "", link)
        }
        guard !novas.isEmpty else { return }
        Task { @MainActor in
            for (nome, link) in novas {
                try? await MinhasListas.shared.adicionar(nome: nome, link: link)
            }
        }
    }

    /// "Nome (2020)" -> ("Nome", "2020").
    private static func separarAno(_ nome: String) -> (String, String) {
        guard nome.hasSuffix(")"), let abre = nome.range(of: " (", options: .backwards) else { return (nome, "") }
        let ano = String(nome[abre.upperBound..<nome.index(before: nome.endIndex)])
        guard ano.count == 4, Int(ano) != nil else { return (nome, "") }
        return (String(nome[..<abre.lowerBound]), ano)
    }

    /// A letra do arquivo do acervo onde o título mora (como nos outros apps).
    private static func letra(_ titulo: String) -> String {
        let primeira = titulo.folding(options: .diacriticInsensitive, locale: nil).uppercased().first
        guard let p = primeira, p.isLetter, ("A"..."Z").contains(String(p)) else { return "#" }
        return String(p)
    }

    private static func numero(_ v: Any?) -> Double {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s) ?? 0 }
        return 0
    }
}
