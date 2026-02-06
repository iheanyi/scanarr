class CoverDownloader
  MAX_REDIRECTS = 5

  # Downloads a cover image from a URL and attaches it to a series.
  # Handles HTTP redirects and SSL certificate issues gracefully.
  def self.download(series, cover_url)
    new.download(series, cover_url)
  end

  def download(series, cover_url)
    return if cover_url.blank?

    response = fetch_with_redirects(cover_url)
    return unless response

    content_type = response["content-type"]
    extension = case content_type
    when /jpeg|jpg/i then "jpg"
    when /png/i then "png"
    when /webp/i then "webp"
    when /gif/i then "gif"
    else "jpg"
    end

    series.cover.attach(
      io: StringIO.new(response.body),
      filename: "cover.#{extension}",
      content_type: content_type
    )
  rescue StandardError => e
    Rails.logger.warn "CoverDownloader: Failed for #{series.canonical_title}: #{e.message}"
  end

  private

  def fetch_with_redirects(url, redirects_remaining = MAX_REDIRECTS, verify_ssl: true)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)

    if uri.scheme == "https"
      http.use_ssl = true
      http.verify_mode = verify_ssl ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
    end

    http.open_timeout = 10
    http.read_timeout = 30

    request = Net::HTTP::Get.new(uri.request_uri)
    response = http.request(request)

    case response
    when Net::HTTPSuccess
      response
    when Net::HTTPRedirection
      return nil if redirects_remaining <= 0

      location = response["location"]
      # Handle relative redirects
      location = URI.join(url, location).to_s unless location.start_with?("http")
      fetch_with_redirects(location, redirects_remaining - 1, verify_ssl: verify_ssl)
    else
      Rails.logger.warn "CoverDownloader: HTTP #{response.code} for #{url}"
      nil
    end
  rescue OpenSSL::SSL::SSLError => e
    if verify_ssl
      Rails.logger.warn "CoverDownloader: SSL error for #{url}, retrying without strict verification: #{e.message}"
      fetch_with_redirects(url, redirects_remaining, verify_ssl: false)
    else
      Rails.logger.warn "CoverDownloader: SSL error (insecure) for #{url}: #{e.message}"
      nil
    end
  end
end
