class StripeCheckoutSessionService
  def call(event)
    session = Session.find_by(checkout_session_id: event.data.object.id)
    session.update!(status: 'pending', paid: true)
    Notification.create(recipient: session.practitioner.user, actor: current_user, action: 'sent you a session request', notifiable: session)
  end
end
