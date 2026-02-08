namespace :variants do
  desc "Backfill WebP display variants for all downloaded pages"
  task backfill: :environment do
    $stdout.sync = true

    unless Page.variant_processing_available?
      abort "libvips is not available. Install with: brew install vips (macOS) or apt install libvips-dev (Linux)"
    end

    # Find pages that don't already have a processed variant
    processed_blob_ids = ActiveStorage::VariantRecord.distinct.pluck(:blob_id)

    scope = Page.joins(image_attachment: :blob)
               .where.not(active_storage_blobs: { content_type: "image/gif" })
    scope = scope.where.not(active_storage_blobs: { id: processed_blob_ids }) if processed_blob_ids.any?

    total = scope.count
    if total.zero?
      puts "All variants are already processed."
      exit
    end

    puts "Processing #{total} pages (#{processed_blob_ids.size} already done)..."
    processed = 0
    errors = 0
    start_time = Time.now

    scope.find_each(batch_size: 100) do |page|
      page.preprocess_display_variant!
      processed += 1

      if (processed % 100).zero?
        elapsed = Time.now - start_time
        rate = processed / elapsed
        remaining = ((total - processed) / rate).round
        mins = remaining / 60
        puts "  #{processed}/#{total} (#{(processed.to_f / total * 100).round(1)}%) — #{rate.round(1)}/s — ~#{mins}m remaining"
      end
    rescue => e
      errors += 1
      Rails.logger.warn "variants:backfill: Failed page #{page.id}: #{e.message}"
    end

    elapsed = (Time.now - start_time).round(1)
    puts "\nDone! Processed #{processed} variants in #{elapsed}s (#{errors} errors)"
  end
end
