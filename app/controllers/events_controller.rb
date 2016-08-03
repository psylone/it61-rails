# frozen_string_literal: true
class EventsController < ApplicationController
  respond_to :html
  respond_to :json
  respond_to :ics, only: :show
  respond_to :rss, only: :index

  before_action :authenticate_user!, except: [:index, :show, :upcoming, :past]
  before_action :set_event, only: [:show, :participate, :register, :revoke_participation]

  authorize_resource

  def index
    redirect_to_relevant_scope
  end

  def upcoming
    show_events(:upcoming)
  end

  def past
    show_events(:past)
  end

  def show
  end

  def new
    @event ||= Event.new
  end

  def create
    event_creator = EventCreator.new
    @event = event_creator.create params, current_user

    if @event.persisted?
      flash[:success] = t("flashes.event_successfully_created")
      redirect_to event_path(@event)
    else
      flash[:errors] = @event.errors.messages
      render "new"
    end
  end

  def edit
  end

  def destroy
  end

  def participate
    if @event.opened? || @event.past?
      @event.register_user!(current_user)
    end
    redirect_to event_path(@event)
  end

  def register
    # there is no business if event have open registration
    unless @event.closed? || @event.user_participated?(current_user)
      return redirect_to @event
    end

    # if user already have some entry form for this event...
    @entry_form = @event.entry_form_for(current_user)
    save_entry_form if request.post?
  end

  def revoke_participation
    participation = @event.participation_for(current_user)
    EventParticipation.destroy(participation) unless participation.blank?
    redirect_to event_path(@event)
  end

  def publish
    @event = Event.find(params[:id])
    @event.publish!
  end

  def unpublish
  end

  def add_to_google_calendar
    refresh_token = current_user.google_refresh_token
    service = GoogleService.new
    event = Event.find params[:id]

    @result = service.add_event_to_calendar refresh_token, event

    if @result && @result.status == 200
      redirect_to event_path(event), notice: t("flashes.event_successfully_added_to_google_calendar")
    else
      redirect_to event_path(event), error: t("flashes.event_failure_to_add_to_google_calendar")
    end
  end

  def download_ics_file
    event = Event.find params[:id]
    ics_service = IcsService.new
    event_url = event_url(event)
    calendar = ics_service.to_ics_calendar event, event_url

    send_data calendar.to_ical, filename: "#{event.title}.ics", type: "application/ics"
  end

  private

  def set_event
    @event = Event.find(params[:id])
  end

  def save_entry_form
    # save entry form
    @entry_form.event = @event
    @entry_form.user = current_user
    @entry_form.update(entry_form_params)
    @entry_form.save

    # mark user as participant
    @event.register_user!(current_user)
    redirect_to @event
  end

  def entry_form_params
    params.require(:entry_form).permit("reason", "profession", "suggestions", "confidence")
  end

  def show_events(scope)
    @events = Event.send(scope).published.paginate(page: params[:page], per_page: 6)
    @scope = scope

    # TODO: Вынести верстку "events/index" в отдельный layout
    view = request.xhr? ? "events/_cards" : "events/index"
    respond_with @events do |f|
      f.html { render view, layout: !request.xhr? }
    end
  end

  def redirect_to_relevant_scope
    path = Event.published.upcoming.count > 0 ? upcoming_events_path : past_events_path
    redirect_to path
  end

  def parse_date_time(event_params)
    Time.new(event_params["started_at_date(1i)"].to_i, event_params["started_at_date(2i)"].to_i, event_params["started_at_date(3i)"].to_i,
             event_params["started_at_time(4i)"].to_i, event_params["started_at_time(5i)"].to_i, event_params["started_at_time(6i)"].to_i)
  end

  def show_correct_scope
    path = Event.published.upcoming.count > 0 ? upcoming_events_path : past_events_path
    redirect_to path
  end

end
