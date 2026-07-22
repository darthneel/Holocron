# frozen_string_literal: true

module Holocron
  module SemanticBurstRules
    MINIMUM_SOURCE_LENGTH = 320
    MINIMUM_LENGTH = 60
    SIGNAL_PATTERN = /\b(decid(?:e|ed|ing)|agree(?:d)?|commit(?:ted|ment)?|will|owner|deadline|due|before|by \w+ \d{1,2}|concern(?:ed)?|object(?:ed|ion)?|oppose(?:d)?|risk|constraint|require(?:d|ment)?|only if|unless|blocked|delay(?:ed)?|asked|requested|recommend(?:ed)?|question|unresolved|follow.?up|next step)\b/i
    IDENTIFIER_PATTERN = /\b(?:[A-Z]{2,}[\s-]?\d{2,}|\d{1,3}(?:\.\d+)?%|\$\d|\w+[._-]v?\d+|\d{4}-\d{2}-\d{2})\b/
    EXPLICIT_KINDS = %w[decision commitment concern request].freeze

    module_function

    def segments(summary)
      paragraphs = summary.split(/\n{2,}/).map(&:strip).reject(&:empty?)
      paragraphs = summary.split(/(?<=[.!?])\s+(?=[A-Z0-9])/).map(&:strip) if paragraphs.length == 1
      paragraphs
    end

    def high_signal?(segment, signal_kind)
      return false if segment.length < MINIMUM_LENGTH
      return true if signal_kind != "background"
      return true if segment.match?(IDENTIFIER_PATTERN)

      segment.length >= 180
    end

    def signal_kind(segment)
      case segment
      when /\b(decid(?:e|ed|ing)|agreed|approved|selected|chose)\b/i then "decision"
      when /\b(commit(?:ted|ment)?|will|owner|deadline|due|follow.?up|next step|by \w+ \d{1,2})\b/i then "commitment"
      when /\b(concern(?:ed)?|object(?:ed|ion)?|oppose(?:d)?|risk|constraint|blocked|delay(?:ed)?|only if|unless|requires?)\b/i then "concern"
      when /\b(asked|requested|recommend(?:ed)?|question|unresolved|confirm)\b/i then "request"
      else
        segment.match?(SIGNAL_PATTERN) ? "signal" : "background"
      end
    end
  end
end
