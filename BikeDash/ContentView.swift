import SwiftUI
import MapKit

struct ContentView: View {
    @EnvironmentObject var link: BoardLink
    @EnvironmentObject var nav: Navigator
    @State private var query = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                // Board status
                HStack(spacing: 8) {
                    Circle()
                        .fill(link.connected ? Color.green : Color.gray)
                        .frame(width: 12, height: 12)
                    Text(link.status).font(.subheadline)
                    Spacer()
                    if link.connected && !nav.navigating {
                        Button("Test") { nav.sendTest() }
                            .buttonStyle(.bordered)
                    }
                }

                if nav.navigating {
                    // Current navigation
                    VStack(alignment: .leading, spacing: 8) {
                        Text(nav.destination?.name ?? "Destination")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text(nav.distanceText)
                            .font(.system(size: 48, weight: .bold))
                        Text(nav.instruction)
                            .font(.title3)
                        if !nav.etaText.isEmpty {
                            Text("ETA \(nav.etaText)  ·  \(nav.remainingText)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    Button(role: .destructive) {
                        nav.stop()
                    } label: {
                        Text("Stop navigation").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)

                    Text("You can lock the phone. Directions keep going to the board.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    // Search
                    HStack {
                        TextField("Where to?", text: $query)
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.search)
                            .onSubmit { nav.search(query) }
                        Button("Search") { nav.search(query) }
                            .buttonStyle(.borderedProminent)
                    }

                    List(nav.results, id: \.self) { item in
                        Button {
                            nav.start(to: item)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? "Place").foregroundStyle(.primary)
                                Text(item.placemark.title ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listStyle(.plain)
                }

                if !nav.message.isEmpty {
                    Text(nav.message).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Bike Dash")
        }
    }
}
