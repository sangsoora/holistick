class StripeCheckoutSessionService
  def call(event)
    if Practitioner.find_by(checkout_session_id: event.data.object.id)
      @practitioner = Practitioner.find_by(checkout_session_id: event.data.object.id)
      @practitioner.update!(payment_status: 'paid')
      PractitionerMailer.with(practitioner: @practitioner).welcome.deliver_now
      AdminMailer.with(practitioner: @practitioner).new_practitioner.deliver_now
    elsif Session.find_by(checkout_session_id: event.data.object.id)
      @session = Session.find_by(checkout_session_id: event.data.object.id)
      @session.update!(status: 'pending', paid: true)
      SessionMailer.with(session: @session).send_request.deliver_now
      Notification.create(recipient: @session.practitioner.user, actor: current_user, action: 'sent you a session request', notifiable: @session)
    end
  end
end
