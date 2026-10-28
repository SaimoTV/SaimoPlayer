import SwiftUI
import AppKit

/// O que os botões de "Minhas listas" fazem fora da tela (menu "Importar
/// lista .m3u…" e Ajustes usam o mesmo caminho).
@MainActor
enum MinhasListasAcoes {
    /// Escolhe um arquivo .m3u/.m3u8 e cria uma lista com ele. Em caso de erro
    /// devolve a mensagem; se a pessoa cancelar, devolve nulo e `escolheu` false.
    static func escolherArquivo(nome: String = "") -> (escolheu: Bool, erro: String?) {
        let painel = NSOpenPanel()
        painel.allowsOtherFileTypes = true
        painel.allowsMultipleSelection = false
        painel.canChooseDirectories = false
        painel.message = "Escolha uma lista .m3u ou .m3u8"
        guard painel.runModal() == .OK, let url = painel.url else { return (false, nil) }
        return (true, MinhasListas.shared.adicionar(arquivo: url, nome: nome))
    }

    /// O "Importar lista .m3u…" de sempre: agora cria uma lista em "Minhas listas".
    static func importarArquivo() {
        let r = escolherArquivo()
        guard let erro = r.erro else { return }
        let alerta = NSAlert()
        alerta.messageText = "Não deu para adicionar a lista"
        alerta.informativeText = erro
        alerta.addButton(withTitle: "OK")
        alerta.runModal()
    }
}

/// A seção "Minhas listas" dos Ajustes: lista as listas e abre o formulário.
struct MinhasListasConteudo: View {
    @ObservedObject private var minhas = MinhasListas.shared
    @State private var adicionando = false
    @State private var paraRemover: ListaSalva?
    @State private var erro: String?

    var body: some View {
        VStack(spacing: 0) {
            texto
            ForEach(minhas.listas) { lista in
                linhaDaLista(lista)
            }
            if let erro {
                Label(erro, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
            }
            botaoAdicionar
        }
        .sheet(isPresented: $adicionando) {
            AdicionarListaView { adicionando = false }
        }
        .alert("Remover \"\(paraRemover?.nome ?? "")\"?", isPresented: Binding(
            get: { paraRemover != nil }, set: { if !$0 { paraRemover = nil } })) {
            Button("Remover", role: .destructive) {
                if let l = paraRemover { minhas.remover(l.id); erro = nil }
                paraRemover = nil
            }
            Button("Cancelar", role: .cancel) { paraRemover = nil }
        } message: {
            Text("Os canais dessa lista saem do app.")
        }
    }

    private var texto: some View {
        HStack(spacing: 14) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Tema.acento)
                .frame(width: 26)
            Text("Cole o link de uma lista .m3u. Ela fica só neste aparelho.")
                .font(.system(size: 12))
                .foregroundStyle(Tema.textoSecundario)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func linhaDaLista(_ lista: ListaSalva) -> some View {
        let baixando = minhas.atualizando.contains(lista.id)
        return HStack(spacing: 14) {
            Image(systemName: lista.ativa ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(lista.ativa ? Tema.acento : Tema.textoApagado)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(lista.nome).font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                Text("\(lista.canaisVisiveis.count) canais · \(MinhasListas.rotuloDeTempo(lista.atualizadaEm))"
                     + (lista.ativa ? "" : " · desativada"))
                    .font(.system(size: 12)).foregroundStyle(Tema.textoSecundario)
            }
            Spacer()
            if baixando { ProgressView().controlSize(.small) }
            if !lista.veioDeArquivo {
                acao("Atualizar", "arrow.clockwise") {
                    Task { erro = await minhas.atualizar(lista.id) }
                }
                .disabled(baixando)
            }
            acao(lista.ativa ? "Desativar" : "Ativar", lista.ativa ? "eye.slash" : "eye") {
                minhas.alternar(lista.id)
            }
            acao("Remover", "trash") { paraRemover = lista }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private func acao(_ titulo: String, _ icone: String, _ feito: @escaping () -> Void) -> some View {
        Button(action: feito) {
            Label(titulo, systemImage: icone)
                .font(.system(size: 12))
                .padding(.vertical, 5)
                .padding(.horizontal, 9)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private var botaoAdicionar: some View {
        Button { erro = nil; adicionando = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Tema.acento)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Adicionar lista").font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                    Text("Pelo link ou escolhendo um arquivo").font(.system(size: 12))
                        .foregroundStyle(Tema.textoSecundario)
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
        .buttonStyle(.plain)
    }
}

/// A janela de adicionar: link e nome opcional, ou um arquivo.
struct AdicionarListaView: View {
    let fechar: () -> Void
    @ObservedObject private var minhas = MinhasListas.shared
    @State private var link = ""
    @State private var nome = ""
    @State private var erro: String?
    @FocusState private var focoNoLink: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Adicionar lista", systemImage: "list.bullet.rectangle")
                .font(.title2.weight(.semibold))
            Text("Cole o link de uma lista .m3u. Ela fica só neste aparelho.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Link da lista (.m3u)").font(.subheadline.weight(.medium))
                TextField("https://…", text: $link)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .focused($focoNoLink)
                    .disabled(minhas.adicionando)
                    .onSubmit { adicionar() }
                    .onChange(of: link) { _, _ in erro = nil }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Nome (opcional)").font(.subheadline.weight(.medium))
                TextField("Lista 1", text: $nome)
                    .textFieldStyle(.roundedBorder)
                    .disabled(minhas.adicionando)
                    .onSubmit { adicionar() }
            }

            if minhas.adicionando {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Baixando a lista…").font(.callout).foregroundStyle(.secondary)
                }
            } else if let erro {
                Label(erro, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            HStack {
                Button("Cancelar", action: fechar)
                    .keyboardShortcut(.cancelAction)
                Button("Escolher arquivo") { escolherArquivo() }
                    .disabled(minhas.adicionando)
                Spacer()
                Button("Adicionar") { adicionar() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(minhas.adicionando
                              || link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear { focoNoLink = true }
    }

    private func adicionar() {
        guard !minhas.adicionando else { return }
        Task {
            if let e = await minhas.adicionar(link: link, nome: nome) { erro = e; focoNoLink = true } else { fechar() }
        }
    }

    private func escolherArquivo() {
        let r = MinhasListasAcoes.escolherArquivo(nome: nome)
        guard r.escolheu else { return }
        if let e = r.erro { erro = e } else { fechar() }
    }
}
