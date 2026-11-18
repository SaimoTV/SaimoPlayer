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

    var body: some View {
        Group {
            if conta.logado { logado } else { qr }
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
