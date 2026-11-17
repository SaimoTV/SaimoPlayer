import SwiftUI

/// O que as telas em fileiras pedem ao acervo. Quem sabe escolher fonte,
/// abrir ficha e montar a tela da série é a `VodGridView`; as telas só dizem
/// o que foi escolhido.
struct AcoesDoAcervo {
    /// Um título do índice: filme abre a ficha, série abre a tela dela.
    let abrirTitulo: (Vod.Achado) -> Void
    let abrirDestaque: (Destaques.Item) -> Void
    /// "Continue assistindo": toca de onde parou.
    let continuar: (Progresso.Andamento) -> Void
    let abrirFavorito: (VodFavoritos.Item) -> Void
    /// Anime ou dorama: já vem com os episódios.
    let abrirColecao: (Serie, [Episodio]) -> Void
    /// Item de catálogo dos Addons ou descoberta TMDB.
    var abrirDescoberta: ((DescobertaItem) -> Void)? = nil
}

/// Monta os cartões das fileiras do acervo, iguais em todas as telas.
@MainActor
enum CartoesDoAcervo {
    static func favorito(titulo: String, serie: Bool, letra: String, ano: String,
                         reservado: Bool = false) -> (marcado: Bool, alternar: () -> Void) {
        let favoritos = VodFavoritos.shared
        let item = VodFavoritos.Item(titulo: titulo, serie: serie, letra: letra, reservado: reservado, ano: ano)
        return (favoritos.contem(titulo, serie: serie, ano: ano), { favoritos.alternar(item) })
    }

    static func achado(_ a: Vod.Achado, acoes: AcoesDoAcervo) -> CartaoFila {
        CartaoFila(
            id: a.id,
            titulo: a.nomeCompleto,
            capa: Generos.capa(a.nomeCompleto, serie: a.serie) ?? Generos.capa(a.titulo, serie: a.serie),
            procurar: (a.nomeCompleto, a.serie),
            progresso: a.serie ? nil : Progresso.fracao(Progresso.chaveFilme(a.titulo)),
            alvo: (a.nomeCompleto, a.serie),
            favorito: favorito(titulo: a.titulo, serie: a.serie, letra: a.letra, ano: a.ano)
        ) { acoes.abrirTitulo(a) }
    }

    static func destaque(_ item: Destaques.Item, acoes: AcoesDoAcervo) -> CartaoFila {
        // O ano do filme mora dentro do próprio nome no catálogo; o da série,
        // num campo à parte.
        let anoNoNome = item.titulo.hasSuffix("(\(item.ano))")
        let nome = anoNoNome ? item.titulo : item.nomeCompleto
        return CartaoFila(
            id: item.id,
            titulo: nome,
            capa: item.capa.isEmpty ? Generos.capa(nome, serie: item.serie) : item.capa,
            procurar: (nome, item.serie),
            progresso: item.serie ? nil : Progresso.fracao(Progresso.chaveFilme(item.titulo)),
            alvo: (nome, item.serie),
            favorito: item.daColecao ? nil
                : favorito(titulo: item.titulo, serie: item.serie, letra: item.letra,
                           ano: anoNoNome ? "" : item.ano)
        ) { acoes.abrirDestaque(item) }
    }

    static func andamento(_ a: Progresso.Andamento, acoes: AcoesDoAcervo) -> CartaoFila {
        let capaSalva = Generos.capa(a.titulo, serie: a.serie)
            ?? AddonHistorico.shared.poster(titulo: a.titulo, serie: a.serie)
        let fundoSalvo = AddonHistorico.shared.buscar(titulo: a.titulo, serie: a.serie)?.fundo
        return CartaoFila(
            id: "c:" + a.chave,
            titulo: a.rotulo,
            capa: capaSalva,
            procurar: (a.titulo, a.serie),
            progresso: a.fracao,
            alvo: (a.titulo, a.serie),
            fundo: fundoSalvo,
            remover: { Progresso.remover(a.chave) }
        ) { acoes.continuar(a) }
    }

