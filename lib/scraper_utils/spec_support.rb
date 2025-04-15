# frozen_string_literal: true

require "scraperwiki"

module ScraperUtils
  # Methods to support specs
  module SpecSupport
    AUSTRALIAN_STATES = %w[ACT NSW NT QLD SA TAS VIC WA].freeze
    STREET_TYPE_PATTERNS = [
      /\bAv(e(nue)?)?\b/i,
      /\bB(oulevard|lvd)\b/i,
      /\b(Circuit|Cct)\b/i,
      /\bCl(ose)?\b/i,
      /\bC(our|r)?t\b/i,
      /\bCircle\b/i,
      /\bChase\b/i,
      /\bCr(es(cent)?)?\b/i,
      /\bDr((ive)?|v)\b/i,
      /\bEnt(rance)?\b/i,
      /\bGr(ove)?\b/i,
      /\bH(ighwa|w)y\b/i,
      /\bLane\b/i,
      /\bLoop\b/i,
      /\bParkway\b/i,
      /\bPl(ace)?\b/i,
      /\bPriv(ate)?\b/i,
      /\bParade\b/i,
      /\bR(oa)?d\b/i,
      /\bRise\b/i,
      /\bSt(reet)?\b/i,
      /\bSquare\b/i,
      /\bTerrace\b/i,
      /\bWay\b/i
    ].freeze

    AUSTRALIAN_POSTCODES = /\b\d{4}\b/.freeze

    # Check if an address is likely to be geocodable by analyzing its format.
    # This is a bit stricter than needed - typically assert >= 75% match
    # @param address [String] The address to check
    # @return [Boolean] True if the address appears to be geocodable.
    def self.geocodable?(address, ignore_case: false)
      return false if address.nil? || address.empty?
      check_address = ignore_case ? address.upcase : address

      # Basic structure check - must have a street name, suburb, state and postcode
      has_state = AUSTRALIAN_STATES.any? { |state| check_address.end_with?(" #{state}") || check_address.include?(" #{state} ") }
      has_postcode = address.match?(AUSTRALIAN_POSTCODES)

      # Using the pre-compiled patterns
      has_street_type = STREET_TYPE_PATTERNS.any? { |pattern| check_address.match?(pattern) }

      has_unit_or_lot = address.match?(/\b(Unit|Lot:?)\s+\d+/i)

      has_suburb_stats = check_address.match?(/(\b[A-Z]{2,}(\s+[A-Z]+)*,?|,\s+[A-Z][A-Za-z ]+)(\s+\d{4})?\s+(#{AUSTRALIAN_STATES.join('|')})\b/)

      if ENV["DEBUG"]
        missing = []
        unless has_street_type || has_unit_or_lot
          missing << "street type / unit / lot"
        end
        missing << "state" unless has_state
        missing << "postcode" unless has_postcode
        missing << "suburb state" unless has_suburb_stats
        puts "  address: #{address} is not geocodable, missing #{missing.join(', ')}" if missing.any?
      end

      (has_street_type || has_unit_or_lot) && has_state && has_postcode && has_suburb_stats
    end

    PLACEHOLDERS = [
      /no description/i,
      /not available/i,
      /to be confirmed/i,
      /\btbc\b/i,
      %r{\bn/a\b}i
    ].freeze

    def self.placeholder?(text)
      PLACEHOLDERS.any? { |placeholder| text.to_s.match?(placeholder) }
    end

    # Check if this looks like a "reasonable" description
    # This is a bit stricter than needed - typically assert >= 75% match
    def self.reasonable_description?(text)
      !placeholder?(text) && text.to_s.split.size >= 3
    end
  end
end

