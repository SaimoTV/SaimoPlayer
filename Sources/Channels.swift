import Foundation

/// Tipos de canal e fonte. Nenhuma fonte fica no código: os canais vêm só dos
/// links configurados em Ajustes (ver RemoteCatalog).
///
/// DASH sources and HLS carrying HEVC-in-TS are repackaged by the ffmpeg
/// gateway before AVFoundation sees them; DASH also carries its CENC ClearKey.
struct Source {
    let url: String
    let referer: String?
    let userAgent: String?
    let clearKey: String?
}

struct CatalogEntry {
    let name: String
    let logo: String?
    let sources: [Source]
}

let defaultChannels: [Channel] = []
let restrictedChannels: [Channel] = []
