import Darwin
import Foundation
import Security

/// Optional local installation trust, written only by the administrator-approved
/// installer. Pins exact code hashes; never disables kernel XPC signature checks.
public struct LocalInstallationTrust: Codable {
  public let applicationHashes: [String]
  public let helperHashes: [String]
  public static let path = "/Library/Application Support/BattuneHelper/identity.json"
  public static func load() -> LocalInstallationTrust? {
    for path in [
      "/Library", "/Library/Application Support", "/Library/Application Support/BattuneHelper",
      Self.path,
    ] {
      var info = stat()
      guard lstat(path, &info) == 0, info.st_uid == 0, info.st_mode & 0o022 == 0,
        info.st_mode & S_IFMT != S_IFLNK
      else { return nil }
    }
    let fd = open(path, O_RDONLY | O_NOFOLLOW)
    guard fd >= 0 else { return nil }
    defer { close(fd) }
    var info = stat()
    guard fstat(fd, &info) == 0, info.st_uid == 0, info.st_mode & 0o022 == 0,
      info.st_size > 0, info.st_size < 4096
    else { return nil }
    var bytes = [UInt8](repeating: 0, count: Int(info.st_size))
    guard read(fd, &bytes, bytes.count) == bytes.count,
      let trust = try? JSONDecoder().decode(Self.self, from: Data(bytes)), trust.valid
    else { return nil }
    return trust
  }
  public var valid: Bool {
    [applicationHashes, helperHashes].allSatisfy { hashes in
      !hashes.isEmpty && hashes.count <= 2
        && hashes.allSatisfy { hash in
          hash.count == 40 && hash.allSatisfy { "0123456789abcdef".contains($0) }
        }
    }
  }
  public static func ownHash() -> String? {
    var code: SecCode?
    var staticCode: SecStaticCode?
    var dictionary: CFDictionary?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
      SecCodeCheckValidity(code, [], nil) == errSecSuccess,
      SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
      SecCodeCopySigningInformation(
        staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &dictionary) == errSecSuccess,
      let hash = (dictionary as? [String: Any])?[kSecCodeInfoUnique as String] as? Data
    else { return nil }
    return hash.map { String(format: "%02x", $0) }.joined()
  }
  public static func requirement(identifier: String, hashes: [String]) -> String {
    "identifier \"\(identifier)\" and ("
      + hashes.map { "cdhash H\"\($0)\"" }.joined(separator: " or ") + ")"
  }
  public static func peerRequirement(forHelper: Bool) -> String? {
    if let team = SigningIdentity.teamIdentifier() {
      return SigningIdentity.requirement(
        identifier: forHelper ? HelperIdentity.machService : HelperIdentity.appIdentifier,
        team: team)
    }
    guard let trust = load(), let own = ownHash(),
      (forHelper ? trust.applicationHashes : trust.helperHashes).contains(own)
    else { return nil }
    return requirement(
      identifier: forHelper ? HelperIdentity.machService : HelperIdentity.appIdentifier,
      hashes: forHelper ? trust.helperHashes : trust.applicationHashes)
  }
}
