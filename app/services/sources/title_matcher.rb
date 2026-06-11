# frozen_string_literal: true

module Sources
  # Title similarity scoring shared by migration discovery and auto-linking.
  # Returns 1.0 for an exact normalized match, 0.8 for containment, otherwise
  # the shared-word ratio.
  module TitleMatcher
    # Above the 0.8 containment score on purpose: only an exact normalized
    # title match may link a series unattended. Containment ("Berserk" inside
    # "Berserk of Gluttony") is a suggestion for a human, not a link.
    AUTO_LINK_CONFIDENCE = 0.9

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

      (shared_terms.to_f / largest_term_count).round(2)
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
