import AVFoundation
import AppKit
import CoreImage

/// O quadro do filme num instante, para a prévia da barra de progresso (como no
/// YouTube): aparece ao passar o mouse na barra ou ao arrastar.
///
/// Arquivo comum (mp4) sai pelo `AVAssetImageGenerator`, que só pede ao servidor
/// o pedaço do quadro. HLS o gerador não lê: aí um segundo player, mudo e na
/// menor qualidade, vai até o instante e entrega o quadro por um
/// `AVPlayerItemVideoOutput`. Nada disso existe até a primeira prévia pedida, e
/// tudo some quando o arquivo no ar muda.
@MainActor
final class PrevisaoDeQuadro: ObservableObject {
    static let shared = PrevisaoDeQuadro()

    @Published private(set) var imagem: NSImage?
    /// O instante da imagem mostrada.
    @Published private(set) var instante: Double = -1

    private var origem: URL?
    private var gerador: AVAssetImageGenerator?
    private var player: AVPlayer?
    private var saida: AVPlayerItemVideoOutput?
    private var pedido: Double?
    private var trabalhando = false
    private var cache: [Int: NSImage] = [:]
    private let contexto = CIContext()

    /// Instantes próximos dividem a mesma prévia: de 5 em 5 segundos.
    private static let passo: Double = 5

    func pedir(_ segundos: Double, em url: URL?) {
        guard let url, segundos.isFinite, segundos >= 0 else { return }
        if url != origem { trocar(para: url) }
        let chave = Int(segundos / Self.passo)
        if let pronta = cache[chave] {
            imagem = pronta
            instante = segundos
            return
        }
        pedido = Double(chave) * Self.passo
        if !trabalhando { proximo() }
    }

    /// O mouse saiu da barra: a última imagem fica, mas nada novo é buscado.
    func cancelar() { pedido = nil }

    private func trocar(para url: URL) {
        origem = url
        cache = [:]
        imagem = nil
        instante = -1
        pedido = nil
        player?.pause()
        player = nil
        saida = nil
        gerador = nil
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": Self.cabecalhos(url)])
        if Self.ehHls(url) {
            montarPlayer(asset)
        } else {
            let g = AVAssetImageGenerator(asset: asset)
            g.appliesPreferredTrackTransform = true
            g.maximumSize = CGSize(width: 320, height: 180)
            // Um pouco de folga deixa o gerador usar o quadro-chave mais perto:
            // muito mais rápido, e a prévia não precisa do quadro exato.
            g.requestedTimeToleranceBefore = CMTime(seconds: 2, preferredTimescale: 600)
            g.requestedTimeToleranceAfter = CMTime(seconds: 2, preferredTimescale: 600)
            gerador = g
        }
    }

    private func montarPlayer(_ asset: AVURLAsset) {
        let item = AVPlayerItem(asset: asset)
        item.preferredPeakBitRate = 400_000
        item.preferredForwardBufferDuration = 1
        let saida = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        item.add(saida)
        let p = AVPlayer(playerItem: item)
        p.isMuted = true
        p.automaticallyWaitsToMinimizeStalling = false
        self.saida = saida
        self.player = p
    }

    private func proximo() {
        guard let alvo = pedido, let url = origem else { trabalhando = false; return }
        pedido = nil
        trabalhando = true
        let tempo = CMTime(seconds: alvo, preferredTimescale: 600)
        if let gerador {
            gerador.generateCGImageAsynchronously(for: tempo) { [weak self] cg, _, erro in
                Task { @MainActor in
                    guard let self, self.origem == url else { return }
                    if let cg {
                        self.entregar(NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)), alvo)
                    } else if erro != nil, self.player == nil {
                        // O gerador não leu este arquivo: tenta pelo player.
                        self.gerador = nil
                        self.montarPlayer(AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": Self.cabecalhos(url)]))
                        self.pedido = self.pedido ?? alvo
                    }
                    self.proximo()
                }
            }
            return
        }
        guard let player, let saida else { trabalhando = false; return }
        player.seek(to: tempo, toleranceBefore: CMTime(seconds: 2, preferredTimescale: 600),
                    toleranceAfter: CMTime(seconds: 2, preferredTimescale: 600)) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.origem == url else { return }
                // O quadro do ponto novo leva um instante para chegar à saída.
                self.colher(saida, alvo: alvo, tentativas: 12)
            }
        }
    }

    private func colher(_ saida: AVPlayerItemVideoOutput, alvo: Double, tentativas: Int) {
        let agora = saida.itemTime(forHostTime: CACurrentMediaTime())
        if saida.hasNewPixelBuffer(forItemTime: agora),
           let buffer = saida.copyPixelBuffer(forItemTime: agora, itemTimeForDisplay: nil) {
            let ci = CIImage(cvPixelBuffer: buffer)
            let escala = 320 / max(ci.extent.width, 1)
            let menor = ci.transformed(by: CGAffineTransform(scaleX: escala, y: escala))
            if let cg = contexto.createCGImage(menor, from: menor.extent) {
                entregar(NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)), alvo)
            }
            proximo()
            return
        }
        guard tentativas > 0 else { proximo(); return }
        // Sem tocar o quadro novo não sai: um instante de reprodução muda.
        player?.rate = 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            self.player?.rate = 0
            self.colher(saida, alvo: alvo, tentativas: tentativas - 1)
        }
    }

    private func entregar(_ nova: NSImage, _ alvo: Double) {
        cache[Int(alvo / Self.passo)] = nova
        if cache.count > 200 { cache.removeAll() }
        imagem = nova
        instante = alvo
    }

    private static func ehHls(_ url: URL) -> Bool {
        let caminho = url.path.lowercased()
        return caminho.hasSuffix(".m3u8") || caminho.hasSuffix(".txt") || caminho.contains("/proxy/")
    }

    private static func cabecalhos(_ url: URL) -> [String: String] {
        ["User-Agent": Upstream.userAgent, "Accept": "*/*"]
    }
}
