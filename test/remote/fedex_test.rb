require 'test_helper'

class FedExTest < Test::Unit::TestCase

  def setup
    @packages  = TestFixtures.packages
    @locations = TestFixtures.locations
    @carrier   = FedEx.new(fixtures(:fedex).merge(:test => true, :log_dir=>'./logs'))
    @carrier_prod = FedEx.new(fixtures(:fedex_production).merge(:test => false, :log_dir=>'./logs'))
  end
    
  def test_valid_credentials
    assert @carrier.valid_credentials?
  end
    
  def test_us_to_canada
    response = nil
    assert_nothing_raised do
      response = @carrier.find_rates(
                   @locations[:beverly_hills],
                   @locations[:ottawa],
                   @packages.values_at(:wii)
                 )
      assert !response.rates.blank?
      response.rates.each do |rate|
        assert_instance_of String, rate.service_name
        assert_instance_of Fixnum, rate.price
      end
    end
  end
  
  def test_zip_to_zip_fails
    begin
      @carrier.find_rates(
        Location.new(:zip => 40524),
        Location.new(:zip => 40515),
        @packages[:wii]
      )
    rescue ResponseError => e
      assert_match /country\s?code/i, e.message
      assert_match /(missing|invalid)/, e.message
    end
  end
  
  # FedEx requires a valid origin and destination postal code
  def test_rates_for_locations_with_only_zip_and_country  
    response = @carrier.find_rates(
                 @locations[:bare_beverly_hills],
                 @locations[:bare_ottawa],
                 @packages.values_at(:wii)
               )
    assert response.rates.size > 0
  end
  
  def test_rates_for_location_with_only_country_code
    begin
      response = @carrier.find_rates(
                   @locations[:bare_beverly_hills],
                   Location.new(:country => 'CA'),
                   @packages.values_at(:wii)
                 )
    rescue ResponseError => e
      assert_match /postal code/i, e.message
      assert_match /(missing|invalid)/i, e.message
    end
  end
  
  def test_invalid_recipient_country
    begin
      response = @carrier.find_rates(
                   @locations[:bare_beverly_hills],
                   Location.new(:country => 'JP', :zip => '108-8361'),
                   @packages.values_at(:wii)
                 )
    rescue ResponseError => e
      assert_match /postal code/i, e.message
      assert_match /(missing|invalid)/i, e.message
    end
  end
  
  def test_ottawa_to_beverly_hills
    response = nil
    assert_nothing_raised do
      response = @carrier.find_rates(
                   @locations[:ottawa],
                   @locations[:beverly_hills],
                   @packages.values_at(:book, :wii)
                 )
      assert !response.rates.blank?
      response.rates.each do |rate|
        assert_instance_of String, rate.service_name
        assert_instance_of Fixnum, rate.price
      end
    end
  end
  
  def test_ottawa_to_london
    response = nil
    assert_nothing_raised do
      response = @carrier.find_rates(
                   @locations[:ottawa],
                   @locations[:london],
                   @packages.values_at(:book, :wii)
                 )
      assert !response.rates.blank?
      response.rates.each do |rate|
        assert_instance_of String, rate.service_name
        assert_instance_of Fixnum, rate.price
      end
    end
  end
  
  def test_beverly_hills_to_london
    response = nil
    assert_nothing_raised do
      response = @carrier.find_rates(
                   @locations[:beverly_hills],
                   @locations[:london],
                   @packages.values_at(:book, :wii)
                 )
      assert !response.rates.blank?
      response.rates.each do |rate|
        assert_instance_of String, rate.service_name
        assert_instance_of Fixnum, rate.price
      end
    end
  end

  def test_tracking
    assert_nothing_raised do
      @carrier.find_tracking_info('077973360403984', :test => true)
    end
  end

  def test_tracking_with_bad_number
    assert_raises ResponseError do
      response = @carrier.find_tracking_info('12345')
    end
  end

  def test_different_rates_for_commercial
    residential_response = @carrier.find_rates(
                             @locations[:beverly_hills],
                             @locations[:ottawa],
                             @packages.values_at(:chocolate_stuff)
                           )
    commercial_response  = @carrier.find_rates(
                             @locations[:beverly_hills],
                             Location.from(@locations[:ottawa].to_hash, :address_type => :commercial),
                             @packages.values_at(:chocolate_stuff)
                           )

    assert_not_equal residential_response.rates.map(&:price), commercial_response.rates.map(&:price)
  end

  # fedex does not have address validation test service 
  def test_address_validation
    response = nil
    assert_nothing_raised do
      #response = @carrier_prod.validate_addresses({'address_from' => @locations[:ottawa], 'address_to' => @locations[:beverly_hills]}, :test=>false)
      @carrier_prod.validate_addresses({'address_from' => Location.new(
                                      :country => 'US',
                                      :state => 'TX',
                                      :city => 'Houston',
                                      :address1 => '11811 North Freeway',
                                      :address2 => 'suite 500',
                                      :zip => '77060'), 
        'address_to' => Location.new(:country => 'US',
                                      :state => 'NY',
                                      :city => 'Brooklyn',
                                      :address1 => '7 Balfour pl',
                                      :address2 => 'Apt E3',
                                      :zip => '11225')})
    end
  end

  def test_pickup_availability
    response = nil
    assert_nothing_raised do
      # response = @carrier_prod.check_pickup_availability(@locations[:ottawa], 
      #   [:same_day, :future_day], Date.new(2012,8,20), Time.new(2012, 8, 10, 16), 
      #   Time.new(1970, 1, 1, 16), ['fedex_express'], @packages.values_at(:american_wii), :test => false)
      response = @carrier_prod.check_pickup_availability(Location.new(:country => 'US',
                                      :state => 'TX',
                                      :city => 'Houston',
                                      :address1 => '11811 North Freeway',
                                      :address2 => 'suite 500',
                                      :zip => '77060'),
      [:same_day, :future_day], Date.new(2012,8,19), Time.new(2012, 10, 19, 10), 
        Time.new(1970, 1, 1, 16), ['fedex_express'], @packages.values_at(:american_wii), :test => false)
    end
  end

  def test_address_validation_bug
    @carrier_prod.validate_addresses({'address_from' => Location.new(
                                    :country => 'US',
                                    :city => 'Akron',
                                    :zip => '44320'), 
      'address_to' => Location.new(:country => 'US',
                                    :city => 'Benton City',
                                    :zip => '65232')})
  end

  def test_courier_dispatch
    response = nil
    assert_nothing_raised do
      response = @carrier.courier_dispatch(
        {:person_name=>'Nikita Mershmall', :company_name=>'Drup inc', :phone_number=>'2513851321'}, 
        @locations[:beverly_hills], Time.parse("14:00", (Time.now + 10*60*60)), Time.new(1970, 1, 1, 16), 
        1, @packages.values_at(:american_wii)[0], ActiveMerchant::Shipping::FedEx::CarrierCodes["fedex_express"], :test => true)
    end    
  end

  def test_shipping
    response = nil
    assert_nothing_raised do
      response = @carrier.request_shipping(Time.parse("14:00", (Time.now + 48*60*60)), 'REQUEST_COURIER', 'FEDEX_2_DAY', 'FEDEX_ENVELOPE', 
        {:person_name=>'Nikita Mershmall', :company_name=>'Drup inc', :phone_number=>'2513851321'}, @locations[:beverly_hills], 
        {:person_name=>'Shiro Nakamuro', :company_name=>'Drop inc', :phone_number=>'1513851300'}, @locations[:new_york], 'US', 
        [{:weight_units=>'LB', :weight_value=>'0.5', :item_description=>'Letter', :customer_reference_value=>'SM-US-000000102'}], :test=>true)
    end
  end
end
