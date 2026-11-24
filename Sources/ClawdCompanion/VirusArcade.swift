import CoreGraphics
import Foundation

/// Local AppKit coordinates, with the hero facing right. Time advances only while the caller ticks.
struct VirusArcade {
    static let size = CGSize(width: 300, height: 160)
    static let step = 1.0 / 60.0
    static let maximumEnemies = 3

    enum Phase { case wave, boss, victory, dead }
    enum Event { case bossAppeared, won, died }
    enum Cue { case fire, enemyHit, enemyDefeated, heroHurt, powerup, boss, victory, death }
    enum Kind: CaseIterable { case bug, worm, spore, boss }
    enum PickupKind: CaseIterable { case restore, shield, rapidFire }

    struct RunStats: Equatable {
        var assists = 0
        var manualDamage = 0
        var manualPickups = 0
        var kills = 0
        var personalKills = 0
        var lastHits = 0
        var killBonus = 0
        var bossDefeated = false
        var personalBoss = false
        var bossLastHit = false
        var deaths = 0
        var victories = 0
        var engaged: Bool { manualDamage > 0 || manualPickups > 0 }
        var personalDeaths: Int { engaged ? deaths : 0 }
        var personalVictories: Int { engaged ? victories : 0 }
        var score: Int { manualDamage + 5 * manualPickups + killBonus }
    }

    struct Enemy: Equatable {
        let id: Int
        let kind: Kind
        var position: CGPoint
        let radius: CGFloat
        var hp: Int
        let maxHP: Int
        var hurt: Double
    }

    struct Shot: Equatable {
        let id: Int
        let hostile: Bool
        var position: CGPoint
    }

    struct Pickup: Equatable {
        let id: Int
        let kind: PickupKind
        var position: CGPoint
        let radius: CGFloat
    }

    struct Frame: Equatable {
        let phase: Phase
        let wave: Int
        let playerHP: Int
        let hero: CGPoint
        let enemies: [Enemy]
        let shots: [Shot]
        let time: Double
        let heroHurt: Double
        let heroFiring: Bool
        let event: Event?
        let cues: [Cue]
        let pickups: [Pickup]
        let shield: Double
        let rapidFire: Double
        /// Counts within the current wave, including regular enemies yet to spawn. Boss wave total is one.
        let enemyTotal: Int
        let defeated: Int
        var stats = RunStats()
    }

    private struct Opponent {
        var body: Enemy
        let home: CGPoint
        let swing: Double
        let angle: Double
        var nextFire: Double
        var manualDamage = 0
    }

    private struct Bolt {
        var shot: Shot
        let velocity: CGPoint
        let damage: Int
    }

    private struct Generator: RandomNumberGenerator {
        var state: UInt64

        // SplitMix64 also accepts a zero seed.
        mutating func next() -> UInt64 {
            state &+= 0x9e3779b97f4a7c15
            var n = state
            n = (n ^ (n >> 30)) &* 0xbf58476d1ce4e5b9
            n = (n ^ (n >> 27)) &* 0x94d049bb133111eb
            return n ^ (n >> 31)
        }
    }

    private var random: Generator
    private var phase: Phase = .wave
    private var wave = 1
    private var total = 0
    private var spawned = 0
    private var defeated = 0
    private var nextSpawn = 0.0
    private var nextWave = Double.infinity
    private var opponents: [Opponent] = []
    private var bolts: [Bolt] = []
    private var pickups: [Pickup] = []
    private var pickupOrder: [PickupKind] = []
    private var serial = 0
    private var playerHP = 100
    private var hero = CGPoint(x: 43, y: 77)
    private var dodgeAngle = 0.0
    private var hurtUntil = 0.0
    private var firingUntil = 0.0
    private var shieldUntil = 0.0
    private var rapidUntil = 0.0
    private var nextHeroFire = 0.5
    private var nextAssist = 0.0
    private var time = 0.0
    private var previousTick: TimeInterval?
    private var remainder = 0.0
    private var event: Event?
    private var cues: [Cue] = []
    private(set) var stats = RunStats()

    init(seed: UInt64 = .random(in: UInt64.min...UInt64.max)) {
        random = Generator(state: seed)
        dodgeAngle = Double.random(in: 0..<(2 * .pi), using: &random)
        startWave()
    }

    var frame: Frame { snapshot(event: nil, cues: []) }

    mutating func pause() {
        previousTick = nil
        remainder = 0
    }

    mutating func resume(now: TimeInterval) {
        previousTick = now.isFinite ? now : nil
        remainder = 0
    }

    mutating func tick(now: TimeInterval) -> Frame {
        if !now.isFinite {
            pause()
        } else if previousTick.map({ now >= $0 }) ?? true {
            if let previous = previousTick {
                let delta = now - previous
                // A delayed Cocoa timer after sleep or a blocked run loop must not simulate unseen combat.
                if (0...0.35).contains(delta), playing {
                    remainder += delta
                    while remainder + 1e-10 >= Self.step && playing {
                        remainder = max(0, remainder - Self.step)
                        advance(Self.step)
                    }
                } else {
                    remainder = 0
                }
            }
            previousTick = now
        }
        let output = snapshot(event: event, cues: cues)
        event = nil
        cues.removeAll(keepingCapacity: true)
        return output
    }

