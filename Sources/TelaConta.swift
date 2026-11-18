import SwiftUI

/// Ajustes > Conta Saimo. Sem conta: o QR (e o código curto) para entrar pelo
/// celular, que já está logado; pergunta ao servidor a cada 5 s e pede outro
/// código quando vence. Com conta: e-mail, última sincronização, sincronizar e sair.
struct TelaConta: View {
    @ObservedObject private var conta = Conta.shared
    let fechar: () -> Void

    @State private var codigo = "…"
    @State private var imagem: NSImage?
    @State private var situacao = "Pedindo um código…"
    @State private var tarefa: Task<Void, Never>?
    /// Formulário de e-mail e senha aberto (sem conta: entrar; com conta: criar ou trocar a senha).
    @State private var comEmail = false

    var body: some View {
        Group {
            if comEmail {
                FormSenha(emailFixo: conta.logado ? conta.email : nil) { comEmail = false }
            } else if conta.logado { logado } else { qr }
        }
        .padding(36)
        .frame(width: 760)
        .background(Color(red: 0.06, green: 0.09, blue: 0.15))
        .onAppear { if !conta.logado { esperar() } }
        // Saiu com a janela aberta: volta para o QR e pede um código novo.
        .onChange(of: conta.logado) { _, logado in if !logado { codigo = "…"; imagem = nil; esperar() } }
        .onDisappear { tarefa?.cancel() }
    }

    private var logado: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Conta Saimo").font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
            Text(conta.email ?? "").font(.system(size: 16)).foregroundStyle(.white)
            Text(conta.sincronizando ? "sincronizando…" : (conta.erro ?? Conta.haQuanto(conta.sincronizadaEm)))
                .font(.system(size: 14)).foregroundStyle(Tema.textoSecundario)
            Text("Perfis, onde parou, favoritos, listas e addons. Sair mantém os dados neste Mac.")
                .font(.system(size: 13)).foregroundStyle(Tema.textoSecundario)
            HStack(spacing: 12) {
                Button("Sincronizar agora") { Task { await conta.sincronizar(forcar: true) } }.disabled(conta.sincronizando)
                if conta.email != nil { Button("Criar ou trocar a senha") { comEmail = true } }
                Button("Sair da conta") { Task { await conta.sair() } }
                Spacer()
                Button("Fechar", action: fechar).keyboardShortcut(.cancelAction)
            }
            .padding(.top, 8)
        }
    }

    private var qr: some View {
        HStack(alignment: .center, spacing: 32) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(.white)
                if let imagem { Image(nsImage: imagem).interpolation(.none).resizable().scaledToFit().padding(12) }
            }
            .frame(width: 240, height: 240)
            VStack(alignment: .leading, spacing: 12) {
                Text("Entrar na Conta Saimo").font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                Text("No celular com o Saimo e a sua conta, leia o QR com a câmera. Ou abra Ajustes > Conta Saimo > Entrar numa TV e digite o código:")
                    .font(.system(size: 14)).foregroundStyle(Tema.textoSecundario).fixedSize(horizontal: false, vertical: true)
                Text(codigo).font(.system(size: 38, weight: .heavy, design: .monospaced)).tracking(4)
                    .foregroundStyle(Color(red: 0.18, green: 0.83, blue: 0.75)).textSelection(.enabled)
                Text(situacao).font(.system(size: 13)).foregroundStyle(Tema.textoSecundario)
                Button("Entrar com e-mail e senha") { comEmail = true }
                HStack {
                    Text("Sem conta, tudo continua só neste Mac.").font(.system(size: 12)).foregroundStyle(.gray)
                    Spacer()
                    Button("Fechar", action: fechar).keyboardShortcut(.cancelAction)
                }
            }
        }
    }

    private func esperar() {
        tarefa?.cancel()
        tarefa = Task { @MainActor in
            while !Task.isCancelled {
                let pedido: Conta.Pedido
                do { pedido = try await conta.pedirCodigo() } catch {
                    situacao = error.localizedDescription
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    continue
                }
                codigo = pedido.codigo
                imagem = Conta.qr(pedido.url, lado: 216)
                situacao = "Esperando o celular…"
                while !Task.isCancelled, Date().timeIntervalSince1970 * 1000 < pedido.expiraEm {
                    try? await Task.sleep(nanoseconds: UInt64(pedido.intervalo * 1_000_000_000))
                    if Task.isCancelled { return }
                    var r: Bool? = false
                    do { r = try await conta.conferir(pedido) } catch { r = false }
                    if r == true { situacao = "Pronto! Sincronizando…"; return }
                    if r == nil { break }
                }
            }
        }
    }
}

