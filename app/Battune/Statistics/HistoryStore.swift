import Foundation

public final class HistoryStore {
  public private(set) var samples: [BatterySnapshot] = []
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
  }
  public func append(_ snapshot: BatterySnapshot) {
    guard snapshot.percentage != nil else { return }
    if let lastSample, snapshot.timestamp.timeIntervalSince(lastSample) < 300 { return }
    lastSample = snapshot.timestamp
    if let last = samples.last, last.percentage == snapshot.percentage,
      last.charging == snapshot.charging,
      last.pluggedIn == snapshot.pluggedIn, last.temperature == snapshot.temperature,
      last.maximumCapacity == snapshot.maximumCapacity
    {
      return
    }
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
  public func clear() throws {
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
    samples = []
    dirtyCount = 0
    lastSample = nil
  }
}
