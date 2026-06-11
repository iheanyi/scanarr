# frozen_string_literal: true

module Sources
  # Title similarity scoring shared by migration discovery and auto-linking.
  # Scores are strict tiers, not a continuous scale: 1.0 is reserved for an
  # exact normalized match, 0.8 for containment, and the shared-word ratio is
  # capped below containment so overlap can never impersonate a higher tier
  # (ten-of-eleven shared words, or the same words reordered, must not link
  # a series unattended).
  module TitleMatcher
    # Only an exact normalized title match may link unattended. Containment
    # ("Berserk" inside "Berserk of Gluttony") and word overlap are
    # suggestions for a human, not links.
    AUTO_LINK_CONFIDENCE = 1.0
    WORD_OVERLAP_CAP = 0.75

    module_function

    def score(title, candidate_title)
      normalized = normalize(title)
      normalized_candidate = normalize(candidate_title)
      return 0.0 if normalized.blank? || normalized_candidate.blank?
      return 1.0 if normalized == normalized_candidate
      return 0.8 if normalized_candidate.include?(normalized) || normalized.include?(normalized_candidate)

      shared_terms = (normalized.split & normalized_candidate.split).size
      largest_term_count = [ normalized.split.size, normalized_candidate.split.size ].max
      return 0.0 if largest_term_count.zero?

      [ (shared_terms.to_f / largest_term_count).round(2), WORD_OVERLAP_CAP ].min
    end

    # Best [result, confidence] pair at or above min_confidence, or [nil, 0.0].
    def best_match(title, results, min_confidence:)
      scored = results.filter_map do |result|
        confidence = score(title, result.title)
        next if confidence < min_confidence

        [ result, confidence ]
      end

      scored.max_by { |(_, confidence)| confidence } || [ nil, 0.0 ]
    end

    def normalize(value)
      value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish
    end
  end
end
