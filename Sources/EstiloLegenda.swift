import SwiftUI

/// Estilo da legenda externa e cor de destaque do app, guardados em UserDefaults.
///
/// A cor de destaque vale a partir da próxima abertura do app: `Tema.acento`
/// é lida uma vez, na largada.
enum EstiloLegenda {
    private static var d: UserDefaults { .standard }

    static let tamanhos: [(String, Double)] = [("Pequena", 20), ("Média", 26), ("Grande", 34), ("Enorme", 44)]
    static let cores: [(String, Color, String)] = [
        ("Branca", .white, "branca"), ("Amarela", Color(red: 1, green: 0.9, blue: 0.2), "amarela"),
        ("Ciano", Color(red: 0.31, green: 0.89, blue: 0.82), "ciano"), ("Verde", Color(red: 0.4, green: 0.95, blue: 0.4), "verde"),
    ]
    static let posicoes: [(String, CGFloat)] = [("Baixa", 0), ("Média", 60), ("Alta", 140)]

    static var indiceTamanho: Int { min(max(d.object(forKey: "legenda.tamanho") as? Int ?? 1, 0), tamanhos.count - 1) }
    static var indiceCor: Int { min(max(d.integer(forKey: "legenda.cor"), 0), cores.count - 1) }
    static var indicePosicao: Int { min(max(d.integer(forKey: "legenda.posicao"), 0), posicoes.count - 1) }
    static var fundo: Bool { d.object(forKey: "legenda.fundo") as? Bool ?? true }

    static var tamanho: Double { tamanhos[indiceTamanho].1 }
    static var cor: Color { cores[indiceCor].1 }
    static var elevacao: CGFloat { posicoes[indicePosicao].1 }

    static func proximoTamanho() { d.set((indiceTamanho + 1) % tamanhos.count, forKey: "legenda.tamanho") }
    static func proximaCor() { d.set((indiceCor + 1) % cores.count, forKey: "legenda.cor") }
    static func proximaPosicao() { d.set((indicePosicao + 1) % posicoes.count, forKey: "legenda.posicao") }
    static func alternarFundo() { d.set(!fundo, forKey: "legenda.fundo") }

    // Cor de destaque do app.
    static let temas: [(String, Color)] = [
        ("Ciano", Color(red: 0x4F / 255, green: 0xE3 / 255, blue: 0xD0 / 255)),
        ("Violeta", Color(red: 0xA7 / 255, green: 0x8B / 255, blue: 0xFA / 255)),
        ("Laranja", Color(red: 0xFB / 255, green: 0x92 / 255, blue: 0x3C / 255)),
        ("Rosa", Color(red: 0xF4 / 255, green: 0x72 / 255, blue: 0xB6 / 255)),
        ("Verde", Color(red: 0x4A / 255, green: 0xDE / 255, blue: 0x80 / 255)),
    ]
    static var indiceTema: Int { min(max(d.integer(forKey: "tema.acento"), 0), temas.count - 1) }
    static func proximoTema() { d.set((indiceTema + 1) % temas.count, forKey: "tema.acento") }
}
