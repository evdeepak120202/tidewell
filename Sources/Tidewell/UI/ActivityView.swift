import AppKit
import SwiftUI
import TidewellCore

/// The run journal.
///
/// Every pass is listed with what moved and where from, and — because nothing is
/// ever deleted — every one of them can be put back.
struct ActivityView: View {

    @Environment(AppEnvironment.self) private var env
    @State private var expanded: Set<UUID> = []

    var body: some View {
        Group {
            if env.settings.runs.isEmpty {
                ContentUnavailableView(
                    "Nothing filed yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Runs appear here, and every one can be undone.")
                )
            } else {
                List {
                    ForEach(env.settings.runs) { run in
                        RunRow(run: run, isExpanded: expanded.contains(run.id)) {
                            if expanded.contains(run.id) { expanded.remove(run.id) }
                            else { expanded.insert(run.id) }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Activity")
    }
}

private struct RunRow: View {

    @Environment(AppEnvironment.self) private var env
    let run: OrganizeRun
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(tint)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(run.folder.lastPathComponent)
                            .font(.system(size: 12, weight: .medium))
                        Text(run.trigger.rawValue)
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                        if run.isUndone {
                            Text("undone")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("\(run.summary) · \(run.startedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !run.moved.isEmpty {
                    Button(isExpanded ? "Hide" : "Details", action: toggle)
                        .controlSize(.small)
                        .buttonStyle(.borderless)

                    if !run.isUndone, run.trigger != .undo {
                        Button("Undo") { Task { await env.undo(run) } }
                            .controlSize(.small)
                    }
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(run.moved) { move in
                        HStack(spacing: 6) {
                            Image(systemName: move.category.symbolName)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .frame(width: 12)
                            Text(move.fileName)
                                .font(.system(size: 10))
                                .lineLimit(1)
                            Spacer()
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([move.destination])
                            } label: {
                                Image(systemName: "arrow.up.forward.app").font(.system(size: 9))
                            }
                            .buttonStyle(.borderless)
                            .help(move.destination.path)
                            .accessibilityLabel("Reveal \(move.fileName) in Finder")
                        }
                    }
                    ForEach(run.failures, id: \.self) { failure in
                        Text(failure)
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                    }
                }
                .padding(.leading, 24)
            }
        }
        .padding(.vertical, 3)
    }

    private var icon: String {
        if !run.failures.isEmpty { return "exclamationmark.triangle" }
        if run.trigger == .undo { return "arrow.uturn.backward" }
        return run.moved.isEmpty ? "minus.circle" : "checkmark.circle"
    }

    private var tint: Color {
        if !run.failures.isEmpty { return .orange }
        return run.moved.isEmpty ? .secondary : .accentColor
    }
}