    static func descoberta(_ item: DescobertaItem, acoes: AcoesDoAcervo) -> CartaoFila {
        let letra = item.serie ? "s" : "f"
        return CartaoFila(
            id: item.id,
            titulo: item.nomeCompleto,
            capa: item.capa,
            procurar: (item.nomeCompleto, item.serie),
            progresso: item.serie ? nil : Progresso.fracao(Progresso.chaveFilme(item.nomeCompleto)),
            alvo: (item.nomeCompleto, item.serie),
            meta: item.ano.isEmpty ? (item.serie ? "Série" : "Filme") : item.ano,
            sinopse: item.sinopse,
            fundo: item.fundo,
            favorito: favorito(titulo: item.titulo, serie: item.serie, letra: letra, ano: item.ano)
        ) {
            acoes.abrirDescoberta?(item)
        }
    }

    static func favoritoItem(_ item: VodFavoritos.Item, acoes: AcoesDoAcervo) -> CartaoFila {
        CartaoFila(
            id: "fav:" + item.id,
            titulo: item.nomeCompleto,
            capa: Generos.capa(item.nomeCompleto, serie: item.serie) ?? Generos.capa(item.titulo, serie: item.serie),
            procurar: (item.nomeCompleto, item.serie),
            progresso: item.serie ? nil : Progresso.fracao(Progresso.chaveFilme(item.titulo)),
            alvo: (item.nomeCompleto, item.serie),
            favorito: (true, { VodFavoritos.shared.alternar(item) })
        ) { acoes.abrirFavorito(item) }
    }

    static func colecao(_ serie: Serie, _ episodios: [Episodio], acoes: AcoesDoAcervo) -> CartaoFila {
        CartaoFila(
            id: "col:" + serie.id,
            titulo: serie.nomeCompleto,
            capa: Generos.capa(serie.titulo, serie: true) ?? Generos.capa(serie.nomeCompleto, serie: true),
            procurar: (serie.nomeCompleto, true),
            alvo: (serie.nomeCompleto, true)
        ) { acoes.abrirColecao(serie, episodios) }
    }

    /// Um canal ao vivo, com o programa no ar e o quanto dele já passou.
    static func canal(_ canal: Channel, model: PlayerModel) -> CartaoFila {
        let epg = EPGService.shared
        let noAr = epg.nowNext(for: canal, at: epg.clock)
        return CartaoFila(
            id: "canal:" + canal.id.uuidString,
            titulo: canal.name,
            subtitulo: noAr?.current.title,
            logoCanal: canal.logo,
            progresso: noAr?.progress,
            seloAoVivo: true,
            meta: noAr.map { "agora: \($0.current.title)" },
            sinopse: noAr?.next.map { "A seguir: \($0.title)" }
        ) {
            model.escolherNaLista(canal.id)
            // Já escolhido, a seleção não dispara: fechar o acervo volta a ele.
            if VodEstado.shared.secao != nil { VodEstado.shared.secao = nil }
        }
    }

    /// Ano de lançamento: o do campo, ou o que vem no fim do nome.
    static func ano(_ titulo: String, _ ano: String) -> Int {
        if let v = Int(ano), (1900...2100).contains(v) { return v }
        guard let faixa = titulo.range(of: #"\((\d{4})\)\s*$"#, options: .regularExpression) else { return 0 }
        let digitos = titulo[faixa].filter(\.isNumber)
        return Int(digitos) ?? 0
    }
}

// MARK: - Início

/// A tela inicial: o título sob o ponteiro em destaque, com a imagem larga
/// dele ao fundo, e as fileiras — o que estava sendo visto, os canais ao vivo
/// agora, os favoritos e as novidades. Tudo a um clique.
struct TelaInicio: View {
    @ObservedObject var model: PlayerModel
    let acoes: AcoesDoAcervo
    let filasDeDestaque: [Destaques.Fila]
    /// Peneira do "continue assistindo" (ver `VodGridView.nomesDoAcervo`).
    let nomesDoAcervo: Set<String>
    let carregando: Bool

