import SwiftUI
import AppKit
import CoreImage.CIFilterBuiltins

/// Apoie o Saimo TV: por que doar, o Pix direto (QR code para doar pelo
/// celular e o botão que copia o código "copia e cola").
struct TelaApoie: View {
    /// Pix "copia e cola" (BR Code estático): o valor vai direto para o desenvolvedor.
    static let codigoPix = "00020126580014br.gov.bcb.pix0136950460d4-51c5-49ba-bf71-b720b60cde435204000053039865802BR5925GABRIEL SAIMO FERREIRA ES60085500019962070503***6304F442"
    @State private var copiado = false
    private let turquesa = Color(red: 0.31, green: 0.89, blue: 0.82)

    var body: some View {
        ScrollView {
            HStack(alignment: .center, spacing: 56) {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Comunidade Saimo TV", systemImage: "heart.fill")
                        .font(.escalado(13, weight: .semibold))
                        .foregroundStyle(turquesa)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(turquesa.opacity(0.14), in: Capsule())
                    (Text("Ajude a manter o Saimo TV ") + Text("100% gratuito").foregroundColor(turquesa))
                        .font(.escalado(40, weight: .heavy))
                    Text("Sem anúncios e sem mensalidade.")
                        .font(.escalado(18)).foregroundStyle(.white.opacity(0.8))
                    Text("O Saimo TV é um player: ele toca as listas e os links que você mesmo adiciona. O app não traz nenhum canal, filme ou série dentro; o que você assiste vem das suas próprias listas.")
                        .font(.escalado(15)).foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("O desenvolvimento e as atualizações do app e do site custam dinheiro todo mês. Quem puder ajudar com qualquer valor faz uma diferença enorme para o Saimo TV continuar gratuito e sem anúncios.")
                        .font(.escalado(15)).foregroundStyle(.white.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Agora o Pix é direto: o valor vai direto para o desenvolvedor, Gabriel Saimo Ferreira, sem intermediário. Aponte a câmera do celular para o QR code ou copie o código Pix e cole no app do seu banco.")
                        .font(.escalado(15)).foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        vantagem("nosign", "Zero anúncios", "Nada interrompendo o que você usa")
                        vantagem("arrow.triangle.2.circlepath", "Atualizações constantes", "Melhorias e correções para o app e o site")
                        vantagem("heart.fill", "Sem mensalidade", "O app é gratuito para todo mundo")
                    }
                    .padding(.top, 6)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Self.codigoPix, forType: .string)
                        copiado = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiado = false }
                    } label: {
                        Label(copiado ? "Código copiado" : "Copiar Pix copia e cola",
                              systemImage: copiado ? "checkmark" : "doc.on.doc")
                            .font(.escalado(15, weight: .bold))
                            .padding(.horizontal, 22).padding(.vertical, 12)
                            .foregroundStyle(.white)
                            .background(LinearGradient(colors: [Color(red: 0.06, green: 0.66, blue: 0.60),
                                                                Color(red: 0.15, green: 0.39, blue: 0.92)],
                                                       startPoint: .leading, endPoint: .trailing), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                }
                .frame(maxWidth: 680, alignment: .leading)

                VStack(spacing: 14) {
                    Text("Aponte a câmera do celular")
                        .font(.escalado(17, weight: .bold)).foregroundStyle(.black)
                    if let qr = Self.qr {
                        Image(nsImage: qr).interpolation(.none).resizable().frame(width: 240, height: 240)
                    }
                    Text("Pix direto")
                        .font(.escalado(15, weight: .bold))
                        .foregroundStyle(Color(red: 0.05, green: 0.45, blue: 0.56))
                    Text("Gabriel Saimo Ferreira")
                        .font(.escalado(12)).foregroundStyle(.gray)
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
            Image(systemName: icone).font(.escalado(18)).foregroundStyle(turquesa)
            VStack(alignment: .leading, spacing: 3) {
                Text(titulo).font(.escalado(14, weight: .bold))
                Text(texto).font(.escalado(12)).foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    /// QR code do Pix, gerado na hora (sem imagem guardada no app).
    private static let qr: NSImage? = {
        let filtro = CIFilter.qrCodeGenerator()
        filtro.message = Data(codigoPix.utf8)
        filtro.correctionLevel = "M"
        guard let saida = filtro.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        let rep = NSCIImageRep(ciImage: saida)
        let imagem = NSImage(size: rep.size)
        imagem.addRepresentation(rep)
        return imagem
    }()
}
