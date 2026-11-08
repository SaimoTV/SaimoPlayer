import SwiftUI
import AppKit
import CoreImage.CIFilterBuiltins

/// Apoie o Saimo TV: por que doar, o botão que abre a página de doação, o QR
/// code (para doar pelo celular) e o link escrito.
struct TelaApoie: View {
    static let link = URL(string: "https://deflow.exchange/pt/qr/saimo-tv")!
    private let turquesa = Color(red: 0.31, green: 0.89, blue: 0.82)

    var body: some View {
        ScrollView {
            HStack(alignment: .center, spacing: 56) {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Comunidade Saimo TV", systemImage: "heart.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(turquesa)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(turquesa.opacity(0.14), in: Capsule())
                    (Text("Ajude a manter tudo ") + Text("100% gratuito").foregroundColor(turquesa))
                        .font(.system(size: 40, weight: .heavy))
                    Text("Sem anúncios, sem mensalidade e livre para todo mundo.")
                        .font(.system(size: 18)).foregroundStyle(.white.opacity(0.8))
                    Text("Manter servidores rápidos, a transmissão e as atualizações de todo dia custa dinheiro todo mês. Quem puder ajudar com qualquer valor faz uma diferença enorme para o Saimo TV continuar no ar para todos.")
                        .font(.system(size: 15)).foregroundStyle(.white.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        vantagem("nosign", "Zero anúncios", "Nada interrompendo o que você assiste")
                        vantagem("bolt.fill", "Servidores rápidos", "Transmissão estável e em alta qualidade")
                        vantagem("heart.fill", "Sem mensalidade", "Canais, filmes e séries para todo mundo")
                    }
                    .padding(.top, 6)
                    HStack(spacing: 12) {
                        Button { NSWorkspace.shared.open(Self.link) } label: {
                            Label("Fazer doação (Pix ou cripto)", systemImage: "heart.fill")
                                .font(.system(size: 15, weight: .bold))
                                .padding(.horizontal, 22).padding(.vertical, 12)
                                .foregroundStyle(.white)
                                .background(LinearGradient(colors: [Color(red: 0.06, green: 0.66, blue: 0.60),
                                                                    Color(red: 0.15, green: 0.39, blue: 0.92)],
                                                           startPoint: .leading, endPoint: .trailing), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(Self.link.absoluteString, forType: .string)
                        } label: {
                            Label("Copiar link", systemImage: "doc.on.doc")
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.horizontal, 18).padding(.vertical, 11)
                                .foregroundStyle(turquesa)
                                .overlay(Capsule().stroke(turquesa.opacity(0.5)))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 10)
                }
                .frame(maxWidth: 680, alignment: .leading)

                VStack(spacing: 14) {
                    Text("Aponte a câmera do celular")
                        .font(.system(size: 17, weight: .bold)).foregroundStyle(.black)
                    if let qr = Self.qr {
                        Image(nsImage: qr).interpolation(.none).resizable().frame(width: 240, height: 240)
                    }
                    Text("deflow.exchange/pt/qr/saimo-tv")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(red: 0.05, green: 0.45, blue: 0.56))
                        .textSelection(.enabled)
                    Text("Pagamento seguro pela Deflow")
                        .font(.system(size: 12)).foregroundStyle(.gray)
                }
                .padding(28)
                .background(.white, in: RoundedRectangle(cornerRadius: 24))
            }
            .padding(.horizontal, 56)
            .padding(.top, Tema.alturaDaBarra + 50)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(.white)
    }

    private func vantagem(_ icone: String, _ titulo: String, _ texto: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icone).font(.system(size: 18)).foregroundStyle(turquesa)
            VStack(alignment: .leading, spacing: 3) {
                Text(titulo).font(.system(size: 14, weight: .bold))
                Text(texto).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    /// QR code do link, gerado na hora (sem imagem guardada no app).
    private static let qr: NSImage? = {
        let filtro = CIFilter.qrCodeGenerator()
        filtro.message = Data(link.absoluteString.utf8)
        filtro.correctionLevel = "M"
        guard let saida = filtro.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        let rep = NSCIImageRep(ciImage: saida)
        let imagem = NSImage(size: rep.size)
        imagem.addRepresentation(rep)
        return imagem
    }()
}
