import AppKit
import SwiftUI

/// Brilho do app (0 a 100; 100 é o normal): um véu preto por cima da janela,
/// não o brilho da tela do Mac. Em 0 a janela fica preta; qualquer tecla ou
/// clique traz o brilho de volta, devagar: quem não vê nada não acharia o ajuste.
@MainActor
final class Brilho: ObservableObject {
    static let shared = Brilho()
    static let escuro = 5

    /// O que a tela mostra agora (anima na volta); o guardado é `valor`.
    @Published private(set) var exibido: Double
    var valor: Int {
        get { UserDefaults.standard.object(forKey: "brilhoApp") as? Int ?? 100 }
        set {
            let v = min(100, max(0, newValue))
            UserDefaults.standard.set(v, forKey: "brilhoApp")
            withAnimation(.easeInOut(duration: 0.25)) { exibido = Double(v) }
            SaimoConnect.shared.avisarEstado(forcado: true)
        }
    }

    private var monitor: Any?

    private init() {
        exibido = Double(UserDefaults.standard.object(forKey: "brilhoApp") as? Int ?? 100)
        // No escuro, a tecla ou o clique só servem para acender: não chegam ao app.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { evento in
            let engolir = MainActor.assumeIsolated { () -> Bool in
                guard Brilho.shared.valor <= Brilho.escuro else { return false }
                Brilho.shared.voltarAoNormal()
                return true
            }
            return engolir ? nil : evento
        }
    }

    func voltarAoNormal() {
        UserDefaults.standard.set(100, forKey: "brilhoApp")
        withAnimation(.easeInOut(duration: 1.5)) { exibido = 100 }
        SaimoConnect.shared.avisarEstado(forcado: true)
    }
}

/// O véu, por cima de tudo na janela.
struct VeuDeBrilho: View {
    @ObservedObject var brilho = Brilho.shared
    var body: some View {
        Color.black
            .opacity(1 - brilho.exibido / 100)
            .allowsHitTesting(false)
            .ignoresSafeArea()
    }
}
