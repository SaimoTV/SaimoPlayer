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
/// Listas adicionadas: união pelo link. Remoções (Remocoes.swift) viajam junto:
/// o que foi tirado num aparelho não volta pela união (só se entrar de novo depois).
@MainActor
enum SincroniaConnect {

    private static let chaveProgresso = "progresso."

    /// Onde parou, títulos e canais favoritos de um perfil (de qualquer perfil, pelo UserDefaults dele).
    private static func dados(de id: String, model: PlayerModel) -> (progresso: [[String: Any]], favTitulos: [[String: Any]], favCanais: [String]) {
        let defaults = Perfis.defaults(de: id)
        let tudo = defaults.dictionaryRepresentation()
        let reg = Remocoes.ler(id)
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
            let emItem = ((tudo[completa + "|t"] as? Double ?? 0) * 1000).rounded()
            if Remocoes.tituloRemovido(reg.prog, tipo: serie ? "s" : "f", titulo: titulo, ano: ano, emItem: emItem) { continue }
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
            let tipo = c[0] == "s" ? "s" : "f", ano = c.count > 4 ? c[4] : ""
            var o: [String: Any] = ["tipo": tipo, "titulo": c[2], "ano": ano, "letra": c[1]]
            if let em = reg.favEm[Remocoes.chaveTitulo(tipo, c[2], ano)] { o["em"] = Int(em) }
            return o
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
            Remocoes.anexar(&o, Remocoes.ler(p.id))
            return o
        }
        let regListas = Remocoes.lerListas()
        var listas: [String: Any] = [
            "canais": Enderecos.canais,
            "filmes": Enderecos.filmes,
            "em": Int(Enderecos.escolhidosEm),
            "minhas": MinhasListas.shared.listas.map { l -> [String: Any] in
                var o: [String: Any] = ["nome": l.nome, "link": l.link]
                if let em = regListas.em[l.link] { o["em"] = Int(em) }
                return o
            },
        ]
        if !regListas.rem.isEmpty { listas["minhasRemovidas"] = regListas.rem }
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
        let reg = Remocoes.juntar(id, j)
        // O que foi removido em outro aparelho depois de entrar aqui sai daqui também.
        if !reg.prog.isEmpty {
            let tudo = defaults.dictionaryRepresentation()
            for (completa, _) in tudo where completa.hasPrefix(chaveProgresso) {
                let chave = String(completa.dropFirst(chaveProgresso.count))
                if chave.hasSuffix("|d") || chave.hasSuffix("|t") { continue }
                let campos = chave.components(separatedBy: "|")
                guard campos.count >= 2 else { continue }
                let serie = campos[0] == "s"
                let (titulo, ano) = serie ? separarAno(campos[1]) : (campos[1], "")
                let em = ((tudo[completa + "|t"] as? Double ?? 0) * 1000).rounded()
                guard Remocoes.tituloRemovido(reg.prog, tipo: serie ? "s" : "f", titulo: titulo, ano: ano, emItem: em) else { continue }
                for k in [completa, completa + "|d", completa + "|t"] { defaults.removeObject(forKey: k) }
            }
        }
        for p in j["progresso"] as? [[String: Any]] ?? [] {
            guard let titulo = p["titulo"] as? String, !titulo.isEmpty else { continue }
            let serie = (p["tipo"] as? String) == "s"
            let pos = numero(p["pos"]) / 1000
            let dur = numero(p["dur"]) / 1000
            let em = numero(p["em"]) / 1000
            let temporada = Int(numero(p["temporada"])), episodio = Int(numero(p["episodio"]))
            guard pos > 0, !serie || (temporada > 0 && episodio > 0) else { continue }
            let ano = p["ano"] as? String ?? ""
            if Remocoes.tituloRemovido(reg.prog, tipo: serie ? "s" : "f", titulo: titulo, ano: ano, emItem: em * 1000) { continue }
            let chave = serie
                ? Progresso.chaveEpisodio(ano.isEmpty ? titulo : "\(titulo) (\(ano))", temporada, episodio)
                : Progresso.chaveFilme(titulo)
            let base = chaveProgresso + chave
            guard defaults.double(forKey: base + "|t") < em else { continue }
            defaults.set(pos, forKey: base)
            if dur > 0 { defaults.set(dur, forKey: base + "|d") }
            defaults.set(em, forKey: base + "|t")
        }

