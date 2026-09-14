// The nearby developer harness: a screen for driving the protocol on two real
// devices, and nothing a player will ever see.
//
// Debug builds only, and reachable only by `-mxq-open-nearby`. It is not the
// nearby feature's user interface — that is Stage 2, designed against the
// interaction contract. This is the instrument the transport and the engine are
// exercised through before there is a surface: English and verbatim throughout,
// so none of it enters the copy catalog, in the shape the connectivity spike
// left behind because that shape is a checklist of what a two-device run has to
// show.
//
// Every intent the protocol gives a player is a control here: propose, consent,
// move — by hand or one ply at a time along a scripted line — offer and accept
// a draw, request and accept an undo, resign, and claim the drawn repetition
// where the rules say it stands.

#if DEBUG && os(iOS)

import DeviceDiscoveryUI
import SwiftUI
import WiFiAware

struct NearbyHarnessScreen: View {
    @State private var log: NearbyLog
    @State private var driver: NearbyDriver
    @State private var transport: NearbyTransport

    /// What the launch asked for. Read once: a run is driven by the arguments
    /// it started with.
    private let launch = NearbyLaunch.current

    /// The proposal being composed, and the two text fields the intents take.
    ///
    /// The game is the app's own vocabulary rather than a list of its own: a
    /// harness with a second table of games is a harness that can be behind the
    /// app about which games there are, which is the one thing it must not be.
    @State private var game = GameKind.miniXiangqi
    @State private var proposerMoves = Mover.first
    @State private var moveText = ""
    @State private var keepText = ""

    /// The library, so a driven run exercises the same store the app's own
    /// nearby games live in. It is the harness's core, which is the app's — a
    /// run that wrote nowhere would prove nothing about Stage 3 — and a driven
    /// run gives itself a library of its own with `-mxq-store-name`.
    private let library: Core

    init(core: Core) {
        let log = NearbyLog()
        let driver = NearbyDriver(rules: core.boardGameRules, log: log,
                                  record: NearbyRecord(library: core,
                                                       rules: core.boardGameRules,
                                                       log: log, mode: .nearby))
        _log = State(initialValue: log)
        _driver = State(initialValue: driver)
        _transport = State(initialValue: NearbyTransport(driver: driver, log: log))
        library = core
    }

    var body: some View {
        NavigationStack {
            harness
                .navigationTitle(Text(verbatim: "Nearby (harness)"))
        }
        .task {
            transport.watchPairedDevices()
            reportTheLibrary()
            if launch.resumesStoredGame { _ = driver.resumeStoredGame() }
            if launch.autostarts { transport.start() }
            follow()
        }
        // A driven run has no hands: the plan the launch arguments describe is
        // re-read whenever anything it reacts to has moved. A step that the
        // engine refuses changes nothing, so a refusal cannot loop.
        .onChange(of: driver.sessions) { follow() }
        .onChange(of: readyConnections.map(\.id)) { follow() }
    }

    // MARK: - The plan a driven run arrives with

    /// What the library holds, said into the run's log at every launch.
    ///
    /// It is the same answer the Play home's **当前对局** card is drawn from —
    /// `mxq_store_active_summary`, with no session materialised — so a driven
    /// run that cannot see a screen can still read the fact the card states.
    private func reportTheLibrary() {
        do {
            guard let summary = try library.activeGameSummary() else {
                log.note("The library holds no active game.")
                return
            }
            log.note("The library holds a \(summary.mode) \(summary.game) game: "
                     + "\(summary.moveCount) plies"
                     + (summary.localSide.map { ", \($0) here" } ?? "") + ".")
        } catch {
            log.note("The library would not say what it holds: "
                     + "\(CoreError(wrapping: error)).")
        }
    }

    /// Performs whatever the launch arguments ask for and the engine allows,
    /// one step at a time. Bounded, because a plan that never settles is a
    /// fault to see in the log rather than a spin.
    private func follow() {
        for _ in 0..<16 {
            if !step() { return }
        }
    }

