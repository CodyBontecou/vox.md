import Foundation

public enum CaptureWebLink {
    /// Foundation also creates URLs for incomplete strings such as `https://`
    /// and `https:notes`. A captured web link needs an authority with a host.
    public static func isValid(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host(percentEncoded: false), !host.isEmpty else {
            return false
        }
        return host.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil
    }
}
