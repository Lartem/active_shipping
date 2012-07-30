module ActiveMerchant #:nodoc:
  module Shipping
    
    class AddressValidation < Response
      attr_reader :carrier # symbol
      attr_reader :carrier_name # string
      attr_reader :status # symbol
      attr_reader :status_code # string
      attr_reader :status_description #string
      attr_reader :addresses # validated locations
      attr_reader :parsed_results # parsed results separated from response
      
      def initialize(success, message, params = {}, options = {})
        @carrier = options[:carrier].parameterize.to_sym
        @carrier_name = options[:carrier]
        @status = options[:status]
        @status_code = options[:status_code]
        @status_description = options[:status_description]
        @addresses = options[:addresses]
        @parsed_results = options[:parsed_av_results]
        super
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