    /// One step, or none. Nothing here decides what the protocol permits — the
    /// engine does, and refuses the rest; the reads of a session are the plan
    /// asking whether its own turn has come, so that a driven run's log carries
    /// what happened rather than a wall of refusals.
    private func step() -> Bool {
        if launch.consents {
            for session in driver.sessions
            where session.state == .proposed && session.proposer == .peer {
                if (try? driver.answer(session.id, accepting: true)) != nil { return true }
            }
        }
        if launch.agrees {
            for session in driver.sessions where session.isInPlay && session.item?.opener == .peer {
                switch session.item?.kind {
                case .drawOffer:
                    if (try? driver.acceptDraw(in: session.id)) != nil { return true }
                case .undoRequest:
                    if (try? driver.acceptUndo(in: session.id)) != nil { return true }
                case nil:
                    continue
                }
            }
        }
        if launch.autoplays {
            for session in driver.sessions where session.isInPlay && session.isLocalTurn {
                guard let move = launch.move(at: session.count) else { continue }
                if (try? driver.play(move, in: session.id)) != nil { return true }
            }
        }
        if let intent = launch.then {
            for session in driver.sessions
            where session.isInPlay && launch.move(at: session.count) == nil {
                switch intent {
                case .offerDraw:
                    guard !session.isLocalTurn, session.item == nil else { continue }
                    if (try? driver.offerDraw(in: session.id)) != nil { return true }
                case .resign:
                    if (try? driver.resign(in: session.id)) != nil { return true }
                case .claim:
                    guard driver.claimStands(in: session) else { continue }
                    if (try? driver.claim(in: session.id)) != nil { return true }
                }
            }
        }
        if let proposal = launch.proposal {
            for connection in readyConnections {
                guard let peer = connection.peer else { continue }
                // Only where nothing this device holds with that peer stands in
                // the way: a live session, or a finished one this device has not
                // settled yet. Both are the engine's rule and it refuses either
                // way; asking first is what keeps a driven run's log from
                // filling with the same refusal while a settlement completes.
                guard driver.sessions(with: peer)
                    .allSatisfy({ $0.state == .ended && $0.settled })
                else { continue }
                if (try? driver.propose(to: peer, on: connection.id,
                                        rulesID: proposal.rulesID,
                                        proposerMoves: proposal.proposerMoves)) != nil {
                    return true
                }
            }
        }
        return false
    }

    private var harness: some View {
        Form {
            pairing
            pairedDevices
            controls
            connections
            proposing
            sessions
            logLines
        }
        .formStyle(.grouped)
    }

    // MARK: - Pairing

    /// The one place the two devices differ, once per pair of devices: someone
    /// shows, someone picks. Both buttons exist on both devices so either can
    /// take either role. Pinned to the one declared service, because pairing
    /// grants access to the device rather than to a service.
    ///
    /// Built only where the radio is, as the app's own sheet builds them: the
    /// system's pairing views hand off to a peer-to-peer Wi-Fi service, and
    /// where there is none they terminate the app that asked. Everything else
    /// on this screen runs there — the other path needs no radio.
    @ViewBuilder
    private var pairing: some View {
        Section {
            if NearbyTransport.hasRadio,
               let publishable = WAPublishableService.boardGame,
               let subscribable = WASubscribableService.boardGame {
                DevicePairingView(.wifiAware(.connecting(to: publishable,
                                                         from: .userSpecifiedDevices))) {
                    Label { Text(verbatim: "Make this device discoverable") } icon: {
                        Image(systemName: "dot.radiowaves.left.and.right")
                    }
                } fallback: {
                    Label { Text(verbatim: "Discoverable mode unavailable") } icon: {
                        Image(systemName: "xmark.circle")
                    }
                }

                DevicePicker(.wifiAware(.connecting(to: .userSpecifiedDevices,
                                                    from: subscribable))) { endpoint in
                    log.note("Paired through the picker: \(String(describing: endpoint)).")
                } label: {
                    Label { Text(verbatim: "Find a nearby device") } icon: {
                        Image(systemName: "magnifyingglass")
                    }
                } fallback: {
                    Label { Text(verbatim: "Device picker unavailable") } icon: {
                        Image(systemName: "xmark.circle")
                    }
                }
            } else if !NearbyTransport.hasRadio {
                Text(verbatim: "No radio on this device — nothing to pair with. "
                     + "The local network is the whole reach here.")
                    .foregroundStyle(.secondary)
            } else {
                Text(verbatim: "\(NearbyService.name) is missing from WiFiAwareServices.")
                    .foregroundStyle(.red)
            }
        } header: {
            Text(verbatim: "Pair (once per pair of devices)")
        }
    }

