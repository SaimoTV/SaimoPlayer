import SwiftUI

/// Ajustes > Conta Saimo. Sem conta: o QR (e o código curto) para entrar pelo
/// celular, que já está logado; pergunta ao servidor a cada 5 s e pede outro
/// código quando vence. Com conta: e-mail, última sincronização, sincronizar e sair.
struct TelaConta: View {
    @ObservedObject private var conta = Conta.shared
    let fechar: () -> Void
    /// Dentro de outra tela (as boas-vindas): sem moldura própria e com o QR em coluna.
    var embutida = false

    @State private var codigo = "…"
    @State private var imagem: NSImage?
    @State private var situacao = "Pedindo um código…"
    @State private var tarefa: Task<Void, Never>?
    /// Formulário de e-mail e senha aberto (sem conta: entrar; com conta: criar ou trocar a senha).
    @State private var comEmail = false

    var body: some View {
        Group {
            if comEmail {
                FormSenha(emailFixo: conta.logado ? conta.email : nil, voltarAoQr: embutida && !conta.logado) { comEmail = false }
            } else if conta.logado { logado } else { qr }
        }
        .padding(embutida ? 0 : 36)
        .frame(width: embutida ? nil : 760)
        .background(embutida ? Color.clear : Color(red: 0.06, green: 0.09, blue: 0.15))
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
                if conta.email != nil { Button("Trocar a senha") { comEmail = true } }
                Button("Sair da conta") { Task { await conta.sair() } }
                Spacer()
                Button("Fechar", action: fechar).keyboardShortcut(.cancelAction)
            }
            .padding(.top, 8)
        }
    }

    private var qr: some View {
        (embutida ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14)) : AnyLayout(HStackLayout(alignment: .center, spacing: 32))) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(.white)
                if let imagem { Image(nsImage: imagem).interpolation(.none).resizable().scaledToFit().padding(12) }
            }
            .frame(width: embutida ? 190 : 240, height: embutida ? 190 : 240)
            VStack(alignment: .leading, spacing: 12) {
                if !embutida { Text("Entrar na Conta Saimo").font(.system(size: 24, weight: .bold)).foregroundStyle(.white) }
                Text("No celular com o Saimo e a sua conta, leia o QR com a câmera. Ou abra Ajustes > Conta Saimo > Entrar numa TV e digite o código:")
                    .font(.system(size: 14)).foregroundStyle(Tema.textoSecundario).fixedSize(horizontal: false, vertical: true)
                Text(codigo).font(.system(size: 38, weight: .heavy, design: .monospaced)).tracking(4)
                    .foregroundStyle(Color(red: 0.18, green: 0.83, blue: 0.75)).textSelection(.enabled)
                Text(situacao).font(.system(size: 13)).foregroundStyle(Tema.textoSecundario)
                Button("Entrar com e-mail e senha") { comEmail = true }
                if !embutida {
                    HStack {
                        Text("Sem conta, tudo continua só neste Mac.").font(.system(size: 12)).foregroundStyle(.gray)
                        Spacer()
                        Button("Fechar", action: fechar).keyboardShortcut(.cancelAction)
                    }
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

/// Sem conta: entrar ou criar a conta com e-mail e senha (o e-mail não é
/// verificado). Com conta (`emailFixo`): trocar a senha.
private struct FormSenha: View {
    @ObservedObject private var conta = Conta.shared
    let emailFixo: String?
    var voltarAoQr = false
    let voltar: () -> Void

    @State private var email = ""
    @State private var senha = ""
    @State private var nova = ""
    @State private var criando = false
    @State private var ocupado = false
    @State private var aviso = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(emailFixo != nil ? "Trocar a senha" : (criando ? "Criar conta" : "Entrar com e-mail e senha"))
                .font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
            if let emailFixo {
                Text(emailFixo).foregroundStyle(Tema.textoSecundario)
                SecureField("Senha atual (em branco se a conta não tem)", text: $senha).textFieldStyle(.roundedBorder).textContentType(.password)
                SecureField("Senha nova (8 ou mais)", text: $nova).textFieldStyle(.roundedBorder).textContentType(.newPassword)
                Text("Trocar a senha tira a conta dos outros aparelhos.").font(.system(size: 12)).foregroundStyle(.gray)
            } else {
                TextField("Seu e-mail", text: $email).textFieldStyle(.roundedBorder).textContentType(.username)
                SecureField(criando ? "Crie uma senha (8 ou mais)" : "Senha", text: $senha).textFieldStyle(.roundedBorder)
                    .textContentType(criando ? .newPassword : .password)
            }
            if !aviso.isEmpty { Text(aviso).font(.system(size: 13)).foregroundStyle(aviso.hasPrefix("Pronto") ? .green : .red) }
            HStack(spacing: 12) {
                if emailFixo != nil {
                    Button("Trocar a senha") {
                        tentar { try await conta.trocarSenha(atual: senha, nova: nova); aviso = "Pronto: senha trocada."; senha = ""; nova = "" }
                    }.disabled(ocupado || nova.count < 8).keyboardShortcut(.defaultAction)
                } else {
                    Button(criando ? "Criar conta" : "Entrar") {
                        tentar {
                            if criando { try await conta.cadastrar(email, senha) } else { try await conta.entrarComSenha(email, senha) }
                            voltar()
                        }
                    }
                    .disabled(ocupado || !email.contains("@") || (criando ? senha.count < 8 : senha.isEmpty)).keyboardShortcut(.defaultAction)
                    Button(criando ? "Já tenho conta" : "Criar conta") { criando.toggle(); aviso = ""; senha = "" }
                }
                Spacer()
                Button(voltarAoQr ? "Voltar ao QR code" : "Voltar", action: voltar).keyboardShortcut(.cancelAction)
            }
        }
    }

    private func tentar(_ f: @escaping @MainActor () async throws -> Void) {
        ocupado = true; aviso = ""
        Task { @MainActor in
            do { try await f() } catch { aviso = error.localizedDescription; if emailFixo == nil { senha = "" } }
            ocupado = false
        }
    }
}
