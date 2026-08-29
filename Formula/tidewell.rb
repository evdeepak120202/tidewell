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
  url "https://github.com/evdeepak120202/tidewell/archive/refs/tags/v0.1.0-beta.4.tar.gz"
  sha256 "605d89c2d2dc7385ef3857a43c06042595d389be14d9d6a06fd1527a7e11dfb7"
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

    bin.write_exec_script "#{prefix}/Tidewell.app/Contents/MacOS/Tidewell"
  end

  def caveats
    <<~EOS
      Tidewell is installed, but Homebrew formulae only link binaries — the app itself
      stays in the Cellar, where Spotlight and Launchpad will not find it. To put it in
      your Applications folder:

        ln -sf #{opt_prefix}/Tidewell.app ~/Applications/

      (Homebrew sandboxes both the install and post-install steps, so a formula cannot
      write outside its own prefix and has to ask you to run this. The link points at
      opt, so it stays valid across upgrades.)

      Or launch it without linking:

        open #{opt_prefix}/Tidewell.app

      It is a menu bar app — no Dock icon and no window at launch. Look for the mark in
      the menu bar.

      To start it at login, use the toggle in Tidewell's own Settings. It registers through
      SMAppService, so you can always revoke it in System Settings › General › Login Items.

      Tidewell never deletes files. Everything it does can be previewed first and undone
      afterwards.

      If you made the link, `brew uninstall` leaves it behind as a broken alias:

        rm ~/Applications/Tidewell.app
    EOS
  end

  test do
    assert_predicate prefix/"Tidewell.app/Contents/MacOS/Tidewell", :executable?
  end
end