    private var pairedDevices: some View {
        Section {
            if transport.pairedDevices.isEmpty {
                Text(verbatim: "No paired devices yet.").foregroundStyle(.secondary)
            } else {
                ForEach(transport.pairedDevices, id: \.id) { device in
                    LabeledContent {
                        Text(verbatim: "wifi-aware-device-\(device.id)")
                            .font(.caption.monospaced())
                    } label: {
                        Text(verbatim: device.displayName ?? "Unnamed device")
                    }
                }
            }
        } header: {
            Text(verbatim: "Paired devices")
        }
    }

    // MARK: - The transport

    private var controls: some View {
        Section {
            if transport.isRunning {
                Button(role: .destructive) {
                    transport.stop()
                } label: {
                    Text(verbatim: "Stop")
                }
            } else {
                Button {
                    transport.start()
                } label: {
                    Text(verbatim: "Start (publish + subscribe)")
                }
            }

            LabeledContent {
                Text(verbatim: transport.listenerState).font(.caption.monospaced())
            } label: {
                Text(verbatim: "Listener")
            }
            LabeledContent {
                Text(verbatim: transport.browserState).font(.caption.monospaced())
            } label: {
                Text(verbatim: "Browser")
            }
            LabeledContent {
                Text(verbatim: transport.networkListenerState).font(.caption.monospaced())
            } label: {
                Text(verbatim: "Network listener")
            }
            LabeledContent {
                Text(verbatim: transport.networkBrowserState).font(.caption.monospaced())
            } label: {
                Text(verbatim: "Network browser")
            }
            LabeledContent {
                // A row's words, not an identifier: what the app's own list
                // would say for each of these, which is a name where one is
                // known and the one neutral label with four characters of the
                // identity where none is. A raw identifier here would be the
                // one thing no reader of any list is ever shown, in the one
                // screen a driven run reads the room off.
                Text(verbatim: transport.advertised.isEmpty
                     ? "—"
                     : transport.advertised.map(\.label.text).joined(separator: ", "))
                    .font(.caption.monospaced())
            } label: {
                Text(verbatim: "On the network")
            }
        } header: {
            Text(verbatim: "Transport (symmetric — start on both devices)")
        }
    }

    private var connections: some View {
        Section {
            if transport.connections.isEmpty {
                Text(verbatim: "No connections.").foregroundStyle(.secondary)
            } else {
                ForEach(transport.connections) { connection in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: connection.direction == .incoming
                                  ? "arrow.down.left.circle" : "arrow.up.right.circle")
                            Text(verbatim: connection.peerName
                                 ?? "Connection \(NearbyDriver.short(connection.id))")
                            Spacer()
                            if connection.isReady {
                                Image(systemName: "circle.fill")
                                    .foregroundStyle(.green).imageScale(.small)
                            }
                        }
                        Text(verbatim: details(of: connection))
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text(verbatim: "Connections")
        } footer: {
            Text(verbatim: "Two rows for one device is the crossed pair the binding allows. "
                 + "Both stay up; a session binds to one of them.")
        }
    }

    private func details(of connection: NearbyConnection) -> String {
        var parts = [connection.direction.rawValue,
                     NearbyDriver.short(connection.id)]
        parts.append(connection.isReady ? "ready" : "not ready")
        if let peer = connection.peer { parts.append(peer.rawValue) }
        if let signal = connection.signalStrength {
            parts.append(String(format: "signal %.2f", signal))
        }
        return parts.joined(separator: "  ·  ")
    }

    // MARK: - Proposing

