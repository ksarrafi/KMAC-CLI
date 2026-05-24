import Foundation

/// A deterministic, repeatable remediation for a known problem. Unlike the
/// Claude path, a playbook runs the exact same vetted commands every time —
/// no LLM, no cost, no variance. `inspect` is read-only (shows what/how much);
/// `apply` performs the change. The LLM is only a fallback when no playbook fits.
public struct Playbook: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let summary: String
    /// Read-only command: reports current state / what would be reclaimed.
    public let inspect: String
    /// The remediation command. Should be safe and idempotent.
    public let apply: String
    /// True if `apply` deletes data (UI should confirm).
    public let destructive: Bool

    public init(id: String, title: String, summary: String, inspect: String, apply: String, destructive: Bool) {
        self.id = id
        self.title = title
        self.summary = summary
        self.inspect = inspect
        self.apply = apply
        self.destructive = destructive
    }
}

public enum Playbooks {
    public static let all: [Playbook] = [diskCleanup, dockerRestart]

    public static func find(_ id: String) -> Playbook? {
        all.first { $0.id == id }
    }

    /// Disk cleanup — mirrors the safe, high-impact targets from `scripts/storage`
    /// (Xcode DerivedData, Homebrew cache, Trash). Deliberately conservative:
    /// it does NOT wipe ~/Library/Caches wholesale, which can break running apps.
    public static let diskCleanup = Playbook(
        id: "disk-cleanup",
        title: "Disk Cleanup",
        summary: "Reclaim space from Xcode DerivedData, Homebrew cache, and the Trash.",
        inspect: #"""
        echo "Reclaimable (largest first):"
        for p in "$HOME/Library/Developer/Xcode/DerivedData" "$(brew --cache 2>/dev/null)" "$HOME/.Trash" "$HOME/Library/Caches/pip" "$HOME/.npm/_cacache"; do
          [ -e "$p" ] && du -sh "$p" 2>/dev/null
        done | sort -rh
        echo "---"
        df -h /System/Volumes/Data 2>/dev/null | awk 'NR==1 || NR==2'
        """#,
        apply: #"""
        set -e
        echo "Cleaning Homebrew cache…"; brew cleanup --prune=all 2>/dev/null || true
        echo "Clearing Xcode DerivedData…"; rm -rf "$HOME/Library/Developer/Xcode/DerivedData"/* 2>/dev/null || true
        echo "Emptying Trash…"; rm -rf "$HOME/.Trash"/* 2>/dev/null || true
        echo "Done."
        df -h /System/Volumes/Data 2>/dev/null | awk 'NR==2{print "Free now: " $4 " (" $5 " used)"}'
        """#,

        destructive: true
    )

    /// Docker restart — quits and relaunches Docker Desktop, then reports status.
    /// Use when the engine is wedged or containers are misbehaving.
    public static let dockerRestart = Playbook(
        id: "docker-restart",
        title: "Restart Docker",
        summary: "Quit and relaunch Docker Desktop; show container status.",
        inspect: #"""
        if command -v docker >/dev/null 2>&1; then
          docker ps -a --format '{{.Names}}\t{{.Status}}' 2>/dev/null || echo "Docker engine not responding."
        else
          echo "docker CLI not found."
        fi
        """#,
        apply: #"""
        echo "Quitting Docker…"; osascript -e 'quit app "Docker"' 2>/dev/null || true
        sleep 3
        echo "Relaunching Docker…"; open -a Docker 2>/dev/null || true
        echo "Docker is restarting (engine may take ~20s to be ready)."
        """#,
        destructive: false
    )
}
