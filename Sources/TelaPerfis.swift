import SwiftUI
import AppKit

/// Pedido para abrir a tela de perfis (do avatar da barra, dos Ajustes).
extension Notification.Name {
    static let abrirPerfis = Notification.Name("saimo.abrirPerfis")
}

/// Avatar de um perfil: a imagem, ou a inicial do nome se o avatar for desconhecido.
struct AvatarPerfil: View {
    let nome: String
    let avatar: String
    var tamanho: CGFloat = 96

    var body: some View {
        Group {
            if let img = Perfis.imagem(avatar) {
                Image(nsImage: img).resizable().interpolation(.high)
            } else {
                ZStack {
                    LinearGradient(colors: [Color(red: 0.49, green: 0.55, blue: 1), Color(red: 0.1, green: 0.12, blue: 0.36)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Text(String(nome.trimmingCharacters(in: .whitespaces).first ?? "?").uppercased())
                        .font(.system(size: tamanho * 0.44, weight: .heavy)).foregroundStyle(.white)
                }
            }
        }
        .frame(width: tamanho, height: tamanho)
        .clipShape(RoundedRectangle(cornerRadius: tamanho * 0.24, style: .continuous))
    }
}

/// "Quem está assistindo?": escolher, gerenciar e editar perfis (até 10, com
/// avatar). Perfil Kids: sair dele, gerenciar estando nele e editar um Kids
/// pedem o código de 4 dígitos. Contrato em docs/perfis.md.
struct TelaPerfis: View {
    enum Modo: Equatable { case escolher, gerenciar, editar(Perfis.Perfil?) }

    let obrigatoria: Bool
    let aoFechar: () -> Void
    @State var modo: Modo
    @State private var pedido: PedidoDeCodigo?
    @State private var destrancado = false
    @State private var versao = 0

    struct PedidoDeCodigo: Identifiable {
        let id = UUID()
        let perfil: Perfis.Perfil
        let motivo: String
        let depois: () -> Void
    }

    init(obrigatoria: Bool, modo: Modo = .escolher, aoFechar: @escaping () -> Void) {
        self.obrigatoria = obrigatoria
        self.aoFechar = aoFechar
        _modo = State(initialValue: modo)
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.08, green: 0.1, blue: 0.27), Color(red: 0.04, green: 0.06, blue: 0.16)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            if let pedido {
                PedirCodigoView(perfil: pedido.perfil, motivo: pedido.motivo) {
                    if pedido.perfil.id == Perfis.idAtivo { destrancado = true }
                    self.pedido = nil
                    pedido.depois()
                } aoCancelar: { self.pedido = nil }
            } else {
                switch modo {
                case .escolher, .gerenciar: grade
                case .editar(let p): EditarPerfilView(perfil: p) { modo = .gerenciar; versao += 1 }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .perfisMudaram)) { _ in versao += 1 }
        .onExitCommand {
            if pedido != nil { pedido = nil }
            else if case .editar = modo { modo = .gerenciar }
            else if modo == .gerenciar { modo = .escolher }
            else if !obrigatoria { aoFechar() }
        }
    }

    private func comCodigo(_ p: Perfis.Perfil, _ motivo: String, _ acao: @escaping () -> Void) {
        if !Perfis.pedeCodigo(p) || (destrancado && p.id == Perfis.idAtivo) { acao(); return }
        pedido = PedidoDeCodigo(perfil: p, motivo: motivo, depois: acao)
    }

    private var grade: some View {
        let gerenciar = modo == .gerenciar
        let lista = Perfis.todos
        let atual = Perfis.ativo
        return VStack(spacing: 26) {
            Text(gerenciar ? "Gerenciar perfis" : "Quem está assistindo?")
                .font(.system(size: 40, weight: .heavy)).foregroundStyle(.white)
            if gerenciar {
                Text("Clique num perfil para mudar o nome, o avatar ou o Kids.").foregroundStyle(.white.opacity(0.6))
            }
            HStack(alignment: .top, spacing: 26) {
                ForEach(lista) { p in
                    BotaoDePerfil(nome: p.nome, avatar: p.avatar, atual: p.id == atual.id && !gerenciar,
                                  kids: p.ehKids, editando: gerenciar) {
                        if gerenciar {
                            comCodigo(p, "Para editar o perfil \(p.nome), digite o código dele.") { modo = .editar(p) }
                        } else if p.id == atual.id {
                            Perfis.escolhidoNestaSessao = true
                            aoFechar()
                        } else {
                            comCodigo(atual, "Para sair do perfil \(atual.nome), digite o código.") { Perfis.entrar(p.id) }
                        }
                    }
                }
                if lista.count < Perfis.maximo && (gerenciar || !atual.ehKids) {
                    Button {
                        if gerenciar { modo = .editar(nil) }
                        else { comCodigo(atual, "Para criar um perfil, digite o código deste perfil Kids.") { modo = .editar(nil) } }
                    } label: {
                        VStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                                .foregroundStyle(.white.opacity(0.4))
                                .frame(width: 120, height: 120)
                                .overlay(Image(systemName: "plus").font(.system(size: 42)).foregroundStyle(.white.opacity(0.8)))
                            Text("Adicionar perfil").foregroundStyle(.white.opacity(0.75))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 14) {
                if gerenciar {
                    Button("Pronto") { modo = .escolher }.buttonStyle(BotaoPerfis(principal: true))
                } else {
                    Button("Gerenciar perfis") {
                        comCodigo(atual, "Para gerenciar os perfis, digite o código deste perfil Kids.") { modo = .gerenciar }
                    }.buttonStyle(BotaoPerfis())
                    if !obrigatoria { Button("Fechar") { aoFechar() }.buttonStyle(BotaoPerfis()) }
                }
            }
            if !gerenciar {
                Toggle("Perguntar quem está assistindo ao abrir", isOn: Binding(
                    get: { Perfis.perguntarAoAbrir }, set: { Perfis.perguntarAoAbrir = $0; versao += 1 }))
                    .toggleStyle(.checkbox).foregroundStyle(.white.opacity(0.8))
            }
            Text("Cada perfil tem os seus favoritos, o que está assistindo e os recentes. As listas e os ajustes valem para todos. Até \(Perfis.maximo) perfis. O perfil Kids só mostra filmes e séries classificados até 12 anos e nada adulto.")
                .font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.45)).multilineTextAlignment(.center).frame(maxWidth: 560)
        }
        .padding(40)
        .id(versao)
    }
}

private struct BotaoDePerfil: View {
    let nome: String
    let avatar: String
    let atual: Bool
    let kids: Bool
    let editando: Bool
    let acao: () -> Void
    @State private var sobre = false