    private var proposing: some View {
        Section {
            Picker(selection: $game) {
                ForEach(GameKind.allCases, id: \.self) { game in
                    Text(verbatim: game.localizedName).tag(game)
                }
            } label: {
                Text(verbatim: "Game")
            }

            // The mover is the protocol's and the same in every game; which
            // side it is, is the chosen game's own naming, asked of it.
            Picker(selection: $proposerMoves) {
                Text(verbatim: "First (\(game.sideName(.red)))").tag(Mover.first)
                Text(verbatim: "Second (\(game.sideName(.black)))").tag(Mover.second)
            } label: {
                Text(verbatim: "I move")
            }

            ForEach(readyConnections) { connection in
                Button {
                    guard let peer = connection.peer else { return }
                    try? driver.propose(to: peer, on: connection.id,
                                        rulesID: game.rulesID, proposerMoves: proposerMoves)
                } label: {
                    Text(verbatim: "Propose on \(NearbyDriver.short(connection.id)) "
                         + "→ \(connection.peerName ?? "the peer")")
                }
            }
            if readyConnections.isEmpty {
                Text(verbatim: "No ready connection to propose on.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(verbatim: "Propose a game")
        }
    }

    private var readyConnections: [NearbyConnection] {
        transport.connections.filter { $0.isReady && $0.peer != nil }
    }

    // MARK: - Sessions

    private var sessions: some View {
        Section {
            if driver.sessions.isEmpty {
                Text(verbatim: "No sessions.").foregroundStyle(.secondary)
            } else {
                ForEach(driver.sessions, id: \.id) { session in
                    sessionRows(session)
                }
            }
            ForEach(driver.declines.suffix(5).reversed()) { decline in
                Text(verbatim: "\(NearbyDriver.short(decline.session)) refused: "
                     + "\(decline.reason.rawValue)")
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        } header: {
            Text(verbatim: "Sessions")
        }
    }

    @ViewBuilder
    private func sessionRows(_ session: BoardGameSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "\(NearbyDriver.short(session.id))  ·  \(session.rulesID)"
                 + "  ·  \(session.state)")
            Text(verbatim: details(of: session))
                .font(.caption.monospaced()).foregroundStyle(.secondary)
        }

        if session.state == .proposed, session.proposer == .peer {
            Button { try? driver.answer(session.id, accepting: true) } label: {
                Text(verbatim: "Accept the proposal")
            }
            Button(role: .destructive) {
                try? driver.answer(session.id, accepting: false)
            } label: {
                Text(verbatim: "Decline the proposal")
            }
        }

        if session.state == .active {
            playing(session)
            negotiating(session)
        }
    }

    @ViewBuilder
    private func playing(_ session: BoardGameSession) -> some View {
        HStack {
            TextField(text: $moveText) { Text(verbatim: "Move text") }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospaced())
            Button {
                let text = moveText.trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { return }
                try? driver.play(text, in: session.id)
                moveText = ""
            } label: {
                Text(verbatim: "Play")
            }
            .buttonStyle(.bordered)
        }

        if let scripted = launch.move(at: session.count) {
            Button {
                try? driver.play(scripted, in: session.id)
            } label: {
                Text(verbatim: "Play next of the script: \(scripted)")
            }
            .disabled(!session.isLocalTurn)
        }

        if driver.claimStands(in: session) {
            Button {
                try? driver.claim(in: session.id)
            } label: {
                Text(verbatim: "Claim the draw")
            }
        }
    }

    @ViewBuilder
    private func negotiating(_ session: BoardGameSession) -> some View {
        Button { try? driver.offerDraw(in: session.id) } label: {
            Text(verbatim: "Offer a draw")
        }
        Button { try? driver.acceptDraw(in: session.id) } label: {
            Text(verbatim: "Accept the draw")
        }
        HStack {
            TextField(text: $keepText) { Text(verbatim: "Keep") }
                .keyboardType(.numberPad)
                .font(.body.monospaced())
            Button {
                guard let keep = Int(keepText.trimmingCharacters(in: .whitespaces)) else { return }
                try? driver.requestUndo(keeping: keep, in: session.id)
            } label: {
                Text(verbatim: "Request undo")
            }
            .buttonStyle(.bordered)
        }
        Button { try? driver.acceptUndo(in: session.id) } label: {
            Text(verbatim: "Accept the undo")
        }
        Button(role: .destructive) { try? driver.resign(in: session.id) } label: {
            Text(verbatim: "Resign")
        }
    }

    private func details(of session: BoardGameSession) -> String {
        var parts = ["count=\(session.count)", "undos=\(session.undos)",
                     "turn=\(session.isLocalTurn ? "mine" : "theirs")",
                     "me=\(session.localMover.rawValue)",
                     "proposer=\(session.proposer)",
                     "settled=\(session.settled)"]
        parts.append("on=\(session.connection.map(NearbyDriver.short) ?? "—")")
        if let item = session.item {
            parts.append("item=\(item.opener)/\(item.kind)@\(item.at)")
        }
        if let end = session.end {
            parts.append("end=\(end.result)/\(end.ending)")
        }
        if session.plies.isEmpty {
            parts.append("plies=—")
        } else {
            parts.append("plies=\(session.plies.joined(separator: " "))")
        }
        return parts.joined(separator: "  ·  ")
    }

    // MARK: - The log

    private var logLines: some View {
        Section {
            ForEach(log.lines.suffix(80).reversed()) { line in
                Text(verbatim: "\(line.at.formatted(date: .omitted, time: .standard))  "
                     + "\(line.text)")
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        } header: {
            Text(verbatim: "Log (newest first)")
        }
    }
}

#endif