    @State private var destaque = DestaqueEstado()
    @State private var versaoProgresso = 0
    @ObservedObject private var favoritos = VodFavoritos.shared
    @ObservedObject private var epg = EPGService.shared
    @ObservedObject private var addons = AddonStore.shared
    @ObservedObject private var descoberta = AddonDescobertaEstado.shared
    @ObservedObject private var addonHist = AddonHistorico.shared

    var body: some View {
        TelaEmFileiras(destaque: destaque, filas: filas, carregando: carregando || (addons.temAtivos && descoberta.carregando && filas.isEmpty))
            .onAppear {
                progressoMudou()
                destaque.padrao(saudacao, "O que vamos assistir?",
                                "Passe o mouse num título para ver do que se trata; clique para abrir. Botão direito favorita.")
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("saimoProgressoMudou"))) { _ in
                progressoMudou()
            }
            .task(id: addons.temAtivos) {
                if addons.temAtivos {
                    await descoberta.carregarSePreciso()
                }
            }
    }

    private func progressoMudou() {
        versaoProgresso &+= 1
    }

    private var filas: [Fila] {
        _ = versaoProgresso
        var out: [Fila] = []
        // Só o que existe no acervo comum ou no histórico dos addons.
        let andamento = Progresso.emAndamento().filter {
            nomesDoAcervo.contains($0.titulo) || addonHist.contem(titulo: $0.titulo, serie: $0.serie)
        }.prefix(20)
        if !andamento.isEmpty {
            out.append(Fila(titulo: "Continue assistindo",
                            cartoes: andamento.map { CartoesDoAcervo.andamento($0, acoes: acoes) }))
        }
        let canais = canaisAoVivo
        if !canais.isEmpty {
            out.append(Fila(titulo: "Ao vivo agora", tipo: .largo,
                            cartoes: canais.map { CartoesDoAcervo.canal($0, model: model) }))
        }
        if !favoritos.itens.isEmpty {
            out.append(Fila(titulo: "Favoritos",
                            cartoes: favoritos.itens.map { CartoesDoAcervo.favoritoItem($0, acoes: acoes) }))
        }
        for fila in filasDeDestaque {
            let cartoes = fila.itens.map { CartoesDoAcervo.destaque($0, acoes: acoes) }
            if !cartoes.isEmpty { out.append(Fila(titulo: fila.titulo, cartoes: cartoes)) }
        }
        if addons.temAtivos {
            for fila in descoberta.catalogosFilas {
                let cartoes = fila.itens.map { CartoesDoAcervo.descoberta($0, acoes: acoes) }
                if !cartoes.isEmpty { out.append(Fila(titulo: fila.titulo, cartoes: cartoes)) }
            }
            if !Enderecos.filmesAtivos {
                for fila in descoberta.filasTMDB {
                    let cartoes = fila.itens.map { CartoesDoAcervo.descoberta($0, acoes: acoes) }
                    if !cartoes.isEmpty { out.append(Fila(titulo: fila.titulo, cartoes: cartoes)) }
                }
            }
        }
        return out
    }

    /// O último canal e os favoritos; sem favoritos, a TV aberta.
    private var canaisAoVivo: [Channel] {
        let todos = model.channels.filter { Categoria.de($0) != .adulto }
        let ultimo = model.selectedChannel.flatMap { c in todos.first { $0.id == c.id } }
        let favoritos = todos.filter { model.isFavorite($0) }
        let base = favoritos.isEmpty ? todos.filter { Categoria.de($0) == .tvAberta } : favoritos
        var vistos = Set<UUID>()
        return ([ultimo].compactMap { $0 } + base).filter { vistos.insert($0.id).inserted }.prefix(16).map { $0 }
    }

