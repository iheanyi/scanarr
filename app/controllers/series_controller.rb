class SeriesController < ApplicationController
  before_action :set_source

  def index
    @series = Series.joins(:series_sources)
                    .where(series_sources: { source_id: @source.id })
                    .order(:canonical_title)
  end

  def show
    @series = Series.joins(:series_sources)
                    .where(series_sources: { source_id: @source.id })
                    .friendly
                    .find(params[:series_slug])
    @chapters = @series.chapters
                       .where(source: @source)
                       .includes(releases: :file_asset)
                       .order(
                         Arel.sql("chapter_number_value ASC NULLS LAST"),
                         Arel.sql("title ASC NULLS LAST"),
                         :chapter_number,
                         :id
                       )
  end

  def update
    @series = Series.joins(:series_sources)
                    .where(series_sources: { source_id: @source.id })
                    .friendly
                    .find(params[:series_slug])
    @series.update!(series_params)
    redirect_to source_series_path(source_slug: @source.key.to_s.tr("_", "-"), series_slug: @series.friendly_id)
  end

  private

  def series_params
    params.require(:series).permit(:reading_style)
  end

  def set_source
    key = params[:source_slug].to_s.tr("-", "_")
    @source = Source.find_by!(key: key)
  end
end
