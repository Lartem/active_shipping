# FedEx module by Jimmy Baker
# http://github.com/jimmyebaker

module ActiveMerchant
  module Shipping
    
    # :key is your developer API key
    # :password is your API password
    # :account is your FedEx account number
    # :login is your meter number
    class FedEx < Carrier
      self.retry_safe = true
      
      cattr_reader :name
      @@name = "FedEx"
      
      TEST_URL = 'https://wsbeta.fedex.com:443/xml'
      LIVE_URL = 'https://ws.fedex.com:443/xml'
      
      CarrierCodes = {
        "fedex_ground" => "FDXG",
        "fedex_express" => "FDXE"
      }
      
      ServiceTypes = {
        "PRIORITY_OVERNIGHT" => "FedEx Priority Overnight",
        "PRIORITY_OVERNIGHT_SATURDAY_DELIVERY" => "FedEx Priority Overnight Saturday Delivery",
        "FEDEX_2_DAY" => "FedEx 2 Day",
        "FEDEX_2_DAY_SATURDAY_DELIVERY" => "FedEx 2 Day Saturday Delivery",
        "STANDARD_OVERNIGHT" => "FedEx Standard Overnight",
        "FIRST_OVERNIGHT" => "FedEx First Overnight",
        "FIRST_OVERNIGHT_SATURDAY_DELIVERY" => "FedEx First Overnight Saturday Delivery",
        "FEDEX_EXPRESS_SAVER" => "FedEx Express Saver",
        "FEDEX_1_DAY_FREIGHT" => "FedEx 1 Day Freight",
        "FEDEX_1_DAY_FREIGHT_SATURDAY_DELIVERY" => "FedEx 1 Day Freight Saturday Delivery",
        "FEDEX_2_DAY_FREIGHT" => "FedEx 2 Day Freight",
        "FEDEX_2_DAY_FREIGHT_SATURDAY_DELIVERY" => "FedEx 2 Day Freight Saturday Delivery",
        "FEDEX_3_DAY_FREIGHT" => "FedEx 3 Day Freight",
        "FEDEX_3_DAY_FREIGHT_SATURDAY_DELIVERY" => "FedEx 3 Day Freight Saturday Delivery",
        "INTERNATIONAL_PRIORITY" => "FedEx International Priority",
        "INTERNATIONAL_PRIORITY_SATURDAY_DELIVERY" => "FedEx International Priority Saturday Delivery",
        "INTERNATIONAL_ECONOMY" => "FedEx International Economy",
        "INTERNATIONAL_FIRST" => "FedEx International First",
        "INTERNATIONAL_PRIORITY_FREIGHT" => "FedEx International Priority Freight",
        "INTERNATIONAL_ECONOMY_FREIGHT" => "FedEx International Economy Freight",
        "GROUND_HOME_DELIVERY" => "FedEx Ground Home Delivery",
        "FEDEX_GROUND" => "FedEx Ground",
        "INTERNATIONAL_GROUND" => "FedEx International Ground"
      }

      PackageTypes = {
        "fedex_envelope" => "FEDEX_ENVELOPE",
        "fedex_pak" => "FEDEX_PAK",
        "fedex_box" => "FEDEX_BOX",
        "fedex_tube" => "FEDEX_TUBE",
        "fedex_10_kg_box" => "FEDEX_10KG_BOX",
        "fedex_25_kg_box" => "FEDEX_25KG_BOX",
        "your_packaging" => "YOUR_PACKAGING"
      }

      DropoffTypes = {
        'regular_pickup' => 'REGULAR_PICKUP',
        'request_courier' => 'REQUEST_COURIER',
        'dropbox' => 'DROP_BOX',
        'business_service_center' => 'BUSINESS_SERVICE_CENTER',
        'station' => 'STATION'
      }

      PaymentTypes = {
        'sender' => 'SENDER',
        'recipient' => 'RECIPIENT',
        'third_party' => 'THIRDPARTY',
        'collect' => 'COLLECT'
      }
      
      PackageIdentifierTypes = {
        'tracking_number' => 'TRACKING_NUMBER_OR_DOORTAG',
        'door_tag' => 'TRACKING_NUMBER_OR_DOORTAG',
        'rma' => 'RMA',
        'ground_shipment_id' => 'GROUND_SHIPMENT_ID',
        'ground_invoice_number' => 'GROUND_INVOICE_NUMBER',
        'ground_customer_reference' => 'GROUND_CUSTOMER_REFERENCE',
        'ground_po' => 'GROUND_PO',
        'express_reference' => 'EXPRESS_REFERENCE',
        'express_mps_master' => 'EXPRESS_MPS_MASTER'
      }

      # FedEx tracking codes as described in the FedEx Tracking Service WSDL Guide
      # All delays also have been marked as exceptions
      TRACKING_STATUS_CODES = HashWithIndifferentAccess.new({
        'AA' => :at_airport,
        'AD' => :at_delivery,
        'AF' => :at_fedex_facility,
        'AR' => :at_fedex_facility,
        'AP' => :at_pickup,
        'CA' => :canceled,
        'CH' => :location_changed,
        'DE' => :exception,
        'DL' => :delivered,
        'DP' => :departed_fedex_location,
        'DR' => :vehicle_furnished_not_used,
        'DS' => :vehicle_dispatched,
        'DY' => :exception,
        'EA' => :exception,
        'ED' => :enroute_to_delivery,
        'EO' => :enroute_to_origin_airport,
        'EP' => :enroute_to_pickup,
        'FD' => :at_fedex_destination,
        'HL' => :held_at_location,
        'IT' => :in_transit,
        'LO' => :left_origin,
        'OC' => :order_created,
        'OD' => :out_for_delivery,
        'PF' => :plane_in_flight,
        'PL' => :plane_landed,
        'PU' => :picked_up,
        'RS' => :return_to_shipper,
        'SE' => :exception,
        'SF' => :at_sort_facility,
        'SP' => :split_status,
        'TR' => :transfer
      })

      PICKUP_REQUEST_TYPES = {
        'same_day' => 'SAME_DAY',
        'future_day' => 'FUTURE_DAY'
      }

      PICKUP_XMLNS = {'xmlns' => 'http://fedex.com/ws/courierdispatch/v3'}

      def self.service_name_for_code(service_code)
        ServiceTypes[service_code] || "FedEx #{service_code.titleize.sub(/Fedex /, '')}"
      end
      
      def requirements
        [:key, :password, :account, :login]
      end
      
      def find_rates(origin, destination, packages, options = {})
        options = @options.update(options)
        packages = Array(packages)
        
        rate_request = build_rate_request(origin, destination, packages, options)
        
        response = commit(save_request(rate_request), (options[:test] || false)).gsub(/<(\/)?.*?\:(.*?)>/, '<\1\2>')
        
        parse_rate_response(origin, destination, packages, response, options)
      end
      
      def find_tracking_info(tracking_number, options={})
        options = @options.update(options)
        
        tracking_request = build_tracking_request(tracking_number, options)
        response = commit(save_request(tracking_request), (options[:test] || false)).gsub(/<(\/)?.*?\:(.*?)>/, '<\1\2>')
        parse_tracking_response(response, options)
      end
      
      def validate_addresses(addresses, options={})
        options = @options.update(options)
        validate_address_request = build_validate_address_request(addresses)
        response = commit(save_request(validate_address_request), (options[:test] || false)).gsub(/\sxmlns(:|=)[^>]*/, '').gsub(/<(\/)?[^<]*?\:(.*?)>/, '<\1\2>')
        parse_address_validation_response(response, options)
      end

      def check_pickup_availability(pickup_address, request_types, dispatch_date, 
        package_ready_time, customer_close_time, carriers, shipment_attributes, options={})
        options = @options.update(options)
        check_pickup_request = build_pickup_request(pickup_address, request_types, dispatch_date, 
          package_ready_time, customer_close_time, carriers, shipment_attributes)
        p check_pickup_request
        response = commit(save_request(check_pickup_request), (options[:test] || false)).gsub(/\sxmlns(:|=)[^>]*/, '').gsub(/<(\/)?[^<]*?\:(.*?)>/, '<\1\2>')
        parse_pickup_response(response, options)        
      end

      protected
      def build_pickup_request(pickup_address, request_types, dispatch_date, 
          package_ready_time, customer_close_time, carriers, packages)
        xml_request = XmlNode.new('AddressValidationRequest', 
          'xmlns:xsd' => 'http://www.w3.org/2001/XMLSchema', 
          'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance',
          'xmlns' => 'http://fedex.com/ws/courierdispatch/v3') do |root_node|

          root_node << build_request_header(PICKUP_XMLNS)

          #version
          root_node << XmlNode.new('Version', PICKUP_XMLNS) do |version_node|
            version_node << XmlNode.new('ServiceId', 'disp')
            version_node << XmlNode.new('Major', 3)
            version_node << XmlNode.new('Intermediate', 0)
            version_node << XmlNode.new('Minor', 1)
          end

          #pickup_address
          root_node << build_location_node_full(pickup_address, 'PickupAddress', PICKUP_XMLNS)
          
          #request types
          request_types.each {|rt| root_node << XmlNode.new('PickupRequestType', PICKUP_REQUEST_TYPES[rt] || rt.capitalize, PICKUP_XMLNS)}

          #dispatch date
          root_node << XmlNode.new('DispatchDate', dispatch_date.strftime('%Y-%m-%d'), PICKUP_XMLNS)

          #package ready time
          root_node << XmlNode.new('PackageReadyTime', package_ready_time, PICKUP_XMLNS)

          #customer close time
          root_node << XmlNode.new('CustomerCloseTime', customer_close_time.strftime('%H:%M:%S'), PICKUP_XMLNS)

          #carriers
          carriers.each { |c| root_node << XmlNode.new('Carriers', CarrierCodes[c], PICKUP_XMLNS)}

          #shipment attributes
          imperial = ['US','LR','MM'].include?(pickup_address.country_code(:alpha2))
          packages.each {|p| root_node << build_package_node(p, 'ShipmentAttributes', imperial, PICKUP_XMLNS)}
        end
        xml_request.to_s
      end

      def build_validate_address_request(addresses_to_validate, options={})
        xml_request = XmlNode.new('AddressValidationRequest', 
          'xmlns:xsd' => 'http://www.w3.org/2001/XMLSchema', 
          'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance',
          'xmlns' => 'http://fedex.com/ws/addressvalidation/v2') do |root_node|
          root_node << build_request_header({'xmlns'=>'http://fedex.com/ws/addressvalidation/v2'})

          #version
          root_node << XmlNode.new('Version', 'xmlns' => 'http://fedex.com/ws/addressvalidation/v2') do |version_node|
            version_node << XmlNode.new('ServiceId', 'aval')
            version_node << XmlNode.new('Major', 2)
            version_node << XmlNode.new('Intermediate', 0)
            version_node << XmlNode.new('Minor', 0)
          end

          #request timestamp
          root_node << XmlNode.new('RequestTimestamp', Time.now)

          #options
          root_node << XmlNode.new('Options', 'xmlns' => 'http://fedex.com/ws/addressvalidation/v2') do |options_node|
            options_node << XmlNode.new('VerifyAddresses', true)
            options_node << XmlNode.new('MaximumNumberOfMatches', options[:av_max_matches] || 2)
            options_node << XmlNode.new('StreetAccuracy', options[:av_str_accuracy] || 'LOOSE')
            options_node << XmlNode.new('ConvertToUpperCase', true)
            options_node << XmlNode.new('RecognizeAlternateCityNames', true)
            options_node << XmlNode.new('ReturnParsedElements', options[:av_parsed] || true)
          end

          #addresses to validate
          addresses_to_validate.each {|address_id, location| root_node << build_location_node_for_validation(address_id, location)}
        end
        xml_request.to_s
      end

      def build_location_node_for_validation(address_id, location) 
        XmlNode.new('AddressesToValidate', 'xmlns' => 'http://fedex.com/ws/addressvalidation/v2') do |av_node|
          av_node << XmlNode.new('AddressId', address_id)
          av_node << build_location_node_full(location, 'Address', nil)
        end
      end

      def build_location_node_full(location, node_name, xmlns)
        XmlNode.new(node_name, xmlns) do |address_node|
          [location.address1, location.address2, location.address3].reject {|e| e.blank?}.each do |s_line|
            address_node << XmlNode.new('StreetLines', s_line)
          end
          address_node << XmlNode.new('City', location.city)
          address_node << XmlNode.new('StateOrProvinceCode', location.province)
          address_node << XmlNode.new('PostalCode', location.postal_code)
          address_node << XmlNode.new('CountryCode', location.country_code(:alpha2))
        end
      end

      def build_rate_request(origin, destination, packages, options={})
        imperial = ['US','LR','MM'].include?(origin.country_code(:alpha2))

        xml_request = XmlNode.new('RateRequest', 'xmlns' => 'http://fedex.com/ws/rate/v6') do |root_node|
          root_node << build_request_header

          # Version
          root_node << XmlNode.new('Version') do |version_node|
            version_node << XmlNode.new('ServiceId', 'crs')
            version_node << XmlNode.new('Major', '6')
            version_node << XmlNode.new('Intermediate', '0')
            version_node << XmlNode.new('Minor', '0')
          end
          
          # Returns delivery dates
          root_node << XmlNode.new('ReturnTransitAndCommit', true)
          # Returns saturday delivery shipping options when available
          root_node << XmlNode.new('VariableOptions', 'SATURDAY_DELIVERY')
          
          root_node << XmlNode.new('RequestedShipment') do |rs|
            rs << XmlNode.new('ShipTimestamp', Time.now)
            rs << XmlNode.new('DropoffType', options[:dropoff_type] || 'REGULAR_PICKUP')
            rs << XmlNode.new('PackagingType', options[:packaging_type] || 'YOUR_PACKAGING')
            
            rs << build_location_node('Shipper', (options[:shipper] || origin))
            rs << build_location_node('Recipient', destination)
            if options[:shipper] and options[:shipper] != origin
              rs << build_location_node('Origin', origin)
            end
            
            rs << XmlNode.new('RateRequestTypes', 'ACCOUNT')
            rs << XmlNode.new('PackageCount', packages.size)
            packages.each do |pkg|
              rs << build_package_node(pkg, 'RequestedPackages', imperial)
            end
            
          end
        end
        xml_request.to_s
      end

      def build_package_node(package, node_name, imperial, xmlns=nil)
        XmlNode.new(node_name, xmlns) do |rps|
          rps << XmlNode.new('Weight') do |tw|
            tw << XmlNode.new('Units', imperial ? 'LB' : 'KG')
            tw << XmlNode.new('Value', [((imperial ? package.lbs : package.kgs).to_f*1000).round/1000.0, 0.1].max)
          end
          rps << XmlNode.new('Dimensions') do |dimensions|
            [:length,:width,:height].each do |axis|
              value = ((imperial ? package.inches(axis) : package.cm(axis)).to_f*1000).round/1000.0 # 3 decimals
              dimensions << XmlNode.new(axis.to_s.capitalize, value.ceil)
            end
            dimensions << XmlNode.new('Units', imperial ? 'IN' : 'CM')
          end
        end
      end
      
      def build_tracking_request(tracking_number, options={})
        xml_request = XmlNode.new('TrackRequest', 'xmlns' => 'http://fedex.com/ws/track/v3') do |root_node|
          root_node << build_request_header
          
          # Version
          root_node << XmlNode.new('Version') do |version_node|
            version_node << XmlNode.new('ServiceId', 'trck')
            version_node << XmlNode.new('Major', '3')
            version_node << XmlNode.new('Intermediate', '0')
            version_node << XmlNode.new('Minor', '0')
          end
          
          root_node << XmlNode.new('PackageIdentifier') do |package_node|
            package_node << XmlNode.new('Value', tracking_number)
            package_node << XmlNode.new('Type', PackageIdentifierTypes[options['package_identifier_type'] || 'tracking_number'])
          end
          
          root_node << XmlNode.new('ShipDateRangeBegin', options['ship_date_range_begin']) if options['ship_date_range_begin']
          root_node << XmlNode.new('ShipDateRangeEnd', options['ship_date_range_end']) if options['ship_date_range_end']
          root_node << XmlNode.new('IncludeDetailedScans', 1)
        end
        xml_request.to_s
      end
      
      def build_request_header(namespaces=nil)
        web_authentication_detail = XmlNode.new('WebAuthenticationDetail', namespaces) do |wad|
          wad << XmlNode.new('UserCredential') do |uc|
            uc << XmlNode.new('Key', @options[:key])
            uc << XmlNode.new('Password', @options[:password])
          end
        end
        
        client_detail = XmlNode.new('ClientDetail') do |cd|
          cd << XmlNode.new('AccountNumber', @options[:account])
          cd << XmlNode.new('MeterNumber', @options[:login])
        end
        
        trasaction_detail = XmlNode.new('TransactionDetail') do |td|
          td << XmlNode.new('CustomerTransactionId', 'ActiveShipping') # TODO: Need to do something better with this..
        end
        
        [web_authentication_detail, client_detail, trasaction_detail]
      end
            
      def build_location_node(name, location)
        location_node = XmlNode.new(name) do |xml_node|
          xml_node << XmlNode.new('Address') do |address_node|
            address_node << XmlNode.new('PostalCode', location.postal_code)
            address_node << XmlNode.new("CountryCode", location.country_code(:alpha2))

            address_node << XmlNode.new("Residential", true) unless location.commercial?
          end
        end
      end
      
      def parse_rate_response(origin, destination, packages, response, options)
        rate_estimates = []
        success, message = nil
        
        xml = REXML::Document.new(response)
        root_node = xml.elements['RateReply']
        
        success = response_success?(xml)
        message = response_message(xml)
        
        root_node.elements.each('RateReplyDetails') do |rated_shipment|
          service_code = rated_shipment.get_text('ServiceType').to_s
          is_saturday_delivery = rated_shipment.get_text('AppliedOptions').to_s == 'SATURDAY_DELIVERY'
          service_type = is_saturday_delivery ? "#{service_code}_SATURDAY_DELIVERY" : service_code
          
          currency = handle_incorrect_currency_codes(rated_shipment.get_text('RatedShipmentDetails/ShipmentRateDetail/TotalNetCharge/Currency').to_s)
          rate_estimates << RateEstimate.new(origin, destination, @@name,
                              self.class.service_name_for_code(service_type),
                              :service_code => service_code,
                              :total_price => rated_shipment.get_text('RatedShipmentDetails/ShipmentRateDetail/TotalNetCharge/Amount').to_s.to_f,
                              :currency => currency,
                              :packages => packages,
                              :delivery_range => [rated_shipment.get_text('DeliveryTimestamp').to_s] * 2)
	    end
		
        if rate_estimates.empty?
          success = false
          message = "No shipping rates could be found for the destination address" if message.blank?
        end

        RateResponse.new(success, message, Hash.from_xml(response), :rates => rate_estimates, :xml => response, :request => last_request, :log_xml => options[:log_xml])
      end
      
      def parse_tracking_response(response, options)
        xml = REXML::Document.new(response)
        root_node = xml.elements['TrackReply']
        
        success = response_success?(xml)
        message = response_message(xml)
        
        if success
          tracking_number, origin, destination, status, status_code, status_description, scheduled_delivery_date = nil
          shipment_events = []

          tracking_details = root_node.elements['TrackDetails']
          tracking_number = tracking_details.get_text('TrackingNumber').to_s
          
          status_code = tracking_details.get_text('StatusCode').to_s
          status_description = tracking_details.get_text('StatusDescription').to_s
          status = TRACKING_STATUS_CODES[status_code]

          origin_node = tracking_details.elements['OriginLocationAddress']
        
          if origin_node
            origin = Location.new(
                  :country =>     origin_node.get_text('CountryCode').to_s,
                  :province =>    origin_node.get_text('StateOrProvinceCode').to_s,
                  :city =>        origin_node.get_text('City').to_s
            )
          end

          destination_node = tracking_details.elements['DestinationAddress']

          if destination_node.nil?
            destination_node = tracking_details.elements['ActualDeliveryAddress']
          end

          destination = Location.new(
                :country =>     destination_node.get_text('CountryCode').to_s,
                :province =>    destination_node.get_text('StateOrProvinceCode').to_s,
                :city =>        destination_node.get_text('City').to_s
              )
          
          unless status == :delivered
            scheduled_delivery_date = Time.parse(tracking_details.get_text('EstimatedDeliveryTimestamp').to_s)
          end

          tracking_details.elements.each('Events') do |event|
            address  = event.elements['Address']

            city     = address.get_text('City').to_s
            state    = address.get_text('StateOrProvinceCode').to_s
            zip_code = address.get_text('PostalCode').to_s
            country  = address.get_text('CountryCode').to_s
            next if country.blank?
            
            location = Location.new(:city => city, :state => state, :postal_code => zip_code, :country => country)
            description = event.get_text('EventDescription').to_s
            
            # for now, just assume UTC, even though it probably isn't
            time = Time.parse("#{event.get_text('Timestamp').to_s}")
            zoneless_time = Time.utc(time.year, time.month, time.mday, time.hour, time.min, time.sec)
            
            shipment_events << ShipmentEvent.new(description, zoneless_time, location)
          end
          shipment_events = shipment_events.sort_by(&:time)

        end
        
        TrackingResponse.new(success, message, Hash.from_xml(response),
          :carrier => @@name,
          :xml => response,
          :request => last_request,
          :status => status,
          :status_code => status_code,
          :status_description => status_description,
          :scheduled_delivery_date => scheduled_delivery_date,
          :shipment_events => shipment_events,
          :origin => origin,
          :destination => destination,
          :tracking_number => tracking_number
        )
      end

      def parse_address_validation_response(response, options)
        xml = REXML::Document.new(response)
        root_node = xml.elements['AddressValidationReply']
        success = response_success?(xml)
        message = response_message(xml)
        addresses = {}
        parsed_results = []
        root_node.elements.each('AddressResults') do |address_result_node|
          address_id, score, changes, delivery_point_validation, parsed_address, address_details = nil
          address_id = address_result_node.get_text('AddressId').to_s
          address_result_node.elements.each('ProposedAddressDetails') do |address_details_node|
            score = address_details_node.get_text('Score')
            changes = address_details_node.elements.inject('Changes', []) {|acc, change_node| acc.push(change_node.get_text.to_s)}
            delivery_point_validation = address_details_node.get_text('DeliveryPointValidation')
            address_details_node.elements.each('Address') do |address_node|
              address1, address2, address3 = address_node.elements.inject('StreetLines', []) {|acc, street_line| acc.push(street_line.get_text.to_s)}
              location = Location.new(
                :address1 => address1,
                :address2 => address2,
                :address3 => address3,
                :city => address_node.get_text('City').to_s,
                :province => address_node.get_text('StateOrProvinceCode').to_s,
                :postal_code => address_node.get_text('PostalCode').to_s,
                :country => address_node.get_text('CountryCode').to_s
              )
              addresses.merge!({address_id => AddressValidationDetails.new(location, score, address_id, changes, delivery_point_validation)})
            end
            address_details_node.elements.each('ParsedAddress') do |p_address|
              parsed_results << ParsedAddressValidationResults.new(
                *['ParsedStreetLine', 
                    'ParsedCity', 
                    'ParsedStateOrProvinceCode', 
                    'ParsedPostalCode', 
                    'ParsedCountryCode'].map {|el| parse_parsed_elements(p_address,el)}
              )
            end
          end
        end
        AddressValidation.new(success, message, Hash.from_xml(response),
          :carrier => @@name,
          :xml => response,
          :request => last_request,
          :addresses => addresses,
          :parsed_results => parsed_results
        )
      end

      def parse_parsed_elements(parsed_address_node, node_name)
        parsed_address_node.elements[node_name].elements.inject('Elements', []) do |acc, element|
          name = element.get_text('Name')
          value = element.get_text('Value')
          local_changes = element.get_text('Changes')
          acc << ParsedAddressValidationElement.new(name, value, local_changes)
        end
      end

      def parse_pickup_response(response, options)
      end

      def response_status_node(document)
        document.elements['/*/Notifications/']
      end
      
      def response_success?(document)
        %w{SUCCESS WARNING NOTE}.include? response_status_node(document).get_text('Severity').to_s
      end
      
      def response_message(document)
        response_node = response_status_node(document)
        "#{response_status_node(document).get_text('Severity')} - #{response_node.get_text('Code')}: #{response_node.get_text('Message')}"
      end
      
      def commit(request, test = false)
        ssl_post(test ? TEST_URL : LIVE_URL, request.gsub("\n",''))        
      end
      
      def handle_incorrect_currency_codes(currency)
        case currency
        when /UKL/i then 'GBP'
        when /SID/i then 'SGD'
        else currency
        end
      end
    end
  end
end
