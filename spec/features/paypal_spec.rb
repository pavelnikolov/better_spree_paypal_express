require 'spec_helper'

describe "PayPal", :js => true do
  let!(:product) { FactoryGirl.create(:product, :name => 'iPad') }
  before do
    @gateway = Spree::Gateway::PayPalExpress.create!({
      :preferred_login => "paypal_api1.ryanbigg.com",
      :preferred_password => "1373587879",
      :preferred_signature => "ACOYQHq-aXKftiD4jURhihawsVSsAsaMr4qH4Tz4K17mJoa3K4M0Dvop",
      :name => "PayPal",
      :active => true,
      :environment => Rails.env
    })
    FactoryGirl.create(:shipping_method)
  end
  def fill_in_billing
    within("#billing") do
      fill_in "First Name", :with => "Test"
      fill_in "Last Name", :with => "User"
      fill_in "Street Address", :with => "1 User Lane"
      # City, State and ZIP must all match for PayPal to be happy
      fill_in "City", :with => "Adamsville"
      select "United States of America", :from => "order_bill_address_attributes_country_id"
      select "Alabama", :from => "order_bill_address_attributes_state_id"
      fill_in "Zip", :with => "35005"
      fill_in "Phone", :with => "555-AME-RICA"
    end
  end
  it "pays for an order successfully" do
    visit spree.root_path
    click_link 'iPad'
    click_button 'Add To Cart'
    click_button 'Checkout'
    within("#guest_checkout") do
      fill_in "Email", :with => "test@example.com"
      click_button 'Continue'
    end
    fill_in_billing
    click_button "Save and Continue"
    # Delivery step doesn't require any action
    click_button "Save and Continue"
    find("#paypal_button").click
    find("#loadLogin").click
    fill_in "login_email", :with => "pp@spreecommerce.com"
    fill_in "login_password", :with => "thequickbrownfox"
    click_button "Log In"
    find("#continue_abovefold").click   # Because there's TWO continue buttons.
    page.should have_content("Your order has been processed successfully")
  end

  it "includes adjustments in PayPal summary" do
    visit spree.root_path
    click_link 'iPad'
    click_button 'Add To Cart'
    # TODO: Is there a better way to find this current order?
    order = Spree::Order.last
    order.adjustments.create!(:amount => -5, :label => "$5 off")
    order.adjustments.create!(:amount => 10, :label => "$10 on")
    visit '/cart'
    within("#cart_adjustments") do
      page.should have_content("$5 off")
      page.should have_content("$10 on")
    end
    click_button 'Checkout'
    within("#guest_checkout") do
      fill_in "Email", :with => "test@example.com"
      click_button 'Continue'
    end
    fill_in_billing
    click_button "Save and Continue"
    # Delivery step doesn't require any action
    click_button "Save and Continue"
    find("#paypal_button").click
    within("#miniCart") do
      page.should have_content("$5 off")
      page.should have_content("$10 on")
    end
  end

  # Regression test for #10
  context "will skip $0 items" do
    let!(:product2) { FactoryGirl.create(:product, :name => 'iPod') }

    specify do
      visit spree.root_path
      click_link 'iPad'
      click_button 'Add To Cart'

      visit spree.root_path
      click_link 'iPod'
      click_button 'Add To Cart'

      # TODO: Is there a better way to find this current order?
      order = Spree::Order.last
      order.line_items.last.update_attribute(:price, 0)
      click_button 'Checkout'
      within("#guest_checkout") do
        fill_in "Email", :with => "test@example.com"
        click_button 'Continue'
      end
      fill_in_billing
      click_button "Save and Continue"
      # Delivery step doesn't require any action
      click_button "Save and Continue"
      find("#paypal_button").click
      within("#miniCart") do
        page.should have_content('iPad')
        page.should_not have_content('iPod')
      end
    end
  end

  context "can process an order with $0 item total" do
    before do
      # If we didn't do this then the order would be free and skip payment altogether
      calculator = Spree::ShippingMethod.first.calculator
      calculator.preferred_amount = 10
      calculator.save
    end

    specify do
      visit spree.root_path
      click_link 'iPad'
      click_button 'Add To Cart'
      # TODO: Is there a better way to find this current order?
      order = Spree::Order.last
      order.adjustments.create!(:amount => -order.line_items.last.price, :label => "FREE iPad ZOMG!")
      click_button 'Checkout'
      within("#guest_checkout") do
        fill_in "Email", :with => "test@example.com"
        click_button 'Continue'
      end
      fill_in_billing
      click_button "Save and Continue"
      # Delivery step doesn't require any action
      click_button "Save and Continue"
      find("#paypal_button").click
      within("#miniCart") do
        page.should have_content('Current purchase')
      end
    end
  end

  context "cannot process a payment with invalid gateway details" do
    before do
      @gateway.preferred_login = nil
      @gateway.save
    end

    specify do
      visit spree.root_path
      click_link 'iPad'
      click_button 'Add To Cart'
      click_button 'Checkout'
      within("#guest_checkout") do
        fill_in "Email", :with => "test@example.com"
        click_button 'Continue'
      end
      fill_in_billing
      click_button "Save and Continue"
      # Delivery step doesn't require any action
      click_button "Save and Continue"
      find("#paypal_button").click
      page.should have_content("PayPal failed. Security header is not valid")
    end
  end
end