/// Entrar com e-mail e senha, ou criar e trocar a senha com o código do e-mail
/// (prova que o e-mail é de quem pede). `emailFixo`: já logado, só a senha.
private struct FormSenha: View {
    @ObservedObject private var conta = Conta.shared
    let emailFixo: String?
    let voltar: () -> Void

    @State private var email = ""
    @State private var senha = ""
    @State private var codigo = ""
    @State private var definindo = false
    @State private var codigoPedido = false
    @State private var ocupado = false
    @State private var aviso = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(emailFixo == nil ? (definindo ? "Criar ou trocar a senha" : "Entrar com e-mail e senha") : "Criar ou trocar a senha")
                .font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
            if emailFixo == nil {
                TextField("Seu e-mail", text: $email).textFieldStyle(.roundedBorder).textContentType(.username)
            } else {
                Text(emailFixo ?? "").foregroundStyle(Tema.textoSecundario)
            }
            if definindo {
                Text(codigoPedido ? "Chegou um código de 6 números no e-mail. Digite o código e a senha nova (pelo menos 8 caracteres)."
                     : "Mandamos um código para o seu e-mail.")
                    .font(.system(size: 13)).foregroundStyle(Tema.textoSecundario).fixedSize(horizontal: false, vertical: true)
                if codigoPedido {
                    TextField("Código (6 números)", text: $codigo).textFieldStyle(.roundedBorder)
                    SecureField("Senha nova", text: $senha).textFieldStyle(.roundedBorder).textContentType(.newPassword)
                }
                if emailFixo != nil {
                    Text("Trocar uma senha que já existia tira a conta dos outros aparelhos.").font(.system(size: 12)).foregroundStyle(.gray)
                }
            } else {
                SecureField("Senha", text: $senha).textFieldStyle(.roundedBorder).textContentType(.password)
            }
            if !aviso.isEmpty { Text(aviso).font(.system(size: 13)).foregroundStyle(.red) }
            HStack(spacing: 12) {
                if definindo {
                    if codigoPedido {
                        Button("Salvar senha e entrar") { tentar { try await conta.definirSenha(alvo, codigo: codigo, senha: senha); voltar() } }
                            .disabled(ocupado || codigo.count != 6 || senha.count < 8).keyboardShortcut(.defaultAction)
                    } else {
                        Button("Mandar o código") { mandarCodigo() }.disabled(ocupado || !alvo.contains("@")).keyboardShortcut(.defaultAction)
                    }
                } else {
                    Button("Entrar") { tentar { try await conta.entrarComSenha(alvo, senha); voltar() } }
                        .disabled(ocupado || !alvo.contains("@") || senha.isEmpty).keyboardShortcut(.defaultAction)
                    Button("Esqueci a senha / criar senha") { definindo = true; senha = ""; mandarCodigo() }.disabled(!alvo.contains("@"))
                }
                Spacer()
                Button("Voltar", action: voltar).keyboardShortcut(.cancelAction)
            }
        }
        .onAppear { if emailFixo != nil { definindo = true } }
    }

    private var alvo: String { emailFixo ?? email }

    private func mandarCodigo() {
        tentar {
            if let dev = try await conta.pedirCodigoPorEmail(alvo) { codigo = dev } // só no servidor de teste
            codigoPedido = true
        }
    }

    private func tentar(_ f: @escaping @MainActor () async throws -> Void) {
        ocupado = true; aviso = ""
        Task { @MainActor in
            do { try await f() } catch { aviso = error.localizedDescription }
            ocupado = false
        }
    }
}