    /// Called by the overlay after a hit test against the sprite's visible pixels.
    mutating func hit(enemyID: Int) {
        guard playing, time >= nextAssist, let i = opponents.firstIndex(where: { $0.body.id == enemyID }) else { return }
        nextAssist = time + 0.16
        damageEnemy(at: i, by: 9, manual: true)
    }

    mutating func collect(pickupID: Int) {
        collect(pickupID: pickupID, manual: true)
    }

    private mutating func collect(pickupID: Int, manual: Bool) {
        guard playing, let i = pickups.firstIndex(where: { $0.id == pickupID }) else { return }
        let item = pickups.remove(at: i)
        let useful: Bool
        switch item.kind {
        case .restore:
            useful = playerHP < 100
            playerHP = min(100, playerHP + 25)
        case .shield:
            useful = shieldUntil < time + 4
            shieldUntil = time + 4
        case .rapidFire:
            useful = rapidUntil < time + 5
            rapidUntil = time + 5
            nextHeroFire = min(nextHeroFire, time + 0.15)
        }
        if manual && useful { stats.manualPickups += 1 }
        cue(.powerup)
    }

    private var playing: Bool { phase == .wave || phase == .boss }

    private func snapshot(event: Event?, cues: [Cue]) -> Frame {
        Frame(phase: phase, wave: wave, playerHP: playerHP, hero: hero, enemies: opponents.map(\.body),
              shots: bolts.map(\.shot), time: time, heroHurt: max(0, (hurtUntil - time) / 0.32),
              heroFiring: firingUntil > time, event: event, cues: cues, pickups: pickups,
              shield: max(0, shieldUntil - time), rapidFire: max(0, rapidUntil - time),
              enemyTotal: total, defeated: defeated, stats: stats)
    }

    private mutating func cue(_ cue: Cue) {
        if !cues.contains(cue) { cues.append(cue) }
    }

    private mutating func nextID() -> Int {
        serial += 1
        return serial
    }

    private mutating func startWave() {
        spawned = 0
        defeated = 0
        nextWave = .infinity
        if wave == 3 {
            phase = .boss
            total = 1
            event = .bossAppeared
            cue(.boss)
        } else {
            total = Int.random(in: (wave + 1)...(wave + 3), using: &random)
        }
        spawnEnemy()
    }

    private mutating func spawnEnemy() {
        let isBoss = phase == .boss
        let kind: Kind = isBoss ? .boss : [Kind.bug, .worm, .spore].randomElement(using: &random)!
        let radius = Double(Int.random(in: isBoss ? 16...20 : 6...11, using: &random))
        let health = Int.random(in: isBoss ? 95...145 : (8 + wave * 2)...(18 + wave * 4), using: &random)
        let home = CGPoint(x: Double.random(in: 166...258, using: &random),
                           y: Double.random(in: 45...113, using: &random))
        let body = Enemy(id: nextID(), kind: kind, position: CGPoint(x: 279, y: home.y),
                         radius: radius, hp: health, maxHP: health, hurt: 0)
        let opponent = Opponent(body: body, home: home, swing: Double.random(in: 7...17, using: &random),
                                angle: Double.random(in: 0..<(2 * .pi), using: &random),
                                nextFire: time + Double.random(in: 0.55...1.55, using: &random))
        opponents.append(opponent)
        spawned += 1
        nextSpawn = time + Double.random(in: 1.0...1.65, using: &random)
    }

    private mutating func advance(_ dt: Double) {
        time += dt
        if time >= nextWave {
            wave += 1
            startWave()
        } else if spawned < total, opponents.count < Self.maximumEnemies, time >= nextSpawn {
            spawnEnemy()
        }
        moveHeroAndPickups(dt)
        moveAndFireEnemies(dt)
        if time >= nextHeroFire, let target = opponents.min(by: { $0.body.position.x < $1.body.position.x }) {
            fire(from: CGPoint(x: hero.x + 8, y: hero.y), toward: target.body.position,
                 speed: 259, damage: Int.random(in: 6...10, using: &random), hostile: false)
            nextHeroFire = time + (rapidUntil > time ? 0.27 : 0.78)
            firingUntil = time + 0.18
            cue(.fire)
        }
        moveBolts(dt)
    }

    private mutating func moveHeroAndPickups(_ dt: Double) {
        var desiredY = 77 + 27 * sin(time * 0.86 + dodgeAngle)
        // Drops drift across the arena in the hero's direction. Claw'd can walk into the last few pixels.
        if let nearest = pickups.min(by: { $0.position.x < $1.position.x }), nearest.position.x < hero.x + 50 {
            desiredY = nearest.position.y
        }
        hero.y += max(-33 * dt, min(33 * dt, desiredY - hero.y))
        for i in pickups.indices { pickups[i].position.x -= 62 * dt }
        let overlaps = pickups.filter { Self.touches(hero, $0.position, $0.radius + 8) }
        for item in overlaps { collect(pickupID: item.id, manual: false) }
        pickups.removeAll { $0.position.x < 0 }
    }

