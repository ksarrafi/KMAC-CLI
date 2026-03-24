# frozen_string_literal: true

class Kmac < Formula
  desc "Portable macOS & Linux dev toolkit with AI, Docker, secrets vault, and remote agent control"
  homepage "https://github.com/ksarrafi/KMAC-CLI"
  license "MIT"
  version "2.8.0"

  # Stable tarball (update version, url, and sha256 when tagging a release).
  # After pushing tag vX.Y.Z, run:
  #   curl -sL "https://github.com/ksarrafi/KMAC-CLI/archive/refs/tags/vX.Y.Z.tar.gz" | shasum -a 256
  url "https://github.com/ksarrafi/KMAC-CLI/archive/refs/tags/v2.8.0.tar.gz"
  sha256 "7cc525ec2166b5a2d13a2448d9f8438d20b74db579f193d413a0b40f6c01bb23"

  head "https://github.com/ksarrafi/KMAC-CLI.git", branch: "main"

  depends_on "fzf" => :recommended
  depends_on "bat" => :recommended
  depends_on "jq" => :recommended

  def install
    libexec.install Dir["*"]
    (bin/"kmac").write <<~SH
      #!/usr/bin/env bash
      exec "#{libexec}/toolkit.sh" "$@"
    SH
    chmod "+x", bin/"kmac"
  end

  def caveats
    <<~EOS
      Shell aliases and functions live in aliases.sh. Add this to ~/.zshrc (or ~/.bashrc):

        source #{opt_libexec}/aliases.sh

      Restart the shell or run source ~/.zshrc afterward.
    EOS
  end

  test do
    out = shell_output("#{bin}/kmac version")
    assert_match(/portable macOS toolkit/, out)
  end
end
