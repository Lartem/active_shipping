module ActiveMerchant #:nodoc:
  module Shipping
    
    class PickupAvailability < Response
      attr_reader :carrier # symbol
      attr_reader :carrier_name # string
      attr_reader :pickup_options # array of options
      
      def initialize(success, message, params = {}, options = {})
        @carrier = options[:carrier].parameterize.to_sym
        @carrier_name = options[:carrier]
        @pickup_options = options[:pickup_options]
        super
      end
    end

    class FedexPickupOptions
      attr_reader :carrier, :schedule_day, :available, :pickup_date, :cutoff_time, :access_time, :residential_available
      
      def initialize(carrier, schedule_day, available, pickup_date, cutoff_time, access_time, residential_available)
        @carrier, @schedule_day, @available, @pickup_date, @cutoff_time, @access_time, @residential_available = 
        carrier, schedule_day, available, pickup_date, cutoff_time, access_time, residential_available
      end
    end
  end
end