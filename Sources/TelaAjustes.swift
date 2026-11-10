import SwiftUI
import AppKit

/// Preferências do app gravadas em disco (Application Support/SaimoTV/ajustes.json)
/// e no UserDefaults, garantindo que sobreviva a fechamento e atualização do app.
enum Preferencias {
    private static let chaveAbrirNoCanal = "ajustes.abrirNoCanal"
    private static let chaveUpscaling    = "ajustes.upscaling"
    private static let chaveFillScreen   = "ajustes.fillScreen"
    private static let chaveAlwaysOnTop  = "ajustes.alwaysOnTop"
    private static let chaveShowStats    = "ajustes.showStats"
    private static let chaveIsMuted      = "ajustes.isMuted"
    private static let chaveDetachedList = "ajustes.detachedList"
    private static let chaveAudioInteligente = "ajustes.audioInteligente"
    private static let chaveZeroDelay        = "ajustes.zeroDelay"

    static let upscalingMudou = Notification.Name("SaimoUpscalingMudou")

    private static var arquivoURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("SaimoTV", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ajustes.json")
    }

    private static func lerMapa() -> [String: Any] {
        guard let data = try? Data(contentsOf: arquivoURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }

    private static func gravar(_ chave: String, _ valor: Any) {
        var mapa = lerMapa()
        mapa[chave] = valor
        if let data = try? JSONSerialization.data(withJSONObject: mapa, options: [.prettyPrinted]) {
            try? data.write(to: arquivoURL, options: .atomic)
        }
        UserDefaults.standard.set(valor, forKey: chave)
        UserDefaults.standard.synchronize()
    }

    private static func lerBool(_ chave: String, padrao: Bool = false) -> Bool {
        let mapa = lerMapa()
        if let v = mapa[chave] as? Bool { return v }
        if UserDefaults.standard.object(forKey: chave) != nil {
            return UserDefaults.standard.bool(forKey: chave)
        }
        return padrao
    }

    private static func lerString(_ chave: String, padrao: String) -> String {
        let mapa = lerMapa()
        if let v = mapa[chave] as? String { return v }
        return UserDefaults.standard.string(forKey: chave) ?? padrao
    }

    /// Ao abrir o app: a tela inicial (como na TV) ou direto o último canal.
    static var abrirNoCanal: Bool {
        get { lerBool(chaveAbrirNoCanal) }
        set { gravar(chaveAbrirNoCanal, newValue) }
    }

    /// Super Resolução (Upscaling): "off" (padrão), "hd" ou "4k".
    static var upscaling: String {
        get { lerString(chaveUpscaling, padrao: "off") }
        set {
            gravar(chaveUpscaling, newValue)
            NotificationCenter.default.post(name: upscalingMudou, object: nil)
        }
    }

    static var fillScreen: Bool {
        get { lerBool(chaveFillScreen) }
        set { gravar(chaveFillScreen, newValue) }
    }

    static var alwaysOnTop: Bool {
        get { lerBool(chaveAlwaysOnTop) }
        set { gravar(chaveAlwaysOnTop, newValue) }
    }

    static var showStats: Bool {
        get { lerBool(chaveShowStats) }
        set { gravar(chaveShowStats, newValue) }
    }

    static var isMuted: Bool {
        get { lerBool(chaveIsMuted) }
        set { gravar(chaveIsMuted, newValue) }
    }

    static var detachedList: Bool {
        get { lerBool(chaveDetachedList) }
        set { gravar(chaveDetachedList, newValue) }
    }

    static var audioInteligente: Bool {
        get { lerBool(chaveAudioInteligente, padrao: true) }
        set { gravar(chaveAudioInteligente, newValue) }
    }

    static var zeroDelay: String {
        get { lerString(chaveZeroDelay, padrao: "equilibrado") }
        set { gravar(chaveZeroDelay, newValue) }
    }

    static func rotuloUpscaling(_ modo: String) -> String {
        switch modo {
        case "hd": return "Nitidez HD (MetalFX · 720p → Full HD)"
        case "4k": return "Super Resolução Ultra (MetalFX · até 4K)"
        default:   return "Desligado"
        }
    }
}

/// Os ajustes, em seções como na TV Box: reprodução, geral, canais e sistema.
/// Cada linha diz o que faz e o valor de agora; clicar troca.
struct TelaAjustes: View {
    @ObservedObject private var minhas = MinhasListas.shared
    @ObservedObject var model: PlayerModel
    @ObservedObject private var epg = EPGService.shared
    @ObservedObject private var connect = SaimoConnect.shared
    @State private var catalogoAtualizado = false
    @State private var urlCanais: String = Enderecos.canais
    @State private var urlFilmes: String = Enderecos.filmes
    @State private var statusListas: String? = nil

    private var versao: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Text("Ajustes")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)

