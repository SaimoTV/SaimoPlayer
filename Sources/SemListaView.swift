import SwiftUI

enum SecaoSemLista {
    case canais
    case filmes
}

struct SemListaView: View {
    let secao: SecaoSemLista
    var compacto: Bool = false

    var body: some View {
        VStack(spacing: compacto ? 8 : 16) {
            Image(systemName: secao == .canais ? "tv.slash" : "film.slash")
                .font(.system(size: compacto ? 28 : 48))
                .foregroundStyle(Tema.textoSecundario)

            Text(secao == .canais ? "Nenhum canal encontrado" : "Nenhum título encontrado")
                .font(.system(size: compacto ? 15 : 20, weight: .bold))
                .foregroundStyle(.white)

            if !compacto {
                Text(secao == .canais
                     ? "Verifique a sua conexão com a internet ou adicione listas em Ajustes."
                     : "O acervo sob demanda está temporariamente indisponível ou sendo atualizado.")
                    .font(.system(size: 14))
                    .foregroundStyle(Tema.textoSecundario)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .padding(compacto ? 12 : 32)
        .frame(maxWidth: .infinity, maxHeight: compacto ? nil : .infinity)
    }
}
