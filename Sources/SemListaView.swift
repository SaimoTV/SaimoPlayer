import SwiftUI

enum SecaoSemLista {
    case canais
    case filmes
}

struct SemListaView: View {
    let secao: SecaoSemLista
    var compacto: Bool = false
    @ObservedObject private var minhas = MinhasListas.shared
    @ObservedObject private var addons = AddonStore.shared

    /// Já há alguma lista (do Saimo ou da pessoa) ou addon ativo: o vazio é falha de carga, não falta de configuração.
    private var temAlgumaLista: Bool {
        Enderecos.canaisAtivos || Vod.temAcervo || !minhas.listas.isEmpty || addons.temAtivos
    }

    private var textoDeAjuda: String {
        if !temAlgumaLista {
            return "Bem-vindo ao Saimo! Para começar, adicione uma lista M3U (só o link já basta), uma lista com usuário e senha, o endereço de uma lista do Saimo ou um addon HTTP Stremio."
        }
        return secao == .canais
            ? "Verifique a sua conexão com a internet ou adicione listas em Ajustes."
            : "O acervo sob demanda está temporariamente indisponível ou sendo atualizado."
    }

    var body: some View {
        VStack(spacing: compacto ? 8 : 16) {
            Image(systemName: secao == .canais ? "tv.slash" : "film.slash")
                .font(.escalado(compacto ? 28 : 48))
                .foregroundStyle(Tema.textoSecundario)

            Text(secao == .canais ? "Nenhum canal encontrado" : "Nenhum título encontrado")
                .font(.escalado(compacto ? 15 : 20, weight: .bold))
                .foregroundStyle(.white)

            if !compacto {
                Text(textoDeAjuda)
                    .font(.escalado(14))
                    .foregroundStyle(Tema.textoSecundario)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                if !temAlgumaLista {
                    HStack(spacing: 10) {
                        Button { MinhasListas.shared.pedirNova() } label: {
                            Label("Adicionar lista", systemImage: "link.badge.plus").font(.escalado(13, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        Button { VodEstado.shared.secao = .ajustes } label: {
                            Label("Endereços do Saimo", systemImage: "gearshape").font(.escalado(13))
                        }
                        .buttonStyle(.bordered)
                        Button { VodEstado.shared.mostrarAddons = true } label: {
                            Label("Addons e Debrid", systemImage: "puzzlepiece.extension").font(.escalado(13))
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(compacto ? 12 : 32)
        .frame(maxWidth: .infinity, maxHeight: compacto ? nil : .infinity)
    }
}
