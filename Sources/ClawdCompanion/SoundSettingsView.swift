import SwiftUI

struct SoundSettingsView: View {
    @ObservedObject var state: CompanionState

    private var volumeText: String {
        state.soundVolume.formatted(.percent.precision(.fractionLength(0)).locale(L10n.locale))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SmallLabel(text: L("Töne"))
            HStack {
                Text(L("Soundeffekte")).font(.system(size: 13, weight: .semibold))
                Spacer()
                Toggle(L("Soundeffekte"), isOn: $state.soundEnabled)
                    .labelsHidden().toggleStyle(.switch)
            }
            .padding(.vertical, 4)
            Divider()
            HStack(spacing: 10) {
                Text(L("Lautstärke")).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 4)
                Slider(value: $state.soundVolume, in: 0...1, step: 0.01)
                    .frame(maxWidth: 145)
                    .accessibilityLabel(L("Lautstärke der Soundeffekte"))
                    .accessibilityValue(volumeText)
                Text(volumeText).font(.system(size: 12)).monospacedDigit()
                    .frame(width: 46, alignment: .trailing)
                    .accessibilityHidden(true)
            }.padding(.vertical, 4)
            Divider()
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 7) {
                    let movement: [PetSound] = [.steps, .climb, .peek, .jump, .land, .rappel]
                    let arcade: [PetSound] = [.arcadeMusic, .arcadeFire, .arcadeHit, .arcadePickup, .arcadeBoss, .arcadeDefeat, .arcadeVictory, .arcadeRevive]
                    soundGroup(L("Bewegung"), sounds: movement)
                    Divider().padding(.vertical, 2)
                    soundGroup(L("Aktivität, Spiel und Meldungen"), sounds: PetSound.allCases.filter { !movement.contains($0) && !arcade.contains($0) })
                    Divider().padding(.vertical, 2)
                    soundGroup(L("Virenarena"), sounds: arcade)
                }.padding(.top, 8)
            } label: {
                HStack {
                    Text(L("Einzelne Töne")).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    let count = PetSound.allCases.filter { state.isSoundEnabled($0) }.count
                    Text(L("{0} von {1} aktiv", count.formatted(.number.locale(L10n.locale)), PetSound.allCases.count.formatted(.number.locale(L10n.locale))))
                        .font(.system(size: 11)).monospacedDigit().foregroundStyle(Ink.dim)
                }
            }.padding(.vertical, 3)
        }.padding(14).background(RoundedRectangle(cornerRadius: 12).fill(Ink.card))
    }

    private func soundGroup(_ title: String, sounds: [PetSound]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SmallLabel(text: title).padding(.bottom, 3)
            ForEach(sounds) { sound in
                let name = L(sound.title)
                HStack(spacing: 12) {
                    Text(name).font(.system(size: 12))
                    Spacer(minLength: 4)
                    Button {
                        state.previewSound(sound)
                    } label: {
                        Image(systemName: "speaker.wave.2")
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 26, height: 23)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .disabled(!state.soundEnabled || state.soundVolume <= 0)
                    .help(L("Hörprobe für „{0}“", name))
                    .accessibilityLabel(L("{0} anhören", name))
                    Toggle(name, isOn: Binding(
                        get: { state.isSoundEnabled(sound) },
                        set: { state.setSound(sound, enabled: $0) }
                    )).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
        }
    }
}
