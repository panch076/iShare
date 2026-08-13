import Foundation

enum RelayConfig {
    /// Point this at your relay server (see /server in this project).
    /// Use the Cloudflare Tunnel / public HTTPS URL once you have one —
    /// http://localhost won't be reachable from a physical device.
    static let baseURL = URL(string: "https://share.yourdomain.com")!

    /// Create this App Group in BOTH targets' Signing & Capabilities tab
    /// (Main app target and Share Extension target) so they can share
    /// the "recent shares" list. Must match exactly in both places.
    static let appGroupID = "group.com.yourname.ishare"
}
