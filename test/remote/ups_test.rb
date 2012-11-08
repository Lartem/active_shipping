require 'test_helper'

class UPSTest < Test::Unit::TestCase
  
  def setup
    @packages  = TestFixtures.packages
    @locations = TestFixtures.locations
    @carrier   = UPS.new(fixtures(:ups).merge(:test => true))
  end
  
  def test_tracking
    assert_nothing_raised do
      response = @carrier.find_tracking_info('1Z12345E0291980793')
    end
  end
  
  def test_tracking_with_bad_number
    assert_raises ResponseError do
      response = @carrier.find_tracking_info('1Z12345E029198079')
    end
  end
  
  def test_tracking_with_another_number
    assert_nothing_raised do
      response = @carrier.find_tracking_info('1Z12345E6692804405')
    end
  end
  
  def test_us_to_uk
    response = nil
    assert_nothing_raised do
      response = @carrier.find_rates(
                   @locations[:beverly_hills],
                   @locations[:london],
                   @packages.values_at(:big_half_pound),
                   :test => true
                 )
    end
  end

  def test_package_rates
    response = nil
    assert_nothing_raised do
      response = @carrier.find_rates(
                   @locations[:joel_gibson],
                   @locations[:anton_kartashov],
                   Package.new(25*16, [31,31,31], {:units => :imperial}),
                   {:test => true, :packaging_type => 'Package'}
                 )

      response = @carrier.find_rates(
                   @locations[:joel_gibson],
                   @locations[:anton_kartashov],
                   Package.new(25*16, [10,5,5], {:units => :imperial}),
                   {:test => true, :packaging_type => 'Package'}
                 )
    end
  end


  def test_envelope_rates
    response = nil
    assert_nothing_raised do
      response = @carrier.find_rates(
                   @locations[:joel_gibson],
                   @locations[:anton_kartashov],
                   Package.new(0.1, [3,3,1], {:units => :imperial}),
                   {:test => true, :packaging_type => 'Envelope'}
                 )
    end
  end
  
  def test_puerto_rico
    response = nil
    assert_nothing_raised do
      response = @carrier.find_rates(
                   @locations[:beverly_hills],
                   Location.new(:city => 'Ponce', :country => 'US', :state => 'PR', :zip => '00733-1283'),
                   @packages.values_at(:big_half_pound),
                   :test => true
                 )
    end
  end
  
  def test_just_country_given
    response = @carrier.find_rates( 
                 @locations[:beverly_hills],
                 Location.new(:country => 'CA'),
                 Package.new(100, [5,10,20])
               )
    assert_not_equal [], response.rates
  end
  
  def test_ottawa_to_beverly_hills
    response = nil
    assert_nothing_raised do
      response = @carrier.find_rates(
                   @locations[:ottawa],
                   @locations[:beverly_hills],
                   @packages.values_at(:book, :wii),
                   :test => true
                 )
    end
    
    assert response.success?, response.message
    assert_instance_of Hash, response.params
    assert_instance_of String, response.xml
    assert_instance_of Array, response.rates
    assert_not_equal [], response.rates
    
    rate = response.rates.first
    assert_equal 'UPS', rate.carrier
    assert_equal 'CAD', rate.currency
    assert_instance_of Fixnum, rate.total_price
    assert_instance_of Fixnum, rate.price
    assert_instance_of String, rate.service_name
    assert_instance_of String, rate.service_code
    assert_instance_of Array, rate.package_rates
    assert_equal @packages.values_at(:book, :wii), rate.packages
    
    package_rate = rate.package_rates.first
    assert_instance_of Hash, package_rate
    assert_instance_of Package, package_rate[:package]
    assert_nil package_rate[:rate]
  end
  
  def test_ottawa_to_us_fails_without_zip
    assert_raises ResponseError do
      @carrier.find_rates(
        @locations[:ottawa],
        Location.new(:country => 'US'),
        @packages.values_at(:book, :wii),
        :test => true
      )
    end
  end
  
  def test_ottawa_to_us_succeeds_with_only_zip
    assert_nothing_raised do
      @carrier.find_rates(
        @locations[:ottawa],
        Location.new(:country => 'US', :zip => 90210),
        @packages.values_at(:book, :wii),
        :test => true
      )
    end
  end
  
  def test_us_to_uk_with_different_pickup_types
    assert_nothing_raised do
      daily_response = @carrier.find_rates(
        @locations[:beverly_hills],
        @locations[:london],
        @packages.values_at(:book, :wii),
        :pickup_type => :daily_pickup,
        :test => true
      )
      one_time_response = @carrier.find_rates(
        @locations[:beverly_hills],
        @locations[:london],
        @packages.values_at(:book, :wii),
        :pickup_type => :one_time_pickup,
        :test => true
      )
      assert_not_equal daily_response.rates.map(&:price), one_time_response.rates.map(&:price)
    end
  end
  
  def test_bare_packages
    response = nil
    p = Package.new(0,0)
    assert_nothing_raised do
      response = @carrier.find_rates(
                   @locations[:beverly_hills], # imperial (U.S. origin)
                   @locations[:ottawa],
                   p,
                   :test => true
                 )
    end
    assert response.success?, response.message
    assert_nothing_raised do
      response = @carrier.find_rates(
                   @locations[:ottawa],
                   @locations[:beverly_hills], # metric
                   p,
                   :test => true
                 )
    end
    assert response.success?, response.message
  end

  def test_different_rates_based_on_address_type
    responses = {}
    locations = [
      :fake_home_as_residential, :fake_home_as_commercial,
      :fake_google_as_residential, :fake_google_as_commercial
      ]

    locations.each do |location|
      responses[location] = @carrier.find_rates(
                              @locations[:beverly_hills],
                              @locations[location],
                              @packages.values_at(:chocolate_stuff)
                            )
    end

    prices_of = lambda {|sym| responses[sym].rates.map(&:price)}

    assert_not_equal prices_of.call(:fake_home_as_residential), prices_of.call(:fake_home_as_commercial)
    assert_not_equal prices_of.call(:fake_google_as_commercial), prices_of.call(:fake_google_as_residential)
  end

  def test_courier_dispatch
    assert_nothing_raised do
      begin
      #pickup_location, close_time, ready_time, pickup_date, service_code, quantity, dest_country_code, container_code, total_weight, weight_units, residential=nil, options={}
      # @carrier.courier_dispatch(
      #   Location.from(@locations[:beverly_hills].to_hash, :company => 'Smailex', :name=>'Smailex'), 
      #   Time.new(2012, 9, 20, 18), Time.new(2012, 9, 20, 10), Date.new(2012, 8, 30), 
      #   '012', 1, 'US', '01', 2, 'LBS')

      @carrier.courier_dispatch(
        Location.from(@locations[:beverly_hills].to_hash, :company => 'Smailex', :name=>'Smailex'), 
        Time.new(2012, 10, 26, 18), Time.new(2012, 10, 26, 10), Date.new(2012, 10, 26), 
        '012', 1, 'US', '01', 2, 'LBS', 'Y', {:test=>true})
    rescue Exception=>e
      puts
      puts e
      puts e.backtrace
    end
    end
  end

  def test_courier_dispatch_cancel
    assert_nothing_raised do
      begin
      prn = '292A81QPBI4'
      @carrier.courier_dispatch_cancel(prn, {:test => true})
    rescue Exception=>e
      puts
      puts e
      puts e.backtrace
    end
    end
  end

  def test_shipping_request
    shipper = {:person_name=>'Joel Gibson', :phone_number=>'8326990301', :shipper_number => '426F0W', :email => 'grindf@gmail.com'}
    
    ship_to_person = {:person_name=>'Anton Kartashov', :phone_number=>'3479034569'}

    ship_from_person = {:person_name=>'Joel Gibson', :phone_number=>'8326990301'}

    package = {:weight_units=>'LBS', :weight_value=>'0.5', :item_description=>'Large Envelope', :declared_value=>'150'}

    shipping_response = @carrier.request_shipping(shipper, @locations[:joel_gibson], 
                                                  ship_to_person, @locations[:anton_kartashov],
                                                  ship_from_person, @locations[:joel_gibson],
                                                  package, {:test=>true, 
                                                            :transaction_reference_id => 'SM-US-0000000100',
                                                            :pickup_type => 'daily_pickup',
                                                            # :bill_shipper_account_number => '426F0W',
                                                            # :credit_card => true,
                                                            # :credit_card_type => 'MasterCard',
                                                            # :credit_card_number => '0123456789',
                                                            # :credit_card_expiration_date => '012015',
                                                            # :credit_card_security_code => '111',
                                                            :credit_card_address => @locations[:cc_address],
                                                            :service_code => '02',
                                                            :packaging_type => '01'})
    assert shipping_response.success?, shipping_response.message
  
  end

  def test_address_validation
    #Bad address
    response = nil
    assert_nothing_raised do
      response = @carrier.validate_address(@locations[:bad_location], {:test => true})
    end

    #Commercial address
    response = nil
    assert_nothing_raised do
      response = @carrier.validate_address(@locations[:cc_address], {:test => true})
    end

    # #Residental address
    assert_nothing_raised do
      response = @carrier.validate_address(@locations[:joel_gibson], {:test => true})
    end
  end

  def test_cancel_shipment
    response = nil
    assert_nothing_raised do
      response = @carrier.cancel_shipment('1ZISDE016691676846', {:test => true})
    end
  end

  
end
