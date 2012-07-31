module ActiveMerchant #:nodoc:
  module Shipping
    
    class AddressValidation < Response
      attr_reader :carrier # symbol
      attr_reader :carrier_name # string
      attr_reader :addresses # validated locations, wrapped to AddressValidationDetails
      attr_reader :parsed_results # parsed results separated from response
      
      def initialize(success, message, params = {}, options = {})
        @carrier = options[:carrier].parameterize.to_sym
        @carrier_name = options[:carrier]
        @addresses = options[:addresses]
        @parsed_results = options[:parsed_av_results]
        super
      end
    end

    # contains location & additional info about validation
    class AddressValidationDetails
      attr_reader :score, :changes, :location, :deliverable, :address_id

      def initialize(location, score, address_id, changes=nil, deliverable=true)
         @address_id, @location, @score, @changes, @deliverable = address_id, location, score, changes, deliverable
      end

      def is_deliverable?
        @deliverable == 'CONFIRMED'
      end
    end

    class ParsedAddressValidationResults 
      attr_reader :street_line # array of parsed street lines {:name, :value, :changes}
      attr_reader :city # array of parsed cities elements
      attr_reader :province # array of parsed province elements
      attr_reader :postal_code # array of parsed postal code elements
      attr_reader :country # array of parsed city elements

      def initialize(street_line, city, province, postal_code, country)
        @street_line, @city, @province, @postal_code, @country = street_line, city, province, postal_code, country
      end
    end
    
    class ParsedAddressValidationElement 
      attr_reader :name
      attr_reader :value
      attr_reader :changes

      def initialize(name, value, changes)
        @name, @value, @changes = name, value, changes
      end

      def changed?
        @changes != 'NO_CHANGES'
      end
    end

  end
end