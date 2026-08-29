import Foundation

/// Persistent permission to a folder the user chose.
///
/// A sandboxed app loses filesystem access the moment it quits. The user picking
/// `~/Downloads` grants access to *this run only*; to still be watching it after a
/// restart, the app has to store a **security-scoped bookmark** — a token minted at the
/// moment of the grant and resolved on each launch.
///
/// Two things make this easy to get subtly wrong, and both are handled here rather than
/// scattered through the app:
///
/// - **Access must be balanced.** Every successful `startAccessingSecurityScopedResource`
///   needs a matching stop, or the process leaks kernel resources until it is killed.
///   Access is therefore owned by this type, which holds it for the app's lifetime and
///   releases everything on quit.
/// - **Bookmarks go stale.** Moving or renaming the folder, or a macOS upgrade, can
///   invalidate one. A stale bookmark still resolves, and must then be *re-minted* — if
///   it is not, it works until the next launch and then quietly stops, which reads as the
///   app having broken itself.
public actor FolderAccess {

    public enum Failure: Error, Sendable {
        case couldNotCreateBookmark(String)
        case couldNotResolve(String)
        case accessDenied
    }

    /// Folders currently held open, and the token that opened them.
    private var held: [URL: Bool] = [:]

    public init() {}

    /// Mint a bookmark for a folder the user has just chosen.
    ///
    /// Must be called while the app still has the access the picker granted — which is
    /// immediately after the panel returns, not later.
    public nonisolated static func makeBookmark(for url: URL) throws -> Data {
        do {
            return try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw Failure.couldNotCreateBookmark(error.localizedDescription)
        }
    }

    /// Resolve a stored bookmark back into a usable URL.
    ///
    /// - Returns: the URL, and a replacement bookmark when the original had gone stale.
    ///   Callers **must** persist the replacement; ignoring it is the bug that makes
    ///   folder access die one launch later.
    public nonisolated static func resolve(
        _ data: Data
    ) throws -> (url: URL, refreshed: Data?) {
        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            throw Failure.couldNotResolve(error.localizedDescription)
        }

        guard isStale else { return (url, nil) }

        // Re-minting needs access, so open it just long enough to do so.
        let opened = url.startAccessingSecurityScopedResource()
        defer { if opened { url.stopAccessingSecurityScopedResource() } }
        let refreshed = try? makeBookmark(for: url)
        return (url, refreshed)
    }

    /// Begin using a folder, and keep it open until `releaseAll()`.
    @discardableResult
    public func begin(_ url: URL) -> Bool {
        if held[url] == true { return true }
        let opened = url.startAccessingSecurityScopedResource()
        held[url] = opened
        return opened
    }

    /// Release everything. Called on quit, and on any watch-set rebuild.
    public func releaseAll() {
        for (url, opened) in held where opened {
            url.stopAccessingSecurityScopedResource()
        }
        held.removeAll()
    }

    public func release(_ url: URL) {
        if held[url] == true { url.stopAccessingSecurityScopedResource() }
        held[url] = nil
    }

    public var openCount: Int { held.values.count(where: { $0 }) }

    /// Whether the app is running inside the sandbox at all.
    ///
    /// A development build run straight from `swift build` is not sandboxed, and bookmark
    /// calls behave differently there. Knowing which world we are in keeps the diagnostics
    /// honest instead of reporting a permission problem that does not exist.
    public nonisolated static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }
}
