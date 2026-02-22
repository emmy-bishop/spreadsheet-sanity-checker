class PropertyImport < ApplicationRecord
  has_many :property_import_rows, dependent: :destroy

  enum :status, {
    pending: "pending",
    previewed: "previewed",
    imported: "imported",
    failed: "failed"
  }, default: :pending, validate: true

  # VALIDATION
  validates :filename, presence: true

  # SCOPES
  scope :recent, -> { order(created_at: :desc) }

  # METHODS
  def property_rows # Rows representing unique buildings (set in FileImportService/create_import_rows())
    property_import_rows.properties
  end

  def unit_rows # Rows representing unique units (set in FileImportService/create_import_rows())
    property_import_rows.units
  end

  def verified_rows # Rows that have been validated and look ok
    property_import_rows.verified
  end

  def rejected_rows # Rows with issues -- import will be blocked if these are present
    property_import_rows.rejected
  end

  def total_property_rows
    property_rows.count
  end

  def total_unit_rows
    unit_rows.count
  end

  def summary_stats
    {
      total_rows: property_import_rows.count,
      by_status: property_import_rows.group(:status).count,
      by_record_type: property_import_rows.group(:record_type).count,
      properties: total_property_rows,
      units: total_unit_rows,
      verified_rows: verified_rows.count,
      rejected_rows: rejected_rows.count,
      new_properties: property_rows.where(status: :verified, existing_property_id: nil).count,
      existing_properties: property_rows.where(status: :verified).where.not(existing_property_id: nil).count
    }
  end
end