    /// "Boa noite" às dez da noite: a abertura fala como gente.
    private var saudacao: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5...11: return "Bom dia"
        case 12...17: return "Boa tarde"
        default: return "Boa noite"
        }
    }
}

// MARK: - On Demand e categorias

/// O On Demand (`tipo` nulo) ou a página de uma categoria, em fileiras.
///
/// No On Demand: os quatro cartões das categorias, o que estava sendo visto,
/// os destaques, os filmes por gênero e, no fim, o acervo de cada categoria de
/// A a Z. Numa categoria: o que estava sendo visto dela, os destaques dela,
/// os lançamentos, uma fileira por gênero (com "Ver todos") e o A a Z.
struct TelaOnDemand: View {
    @ObservedObject var model: PlayerModel
    let tipo: VodSecao?
    let acoes: AcoesDoAcervo
    let filasDeDestaque: [Destaques.Fila]
    let nomesDoAcervo: Set<String>

    @State private var destaque = DestaqueEstado()
    private var estado: VodEstado { .shared }
    @ObservedObject private var favoritos = VodFavoritos.shared
    @ObservedObject private var addons = AddonStore.shared
    @ObservedObject private var descoberta = AddonDescobertaEstado.shared
    @ObservedObject private var addonHist = AddonHistorico.shared
    @State private var acervo: [Vod.Achado] = []
    @State private var colecoes: [String: [(Serie, [Episodio])]] = [:]
    @State private var carregando = true
    /// As fileiras montadas uma vez por carga: varrer trinta mil títulos a
    /// cada redesenho deixaria a tela pesada.
    @State private var prontas: [Fila] = []
    @State private var cargas = 0

    /// Os gêneros mais procurados primeiro; o resto entra depois.
    private static let ordemGeneros = [
        "Ação", "Comédia", "Drama", "Terror", "Thriller", "Suspense", "Ficção científica",
        "Animação", "Romance", "Aventura", "Crime", "Família", "Fantasia", "Mistério",
        "Documentário", "Guerra", "Faroeste", "História", "Música", "Action & Adventure",
        "Sci-Fi & Fantasy", "Kids", "Reality", "Soap", "Talk", "War & Politics"]
    /// No On Demand, só os gêneros que leem bem como "Filmes de ...".
    private static let generosOnDemand = [
        "Ação", "Comédia", "Terror", "Ficção científica", "Romance", "Suspense",
        "Animação", "Aventura", "Drama", "Crime", "Fantasia"]

    private static let sobre: [VodSecao: String] = [
        .filmes: "Lançamentos, clássicos e tudo entre eles, dublados e legendados.",
        .series: "Temporadas completas, com o próximo episódio emendando sozinho.",
        .animes: "Os animes do momento e os que marcaram época.",
        .doramas: "Romance, drama e suspense da Coreia, do Japão e da China.",
        .novelas: "Novelas brasileiras, mexicanas e turcas, do primeiro ao último capítulo.",
        .kids: "Desenhos, animações e filmes para a família, com classificação livre.",
        .novelinhas: "Minisséries em pé, de um minuto por episódio, para maratonar.",
    ]

    private var nome: String { tipo?.titulo ?? "On Demand" }

