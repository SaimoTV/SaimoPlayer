import Foundation
@preconcurrency import UserNotifications

/// Avisos de episódios novos nas séries favoritas.
///
/// O catálogo diz quantos episódios cada série tem. Para cada série favorita
/// guarda-se a contagem "já vista"; se o catálogo passa a ter mais, nasce um
/// aviso (notificação do sistema) que fica em Ajustes até ser dispensado. A
/// primeira olhada numa série só marca a contagem, sem avisar.
@MainActor
enum NovosEpisodios {
    private static let chaveVistos = "novosEpisodios.vistos"
    private static let chaveAvisos = "novosEpisodios.avisos"
    private static var rodando = false

    private static func chave(_ i: VodFavoritos.Item) -> String { "\(i.titulo)|\(i.ano)" }

    /// "Título|ano" -> episódios a mais desde a última vez.
    static func avisos() -> [String: Int] {
        Perfis.defaults.dictionary(forKey: chaveAvisos) as? [String: Int] ?? [:]
    }

    static func resumo() -> String {
        let a = avisos()
        return a.isEmpty ? "Nenhum episódio novo" : "\(a.values.reduce(0, +)) novos em \(a.count) séries · clique dispensa"
    }

    static func dispensarTodos() {
        var vistos = Perfis.defaults.dictionary(forKey: chaveVistos) as? [String: Int] ?? [:]
        for k in avisos().keys { vistos[k] = nil }
        Perfis.defaults.set(vistos, forKey: chaveVistos)
        Perfis.defaults.removeObject(forKey: chaveAvisos)
    }

    /// Roda uns segundos depois de abrir o app e a cada 30 minutos.
    static func iniciar() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(25))
            while !Task.isCancelled {
                await verificar()
                try? await Task.sleep(for: .seconds(1800))
            }
        }
    }

    static func verificar() async {
        guard !rodando else { return }
        rodando = true
        defer { rodando = false }
        let favoritas = VodFavoritos.shared.itens.filter { $0.serie && !$0.letra.isEmpty }
        guard !favoritas.isEmpty else { return }
        var vistos = Perfis.defaults.dictionary(forKey: chaveVistos) as? [String: Int] ?? [:]
        var avisos = avisos()
        var novas: [String] = []
        var porLetra: [String: [Serie]] = [:]
        for item in favoritas {
            if porLetra[item.letra] == nil { porLetra[item.letra] = await Vod.series(letra: item.letra) }
            let lista = porLetra[item.letra] ?? []
            guard let achada = lista.first(where: { $0.titulo == item.titulo && $0.ano == item.ano })
                ?? lista.first(where: { $0.titulo == item.titulo }), achada.episodios > 0 else { continue }
            let k = chave(item)
            guard let visto = vistos[k] else { vistos[k] = achada.episodios; continue }
            if achada.episodios > visto {
                if avisos[k] == nil { novas.append(item.titulo) }
                avisos[k] = achada.episodios - visto
            } else if achada.episodios < visto {
                // O catálogo foi reorganizado: recomeça a conta sem avisar.
                vistos[k] = achada.episodios
                avisos[k] = nil
            }
        }
        Perfis.defaults.set(vistos, forKey: chaveVistos)
        Perfis.defaults.set(avisos, forKey: chaveAvisos)
        if !novas.isEmpty { notificar(novas) }
    }

    private static func notificar(_ titulos: [String]) {
        let centro = UNUserNotificationCenter.current()
        centro.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            guard ok else { return }
            let c = UNMutableNotificationContent()
            c.title = "Episódio novo"
            c.body = titulos.prefix(3).joined(separator: ", ") + (titulos.count > 3 ? " e mais \(titulos.count - 3)" : "")
            centro.add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
        }
    }
}
