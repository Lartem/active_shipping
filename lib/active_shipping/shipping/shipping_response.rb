module ActiveMerchant #:nodoc:
  module Shipping
    
    class ShippingResponse < Response
      attr_reader :carrier # symbol
      attr_reader :carrier_name # string
      attr_reader :shipment_details # details
      
      def initialize(success, message, params = {}, options = {})
        @carrier = options[:carrier].parameterize.to_sym
        @carrier_name = options[:carrier]
        @pickup_options = options[:shipment_details]
        super
      end
    end
  end
end