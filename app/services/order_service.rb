module OrderService
  def self.create!(user_id:, partner_id:, currency_code:, line_items: [])
    raise Errors::OrderError, 'Currency not supported' unless valid_currency_code?(currency_code)
    Order.transaction do
      order = Order.create!(user_id: user_id, partner_id: partner_id, currency_code: currency_code, state: Order::PENDING)
      line_items.each { |li| LineItemService.create!(order, li) }
      order
    end
  end

  def self.set_payment!(order, credit_card_id:, merchant_account_id:)
    raise Errors::OrderError, 'Cannot set payment info on non-pending orders' unless order.state == Order::PENDING
    Order.transaction do
      order.update!(credit_card_id: credit_card_id, merchant_account_id: merchant_account_id)
    end
    order
  end

  def self.set_shipping!(order, attributes)
    raise Errors::OrderError, 'Cannot set shipping info on non-pending orders' unless order.state == Order::PENDING
    Order.transaction do
      order.update!(
        attributes.slice(
          :shipping_address_line1,
          :shipping_address_line2,
          :shipping_city,
          :shipping_country,
          :shipping_postal_code,
          :fulfillment_type
        )
      )
    end
    order
  end

  def self.submit!(order)
    raise Errors::OrderError, "Missing info for submitting order(#{order.id})" unless can_submit?(order)
    Order.transaction do
      # verify price change?
      # TODO: hold the charge for this price on credit card
      order.submit!
      charge = PaymentService.authorize_charge(order, order.items_total_cents)
      TransactionService.create_success!(order, charge)
      order.save!
    end
    order
  rescue Errors::PaymentError => e
    TransactionService.create_failure!(order, e.body)
    raise e
  end

  def self.approve!(order)
    Order.transaction do
      order.approve!
      order.save!
      # TODO: process the charge by calling gravity with current credit_card_id and price
    end
    order
  end

  def self.finalize!(order)
    Order.transaction do
      order.finalize!
      order.save!
      # TODO: process the charge by calling gravity with current credit_card_id and price
    end
    order
  end

  def self.reject!(order)
    Order.transaction do
      order.reject!
      order.save!
      # TODO: release the charge
    end
    order
  end

  def self.abandon!(order)
    Order.transaction do
      order.abandon!
      order.save!
    end
  end

  def self.valid_currency_code?(currency_code)
    currency_code == 'usd'
  end

  def self.can_submit?(order)
    order.shipping_info? && order.payment_info?
  end
end
