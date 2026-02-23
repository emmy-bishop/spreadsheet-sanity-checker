class Property < ApplicationRecord
  has_many :units, dependent: :destroy

  enum :property_type, {
    single_family: "single_family",
    multi_family: "multi_family"
  }, validate: true

  # VALIDATION
  validates :building_name, presence: true, uniqueness: true
  validates :street_address, :city, :state, :zip_code, presence: true
  validates :street_address, uniqueness: {
    scope: [ :city, :state, :zip_code ],
    message: "must be unique within the same city, state, and zip code"
  }

  # This list of US states is not the most sophisticated,
  # but our use case is simple, so we can keep it self-contained for max control
  # e.g. we choose exactly what to include, there are no external dependencies to install/maintain,
  # and no worry about data changing unexpectedly in future updates
  US_STATES = [
    "Alabama", "Alaska", "Arizona", "Arkansas", "California", "Colorado", "Connecticut", "Delaware", "Florida", "Georgia", "Hawaii", "Idaho", "Illinois", "Indiana", "Iowa", "Kansas", "Kentucky", "Louisiana", "Maine", "Maryland", "Massachusetts", "Michigan", "Minnesota", "Mississippi", "Missouri", "Montana", "Nebraska", "Nevada", "New Hampshire", "New Jersey", "New Mexico", "New York", "North Carolina", "North Dakota", "Ohio", "Oklahoma", "Oregon", "Pennsylvania", "Rhode Island", "South Carolina", "South Dakota", "Tennessee", "Texas", "Utah", "Vermont", "Virginia", "Washington", "West Virginia", "Wisconsin", "Wyoming", "District of Columbia"
  ].freeze

  STATE_LOOKUP = US_STATES.index_by(&:upcase).freeze

  validates :state, inclusion: { in: US_STATES, message: "%{value} is not a valid US state" }

  before_validation :clean_state_name

  # METHODS
  def display_name
    building_name
  end

  def full_address
    "#{street_address}, #{city}, #{state} #{zip_code}"
  end

  private

  # Normalize state name to cover inconsequential typos and capitalization differences we don't want to bother the user with fixing
  def clean_state_name
    # If no value at all, reject immediately
    return if state.blank?
    # Remove leading/trailing whitespace, non-letter/whitespace chars, and multiple consecutive spaces
    # Convert to uppercase so we can match it against our defined state names
    cleaned = state.strip.delete("^a-zA-Z\s").squish.upcase
    self.state = STATE_LOOKUP[cleaned] # ex. " washington" --> "Washington"
  end
end