        let titulos = (j["favTitulos"] as? [[String: Any]] ?? []).filter { f in
            let t = (f["tipo"] as? String) == "s" ? "s" : "f"
            return !Remocoes.tituloRemovido(reg.fav, tipo: t, titulo: f["titulo"] as? String ?? "", ano: f["ano"] as? String ?? "",
                                            emItem: Remocoes.numero(f["em"]))
        }
        let canaisRecebidos = (j["favCanais"] as? [String] ?? []).filter { !Remocoes.canalRemovido(reg, nome: $0) }
        if ativo {
            let favoritos = VodFavoritos.shared
            for item in favoritos.itens {
                let t = item.serie ? "s" : "f"
                if Remocoes.tituloRemovido(reg.fav, tipo: t, titulo: item.titulo, ano: item.ano,
                                           emItem: reg.favEm[Remocoes.chaveTitulo(t, item.titulo, item.ano)] ?? 0) {
                    favoritos.alternar(item, anotar: false)
                }
            }
            for f in titulos {
                guard let titulo = f["titulo"] as? String, !titulo.isEmpty else { continue }
                let serie = (f["tipo"] as? String) == "s"
                let ano = f["ano"] as? String ?? ""
                if !favoritos.contem(titulo, serie: serie, ano: ano) {
                    favoritos.alternar(.init(titulo: titulo, serie: serie, letra: f["letra"] as? String ?? letra(titulo),
                                             reservado: false, ano: ano), anotar: false)
                }
            }
            for canal in model.channels where model.isFavorite(canal) && Remocoes.canalRemovido(reg, nome: canal.name) {
                model.toggleFavorite(canal, anotar: false)
            }
            for nome in canaisRecebidos {
                if let canal = model.channels.first(where: { $0.name == nome }), !model.isFavorite(canal) {
                    model.toggleFavorite(canal, anotar: false)
                }
            }
            return
        }
        var linhas = (defaults.stringArray(forKey: chaveFavTitulos) ?? []).filter { l in
            let c = l.components(separatedBy: "\t")
            guard c.count >= 3 else { return true }
            let t = c[0] == "s" ? "s" : "f", ano = c.count > 4 ? c[4] : ""
            return !Remocoes.tituloRemovido(reg.fav, tipo: t, titulo: c[2], ano: ano, emItem: reg.favEm[Remocoes.chaveTitulo(t, c[2], ano)] ?? 0)
        }
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
        for canal in model.channels where urls.contains(canal.source.absoluteString) && Remocoes.canalRemovido(reg, nome: canal.name) {
            urls.remove(canal.source.absoluteString)
        }
        for nome in canaisRecebidos {
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
        let reg = Remocoes.juntarListas(l["minhasRemovidas"] as? [[String: Any]] ?? [])
        for lista in MinhasListas.shared.listas where Remocoes.listaRemovida(reg, link: lista.link) {
            MinhasListas.shared.remover(lista.id, anotar: false)
        }
        let minhas = l["minhas"] as? [[String: Any]] ?? []
        let novas = minhas.compactMap { m -> (String, String)? in
            guard let link = (m["link"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  link.hasPrefix("http://") || link.hasPrefix("https://"),
                  !MinhasListas.shared.listas.contains(where: { $0.link == link }),
                  !Remocoes.listaRemovida(reg, link: link, emItem: Remocoes.numero(m["em"])) else { return nil }
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
