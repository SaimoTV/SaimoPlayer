import SwiftUI

/// Estado reativo para notificar as telas quando as listas de canais ou VOD mudam.
@MainActor
final class ListasEstado: ObservableObject {
    static let shared = ListasEstado()

    @Published var geracao: Int = 0
    @Published var canais: String? = Enderecos.canais
    @Published var filmes: String? = Enderecos.filmes

    func atualizar() {
        geracao += 1
    }
}
