import SwiftUI

/// Moon button with a custom dropdown for the sleep timer, styled after the
/// NetworkPicker popover. The 1s countdown timer exists only while a sleep
/// timer is active — idle, this view never re-renders.
struct SleepTimerView: View {
    @Environment(AppState.self) private var appState
    @State private var isOpen = false
    @State private var customMinutes = Prefs.string(.sleepTimerCustomMinutes) ?? "45"

    private let presets = [
        SleepTimerPreset(minutes: 15, label: "15 minutes"),
        SleepTimerPreset(minutes: 30, label: "30 minutes"),
        SleepTimerPreset(minutes: 45, label: "45 minutes"),
        SleepTimerPreset(minutes: 60, label: "1 hour"),
        SleepTimerPreset(minutes: 120, label: "2 hours"),
        SleepTimerPreset(minutes: 240, label: "4 hours"),
        SleepTimerPreset(minutes: 480, label: "8 hours"),
        SleepTimerPreset(minutes: 720, label: "12 hours"),
    ]

    private var isActive: Bool { appState.sleepTimerEndDate != nil }

    var body: some View {
        HStack(spacing: 4) {
            if let endDate = appState.sleepTimerEndDate {
                CountdownText(endDate: endDate) { remaining in
                    Text(NowPlaying.formatTime(remaining))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Button {
                isOpen.toggle()
            } label: {
                Image(systemName: isActive ? "moon.zzz.fill" : "moon.zzz")
                    .font(.system(size: 12))
                    .foregroundStyle(isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .cursor(.pointingHand)
            .help("Sleep timer")
            .popover(isPresented: $isOpen, arrowEdge: .bottom) {
                popoverContent
            }
        }
    }

    private var popoverContent: some View {
        DropdownContainer(width: 190) {
            if let endDate = appState.sleepTimerEndDate {
                HStack {
                    CountdownText(endDate: endDate) { remaining in
                        Text("Stops in \(NowPlaying.formatTime(remaining))")
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)

                TimerRow(label: "Cancel timer", tint: .red) {
                    appState.cancelSleepTimer()
                    isOpen = false
                }

                Divider()
                    .padding(.vertical, 4)
            }

            ForEach(presets) { preset in
                TimerRow(label: preset.label) {
                    appState.startSleepTimer(minutes: preset.minutes)
                    isOpen = false
                }
            }

            Divider()
                .padding(.vertical, 4)

            HStack(spacing: 6) {
                TextField("min", text: customMinutesBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .frame(width: 44)
                    .onSubmit(startCustomTimer)
                Text("minutes")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer()
                Button("Start", action: startCustomTimer)
                    .controlSize(.small)
                    .disabled(SleepTimerInput.minutes(from: customMinutes) == nil)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
    }

    private func startCustomTimer() {
        guard let minutes = SleepTimerInput.effectiveMinutes(from: customMinutes) else { return }
        customMinutes = SleepTimerInput.storedValue(for: minutes)
        Prefs.set(customMinutes, for: .sleepTimerCustomMinutes)
        appState.startSleepTimer(minutes: minutes)
        isOpen = false
    }

    private var customMinutesBinding: Binding<String> {
        Binding(
            get: { customMinutes },
            set: { customMinutes = SleepTimerInput.sanitized($0) }
        )
    }
}

private struct SleepTimerPreset: Identifiable {
    let minutes: Double
    let label: String

    var id: Double { minutes }
}

/// Owns the once-per-second tick so only the label re-renders, and only
/// while a countdown is showing.
private struct CountdownText<Content: View>: View {
    let endDate: Date
    @ViewBuilder let content: (Int) -> Content
    @State private var now = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        content(max(Int(ceil(endDate.timeIntervalSince(now))), 0))
            .onReceive(timer) { now = $0 }
    }
}

private struct TimerRow: View {
    let label: String
    var tint: Color = .primary
    let action: () -> Void

    var body: some View {
        DropdownRow(action: action) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(tint)
            Spacer()
        }
    }
}
