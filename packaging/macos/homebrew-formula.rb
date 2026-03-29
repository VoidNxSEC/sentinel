# Homebrew formula for voidnxlabs CLI tools
# Tap: https://github.com/VoidNxSEC/homebrew-tap
#
# Installation:
#   brew tap VoidNxSEC/tap
#   brew install voidnxlabs

class Voidnxlabs < Formula
  desc "voidnxlabs infrastructure stack — AI Security & DevOps tooling"
  homepage "https://github.com/VoidNxSEC"
  version "0.1.0"
  license "Apache-2.0"

  on_macos do
    on_arm do
      url "https://github.com/VoidNxSEC/releases/download/v#{version}/voidnxlabs-#{version}-aarch64-apple-darwin.tar.gz"
      # sha256 computed at release time
    end

    on_intel do
      url "https://github.com/VoidNxSEC/releases/download/v#{version}/voidnxlabs-#{version}-x86_64-apple-darwin.tar.gz"
      # sha256 computed at release time
    end
  end

  # Binaries included in the formula
  #   ai-agent       — system monitoring agent
  #   securellm-bridge — zero-trust LLM proxy

  def install
    bin.install "ai-agent"
    bin.install "securellm-bridge"
    bin.install "owasaka" if File.exist?("owasaka")
  end

  def post_install
    (var/"voidnxlabs").mkpath
    (etc/"voidnxlabs").mkpath

    unless (etc/"voidnxlabs/env").exist?
      (etc/"voidnxlabs/env").write <<~ENV
        # voidnxlabs environment
        NATS_URL=nats://localhost:4222
      ENV
    end
  end

  service do
    run [opt_bin/"ai-agent"]
    keep_alive true
    log_path var/"log/voidnxlabs-ai-agent.log"
    error_log_path var/"log/voidnxlabs-ai-agent.log"
    environment_variables(
      NATS_URL: "nats://localhost:4222"
    )
  end

  test do
    assert_match "voidnxlabs", shell_output("#{bin}/ai-agent --version 2>&1")
  end
end
