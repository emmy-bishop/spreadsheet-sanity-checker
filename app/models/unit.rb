class Unit < ApplicationRecord
  belongs_to :property

  # VALIDATION
  validates :unit_number, presence: true, uniqueness: { scope: :property_id }

  # METHODS
  def full_name
    unit_number.present? ? "#{property.building_name} - Unit #{unit_number}" : property.building_name
  end
end
