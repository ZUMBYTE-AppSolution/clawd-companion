import Foundation

struct ArenaTotals: Codable, Equatable {
    private(set) var rounds = 0
    private(set) var points = 0
    private(set) var kills = 0
    private(set) var deaths = 0
    private(set) var wins = 0
    private(set) var bossKills = 0
    private var lastRound: UUID?

    // The local coordinator owns one live round and emits its terminal frame once.
    // The server keeps a separate, authoritative record of ranked games.
    mutating func record(id: UUID, stats: VirusArcade.RunStats) -> Bool {
        guard stats.engaged, stats.deaths + stats.victories == 1, lastRound != id else { return false }
        lastRound = id
        rounds += 1
        points += stats.score
        kills += stats.lastHits
        deaths += stats.personalDeaths
        wins += stats.personalVictories
        if stats.bossLastHit { bossKills += 1 }
        return true
    }
}