    var body: some View {
        TelaEmFileiras(destaque: destaque, filas: prontas, carregando: carregando)
            .onAppear { padrao() }
            .onChange(of: tipo) { _, _ in padrao() }
            .onChange(of: favoritos.itens) { _, _ in prontas = filas }
            .onChange(of: filasDeDestaque) { _, _ in prontas = filas }
            .onChange(of: nomesDoAcervo) { _, _ in prontas = filas }
            .onChange(of: descoberta.catalogosFilas) { _, _ in prontas = filas }
            .onChange(of: descoberta.filasTMDB) { _, _ in prontas = filas }
            .onChange(of: cargas) { _, _ in
                prontas = filas
                padrao()
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("saimoProgressoMudou"))) { _ in
                prontas = filas
            }
            .task(id: tipo) { await carregar() }
    }

    private func padrao() {
        let total = contagem(tipo)
        let sub = total.map { "\($0.formatted()) títulos" }
            ?? (addons.temAtivos ? "Catálogos dos Addons e TMDB" : "Carregando…")
        destaque.padrao(nome, sub,
                        tipo.flatMap { Self.sobre[$0] } ?? "Filmes, séries, animes e doramas.")
    }

    private func carregar() async {
        carregando = true
        prontas = []
        if Enderecos.filmesAtivos {
            await Generos.carregar()
            await InfoDosTitulos.carregar()
            await CategoriasVod.carregar()
            if tipo == nil { await Novelinhas.shared.carregar() }
            acervo = await Vod.todos()
            if tipo == nil || tipo == .animes { colecoes["animes"] = await Vod.colecao("animes") }
            if tipo == nil || tipo == .doramas { colecoes["doramas"] = await Vod.colecao("doramas") }
        }
        if addons.temAtivos {
            await descoberta.carregarSePreciso()
        }
        carregando = false
        // Montar aqui usaria a cópia da tela de quando a tarefa começou, com
        // os destaques de então; o `onChange` monta com a de agora.
        cargas += 1
    }

    private func contagem(_ secao: VodSecao?) -> Int? {
        switch secao {
        case nil:
            guard !acervo.isEmpty else { return nil }
            return acervo.count + (colecoes["animes"]?.count ?? 0) + (colecoes["doramas"]?.count ?? 0)
        case .filmes: return acervo.isEmpty ? nil : acervo.filter { !$0.serie }.count
        case .series: return acervo.isEmpty ? nil : acervo.filter(\.serie).count
        case .animes, .doramas:
            guard let c = colecoes[secao == .animes ? "animes" : "doramas"] else { return nil }
            return c.count + extrasDoAcervo(secao!).count
        case .novelas, .kids: return acervo.isEmpty ? nil : doAcervoDaCategoria(secao!).count
        case .novelinhas: return Novelinhas.shared.lista.isEmpty ? nil : Novelinhas.shared.lista.count
        default: return nil
        }
    }

    private func letraDe(_ secao: VodSecao) -> Character {
        switch secao {
        case .series: return "s"
        case .animes: return "a"
        case .doramas: return "d"
        default: return "f"
        }
    }

    // MARK: Fileiras

    private var filas: [Fila] {
        guard !carregando || !filasDeDestaque.isEmpty || addons.temAtivos else { return [] }
        var out: [Fila] = []
        if tipo == nil { out.append(categorias(titulo: "Categorias", az: false)) }
        if let continuar = continuar { out.append(continuar) }
        for fila in filasDeDestaque {
            let itens = tipo.map { t in fila.itens.filter { d in
                if let cat = t.categoriaVod, CategoriasVod.tem(d.nomeCompleto, serie: d.serie, cat) { return true }
                return [.filmes, .series, .animes, .doramas].contains(t) && d.tipo == letraDe(t)
            } } ?? fila.itens
            if itens.count >= 4 {
                out.append(Fila(titulo: fila.titulo, cartoes: itens.map { CartoesDoAcervo.destaque($0, acoes: acoes) }))
            }
        }
        if Enderecos.filmesAtivos {
            if let tipo {
                // O acervo inteiro com filtros (gênero, ano, idade, nota) logo
                // depois da primeira fileira, sem precisar rolar a página toda.
                let explorarFila = Fila(titulo: "Filtrar e explorar", tipo: .secao,
                                        cartoes: [explorar(tipo, titulo: "Todos, com filtros")])
                // Novelas e Kids misturam filmes e séries: não têm grade A–Z.
                if tipo != .novelas && tipo != .kids {
                    out.insert(explorarFila, at: min(out.count, continuar == nil ? 1 : 2))
                }
                let candidatos = self.candidatos(tipo)
                if tipo == .novelas || tipo == .kids {
                    let populares = candidatos.sorted { $0.popularidade > $1.popularidade }.prefix(30)
                    if populares.count >= 4 { out.append(Fila(titulo: "Mais populares", cartoes: populares.map(\.cartao))) }
                }
                let lancamentos = candidatos.filter { $0.ano >= anoAtual - 1 }.sorted { $0.ano > $1.ano }.prefix(30)
                if lancamentos.count >= 4 {
                    out.append(Fila(titulo: "Lançamentos", cartoes: lancamentos.map(\.cartao)))
                }
                let generos = Generos.todos.sorted { posicao($0) < posicao($1) }
                for genero in generos {
                    let doGenero = candidatos.filter { $0.generos.contains(genero) }.sorted { $0.ano > $1.ano }.prefix(25)
                    guard doGenero.count >= 6 else { continue }
                    out.append(Fila(titulo: genero, cartoes: doGenero.map(\.cartao) + [verTodos(tipo, genero)]))
                }
            } else {
                let filmes = candidatos(.filmes)
                for genero in Self.generosOnDemand where Generos.todos.contains(genero) {
                    let doGenero = filmes.filter { $0.generos.contains(genero) }.sorted { $0.ano > $1.ano }.prefix(25)
                    guard doGenero.count >= 6 else { continue }
                    out.append(Fila(titulo: "Filmes de \(genero.lowercased())",
                                    cartoes: doGenero.map(\.cartao) + [verTodos(.filmes, genero)]))
                }
                out.append(categorias(titulo: "Explorar", az: true))
            }
        }
        if addons.temAtivos {
            for f in filasDescobertaFiltradas(descoberta.catalogosFilas) {
                out.append(Fila(titulo: f.titulo, cartoes: f.itens.map { CartoesDoAcervo.descoberta($0, acoes: acoes) }))
            }
            if !Enderecos.filmesAtivos {
                for f in filasDescobertaFiltradas(descoberta.filasTMDB) {
                    out.append(Fila(titulo: f.titulo, cartoes: f.itens.map { CartoesDoAcervo.descoberta($0, acoes: acoes) }))
                }
            }
        }
        return out
    }

    private func filasDescobertaFiltradas(_ lista: [AddonDescobertaFila]) -> [AddonDescobertaFila] {
        guard let tipo else { return lista }
        let alvoTipo = (tipo == .filmes) ? "movie" : "series"
        let filtradas = lista.filter { $0.tipo == alvoTipo || $0.tipo == "all" }
        if tipo == .animes {
            return filtradas.sorted { a, b in
                let aAnime = a.titulo.lowercased().contains("anime") || a.titulo.lowercased().contains("anima")
                let bAnime = b.titulo.lowercased().contains("anime") || b.titulo.lowercased().contains("anima")
                return aAnime && !bAnime
            }
        }
        return filtradas
    }

    private var anoAtual: Int { Calendar.current.component(.year, from: Date()) }

    private func posicao(_ genero: String) -> Int {
        Self.ordemGeneros.firstIndex(of: genero) ?? 99
    }

    private struct Candidato {
        let ano: Int
        let generos: [String]
        let cartao: CartaoFila
        var popularidade: Int = 0
    }

    /// Nome sem ano, acento e pontuação: junta "Naruto" da coleção com o do acervo.
    private static func nomeChave(_ titulo: String) -> String {
        Generos.semAno(titulo).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Filmes e séries do acervo marcados no categorias.txt com a categoria da seção.
    private func doAcervoDaCategoria(_ secao: VodSecao) -> [Vod.Achado] {
        guard let cat = secao.categoriaVod else { return [] }
        return acervo.filter { CategoriasVod.tem($0.nomeCompleto, serie: $0.serie, cat) || CategoriasVod.tem($0.titulo, serie: $0.serie, cat) }
    }

    /// Animes e doramas do acervo que a coleção não tem (pelo nome).
    private func extrasDoAcervo(_ secao: VodSecao) -> [Vod.Achado] {
        let nomes = Set((colecoes[secao == .animes ? "animes" : "doramas"] ?? []).map { Self.nomeChave($0.0.titulo) })
        return doAcervoDaCategoria(secao).filter { !nomes.contains(Self.nomeChave($0.titulo)) }
    }

    private func candidatoDoAcervo(_ a: Vod.Achado) -> Candidato? {
        guard Generos.capa(a.nomeCompleto, serie: a.serie) != nil || Generos.capa(a.titulo, serie: a.serie) != nil else { return nil }
        return Candidato(ano: CartoesDoAcervo.ano(a.titulo, a.ano),
                         generos: Generos.de(a.nomeCompleto, serie: a.serie),
                         cartao: CartoesDoAcervo.achado(a, acoes: acoes),
                         popularidade: InfoDosTitulos.de(a.nomeCompleto, serie: a.serie)?.popularidade ?? 0)
    }

    /// Só títulos com capa: fileira cheia de quadrados vazios não convida ninguém.
    private func candidatos(_ secao: VodSecao) -> [Candidato] {
        switch secao {
        case .animes, .doramas:
            return (colecoes[secao == .animes ? "animes" : "doramas"] ?? []).compactMap { serie, episodios in
                guard Generos.capa(serie.titulo, serie: true) != nil else { return nil }
                return Candidato(ano: CartoesDoAcervo.ano(serie.titulo, serie.ano),
                                 generos: Generos.de(serie.titulo, serie: true),
                                 cartao: CartoesDoAcervo.colecao(serie, episodios, acoes: acoes))
            } + extrasDoAcervo(secao).compactMap(candidatoDoAcervo)
        case .novelas, .kids:
            return doAcervoDaCategoria(secao).compactMap(candidatoDoAcervo)
        default:
            let serie = secao == .series
            return acervo.compactMap { a in
                guard a.serie == serie, Generos.capa(a.nomeCompleto, serie: a.serie) != nil
                        || Generos.capa(a.titulo, serie: a.serie) != nil else { return nil }
                return Candidato(ano: CartoesDoAcervo.ano(a.titulo, a.ano),
                                 generos: Generos.de(a.nomeCompleto, serie: a.serie),
                                 cartao: CartoesDoAcervo.achado(a, acoes: acoes))
            }
        }
    }

    private var continuar: Fila? {
        let itens = Progresso.emAndamento().filter { a in
            guard nomesDoAcervo.contains(a.titulo) || addonHist.contem(titulo: a.titulo, serie: a.serie) else { return false }
            switch tipo {
            case nil: return true
            case .filmes: return !a.serie
            case .series, .animes, .doramas: return a.serie
            case .novelas: return CategoriasVod.tem(a.titulo, serie: a.serie, "novela")
            case .kids: return CategoriasVod.tem(a.titulo, serie: a.serie, "kids")
            default: return false
            }
        }.prefix(20)
        guard !itens.isEmpty else { return nil }
        return Fila(titulo: "Continue assistindo", cartoes: itens.map { CartoesDoAcervo.andamento($0, acoes: acoes) })
    }

    /// "Ver todos" no fim de uma fileira de gênero: a grade já filtrada.
    private func verTodos(_ secao: VodSecao, _ genero: String) -> CartaoFila {
        CartaoFila(id: "mais:\(secao.rawValue):\(genero)", titulo: "Ver todos",
                   meta: genero, sinopse: "Todos os títulos de \(genero.lowercased()), de A a Z.") {
            estado.serieAberta = nil
            estado.genero = genero
            estado.explorando = true
            estado.secao = secao
        }
    }

    private func explorar(_ secao: VodSecao, titulo: String) -> CartaoFila {
        var c = cartaoDaCategoria(secao)
        c = CartaoFila(id: "az:" + secao.rawValue, titulo: titulo, subtitulo: c.subtitulo,
                       meta: c.meta, sinopse: c.sinopse, fundoDe: c.fundoDe,
                       colagem: c.colagem, icone: "textformat.abc", cor: c.cor) {
            estado.serieAberta = nil
            estado.genero = ""
            estado.explorando = true
            estado.secao = secao
        }
        return c
    }

    private func categorias(titulo: String, az: Bool) -> Fila {
        let tipos: [VodSecao] = [.filmes, .series, .animes, .doramas, .novelas, .novelinhas, .kids]
            .filter { [.filmes, .series, .animes, .doramas].contains($0) || (contagem($0) ?? 0) > 0 }
        return Fila(titulo: titulo, tipo: .secao, cartoes: tipos.map { secao in
            az && ![.novelas, .kids, .novelinhas].contains(secao)
                ? explorar(secao, titulo: "\(secao.titulo) de A a Z") : cartaoDaCategoria(secao)
        })
    }

    /// O cartão grande de uma categoria: colagem com as capas em alta dela.
    private func cartaoDaCategoria(_ secao: VodSecao) -> CartaoFila {
        let letra = letraDe(secao)
        let emAlta = filasDeDestaque.flatMap(\.itens).filter { d in
            guard !d.capa.isEmpty else { return false }
            if secao == .novelas || secao == .kids { return CategoriasVod.tem(d.nomeCompleto, serie: d.serie, secao.categoriaVod!) }
            if secao == .novelinhas { return false }
            return d.tipo == letra
        }
        var vistas = Set<String>()
        var colagem = Array(emAlta.map(\.capa).filter { vistas.insert($0).inserted }.prefix(4))
        if colagem.count < 4 {
            let extras: [String] = secao == .novelinhas
                ? Novelinhas.shared.lista.prefix(8).map(\.capa)
                : (secao == .novelas || secao == .kids ? doAcervoDaCategoria(secao).prefix(30).compactMap { Generos.capa($0.nomeCompleto, serie: $0.serie) ?? Generos.capa($0.titulo, serie: $0.serie) } : [])
            colagem += extras.filter { vistas.insert($0).inserted }.prefix(4 - colagem.count)
        }
        if colagem.isEmpty && addons.temAtivos {
            let alvoSerie = secao != .filmes
            let descobertaCapas = (descoberta.catalogosFilas + descoberta.filasTMDB)
                .flatMap(\.itens)
                .filter { $0.serie == alvoSerie }
                .compactMap(\.capa)
            colagem = Array(descobertaCapas.filter { vistas.insert($0).inserted }.prefix(4))
        }
        let primeiro = emAlta.first
        let quantos = contagem(secao).map { "\($0.formatted()) títulos" }
        let (icone, cor): (String, Color) = {
            switch secao {
            case .series: return ("play.rectangle.on.rectangle.fill", Tema.corSeries)
            case .animes: return ("sparkles", Tema.corAnimes)
            case .doramas: return ("heart.fill", Tema.corDoramas)
            case .novelas: return ("theatermasks.fill", Color(red: 0xC7 / 255, green: 0x92 / 255, blue: 0xEA / 255))
            case .kids: return ("figure.and.child.holdinghands", Color(red: 0x7E / 255, green: 0xE7 / 255, blue: 0x87 / 255))
            case .novelinhas: return ("iphone", Tema.corDoramas)
            default: return ("film.fill", Tema.corFilmes)
            }
        }()
        return CartaoFila(
            id: "cat:" + secao.rawValue,
            titulo: secao.titulo,
            subtitulo: quantos,
            meta: quantos ?? "",
            sinopse: Self.sobre[secao],
            fundoDe: primeiro.map { ($0.nomeCompleto, $0.serie) },
            colagem: Array(colagem),
            icone: icone,
            cor: cor
        ) {
            estado.serieAberta = nil
            estado.explorando = false
            estado.genero = ""
            estado.secao = secao
        }
    }
}
