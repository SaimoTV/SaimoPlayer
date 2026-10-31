import SwiftUI
import Combine

/// Estado reativo para notificar as telas quando as listas de canais ou VOD mudam.
@MainActor
final class ListasEstado: ObservableObject {
    static let shared = ListasEstado()

    @Published var geracao: Int = 0
    @Published var canais: String = Enderecos.canais
    @Published var filmes: String = Enderecos.filmes

    private var cancellables = Set<AnyCancellable>()

    private init() {
        NotificationCenter.default.publisher(for: Enderecos.mudou)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.atualizar()
            }
            .store(in: &cancellables)
    }

    func atualizar() {
        canais = Enderecos.canais
        filmes = Enderecos.filmes
        geracao += 1
    }
}
