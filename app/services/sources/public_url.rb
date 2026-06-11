# frozen_string_literal: true

require "ipaddr"
require "socket"

module Sources
  # SSRF guard for URLs that originate in third-party data (the upstream
  # catalog feed). Literal host checks run at ingest over the whole feed;
  # DNS resolution runs only at adoption time, just before a stored URL is
  # first probed, so a hostname pointed at an internal address is rejected
  # at the moment it would matter.
  module PublicUrl
    INTERNAL_SUFFIXES = [ ".localhost", ".internal", ".local" ].freeze

    # Non-global ranges IPAddr's predicates don't cover: "this network",
    # CGNAT, IETF reserved, documentation/benchmark nets, multicast, and
    # class E, plus their IPv6 analogues.
    RESERVED_RANGES = %w[
      0.0.0.0/8 100.64.0.0/10 192.0.0.0/24 192.0.2.0/24 198.18.0.0/15
      198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4
      ::/128 100::/64 2001:db8::/32 ff00::/8
    ].map { |cidr| IPAddr.new(cidr) }.freeze

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

    # The system resolver (getaddrinfo), not Resolv: Net::HTTP connects via
    # the socket layer, which also accepts noncanonical IPv4 forms like
    # "127.1" or "2130706433" that IPAddr refuses to parse and DNS would not
    # answer for. Guarding with anything weaker than what the fetch path
    # uses leaves a bypass.
    SYSTEM_RESOLVER = lambda do |host|
      Addrinfo.getaddrinfo(host, nil, nil, :STREAM).map(&:ip_address)
    rescue SocketError
      []
    end

    # Literal checks plus resolution. An unresolvable host is allowed
    # through: it cannot be fetched anyway, and a DNS flake must not reject
    # a legitimate domain.
    def resolves_internal?(host, resolver: SYSTEM_RESOLVER)
      return true if internal_host?(host)

      resolver.call(host.to_s).any? { |address| internal_address?(address) }
    end

    def internal_address?(value)
      addr = value.is_a?(IPAddr) ? value : IPAddr.new(value.to_s)
      addr.loopback? || addr.private? || addr.link_local? ||
        RESERVED_RANGES.any? { |range| range.include?(addr) }
    rescue IPAddr::InvalidAddressError
      false
    end
  end
end
