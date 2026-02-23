class ImportTransactionService
  include ImportConfig

  attr_reader :import, :errors, :results

  def initialize(import)
    @import = import
    @errors = []
    @results = { properties_created: [], units_created: [] }
  end

  # ==================================================
  # MAIN EXECUTION FLOW
  # ==================================================

  # Purpose: Executes the actual import of verified properties & units into the database
  # Steps:
  #   1. Ensure import is in previewed state (safety check)
  #   2. Begin database transaction
  #   3. Create all new properties first (they're needed for units)
  #   4. Mark existing property rows as imported
  #   5. Create all units (linked to properties)
  #   6. Update import record with results and timestamps
  #   7. Handle any errors with rollback
  def execute
    return false unless import.previewed?

    ActiveRecord::Base.transaction do
      begin
        # Track property mapping between import rows and created properties
        property_mapping = {}

        create_new_properties(property_mapping)
        mark_existing_properties_imported
        create_units(property_mapping)
        update_import_record

        true
      rescue => e
        @errors << e.message
        import.update!(status: :failed, error_summary: { errors: @errors, results: @results })
        raise ActiveRecord::Rollback
      end
    end
  end

  private

    # ==================================================
    # PROPERTY CREATION
    # ==================================================

    # Purpose: Creates new property records in the database from verified import rows
    # Steps:
    #   1. Find all verified property rows that don't link to existing properties
    #   2. For each row, create a new Property record
    #   3. Store mapping between building name and created property (for unit linking)
    #   4. Update row status to imported and store reference to created property
    #   5. Track created property IDs in results
    def create_new_properties(property_mapping)
      import.property_rows
          .verified
          .where(existing_property_id: nil)
          .find_each do |row|
        property = create_property_from_row(row)
        property_mapping[row.building_name] = property
        row.update!(created_property: property, status: :imported)
        @results[:properties_created] << property.id
      end
    end

    # Purpose: Creates a single property record from an import row's parsed data
    # Steps:
    #   1. Extract parsed data from row
    #   2. Determine property type based on associated units
    #   3. Create and return new Property record
    def create_property_from_row(row)
      data = row.parsed_data

      Property.create!(
        building_name: data[ParsedKeys::BUILDING_NAME],
        property_type: determine_property_type(row),
        street_address: data[ParsedKeys::STREET_ADDRESS],
        city: data[ParsedKeys::CITY],
        state: data[ParsedKeys::STATE],
        zip_code: data[ParsedKeys::ZIP_CODE]
      )
    end

    # Purpose: Determines if a property is multi-family or single-family
    # Steps:
    #   1. Count verified unit rows associated with this building
    #   2. Return "multi_family" if units exist, otherwise "single_family"
    def determine_property_type(row)
      unit_count = import.property_import_rows
        .where(record_type: :unit, status: :verified)
        .where("parsed_data->>'building_name' = ?", row.parsed_data[ParsedKeys::BUILDING_NAME])
        .count

      unit_count > 0 ? "multi_family" : "single_family"
    end

    # ==================================================
    # EXISTING PROPERTY HANDLING
    # ==================================================

    # Purpose: Marks verified property rows that link to existing database properties as imported
    # Steps:
    #   1. Find all verified property rows that already have existing_property_id
    #   2. Bulk update their status to imported (no new property created)
    def mark_existing_properties_imported
      import.property_import_rows
          .where(record_type: :property, status: :verified)
          .where.not(existing_property_id: nil)
          .update_all(status: :imported)
    end

    # ==================================================
    # UNIT CREATION
    # ==================================================

    # Purpose: Creates all unit records from verified unit import rows
    # Steps:
    #   1. Find all verified unit rows
    #   2. For each row, create a Unit record linked to its property
    #   3. Update row status to imported
    #   4. Track created unit IDs in results
    def create_units(property_mapping)
      import.property_import_rows
          .where(record_type: :unit, status: :verified)
          .find_each do |row|
        unit = create_unit_from_row(row, property_mapping)
        row.update!(status: :imported)
        @results[:units_created] << unit.id
      end
    end

    # Purpose: Creates a single unit record from an import row
    # Steps:
    #   1. Extract parsed data from row
    #   2. Find the associated property (from mapping, database, or row reference)
    #   3. Create and return new Unit record
    def create_unit_from_row(row, property_mapping)
      data = row.parsed_data
      building_name = data[ParsedKeys::BUILDING_NAME]

      property = find_property_for_unit(building_name, property_mapping, row)

      Unit.create!(
        property: property,
        unit_number: data[ParsedKeys::UNIT_NUMBER]
      )
    end

    # Purpose: Locates the correct property for a unit being imported
    # Priority order:
    #   1. Check property_mapping (newly created properties in this transaction)
    #   2. Search database by building name
    #   3. Use row.existing_property (fallback)
    def find_property_for_unit(building_name, property_mapping, row)
      property_mapping[building_name] ||
      Property.find_by(building_name: building_name) ||
      row.existing_property
    end

    # ==================================================
    # IMPORT RECORD FINALIZATION
    # ==================================================

    # Purpose: Updates the main import record with completion data
    # Steps:
    #   1. Set status to imported
    #   2. Record timestamp
    #   3. Store counts of created properties and units
    #   4. Merge results into existing summary
    def update_import_record
      import.update!(
        status: :imported,
        imported_at: Time.current,
        properties_created_count: @results[:properties_created].size,
        units_created_count: @results[:units_created].size,
        summary: import.summary.merge(import_results: @results)
      )
    end
end
