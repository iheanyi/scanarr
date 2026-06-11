# frozen_string_literal: true

require "ipaddr"
require "resolv"

module Sources
  # SSRF guard for URLs that originate in third-party data (the upstream
  # catalog feed). Literal host checks run at ingest over the whole feed;
  # DNS resolution runs only at adoption time, just before a stored URL is
  # first probed, so a hostname pointed at an internal address is rejected
  # at the moment it would matter.
  module PublicUrl
    INTERNAL_SUFFIXES = [ ".localhost", ".internal", ".local" ].freeze

    module_function

    def internal_host?(host)
      bare = host.to_s.delete_prefix("[").delete_suffix("]")
      return true if bare.casecmp?("localhost")
      return true if INTERNAL_SUFFIXES.any? { |suffix| bare.downcase.end_with?(suffix) }

      internal_address?(bare)
    rescue IPAddr::InvalidAddressError
      # A plain hostname, not an IP literal.
      false
    end

    # Literal checks plus DNS resolution. An unresolvable host is allowed
    # through: it cannot be fetched anyway, and a DNS flake must not reject
    # a legitimate domain.
    def resolves_internal?(host, resolver: Resolv.method(:getaddresses))
      return true if internal_host?(host)

      resolver.call(host.to_s).any? { |address| internal_address?(address) }
    end

    def internal_address?(value)
      addr = value.is_a?(IPAddr) ? value : IPAddr.new(value.to_s)
      addr.loopback? || addr.private? || addr.link_local? || addr == IPAddr.new("0.0.0.0")
    rescue IPAddr::InvalidAddressError
      false
    end
  end
end
