# frozen_string_literal: true

class AdapterRegistry
  class UnknownSourceError < StandardError; end

  ADAPTERS = {
    "mangadex" => -> { Scrapers::Mangadex::Adapter },
    "weeb_central" => -> { Scrapers::WeebCentral::Adapter },
    "manga_see" => -> { Scrapers::MangaSee::Adapter },
    "asura_scans" => -> { Scrapers::AsuraScans::Adapter },
    "manga_pill" => -> { Scrapers::MangaPill::Adapter },
    "comick" => -> { Scrapers::Comick::Adapter },
    "tcb_scans" => -> { Scrapers::TcbScans::Adapter },
    "manga_kakalot" => -> { Scrapers::MangaKakalot::Adapter },
    "flame_comics" => -> { Scrapers::FlameComics::Adapter },
    "batoto" => -> { Scrapers::Batoto::Adapter },
    "manga_here" => -> { Scrapers::MangaHere::Adapter },
    "manga_clash" => -> { Scrapers::MangaClash::Adapter },
    "manga_buddy" => -> { Scrapers::MangaBuddy::Adapter },
    "zero_scans" => -> { Scrapers::ZeroScans::Adapter },
    "manhua_plus" => -> { Scrapers::ManhuaPlus::Adapter },
    "isekai_scan" => -> { Scrapers::IsekaiScan::Adapter },
    "toonily" => -> { Scrapers::Toonily::Adapter },
    "drake_scans" => -> { Scrapers::DrakeScans::Adapter },
    "like_manga" => -> { Scrapers::LikeManga::Adapter },
    "manga_freak" => -> { Scrapers::MangaFreak::Adapter },
    "manga_read" => -> { Scrapers::MangaRead::Adapter },
    "manga_geko" => -> { Scrapers::MangaGeko::Adapter },
    "manhwa18" => -> { Scrapers::Manhwa18::Adapter },
    "manga_nato" => -> { Scrapers::MangaNato::Adapter },
    "manga_fire" => -> { Scrapers::MangaFire::Adapter }
  }.freeze

  class << self
    def for(source_or_key)
      key = source_or_key.is_a?(String) ? source_or_key : source_or_key.key
      adapter_for_key(key)
    end

    def adapter_for_key(key)
      adapter_proc = ADAPTERS[key]
      raise UnknownSourceError, "Unknown source: #{key}" unless adapter_proc

      config = source_config(key)
      adapter_proc.call.new(config: config)
    end

    def registered_keys
      ADAPTERS.keys
    end

    def registered?(key)
      ADAPTERS.key?(key)
    end

    private

    def source_config(key)
      Rails.application.config_for(:sources).fetch(key.to_sym, {}).to_h.deep_stringify_keys
    rescue RuntimeError
      {}
    end
  end
end
