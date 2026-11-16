import SwiftUI
import AppKit

/// Logo que serve de carregamento: aparece apagada e em tons de cinza e vai
/// ganhando cor da esquerda para a direita enquanto o vídeo abre. Sem medida
/// real de progresso, a cor avança sozinha e desacelera perto do fim (0 a 92 %
/// em 12 s); quando o pai tira a view (o vídeo começou) ela já está quase
/// toda colorida.
struct LogoCarregando: View {
    let imagem: NSImage
    var tamanho: CGFloat = 140
    @State private var progresso: CGFloat = 0

    var body: some View {
        ZStack(alignment: .leading) {
            Image(nsImage: imagem)
                .resizable().scaledToFit()
                .saturation(0)
                .opacity(0.22)
            Image(nsImage: imagem)
                .resizable().scaledToFit()
                .mask(alignment: .leading) {
                    Rectangle().frame(width: tamanho * progresso)
                }
        }
        .frame(width: tamanho, height: tamanho)
        .shadow(color: .black.opacity(0.5), radius: 12)
        .onAppear {
            progresso = 0
            withAnimation(.easeOut(duration: 12)) { progresso = 0.92 }
        }
        .accessibilityLabel("Carregando")
    }
}

/// O logo do canal (ou o do Saimo) no meio do vídeo enquanto a fonte abre.
struct LogoAoAbrir: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject private var logos = LogoLoader.shared

    var body: some View {
        if model.isLoadingSource, !model.multiTela {
            let url = model.playingFile == nil ? model.selectedChannel?.logo : nil
            let imagem = url.flatMap { logos.image(for: $0) } ?? NSApp.applicationIconImage
            LogoCarregando(imagem: imagem ?? NSImage())
                .id(url?.absoluteString ?? "saimo")
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }
}