    private mutating func moveAndFireEnemies(_ dt: Double) {
        for i in opponents.indices {
            var opponent = opponents[i]
            opponent.body.hurt = max(0, opponent.body.hurt - dt / 0.22)
            opponent.body.position.x = max(opponent.home.x, opponent.body.position.x - 29 * dt)
            opponent.body.position.y = opponent.home.y + opponent.swing * sin(time * 1.05 + opponent.angle)
            if time >= opponent.nextFire {
                let origin = opponent.body.position
                let boss = opponent.body.kind == .boss
                let offsets: [Double] = boss ? [-19, 0, 19] : [0]
                for offset in offsets {
                    let aim = CGPoint(x: hero.x, y: hero.y + offset + Double.random(in: -4...4, using: &random))
                    fire(from: origin, toward: aim, speed: boss ? 133 : 112,
                         damage: Int.random(in: boss ? 10...17 : 6...11, using: &random), hostile: true)
                }
                opponent.nextFire = time + Double.random(in: boss ? 1.1...1.65 : 1.7...2.8, using: &random)
            }
            opponents[i] = opponent
        }
    }

    private mutating func fire(from origin: CGPoint, toward target: CGPoint, speed: Double, damage: Int, hostile: Bool) {
        let dx = target.x - origin.x
        let dy = target.y - origin.y
        let length = max(0.001, hypot(dx, dy))
        let shot = Shot(id: nextID(), hostile: hostile, position: origin)
        bolts.append(Bolt(shot: shot, velocity: CGPoint(x: dx * speed / length, y: dy * speed / length), damage: damage))
    }

    private mutating func moveBolts(_ dt: Double) {
        // Process in launch order. Advancing by at most 4.4 pt per step is smaller than the minimum hit radius.
        let inFlight = bolts
        bolts.removeAll(keepingCapacity: true)
        for var bolt in inFlight {
            let p = CGPoint(x: bolt.shot.position.x + bolt.velocity.x * dt,
                            y: bolt.shot.position.y + bolt.velocity.y * dt)
            bolt.shot.position = p
            if bolt.shot.hostile {
                if Self.touches(p, hero, 10) {
                    if shieldUntil <= time {
                        playerHP = max(0, playerHP - bolt.damage)
                        hurtUntil = time + 0.32
                        cue(.heroHurt)
                        if playerHP == 0 {
                            finish(.dead)
                            return
                        }
                    }
                    continue
                }
            } else if let index = opponents.firstIndex(where: { Self.touches(p, $0.body.position, $0.body.radius + 2) }) {
                damageEnemy(at: index, by: bolt.damage)
                if !playing { return }
                continue
            }
            if p.x >= -4, p.x <= Self.size.width + 4, p.y >= -4, p.y <= Self.size.height + 4 {
                bolts.append(bolt)
            }
        }
    }

    private static func touches(_ a: CGPoint, _ b: CGPoint, _ radius: CGFloat) -> Bool {
        let x = a.x - b.x
        let y = a.y - b.y
        return x * x + y * y <= radius * radius
    }

    private mutating func damageEnemy(at index: Int, by damage: Int, manual: Bool = false) {
        let effectiveDamage = min(opponents[index].body.hp, damage)
        if manual && effectiveDamage > 0 {
            stats.assists += 1
            stats.manualDamage += effectiveDamage
            opponents[index].manualDamage += effectiveDamage
        }
        opponents[index].body.hp -= effectiveDamage
        opponents[index].body.hurt = 1
        cue(.enemyHit)
        guard opponents[index].body.hp == 0 else { return }
        let opponent = opponents.remove(at: index)
        let fallen = opponent.body
        defeated += 1
        stats.kills += 1
        if manual { stats.lastHits += 1 }
        if opponent.manualDamage > 0 {
            stats.personalKills += 1
            stats.killBonus += (fallen.kind == .boss ? 50 : 10) * opponent.manualDamage / fallen.maxHP
        }
        cue(.enemyDefeated)
        if fallen.kind == .boss {
            stats.bossDefeated = true
            stats.personalBoss = opponent.manualDamage > 0
            stats.bossLastHit = manual
            finish(.victory)
        } else {
            if stats.kills % 2 == 0 || Int.random(in: 0..<5, using: &random) == 0 {
                drop(at: fallen.position)
            }
            if defeated == total { nextWave = time + 1.15 }
        }
    }

    private mutating func drop(at position: CGPoint) {
        guard pickups.count < 3 else { return }
        if pickupOrder.isEmpty { pickupOrder = PickupKind.allCases.shuffled(using: &random) }
        let pickup = Pickup(id: nextID(), kind: pickupOrder.removeLast(), position: position, radius: 7)
        pickups.append(pickup)
    }

    private mutating func finish(_ outcome: Phase) {
        phase = outcome
        pickups.removeAll()
        bolts.removeAll()
        firingUntil = 0
        shieldUntil = 0
        rapidUntil = 0
        if outcome == .dead {
            stats.deaths = 1
            event = .died
            cue(.death)
        } else {
            stats.victories = 1
            event = .won
            cue(.victory)
        }
    }
}
