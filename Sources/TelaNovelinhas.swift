import SwiftUI
import AVKit

/// Aba Novelinhas: as minisséries em pé da RedeFlix. Grade de capas verticais
/// com continuar assistindo, áudio e tema; clicar abre o player vertical.
struct TelaNovelinhas: View {
    @ObservedObject private var novelinhas = Novelinhas.shared
    @State private var audio = 0          // 0 todas, 1 dubladas, 2 legendadas
    @State private var tema = ""
    @State private var termo = ""
    @State private var aberta: Novelinhas.Novelinha?
    @State private var versao = 0

    private var temas: [String] {
        var conta: [String: Int] = [:]
        for n in novelinhas.lista { for g in n.generos { conta[g, default: 0] += 1 } }
        return conta.filter { $0.value >= 5 }.sorted { $0.value > $1.value }.prefix(14).map(\.key)
    }

    private var filtradas: [Novelinhas.Novelinha] {
        let t = termo.lowercased().trimmingCharacters(in: .whitespaces)
        return novelinhas.lista.filter { n in
            (audio == 0 || (audio == 1) == n.dublada)
                && (tema.isEmpty || n.generos.contains(tema))
                && (t.isEmpty || n.titulo.lowercased().contains(t))
        }
    }

    private var continuar: [Novelinhas.Novelinha] {
        _ = versao
        let porId = Dictionary(novelinhas.lista.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return novelinhas.recentes().compactMap { porId[$0] }.prefix(20).map { $0 }
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Novelinhas").font(.system(size: 34, weight: .bold))
                        Text("Minisséries em pé, de um minuto por episódio.")
                            .foregroundStyle(.secondary)
                    }
                    if !continuar.isEmpty {
                        Text("Continue assistindo").font(.title3.weight(.semibold))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(continuar) { n in cartao(n).frame(width: 140) }
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        TextField("Buscar novelinha…", text: $termo)
                            .textFieldStyle(.roundedBorder).frame(width: 220)
                        Picker("", selection: $audio) {
                            Text("Todas").tag(0); Text("Dubladas").tag(1); Text("Legendadas").tag(2)
                        }.pickerStyle(.segmented).frame(width: 280)
                        Picker("Tema", selection: $tema) {
                            Text("Todos os temas").tag("")
                            ForEach(temas, id: \.self) { Text($0).tag($0) }
                        }.frame(width: 220)
                        Spacer()
                        Text("\(filtradas.count) novelinhas").foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 14)], spacing: 18) {
                        ForEach(filtradas) { n in cartao(n) }
                    }
                }
                .padding(.horizontal, 40)
                .padding(.top, Tema.alturaDaBarra + 16)
                .padding(.bottom, 40)
            }
            if novelinhas.lista.isEmpty {
                ProgressView().controlSize(.large)
            }
            if let aberta {
                PlayerNovelinha(novelinha: aberta) {
                    self.aberta = nil
                    versao += 1
                }
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .task { await novelinhas.carregar() }
    }

    private func cartao(_ n: Novelinhas.Novelinha) -> some View {
        let parada = novelinhas.parada(n.id)
        return Button { aberta = n } label: {
            VStack(alignment: .leading, spacing: 5) {
                ZStack(alignment: .topLeading) {
                    AsyncImage(url: URL(string: n.capa)) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: { Color.white.opacity(0.06) }
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .aspectRatio(9 / 16, contentMode: .fit)
                    .clipped()
                    Text(n.dublada ? "DUB" : "LEG")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(n.dublada ? Color.green : Color.orange)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                        .padding(6)
                    if let parada {
                        VStack { Spacer()
                            GeometryReader { g in
                                Rectangle().fill(Tema.corDoramas)
                                    .frame(width: g.size.width * min(1, Double(parada.ep) / Double(n.episodios)), height: 3)
                            }.frame(height: 3)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                Text(n.titulo).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                Text(parada.map { "Ep. \($0.ep) de \(n.episodios)" } ?? "\(n.episodios) episódios")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Player vertical: os episódios em fila num AVQueuePlayer (o seguinte já vem
/// carregando e entra sozinho). Setas cima/baixo e a roda trocam de episódio,
/// espaço pausa, Esc fecha. Onde parou fica guardado.
struct PlayerNovelinha: View {
    let novelinha: Novelinhas.Novelinha
    let aoFechar: () -> Void
    @State private var player = AVPlayer()
    @State private var ep = 1
    @State private var fracao = 0.0
    @State private var observador: Any?
    @State private var fim: NSObjectProtocol?
    @FocusState private var focado: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoNovelinha(player: player)
                .aspectRatio(9 / 16, contentMode: .fit)
                .frame(maxHeight: .infinity)
                .onTapGesture { alternar() }
            VStack {
                HStack(alignment: .top) {
                    Button(action: aoFechar) {
                        Image(systemName: "chevron.left").font(.title2).padding(10)
                            .background(.black.opacity(0.5), in: Circle())
                    }.buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(novelinha.titulo).font(.title3.weight(.bold))
                        Text("Episódio \(ep) de \(novelinha.episodios) · \(novelinha.dublada ? "Dublado" : "Legendado")")
                            .foregroundStyle(.secondary)
                        Text("↑ ↓ trocam de episódio · espaço pausa · Esc fecha")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .padding(24)
                Spacer()
                HStack(spacing: 14) {
                    Button { ir(ep - 1) } label: { Image(systemName: "chevron.up") }.disabled(ep <= 1)
                    Menu("Episódio \(ep)") {
                        ForEach(1...novelinha.episodios, id: \.self) { i in Button("Episódio \(i)") { ir(i) } }
                    }.frame(width: 140)
                    Button { ir(ep + 1) } label: { Image(systemName: "chevron.down") }.disabled(ep >= novelinha.episodios)
                }
                .padding(.bottom, 24)
                GeometryReader { g in
                    Rectangle().fill(Tema.corDoramas).frame(width: g.size.width * fracao, height: 3)
                }.frame(height: 3)
            }
        }
        .focusable()
        .focused($focado)
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { ir(ep + 1); return .handled }
        .onKeyPress(.upArrow) { ir(ep - 1); return .handled }
        .onKeyPress(.space) { alternar(); return .handled }
        .onKeyPress(.escape) { aoFechar(); return .handled }
        .onAppear {
            focado = true
            let parada = Novelinhas.shared.parada(novelinha.id)
            ep = min(max(1, parada?.ep ?? 1), novelinha.episodios)
            tocar(ep, em: parada?.ep == ep ? parada?.t ?? 0 : 0)
            observador = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 1), queue: .main) { t in
                MainActor.assumeIsolated {
                    let d = player.currentItem?.duration.seconds ?? 0
                    fracao = d > 0 && d.isFinite ? t.seconds / d : 0
                    if Int(t.seconds) % 5 == 0 { Novelinhas.shared.guardar(novelinha.id, ep: ep, t: t.seconds) }
                }
            }
        }
        .onDisappear {
            Novelinhas.shared.guardar(novelinha.id, ep: ep, t: player.currentTime().seconds)
            if let observador { player.removeTimeObserver(observador) }
            if let fim { NotificationCenter.default.removeObserver(fim) }
            player.pause()
        }
    }

    private func tocar(_ numero: Int, em segundos: Double = 0) {
        guard let url = Novelinhas.shared.url(novelinha, numero) else { return }
        ep = numero
        fracao = 0
        let item = AVPlayerItem(url: url)
        if let fim { NotificationCenter.default.removeObserver(fim) }
        fim = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
            MainActor.assumeIsolated { ir(ep + 1) }
        }
        player.replaceCurrentItem(with: item)
        if segundos > 0 { player.seek(to: CMTime(seconds: segundos, preferredTimescale: 600)) }
        player.play()
        Novelinhas.shared.guardar(novelinha.id, ep: numero, t: segundos)
        // O próximo já vem carregando: um item pré-carregado e jogado fora.
        if numero < novelinha.episodios, let prox = Novelinhas.shared.url(novelinha, numero + 1) {
            let previa = AVURLAsset(url: prox)
            Task { _ = try? await previa.load(.isPlayable) }
        }
    }

    private func ir(_ numero: Int) {
        guard numero >= 1, numero <= novelinha.episodios else { return }
        tocar(numero)
    }

    private func alternar() {
        if player.timeControlStatus == .playing { player.pause() } else { player.play() }
    }
}

/// AVPlayerView sem controles: o vídeo em pé ocupa a altura, centralizado.
private struct VideoNovelinha: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.controlsStyle = .none
        v.videoGravity = .resizeAspect
        v.player = player
        return v
    }
    func updateNSView(_ v: AVPlayerView, context: Context) { v.player = player }
}