                    secao("Reprodução") {
                        linha("Super Resolução (Upscaling)", Preferencias.rotuloUpscaling(model.upscaling),
                              icone: "sparkles") {
                            switch model.upscaling {
                            case "off": model.upscaling = "hd"
                            case "hd":  model.upscaling = "4k"
                            default:    model.upscaling = "off"
                            }
                        }
                        alternador("Preencher a tela", "Corta as bordas em vez de mostrar faixas pretas",
                                   icone: "rectangle.arrowtriangle.2.outward", valor: $model.fillScreen)
                        alternador("Manter à frente", "A janela fica por cima das outras",
                                   icone: "pin.fill", valor: $model.alwaysOnTop)
                        alternador("Estatísticas do vídeo", "Resolução, bitrate e buffer no canto da imagem",
                                   icone: "chart.bar.xaxis", valor: $model.showStats)
                        alternador("Sem som", "Silencia o vídeo e o ao vivo",
                                   icone: "speaker.slash.fill", valor: $model.isMuted)
                    }

                    secao("Geral") {
                        linha("Ao abrir o app", model.abrirNoCanal ? "Ir direto ao último canal" : "Mostrar a tela inicial",
                              icone: "house.fill") {
                            model.abrirNoCanal.toggle()
                        }
                        alternador("Lista de canais em janela separada",
                                   "Uma janela ao lado do player, como antes (⇧⌘L)",
                                   icone: "sidebar.leading", valor: $model.detachedList)
                    }

