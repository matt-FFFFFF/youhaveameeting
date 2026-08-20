import SwiftUI

/// The alert body. Used at full size inside the takeover and compact inside the
/// corner banner, so the two presentations cannot drift apart.
struct AlertCardView: View {
    let meeting: Meeting
    let compact: Bool
    let onJoin: () -> Void
    let onSnooze: (Int) -> Void
    let onDismiss: () -> Void

    @State private var pulse = false

    private static let snoozeMinutes = [1, 2, 5]

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 24) {
            header
            if let joinURL = meeting.joinURL {
                joinButton(for: joinURL)
            } else {
                noLinkNotice
            }
            controls
        }
        .padding(compact ? 18 : 56)
        .frame(maxWidth: compact ? 380 : 760, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: compact ? 14 : 28, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 14 : 28, style: .continuous)
                .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
        )
        .scaleEffect(pulse ? 1.012 : 1.0)
        .onAppear {
            guard !compact else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 10) {
            Text(startLabel)
                .font(compact ? .caption.weight(.semibold) : .title3.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(meeting.title)
                .font(compact ? .headline : .system(size: 52, weight: .bold))
                .lineLimit(compact ? 2 : 3)
                .fixedSize(horizontal: false, vertical: true)
            if let organiser = meeting.organiser, !compact {
                Text(organiser)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func joinButton(for url: URL) -> some View {
        Button(action: onJoin) {
            Text("Join")
                .font(compact ? .body.weight(.semibold) : .system(size: 30, weight: .bold))
                .frame(maxWidth: compact ? .infinity : 320)
                .padding(.vertical, compact ? 6 : 16)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(compact ? .large : .extraLarge)
        .keyboardShortcut(.defaultAction)
        .help(url.absoluteString)
    }

    private var noLinkNotice: some View {
        Text("No join link on this event.")
            .font(compact ? .caption : .title3)
            .foregroundStyle(.secondary)
    }

    private var controls: some View {
        HStack(spacing: compact ? 8 : 14) {
            ForEach(Self.snoozeMinutes, id: \.self) { minutes in
                Button("\(minutes) min") { onSnooze(minutes) }
            }
            Spacer(minLength: 0)
            Button("Dismiss", action: onDismiss)
        }
        .controlSize(compact ? .small : .large)
        .font(compact ? .caption : .body)
    }

    private var startLabel: String {
        let time = meeting.start.formatted(date: .omitted, time: .shortened)
        return meeting.start <= .now ? "Starting now  ·  \(time)" : "Starts \(time)"
    }
}

/// Secondary displays only get the dim plus the title - the interactive card
/// lives on the screen the user is actually looking at.
struct ShieldBackdropView: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 40, weight: .semibold))
            .foregroundStyle(.white.opacity(0.85))
            .multilineTextAlignment(.center)
            .padding(60)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
