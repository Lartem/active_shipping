# -*- encoding: utf-8 -*-

module ActiveMerchant
  module Shipping
    class UPS < Carrier
      self.retry_safe = true
      
      cattr_accessor :default_options
      cattr_reader :name
      @@name = "UPS"
      
      TEST_URL = 'https://wwwcie.ups.com'
      LIVE_URL = 'https://onlinetools.ups.com'
      
      RESOURCES = {
        :rates => 'ups.app/xml/Rate',
        :track => 'ups.app/xml/Track',
        :address_validation => 'ups.app/xml/AV',
        :shipping => 'webservices/Ship', # webservices
        :address_validation_street => 'webservices/XAV',
        :courier_dispatch => 'webservices/Pickup',
        :cancel_shipping => 'webservices/Void'
      }
      
      PICKUP_CODES = HashWithIndifferentAccess.new({
        :daily_pickup => "01",
        :customer_counter => "03", 
        :one_time_pickup => "06",
        :on_call_air => "07",
        :suggested_retail_rates => "11",
        :letter_center => "19",
        :air_service_center => "20"
      })

      CREDIT_CARD_TYPES = {
        '01' => 'American Express',
        '03' => 'Discover',
        '04' => 'MasterCard',
        '05' => 'Optima', 
        '06' => 'VISA',
        '07' => 'Bravo',
        '08' => 'Diners Club' 
      }


      CUSTOMER_CLASSIFICATIONS = HashWithIndifferentAccess.new({
        :wholesale => "01",
        :occasional => "03", 
        :retail => "04"
      })

      # these are the defaults described in the UPS API docs,
      # but they don't seem to apply them under all circumstances,
      # so we need to take matters into our own hands
      DEFAULT_CUSTOMER_CLASSIFICATIONS = Hash.new do |hash,key|
        hash[key] = case key.to_sym
        when :daily_pickup then :wholesale
        when :customer_counter then :retail
        else
          :occasional
        end
      end
      
      DEFAULT_SERVICES = {
        "01" => "UPS Next Day Air",
        "02" => "UPS Second Day Air",
        "03" => "UPS Ground",
        "07" => "UPS Worldwide Express",
        "08" => "UPS Worldwide Expedited",
        "11" => "UPS Standard",
        "12" => "UPS Three-Day Select",
        "13" => "UPS Next Day Air Saver",
        "14" => "UPS Next Day Air Early A.M.",
        "54" => "UPS Worldwide Express Plus",
        "59" => "UPS Second Day Air A.M.",
        "65" => "UPS Saver",
        "82" => "UPS Today Standard",
        "83" => "UPS Today Dedicated Courier",
        "84" => "UPS Today Intercity",
        "85" => "UPS Today Express",
        "86" => "UPS Today Express Saver"
      }
      
      CANADA_ORIGIN_SERVICES = {
        "01" => "UPS Express",
        "02" => "UPS Expedited",
        "14" => "UPS Express Early A.M."
      }
      
      MEXICO_ORIGIN_SERVICES = {
        "07" => "UPS Express",
        "08" => "UPS Expedited",
        "54" => "UPS Express Plus"
      }
      
      EU_ORIGIN_SERVICES = {
        "07" => "UPS Express",
        "08" => "UPS Expedited"
      }
      
      OTHER_NON_US_ORIGIN_SERVICES = {
        "07" => "UPS Express"
      }

      TRACKING_STATUS_CODES = HashWithIndifferentAccess.new({
        'I' => :in_transit,
        'D' => :delivered,
        'X' => :exception,
        'P' => :pickup,
        'M' => :manifest_pickup
      })

      PACKAGING_TYPES = {
        '00' => 'Unknown',
        '01' => 'UPS Letter', 
        '02' => 'Package',
        '03' => 'Tube', 
        '04' => 'Pak',
        '21' => 'Express Box',
        '24' => '25KG Box',
        '25' => '10KG Box', 
        '30' => 'Pallet',
        '2a' => 'Small Express Box', 
        '22b' => 'Medium Express Box',
        '2c' => 'Large Express Box'
      }

      # From http://en.wikipedia.org/w/index.php?title=European_Union&oldid=174718707 (Current as of November 30, 2007)
      EU_COUNTRY_CODES = ["GB", "AT", "BE", "BG", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT", "LV", "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE"]
      
      US_TERRITORIES_TREATED_AS_COUNTRIES = ["AS", "FM", "GU", "MH", "MP", "PW", "PR", "VI"]

      #Shipment response structures
      ShipmentResult = Struct.new(:shipment_charges, :billing_weight, :shipment_identification_number, :package_results)
      ShipmentCharges = Struct.new(:transportation_charges, :service_options_charges, :total_charges)
      Charge = Struct.new(:currency_code, :monetary_value)
      BillingWeight = Struct.new(:unit_of_measurement, :weight)
      UnitOfMeasurement = Struct.new(:code, :description)
      PackageResult = Struct.new(:tracking_number, :service_options_charges, :shipping_label)
      ShippingLabel = Struct.new(:image_format, :graphic_image_base64, :html_image_base64)
      
      #void shipping response
      VoidShippingResponse = Struct.new(:is_success, :message, :status, :transaction_reference, :summary_result)
      Status = Struct.new(:code, :description)
      TransactionReference = Struct.new(:customer_context, :transaction_identifier)

      #Address validation response
      AddressValidationResponse = Struct.new(:city_level_status, :street_level_status, :status, :message, :type, :error, :valid_address, :candidates)
      AddressCandidate = Struct.new(:address_type, :location)
      AddressType = Struct.new(:code, :description)
      Error = Struct.new(:code, :severity, :description)

      LOGGER_NAMES = [:address_validation, :rates, :tracking, :pickup_availability, :courier_dispatch, :request_shipping, :cancel_pickup, :cancel_shipping, :search_location]

      def initialize(options={})
        @loggers = create_loggers(options[:log_dir]) if options[:log_dir] != nil
        @loggers ||= {}
        super(options)
      end

      def requirements
        [:key, :login, :password]
      end
      
      def find_rates(origin, destination, packages, options={})
        origin, destination = upsified_location(origin), upsified_location(destination)
        options = @options.merge(options)
        packages = Array(packages)
        access_request = build_access_request
        rate_request = build_rate_request(origin, destination, packages, options)
        p rate_request
        response = commit(:rates, save_request(access_request + rate_request), (options[:test] || false))
         p 'Rates response'
         p response
        parse_rate_response(origin, destination, packages, response, options)
      end
      
      def find_tracking_info(tracking_number, options={})
        options = @options.update(options)
        access_request = build_access_request
        tracking_request = build_tracking_request(tracking_number, options)
        p access_request + tracking_request
        response = commit(:track, save_request(access_request + tracking_request), (options[:test] || false))
        p 'Tracking response'
        p response
        parse_tracking_response(response, options)
      end

      def request_shipping(shipper, shipper_location, ship_to_person, ship_to_location, ship_from_person, ship_from_location, package_item, options={})
        options = @options.update(options)
        shipping_request = build_shipping_request(shipper, shipper_location, ship_to_person, ship_to_location, ship_from_person, ship_from_location, package_item, options)
        
        response = commit(:shipping, save_request(shipping_request), (options[:test] || false))
        response = response.gsub(/\sxmlns(:|=)[^>]*/, '').gsub(/<(\/)?[^<]*?\:(.*?)>/, '<\1\2>')
        parse_shipping_response(response, options)
      end
      
      #
      # UPS Address validation schema contains only one address container
      def validate_address(address, options={})
        options = @options.update(options)
        access_request = build_access_request
        address_validation_city_request = build_address_validation_city_request(address, options)
        p 'Address city validation request'
        #UPS API wants to see <?xml ..?> tags in this request
        req = "<?xml version='1.0'?>" + access_request +"<?xml version='1.0'?>"+ address_validation_city_request
        p req
        response_city_validation = commit(:address_validation, save_request(req), (options[:test] || false))
        p 'Address validation response_city_validation'
        p response_city_validation
        parsed_response = parse_address_city_validation_response(response_city_validation, options)
        
        
        if parsed_response.city_level_status
          address_street_validation_request = build_address_validation_street_request(address, options)
          p address_street_validation_request
          #UPS sandbox is not knowing about all states
          response_street_validation = commit(:address_validation_street, save_request(address_street_validation_request), (false))
          p response_street_validation
          response_street_validation = response_street_validation.gsub(/\sxmlns(:|=)[^>]*/, '').gsub(/<(\/)?[^<]*?\:(.*?)>/, '<\1\2>')
          parsed_response = parse_address_street_validation_response(response_street_validation, parsed_response, options)

        end
        p parsed_response
        parsed_response
      end

      def check_pickup_availability()
        #TODO
      end

      def cancel_shipment shipment_identification_number, options = {}
        options = @options.update(options)
        cancel_request = build_cancel_shipment_request(shipment_identification_number, options)
        p cancel_request
        response = commit(:cancel_shipping, save_request(cancel_request), (options[:test] || false))
        response = response.gsub(/\sxmlns(:|=)[^>]*/, '').gsub(/<(\/)?[^<]*?\:(.*?)>/, '<\1\2>')
        resp = parse_cancel_shipment_response(response, options)
        resp
      end
      
      def courier_dispatch(pickup_location, close_time, ready_time, pickup_date, service_code, quantity, dest_country_code, container_code, total_weight, weight_units, residential=nil, options={})
        options = @options.update(options)
        p options
        courier_dispatch_request = build_courier_dispatch_request(pickup_location, close_time, ready_time, pickup_date, service_code, quantity, dest_country_code, container_code, total_weight, weight_units, residential)
        puts 'Courier dispatch request'
        p courier_dispatch_request
        response = commit(:courier_dispatch, save_request(courier_dispatch_request), (options[:test] || false)) #.gsub(/\sxmlns(:|=)[^>]*/, '').gsub(/<(\/)?[^<]*?\:(.*?)>/, '<\1\2>')
        puts 'response!'
        response = response.gsub(/\sxmlns(:|=)[^>]*/, '').gsub(/<(\/)?[^<]*?\:(.*?)>/, '<\1\2>')
        p response
        parse_courier_dispatch_response(response, options)
      end

      def courier_dispatch_cancel(prn, options={})
        options = @options.update(options)
        courier_dispatch_cancel_request = build_courier_dispatch_cancel_request(prn, options)
        puts 'Courier dispatch Cancel request'
        p courier_dispatch_cancel_request
        response = commit(:courier_dispatch, save_request(courier_dispatch_cancel_request), (options[:test] || false)) #.gsub(/\sxmlns(:|=)[^>]*/, '').gsub(/<(\/)?[^<]*?\:(.*?)>/, '<\1\2>')
        response = response.gsub(/\sxmlns(:|=)[^>]*/, '').gsub(/<(\/)?[^<]*?\:(.*?)>/, '<\1\2>')
        p response
        parse_courier_dispatch_cancel_response(response, options)
      end

      protected

      def build_cancel_shipment_request shipment_identification_number, options
        xml_request = XmlNode.new('envr:Envelope', 'xmlns:auth' => 'http://www.ups.com/schema/xpci/1.0/auth', 
          'xmlns:upss' => 'http://www.ups.com/XMLSchema/XOLTWS/UPSS/v1.0', 'xmlns:envr' => 'http://schemas.xmlsoap.org/soap/envelope/',
          'xmlns:xsd' => 'http://www.w3.org/2001/XMLSchema', 'xmlns:common' => 'http://www.ups.com/XMLSchema/XOLTWS/Common/v1.0',
          'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance', 'xmlns:wsf' => 'http://www.ups.com/schema/wsf') do |env_node|
          env_node << XmlNode.new('envr:Header') do |h_node|
            h_node << build_ws_access_request
          end
          env_node << XmlNode.new('envr:Body') do |body_node| 
            body_node << XmlNode.new('VoidShipmentRequest', {'xmlns'=>'http://www.ups.com/XMLSchema/XOLTWS/Void/v1.1', 'xmlns:xsd' => 'http://www.w3.org/2001/XMLSchema', 'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance', 'xmlns:common'=>'http://www.ups.com/XMLSchema/XOLTWS/Common/v1.0'}) do |void_shipment_request_node|
              void_shipment_request_node << XmlNode.new('Request', 'xmlns' => 'http://www.ups.com/XMLSchema/XOLTWS/Common/v1.0') do |request_node|
                request_node << XmlNode.new('TransactionReference', options[:transaction_reference]) if options[:transaction_reference]
              end
              void_shipment_request_node << XmlNode.new('VoidShipment', 'xmlns' => 'http://www.ups.com/XMLSchema/XOLTWS/Void/v1.1') do |void_shipment_node|
                void_shipment_node << XmlNode.new('ShipmentIdentificationNumber', shipment_identification_number)
                void_shipment_node << XmlNode.new('TrackingNumber', options[:tracking_number]) if options[:tracking_number]
              end
            end
          end
        end
        xml_request.to_s
      end

      def build_address_validation_city_request(address, options={})
        xml_request = XmlNode.new('AddressValidationRequest') do |root_node|
          root_node << XmlNode.new('Request') do |request_node|
            request_node << XmlNode.new('RequestAction', 'AV')
          end
          #Note that AV request contains only City, StateProvinceCode, CountryCode and PostalCode fields
          root_node << XmlNode.new('Address') do |address_node|
            address_node << XmlNode.new('City', address.city) unless address.city.blank?
            address_node << XmlNode.new('StateProvinceCode', address.state) unless address.state.blank?
            address_node << XmlNode.new('CountryCode', address.country_code) unless address.country_code.blank?
            address_node << XmlNode.new('PostalCode', address.postal_code) unless address.postal_code.blank?
          end
        end
        xml_request.to_s
      end

      def build_address_validation_street_request(address, options={})
        xml_request = XmlNode.new('envr:Envelope', 'xmlns:auth' => 'http://www.ups.com/schema/xpci/1.0/auth', 
          'xmlns:upss' => 'http://www.ups.com/XMLSchema/XOLTWS/UPSS/v1.0', 'xmlns:envr' => 'http://schemas.xmlsoap.org/soap/envelope/',
          'xmlns:xsd' => 'http://www.w3.org/2001/XMLSchema', 'xmlns:common' => 'http://www.ups.com/XMLSchema/XOLTWS/Common/v1.0',
          'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance', 'xmlns:wsf' => 'http://www.ups.com/schema/wsf') do |env_node|
          env_node << XmlNode.new('envr:Header') do |h_node|
            h_node << build_ws_access_request
          end
          env_node << XmlNode.new('envr:Body') do |body_node| 
            body_node << build_address_validation_street_request_body(address, options)
          end
        end
        xml_request.to_s
      end  

      def build_address_validation_street_request_body(address, options = {})
        xml_request = XmlNode.new('XAVRequest', {'xmlns'=>'http://www.ups.com/XMLSchema/XOLTWS/xav/v1.0', 'xmlns:xsd' => 'http://www.w3.org/2001/XMLSchema', 'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance', 'xmlns:common'=>'http://www.ups.com/XMLSchema/XOLTWS/Common/v1.0'}) do |root_node|
          root_node << XmlNode.new('Request', 'xmlns' => 'http://www.ups.com/XMLSchema/XOLTWS/Common/v1.0') do |request_node|
            request_node << XmlNode.new('RequestOption', '3')
          end

          root_node << XmlNode.new('AddressKeyFormat') do |address_key_node|
            address_key_node << XmlNode.new('AddressLine', address.address1) unless address.address1.blank?
            address_key_node << XmlNode.new('PoliticalDivision2', address.city) unless address.city.blank?
            address_key_node << XmlNode.new('PoliticalDivision1', address.state) unless address.state.blank?          
            address_key_node << XmlNode.new('PostcodePrimaryLow', address.postal_code) unless address.postal_code.blank?
            #address_key_node << XmlNode.new('PostcodeExtendedLow', options[:extended_postal_code]) unless options[:extended_postal_code]
            address_key_node << XmlNode.new('CountryCode', address.country_code(:alpha2)) unless address.country.blank?
          end
        end
      end

      def build_courier_dispatch_request( pickup_location, close_time, ready_time, pickup_date, service_code, quantity, dest_country_code, container_code, total_weight, weight_units, residential=nil)
        xml_request = XmlNode.new('envr:Envelope', 'xmlns:auth' => 'http://www.ups.com/schema/xpci/1.0/auth', 
          'xmlns:upss' => 'http://www.ups.com/XMLSchema/XOLTWS/UPSS/v1.0', 'xmlns:envr' => 'http://schemas.xmlsoap.org/soap/envelope/',
          'xmlns:xsd' => 'http://www.w3.org/2001/XMLSchema', 'xmlns:common' => 'http://www.ups.com/XMLSchema/XOLTWS/Common/v1.0',
          'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance', 'xmlns:wsf' => 'http://www.ups.com/schema/wsf') do |env_node|
          env_node << XmlNode.new('envr:Header') do |h_node|
            h_node << build_ws_access_request
          end
          env_node << XmlNode.new('envr:Body') do |body_node| 
            body_node << build_courier_dispatch_request_old(pickup_location, close_time, ready_time, pickup_date, service_code, quantity, dest_country_code, container_code, total_weight, weight_units, residential)
          end
        end
        xml_request.to_s
      end

      def build_courier_dispatch_cancel_request prn, options = {}
        xml_request = XmlNode.new('envr:Envelope', 'xmlns:auth' => 'http://www.ups.com/schema/xpci/1.0/auth', 
          'xmlns:upss' => 'http://www.ups.com/XMLSchema/XOLTWS/UPSS/v1.0', 'xmlns:envr' => 'http://schemas.xmlsoap.org/soap/envelope/',
          'xmlns:xsd' => 'http://www.w3.org/2001/XMLSchema', 'xmlns:common' => 'http://www.ups.com/XMLSchema/XOLTWS/Common/v1.0',
          'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance', 'xmlns:wsf' => 'http://www.ups.com/schema/wsf') do |env_node|
          env_node << XmlNode.new('envr:Header') do |h_node|
            h_node << build_ws_access_request
          end
          env_node << XmlNode.new('envr:Body') do |body_node| 
            body_node << XmlNode.new('PickupCancelRequest', {'xmlns'=>'http://www.ups.com/XMLSchema/XOLTWS/Pickup/v1.1', 'xmlns:xsd' => 'http://www.w3.org/2001/XMLSchema', 'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance', 'xmlns:common'=>'http://www.ups.com/XMLSchema/XOLTWS/Common/v1.0'}) do |pickup_cancel_request_node|
              pickup_cancel_request_node << XmlNode.new('common:Request', 'xmlns' => 'http://www.ups.com/XMLSchema/XOLTWS/Common/v1.0')
              pickup_cancel_request_node << XmlNode.new('CancelBy', '02', {'xmlns'=>'http://www.ups.com/XMLSchema/XOLTWS/Pickup/v1.1', 'xmlns:xsd' => 'http://www.w3.org/2001/XMLSchema', 'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance', 'xmlns:common'=>'http://www.ups.com/XMLSchema/XOLTWS/Common/v1.0'})
              pickup_cancel_request_node << XmlNode.new('PRN', prn)
            end
          end
        end
        xml_request.to_s
      end

      def build_shipping_request(shipper, shipper_location, ship_to_person, ship_to_location, ship_from_person, ship_from_location, package_item, options={})
        xml_request = XmlNode.new('envr:Envelope', 'xmlns:auth' => 'http://www.ups.com/schema/xpci/1.0/auth', 
          'xmlns:upss' => 'http://www.ups.com/XMLSchema/XOLTWS/UPSS/v1.0', 'xmlns:envr' => 'http://schemas.xmlsoap.org/soap/envelope/',
          'xmlns:xsd' => 'http://www.w3.org/2001/XMLSchema', 'xmlns:common' => 'http://www.ups.com/XMLSchema/XOLTWS/Common/v1.0',
          'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance', 'xmlns:wsf' => 'http://www.ups.com/schema/wsf') do |env_node|
          env_node << XmlNode.new('envr:Header') do |h_node|
            h_node << build_ws_access_request
          end
          env_node << XmlNode.new('envr:Body') do |body_node| 
            body_node << build_shipping_request_body(shipper, shipper_location, ship_to_person, ship_to_location, ship_from_person, ship_from_location, package_item, options)
          end
        end
        xml_request.to_s
      end

      def build_shipping_request_body(shipper, shipper_location, ship_to_person, ship_to_location, ship_from_person, ship_from_location, package_item, options={})
        xml_request = XmlNode.new('ShipmentRequest',{'xmlns'=>'http://www.ups.com/XMLSchema/XOLTWS/Ship/v1.0', 'xmlns:xsd' => 'http://www.w3.org/2001/XMLSchema', 'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance', 'xmlns:common'=>'http://www.ups.com/XMLSchema/XOLTWS/Common/v1.0'}) do |root_node|
          #Request node

          root_node << XmlNode.new('Request', 'xmlns' => 'http://www.ups.com/XMLSchema/XOLTWS/Common/v1.0') do |request_node|
            request_node << XmlNode.new('RequestOption', 'nonvalidate')
            if options[:transaction_reference_id]
              request_node << XmlNode.new('TransactionReference') do |tr_ref_node|
                tr_ref_node << XmlNode.new('TransactionIdentifier', options[:transaction_reference_id])
              end
            end
          end #End Request node

          #Shipment node
          root_node << XmlNode.new('Shipment', 'xmlns' => 'http://www.ups.com/XMLSchema/XOLTWS/Ship/v1.0') do |shipment_node|
            #Description node required if all of the listed conditions below are true:
            #1. ShipFrom and ShipTo countries are not the same;
            #2. The packaging type is not UPS Letter;
            #3. The ShipFrom and or ShipTo countries are not in the European Union or 
            # the ShipFrom and ShipTo countries are both in the European Union and the shipments service type 
            # is not UPS Standard.
            # WARNING! Not implemented yet
            shipment_node << XmlNode.new('Description', package_item[:item_description]) if package_item[:item_description]
            shipment_node << build_ship_param_node('Shipper', shipper, shipper_location) 
            shipment_node << build_ship_param_node('ShipTo', ship_to_person, ship_to_location)
            shipment_node << build_ship_param_node('ShipFrom', ship_from_person, ship_from_location)

            #PaymentInformation node
            shipment_node << XmlNode.new('PaymentInformation') do |payment_node|
              payment_node << XmlNode.new('ShipmentCharge') do |shipment_charge_node|
                shipment_charge_node << XmlNode.new('Type', '01')
                shipment_charge_node << XmlNode.new('BillShipper') do |bill_shipper_node|

                  bill_shipper_node << XmlNode.new('AccountNumber', shipper[:shipper_number]) 
                  #if options[:bill_shipper_account_number]
                  # if options[:credit_card] 
                  #   bill_shipper_node << XmlNode.new('CreditCard') do |credit_card_node|
                  #     cc_type = CREDIT_CARD_TYPES.invert[options[:credit_card_type]]
                  #     credit_card_node << XmlNode.new('Type', cc_type)
                  #     credit_card_node << XmlNode.new('Number', options[:credit_card_number])
                  #     credit_card_node << XmlNode.new('ExpirationDate', options[:credit_card_expiration_date])
                  #     credit_card_node << XmlNode.new('SecurityCode', options[:credit_card_security_code])
                  #     credit_card_node << build_address_node(options[:credit_card_address])
                  #   end
                  # end
                end

              end
            end #End PaymentInformation node
            
            #Service node
            shipment_node << XmlNode.new('Service') do |service_node|
              service_node << XmlNode.new('Code', options[:service_code] || '01')
              service_node << XmlNode.new('Description', DEFAULT_SERVICES[options[:service_code]] || DEFAULT_SERVICES['01'])
            end #End Service node

            #Package node
            shipment_node << XmlNode.new('Package') do |package_node|
              #Required for shipment with return service
              package_node << XmlNode.new('Description', package_item[:item_description]) if package_item[:item_description]              
              package_node << XmlNode.new('Packaging') do |packaging_node|
                packaging_node << XmlNode.new('Code', options[:packaging_type] || '02')
              end
              package_node << XmlNode.new('PackageWeight') do |package_weight_node|
                package_weight_node << XmlNode.new('UnitOfMeasurement') do |unit_of_measurement_node|
                  unit_of_measurement_node << XmlNode.new('Code', package_item[:weight_units] || 'LBS')
                end
                package_weight_node << XmlNode.new('Weight', package_item[:weight_value])
              end
            end #End Package node

            shipment_node << XmlNode.new('PackageServiceOptions') do |package_service_options_node|
              package_service_options_node << XmlNode.new('DeclaredValue') do |declared_value_node|
                declared_value_node << XmlNode.new('CurrencyCode', package_item[:currency_code] || 'USD')
                declared_value_node << XmlNode.new('MonetaryValue', package_item[:declared_value] || '100')
              end
            end
          end #End Shipment node

          #LabelSpecification node
          root_node << XmlNode.new('LabelSpecification', 'xmlns' => 'http://www.ups.com/XMLSchema/XOLTWS/Ship/v1.0') do |label_specification_node|
            label_specification_node << XmlNode.new('LabelImageFormat') do | label_image_format_node |
              label_image_format_node << XmlNode.new('Code', 'GIF')
            end
          end
        end
        xml_request
      end
      
      def build_courier_dispatch_request_old(pickup_location, close_time, ready_time, pickup_date, service_code, quantity, dest_country_code, container_code, total_weight, weight_units, residential=nil)
        xml_request = XmlNode.new('PickupCreationRequest', {'xmlns'=>'http://www.ups.com/XMLSchema/XOLTWS/Pickup/v1.1', 'xmlns:xsd' => 'http://www.w3.org/2001/XMLSchema', 'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance', 'xmlns:common'=>'http://www.ups.com/XMLSchema/XOLTWS/Common/v1.0'}) do |root_node|
          root_node << XmlNode.new('common:Request', 'xmlns' => 'http://www.ups.com/XMLSchema/XOLTWS/Common/v1.0')

          root_node << XmlNode.new('RatePickupIndicator', 'Y')

          root_node << XmlNode.new('Shipper', 'xmlns' => 'http://www.ups.com/XMLSchema/XOLTWS/Pickup/v1.1') do |shipper_node|
            shipper_node << XmlNode.new('Account') do |account_node|
              build_nodes_from_hash(account_node, {:account_number => @options[:account_number] , :account_country_code => @options[:account_country_code]}) 
            end
          end

          root_node << XmlNode.new('PickupDateInfo', 'xmlns' => 'http://www.ups.com/XMLSchema/XOLTWS/Pickup/v1.1') do |date_node|
            date_node << XmlNode.new('CloseTime', close_time.strftime('%H%M'))
            date_node << XmlNode.new('ReadyTime', ready_time.strftime('%H%M'))
            date_node << XmlNode.new('PickupDate', pickup_date.strftime('%Y%m%d'))
          end

          root_node << XmlNode.new('PickupAddress', 'xmlns' => 'http://www.ups.com/XMLSchema/XOLTWS/Pickup/v1.1') do |address_node|
            address_node << XmlNode.new('CompanyName', pickup_location.company_name) if pickup_location.company_name != nil
            address_node << XmlNode.new('ContactName', pickup_location.name) if pickup_location.name != nil
            address_node << XmlNode.new('AddressLine', pickup_location.address1) # only one address line allowed
            address_node << XmlNode.new('City', pickup_location.city)
            address_node << XmlNode.new('StateProvince', pickup_location.province)
            address_node << XmlNode.new('PostalCode', pickup_location.postal_code)
            address_node << XmlNode.new('CountryCode', pickup_location.country_code(:alpha2))
            address_node << XmlNode.new('ResidentialIndicator', residential || 'Y')
            address_node << XmlNode.new('Phone') do |phone_node|
              phone_node << XmlNode.new('Number', pickup_location.phone)
            end
          end
          root_node << XmlNode.new('AlternateAddressIndicator', 'Y')

          root_node << XmlNode.new('PickupPiece', 'xmlns' => 'http://www.ups.com/XMLSchema/XOLTWS/Pickup/v1.1') do |piece_node|
            piece_node << XmlNode.new('ServiceCode', service_code)
            piece_node << XmlNode.new('Quantity', quantity)
            piece_node << XmlNode.new('DestinationCountryCode', dest_country_code)
            piece_node << XmlNode.new('ContainerCode', container_code)
          end

          root_node << XmlNode.new('TotalWeight', 'xmlns' => 'http://www.ups.com/XMLSchema/XOLTWS/Pickup/v1.1') do |weight_node|
            weight_node << XmlNode.new('Weight', total_weight)
            weight_node << XmlNode.new('UnitOfMeasurement', weight_units)
          end

          root_node << XmlNode.new('OverweightIndicator', 'N', 'xmlns' => 'http://www.ups.com/XMLSchema/XOLTWS/Pickup/v1.1')
          root_node << XmlNode.new('PaymentMethod', '01', 'xmlns' => 'http://www.ups.com/XMLSchema/XOLTWS/Pickup/v1.1')
        end
        xml_request
      end

      def build_nodes_from_hash(main_node, hash) 
        hash.keys.each do |k|
          node_name = k.to_s.split('_').map { |w| w.capitalize }.join
          main_node << XmlNode.new(node_name, hash[k])
        end
      end

      def upsified_location(location)
        if location.country_code == 'US' && US_TERRITORIES_TREATED_AS_COUNTRIES.include?(location.state)
          atts = {:country => location.state}
          [:zip, :city, :address1, :address2, :address3, :phone, :fax, :address_type].each do |att|
            atts[att] = location.send(att)
          end
          Location.new(atts)
        else
          location
        end
      end
      
      def build_access_request
        xml_request = XmlNode.new('AccessRequest') do |access_request|
          access_request << XmlNode.new('AccessLicenseNumber', @options[:key])
          access_request << XmlNode.new('UserId', @options[:login])
          access_request << XmlNode.new('Password', @options[:password])
        end
        xml_request.to_s
      end
      
      def build_ws_access_request
        xml_request = XmlNode.new('upss:UPSSecurity') do |s_node|
          s_node << XmlNode.new('upss:UsernameToken') do |ut_node|
            ut_node << XmlNode.new('upss:Username', @options[:login])
            ut_node << XmlNode.new('upss:Password', @options[:password])
          end
          s_node << XmlNode.new('upss:ServiceAccessToken') do |sat_node|
            sat_node << XmlNode.new('upss:AccessLicenseNumber', @options[:key])
          end
        end
      end

      def build_rate_request(origin, destination, packages, options={})
        packages = Array(packages)
        xml_request = XmlNode.new('RatingServiceSelectionRequest') do |root_node|
          root_node << XmlNode.new('Request') do |request|
            request << XmlNode.new('RequestAction', 'Rate')
            request << XmlNode.new('RequestOption', 'Shop')
            # not implemented: 'Rate' RequestOption to specify a single service query
            # request << XmlNode.new('RequestOption', ((options[:service].nil? or options[:service] == :all) ? 'Shop' : 'Rate'))
          end
          
          # pickup_type = options[:pickup_type] || :on_call_air
          
          # root_node << XmlNode.new('PickupType') do |pickup_type_node|
          #   pickup_type_node << XmlNode.new('Code', PICKUP_CODES[pickup_type]) 
          #   # not implemented: PickupType/PickupDetails element
          # end
          # cc = options[:customer_classification] || DEFAULT_CUSTOMER_CLASSIFICATIONS[pickup_type]
          # root_node << XmlNode.new('CustomerClassification') do |cc_node|
          #   cc_node << XmlNode.new('Code', CUSTOMER_CLASSIFICATIONS[cc])
          # end
          
          root_node << XmlNode.new('Shipment') do |shipment|
            # not implemented: Shipment/Description element
            shipment << build_location_node('Shipper', (options[:shipper] || origin), options)
            shipment << build_location_node('ShipTo', destination, options)
            if options[:shipper] and options[:shipper] != origin
              shipment << build_location_node('ShipFrom', origin, options)
            end
            
            # not implemented:  * Shipment/ShipmentWeight element
            #                   * Shipment/ReferenceNumber element                    
            #                   * Shipment/Service element                            
            #                   * Shipment/PickupDate element                         
            #                   * Shipment/ScheduledDeliveryDate element              
            #                   * Shipment/ScheduledDeliveryTime element              
            #                   * Shipment/AlternateDeliveryTime element              
            #                   * Shipment/DocumentsOnly element                      
            
            packages.each do |package|
              #Metric system detection depends on country for UPS
              imperial = ['US','LR','MM'].include?(origin.country_code(:alpha2))
              #imperial = package.options[:units] == :imperial
              shipment << XmlNode.new("Package") do |package_node|
                
                # not implemented: * Shipment/Package/Description element
                
                pack_type = if !!options[:packaging_type] 
                  options[:packaging_type].to_s.casecmp('Envelope') == 0 ? 'UPS Letter' : 'Package'
                else 
                   'Package'
                end

                pack_code = PACKAGING_TYPES.invert[pack_type]
                package_node << XmlNode.new("PackagingType") do |packaging_type|
                  packaging_type << XmlNode.new("Code", pack_code)
                end
                
                if pack_code != '01' #Add dimensions only for package, not for Letter/Envelope
                  package_node << XmlNode.new("Dimensions") do |dimensions|
                    dimensions << XmlNode.new("UnitOfMeasurement") do |units|
                      units << XmlNode.new("Code", imperial ? 'IN' : 'CM')
                    end
                    [:length,:width,:height].each do |axis|
                      value = ((imperial ? package.inches(axis) : package.cm(axis)).to_f*1000).round/1000.0 # 3 decimals
                      dimensions << XmlNode.new(axis.to_s.capitalize, [value,0.1].max)
                    end
                  end
                end

                package_node << XmlNode.new("PackageWeight") do |package_weight|
                  package_weight << XmlNode.new("UnitOfMeasurement") do |units|
                    units << XmlNode.new("Code", imperial ? 'LBS' : 'KGS')
                  end
                  
                  value = ((imperial ? package.lbs : package.kgs).to_f*1000).round/1000.0 # 3 decimals
                  package_weight << XmlNode.new("Weight", [value,0.1].max)
                end
              
                # not implemented:  * Shipment/Package/LargePackageIndicator element
                #                   * Shipment/Package/ReferenceNumber element
                #                   * Shipment/Package/PackageServiceOptions element
                #                   * Shipment/Package/AdditionalHandling element  
              end
              
            end
            
            # not implemented:  * Shipment/ShipmentServiceOptions element
            #                   * Shipment/RateInformation element
            
          end
          
        end
        xml_request.to_s
      end
      
      def build_tracking_request(tracking_number, options={})
        xml_request = XmlNode.new('TrackRequest') do |root_node|
          root_node << XmlNode.new('Request') do |request|
            request << XmlNode.new('RequestAction', 'Track')
            request << XmlNode.new('RequestOption', '1')
          end
          root_node << XmlNode.new('TrackingNumber', tracking_number.to_s)
        end
        xml_request.to_s
      end

      # [Shipper, ShipTo, ShipFrom] nodes
      def build_ship_param_node(node_name, person, location, options={})
        node = XmlNode.new(node_name) do |node|
          node << XmlNode.new('Name', person[:person_name])
          if person[:phone_number]
            node << XmlNode.new('Phone') do |phone|
              phone << XmlNode.new('Number', person[:phone_number].gsub(/[^\d]/, ''))
              phone << XmlNode.new('Extension', person[:phone_number_ext].gsub(/[^\d]/, '')) if person[:phone_number_ext]
            end
          end
          node << XmlNode.new('ShipperNumber', person[:shipper_number]) if node_name == 'Shipper' and person[:shipper_number]
          node << XmlNode.new('FaxNumber', person[:shipper_fax_number]) if node_name == 'Shipper' and person[:shipper_fax_number]
          node << XmlNode.new('EMailAddress', person[:email]) if person[:email]
          node << build_address_node(location)

        end  
      end

      def build_address_node(location, opts = {})
        node = XmlNode.new('Address') do |address_node|
          address_node << XmlNode.new('AddressLine', location.address1) unless location.address1.blank?
          address_node << XmlNode.new('AddressLine', location.address2) unless location.address2.blank?
          address_node << XmlNode.new('AddressLine', location.address3) unless location.address3.blank?
          address_node << XmlNode.new('City', location.city) unless location.city.blank?
          #Required if shipper is in the US or CA. If Shipper country is US or CA, then the value must be a valid
          #US State/ Canadian Province code. If the country is Ireland, the StateProvinceCode will contain the county.
          address_node << XmlNode.new('StateProvinceCode', location.province) unless location.province.blank?
          address_node << XmlNode.new('PostalCode', location.postal_code) unless location.postal_code.blank?
          address_node << XmlNode.new('CountryCode', location.country_code(:alpha2)) unless location.country_code(:alpha2).blank?
          address_node << XmlNode.new("ResidentialAddressIndicator", true) if location.residential?
        end
      end
      
      def build_location_node(name,location,options={})
        # not implemented:  * Shipment/Shipper/Name element
        #                   * Shipment/(ShipTo|ShipFrom)/CompanyName element
        #                   * Shipment/(Shipper|ShipTo|ShipFrom)/AttentionName element
        #                   * Shipment/(Shipper|ShipTo|ShipFrom)/TaxIdentificationNumber element
        location_node = XmlNode.new(name) do |location_node|
          location_node << XmlNode.new('PhoneNumber', location.phone.gsub(/[^\d]/,'')) unless location.phone.blank?
          location_node << XmlNode.new('FaxNumber', location.fax.gsub(/[^\d]/,'')) unless location.fax.blank?
          
          if name == 'Shipper' and (origin_account = @options[:origin_account] || options[:origin_account])
            location_node << XmlNode.new('ShipperNumber', origin_account)
          elsif name == 'ShipTo' and (destination_account = @options[:destination_account] || options[:destination_account])
            location_node << XmlNode.new('ShipperAssignedIdentificationNumber', destination_account)
          end
          
          location_node << XmlNode.new('Address') do |address|
            address << XmlNode.new("AddressLine1", location.address1) unless location.address1.blank?
            address << XmlNode.new("AddressLine2", location.address2) unless location.address2.blank?
            address << XmlNode.new("AddressLine3", location.address3) unless location.address3.blank?
            address << XmlNode.new("City", location.city) unless location.city.blank?
            address << XmlNode.new("StateProvinceCode", location.province) if (!location.province.blank? && location.province.length == 2)
              # StateProvinceCode required for negotiated rates but not otherwise, for some reason
            address << XmlNode.new("PostalCode", location.postal_code) unless location.postal_code.blank?
            address << XmlNode.new("CountryCode", location.country_code(:alpha2)) unless location.country_code(:alpha2).blank?
            address << XmlNode.new("ResidentialAddressIndicator", true) unless location.commercial? # the default should be that UPS returns residential rates for destinations that it doesn't know about
            # not implemented: Shipment/(Shipper|ShipTo|ShipFrom)/Address/ResidentialAddressIndicator element
          end
        end
      end

      def parse_shipping_response(response, options={})
        xml = REXML::Document.new(response)
        root_node = xml.elements['Envelope']
        success = response_success?(xml)
        message = response_message(xml)
        shipment_result = nil

        if success
          shipment_result_node = xml.elements['/Envelope/Body/ShipmentResponse/ShipmentResults']
          shipment_charges_node = shipment_result_node.elements['ShipmentCharges']

          transportation_charges = Charge.new(shipment_charges_node.get_text('TransportationCharges/CurrencyCode'), shipment_charges_node.get_text('TransportationCharges/MonetaryValue'))
          service_options_charges = Charge.new(shipment_charges_node.get_text('ServiceOptionsCharges/CurrencyCode'), shipment_charges_node.get_text('ServiceOptionsCharges/MonetaryValue'))
          total_charges = Charge.new(shipment_charges_node.get_text('TotalCharges/CurrencyCode'), shipment_charges_node.get_text('TotalCharges/MonetaryValue'))
          shipment_charges = ShipmentCharges.new(transportation_charges, service_options_charges, total_charges)         
          
          billing_weight_uom = UnitOfMeasurement.new(shipment_result_node.get_text('BillingWeight/UnitOfMeasurement/Code'), shipment_result_node.get_text('BillingWeight/UnitOfMeasurement/Description'))
          billing_weight = BillingWeight.new(billing_weight_uom, shipment_result_node.get_text('BillingWeight/Weight'))
          
          shipment_identification_number = shipment_result_node.get_text('ShipmentIdentificationNumber')

          tracking_number = shipment_result_node.get_text('PackageResults/TrackingNumber')
          service_options_charges_pr = Charge.new(shipment_result_node.get_text('PackageResults/ServiceOptionsCharges/CurrencyCode'), shipment_result_node.get_text('PackageResults/ServiceOptionsCharges/MonetaryValue'))
          
          shipping_label = ShippingLabel.new(shipment_result_node.get_text('PackageResults/ShippingLabel/ImageFormat/Code'), shipment_result_node.get_text('PackageResults/ShippingLabel/GraphicImage'), shipment_result_node.get_text('PackageResults/ShippingLabel/HTMLImage'))

          package_results = PackageResult.new(tracking_number, service_options_charges_pr, shipping_label)

          shipment_result = ShipmentResult.new(shipment_charges, billing_weight, shipment_identification_number, package_results)

        end

        resp = ShippingResponse.new(success, message, Hash.from_xml(response),
          :carrier => @@name,
          :xml => response,
          :request => last_request,
          :shipment_details => shipment_result 
        )
        resp
      end

      def parse_courier_dispatch_response(response, options)
        xml = REXML::Document.new(response)
        root_node = xml.elements['/Envelope/Body/PickupCreationResponse']
        success = response_success?(xml)
        message = response_message(xml)
        if success
          prn = root_node.get_text('PRN').to_s
          params = {:dispatch_confirmation_number => prn}
          rate_status_node = root_node.elements['RateStatus']
          if rate_status_node && rate_status_node.get_text('Code') == '01'
            grand_of_all_charge = root_node.get_text('RateResult/GrandTotalOfAllCharge').to_s.to_f
            currency = root_node.get_text('RateResult/CurrencyCode').to_s
            charge = Charge.new(currency, grand_of_all_charge)
            params[:total_charge] = charge
          end
        else
          params = {:code => response_status_node(xml).get_text('Code'), :message => message}
        end
        p params
        Response.new(success, message, params)
      end

      def parse_courier_dispatch_cancel_response(response, options)
        xml = REXML::Document.new(response)
        root_node = xml.elements['/Envelope/Body/PickupCancelResponse']
        success = response_success?(xml)
        message = response_message(xml)
        Response.new(success, message)
      end

      def parse_cancel_shipment_response response, options = {}
        xml = REXML::Document.new(response)
        root_node = xml.elements['Envelope']
        success = response_success?(xml)
        message = response_message(xml)
        status, transaction_reference, summary_result = nil, nil, nil
        if success
           cancel_response_status_node = xml.elements['/Envelope/Body/VoidShipmentResponse/Response']
           status = Status.new(cancel_response_status_node.get_text('ResponseStatus/Code'), cancel_response_status_node.get_text('ResponseStatus/Description'))
           transaction_reference = TransactionReference.new(cancel_response_status_node.get_text('TransactionReference/CustomerContext'), cancel_response_status_node.get_text('TransactionReference/TransactionIdentifier'))
           summary_result = Status.new(xml.get_text('/Envelope/Body/VoidShipmentResponse/SummaryResult/Status/Code'), xml.get_text('/Envelope/Body/VoidShipmentResponse/SummaryResult/Status/Description'))
        end

         resp = VoidShippingResponse.new(success, message, status, transaction_reference, summary_result)
         resp
      end

      def parse_address_city_validation_response response, options={}
        xml = REXML::Document.new(response)
        success = response_success?(xml)
        message = response_message(xml)
        address_validation_result = nil
        if success
          address_validation_result = AddressValidationResponse.new(success, nil, nil, message, nil, nil, nil)
        else
          error_node = xml.elements['/AddressValidationResponse/Response/Error']
          error = Error.new(error_node.get_text('ErrorCode'), error_node.get_text('ErrorSeverity'), error_node.get_text('ErrorDescription'))
          p error
          address_validation_result = AddressValidationResponse.new(success, nil, nil, message, nil, error, nil)
        end
        address_validation_result
      end

      def parse_address_street_validation_response(response, parsed_city_response, options)
        p '==============Street'
        p response
        xml = REXML::Document.new(response)
        success = response_success?(xml)
        message = response_message(xml)
        parsed_city_response.street_level_status = success
        parsed_city_response.valid_address = xml.elements['/Envelope/Body/XAVResponse/ValidAddressIndicator'] != nil
        
        if success
          type = parse_address_type(xml.elements['/Envelope/Body/XAVResponse/AddressClassification']) if xml.elements['/Envelope/Body/XAVResponse/AddressClassification']
          
          parsed_city_response.type = type
          candidates = []
          xml.elements.each('/Envelope/Body/XAVResponse/Candidate') do |candidate_node|
            ca_type = parse_address_type(candidate_node.elements['AddressClassification'])
            location = Location.new(
              :address1 => candidate_node.get_text('AddressKeyFormat/AddressLine'),
              :city => candidate_node.get_text('AddressKeyFormat/PoliticalDivision2 '),
              :state => candidate_node.get_text('AddressKeyFormat/PoliticalDivision1'),
              :postal_code => candidate_node.get_text('AddressKeyFormat/PostcodePrimaryLow'),
            )
            address_candidate = AddressCandidate.new(ca_type, location)
            candidates.push(address_candidate)
          end
        parsed_city_response.candidates = candidates  
        end
        parsed_city_response.status = parsed_city_response.city_level_status && parsed_city_response.street_level_status 
      
        parsed_city_response
      end

      def parse_address_type(node, options={})
        address_type = AddressType.new(node.get_text('Code'), node.get_text('Description'))   
        address_type
      end

      def parse_rate_response(origin, destination, packages, response, options={})
        rates = []
        
        xml = REXML::Document.new(response)
        success = response_success?(xml)
        message = response_message(xml)
        
        if success
          rate_estimates = []
          
          xml.elements.each('/*/RatedShipment') do |rated_shipment|
            service_code = rated_shipment.get_text('Service/Code').to_s
            days_to_delivery = rated_shipment.get_text('GuaranteedDaysToDelivery').to_s.to_i
            days_to_delivery = nil if days_to_delivery == 0
            
            surcharges = {}
            
            ['TransportationCharges', 'ServiceOptionsCharges', 'TotalCharges'].each do |name| 
              surcharge =  RateEstimate::Surcharge.new(
                name,
                name,
                rated_shipment.get_text("#{name}/CurrencyCode").to_s,
                rated_shipment.get_text("#{name}/MonetaryValue").to_s,
              )
              surcharges.merge!({name => surcharge})
            end
            service_name = service_name_for(origin, service_code)
            
            rate_estimates << RateEstimate.new(origin, destination, @@name,
                                service_name,
                                :total_price => rated_shipment.get_text('TotalCharges/MonetaryValue').to_s.to_f,
                                :currency => rated_shipment.get_text('TotalCharges/CurrencyCode').to_s,
                                :service_code => service_name.upcase.gsub(/ /, '_'),
                                :packages => packages,
                                :delivery_range => [timestamp_from_business_day(days_to_delivery)],
                                :surcharges => surcharges)
          end
        end
        RateResponse.new(success, message, Hash.from_xml(response).values.first, :rates => rate_estimates, :xml => response, :request => last_request)
      end
      
      def parse_tracking_response(response, options={})
        xml = REXML::Document.new(response)
        success = response_success?(xml)
        message = response_message(xml)
        
        if success
          tracking_number, origin, destination, status_code, status_description, scheduled_delivery_date = nil
          delivered, exception = false
          exception_event = nil
          shipment_events = []
          status = {}

          first_shipment = xml.elements['/*/Shipment']
          first_package = first_shipment.elements['Package']
          tracking_number = first_shipment.get_text('ShipmentIdentificationNumber | Package/TrackingNumber').to_s
          
          # Build status hash
          status_node = first_package.elements['Activity/Status/StatusType']
          status_code = status_node.get_text('Code').to_s
          status_description = status_node.get_text('Description').to_s
          status = TRACKING_STATUS_CODES[status_code]

          if status_description =~ /out.*delivery/i
            status = :out_for_delivery
          end

          origin, destination = %w{Shipper ShipTo}.map do |location|
            location_from_address_node(first_shipment.elements["#{location}/Address"])
          end

          # Get scheduled delivery date
          unless status == :delivered
            scheduled_delivery_date = parse_ups_datetime({
              :date => first_shipment.get_text('ScheduledDeliveryDate'),
              :time => nil
              })
          end

          activities = first_package.get_elements('Activity')
          unless activities.empty?
            shipment_events = activities.map do |activity|
              description = activity.get_text('Status/StatusType/Description').to_s
              zoneless_time = if (time = activity.get_text('Time')) &&
                                 (date = activity.get_text('Date'))
                time, date = time.to_s, date.to_s
                hour, minute, second = time.scan(/\d{2}/)
                year, month, day = date[0..3], date[4..5], date[6..7]
                Time.utc(year, month, day, hour, minute, second)
              end
              location = location_from_address_node(activity.elements['ActivityLocation/Address'])
              ShipmentEvent.new(description, zoneless_time, location)
            end
            
            shipment_events = shipment_events.sort_by(&:time)
            
            # UPS will sometimes archive a shipment, stripping all shipment activity except for the delivery 
            # event (see test/fixtures/xml/delivered_shipment_without_events_tracking_response.xml for an example).
            # This adds an origin event to the shipment activity in such cases.
            if origin && !(shipment_events.count == 1 && status == :delivered)
              first_event = shipment_events[0]
              same_country = origin.country_code(:alpha2) == first_event.location.country_code(:alpha2)
              same_or_blank_city = first_event.location.city.blank? or first_event.location.city == origin.city
              origin_event = ShipmentEvent.new(first_event.name, first_event.time, origin)
              if same_country and same_or_blank_city
                shipment_events[0] = origin_event
              else
                shipment_events.unshift(origin_event)
              end
            end

            # Has the shipment been delivered?
            if status == :delivered
              if !destination
                destination = shipment_events[-1].location
              end
              shipment_events[-1] = ShipmentEvent.new(shipment_events.last.name, shipment_events.last.time, destination)
            end
          end
          
        end
        TrackingResponse.new(success, message, Hash.from_xml(response).values.first,
          :carrier => @@name,
          :xml => response,
          :request => last_request,
          :status => status,
          :status_code => status_code,
          :status_description => status_description,
          :scheduled_delivery_date => scheduled_delivery_date,
          :shipment_events => shipment_events,
          :delivered => delivered,
          :exception => exception,
          :exception_event => exception_event,
          :origin => origin,
          :destination => destination,
          :tracking_number => tracking_number)
      end
      
      def location_from_address_node(address)
        return nil unless address
        Location.new(
                :country =>     node_text_or_nil(address.elements['CountryCode']),
                :postal_code => node_text_or_nil(address.elements['PostalCode']),
                :province =>    node_text_or_nil(address.elements['StateProvinceCode']),
                :city =>        node_text_or_nil(address.elements['City']),
                :address1 =>    node_text_or_nil(address.elements['AddressLine1']),
                :address2 =>    node_text_or_nil(address.elements['AddressLine2']),
                :address3 =>    node_text_or_nil(address.elements['AddressLine3'])
              )
      end
      
      def parse_ups_datetime(options = {})
        time, date = options[:time].to_s, options[:date].to_s
        if time.nil?
          hour, minute, second = 0
        else
          hour, minute, second = time.scan(/\d{2}/)
        end
        year, month, day = date[0..3], date[4..5], date[6..7]

        Time.utc(year, month, day, hour, minute, second)
      end

      def response_success?(xml)
        xml.get_text('/*/Response/ResponseStatusCode | */*/*/Response/ResponseStatus/Code').to_s == '1'
      end
      
      def response_message(xml)
        xml.get_text('/*/Response/Error/ErrorDescription | /*/Response/ResponseStatusDescription | */*/*/Response/ResponseStatus/Description').to_s
      end
      
      def commit(action, request, test = false)
        p "#{test ? TEST_URL : LIVE_URL}/#{RESOURCES[action]}"
        ssl_post("#{test ? TEST_URL : LIVE_URL}/#{RESOURCES[action]}", request)
      end
      
      def service_name_for(origin, code)
        origin = origin.country_code(:alpha2)
        
        name = case origin
          when "CA" then CANADA_ORIGIN_SERVICES[code]
          when "MX" then MEXICO_ORIGIN_SERVICES[code]
          when *EU_COUNTRY_CODES then EU_ORIGIN_SERVICES[code]
        end
        
        name ||= OTHER_NON_US_ORIGIN_SERVICES[code] unless name == 'US'
        name ||= DEFAULT_SERVICES[code]
      end

      def create_loggers log_dir
        Dir.mkdir log_dir rescue nil
        LOGGER_NAMES.inject({}) { |acc, l_sym|
          acc.merge!({l_sym => Lumberjack::Logger.new(log_dir + '/' + l_sym.to_s)})
        }
      end

      def log request_type, message
        @loggers[request_type].info(message) if @loggers[request_type] != nil
      end
    end
  end
end