                    secao("Listas") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Os endereços de onde o app lê os canais e os filmes e séries. Já vêm preenchidos; troque por outros, ou deixe em branco e salve para desligar uma lista (o app fica vazio naquela parte).")
                                .font(.system(size: 13))
                                .foregroundStyle(Tema.textoSecundario)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 14)
                        .padding(.bottom, 6)

                        Divider().background(Color.white.opacity(0.08))

                        // Canais
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .center, spacing: 10) {
                                Image(systemName: "tv")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Tema.acento)
                                    .frame(width: 26)

                                Text("Canais")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)

                                Spacer()

                                if !urlCanais.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Button("Apagar") {
                                        urlCanais = ""
                                        salvarListas()
                                    }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.red.opacity(0.85))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                                }
                            }

                            TextField("https://exemplo.dev/canais/", text: $urlCanais)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(.white)
                                .padding(9)
                                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12), lineWidth: 1))

                            Text("Lista de canais, rádios e guia de programação.")
                                .font(.system(size: 12))
                                .foregroundStyle(Tema.textoApagado)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)

                        Divider().background(Color.white.opacity(0.08))

                        // Filmes e séries
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .center, spacing: 10) {
                                Image(systemName: "film.stack")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Tema.acento)
                                    .frame(width: 26)

                                Text("Filmes e séries")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)

                                Spacer()

                                if !urlFilmes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Button("Apagar") {
                                        urlFilmes = ""
                                        salvarListas()
                                    }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.red.opacity(0.85))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                                }
                            }

                            TextField("https://exemplo.dev/filmes/", text: $urlFilmes)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(.white)
                                .padding(9)
                                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12), lineWidth: 1))

                            Text("Lista de filmes, séries, animes e doramas.")
                                .font(.system(size: 12))
                                .foregroundStyle(Tema.textoApagado)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)

                        Divider().background(Color.white.opacity(0.08))

                        // Ações de Listas
                        HStack(spacing: 12) {
                            Spacer()

                            if let status = statusListas {
                                Text(status)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(status.contains("✓") ? Tema.acento : .orange)
                                    .transition(.opacity)
                            }

                            Button {
                                salvarListas()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark")
                                    Text("Salvar")
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(Tema.acento, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                    }

                    secao("Minhas listas") {
                        ForEach(minhas.listas) { lista in
                            linha(lista.nome, "\(lista.total) canais · toque para remover", icone: "list.bullet") {
                                minhas.confirmarRemocao(lista)
                            }
                        }
                        linha("Adicionar lista por link",
                              minhas.listas.isEmpty
                              ? "Uma lista .m3u: os canais entram no Ao vivo. Também chegam do celular pelo Saimo Connect"
                              : "Até \(MinhasListas.maximo) listas",
                              icone: "plus.circle") {
                            minhas.pedirNova()
                        }
                    }

                    secao("Canais") {
                        linha("Importar lista .m3u", "Junta os canais de um arquivo à lista", icone: "square.and.arrow.down") {
                            ChannelListActions.importList(into: model)
                        }
                        linha("Adicionar canal por endereço", "Cole o URL de um fluxo .m3u8", icone: "link.badge.plus") {
                            ChannelListActions.addByURL(into: model)
                        }
                        linha("Exportar playlist", "Salva a lista com os links do app", icone: "square.and.arrow.up") {
                            model.exportPlaylist()
                        }
                        linha("Atualizar guia", "Busca a programação de novo (⇧⌘G)", icone: "calendar.badge.clock") {
                            EPGService.shared.refresh(channels: model.channels)
                        }
                        linha("Programação completa", "A grade de todos os canais", icone: "list.bullet.rectangle") {
                            model.showGuide = true
                        }
                    }

                    secao("Saimo Connect") {
                        informacao("Controle pelo celular",
                                   connect.ativo
                                   ? "No app Saimo do celular, toque em Conectar e escolha \"\(connect.nome)\" (\(ProxyServer.lanAddress() ?? "sem rede"):\(SaimoConnect.porta))"
                                   : "Indisponível: a porta \(SaimoConnect.porta) está ocupada",
                                   icone: "iphone.radiowaves.left.and.right")
                        informacao("Celulares autorizados", rotuloDosCelulares, icone: "iphone")
                        linha("Esquecer todos os celulares", "Na próxima conexão o Mac pergunta de novo",
                              icone: "iphone.slash") {
                            connect.esquecerTodos()
                        }
                    }

                    secao("Sistema") {
                        linha("Atualizar Catálogo e Fontes",
                              catalogoAtualizado ? "✓ Catálogo e fontes atualizados com sucesso!" : "Recarrega filmes, séries e novas fontes da nuvem",
                              icone: "arrow.clockwise") {
                            Vod.limparCache()
                            model.refreshCatalog()
                            EPGService.shared.refresh(channels: model.channels)
                            withAnimation { catalogoAtualizado = true }
                            Task {
                                try? await Task.sleep(nanoseconds: 3_000_000_000)
                                withAnimation { catalogoAtualizado = false }
                            }
                        }
                        linha("Procurar atualização", "v\(versao)", icone: "arrow.down.circle") {
                            Atualizacao.shared.procurar(manual: true)
                        }
                    }

                    Text("Saimo TV \(versao) para Mac")
                        .font(.system(size: 12))
                        .foregroundStyle(Tema.textoApagado)
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, Tema.margem)
                .padding(.top, Tema.alturaDaBarra + 20)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                urlCanais = Enderecos.canais
                urlFilmes = Enderecos.filmes
            }
        }
    }

    private func salvarListas() {
        let canaisNorm = Enderecos.normalizar(urlCanais)
        let filmesNorm = Enderecos.normalizar(urlFilmes)

        let mudou = Enderecos.canais != canaisNorm || Enderecos.filmes != filmesNorm

        Enderecos.canais = canaisNorm
        Enderecos.filmes = filmesNorm
        if mudou {
            Enderecos.escolhidosEm = Date().timeIntervalSince1970 * 1000
            connect.avisarDados()
        }
        urlCanais = canaisNorm
        urlFilmes = filmesNorm

        if mudou {
            recarregarTudo()
        }
        mostrarStatus("✓ Listas salvas com sucesso")
    }

    private func recarregarTudo() {
        Vod.limparCache()
        model.refreshCatalog()
        EPGService.shared.refresh(channels: model.channels)
        ListasEstado.shared.atualizar()
    }

    private func mostrarStatus(_ msg: String) {
        withAnimation { statusListas = msg }
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            withAnimation { statusListas = nil }
        }
    }

    private var rotuloDosCelulares: String {
        let n = connect.autorizados
        let base = n == 0 ? "Nenhum celular autorizado" : n == 1 ? "1 celular autorizado" : "\(n) celulares autorizados"
        guard !connect.conectados.isEmpty else { return base }
        return base + " · conectado agora: " + connect.conectados.joined(separator: ", ")
    }

    private func informacao(_ titulo: String, _ detalhe: String, icone: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icone)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Tema.acento)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo).font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                Text(detalhe).font(.system(size: 12)).foregroundStyle(Tema.textoSecundario)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func secao<Conteudo: View>(_ titulo: String, @ViewBuilder _ conteudo: () -> Conteudo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titulo.uppercased())
                .font(.system(size: 12, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(Tema.acento)
                .padding(.leading, 6)
            VStack(spacing: 0) { conteudo() }
                .vidroPainel(raio: 18)
        }
    }

    private func linha(_ titulo: String, _ detalhe: String, icone: String,
                       acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            HStack(spacing: 14) {
                Image(systemName: icone)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Tema.acento)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(titulo).font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                    Text(detalhe).font(.system(size: 12)).foregroundStyle(Tema.textoSecundario)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(LinhaSobMouse())
    }

    private func alternador(_ titulo: String, _ detalhe: String, icone: String,
                            valor: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icone)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Tema.acento)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo).font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                Text(detalhe).font(.system(size: 12)).foregroundStyle(Tema.textoSecundario)
            }
            Spacer()
            Toggle("", isOn: valor)
                .toggleStyle(.switch)
                .tint(Tema.acento)
                .labelsHidden()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}

/// A linha sob o ponteiro clareia, como a linha focada na TV.
private struct LinhaSobMouse: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Modificador(configuration: configuration)
    }

    private struct Modificador: View {
        let configuration: Configuration
        @State private var sobre = false
        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(configuration.isPressed ? 0.14 : sobre ? 0.07 : 0)))
                .onHover { sobre = $0 }
        }
    }
}
