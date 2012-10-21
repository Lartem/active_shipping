require 'test_helper'

class FedExProdTest < Test::Unit::TestCase
  def setup
    @packages  = TestFixtures.packages
    @locations = TestFixtures.locations
    @carrier_prod = FedEx.new(fixtures(:fedex_production).merge(:test => false, :log_dir=>'./logs'))
  end

  def test_courier_dispatch_and_cancel_pickup
    response = nil
    assert_nothing_raised do
      time = Time.parse("14:00", (Time.now + 10*60*60))
      dispatch_response = @carrier_prod.courier_dispatch(
        {:person_name=>'Nikita Mershmall', :company_name=>'Drup inc', :phone_number=>'2513851321'}, 
        @locations[:beverly_hills], time, Time.new(1970, 1, 1, 16), 
        1, @packages.values_at(:american_wii)[0], ActiveMerchant::Shipping::FedEx::CarrierCodes["fedex_express"], :test => false)
      response = @carrier_prod.cancel_pickup(dispatch_response.params["dispatch_confirmation_number"], "FDXE", time, dispatch_response.params["location"], 'ActiveShipping', 'USD', 150.0, :test => false)
    end
  end

  def test_shipment_and_cancel_shipment
    response = nil
    #assert_nothing_raised do
      time = Time.parse("14:00", (Time.now + 48*60*60))
      ship_response = @carrier_prod.request_shipping(time, 'REQUEST_COURIER', 'FEDEX_2_DAY', 'FEDEX_ENVELOPE', 
        {:person_name=>'Nikita Mershmall', :company_name=>'Drup inc', :phone_number=>'2513851321'}, @locations[:beverly_hills], 
        {:person_name=>'Shiro Nakamuro', :company_name=>'Drop inc', :phone_number=>'1513851300'}, @locations[:new_york], 'US', 
        [{:weight_units=>'LB', :weight_value=>'0.5', :item_description=>'Letter', :customer_reference_value=>'SM-US-000000102'}], :test=>false)
      details = ship_response.shipment_details.completed_package_details
      p details

      response = @carrier_prod.cancel_shipping(
        details.tracking_number, 
        time,
        details.form_id, 
        details.tracking_id_type,
        :test => false)
      p response
    #end
  end

end