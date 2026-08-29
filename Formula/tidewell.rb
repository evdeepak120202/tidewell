# Homebrew formula for Tidewell.
#
# Deliberately a *formula*, not a cask. A cask downloads a prebuilt binary, which macOS
# quarantines — and since this project has no paid Apple Developer membership, that binary
# is unnotarised and Gatekeeper will refuse to open it without a trip to System Settings.
#
# A formula compiles on the user's own machine. Nothing is downloaded as an executable, so
# nothing is quarantined, and the install is cleaner than most notarised apps.
class Tidewell < Formula
  desc "File organiser for macOS that cannot delete your files"
  homepage "https://iam-deepak.space"
  url "https://github.com/evdeepak120202/tidewell/archive/refs/tags/v0.1.0-beta.2.tar.gz"
  sha256 "4eb25c90e4e06c8e021d27966395bf02cc7f7e849ff9698572b1278df78c7350"
  license "GPL-3.0-or-later"
  head "https://github.com/evdeepak120202/tidewell.git", branch: "main"

  depends_on xcode: ["15.0", :build]
  depends_on macos: :sonoma

  def install
    # Homebrew builds inside its own sandbox and SwiftPM sandboxes manifest compilation
    # with sandbox-exec. The two cannot nest — the build fails with
    # "sandbox_apply: Operation not permitted" — so SwiftPM's own sandbox is turned off.
    ENV["SWIFT_FLAGS"] = "--disable-sandbox"
    # Without this the bundle reports build.sh's fallback version rather than the one
    # being installed, so About — and therefore every bug report — would be wrong.
    ENV["VERSION"] = version.to_s
    # Homebrew's temporary HOME is not writable by SwiftPM's caches.
    ENV["SWIFTPM_CACHE_DIR"] = buildpath/".swiftpm-cache"

    # Build the bundle exactly the way a developer would, so what the user runs is what
    # the repository describes.
    system "./Scripts/build.sh"

    prefix.install "build/Tidewell.app"

    # A formula only links *binaries* into the prefix, so without this the app exists but
    # Spotlight, Launchpad and the Applications folder never see it — which for a Mac app
    # reads as "the install did nothing".
    #
    # The link points at `opt_prefix`, not the versioned Cellar path: opt is stable across
    # upgrades, so the folder-access grants and login-item registration macOS ties to the
    # bundle path survive a `brew upgrade` instead of resetting every time.
    (Dir.home/"Applications").mkpath
    ln_sf opt_prefix/"Tidewell.app", Dir.home/"Applications/Tidewell.app"

    bin.write_exec_script "#{prefix}/Tidewell.app/Contents/MacOS/Tidewell"
  end

  def caveats
    <<~EOS
      Tidewell has been linked into your Applications folder, so it is in Spotlight and
      Launchpad. Open it from there, or with:

        open ~/Applications/Tidewell.app

      It is a menu bar app — there is no Dock icon and no window at launch. Look for the
      mark in the menu bar.

      To start it at login, use the toggle in Tidewell's own Settings. It registers through
      SMAppService, so you can always revoke it in System Settings › General › Login Items.

      Tidewell never deletes files. Everything it does can be previewed first and undone
      afterwards.

      `brew uninstall` leaves ~/Applications/Tidewell.app behind as a broken link. Remove
      it with:

        rm ~/Applications/Tidewell.app
    EOS
  end

  test do
    assert_predicate prefix/"Tidewell.app/Contents/MacOS/Tidewell", :executable?
  end
end
