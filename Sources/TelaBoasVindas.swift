import SwiftUI

/// Primeira tela para quem ainda não entrou numa conta: à esquerda entrar ou
/// criar a conta, à direita seguir sem login. A conta é opcional. Quem escolhe
/// "sem login" não vê esta tela de novo; a Conta Saimo continua sendo a
/// primeira opção em Ajustes.
@MainActor
struct TelaBoasVindas: View {
    static let chave = "boasVindas.feito"

    static var precisa: Bool { !Conta.shared.logado && !UserDefaults.standard.bool(forKey: chave) }

    @ObservedObject private var conta = Conta.shared
    let terminar: () -> Void

    var body: some View {
        ZStack {
            Tema.fundo.ignoresSafeArea()
            HStack(alignment: .top, spacing: 28) {
                cartao(destaque: true) {
                    Text("Entrar ou criar conta").font(.escalado(30, weight: .bold))
                    Text("Por que criar uma conta?").font(.escalado(16, weight: .semibold)).padding(.top, 10)
                    ForEach(["Perfis, favoritos, listas e addons guardados e em qualquer aparelho.",
                             "Continue de onde parou no celular, na TV e no computador.",
                             "Trocou de aparelho ou reinstalou? Nada se perde."], id: \.self) { t in
                        Text("•  \(t)").font(.escalado(15)).foregroundStyle(Tema.textoSecundario)
                    }
                    // O QR já aparece aqui; o botão do formulário troca o QR por e-mail e senha.
                    TelaConta(fechar: {}, embutida: true).padding(.top, 10)
                }
                cartao(destaque: false) {
                    Text("Entrar sem login").font(.escalado(30, weight: .bold))
                    (Text("A conta não é obrigatória. ").bold()
                     + Text("Dá para usar o Saimo TV inteiro sem entrar: tudo fica guardado só neste computador."))
                        .font(.escalado(16)).foregroundStyle(Tema.textoSecundario).padding(.top, 6)
                    Text("Crie a conta quando quiser, em Ajustes > Conta Saimo.")
                        .font(.escalado(16)).foregroundStyle(Tema.textoSecundario)
                    Button {
                        UserDefaults.standard.set(true, forKey: Self.chave)
                        terminar()
                    } label: {
                        Text("Entrar sem login").font(.escalado(16, weight: .semibold)).padding(.horizontal, 22).padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 14)
                }
            }
            .frame(maxWidth: 1000)
            .padding(40)
        }
        .foregroundStyle(.white)
        // Entrou na conta aqui mesmo: segue.
        .onChange(of: conta.logado) { _, logado in if logado { terminar() } }
    }

    private func cartao<C: View>(destaque: Bool, @ViewBuilder _ conteudo: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) { conteudo() }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(28)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(destaque ? Tema.acento.opacity(0.7) : Color.white.opacity(0.14), lineWidth: destaque ? 2 : 1))
    }
}
