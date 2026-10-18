//
//  SecurityScopedResourceManager.swift
//  Wallpaper engine
//

import Foundation

/// Coordinates security-scoped file access across all app subsystems (Preview, Desktop, Thumbnails).
/// Maintains reference counts per file to prevent premature kernel sandbox extension revocation
/// when one subsystem finishes using a file while another is still playing it.
@MainActor
final class SecurityScopedResourceManager {
    
    static let shared = SecurityScopedResourceManager()
    
    private struct TrackedResource {
        let url: URL
        var count: Int
    }
    
    private var resources: [UUID: TrackedResource] = [:]
    
    private init() {}
    
    /// Starts accessing the security-scoped URL for the given gallery item.
    /// If the resource is already open, increments its access count and returns the existing URL.
    func startAccess(for item: GalleryItem) -> URL? {
        if var tracked = resources[item.id] {
            tracked.count += 1
            resources[item.id] = tracked
            return tracked.url
        }
        
        var isStale = false
        var resolvedURL: URL?
        
        if let url = try? URL(resolvingBookmarkData: item.bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
            resolvedURL = url
        } else if let url = try? URL(resolvingBookmarkData: item.bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) {
            resolvedURL = url
        }
        
        guard let url = resolvedURL else {
            return nil
        }
        
        let _ = url.startAccessingSecurityScopedResource()
        resources[item.id] = TrackedResource(url: url, count: 1)
        return url
    }
    
    /// Decrements the access count for the given gallery item.
    /// Only calls `stopAccessingSecurityScopedResource` when no subsystem is accessing the file.
    func stopAccess(for item: GalleryItem) {
        stopAccess(forItemID: item.id)
    }
    
    /// Decrements access count by item ID.
    func stopAccess(forItemID id: UUID) {
        guard var tracked = resources[id] else { return }
        tracked.count -= 1
        if tracked.count <= 0 {
            resources.removeValue(forKey: id)
            tracked.url.stopAccessingSecurityScopedResource()
        } else {
            resources[id] = tracked
        }
    }
    
    /// Releases all active security-scoped resources (e.g. at app termination).
    func releaseAll() {
        for (_, tracked) in resources {
            tracked.url.stopAccessingSecurityScopedResource()
        }
        resources.removeAll()
    }
}
