class PropertyImportRow < ApplicationRecord
  belongs_to :property_import
  belongs_to :existing_property, class_name: "Property", optional: true
  belongs_to :created_property, class_name: "Property", optional: true

  enum :status, {
    pending: "pending",
    verified: "verified",
    rejected: "rejected",
    imported: "imported"
  }, validate: true

  enum :record_type, {
    property: "property",
    unit: "unit"
  }, validate: true

  # SCOPES
  scope :properties, -> { where(record_type: "property") }
  scope :units, -> { where(record_type: "unit") }
  scope :verified, -> { where(status: "verified") }
  scope :rejected, -> { where(status: "rejected") }
  scope :pending, -> { where(status: "pending") }

  # METHODS
  def original_row_number
    original_data&.[]("_original_row")
  end

  def building_name
    parsed_data&.fetch("building_name", nil)
  end

  def unit_number
    parsed_data&.fetch("unit_number", nil)
  end

  def street_address
    parsed_data&.fetch("street_address", nil)
  end

  def city
    parsed_data&.fetch("city", nil)
  end

  def state
    parsed_data&.fetch("state", nil)
  end

  def zip_code
    parsed_data&.fetch("zip_code", nil)
  end

  def update_status_and_errors(errors)
    if errors.any?
      update(
        status: :rejected,
        validation_errors: errors.join("; ")
      )
    else
      update(
        status: :verified,
        validation_errors: nil
      )
    end
  end

  def has_errors?
    validation_errors.present?
  end

  def error_list
    return [] if validation_errors.blank?
    validation_errors.to_s.split("; ").map(&:strip)
  end

  def verified?
    status == "verified"
  end

  def rejected?
    status == "rejected"
  end

  def pending?
    status == "pending"
  end

  def imported?
    status == "imported"
  end

  def property?
    record_type == "property"
  end

  def unit?
    record_type == "unit"
  end
end
