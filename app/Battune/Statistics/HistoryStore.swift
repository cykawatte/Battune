import Combine
import Foundation

public final class HistoryStore: ObservableObject {
  @Published public private(set) var samples: [BatterySnapshot] = []
  private let url: URL
  private var dirtyCount = 0
  private var lastSample: Date?
  public init(url: URL) { self.url = url }
  public static var defaultURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Battune/history.json")
  }
  public func load(now: Date = Date()) throws {
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    let size = (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
    guard size <= 8_000_000 else { throw BattuneError.corruptPersistence }
    samples = try JSONDecoder().decode([BatterySnapshot].self, from: Data(contentsOf: url))
    prune(now: now)
    lastSample = samples.last?.timestamp
  }
  public func append(_ snapshot: BatterySnapshot) {
    guard let percentage = snapshot.percentage, (0...100).contains(percentage),
      lastSample.map({ snapshot.timestamp >= $0 }) ?? true
    else { return }
    let transition =
      samples.last.map { $0.charging != snapshot.charging || $0.pluggedIn != snapshot.pluggedIn }
      ?? false
    if let lastSample, snapshot.timestamp.timeIntervalSince(lastSample) < 300 && !transition {
      return
    }
    lastSample = snapshot.timestamp
    samples.append(snapshot)
    prune(now: snapshot.timestamp)
    dirtyCount += 1
  }
  private func prune(now: Date) {
    samples = Array(
      samples.filter { now.timeIntervalSince($0.timestamp) <= 30 * 86400 && $0.timestamp <= now }
        .suffix(8640))
  }
  public func flush(force: Bool = false) throws {
    guard dirtyCount > 0, force || dirtyCount >= 12 else { return }
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(samples).write(to: url, options: .atomic)
    dirtyCount = 0
  }
  public func exportCSV(since: Date = .distantPast) -> String {
    let iso = ISO8601DateFormatter()
    let header =
      "timestamp,charge_percent,plugged_in,charging,temperature_c,voltage_v,current_a,power_w,capacity_mah,design_mah,cycle_count"
    let rows = samples.filter { $0.timestamp >= since }.map { value in
      var fields: [String] = [iso.string(from: value.timestamp)]
      fields.append(value.percentage.map { String($0) } ?? "")
      fields.append(value.pluggedIn.map { String($0) } ?? "")
      fields.append(value.charging.map { String($0) } ?? "")
      fields.append(value.temperature.map { String($0) } ?? "")
      fields.append(value.voltage.map { String($0) } ?? "")
      fields.append(value.current.map { String($0) } ?? "")
      fields.append(value.power.map { String($0) } ?? "")
      fields.append(value.maximumCapacity.map { String($0) } ?? "")
      fields.append(value.designCapacity.map { String($0) } ?? "")
      fields.append(value.cycleCount.map { String($0) } ?? "")
      return fields.joined(separator: ",")
    }
    return ([header] + rows).joined(separator: "\n") + "\n"
  }
  public func clear() throws {
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
    samples = []
    dirtyCount = 0
    lastSample = nil
  }
}
