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
  url "https://github.com/evdeepak120202/tidewell/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "REPLACE_ON_RELEASE"
  license "GPL-3.0-or-later"
  head "https://github.com/evdeepak120202/tidewell.git", branch: "main"

  depends_on xcode: ["15.0", :build]
  depends_on macos: :sonoma

  def install
    # Build the bundle exactly the way a developer would, so what the user runs is what
    # the repository describes.
    system "./Scripts/build.sh"

    prefix.install "build/Tidewell.app"
    # Symlink so `open -a Tidewell` and Spotlight find it.
    bin.write_exec_script "#{prefix}/Tidewell.app/Contents/MacOS/Tidewell"
  end

  def caveats
    <<~EOS
      Tidewell is a menu bar app. Launch it with:

        open #{prefix}/Tidewell.app

      To have it start at login, use the toggle in Tidewell's own Settings — it registers
      through SMAppService so you can revoke it in System Settings › General › Login Items.

      Tidewell never deletes files. Everything it does can be previewed first and undone
      afterwards.
    EOS
  end

  test do
    assert_predicate prefix/"Tidewell.app/Contents/MacOS/Tidewell", :executable?
  end
end
