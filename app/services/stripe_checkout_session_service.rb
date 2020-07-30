class StripeCheckoutSessionService
  def call(event)
    session = Session.find_by(checkout_session_id: event.data.object.id)
    session.update!(status: 'paid', paid: true)
  end
end