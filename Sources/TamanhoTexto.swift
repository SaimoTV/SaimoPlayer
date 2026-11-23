import SwiftUI

/// Acessibilidade (Ajustes > Aparência e acessibilidade > Tamanho do texto).
///
/// As telas usam `.font(.escalado(n))` no lugar de `.system(size: n)`: o
/// tamanho escolhido multiplica todos. A barra do topo cresce junto e, se não
/// couber, troca os nomes das abas por ícones.
enum TamanhoTexto {
    static let chave = "tamanhoTexto"
    static let opcoes: [(nome: String, valor: CGFloat)] = [("Normal", 1), ("Grande", 1.15), ("Muito grande", 1.3), ("Enorme", 1.45)]
    static let chaveNegrito = "acessNegrito"
    static let chaveContraste = "acessContraste"

    static var negrito: Bool { UserDefaults.standard.bool(forKey: chaveNegrito) }
    static var contraste: Bool { UserDefaults.standard.bool(forKey: chaveContraste) }

    struct Escolha: Equatable { var escala: CGFloat; var negrito: Bool; var contraste: Bool }
    static var atual: Escolha { Escolha(escala: escala, negrito: negrito, contraste: contraste) }
    static let padrao = Escolha(escala: 1, negrito: false, contraste: false)

    static func aplicar(_ e: Escolha) {
        UserDefaults.standard.set(Double(e.escala), forKey: chave)
        UserDefaults.standard.set(e.negrito, forKey: chaveNegrito)
        UserDefaults.standard.set(e.contraste, forKey: chaveContraste)
        NotificationCenter.default.post(name: .tamanhoTextoMudou, object: nil)
    }

    static var escala: CGFloat {
        let v = UserDefaults.standard.double(forKey: chave)
        return v == 0 ? 1 : CGFloat(min(max(v, 0.8), 1.6))
    }

    /// A barra do topo cresce junto com o tamanho escolhido (sem nomes nas abas se não couber).
    static var escalaDaBarra: CGFloat { escala }

    static var nome: String { opcoes.min(by: { abs($0.valor - escala) < abs($1.valor - escala) })?.nome ?? "Normal" }

    /// Normal → Grande → Muito grande → Normal.
    static func proximo() {
        let i = opcoes.firstIndex(where: { abs($0.valor - escala) < 0.01 }) ?? 0
        UserDefaults.standard.set(Double(opcoes[(i + 1) % opcoes.count].valor), forKey: chave)
        NotificationCenter.default.post(name: .tamanhoTextoMudou, object: nil)
    }
}

extension Notification.Name {
    static let tamanhoTextoMudou = Notification.Name("saimo.tamanhoTextoMudou")
}

extension Font {
    /// `.system(size:)` com o tamanho do texto escolhido nos Ajustes.
    static func escalado(_ tamanho: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: (tamanho * TamanhoTexto.escala).rounded(), weight: TamanhoTexto.negrito ? mais(weight) : weight, design: design)
    }

    /// Um passo mais grosso (texto em negrito da acessibilidade).
    private static func mais(_ w: Font.Weight) -> Font.Weight {
        switch w {
        case .ultraLight, .thin, .light, .regular: return .semibold
        case .medium: return .bold
        case .semibold, .bold: return .heavy
        default: return .black
        }
    }
}

/// Acessibilidade com prévia: as escolhas aparecem no exemplo; só Aplicar leva ao app.
struct TelaAcessibilidade: View {
    var fechar: () -> Void
    @State private var aplicado = TamanhoTexto.atual
    @State private var rascunho = TamanhoTexto.atual

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Acessibilidade").font(.system(size: 26, weight: .bold))
            Text("Escolha e veja no exemplo. Nada muda no app até Aplicar.").foregroundStyle(.secondary)
            Picker("Tamanho do texto", selection: $rascunho.escala) {
                ForEach(TamanhoTexto.opcoes, id: \.valor) { Text($0.nome).tag($0.valor) }
            }
            .pickerStyle(.segmented)
            Toggle("Texto em negrito — letras mais grossas", isOn: $rascunho.negrito)
            Toggle("Alto contraste — texto secundário branco", isOn: $rascunho.contraste)
            previa
            HStack {
                Button("Voltar ao padrão") { rascunho = TamanhoTexto.padrao }.disabled(rascunho == TamanhoTexto.padrao)
                Spacer()
                Button("Desfazer") { rascunho = aplicado }.disabled(rascunho == aplicado)
                Button("Fechar") { fechar() }.keyboardShortcut(.cancelAction)
                Button("Aplicar") { TamanhoTexto.aplicar(rascunho); aplicado = rascunho }
                    .keyboardShortcut(.defaultAction).disabled(rascunho == aplicado)
            }
        }
        .padding(28)
        .frame(width: 620)
    }

    /// O exemplo, desenhado com o rascunho (fontes fixas, sem a escala aplicada).
    private var previa: some View {
        let k = rascunho.escala
        let peso: Font.Weight = rascunho.negrito ? .semibold : .regular
        let sec: Color = rascunho.contraste ? .white : Color(red: 0xA8 / 255, green: 0xB4 / 255, blue: 0xC0 / 255)
        return VStack(alignment: .leading, spacing: 8) {
            Text("PRÉVIA").font(.system(size: 11 * k, weight: .bold)).foregroundStyle(Tema.acento)
            Text("Filmes em alta").font(.system(size: 22 * k, weight: .bold)).foregroundStyle(.white)
            HStack(alignment: .top, spacing: 14) {
                ForEach([("A Odisseia", "2026 · Aventura"), ("Série do domingo", "T2 · E5")], id: \.0) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        LinearGradient(colors: [Color(red: 0.55, green: 0.36, blue: 0.96), Tema.acento], startPoint: .topLeading, endPoint: .bottomTrailing)
                            .frame(width: 150, height: 86).clipShape(RoundedRectangle(cornerRadius: 8))
                        Text(item.0).font(.system(size: 15 * k, weight: peso)).foregroundStyle(.white)
                        Text(item.1).font(.system(size: 12 * k, weight: peso)).foregroundStyle(sec)
                    }
                    .frame(width: 150, alignment: .leading)
                }
            }
            Text("Clique para abrir · clique com o botão direito para favoritar")
                .font(.system(size: 13 * k, weight: peso)).foregroundStyle(sec)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5])))
    }
}