    var body: some View {
        Button(action: acao) {
            VStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    AvatarPerfil(nome: nome, avatar: avatar, tamanho: 120)
                        .opacity(editando ? 0.5 : 1)
                        .overlay {
                            if editando { Image(systemName: "pencil").font(.system(size: 38, weight: .bold)).foregroundStyle(.white) }
                        }
                        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .strokeBorder(sobre ? Color.white : (atual ? Tema.acento : .clear), lineWidth: 4))
                    if kids {
                        Text("KIDS").font(.system(size: 11, weight: .heavy)).foregroundStyle(Color(red: 0.16, green: 0.08, blue: 0))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Color(red: 1, green: 0.71, blue: 0.24)))
                            .offset(x: 6, y: 6)
                    }
                }
                Text(nome).font(.system(size: 16, weight: atual ? .bold : .medium))
                    .foregroundStyle(.white.opacity(sobre || atual ? 1 : 0.75)).lineLimit(1).frame(maxWidth: 130)
            }
            .scaleEffect(sobre ? 1.06 : 1)
            .animation(.easeOut(duration: 0.15), value: sobre)
        }
        .buttonStyle(.plain)
        .onHover { sobre = $0 }
    }
}

struct BotaoPerfis: ButtonStyle {
    var principal = false
    var perigo = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(principal ? Color.black : (perigo ? Color(red: 1, green: 0.7, blue: 0.7) : .white))
            .padding(.horizontal, 22).padding(.vertical, 11)
            .background(Capsule().fill(principal ? Tema.acento : Color.white.opacity(configuration.isPressed ? 0.15 : 0.07)))
            .overlay(Capsule().strokeBorder(principal ? Color.clear : Color.white.opacity(0.25)))
    }
}

/// Pede o código de 4 dígitos do perfil Kids (sair dele, editar, abrir os Ajustes).
struct PedirCodigoView: View {
    let perfil: Perfis.Perfil
    let motivo: String
    let aoConfirmar: () -> Void
    let aoCancelar: () -> Void
    @State private var codigo = ""
    @State private var erro = false
    @FocusState private var foco: Bool

    var body: some View {
        VStack(spacing: 18) {
            AvatarPerfil(nome: perfil.nome, avatar: perfil.avatar, tamanho: 90)
            Text("Código do perfil \(perfil.nome)").font(.system(size: 30, weight: .heavy)).foregroundStyle(.white)
            Text(motivo).foregroundStyle(.white.opacity(0.65))
            SecureField("••••", text: $codigo)
                .textFieldStyle(.plain)
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)
                .frame(width: 180, height: 56)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.25)))
                .focused($foco)
                .onChange(of: codigo) { _, novo in
                    let limpo = String(novo.filter(\.isNumber).prefix(4))
                    if limpo != novo { codigo = limpo; return }
                    erro = false
                    if limpo.count == 4 { conferir() }
                }
                .onSubmit { conferir() }
            Text(erro ? "Código errado. Tente de novo." : " ").foregroundStyle(Color(red: 1, green: 0.7, blue: 0.7))
            Button("Cancelar", action: aoCancelar).buttonStyle(BotaoPerfis())
        }
        .onAppear { foco = true }
    }

    private func conferir() {
        guard codigo.count == 4 else { return }
        if Perfis.conferirCodigo(perfil, codigo) { aoConfirmar() } else { erro = true; codigo = "" }
    }
}

