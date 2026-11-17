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

    /// Onde parou, títulos e canais favoritos de um perfil (de qualquer perfil, pelo UserDefaults dele).
    private static func dados(de id: String, model: PlayerModel) -> (progresso: [[String: Any]], favTitulos: [[String: Any]], favCanais: [String]) {
        let defaults = Perfis.defaults(de: id)
        let tudo = defaults.dictionaryRepresentation()
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
        let favTitulos: [[String: Any]] = (defaults.stringArray(forKey: chaveFavTitulos) ?? []).compactMap { linha in
            let c = linha.components(separatedBy: "\t")
            guard c.count >= 3, !c[2].isEmpty else { return nil }
            return ["tipo": c[0] == "s" ? "s" : "f", "titulo": c[2], "ano": c.count > 4 ? c[4] : "", "letra": c[1]]
        }
        let urls = Set(defaults.stringArray(forKey: chaveFavCanais) ?? [])
        let favCanais = model.channels.filter { urls.contains($0.source.absoluteString) }.map(\.name)
        return (progresso, favTitulos, favCanais)
    }

    private static let chaveFavTitulos = "vodFavoritos"
    private static let chaveFavCanais = "favorites"

    static func pacote(_ model: PlayerModel) -> [String: Any] {
        // Os campos de sempre levam o perfil principal: apps sem perfis seguem funcionando.
        let principal = dados(de: Perfis.principal, model: model)
        let perfis: [[String: Any]] = Perfis.todos.map { p in
            let d = p.id == Perfis.principal ? principal : dados(de: p.id, model: model)
            var o: [String: Any] = ["id": p.id, "nome": p.nome, "avatar": p.avatar, "em": Int(p.em),
                                    "progresso": d.progresso, "favTitulos": d.favTitulos, "favCanais": d.favCanais]
            if p.ehKids { o["kids"] = true; o["codigo"] = p.codigo ?? "" }
            return o
        }
        let listas: [String: Any] = [
            "canais": Enderecos.canais,
            "filmes": Enderecos.filmes,
            "em": Int(Enderecos.escolhidosEm),
            "minhas": MinhasListas.shared.listas.map { ["nome": $0.nome, "link": $0.link] },
        ]
        var saida: [String: Any] = [
            "t": "dados",
            "progresso": principal.progresso,
            "favTitulos": principal.favTitulos,
            "favCanais": principal.favCanais,
            "perfis": perfis,
            "perfisRemovidos": Perfis.removidos.map { ["id": $0.id, "em": Int($0.em)] },
            "listas": listas,
            "addons": AddonStore.shared.paraConnect(),
        ]
        if DebridStore.shared.sincronizarConnect {
            saida["debrid"] = DebridStore.shared.paraConnect()
        }
        return saida
    }

    /// Junta o que veio do celular ao que o Mac tem.
    static func aplicar(_ j: [String: Any], model: PlayerModel) {
        if let lista = j["perfis"] as? [[String: Any]] {
            let remotos: [(Perfis.Perfil, [String: Any])] = lista.compactMap { o in
                guard let id = o["id"] as? String, !id.isEmpty else { return nil }
                let kids = (o["kids"] as? Bool) == true
                return (Perfis.Perfil(id: id, nome: o["nome"] as? String ?? "", avatar: o["avatar"] as? String ?? "",
                                      em: numero(o["em"]), kids: kids ? true : nil, codigo: kids ? o["codigo"] as? String : nil), o)
            }
            let remocoes = (j["perfisRemovidos"] as? [[String: Any]] ?? []).compactMap { r -> Perfis.Remocao? in
                guard let id = r["id"] as? String else { return nil }
                return Perfis.Remocao(id: id, em: numero(r["em"]))
            }
            let existem = Perfis.mesclar(remotos.map(\.0), remocoes: remocoes)
            for (p, o) in remotos where existem.contains(p.id) { aplicarDoPerfil(p.id, o, model: model) }
        } else {
            // Celular sem perfis: os campos de sempre são do perfil principal.
            aplicarDoPerfil(Perfis.principal, j, model: model)
        }

        if let l = j["listas"] as? [String: Any] { aplicarListas(l, model: model) }
        aplicarAddonsSePresente(j)
        if DebridStore.shared.sincronizarConnect,
           let debridObj = j["debrid"] as? [String: Any] {
            DebridStore.shared.aplicarConnect(debridObj)
        }
    }

    /// Onde parou e favoritos de um perfil vindos do celular.
    private static func aplicarDoPerfil(_ id: String, _ j: [String: Any], model: PlayerModel) {
        let defaults = Perfis.defaults(de: id)
        let ativo = id == Perfis.idAtivo
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

        let titulos = j["favTitulos"] as? [[String: Any]] ?? []
        if ativo {
            let favoritos = VodFavoritos.shared
            for f in titulos {
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
            return
        }
        var linhas = defaults.stringArray(forKey: chaveFavTitulos) ?? []
        for f in titulos {
            guard let titulo = f["titulo"] as? String, !titulo.isEmpty else { continue }
            let serie = (f["tipo"] as? String) == "s"
            let ano = f["ano"] as? String ?? ""
            let existe = linhas.contains { l in
                let c = l.components(separatedBy: "\t")
                return c.count >= 3 && c[2] == titulo && (c[0] == "s") == serie && (c.count > 4 ? c[4] : "") == ano
            }
            if !existe {
                linhas.insert([serie ? "s" : "f", f["letra"] as? String ?? letra(titulo), titulo, "n", ano].joined(separator: "\t"), at: 0)
            }
        }
        defaults.set(linhas, forKey: chaveFavTitulos)
        var urls = Set(defaults.stringArray(forKey: chaveFavCanais) ?? [])
        for nome in j["favCanais"] as? [String] ?? [] {
            if let canal = model.channels.first(where: { $0.name == nome }) { urls.insert(canal.source.absoluteString) }
        }
        defaults.set(Array(urls), forKey: chaveFavCanais)
    }

    /// Retrocompatibilidade: pacotes `{t:"dados"}` antigos sem `"addons"` não apagam os addons locais.
    static func aplicarAddonsSePresente(_ j: [String: Any], store: AddonStore = .shared) {
        if let addonsRecebidos = j["addons"] as? [[String: Any]] {
            store.aplicarConnect(addonsRecebidos)
        }
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
