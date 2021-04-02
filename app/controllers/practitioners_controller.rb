class PractitionersController < ApplicationController
  skip_before_action :authenticate_user!, only: %i[index show filter]
  before_action :set_practitioner, only: %i[show update destroy discovery_call]
  before_action :set_notifications, only: %i[index show new profile service booking discovery_call]

  def index
    @practitioners = policy_scope(Practitioner)
  end

  def show
    @conversation = Conversation.new
  end

  def new
    @practitioner = Practitioner.new
    authorize @practitioner
    @practitioner.user = User.find(params[:user_id])
  end

  def create
    @practitioner = Practitioner.new(practitioner_params)
    authorize @practitioner
    @practitioner.user = User.find(params[:user_id])
    languages = params[:practitioner][:language_ids].reject(&:blank?)
    specialties = params[:practitioner][:specialty_ids].reject(&:blank?)
    if @practitioner.save
      languages.each { |language| PractitionerLanguage.create!(practitioner: @practitioner, language: Language.find(language)) }
      specialties.each { |specialty| PractitionerSpecialty.create!(practitioner: @practitioner, specialty: Specialty.find(specialty)) }
      (0..6).each { |day| WorkingHour.create!(day: day, practitioner: @practitioner, opens: '', closes: '') }
      respond_to do |format|
        format.html { redirect_to root_path }
        format.js
      end
      # redirect_to root_path, notice: 'Your application has been received'
    else
      render :new
    end
  end

  def filter
    @practitioners = Practitioner.checked_practitioners.left_outer_joins(:user).where("(first_name ILIKE :search) or (last_name ILIKE :search) or (first_name || ' ' || last_name ILIKE :search)", search: "%#{params[:query]}%")
    authorize @practitioners
  end

  def profile
    @practitioner = current_user.practitioner
    authorize @practitioner
    @columns = %w[title specialties languages certifications memberships country experience bio approach video address healthgoals timezone city name phone]
    @workingdays = %w[Mon Tue Wed Thu Fri Sat Sun]
    @specialties = Specialty.all.sort_by(&:name)
    @languages = Language.all.sort_by(&:name)
    @health_goals = HealthGoal.all.sort_by(&:name)
    @practitioner_specialty = PractitionerSpecialty.new
    @practitioner_language = PractitionerLanguage.new
    @practitioner_social_link = PractitionerSocialLink.new
    @practitioner_certification = PractitionerCertification.new
    @practitioner_membership = PractitionerMembership.new
    @health_goal = UserHealthGoal.new
    @newsletter = Newsletter.find_by(email: @practitioner.user.email) if @practitioner.user.newsletter
    @user = @practitioner.user
    @working_hours = @practitioner.working_hours
  end

  def service
    @practitioner = current_user.practitioner
    authorize @practitioner
    @services = @practitioner.services.includes(:sessions, :specialty, :practitioner)
    @active_serivces = @practitioner.services.where(active: true).includes(:sessions, :specialty, :practitioner)
    @deactivated_serivces = @practitioner.services.where(active: false).includes(:sessions, :specialty, :practitioner)
    @service = Service.new
  end

  def booking
    @practitioner = current_user.practitioner
    authorize @practitioner
    @confirmed_sessions = @practitioner.sessions.includes(:review, service: [practitioner: [{ user: :photo_attachment }]]).where(['status= ?', 'confirmed']).order('start_time DESC')
    @pending_sessions = @practitioner.sessions.includes(:review, service: [practitioner: [{ user: :photo_attachment }]]).where(['paid = ? AND status= ?', true, 'pending']).order('created_at DESC')
    @cancelled_sessions = @practitioner.sessions.includes(:review, service: [practitioner: [{ user: :photo_attachment }]]).where(['status= ?', 'cancelled']).order('start_time DESC')
    @discovery_calls = Session.where(free_practitioner_id: @practitioner).includes(:review, :service)
  end

  def discovery_call
    @session = Session.new
    @service = Service.first
    @times = ['00:00', '00:30', '01:00', '01:30', '02:00', '02:30', '03:00', '03:30', '04:00', '04:30', '05:00', '05:30', '06:00', '06:30', '07:00', '07:30', '08:00', '08:30', '09:00', '09:30', '10:00', '10:30', '11:00', '11:30', '12:00', '12:30', '13:00', '13:30', '14:00', '14:30', '15:00', '15:30', '16:00', '16:30', '17:00', '17:30', '18:00', '18:30', '19:00', '19:30', '20:00', '20:30', '21:00', '21:30', '22:00', '22:30', '23:00', '23:30']
  end

  def update
    if params[:commit] == 'Proceed To Payment'
      if (params[:practitioner][:agreement_consent][1]) && (params[:practitioner][:background_check_consent][1]) && @practitioner.update(background_check_consent: true, agreement_consent: true, amount_cents: 3500)
        payment_session = Stripe::Checkout::Session.create(
          billing_address_collection: 'required',
          payment_method_types: ['card'],
          line_items: [{
            name: 'Practitioner Onboarding Fee',
            amount: 3500,
            currency: 'cad',
            quantity: 1
          }],
          success_url: practitioner_profile_url,
          cancel_url: practitioner_profile_url
        )
        @practitioner.update(checkout_session_id: payment_session.id)
        redirect_to new_practitioner_practitioner_payment_path(@practitioner)
      else
        redirect_to practitioner_profile_path
      end
    elsif params[:commit] == 'Delete Banner Image'
      @practitioner.banner_image.purge
      flash[:notice] = 'Your banner image has been deleted.'
      redirect_to practitioner_profile_path
    # elsif params[:commit] == 'Set Up Payouts'
    #   unless @practitioner.stripe_account_id
    #     account = Stripe::Account.create({
    #       email: "#{@practitioner.user.email}",
    #       country: "#{@practitioner.country_code}",
    #       type: 'express'
    #     })
    #     @practitioner.update(stripe_account_id: account[:id])
    #     account_links = Stripe::AccountLink.create({
    #       account: "#{@practitioner.stripe_account_id}",
    #       refresh_url: 'http://localhost:3000/profile',
    #       return_url: 'http://localhost:3000/profile',
    #       type: 'account_onboarding'
    #     })
    #     redirect_to "#{account_links[:url]}"
    #   end
    # elsif params[:commit] == 'Payouts Dashboard'
    #   link = Stripe::Account.create_login_link(@practitioner.stripe_account_id)
    #   redirect_to "#{link[:url]}"
    else
      if @practitioner.update(practitioner_params)
        if params[:commit] == 'Upload' && params[:practitioner][:banner_image]
          flash[:notice] = 'Your banner image has been uploaded.'
        end
        if @practitioner.video && !@practitioner.video.start_with?('http://', 'https://')
          @practitioner.update(video: 'http://' + @practitioner.video)
        end
        @practitioner.update(latitude: nil, longitude: nil) unless @practitioner.address?
        @param = practitioner_params
        respond_to do |format|
          format.html { redirect_to practitioner_profile_path }
          format.js
        end
      end
    end
  end

  def destroy
    @practitioner.destroy
    redirect_to root_path
  end

  private

  def set_practitioner
    @practitioner = Practitioner.find(params[:id].split('_').last.to_i)
    authorize @practitioner
  end

  def set_notifications
    @notifications = Notification.includes(:actor).where(recipient: current_user).order("created_at DESC").unread
  end

  def practitioner_params
    params.require(:practitioner).permit(:title, :location, :address, :address_type, :bio, :approach, :video, :latitude, :longitude, :experience, :timezone, :country_code, :state, :checkout_session_id, :amount, :payment_status, :agreement_consent, :agreement_status, :status, :background_check_status, :background_check_consent, :background_check_id, :insurance, :banner_image, :specialty_ids, :language_ids)
  end
end