/// Criar ou editar: nome, avatar e Kids (com o código).
private struct EditarPerfilView: View {
    let perfil: Perfis.Perfil?
    let aoVoltar: () -> Void
    @State private var nome = ""
    @State private var avatar = Perfis.avatares[0]
    @State private var kids = false
    @State private var cod1 = ""
    @State private var cod2 = ""
    @State private var aviso = ""
    @State private var confirmarApagar = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text(perfil == nil ? "Novo perfil" : "Editar perfil").font(.system(size: 34, weight: .heavy)).foregroundStyle(.white)
                HStack(spacing: 22) {
                    AvatarPerfil(nome: nome.isEmpty ? "?" : nome, avatar: avatar, tamanho: 104)
                    TextField("Nome do perfil", text: $nome)
                        .textFieldStyle(.plain).font(.system(size: 20, weight: .semibold))
                        .padding(.horizontal, 16).frame(width: 360, height: 50)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.07)))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.22)))
                        .onChange(of: nome) { _, n in if n.count > Perfis.maxNome { nome = String(n.prefix(Perfis.maxNome)) } }
                }
                Text("Escolha um avatar").foregroundStyle(.white.opacity(0.6))
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(68), spacing: 12), count: 7), spacing: 12) {
                    ForEach(Perfis.avatares, id: \.self) { a in
                        Button { avatar = a } label: {
                            AvatarPerfil(nome: a, avatar: a, tamanho: 62)
                                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(a == avatar ? Tema.acento : .clear, lineWidth: 3))
                        }.buttonStyle(.plain)
                    }
                }
                if perfil?.id != Perfis.principal {
                    Toggle(isOn: $kids) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Perfil Kids").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                            Text("Só filmes e séries classificados até 12 anos, nada adulto. Sair dele pede um código de 4 números.")
                                .font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .toggleStyle(.checkbox).frame(width: 520, alignment: .leading)
                    if kids {
                        HStack(spacing: 12) {
                            SecureField(precisaCodigo ? "Código" : "Novo código (opcional)", text: $cod1).textFieldStyle(.roundedBorder).frame(width: 180)
                            SecureField("Repita o código", text: $cod2).textFieldStyle(.roundedBorder).frame(width: 180)
                        }
                    }
                }
                Text(aviso.isEmpty ? " " : aviso).foregroundStyle(Color(red: 1, green: 0.7, blue: 0.7))
                HStack(spacing: 12) {
                    Button("Salvar", action: salvar).buttonStyle(BotaoPerfis(principal: true))
                    Button("Cancelar", action: aoVoltar).buttonStyle(BotaoPerfis())
                    if let p = perfil, p.id != Perfis.principal {
                        Button(confirmarApagar ? "Apagar mesmo (favoritos e progresso somem)" : "Apagar perfil") {
                            if confirmarApagar { Perfis.apagar(p.id); aoVoltar() } else { confirmarApagar = true }
                        }.buttonStyle(BotaoPerfis(perigo: true))
                    }
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            nome = perfil?.nome ?? ""
            avatar = perfil?.avatar ?? (Perfis.avatares.first { a in !Perfis.todos.contains { $0.avatar == a } } ?? Perfis.avatares[0])
            kids = perfil?.ehKids ?? false
        }
    }

    private var precisaCodigo: Bool { kids && !(perfil?.ehKids == true && !(perfil?.codigo ?? "").isEmpty) }

    private func salvar() {
        guard !nome.trimmingCharacters(in: .whitespaces).isEmpty else { aviso = "Escreva um nome para o perfil."; return }
        var kidsCodigo: String?
        if kids {
            if !cod1.isEmpty || !cod2.isEmpty || precisaCodigo {
                guard cod1.count == 4, cod1.allSatisfy(\.isNumber) else { aviso = "O código do Kids tem 4 números."; return }
                guard cod1 == cod2 else { aviso = "Os dois códigos não são iguais."; return }
                kidsCodigo = cod1
            }
        } else if perfil?.ehKids == true { kidsCodigo = "" }
        if let p = perfil { Perfis.editar(p.id, nome: nome, avatar: avatar, kidsCodigo: kidsCodigo) }
        else { Perfis.criar(nome: nome, avatar: avatar, kidsCodigo: kidsCodigo) }
        aoVoltar()
    }
}
