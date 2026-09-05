module UI
  class ContinueReadingComponent < BaseComponent
    def initialize(progress:)
      @progress = progress
      super()
    end

    private

    attr_reader :progress

    def chapter = progress.chapter
    def series = chapter.series

    def current_page
      [ [ progress.page_index, 1 ].max, progress.page_count ].min
    end

    def reader_path
      helpers.source_series_chapter_path(
        source_slug: chapter.source.slug,
        series_slug: series.to_param,
        chapter_identifier: chapter.public_id
      )
    end
  end
end
