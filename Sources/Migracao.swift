import Foundation

enum Migracao {
    private static let chave = "migradoParaPages"

    static func executarSeNecessario() {
        guard !UserDefaults.standard.bool(forKey: chave) else { return }
        UserDefaults.standard.set(true, forKey: chave)
    }
}
