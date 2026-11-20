import Foundation

/// Registro do que foi removido ("Continue assistindo", favoritos, canais
/// favoritos, Minhas listas), para a sincronia (Conta Saimo e Saimo Connect)
/// não trazer de volta. Contrato em docs/perfis.md: cada remoção é `{…, em}` e
/// um item só fica se for mais novo que ela (sem `em` conta como 0). As mesmas
/// regras do servidor (SaimoConta/src/juntar.ts).
///
/// Por perfil (UserDefaults do perfil, chave `remocoes`): prog e fav
/// ({tipo, titulo, ano, em}; ano vazio vale para qualquer ano), canal
/// ({nome, em}), favEm e canalEm (quando cada favorito entrou). Minhas listas
/// (do aparelho, `remocoesListas`): rem ({link, em}) e em por link.
@MainActor
enum Remocoes {

    typealias Obj = [String: Any]

    struct Registro {
        var prog: [Obj] = []
        var fav: [Obj] = []
        var canal: [Obj] = []
        var favEm: [String: Double] = [:]
        var canalEm: [String: Double] = [:]
    }

    private static let chave = "remocoes"
    private static let chaveListas = "remocoesListas"
    private static let maximo = 300
    private static let vida: Double = 180 * 24 * 3600_000

    static func numero(_ v: Any?) -> Double {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s) ?? 0 }
        return 0
    }

    private static func texto(_ v: Any?) -> String { v as? String ?? "" }
    private static func tipo(_ o: Obj) -> String { texto(o["tipo"]) == "s" ? "s" : "f" }
    static func chaveTitulo(_ tipo: String, _ titulo: String, _ ano: String) -> String { "\(tipo)|\(titulo)|\(ano)" }
    private static func chaveRemTitulo(_ o: Obj) -> String? {
        texto(o["titulo"]).isEmpty ? nil : chaveTitulo(tipo(o), texto(o["titulo"]), texto(o["ano"]))
    }
    private static func chaveCanal(_ o: Obj) -> String? { texto(o["nome"]).isEmpty ? nil : texto(o["nome"]) }
    private static func chaveLink(_ o: Obj) -> String? {
        let l = texto(o["link"]).trimmingCharacters(in: .whitespaces)
        return l.isEmpty ? nil : l
    }

    /// Junta pela chave (vale o `em` maior); as velhas demais saem.
    private static func juntarPor(_ a: [Obj], _ b: [Obj], _ chave: (Obj) -> String?) -> [Obj] {
        var m: [String: Obj] = [:]
        let limite = Date().timeIntervalSince1970 * 1000 - vida
        for r in a + b {
            guard let k = chave(r) else { continue }
            let em = numero(r["em"])
            guard em > 0, em >= limite else { continue }
            if let atual = m[k], numero(atual["em"]) >= em { continue }
            m[k] = r
        }
        return Array(m.values.sorted { numero($0["em"]) > numero($1["em"]) }.prefix(maximo))
    }

    static func tituloRemovido(_ rem: [Obj], tipo t: String, titulo: String, ano: String, emItem: Double) -> Bool {
        rem.contains {
            tipo($0) == t && texto($0["titulo"]) == titulo
                && (texto($0["ano"]).isEmpty || ano.isEmpty || texto($0["ano"]) == ano) && numero($0["em"]) >= emItem
        }
    }

    static func canalRemovido(_ r: Registro, nome: String, emItem: Double? = nil) -> Bool {
        let em = emItem ?? r.canalEm[nome] ?? 0
        return r.canal.contains { texto($0["nome"]) == nome && numero($0["em"]) >= em }
    }

    private static func mapa(_ v: Any?) -> [String: Double] {
        var out: [String: Double] = [:]
        for (k, x) in v as? [String: Any] ?? [:] { out[k] = numero(x) }
        return out
    }

    static func ler(_ id: String) -> Registro {
        guard let dados = Perfis.defaults(de: id).data(forKey: chave),
              let o = try? JSONSerialization.jsonObject(with: dados) as? Obj else { return Registro() }
        return Registro(prog: o["prog"] as? [Obj] ?? [], fav: o["fav"] as? [Obj] ?? [], canal: o["canal"] as? [Obj] ?? [],
                        favEm: mapa(o["favEm"]), canalEm: mapa(o["canalEm"]))
    }

    static func gravar(_ id: String, _ r: Registro) {
        let o: Obj = [
            "prog": juntarPor(r.prog, [], chaveRemTitulo),
            "fav": juntarPor(r.fav, [], chaveRemTitulo),
            "canal": juntarPor(r.canal, [], chaveCanal),
            "favEm": r.favEm, "canalEm": r.canalEm,
        ]
        if let d = try? JSONSerialization.data(withJSONObject: o) { Perfis.defaults(de: id).set(d, forKey: chave) }
    }

    /// Junta ao registro do perfil as remoções que vieram de fora (perfil do pacote).
    static func juntar(_ id: String, _ chegou: Obj) -> Registro {
        var r = ler(id)
        for (n, em) in mapa(chegou["favCanaisEm"]) where em > (r.canalEm[n] ?? 0) { r.canalEm[n] = em }
        for f in chegou["favTitulos"] as? [Obj] ?? [] {
            let k = chaveTitulo(tipo(f), texto(f["titulo"]), texto(f["ano"]))
            if numero(f["em"]) > (r.favEm[k] ?? 0) { r.favEm[k] = numero(f["em"]) }
        }
        r.prog = juntarPor(r.prog, chegou["progressoRemovido"] as? [Obj] ?? [], chaveRemTitulo)
        r.fav = juntarPor(r.fav, chegou["favTitulosRemovidos"] as? [Obj] ?? [], chaveRemTitulo)
        r.canal = juntarPor(r.canal, chegou["favCanaisRemovidos"] as? [Obj] ?? [], chaveCanal)
        gravar(id, r)
        return r
    }

    /// As remoções no perfil do pacote.
    static func anexar(_ o: inout Obj, _ r: Registro) {
        if !r.prog.isEmpty { o["progressoRemovido"] = r.prog }
        if !r.fav.isEmpty { o["favTitulosRemovidos"] = r.fav }
        if !r.canal.isEmpty { o["favCanaisRemovidos"] = r.canal }
        if !r.canalEm.isEmpty { o["favCanaisEm"] = r.canalEm.mapValues { Int($0) } }
    }

    private static var agora: Double { (Date().timeIntervalSince1970 * 1000).rounded() }

    /// Tirou do "Continue assistindo" (perfil ativo).
    static func anotarContinuar(serie: Bool, titulo: String, ano: String) {
        guard !titulo.isEmpty else { return }
        var r = ler(Perfis.idAtivo)
        r.prog.append(["tipo": serie ? "s" : "f", "titulo": titulo, "ano": ano, "em": Int(agora)])
        gravar(Perfis.idAtivo, r)
    }

    /// Desfavoritou (removido) ou favoritou um título (perfil ativo).
    static func anotarFavorito(serie: Bool, titulo: String, ano: String, removido: Bool) {
        var r = ler(Perfis.idAtivo)
        let t = serie ? "s" : "f"
        let k = chaveTitulo(t, titulo, ano)
        if removido {
            r.fav.append(["tipo": t, "titulo": titulo, "ano": ano, "em": Int(agora)])
            r.favEm[k] = nil
        } else {
            r.fav.removeAll { chaveRemTitulo($0) == k }
            r.favEm[k] = agora
        }
        gravar(Perfis.idAtivo, r)
    }

    /// Desfavoritou (removido) ou favoritou um canal (perfil ativo).
    static func anotarCanal(nome: String, removido: Bool) {
        var r = ler(Perfis.idAtivo)
        if removido {
            r.canal.append(["nome": nome, "em": Int(agora)])
            r.canalEm[nome] = nil
        } else {
            r.canal.removeAll { texto($0["nome"]) == nome }
            r.canalEm[nome] = agora
        }
        gravar(Perfis.idAtivo, r)
    }

    // MARK: Minhas listas (do aparelho)

    struct RegistroListas { var rem: [Obj] = []; var em: [String: Double] = [:] }

    static func lerListas() -> RegistroListas {
        guard let d = UserDefaults.standard.data(forKey: chaveListas),
              let o = try? JSONSerialization.jsonObject(with: d) as? Obj else { return RegistroListas() }
        return RegistroListas(rem: o["rem"] as? [Obj] ?? [], em: mapa(o["em"]))
    }

    static func gravarListas(_ r: RegistroListas) {
        let o: Obj = ["rem": juntarPor(r.rem, [], chaveLink), "em": r.em]
        if let d = try? JSONSerialization.data(withJSONObject: o) { UserDefaults.standard.set(d, forKey: chaveListas) }
    }

    static func juntarListas(_ chegou: [Obj]) -> RegistroListas {
        var r = lerListas()
        r.rem = juntarPor(r.rem, chegou, chaveLink)
        gravarListas(r)
        return r
    }

    static func listaRemovida(_ r: RegistroListas, link: String, emItem: Double? = nil) -> Bool {
        let em = emItem ?? r.em[link] ?? 0
        return r.rem.contains { chaveLink($0) == link && numero($0["em"]) >= em }
    }

    static func anotarLista(_ link: String?, removida: Bool) {
        guard let link, !link.isEmpty else { return }
        var r = lerListas()
        if removida {
            r.rem.append(["link": link, "em": Int(agora)])
            r.em[link] = nil
        } else {
            r.rem.removeAll { chaveLink($0) == link }
            r.em[link] = agora
        }
        gravarListas(r)
    }
}
