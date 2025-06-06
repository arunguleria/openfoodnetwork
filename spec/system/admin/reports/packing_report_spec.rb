# frozen_string_literal: true

require "system_helper"

RSpec.describe "Packing Reports" do
  include AuthenticationHelper
  include WebHelper

  around do |example|
    Timecop.freeze(Time.zone.now.strftime("%Y-%m-%d 00:00")) { example.run }
  end

  let!(:open_datetime) { 1.month.ago.strftime("%Y-%m-%d 00:00") }
  let!(:close_datetime) { Time.zone.now.strftime("%Y-%m-%d 00:00") }

  shared_examples "shipment state and shipping method specs" do |report_name|
    it "makes shipping method and shipment state visible in #{report_name}" do
      find('.ofn-drop-down').click
      within ".menu" do
        page.find("span", text: "Shipment State").click
        page.find("span", text: "Shipping Method").click
      end

      run_report

      within "table.report__table" do
        expect(page).to have_selector("th", text: "Shipment State")
        expect(page).to have_selector("th", text: "Shipping Method")
      end
    end
  end

  describe "Packing reports" do
    before do
      login_as_admin
      visit admin_reports_path
    end

    let(:bill_address1) { create(:address, lastname: "ABRA") }
    let(:bill_address2) { create(:address, lastname: "KADABRA") }
    let(:distributor_address) {
      create(:address, address1: "distributor address", city: 'The Shire', zipcode: "1234")
    }
    let(:distributor) { create(:distributor_enterprise, address: distributor_address) }
    let(:order1) {
      create(:completed_order_with_totals, line_items_count: 0, distributor:,
                                           bill_address: bill_address1)
    }
    let(:order2) {
      create(:completed_order_with_totals, line_items_count: 0, distributor:,
                                           bill_address: bill_address2)
    }
    let(:supplier) { create(:supplier_enterprise, name: "Supplier") }
    let(:product1) { create(:simple_product, name: "Product 1", supplier_id: supplier.id ) }
    let(:variant1) { create(:variant, product: product1, unit_description: "Big", supplier: ) }
    let(:variant2) { create(:variant, product: product1, unit_description: "Small", supplier: ) }
    let(:product2) { create(:simple_product, name: "Product 2", supplier_id: supplier.id) }

    before do
      order1.finalize!
      order2.finalize!

      create(:line_item_with_shipment, variant: variant1, quantity: 1, order: order1)
      create(:line_item_with_shipment, variant: variant2, quantity: 3, order: order1)
      create(:line_item_with_shipment, variant: product2.variants.first, quantity: 3, order: order2)
    end

    describe "Pack By Customer" do
      before { click_link "Pack By Customer" }

      it "displays the report" do
        # pre-fills with dates
        check_prefilled_dates

        run_report

        rows = find("table.report__table").all("thead tr")
        table = rows.map { |r| r.all("th").map { |c| c.text.strip } }
        expect(table).to eq([
                              ["Hub", "Customer Code", "First Name", "Last Name", "Supplier",
                               "Product", "Variant", "Weight", "Height", "Width", "Depth",
                               "Quantity", "TempControlled?"]
                            ])
        expect(page).to have_selector 'table.report__table tbody tr', count: 5 # Totals row/order

        # date range is kept after form submission
        check_prefilled_dates
      end

      it "sorts alphabetically" do
        # pre-fills with dates
        check_prefilled_dates

        run_report
        rows = find("table.report__table").all("tr")
        table = rows.map { |r| r.all("th,td").map { |c| c.text.strip }[3] }
        expect(table).to eq([
                              "Last Name",
                              order1.bill_address.lastname,
                              order1.bill_address.lastname,
                              "",
                              order2.bill_address.lastname,
                              ""
                            ])

        # date range is kept after form submission
        check_prefilled_dates
      end

      it_behaves_like "shipment state and shipping method specs", "Pack By Customer"
    end

    describe "Pack By Supplier" do
      before { click_link "Pack By Supplier" }

      it "displays the report" do
        # pre-fills with dates
        check_prefilled_dates

        find(:css, "#display_summary_row").set(false) # does not include summary rows

        run_report

        rows = find("table.report__table").all("thead tr")
        table = rows.map { |r| r.all("th").map { |c| c.text.strip } }
        expect(table).to eq([
                              ["Hub", "Supplier", "Customer Code", "First Name", "Last Name",
                               "Product", "Variant", "Quantity", "TempControlled?"]
                            ])

        expect(all('table.report__table tbody tr').count).to eq(3) # Totals row per supplier

        # date range is kept after form submission
        check_prefilled_dates
      end

      it_behaves_like "shipment state and shipping method specs", "Pack By Supplier"
    end
  end

  describe "With soft-deleted variants" do
    let(:distributor) { create(:distributor_enterprise) }
    let(:oc) { create(:simple_order_cycle) }
    let(:order) {
      create(:completed_order_with_totals, line_items_count: 0,
                                           order_cycle: oc, distributor:)
    }
    let(:li1) { build(:line_item_with_shipment) }
    let(:li2) { build(:line_item_with_shipment) }

    before do
      order.line_items << li1
      order.line_items << li2
      order.finalize!
      login_as_admin
    end

    describe "viewing the Pack by Product report" do
      context "when an associated variant has been soft-deleted" do
        before do
          li1.variant.delete
          visit admin_reports_path
          click_link "Pack By Product"
        end

        it "shows line items" do
          select oc.name, from: "q_order_cycle_id_in"

          # pre-fills with dates
          check_prefilled_dates

          run_report
          expect(page).to have_content li1.product.name
          expect(page).to have_content li2.product.name

          # date range is kept after form submission
          check_prefilled_dates
        end

        it_behaves_like "shipment state and shipping method specs", "Pack By Product"
      end
    end
  end
end

private

def check_prefilled_dates
  expect(page).to have_input "q[order_completed_at_gt]", value: open_datetime, visible: false
  expect(page).to have_input "q[order_completed_at_lt]", value: close_datetime, visible: false
end
